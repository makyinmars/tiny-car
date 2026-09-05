//! Versioned, deterministic simulation. No rendering, clock, audio, or browser dependencies.
const std = @import("std");

pub const version = 2;
pub const hz = 60;
pub const duration_ticks = 90 * hz;
pub const dt: f32 = 1.0 / @as(f32, hz);
pub const car_width: f32 = 32;
pub const car_height: f32 = 48;
pub const State = enum(u32) { ready, countdown, playing, paused, finished };
pub const Input = packed struct(u8) {
    left: bool = false,
    right: bool = false,
    accelerate: bool = false,
    brake: bool = false,
    padding: u4 = 0,
};
pub const Traffic = struct {
    active: bool = false,
    x: f32 = 0,
    y: f32 = -60,
    speed: f32 = 0,
    sprite: u32 = 0,
    passed: bool = false,
    collided: bool = false,
    closest: f32 = std.math.inf(f32),
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
    x: f32 = 384,
    y: f32 = 430,
    speed: f32 = 30,
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
        const lane = self.random() % 5;
        const speed = 80 + self.random() % 41;
        const sprite = self.random() % 6;
        self.spawned += 1;
        for (&self.traffic) |*car| {
            if (!car.active) {
                car.* = .{ .active = true, .x = 278 + @as(f32, @floatFromInt(lane)) * 47, .speed = @floatFromInt(speed), .sprite = sprite };
                return;
            }
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
        const target: f32 = if (input.brake) 0 else if (input.accelerate) 90 else 42;
        if (self.speed < target) self.speed = @min(target, self.speed + 45 * dt);
        if (self.speed > target) self.speed = @max(target, self.speed - (if (input.brake) @as(f32, 85) else 30) * dt);
        const horizontal: f32 = @as(f32, @floatFromInt(@intFromBool(input.right))) - @as(f32, @floatFromInt(@intFromBool(input.left)));
        const vertical: f32 = @as(f32, @floatFromInt(@intFromBool(input.brake))) - @as(f32, @floatFromInt(@intFromBool(input.accelerate)));
        self.x = std.math.clamp(self.x + horizontal * 210 * dt, 268, 500);
        self.y = std.math.clamp(self.y + vertical * 85 * dt, 110, 540);
        self.distance += self.speed * 5 * dt;
        if (self.invulnerable > 0) self.invulnerable -= 1;
        if (self.award_ticks > 0) self.award_ticks -= 1;
        if (self.ticks >= self.next_spawn) {
            self.spawn();
            // 1.1s between cars at the start; 0.55s toward the finish.
            self.next_spawn = self.ticks + 66 - @min(self.ticks / 160, 33);
        }
        for (&self.traffic) |*car| {
            if (!car.active) continue;
            car.y += (self.speed * 5 - car.speed) * dt;
            const vertical_overlap = self.y < car.y + car_height and self.y + car_height > car.y;
            const gap = @max(self.x - (car.x + car_width), car.x - (self.x + car_width));
            if (vertical_overlap) {
                if (gap < -4) {
                    // Touching the same car during recovery never becomes a clean pass.
                    const first_contact = !car.collided;
                    car.collided = true;
                    if (first_contact and self.invulnerable == 0) {
                        self.crashes += 1;
                        self.streak = 0;
                        self.speed *= 0.45;
                        self.invulnerable = 60;
                    }
                } else if (gap >= 0) {
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
