//! Versioned, deterministic simulation. No rendering, clock, audio, or browser dependencies.
const std = @import("std");
pub const road = @import("road.zig");
pub const encounters = @import("encounters.zig");

pub const version = 5;
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
    fast: bool = false,
    age: u32 = 0,
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
        return .{ .x = self.x, .y = self.y, .heading = self.heading, .height = self.height() };
    }

    pub fn height(self: Traffic) f32 {
        return if (self.fast) encounters.fast_height else car_height;
    }
};

pub const Race = struct {
    route: road.route.Route = .{},
    state: State = .ready,
    resume_state: State = .playing,
    seed: u32 = 1,
    rng: u32 = 1,
    encounter_rng: u32 = 1,
    next_encounter: u32 = 180,
    encounter_attempts: u32 = 0,
    pedestrian_spawns: u32 = 0,
    pedestrian_entries: u32 = 0,
    pedestrian_contacts: u32 = 0,
    fast_spawns: u32 = 0,
    pedestrian: encounters.Pedestrian = .{},
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
        return .{ .route = road.route.Route.init(seed), .state = .countdown, .seed = seed, .rng = if (seed == 0) 1 else seed, .encounter_rng = (seed ^ 0x9e3779b9) | 1 };
    }

    pub fn metric(self: *const Race, key: u32) f64 {
        return switch (key) {
            0 => @floatFromInt(@intFromEnum(self.state)),
            1 => @floatFromInt(self.score),
            2 => @floatFromInt(self.ticks),
            3 => @floatFromInt(self.multiplier()),
            4 => self.speed,
            5 => @floatFromInt(self.overtakes),
            6 => @floatFromInt(self.near_misses),
            7 => @floatFromInt(self.crashes),
            8 => @floatFromInt(self.base_points),
            9 => @floatFromInt(self.near_points),
            10 => @floatFromInt(self.speed_points),
            11 => @floatFromInt(self.clean_points),
            12 => @floatFromInt(self.best_streak),
            13 => @floatFromInt(self.seed),
            14 => self.x,
            15 => self.y,
            16 => @floatFromInt(self.countdown),
            17 => version,
            18 => self.heading,
            19 => self.lateral_velocity,
            20 => @floatFromInt(self.pedestrian_spawns),
            21 => @floatFromInt(self.fast_spawns),
            22 => @floatFromInt(self.pedestrian_entries),
            23 => @floatFromInt(self.pedestrian_contacts),
            24 => @floatFromInt(@intFromEnum(self.pedestrian.phase)),
            25 => @floatFromInt(self.pedestrian.age),
            26 => self.pedestrian.x,
            27 => self.pedestrian.y,
            28 => @floatFromInt(self.warningMask()),
            29 => @floatFromInt(@intFromEnum(encounters.pace(self.ticks))),
            30 => if (self.fastCar()) |car| car.y else -1000,
            31 => if (self.fastCar()) |car| car.speed else 0,
            32 => if (self.fastCar()) |car| @floatFromInt(car.lane) else 0,
            33 => if (self.fastCar()) |car| @floatFromInt(car.target_lane) else 0,
            34 => if (self.fastCar()) |car| @floatFromInt(car.age) else 0,
            35 => if (self.fastCar()) |car| @floatFromInt(car.signal) else 0,
            36 => if (self.fastCar()) |car| @floatFromInt(car.merge) else 0,
            37 => self.distance,
            38 => self.route.sample(self.distance).curvature,
            39 => self.route.safeSpeed(self.distance),
            40 => @floatFromInt(@intFromEnum(self.route.preview(self.distance).kind)),
            41 => self.route.preview(self.distance).lead,
            42 => self.route.preview(self.distance).guide,
            else => 0,
        };
    }

    pub fn pause(self: *Race) void {
        if (self.state == .playing or self.state == .countdown) {
            self.resume_state = self.state;
            self.state = .paused;
        }
    }

    pub fn fastCar(self: *const Race) ?Traffic {
        for (self.traffic) |car| if (car.active and car.fast) return car;
        return null;
    }

    pub fn warningMask(self: *const Race) u32 {
        if (self.state == .ready or self.state == .finished) return 0;
        var flags: u32 = 0;
        const p = self.pedestrian;
        if (p.active() and p.phase != .startled and p.y < self.y + car_height) {
            flags |= if (p.side == .left) @as(u32, 1) else 2;
            if (p.outer_lane) flags |= 4;
        }
        if (self.fastCar()) |car| {
            if (car.y >= self.y - 110) {
                flags |= 8;
                if (car.speed < car.cruise * 0.6) flags |= 16;
            }
        }
        return flags;
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
        if (encounters.pace(self.ticks) == .breather or self.reservedLane(lane)) return;
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
        return self.worldBody(.{ .x = self.x, .y = self.y, .heading = self.heading });
    }

    pub fn worldBody(self: *const Race, local: road.Body) road.Body {
        return road.bend(&self.route, self.distance, local);
    }

    pub fn groundSpeed(self: *const Race) f32 {
        return self.speed * road.pixels_per_mph;
    }

    pub fn onShoulder(self: *const Race) bool {
        return road.footprintOnShoulder(&self.route, self.distance, .{ .x = self.x, .y = self.y, .heading = self.heading });
    }

    fn encounterRandom(self: *Race) u32 {
        var x = self.encounter_rng;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.encounter_rng = x;
        return x;
    }

    fn reservedLane(self: *const Race, lane: u32) bool {
        const p = self.pedestrian;
        return p.active() and p.phase != .startled and
            (lane == p.escapeLane() or (p.outer_lane and lane == p.lane()));
    }

    /// A reachable lateral corridor, checked against both lanes of every merge
    /// and enough longitudinal time for reaction, steering inertia and travel.
    fn escapeClear(self: *const Race, p: encounters.Pedestrian) bool {
        const target_x = road.laneX(p.escapeLane());
        const left = @min(self.x, target_x) - 14;
        const right = @max(self.x, target_x) + car_width + 14;
        const horizon = @max(1.5, 1 + @abs(self.x - target_x) / @max(self.speed * 1.6, 20));
        for (self.traffic) |car| {
            if (!car.active) continue;
            const car_left = @min(car.x, road.laneX(car.target_lane));
            const car_right = @max(car.x, road.laneX(car.target_lane)) + car_width;
            if (car_right < left or car_left > right) continue;
            const relative_y = car.y - self.y;
            // A driver may accelerate to 90 mph or brake during the warning.
            const near = relative_y - car.speed * horizon;
            const far = relative_y + (450 - car.speed) * horizon;
            if (near < car_height + 45 and far > -car.height() - 45) return false;
        }
        return true;
    }

    fn pedestrianCanEnter(self: *const Race) bool {
        const p = self.pedestrian;
        // Crossings use mild bends/straights with a reachable exit. Recheck at
        // entry as well as placement, independent of camera visibility or zoom.
        if (self.route.maxCurvature(self.distance, @max(500, self.y - p.y + 200)) > 0.0012) return false;
        if (!self.escapeClear(p)) return false;
        if (p.outer_lane) for (self.traffic) |car| {
            if (!car.active or !car.occupies(p.lane())) continue;
            // Pedestrians yield to cars already committed to the crossing lane.
            if (car.y + car.height() > p.y - 30 and car.y - car.speed * 3 < p.y + 40) return false;
        };
        return true;
    }

    fn spawnEncounter(self: *Race) void {
        // Four draws at every scheduled attempt, including quiet periods, busy
        // pools, occupied roads and skipped encounters. Separate from traffic.
        const choice = self.encounterRandom();
        const style = self.encounterRandom();
        const speed = self.encounterRandom();
        const variation = self.encounterRandom();
        self.encounter_attempts += 1;
        if (encounters.pace(self.ticks) == .breather) return;
        if (self.encounter_attempts % 3 == 2) {
            for (self.traffic) |car| if (car.active and car.fast) return;
            var lane: ?u32 = null;
            var runway: f32 = -1;
            // Choose the clearest legal entrance, with seeded tie breaking.
            // No rerolls: the scheduled four draws above are the entire budget.
            for (0..road.lane_count) |offset| {
                const candidate = (choice % road.lane_count + @as(u32, @intCast(offset))) % road.lane_count;
                if (self.reservedLane(candidate)) continue;
                const space = self.laneRunway(1540, candidate);
                if (space > runway) {
                    runway = space;
                    lane = candidate;
                }
            }
            const selected = lane orelse return;
            const y: f32 = 1540;
            for (self.traffic) |car| {
                if (car.active and car.occupies(selected) and @abs(car.y - y) < 300) return;
            }
            for (&self.traffic) |*car| {
                if (car.active) continue;
                const cruise: f32 = @floatFromInt(1000 + speed % 201);
                car.* = .{
                    .active = true,
                    .fast = true,
                    .x = road.laneX(selected),
                    .y = y,
                    .speed = cruise,
                    .cruise = cruise,
                    .sprite = style % 2,
                    .lane = selected,
                    .target_lane = selected,
                    .next_decision = self.ticks + 30,
                    .preference = if (variation & 1 == 0) -1 else 1,
                };
                self.fast_spawns += 1;
                return;
            }
        } else {
            if (self.pedestrian.active()) return;
            var lead: f32 = 1490;
            while (lead <= 2690 and self.route.maxCurvature(self.distance + lead - 400, 800) > 0.0012) : (lead += 100) {}
            if (lead > 2690) return;
            self.pedestrian = .{
                .phase = .preparing,
                .side = if ((self.pedestrian_spawns +% self.seed) & 1 == 1) .left else .right,
                .outer_lane = self.ticks >= 1800 and choice % 3 == 0,
                .jumping = variation & 1 == 0,
                .appearance = style % 3,
                // Three seconds at the maximum possible speed plus a margin.
                // The offscreen marker announces this world-anchored position.
                .y = self.y - lead,
                .born = self.ticks,
            };
            self.pedestrian.x = self.pedestrian.homeX();
            self.pedestrian_spawns += 1;
        }
    }

    fn updatePedestrian(self: *Race) void {
        const p = &self.pedestrian;
        if (!p.active()) return;
        p.y += self.groundSpeed() * dt;
        p.age += 1;
        p.phase_ticks += 1;
        // A conservative preparation window stays below the HUD even at maximum zoom.
        if (p.y >= 170 and p.y < 600) p.visible_ticks += 1;
        switch (p.phase) {
            .preparing => {
                const lead = self.y - p.y;
                // A gap that opens at the last instant is not a fair invitation
                // to dash. Give the driver a whole second to use the exit first.
                p.clear_ticks = if (self.escapeClear(p.*)) p.clear_ticks + 1 else 0;
                if (p.age >= encounters.warning_ticks and p.visible_ticks >= encounters.visible_preparation_ticks and
                    p.clear_ticks >= encounters.clear_escape_ticks and lead <= 340 and lead >= 150 and self.pedestrianCanEnter())
                {
                    p.setPhase(.dashing);
                    p.entered_tick = self.ticks;
                    self.pedestrian_entries += 1;
                }
            },
            .dashing => {
                p.x = approach(p.x, p.targetX(), 150 * dt);
                if (p.x == p.targetX()) p.setPhase(.waiting);
            },
            .waiting => {
                if (p.y > self.y + car_height + 35 or p.phase_ticks >= 150) p.setPhase(.retreating);
            },
            .retreating, .startled => {
                p.x = approach(p.x, p.homeX(), 180 * dt);
                if (p.x == p.homeX() and p.phase_ticks >= 45) p.phase = .inactive;
            },
            .inactive => {},
        }
        if (p.dangerous() and !p.collided and self.body().gap(self.worldBody(p.body())) < 0) {
            p.collided = true;
            p.setPhase(.startled);
            self.pedestrian_contacts += 1;
            self.crash();
        }
        if (p.y > 720 or p.age > 1200) p.phase = .inactive;
    }

    fn crash(self: *Race) void {
        if (self.invulnerable > 0) return;
        self.crashes += 1;
        self.streak = 0;
        self.speed *= 0.45;
        self.acceleration = 0;
        self.lateral_velocity *= 0.4;
        self.invulnerable = 60;
    }

    fn laneSafe(self: *const Race, index: usize, lane: u32) bool {
        if (self.reservedLane(lane)) return false;
        const car = self.traffic[index];
        if (self.route.maxCurvature(road.station(self.distance, car.y, car.height()), @max(350, car.speed * 2)) > 0.0015) return false;
        for (self.traffic, 0..) |other, j| {
            if (j == index or !other.active or !other.occupies(lane)) continue;
            const closing = if (other.y < car.y) car.speed - other.speed else other.speed - car.speed;
            // Reserve space for the entire signal + merge, not just the current gap.
            const approach_gap = if (car.fast and other.y < car.y) brakingRoom(closing) else @max(0, closing) * 3;
            if (@abs(other.y - car.y) < @max(car.height(), other.height()) + following_gap + approach_gap) return false;
        }
        const target_x = road.laneX(lane);
        if (self.x + car_width > target_x - 18 and self.x < target_x + car_width + 18) {
            const closing = if (self.y < car.y) car.speed - self.groundSpeed() else self.groundSpeed() - car.speed;
            const approach_gap = if (car.fast and self.y < car.y) brakingRoom(closing) else @max(0, closing) * 3;
            if (@abs(self.y - car.y) < @max(car.height(), car_height) + 50 + approach_gap) return false;
        }
        return true;
    }

    fn laneRunway(self: *const Race, y: f32, lane: u32) f32 {
        var space: f32 = 3000;
        for (self.traffic) |car| {
            if (car.active and car.occupies(lane) and car.y < y) space = @min(space, y - car.y - car.height());
        }
        const x = road.laneX(lane);
        if (self.y < y and self.x + car_width > x - 18 and self.x < x + car_width + 18)
            space = @min(space, y - self.y - car_height);
        return space;
    }

    fn safetyLength(self: *const Race, y: f32, height: f32) f32 {
        const k = self.route.maxCurvature(road.station(self.distance, y, height), 600);
        // Inside lanes cover less world distance per station. Reserve enough
        // station space for a rotated body before that compression arrives.
        return height / @max(0.4, 1 - k * 145);
    }

    fn updateTraffic(self: *Race) void {
        // Snapshot velocities/positions so following does not depend on pool slot order.
        const before = self.traffic;
        for (&self.traffic, 0..) |*car, i| {
            if (!car.active) continue;
            car.age += 1;
            const station = road.station(self.distance, car.y, car.height());
            const curvature = self.route.maxCurvature(station, if (car.fast) 900 else 300);
            // Open-wheel grip is higher, but fast cars also brake before tight
            // sequences and hold their lane until the road opens up.
            var target = @min(car.cruise, @sqrt((if (car.fast) @as(f32, 700) else 150) / @max(curvature, 0.00001)));
            var bumper_gap: f32 = std.math.inf(f32);
            var lead_speed = car.cruise;
            for (before, 0..) |other, j| {
                if (i == j or !other.active or other.y >= car.y) continue;
                if (!other.occupies(car.lane) and !other.occupies(car.target_lane)) continue;
                const gap = car.y - other.y - self.safetyLength(other.y, other.height());
                if (gap < bumper_gap) {
                    bumper_gap = gap;
                    lead_speed = other.speed;
                }
            }
            if (self.y < car.y and @abs(self.x - car.x) < car_width + 8) {
                const gap = car.y - self.y - self.safetyLength(self.y, car_height);
                if (gap < bumper_gap) {
                    bumper_gap = gap;
                    lead_speed = self.groundSpeed();
                }
            }
            const desired_gap = following_gap + car.speed * (if (car.fast) @as(f32, 0.35) else 0.45);
            if (bumper_gap < desired_gap + 100) target = @min(target, @max(0, lead_speed + (bumper_gap - desired_gap) * 1.5));
            const deceleration: f32 = if (car.fast) 1800 else 220;
            const acceleration: f32 = if (car.fast) 480 else 55;
            car.speed = approach(car.speed, target, (if (target < car.speed) deceleration else acceleration) * dt);
            car.braking = target < before[i].speed - 4;

            if (car.lane == car.target_lane and self.ticks >= car.next_decision) {
                car.next_decision = self.ticks + (if (car.fast) @as(u32, 90) else 300) + @as(u32, @intCast(i)) * 7;
                // Most changes are overtakes; a minority are route preferences.
                const wants_change = bumper_gap < desired_gap + (if (car.fast) @as(f32, 600) else 85) or (!car.fast and (self.ticks / 300 + i) % 3 == 0);
                if (wants_change) {
                    var target_lane = @as(i32, @intCast(car.lane)) + car.preference;
                    if (target_lane < 0 or target_lane >= road.lane_count) target_lane = @as(i32, @intCast(car.lane)) - car.preference;
                    // Prefer an adjacent lane that actually improves the pass.
                    if (car.fast) {
                        const alternate = @as(i32, @intCast(car.lane)) - car.preference;
                        if (alternate >= 0 and alternate < road.lane_count and self.laneSafe(i, @intCast(alternate)) and
                            (!self.laneSafe(i, @intCast(target_lane)) or self.laneRunway(car.y, @intCast(alternate)) > self.laneRunway(car.y, @intCast(target_lane)))) target_lane = alternate;
                    }
                    if (self.laneSafe(i, @intCast(target_lane)) and (!car.fast or self.laneRunway(car.y, @intCast(target_lane)) > bumper_gap + 80)) {
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
                        car.next_decision = self.ticks + (if (car.fast) @as(u32, 60) else 180);
                    }
                } else {
                    // Recheck the player's swept corridor every tick. Yield laterally
                    // if a driver enters the reserved space; never snap across a car.
                    const target_x = road.laneX(car.target_lane);
                    const player_near = @abs(self.y - car.y) < @max(car.height(), car_height) + 36 and
                        self.x + car_width > @min(car.x, target_x) - 10 and
                        self.x < @max(car.x, target_x) + car_width + 10;
                    if (!player_near) car.merge += 1;
                    const progress = @as(f32, @floatFromInt(car.merge)) / merge_ticks;
                    const eased = progress * progress * (3 - 2 * progress);
                    car.x = road.laneX(car.lane) + (target_x - road.laneX(car.lane)) * eased;
                    if (car.merge >= merge_ticks) {
                        car.lane = car.target_lane;
                        car.merge = 0;
                        if (car.fast) car.next_decision = self.ticks + 90;
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
            if (car.fast and bumper_gap >= 0 and bumper_gap < following_gap)
                car.speed = @min(car.speed, lead_speed);
            // A full warning precedes onscreen entry even at zero player speed.
            if (car.fast and car.age <= encounters.warning_ticks)
                car.speed = @min(car.speed, self.groundSpeed() + @max(0, car.y - encounters.fast_entry_y) / dt);
            car.y += (self.groundSpeed() - car.speed) * dt;
        }
    }

    pub fn award(self: *Race, car: *Traffic) void {
        if (car.fast or car.passed or car.collided) return;
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
        const center_curvature = self.route.sample(self.distance).curvature;
        // A tighter inside line asks for more grip than a wide entry. Moving
        // across a clear lane can open the radius before clipping the apex.
        const lateral = self.x + car_width / 2 - 400;
        const curvature = center_curvature / @max(0.45, 1 - lateral * center_curvature);
        // Gentle lane following assists a cruise. At speed, lateral grip runs
        // out progressively: countersteer or brake before the apex.
        const outward = -curvature * self.groundSpeed() * self.groundSpeed() * 0.23;
        self.lateral_velocity += (horizontal * self.speed * 1.6 + outward - self.lateral_velocity) * 7 * dt;
        if (self.speed == 0) self.lateral_velocity = 0;
        self.x = std.math.clamp(self.x + self.lateral_velocity * dt, road.min_x, road.max_x);
        if (self.x == road.min_x or self.x == road.max_x) self.lateral_velocity = 0;
        const target_heading = std.math.clamp(std.math.atan2(self.lateral_velocity, @max(self.groundSpeed(), 1)), -road.max_heading, road.max_heading);
        self.heading += (target_heading - self.heading) * 10 * dt;
        // Player station is fixed; camera framing belongs entirely to presentation.
        if (self.onShoulder()) {
            const runoff_speed = @min(54, self.route.safeSpeed(self.distance) * 0.85);
            self.speed = @max(0, self.speed - (if (self.speed > runoff_speed) @as(f32, 80) else 22) * dt);
        }
        self.distance += self.groundSpeed() * dt;
        if (self.invulnerable > 0) self.invulnerable -= 1;
        if (self.award_ticks > 0) self.award_ticks -= 1;
        if (self.ticks >= self.next_encounter) {
            self.spawnEncounter();
            self.next_encounter = self.ticks + encounters.interval(self.ticks);
        }
        if (self.ticks >= self.next_spawn) {
            self.spawn();
            // 1.1s between cars at the start; 0.55s toward the finish.
            self.next_spawn = self.ticks + 66 - @min(self.ticks / 160, 33);
        }
        self.updateTraffic();
        self.updatePedestrian();
        for (&self.traffic) |*car| {
            if (!car.active) continue;
            const vertical_overlap = @abs(self.y - car.y) < car_height - 8;
            const gap = self.body().gap(self.worldBody(car.body()));
            if (gap < 0) {
                const first_contact = !car.collided;
                car.collided = true;
                if (first_contact) self.crash();
            }
            if (vertical_overlap) {
                if (gap >= 0) {
                    car.closest = @min(car.closest, gap);
                }
            }
            if (car.y > self.y + car_height) self.award(car);
            if ((!car.fast and car.y > 700) or (car.fast and car.age > encounters.warning_ticks and car.y > 1800) or car.y < -180) car.active = false;
        }
        self.ticks += 1;
        if (self.ticks == duration_ticks) self.state = .finished;
    }
};

fn approach(value: f32, target: f32, amount: f32) f32 {
    return value + std.math.clamp(target - value, -amount, amount);
}

fn brakingRoom(closing: f32) f32 {
    const speed = @max(0, closing);
    // Fast cars can shed 1800 px/s each second. Reserve stopping distance plus
    // 0.3 seconds of margin; both lanes still obey following floors while merging.
    return speed * speed / (2 * 1800) + speed * 0.3;
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
                    try std.testing.expect(race.worldBody(car.body()).gap(race.worldBody(other.body())) >= 0);
                };
            };
        }
        try std.testing.expectEqual(State.finished, race.state);
        try std.testing.expectEqual(@as(u32, 113), race.spawned);
        try std.testing.expectEqual(race.score, race.base_points + race.near_points + race.speed_points + race.clean_points);
    }
}

test "encounter scheduling consumes four draws regardless of input, reservations and full pools" {
    var a = Race.start(99);
    var b = a;
    var reference = a;
    for (&b.traffic) |*car| car.* = fixture(1, 1540, 180);
    b.pedestrian = .{ .phase = .preparing };
    for (0..40) |i| {
        a.ticks = @intCast(i * 180);
        b.ticks = a.ticks;
        a.spawnEncounter();
        b.spawnEncounter();
        for (0..4) |_| _ = reference.encounterRandom();
        try std.testing.expectEqual(reference.encounter_rng, a.encounter_rng);
        try std.testing.expectEqual(a.encounter_rng, b.encounter_rng);
        try std.testing.expectEqual(a.encounter_attempts, b.encounter_attempts);
    }
    a = Race.start(17);
    b = a;
    for (0..duration_ticks + 180) |_| {
        a.step(.{ .accelerate = true, .left = true });
        b.step(.{ .brake = true, .right = true });
        try std.testing.expectEqual(a.encounter_rng, b.encounter_rng);
        try std.testing.expectEqual(a.encounter_attempts, b.encounter_attempts);
        try std.testing.expectEqual(a.next_encounter, b.next_encounter);
        try std.testing.expectEqual(a.rng, b.rng);
        try std.testing.expectEqual(a.next_spawn, b.next_spawn);
    }
}

test "fast cars announce for 150 ticks before onscreen entry at every player speed" {
    for ([_]f32{ 0, 42, 90 }) |speed| {
        var race = Race.start(5);
        race.speed = speed;
        race.x = road.laneX(2);
        race.encounter_attempts = 1;
        race.spawnEncounter();
        try std.testing.expectEqual(@as(u32, 1), race.fast_spawns);
        for (0..encounters.warning_ticks) |_| {
            race.updateTraffic();
            for (race.traffic) |car| if (car.active and car.fast) {
                try std.testing.expect(car.y >= encounters.fast_entry_y - 0.01);
                try std.testing.expect(car.body().gap(race.body()) > 0);
            };
            race.ticks += 1;
        }
    }
}

test "fast followers never rear end a steady or emergency-braking player" {
    for ([_]f32{ 0, 42, 90 }) |speed| {
        var race = Race.start(4);
        race.speed = speed;
        race.traffic[0] = fixture(1, 1540, 1200);
        race.traffic[0].fast = true;
        for (0..900) |tick| {
            if (tick > 200) race.speed = @max(0, race.speed - 68 * dt);
            race.updateTraffic();
            const car = race.traffic[0];
            try std.testing.expect(car.y - race.y >= car_height + following_gap - 0.01);
            try std.testing.expect(car.body().gap(race.body()) >= 0);
            race.ticks += 1;
        }
    }
}

test "open-wheel traffic signals, passes a slower leader and earns no spawn points" {
    var race = Race.start(8);
    race.speed = 42;
    race.x = road.laneX(2);
    race.traffic[0] = fixture(0, 50, 140);
    race.traffic[1] = fixture(0, 800, 1100);
    race.traffic[1].fast = true;
    race.traffic[1].age = encounters.warning_ticks;
    race.traffic[1].next_decision = 0;
    var signaled: u32 = 0;
    var passed = false;
    for (0..720) |_| {
        const previous = race.traffic[1];
        race.updateTraffic();
        const car = race.traffic[1];
        if (car.signal > 0) signaled += 1;
        if (previous.signal > 0) try std.testing.expectEqual(previous.x, car.x);
        if (car.merge > 0) try std.testing.expect(signaled >= signal_ticks - 1);
        try std.testing.expect(car.body().gap(race.traffic[0].body()) >= 0);
        passed = passed or car.y + car.height() < race.traffic[0].y;
        race.award(&race.traffic[1]);
        race.ticks += 1;
    }
    try std.testing.expect(passed);
    try std.testing.expectEqual(@as(u32, 0), race.score);
}

test "pedestrian entry needs a full warning, visible preparation and a clear escape corridor" {
    var race = Race.start(1);
    race.speed = 90;
    race.x = road.min_x;
    race.pedestrian = .{ .phase = .preparing, .side = .left, .outer_lane = true, .x = road.left - 34, .y = 120 };
    for (0..encounters.warning_ticks - 1) |_| {
        // Keep the fixture ahead while checking the temporal gate.
        race.pedestrian.y = race.y - 260;
        race.updatePedestrian();
        try std.testing.expectEqual(encounters.Phase.preparing, race.pedestrian.phase);
        race.ticks += 1;
    }
    race.traffic[0] = fixture(1, race.y - 80, 150);
    race.pedestrian.y = race.y - 260;
    race.updatePedestrian();
    try std.testing.expectEqual(encounters.Phase.preparing, race.pedestrian.phase);
    race.traffic[0].active = false;
    // An existing outer-lane vehicle also makes the person wait.
    race.traffic[0] = fixture(0, race.pedestrian.y + 180, 150);
    race.updatePedestrian();
    try std.testing.expectEqual(encounters.Phase.preparing, race.pedestrian.phase);
    race.traffic[0].active = false;
    for (0..encounters.clear_escape_ticks) |_| {
        race.pedestrian.y = race.y - 260;
        race.updatePedestrian();
        race.ticks += 1;
    }
    try std.testing.expectEqual(encounters.Phase.dashing, race.pedestrian.phase);
    try std.testing.expect(race.pedestrian.age >= encounters.warning_ticks);
    try std.testing.expect(race.pedestrian.visible_ticks >= encounters.visible_preparation_ticks);
    try std.testing.expect(race.escapeClear(race.pedestrian));
    try std.testing.expect(race.reservedLane(0));
    try std.testing.expect(race.reservedLane(1));
    try std.testing.expect(!race.reservedLane(2));
}

test "pedestrian contact uses recovery and a harmless startled retreat" {
    var race = Race.start(1);
    race.speed = 0;
    race.streak = 12;
    race.pedestrian = .{ .phase = .waiting, .x = race.x + 10, .y = race.y + 10 };
    race.updatePedestrian();
    try std.testing.expectEqual(@as(u32, 1), race.crashes);
    try std.testing.expectEqual(@as(u32, 1), race.pedestrian_contacts);
    try std.testing.expectEqual(@as(u32, 0), race.streak);
    try std.testing.expectEqual(@as(u32, 60), race.invulnerable);
    try std.testing.expectEqual(encounters.Phase.startled, race.pedestrian.phase);
    for (0..120) |_| race.updatePedestrian();
    try std.testing.expectEqual(@as(u32, 1), race.crashes);
    try std.testing.expect(!race.pedestrian.active());
}

test "encounters freeze during pause and restart restores every warning and animation" {
    var race = Race.start(20260905);
    for (0..1050) |_| race.step(.{ .accelerate = true });
    race.pause();
    const frozen = race;
    for (0..1000) |_| race.step(.{ .left = true, .brake = true });
    try std.testing.expectEqualDeep(frozen, race);
    race.resumeRace();
    var replay = Race.start(20260905);
    for (0..1050) |_| replay.step(.{ .accelerate = true });
    try std.testing.expectEqualDeep(replay, race);
    race = Race.start(20260905);
    try std.testing.expectEqualDeep(Race.start(20260905), race);
}

test "encounter audit of complete runs and repeated shoulder use" {
    var entries: u32 = 0;
    var contacts: u32 = 0;
    var fast: u32 = 0;
    var outer_entries: u32 = 0;
    var left_contacts: u32 = 0;
    var right_contacts: u32 = 0;
    var pressured_runs: u32 = 0;
    var combined_entries: u32 = 0;
    var fast_passes: u32 = 0;
    var peak_visible_speed: f32 = 0;
    for (1..65) |seed| {
        for ([_]bool{ false, true }) |right| {
            var race = Race.start(@intCast(seed));
            for (0..duration_ticks + 180) |_| {
                const previous_entries = race.pedestrian_entries;
                const previous_contacts = race.pedestrian_contacts;
                const before = race.traffic;
                race.step(.{ .accelerate = true, .left = !right, .right = right });
                if (race.pedestrian_entries > previous_entries) {
                    const p = race.pedestrian;
                    try std.testing.expect(p.age >= encounters.warning_ticks);
                    try std.testing.expect(p.visible_ticks >= encounters.visible_preparation_ticks);
                    try std.testing.expect(p.clear_ticks >= encounters.clear_escape_ticks);
                    try std.testing.expect(race.escapeClear(p));
                    if (p.outer_lane) outer_entries += 1;
                    for (race.traffic) |car| if (car.active and car.fast) {
                        combined_entries += 1;
                        break;
                    };
                }
                if (race.pedestrian_contacts > previous_contacts) {
                    if (right) right_contacts += 1 else left_contacts += 1;
                }
                for (race.traffic, 0..) |car, i| if (car.active) {
                    if (car.fast and car.y >= 0 and car.y < road.height) peak_visible_speed = @max(peak_visible_speed, car.speed);
                    for (race.traffic[i + 1 ..]) |other| if (other.active) {
                        try std.testing.expect(race.worldBody(car.body()).gap(race.worldBody(other.body())) >= 0);
                    };
                    if (car.fast and before[i].active and car.age == before[i].age + 1) {
                        for (race.traffic, 0..) |other, j| {
                            if (!other.active or other.fast or !before[j].active or other.age != before[j].age + 1) continue;
                            if (before[i].y + car.height() >= before[j].y and car.y + car.height() < other.y) fast_passes += 1;
                        }
                    }
                };
            }
            entries += race.pedestrian_entries;
            contacts += race.pedestrian_contacts;
            fast += race.fast_spawns;
            if (race.pedestrian_contacts >= 2) pressured_runs += 1;
            try std.testing.expectEqual(State.finished, race.state);
            try std.testing.expectEqual(@as(u32, 113), race.spawned);
        }
    }
    // v5 confines crossings to mild sections and slows sustained runoff use.
    try std.testing.expect(entries >= 64);
    try std.testing.expect(outer_entries > 0);
    try std.testing.expect(left_contacts >= 32 and right_contacts >= 32);
    try std.testing.expect(fast >= 128);
    try std.testing.expect(pressured_runs >= 8);
    try std.testing.expect(combined_entries >= 32);
    try std.testing.expect(fast_passes >= 128);
    try std.testing.expect(peak_visible_speed >= 1000);
    try std.testing.expect(contacts >= 64);
}

test "browser warning flags describe the same frozen encounter as the renderer" {
    var race = Race.start(1);
    race.state = .playing;
    race.pedestrian = .{ .phase = .preparing, .side = .left, .outer_lane = true };
    race.traffic[0] = fixture(2, 900, 1200);
    race.traffic[0].fast = true;
    try std.testing.expectEqual(@as(u32, 1 | 4 | 8), race.warningMask());
    race.traffic[0].speed = 150;
    race.pause();
    try std.testing.expectEqual(@as(u32, 1 | 4 | 8 | 16), race.warningMask());
    race.state = .finished;
    try std.testing.expectEqual(@as(u32, 0), race.warningMask());
}

test "reading a crossing warning provides a usable temporary shoulder exit" {
    for (1..65) |seed| {
        for ([_]bool{ false, true }) |right| {
            var race = Race.start(@intCast(seed));
            var escaping = false;
            var target: f32 = if (right) road.max_x else road.min_x;
            for (0..duration_ticks + 180) |_| {
                const p = race.pedestrian;
                if (p.active() and (p.side == .right) == right and p.y < race.y + car_height + 100) {
                    if (race.escapeClear(p)) {
                        escaping = true;
                        target = road.laneX(p.escapeLane());
                    }
                } else if (escaping) {
                    escaping = false;
                    target = if (right) road.max_x else road.min_x;
                }
                race.step(.{ .accelerate = true, .left = race.x > target + 3, .right = race.x < target - 3 });
                if (race.pedestrian_contacts > 0) {
                    std.debug.print("\nEscape failure seed={d} right={} tick={d} x={d:.1} target={d:.1} speed={d:.1} p={any}\n", .{ seed, right, race.ticks, race.x, target, race.speed, race.pedestrian });
                    break;
                }
            }
            try std.testing.expectEqual(@as(u32, 0), race.pedestrian_contacts);
        }
    }
}

test "cornering demands less countersteer after braking and permits different lines" {
    // Remove encounter scheduling to measure lateral grip in one known corner.
    var gas = Race.start(20260905);
    gas.state = .playing;
    gas.distance = 14380;
    gas.speed = 85;
    gas.next_spawn = duration_ticks;
    gas.next_encounter = duration_ticks;
    var braking = gas;
    const start_x = gas.x;
    for (0..60) |_| {
        gas.step(.{ .accelerate = true });
        braking.step(.{ .brake = true });
    }
    try std.testing.expect(@abs(gas.x - start_x) > @abs(braking.x - start_x) + 10);
    try std.testing.expect(braking.speed < gas.speed - 20);
    var inside = Race.start(2);
    inside.state = .playing;
    inside.distance = 15000;
    inside.x = road.laneX(0);
    inside.next_spawn = duration_ticks;
    inside.next_encounter = duration_ticks;
    var outside = inside;
    outside.x = road.laneX(2);
    for (0..60) |_| {
        inside.step(.{});
        outside.step(.{});
    }
    try std.testing.expect(outside.x - inside.x > road.lane_width);
}

test "changing zoom throughout 30 60 and 144 Hz full replays cannot affect any simulation field" {
    const camera = @import("camera.zig");
    var expected: ?Race = null;
    for ([_]u32{ 30, 60, 144 }) |fps| {
        var race = Race.start(6197);
        var clock: Clock = .{};
        var view: camera.Camera = .{};
        for (0..93 * fps) |frame| {
            const phase = (frame / fps) % 12;
            const input: Input = .{ .accelerate = phase < 8, .brake = phase == 9, .left = phase == 2 or phase == 3, .right = phase == 5 or phase == 6 };
            view.setZoom(if (phase < 4) camera.minimum else if (phase < 8) camera.maximum else camera.default_zoom);
            view.update(&race.route, race.distance, 1.0 / @as(f32, @floatFromInt(fps)));
            clock.advance(&race, 1.0 / @as(f64, @floatFromInt(fps)), input);
            try std.testing.expect(view.zoom >= camera.minimum and view.zoom <= camera.maximum);
            try std.testing.expect(std.math.isFinite(view.heading));
        }
        try std.testing.expectEqual(State.finished, race.state);
        if (expected) |other| try std.testing.expectEqualDeep(other, race);
        expected = race;
    }
}

test "traffic world bodies stay separate during full runs with varied cornering and braking" {
    var passes: u32 = 0;
    var combined: u32 = 0;
    for (1..33) |seed| {
        var race = Race.start(@intCast(seed * 7919));
        for (0..duration_ticks + 180) |_| {
            const phase = race.ticks / 240 % 8;
            race.step(.{ .accelerate = phase < 6, .brake = phase == 6, .left = phase == 2, .right = phase == 4 });
            for (race.traffic, 0..) |car, i| {
                if (!car.active) continue;
                for (race.traffic[i + 1 ..]) |other| {
                    if (!other.active) continue;
                    try std.testing.expect(race.worldBody(car.body()).gap(race.worldBody(other.body())) >= 0);
                }
            }
            if (race.pedestrian.dangerous() and race.fastCar() != null) combined += 1;
        }
        passes += race.overtakes;
        try std.testing.expectEqual(State.finished, race.state);
    }
    try std.testing.expect(passes > 300);
    try std.testing.expect(combined > 0);
}
