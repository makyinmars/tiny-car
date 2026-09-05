//! Versioned, deterministic simulation. No rendering, clock, audio, or browser dependencies.
const std = @import("std");
pub const road = @import("road.zig");

pub const version = 3;
pub const hz = 60;
pub const duration_ticks = 90 * hz;
pub const dt: f32 = 1.0 / @as(f32, hz);
pub const car_width = road.car_width;
pub const car_height = road.car_height;
pub const signal_ticks = 60;
pub const merge_ticks = 120;
pub const following_gap: f32 = 26;
pub const State = enum(u32) { ready, countdown, playing, paused, finished };
pub const Input = packed struct(u8) {
    left: bool = false,
    right: bool = false,
    accelerate: bool = false,
    brake: bool = false,
    padding: u4 = 0,
};

test "a stopped car cannot slide sideways" {
    var race = Race.start(1);
    race.state = .playing;
    race.speed = 0;
    const x = race.x;
    for (0..60) |_| race.step(.{ .right = true, .brake = true });
    try std.testing.expectApproxEqAbs(x, race.x, 0.01);
}
pub const Traffic = struct {
    active: bool = false,
    x: f32 = 0,
    y: f32 = -100,
    speed: f32 = 0,
    cruise: f32 = 180,
    sprite: u32 = 0,
    lane: u32 = 0,
    target_lane: u32 = 0,
    signal: u32 = 0,
    merge: u32 = 0,
    next_decision: u32 = 0,
    preference: i32 = 1,
    heading: f32 = 0,
    braking: bool = false,
    passed: bool = false,
    collided: bool = false,
    closest: f32 = std.math.inf(f32),

    pub fn occupies(self: Traffic, lane: u32) bool {
        return self.lane == lane or self.target_lane == lane;
    }

    pub fn body(self: Traffic) road.Body {
        return .{ .x = self.x, .y = self.y, .heading = self.heading };
    }
};

pub const Race = struct {
    state: State = .ready,
    resume_state: State = .playing,
    seed: u32 = 1,
    rng: u32 = 1,
    ticks: u32 = 0,
    countdown: u32 = 180,
    next_spawn: u32 = 0,
    spawned: u32 = 0,
    x: f32 = road.laneX(1),
    y: f32 = 450,
    speed: f32 = 30,
    acceleration: f32 = 0,
    lateral_velocity: f32 = 0,
    heading: f32 = 0,
    braking: bool = false,
    distance: f32 = 0,
    score: u32 = 0,
    overtakes: u32 = 0,
    near_misses: u32 = 0,
    crashes: u32 = 0,
    streak: u32 = 0,
    best_streak: u32 = 0,
    base_points: u32 = 0,
    near_points: u32 = 0,
    speed_points: u32 = 0,
    clean_points: u32 = 0,
    invulnerable: u32 = 0,
    last_award: u32 = 0,
    award_ticks: u32 = 0,
    traffic: [24]Traffic = @splat(.{}),

    pub fn start(seed: u32) Race {
        return .{ .state = .countdown, .seed = seed, .rng = if (seed == 0) 1 else seed };
    }

    pub fn pause(self: *Race) void {
        if (self.state == .playing or self.state == .countdown) {
            self.resume_state = self.state;
            self.state = .paused;
        }
    }

    pub fn resumeRace(self: *Race) void {
        if (self.state == .paused) self.state = self.resume_state;
    }

    pub fn multiplier(self: *const Race) u32 {
        return 1 + @min(self.streak / 5, 4);
    }

    fn random(self: *Race) u32 {
        var x = self.rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.rng = x;
        return x;
    }

    fn spawn(self: *Race) void {
        // Always consume the same random values at the same tick, even if all slots are busy.
        const lane = self.random() % road.lane_count;
        const speed = 125 + self.random() % 91;
        const style = self.random();
        self.spawned += 1;
        // A blocked entrance skips the attempt, without rerolling or changing the schedule.
        for (self.traffic) |car| {
            if (car.active and car.occupies(lane) and @abs(car.y + 100) < car_height + following_gap + 90) return;
        }
        for (&self.traffic) |*car| {
            if (!car.active) {
                car.* = .{
                    .active = true,
                    .x = road.laneX(lane),
                    .speed = @floatFromInt(speed),
                    .cruise = @floatFromInt(speed),
                    .sprite = 1 + style % 5,
                    .lane = lane,
                    .target_lane = lane,
                    .next_decision = self.ticks + 45 + style % 120,
                    .preference = if (style & 8 == 0) -1 else 1,
                };
                return;
            }
        }
    }

    pub fn body(self: *const Race) road.Body {
        return .{ .x = self.x, .y = self.y, .heading = self.heading };
    }

    pub fn groundSpeed(self: *const Race) f32 {
        return self.speed * road.pixels_per_mph;
    }

    fn laneSafe(self: *const Race, index: usize, lane: u32) bool {
        const car = self.traffic[index];
        for (self.traffic, 0..) |other, j| {
            if (j == index or !other.active or !other.occupies(lane)) continue;
            const closing = if (other.y < car.y) car.speed - other.speed else other.speed - car.speed;
            // Reserve space for the entire signal + merge, not just the current gap.
            if (@abs(other.y - car.y) < car_height + following_gap + @max(0, closing) * 3) return false;
        }
        const target_x = road.laneX(lane);
        if (self.x + car_width > target_x - 18 and self.x < target_x + car_width + 18) {
            const closing = if (self.y < car.y) car.speed - self.groundSpeed() else self.groundSpeed() - car.speed;
            if (@abs(self.y - car.y) < car_height + 50 + @max(0, closing) * 3) return false;
        }
        return true;
    }

    fn updateTraffic(self: *Race) void {
        // Snapshot velocities/positions so following does not depend on pool slot order.
        const before = self.traffic;
        for (&self.traffic, 0..) |*car, i| {
            if (!car.active) continue;
            var target = car.cruise;
            var bumper_gap: f32 = std.math.inf(f32);
            var lead_speed = car.cruise;
            for (before, 0..) |other, j| {
                if (i == j or !other.active or other.y >= car.y) continue;
                if (!other.occupies(car.lane) and !other.occupies(car.target_lane)) continue;
                const gap = car.y - other.y - car_height;
                if (gap < bumper_gap) {
                    bumper_gap = gap;
                    lead_speed = other.speed;
                }
            }
            if (self.y < car.y and @abs(self.x - car.x) < car_width + 8) {
                const gap = car.y - self.y - car_height;
                if (gap < bumper_gap) {
                    bumper_gap = gap;
                    lead_speed = self.groundSpeed();
                }
            }
            const desired_gap = following_gap + car.speed * 0.45;
            if (bumper_gap < desired_gap + 100) target = @min(target, @max(0, lead_speed + (bumper_gap - desired_gap) * 1.5));
            car.speed = approach(car.speed, target, (if (target < car.speed) @as(f32, 220) else 55) * dt);
            car.braking = target < before[i].speed - 4;

            if (car.lane == car.target_lane and self.ticks >= car.next_decision) {
                car.next_decision = self.ticks + 300 + @as(u32, @intCast(i)) * 7;
                // Most changes are overtakes; a minority are route preferences.
                const wants_change = bumper_gap < desired_gap + 85 or (self.ticks / 300 + i) % 3 == 0;
                if (wants_change) {
                    var target_lane = @as(i32, @intCast(car.lane)) + car.preference;
                    if (target_lane < 0 or target_lane >= road.lane_count) target_lane = @as(i32, @intCast(car.lane)) - car.preference;
                    if (self.laneSafe(i, @intCast(target_lane))) {
                        car.target_lane = @intCast(target_lane);
                        car.signal = signal_ticks;
                        car.merge = 0;
                    }
                    car.preference = -car.preference;
                }
            }
            const previous_x = car.x;
            if (car.lane != car.target_lane) {
                if (car.signal > 0) {
                    car.signal -= 1;
                    if (car.signal == 0 and !self.laneSafe(i, car.target_lane)) {
                        car.target_lane = car.lane;
                        car.next_decision = self.ticks + 180;
                    }
                } else {
                    // Recheck the player's swept corridor every tick. Yield laterally
                    // if a driver enters the reserved space; never snap across a car.
                    const target_x = road.laneX(car.target_lane);
                    const player_near = @abs(self.y - car.y) < car_height + 36 and
                        self.x + car_width > @min(car.x, target_x) - 10 and
                        self.x < @max(car.x, target_x) + car_width + 10;
                    if (!player_near) car.merge += 1;
                    const progress = @as(f32, @floatFromInt(car.merge)) / merge_ticks;
                    const eased = progress * progress * (3 - 2 * progress);
                    car.x = road.laneX(car.lane) + (target_x - road.laneX(car.lane)) * eased;
                    if (car.merge >= merge_ticks) {
                        car.lane = car.target_lane;
                        car.merge = 0;
                    }
                }
            }
            const vx = (car.x - previous_x) / dt;
            car.heading = approach(car.heading, std.math.clamp(std.math.atan2(vx, @max(car.speed, 30)), -road.max_heading, road.max_heading), 0.9 * dt);
            // Hard following floor handles sudden stops, while ordinary following
            // above uses smooth deceleration. A cut-in can start inside this floor;
            // don't teleport backward to repair it.
            if (bumper_gap >= following_gap)
                car.speed = @min(car.speed, @max(0, lead_speed + (bumper_gap - following_gap) / dt));
            car.y += (self.groundSpeed() - car.speed) * dt;
        }
    }

    pub fn award(self: *Race, car: *Traffic) void {
        if (car.passed or car.collided) return;
        car.passed = true;
        const near: u32 = if (car.closest <= 12) 30 else 0;
        const speed_bonus: u32 = if (self.speed >= 80) 40 else if (self.speed >= 60) 20 else 0;
        const raw = 50 + near + speed_bonus;
        const clean = raw * (self.multiplier() - 1);
        self.base_points += 50;
        self.near_points += near;
        self.speed_points += speed_bonus;
        self.clean_points += clean;
        self.last_award = raw + clean;
        self.award_ticks = 60;
        self.score += self.last_award;
        self.overtakes += 1;
        if (near > 0) self.near_misses += 1;
        self.streak += 1;
        self.best_streak = @max(self.best_streak, self.streak);
    }

    pub fn step(self: *Race, input: Input) void {
        if (self.state == .countdown) {
            self.countdown -= 1;
            if (self.countdown == 0) self.state = .playing;
            return;
        }
        if (self.state != .playing) return;
        // Gentle automatic cruise keeps one-thumb/keyboard play approachable.
        // Pedals change forward speed, not screen-space position independently.
        const target: f32 = if (input.brake) 0 else if (input.accelerate) 90 else 42;
        const desired_accel = std.math.clamp((target - self.speed) * 1.8, if (input.brake) @as(f32, -68) else -20, 32);
        self.acceleration = approach(self.acceleration, desired_accel, 140 * dt);
        self.speed = std.math.clamp(self.speed + self.acceleration * dt, 0, 90);
        if (input.brake and self.speed < 0.15) {
            self.speed = 0;
            self.acceleration = 0;
        }
        self.braking = input.brake;
        const horizontal: f32 = @as(f32, @floatFromInt(@intFromBool(input.right))) - @as(f32, @floatFromInt(@intFromBool(input.left)));
        self.lateral_velocity += (horizontal * self.speed * 1.6 - self.lateral_velocity) * 7 * dt;
        if (self.speed == 0) self.lateral_velocity = 0;
        self.x = std.math.clamp(self.x + self.lateral_velocity * dt, road.min_x, road.max_x);
        if (self.x == road.min_x or self.x == road.max_x) self.lateral_velocity = 0;
        const target_heading = std.math.clamp(std.math.atan2(self.lateral_velocity, @max(self.groundSpeed(), 1)), -road.max_heading, road.max_heading);
        self.heading += (target_heading - self.heading) * 10 * dt;
        // Camera framing gives more look-ahead at speed; it never teleports a car.
        self.y += (430 + self.speed * 0.65 - self.y) * 1.5 * dt;
        if (road.onShoulder(self.x)) self.speed = @max(0, self.speed - 22 * dt);
        self.distance += self.groundSpeed() * dt;
        if (self.invulnerable > 0) self.invulnerable -= 1;
        if (self.award_ticks > 0) self.award_ticks -= 1;
        if (self.ticks >= self.next_spawn) {
            self.spawn();
            // 1.1s between cars at the start; 0.55s toward the finish.
            self.next_spawn = self.ticks + 66 - @min(self.ticks / 160, 33);
        }
        self.updateTraffic();
        for (&self.traffic) |*car| {
            if (!car.active) continue;
            const vertical_overlap = @abs(self.y - car.y) < car_height - 8;
            const gap = self.body().gap(car.body());
            if (gap < 0) {
                const first_contact = !car.collided;
                car.collided = true;
                if (first_contact and self.invulnerable == 0) {
                    self.crashes += 1;
                    self.streak = 0;
                    self.speed *= 0.45;
                    self.acceleration = 0;
                    self.lateral_velocity *= 0.4;
                    self.invulnerable = 60;
                }
            }
            if (vertical_overlap) {
                if (gap >= 0) {
                    car.closest = @min(car.closest, gap);
                }
            }
            if (car.y > self.y + car_height) self.award(car);
            if (car.y > 700 or car.y < -180) car.active = false;
        }
        self.ticks += 1;
        if (self.ticks == duration_ticks) self.state = .finished;
    }
};

fn approach(value: f32, target: f32, amount: f32) f32 {
    return value + std.math.clamp(target - value, -amount, amount);
}

/// Accumulate real time and simulate identical 60 Hz steps at any display refresh rate.
pub const Clock = struct {
    accumulator: f64 = 0,
    pub fn advance(self: *Clock, race: *Race, seconds: f64, input: Input) void {
        if (race.state != .countdown and race.state != .playing) {
            self.accumulator = 0;
            return;
        }
        // Treat long stalls as a pause; never silently drop simulation time in a ranked run.
        if (seconds > 0.5) {
            race.pause();
            self.accumulator = 0;
            return;
        }
        self.accumulator += @max(seconds, 0);
        while (self.accumulator + 1e-9 >= 1.0 / @as(f64, hz)) {
            race.step(input);
            self.accumulator -= 1.0 / @as(f64, hz);
        }
    }
};

test "a traffic car awards once and crashed cars never award" {
    var race = Race.start(1);
    var car: Traffic = .{ .closest = 8 };
    race.speed = 90;
    race.award(&car);
    race.award(&car);
    try std.testing.expectEqual(@as(u32, 120), race.score);
    try std.testing.expectEqual(@as(u32, 1), race.near_misses);
    car = .{ .collided = true };
    race.award(&car);
    try std.testing.expectEqual(@as(u32, 1), race.overtakes);
}

test "score accounting and clean multiplier" {
    var race = Race.start(2);
    race.speed = 90;
    for (0..25) |_| {
        var car: Traffic = .{ .closest = 8 };
        race.award(&car);
    }
    try std.testing.expectEqual(@as(u32, 5), race.multiplier());
    try std.testing.expectEqual(race.score, race.base_points + race.near_points + race.speed_points + race.clean_points);
    race.streak = 0;
    try std.testing.expectEqual(@as(u32, 1), race.multiplier());
}

test "30, 60 and 144 Hz render loops finish identical seeded 90 second runs" {
    var expected: ?Race = null;
    for ([_]u32{ 30, 60, 144 }) |fps| {
        var race = Race.start(7321);
        var clock: Clock = .{};
        for (0..93 * fps) |_| clock.advance(&race, 1.0 / @as(f64, @floatFromInt(fps)), .{ .accelerate = true });
        try std.testing.expectEqual(State.finished, race.state);
        try std.testing.expectEqual(@as(u32, 5400), race.ticks);
        if (expected) |other| try std.testing.expectEqualDeep(other, race);
        expected = race;
    }
}

test "pause and countdown do not consume race time; restart restores seed" {
    var race = Race.start(42);
    race.step(.{});
    try std.testing.expectEqual(@as(u32, 0), race.ticks);
    race.pause();
    const saved = race;
    for (0..600) |_| race.step(.{});
    try std.testing.expectEqualDeep(saved, race);
    race.resumeRace();
    try std.testing.expectEqual(State.countdown, race.state);
    race = Race.start(42);
    var replay = Race.start(42);
    for (0..1000) |_| {
        race.step(.{ .left = true, .accelerate = true });
        replay.step(.{ .left = true, .accelerate = true });
    }
    try std.testing.expectEqualDeep(race, replay);
}

test "traffic schedule is independent of input and visual effects" {
    var a = Race.start(17);
    var b = Race.start(17);
    for (0..3000) |_| {
        a.step(.{ .accelerate = true });
        b.step(.{ .brake = true });
    }
    try std.testing.expectEqual(a.rng, b.rng);
    try std.testing.expectEqual(a.spawned, b.spawned);
    try std.testing.expectEqual(a.next_spawn, b.next_spawn);
}

test "steering scales with speed, retains inertia, and settles after release" {
    var slow = Race.start(1);
    slow.state = .playing;
    slow.next_spawn = duration_ticks;
    slow.speed = 12;
    var fast = slow;
    fast.speed = 80;
    const origin = slow.x;
    for (0..20) |_| {
        slow.step(.{ .right = true });
        fast.step(.{ .right = true, .accelerate = true });
    }
    try std.testing.expect(fast.x - origin > (slow.x - origin) * 3);
    const velocity = fast.lateral_velocity;
    const x = fast.x;
    fast.step(.{ .left = true });
    try std.testing.expect(fast.lateral_velocity > 0 and fast.lateral_velocity < velocity);
    try std.testing.expect(fast.x > x);
    for (0..100) |_| fast.step(.{});
    try std.testing.expect(@abs(fast.lateral_velocity) < 0.01);
    try std.testing.expect(@abs(fast.heading) < 0.001);
}

test "pedals ramp smoothly, brake overrides gas, and coasting returns to cruise" {
    var race = Race.start(1);
    race.state = .playing;
    race.next_spawn = duration_ticks;
    race.step(.{ .accelerate = true });
    try std.testing.expect(race.speed > 30 and race.speed < 30.1);
    for (0..300) |_| race.step(.{ .accelerate = true });
    try std.testing.expect(race.speed > 89);
    for (0..300) |_| race.step(.{});
    try std.testing.expectApproxEqAbs(@as(f32, 42), race.speed, 0.2);
    for (0..360) |_| race.step(.{ .accelerate = true, .brake = true, .left = true });
    try std.testing.expectEqual(@as(f32, 0), race.speed);
    try std.testing.expectEqual(@as(f32, 0), race.lateral_velocity);
}

fn fixture(lane: u32, y: f32, speed: f32) Traffic {
    return .{ .active = true, .lane = lane, .target_lane = lane, .x = road.laneX(lane), .y = y, .speed = speed, .cruise = speed, .next_decision = duration_ticks };
}

test "traffic brakes for a slower leader and preserves following gaps" {
    var race = Race.start(1);
    race.speed = 40;
    race.x = road.laneX(2);
    race.traffic[0] = fixture(0, 100, 130);
    race.traffic[1] = fixture(0, 340, 215);
    var braked = false;
    for (0..600) |_| {
        race.updateTraffic();
        braked = braked or race.traffic[1].braking;
        try std.testing.expect(race.traffic[1].y - race.traffic[0].y >= car_height + following_gap - 0.02);
    }
    try std.testing.expect(braked);
    try std.testing.expect(race.traffic[1].speed <= 131);
}

test "traffic reserves a lane, signals for a second, and merges smoothly" {
    var race = Race.start(1);
    race.speed = 40;
    race.x = road.laneX(2);
    race.traffic[0] = fixture(0, 0, 180);
    race.traffic[0].next_decision = 0;
    race.traffic[0].preference = 1;
    for (0..signal_ticks) |_| {
        race.updateTraffic();
        try std.testing.expectEqual(@as(u32, 1), race.traffic[0].target_lane);
        try std.testing.expectEqual(road.laneX(0), race.traffic[0].x);
        race.ticks += 1;
    }
    var prior = race.traffic[0].x;
    for (0..merge_ticks) |_| {
        race.updateTraffic();
        const car = race.traffic[0];
        try std.testing.expect(car.x >= prior and car.x - prior < 1.4);
        try std.testing.expect(@abs(car.heading) <= road.max_heading);
        prior = car.x;
        race.ticks += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), race.traffic[0].lane);
    try std.testing.expectApproxEqAbs(road.laneX(1), race.traffic[0].x, 0.001);
}

test "target lane reservations and fast approaching players block cut-ins" {
    var race = Race.start(1);
    race.speed = 90;
    race.x = road.laneX(1);
    race.y = 450;
    race.traffic[0] = fixture(0, 150, 150);
    try std.testing.expect(!race.laneSafe(0, 1));
    race.x = road.laneX(2);
    try std.testing.expect(race.laneSafe(0, 1));
    race.traffic[1] = fixture(2, 160, 150);
    race.traffic[1].target_lane = 1;
    race.traffic[1].signal = 50;
    try std.testing.expect(!race.laneSafe(0, 1));
}

test "a newly occupied target cancels signaling without snapping sideways" {
    var race = Race.start(1);
    race.speed = 40;
    race.x = road.laneX(1);
    race.y = 250;
    race.traffic[0] = fixture(0, 250, 180);
    race.traffic[0].target_lane = 1;
    race.traffic[0].signal = 1;
    race.updateTraffic();
    try std.testing.expectEqual(@as(u32, 0), race.traffic[0].target_lane);
    try std.testing.expectEqual(road.laneX(0), race.traffic[0].x);
}

test "blocked spawns and a full pool consume the same random stream" {
    var free = Race.start(23);
    var full = free;
    for (&full.traffic, 0..) |*car, i| car.* = fixture(@intCast(i % road.lane_count), 200, 180);
    for (0..40) |_| {
        free.spawn();
        full.spawn();
        try std.testing.expectEqual(free.rng, full.rng);
        try std.testing.expectEqual(free.spawned, full.spawned);
    }
    for (free.traffic) |car| if (car.active) {
        try std.testing.expectEqual(road.laneX(car.lane), car.x);
    };
}

test "frame stalls pause without consuming time, including during countdown" {
    var race = Race.start(3);
    var clock: Clock = .{};
    clock.advance(&race, 0.6, .{ .accelerate = true });
    try std.testing.expectEqual(State.paused, race.state);
    try std.testing.expectEqual(@as(u32, 180), race.countdown);
    try std.testing.expectEqual(@as(u32, 0), race.ticks);
    race.resumeRace();
    clock.advance(&race, 3.0 / 60.0, .{});
    try std.testing.expectEqual(@as(u32, 177), race.countdown);
}

test "varied seeded full runs remain bounded with the fixed 113-attempt schedule" {
    for (1..33) |seed| {
        var race = Race.start(@intCast(seed));
        for (0..duration_ticks + 180) |tick| {
            race.step(.{ .accelerate = tick % 540 < 440, .brake = tick % 540 >= 500, .left = tick % 360 < 45, .right = tick % 360 >= 180 and tick % 360 < 225 });
            try std.testing.expect(race.x >= road.min_x and race.x <= road.max_x);
            try std.testing.expect(race.speed >= 0 and race.speed <= 90);
            try std.testing.expect(@abs(race.heading) <= road.max_heading + 0.00001);
            for (race.traffic, 0..) |car, i| if (car.active) {
                try std.testing.expect(car.x >= road.laneX(0) and car.x <= road.laneX(2));
                try std.testing.expect(car.speed >= 0 and car.speed <= car.cruise);
                try std.testing.expect(car.target_lane < road.lane_count);
                for (race.traffic[i + 1 ..]) |other| if (other.active) {
                    try std.testing.expect(car.body().gap(other.body()) >= 0);
                };
            };
        }
        try std.testing.expectEqual(State.finished, race.state);
        try std.testing.expectEqual(@as(u32, 113), race.spawned);
        try std.testing.expectEqual(race.score, race.base_points + race.near_points + race.speed_points + race.clean_points);
    }
}
