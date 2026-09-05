//! Presentation only. No simulation mutation and no use of the traffic PRNG.
const rl = @import("raylib");
const std = @import("std");
const sim = @import("race.zig");
const road = sim.road;
const camera = @import("camera.zig");
const encounters = sim.encounters;

const cream: rl.Color = .{ .r = 236, .g = 230, .b = 211, .a = 255 };
const sage: rl.Color = .{ .r = 190, .g = 211, .b = 159, .a = 255 };
const ink: rl.Color = .{ .r = 18, .g = 31, .b = 28, .a = 235 };
const amber: rl.Color = .{ .r = 255, .g = 202, .b = 102, .a = 255 };
const cyan: rl.Color = .{ .r = 118, .g = 232, .b = 233, .a = 255 };

// Occupied alpha bounds in the generated atlas, including a small edge guard.
// Every vehicle is rendered to the shared 38x72 footprint, nose pointing up.
const vehicle_sources = [_]rl.Rectangle{
    .{ .x = 198, .y = 16, .width = 261, .height = 480 },
    .{ .x = 638, .y = 8, .width = 259, .height = 496 },
    .{ .x = 1078, .y = 20, .width = 259, .height = 485 },
    .{ .x = 193, .y = 511, .width = 269, .height = 500 },
    .{ .x = 627, .y = 515, .width = 282, .height = 496 },
    .{ .x = 1077, .y = 527, .width = 261, .height = 476 },
};
const tree_sources = [_]rl.Rectangle{
    .{ .x = 20, .y = 22, .width = 602, .height = 586 },
    .{ .x = 653, .y = 14, .width = 585, .height = 608 },
    .{ .x = 20, .y = 630, .width = 594, .height = 599 },
    .{ .x = 650, .y = 630, .width = 588, .height = 609 },
};
const fast_sources = [_]rl.Rectangle{
    .{ .x = 83, .y = 13, .width = 504, .height = 1213 },
    .{ .x = 667, .y = 14, .width = 505, .height = 1212 },
};
const pedestrian_sources = [_]rl.Rectangle{
    .{ .x = 117, .y = 66, .width = 213, .height = 227 },
    .{ .x = 479, .y = 95, .width = 190, .height = 181 },
    .{ .x = 808, .y = 74, .width = 296, .height = 193 },
    .{ .x = 1191, .y = 85, .width = 280, .height = 200 },
    .{ .x = 109, .y = 360, .width = 200, .height = 239 },
    .{ .x = 467, .y = 416, .width = 221, .height = 177 },
    .{ .x = 816, .y = 383, .width = 290, .height = 209 },
    .{ .x = 1195, .y = 396, .width = 292, .height = 199 },
    .{ .x = 115, .y = 686, .width = 212, .height = 238 },
    .{ .x = 490, .y = 739, .width = 177, .height = 177 },
    .{ .x = 807, .y = 702, .width = 294, .height = 201 },
    .{ .x = 1195, .y = 711, .width = 279, .height = 209 },
};

pub const Ghost = struct { x: f32 = -100, y: f32 = -100, heading: f32 = 0, distance: f32 = 0 };
const Kind = enum { tire, dust, spark };
const Particle = struct {
    kind: Kind = .tire,
    x: f32 = 0,
    world_y: f32 = 0,
    vx: f32 = 0,
    vy: f32 = 0,
    born: u32 = 0,
    life: u32 = 0,
    length: i32 = 12,
};

pub const Renderer = struct {
    vehicles: rl.Texture2D,
    trees: rl.Texture2D,
    grass: rl.Texture2D,
    asphalt: rl.Texture2D,
    open_wheel: rl.Texture2D,
    pedestrians: rl.Texture2D,
    particles: [192]Particle = @splat(.{}),
    cursor: usize = 0,
    previous_tick: u32 = 0,
    previous_crashes: u32 = 0,
    impact_tick: ?u32 = null,
    view: camera.Camera = .{},

    pub fn init() !Renderer {
        const vehicles = try rl.loadTexture("resources/textures/cars.png");
        errdefer rl.unloadTexture(vehicles);
        const trees = try rl.loadTexture("resources/textures/trees.png");
        errdefer rl.unloadTexture(trees);
        const grass = try rl.loadTexture("resources/textures/grass.png");
        errdefer rl.unloadTexture(grass);
        const asphalt = try rl.loadTexture("resources/textures/road.png");
        errdefer rl.unloadTexture(asphalt);
        const open_wheel = try rl.loadTexture("resources/textures/open-wheel.png");
        errdefer rl.unloadTexture(open_wheel);
        const pedestrians = try rl.loadTexture("resources/textures/pedestrians.png");
        for ([_]rl.Texture2D{ vehicles, trees, grass, asphalt, open_wheel, pedestrians }) |texture| rl.setTextureFilter(texture, .bilinear);
        return .{ .vehicles = vehicles, .trees = trees, .grass = grass, .asphalt = asphalt, .open_wheel = open_wheel, .pedestrians = pedestrians };
    }

    pub fn deinit(self: Renderer) void {
        for ([_]rl.Texture2D{ self.vehicles, self.trees, self.grass, self.asphalt, self.open_wheel, self.pedestrians }) |texture| rl.unloadTexture(texture);
    }

    fn emit(self: *Renderer, particle: Particle) void {
        self.particles[self.cursor] = particle;
        self.cursor = (self.cursor + 1) % self.particles.len;
    }

    fn update(self: *Renderer, race: *const sim.Race) void {
        if (race.ticks < self.previous_tick or race.state == .ready) {
            self.particles = @splat(.{});
            self.previous_crashes = 0;
            self.impact_tick = null;
        }
        const changed = race.ticks != self.previous_tick;
        if (changed and race.state == .playing) {
            if (race.braking and race.acceleration < -25 and race.speed > 40 and race.ticks / 3 != self.previous_tick / 3) {
                for ([_]f32{ 5, road.car_width - 5 }) |x| self.emit(.{
                    .kind = .tire,
                    .x = race.x + x,
                    .world_y = race.y + road.car_height - 10 - race.distance,
                    .born = race.ticks,
                    .life = 140,
                    .length = @intFromFloat(race.groundSpeed() * 0.05 + 2),
                });
            }
            if (race.onShoulder() and race.speed > 12 and race.ticks / 4 != self.previous_tick / 4) {
                const side: f32 = if (race.x < road.left + 2) -1 else 1;
                self.emit(.{ .kind = .dust, .x = race.x + road.car_width / 2 + side * 15, .world_y = race.y + road.car_height - race.distance, .vx = side * 15, .vy = 8, .born = race.ticks, .life = 35 });
            }
            if (race.crashes > self.previous_crashes) {
                self.impact_tick = race.ticks;
                for (0..12) |i| {
                    const angle = @as(f32, @floatFromInt(i)) * 2.399;
                    self.emit(.{ .kind = .spark, .x = race.x + road.car_width / 2, .world_y = race.y + 20 - race.distance, .vx = @cos(angle) * 70, .vy = @sin(angle) * 55, .born = race.ticks, .life = 22 });
                }
            }
        }
        self.previous_tick = race.ticks;
        self.previous_crashes = race.crashes;
    }

    pub fn draw(self: *Renderer, race: *const sim.Race, ghost: Ghost) void {
        self.update(race);
        rl.clearBackground(.{ .r = 78, .g = 96, .b = 57, .a = 255 });
        self.view.update(&race.route, race.distance, rl.getFrameTime());
        rl.beginMode2D(self.camera2D());
        self.drawRoute(race);
        self.drawParticles(race, false);
        self.drawPedestrian(race);
        for (race.traffic) |car| {
            if (!car.active) continue;
            const body = race.worldBody(car.body());
            self.vehicle(car.sprite, body.x, body.y, body.heading, .white, true, car.fast);
            lights(body.x, body.y, body.heading, car.braking, if (car.target_lane == car.lane) 0 else if (car.target_lane > car.lane) 1 else -1, race.ticks, car.height());
        }
        if (race.state == .playing and ghost.x >= 0) {
            const body = road.bend(&race.route, ghost.distance, .{ .x = ghost.x, .y = ghost.y, .heading = ghost.heading });
            self.vehicle(0, body.x, body.y, body.heading, .{ .r = 169, .g = 220, .b = 239, .a = 75 }, false, false);
        }
        const tint: rl.Color = if (race.invulnerable > 0 and (race.invulnerable / 6) % 2 == 0) .{ .r = 255, .g = 233, .b = 211, .a = 150 } else .white;
        const player = race.body();
        self.vehicle(0, player.x, player.y, player.heading, tint, true, false);
        lights(player.x, player.y, player.heading, race.braking, 0, race.ticks, road.car_height);
        self.drawParticles(race, true);
        rl.endMode2D();
        if (self.impact_tick) |tick| {
            const age = race.ticks - tick;
            if (age < 10) rl.drawRectangle(0, 0, road.width, road.height, .{ .r = 198, .g = 96, .b = 60, .a = @intCast((10 - age) * 3) });
        }
        drawHud(race);
        self.drawWarnings(race);
        self.drawRouteInfo(race);
    }

    pub fn camera2D(self: *const Renderer) rl.Camera2D {
        return .{ .offset = .{ .x = 400, .y = 480 }, .target = vec(self.view.target), .rotation = -self.view.heading * 180 / std.math.pi, .zoom = self.view.zoom };
    }

    fn drawRoute(self: *const Renderer, race: *const sim.Race) void {
        const origin = race.route.sample(race.distance).center;
        // Lawn is anchored to world coordinates, not camera zoom or frame count.
        var gx = @floor((origin.x - 1600) / 256) * 256;
        while (gx < origin.x + 1600) : (gx += 256) {
            var gy = @floor((origin.y - 1600) / 256) * 256;
            while (gy < origin.y + 1600) : (gy += 256) {
                rl.drawTexturePro(self.grass, .{ .x = 0, .y = 0, .width = @floatFromInt(self.grass.width), .height = @floatFromInt(self.grass.height) }, .{ .x = gx, .y = gy, .width = 256, .height = 256 }, .{ .x = 0, .y = 0 }, 0, .{ .r = 162, .g = 184, .b = 144, .a = 255 });
            }
        }
        var s = @floor((race.distance - 1400) / 20) * 20;
        while (s < race.distance + 1600) : (s += 20) {
            const a = race.route.sample(s);
            const b = race.route.sample(s + 20);
            const curved = @abs(a.curvature) > 0.0007;
            ribbon(a, b, -228, 228, .{ .r = 172, .g = 161, .b = 130, .a = 255 });
            ribbon(a, b, -188, 188, .{ .r = 55, .g = 116, .b = 104, .a = 255 });
            ribbon(a, b, -156, 156, .{ .r = 54, .g = 62, .b = 63, .a = 255 });
            const curb: rl.Color = if (@mod(@floor(s / 40), 2) == 0) .{ .r = 210, .g = 66, .b = 51, .a = 255 } else cream;
            for ([_]f32{ -164, 156 }) |edge| ribbon(a, b, edge, edge + 8, curb);
            for ([_]f32{ -154, 152 }) |edge| ribbon(a, b, edge, edge + 2, cream);
            // Retain three legible overtaking lanes through every corner.
            if (@mod(s, 120) < 40) for ([_]f32{ -52, 52 }) |divider| ribbon(a, b, divider - 1, divider + 1, .{ .r = 210, .g = 220, .b = 211, .a = 105 });
            if (curved and @mod(s, 60) < 20) {
                const edge: f32 = if (a.curvature > 0) -220 else 190;
                ribbon(a, b, edge, edge + 30, .{ .r = 215, .g = 207, .b = 178, .a = 150 });
            }
            for ([_]f32{ -238, 235 }) |edge| ribbon(a, b, edge, edge + 3, .{ .r = 163, .g = 180, .b = 173, .a = 255 });
            if (@mod(s, 200) == 0) for ([_]f32{ -242, 242 }) |edge| rl.drawCircleV(vec(a.offset(edge)), 4, cream);
            if (s >= 0 and s < 40) {
                var x: f32 = -150;
                while (x < 150) : (x += 20) ribbon(a, b, x, x + 20, if (@mod(x + s, 40) == 10) cream else ink);
            }
        }
        s = @floor((race.distance - 1400) / 180) * 180;
        while (s < race.distance + 1600) : (s += 180) {
            const sample = race.route.sample(s);
            for ([_]f32{ -1, 1 }, 0..) |side, i| {
                const point = sample.offset(side * (350 + @mod(@abs(s), 137)));
                const source = tree_sources[@as(usize, @intFromFloat(@mod(@abs(s / 180), 4)))];
                const size: f32 = 90 + @as(f32, @floatFromInt(i)) * 20;
                rl.drawTexturePro(self.trees, source, .{ .x = point.x - size / 2, .y = point.y - size / 2, .width = size, .height = size }, .{ .x = 0, .y = 0 }, 0, .{ .r = 216, .g = 231, .b = 204, .a = 255 });
            }
            if (@mod(s, 1260) == 0) {
                const point = sample.offset(-290);
                for (0..5) |row| {
                    const y = point.y + @as(f32, @floatFromInt(row)) * 9;
                    rl.drawRectangle(@intFromFloat(point.x - 22), @intFromFloat(y), 42, 6, if (row % 2 == 0) cream else .{ .r = 55, .g = 89, .b = 87, .a = 255 });
                }
            }
        }
    }

    fn drawRouteInfo(self: *const Renderer, race: *const sim.Race) void {
        panel(250, 18, 300, 76);
        const upcoming = race.route.preview(race.distance);
        const label: [:0]const u8 = switch (upcoming.kind) {
            .straight => "SHORT STRAIGHT",
            .sweep => "SWEEPING BENDS",
            .corner => "TIGHT CORNERS",
            .chicane => "CHICANE",
        };
        rl.drawText(label, 266, 31, 16, cream);
        var buffer: [80]u8 = undefined;
        const safe = upcoming.guide;
        const text = std.fmt.bufPrintZ(&buffer, "{d:.0} MPH GUIDE   /   {d:.0}m", .{ safe, upcoming.lead / 5 }) catch "";
        rl.drawText(text, 266, 59, 12, if (race.speed > safe + 5) amber else sage);
        // A zoom-independent route strip gives advance information beyond the view.
        panel(666, 18, 116, 168);
        rl.drawText("UP NEXT", 680, 30, 11, sage);
        const base = race.route.sample(race.distance);
        var previous: rl.Vector2 = .{ .x = 724, .y = 170 };
        for (1..41) |i| {
            const sample = race.route.sample(race.distance + @as(f32, @floatFromInt(i)) * 35);
            const dx = sample.center.x - base.center.x;
            const dy = sample.center.y - base.center.y;
            const point: rl.Vector2 = .{ .x = std.math.clamp(724 + (dx * @cos(base.heading) + dy * @sin(base.heading)) * 0.075, 674, 774), .y = 170 - @as(f32, @floatFromInt(i)) * 2.85 };
            rl.drawLineEx(previous, point, 3, if (@abs(sample.curvature) > 0.002) amber else cream);
            previous = point;
        }
        rl.drawCircle(724, 170, 4, cyan);
        if (@import("builtin").cpu.arch != .wasm32) {
            panel(18, 568, 178, 54);
            rl.drawText("-     RESET     +", 31, 581, 13, cream);
            const zoom = std.fmt.bufPrintZ(&buffer, "VIEW {d:.0}%   [ - / 0 / + ]", .{self.view.requested / camera.default_zoom * 100}) catch "";
            rl.drawText(zoom, 29, 605, 9, sage);
        }
    }

    fn vehicle(self: Renderer, sprite: u32, x: f32, y: f32, heading: f32, tint: rl.Color, shadow: bool, fast: bool) void {
        const source = if (fast) fast_sources[sprite % fast_sources.len] else vehicle_sources[sprite % vehicle_sources.len];
        const texture = if (fast) self.open_wheel else self.vehicles;
        const height = if (fast) encounters.fast_height else road.car_height;
        const origin: rl.Vector2 = .{ .x = road.car_width / 2, .y = height / 2 };
        const dest: rl.Rectangle = .{ .x = x + origin.x, .y = y + origin.y, .width = road.car_width, .height = height };
        const degrees = heading * 180.0 / std.math.pi;
        if (shadow) {
            var shade = dest;
            shade.x += 3;
            shade.y += 4;
            rl.drawTexturePro(texture, source, shade, origin, degrees, .{ .r = 0, .g = 0, .b = 0, .a = 95 });
        }
        rl.drawTexturePro(texture, source, dest, origin, degrees, tint);
    }

    fn person(self: Renderer, p: encounters.Pedestrian, x: f32, y: f32, scale: f32, shadow: bool, rotation: f32) void {
        var source = pedestrian_sources[p.appearance * 4 + p.frame()];
        const width = source.width * scale;
        const height = source.height * scale;
        if ((p.side == .right) != (p.phase == .retreating or p.phase == .startled)) source.width *= -1;
        const origin: rl.Vector2 = .{ .x = width / 2, .y = height / 2 };
        var dest: rl.Rectangle = .{ .x = x, .y = y, .width = width, .height = height };
        if (shadow) {
            dest.x += 2;
            dest.y += 3;
            rl.drawTexturePro(self.pedestrians, source, dest, origin, rotation, .{ .r = 0, .g = 0, .b = 0, .a = 90 });
            dest.x -= 2;
            dest.y -= 3;
        }
        if (p.jumping and p.phase == .dashing) {
            const span = @abs(p.targetX() - p.homeX());
            const progress = @abs(p.x - p.homeX()) / span;
            dest.y -= @sin(progress * std.math.pi) * 5;
        }
        rl.drawTexturePro(self.pedestrians, source, dest, origin, rotation, .white);
    }

    fn drawPedestrian(self: Renderer, race: *const sim.Race) void {
        const p = race.pedestrian;
        if (!p.active()) return;
        const sample = race.route.sample(road.station(race.distance, p.y, encounters.pedestrian_size));
        const center = sample.offset(p.x + encounters.pedestrian_size / 2 - 400);
        if (p.phase == .preparing or p.dangerous()) {
            const a = sample.offset(p.homeX() + 9 - 400);
            const b = sample.offset(p.targetX() + 9 - 400);
            rl.drawLineEx(vec(a), vec(b), 2, amber);
            rl.drawCircleLinesV(vec(b), 15, amber);
        }
        // Rotate the torso art with the same road normal as its collision box.
        self.person(p, center.x, center.y, 0.11, true, sample.heading * 180 / std.math.pi);
        if (p.phase == .startled) rl.drawText("WHOOPS!", @intFromFloat(center.x - 24), @intFromFloat(center.y - 30), 12, amber);
    }

    fn drawWarnings(self: Renderer, race: *const sim.Race) void {
        if (race.state == .ready or race.state == .finished) return;
        const p = race.pedestrian;
        if (p.active() and p.phase != .startled and p.y < race.y + road.car_height) {
            const left_side = p.side == .left;
            const x: i32 = 18;
            panel(@floatFromInt(x), 388, 188, 92);
            rl.drawText("CROSSING AHEAD", x + 12, 400, 12, amber);
            rl.drawText(if (p.outer_lane) (if (left_side) "LEFT OUTER LANE" else "RIGHT OUTER LANE") else (if (left_side) "LEFT SHOULDER" else "RIGHT SHOULDER"), x + 12, 422, 12, cream);
            rl.drawText(if (p.phase == .preparing) "WATCH THE ROADSIDE" else "GIVE THEM ROOM", x + 12, 459, 10, sage);
            self.person(p, @as(f32, @floatFromInt(x)) + 164, 441, 0.12, false, 0);
            const world = race.worldBody(p.body());
            const screen = rl.getWorldToScreen2D(.{ .x = world.x + 9, .y = world.y + 9 }, self.camera2D());
            const marker_y = std.math.clamp(screen.y - 30, 110, 570);
            const marker_x = std.math.clamp(screen.x, 230, 570);
            rl.drawCircleV(.{ .x = marker_x, .y = marker_y }, 11, ink);
            rl.drawText("!", @intFromFloat(marker_x - 3), @intFromFloat(marker_y - 8), 18, amber);
            if (p.y < 0) rl.drawTriangle(.{ .x = marker_x, .y = marker_y - 23 }, .{ .x = marker_x - 6, .y = marker_y - 14 }, .{ .x = marker_x + 6, .y = marker_y - 14 }, amber);
        }
        for (race.traffic) |car| {
            if (!car.active or !car.fast or car.y < race.y - 110) continue;
            panel(594, 382, 188, 96);
            rl.drawText("FAST CAR BEHIND", 606, 394, 12, cyan);
            rl.drawText("HOLD YOUR LINE", 606, 417, 13, cream);
            rl.drawText(if (car.speed < car.cruise * 0.6) "WAITING TO PASS" else "WATCH ITS SIGNALS", 606, 450, 10, sage);
            const x = 400 + (road.laneCenter(car.lane) - 400) * self.view.zoom;
            panel(x - 26, 591, 52, 36);
            rl.drawText("FAST", @intFromFloat(x - 16), 609, 11, cyan);
            rl.drawTriangle(.{ .x = x, .y = 593 }, .{ .x = x - 7, .y = 603 }, .{ .x = x + 7, .y = 603 }, cyan);
            if (car.target_lane != car.lane) {
                const target = 400 + (road.laneCenter(car.target_lane) - 400) * self.view.zoom;
                rl.drawLineEx(.{ .x = x, .y = 584 }, .{ .x = target, .y = 584 }, 2, amber);
                rl.drawCircle(@intFromFloat(target), 584, 3, amber);
            }
        }
    }

    fn drawParticles(self: Renderer, race: *const sim.Race, foreground: bool) void {
        for (self.particles) |particle| {
            if (particle.life == 0 or particle.born > race.ticks) continue;
            const age = race.ticks - particle.born;
            if (age >= particle.life or (particle.kind != .tire) != foreground) continue;
            const seconds = @as(f32, @floatFromInt(age)) / 60;
            const fade = 1 - @as(f32, @floatFromInt(age)) / @as(f32, @floatFromInt(particle.life));
            const sample = race.route.sample(486 - particle.world_y - particle.vy * seconds);
            const point = sample.offset(particle.x + particle.vx * seconds - 400);
            const x = point.x;
            const y = point.y;
            switch (particle.kind) {
                .tire => rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), 2, particle.length, .{ .r = 14, .g = 20, .b = 21, .a = @intFromFloat(65 * fade) }),
                .dust => rl.drawCircleGradient(.{ .x = x, .y = y }, 4 + seconds * 21, .{ .r = 183, .g = 168, .b = 128, .a = @intFromFloat(100 * fade) }, .{ .r = 183, .g = 168, .b = 128, .a = 0 }),
                .spark => rl.drawLineEx(.{ .x = x, .y = y }, .{ .x = x - particle.vx * 0.035, .y = y - particle.vy * 0.035 }, 1.5, .{ .r = 255, .g = 211, .b = 128, .a = @intFromFloat(230 * fade) }),
            }
        }
    }
};

fn vec(point: road.route.Point) rl.Vector2 {
    return .{ .x = point.x, .y = point.y };
}

fn ribbon(a: road.route.Sample, b: road.route.Sample, left: f32, right: f32, color: rl.Color) void {
    const al = vec(a.offset(left));
    const ar = vec(a.offset(right));
    const bl = vec(b.offset(left));
    const br = vec(b.offset(right));
    rl.drawTriangle(al, ar, br, color);
    rl.drawTriangle(al, br, bl, color);
}

fn lamp(x: f32, y: f32, heading: f32, dx: f32, dy: f32, color: rl.Color) void {
    const center: rl.Vector2 = .{ .x = x + road.car_width / 2 + dx * @cos(heading) - dy * @sin(heading), .y = y + road.car_height / 2 + dx * @sin(heading) + dy * @cos(heading) };
    rl.drawCircleGradient(center, 5, .{ .r = color.r, .g = color.g, .b = color.b, .a = 75 }, .{ .r = color.r, .g = color.g, .b = color.b, .a = 0 });
    rl.drawCircleV(center, 1.8, color);
}

fn lights(x: f32, y: f32, heading: f32, braking: bool, signal: i32, ticks: u32, height: f32) void {
    const origin_y = y + (height - road.car_height) / 2;
    if (braking) for ([_]f32{ -12, 12 }) |dx| lamp(x, origin_y, heading, dx, 29, .{ .r = 255, .g = 57, .b = 34, .a = 255 });
    if (signal != 0 and ticks % 30 < 18) {
        for ([_]f32{ -26, 27 }) |dy| lamp(x, origin_y, heading, @as(f32, @floatFromInt(signal)) * 17, dy, .{ .r = 255, .g = 193, .b = 59, .a = 255 });
    }
}

fn panel(x: f32, y: f32, width: f32, height: f32) void {
    rl.drawRectangleRounded(.{ .x = x, .y = y, .width = width, .height = height }, 0.12, 12, ink);
}

fn drawHud(race: *const sim.Race) void {
    panel(18, 18, 200, 130);
    rl.drawText(if (race.state == .ready) "CIRCUIT / 90" else if (race.invulnerable > 0) "RECOVERING" else switch (encounters.pace(race.ticks)) {
        .opening => "SETTLE IN",
        .building => "PICKING UP",
        .rush => "FINAL PUSH",
        .breather => "TAKE A BREATH",
    }, 32, 32, 13, if (race.invulnerable > 0) amber else sage);
    var buffer: [96]u8 = undefined;
    const score = std.fmt.bufPrintZ(&buffer, "{d}", .{race.score}) catch "0";
    rl.drawText(score, 30, 55, 38, cream);
    const time = std.fmt.bufPrintZ(&buffer, "{d}s LEFT     x{d} CLEAN", .{ (sim.duration_ticks - race.ticks + 59) / 60, race.multiplier() }) catch "";
    rl.drawText(time, 32, 108, 14, sage);
    rl.drawRectangle(32, 133, @intFromFloat(172 * (1 - @as(f32, @floatFromInt(race.ticks)) / sim.duration_ticks)), 2, sage);
    panel(594, 502, 188, 120);
    rl.drawText("GROUND SPEED", 610, 517, 12, sage);
    const speed = std.fmt.bufPrintZ(&buffer, "{d:0>2.0}", .{race.speed}) catch "0";
    rl.drawText(speed, 609, 536, 42, cream);
    rl.drawText("MPH", 691, 559, 13, sage);
    for (0..18) |i| rl.drawRectangle(610 + @as(i32, @intCast(i)) * 9, 593, 6, 9, if (race.speed >= @as(f32, @floatFromInt(i)) * 5) sage else .{ .r = 62, .g = 77, .b = 60, .a = 255 });
    if (race.award_ticks > 0) {
        const award = std.fmt.bufPrintZ(&buffer, "+{d}", .{race.last_award}) catch "";
        rl.drawText(award, 32, 191, 18, sage);
    }
}
