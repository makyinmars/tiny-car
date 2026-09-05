//! Presentation only. No simulation mutation and no use of the traffic PRNG.
const rl = @import("raylib");
const std = @import("std");
const sim = @import("race.zig");
const road = sim.road;
const ground = @import("grass.zig");

const cream: rl.Color = .{ .r = 236, .g = 230, .b = 211, .a = 255 };
const sage: rl.Color = .{ .r = 190, .g = 211, .b = 159, .a = 255 };
const ink: rl.Color = .{ .r = 18, .g = 31, .b = 28, .a = 235 };

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

pub const Ghost = struct { x: f32 = -100, y: f32 = -100, heading: f32 = 0 };
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
    particles: [192]Particle = @splat(.{}),
    cursor: usize = 0,
    previous_tick: u32 = 0,
    previous_crashes: u32 = 0,
    impact_tick: ?u32 = null,

    pub fn init() !Renderer {
        const vehicles = try rl.loadTexture("resources/textures/cars.png");
        errdefer rl.unloadTexture(vehicles);
        const trees = try rl.loadTexture("resources/textures/trees.png");
        errdefer rl.unloadTexture(trees);
        const grass = try rl.loadTexture("resources/textures/grass.png");
        errdefer rl.unloadTexture(grass);
        const asphalt = try rl.loadTexture("resources/textures/road.png");
        for ([_]rl.Texture2D{ vehicles, trees, grass, asphalt }) |texture| rl.setTextureFilter(texture, .bilinear);
        return .{ .vehicles = vehicles, .trees = trees, .grass = grass, .asphalt = asphalt };
    }

    pub fn deinit(self: Renderer) void {
        for ([_]rl.Texture2D{ self.vehicles, self.trees, self.grass, self.asphalt }) |texture| rl.unloadTexture(texture);
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
            if (road.onShoulder(race.x) and race.speed > 12 and race.ticks / 4 != self.previous_tick / 4) {
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
        // One unwrapped world distance drives every ground layer. Mirrored tiles
        // avoid seams even at the exact repeat boundary and on WebGL 1.
        for (0..4) |col| drawTiles(self.grass, @as(f32, @floatFromInt(col)) * 256, 256, race.distance, col % 2 != 0, .{ .r = 184, .g = 198, .b = 163, .a = 255 });
        rl.drawRectangle(@intFromFloat(road.left - road.shoulder), 0, @intFromFloat(road.right - road.left + road.shoulder * 2), road.height, .{ .r = 140, .g = 128, .b = 99, .a = 255 });
        drawTiles(self.asphalt, road.left, road.right - road.left, race.distance, false, .{ .r = 184, .g = 189, .b = 186, .a = 255 });
        // Slight wheel-path darkening, continuous rather than moving overlays.
        for (0..road.lane_count) |i| {
            const center = road.laneCenter(@intCast(i));
            for ([_]f32{ -15, 12 }) |dx| rl.drawRectangle(@intFromFloat(center + dx), 0, 4, road.height, .{ .r = 12, .g = 17, .b = 20, .a = 18 });
        }
        for ([_]f32{ road.left + 3, road.right - 5 }) |edge| rl.drawRectangle(@intFromFloat(edge), 0, 2, road.height, cream);
        for (1..road.lane_count) |lane| {
            var y = @mod(race.distance, 108) - 108;
            while (y < road.height) : (y += 108) rl.drawRectangle(@intFromFloat(road.divider(@intCast(lane)) - 1), @intFromFloat(y), 2, 48, .{ .r = 221, .g = 218, .b = 195, .a = 195 });
        }
        var post_y = @mod(race.distance, 160) - 160;
        while (post_y < road.height) : (post_y += 160) {
            for ([_]f32{ road.left - 22, road.right + 18 }) |x| {
                rl.drawRectangle(@intFromFloat(x + 2), @intFromFloat(post_y + 3), 4, 14, .{ .r = 20, .g = 27, .b = 18, .a = 70 });
                rl.drawRectangle(@intFromFloat(x), @intFromFloat(post_y), 4, 12, cream);
                rl.drawRectangle(@intFromFloat(x), @intFromFloat(post_y + 2), 4, 3, .{ .r = 216, .g = 114, .b = 70, .a = 255 });
                rl.drawCircle(@intFromFloat(x + 9), @intFromFloat(post_y + 55), 1.5, .{ .r = 145, .g = 137, .b = 110, .a = 220 });
            }
        }
        // Overhead tree crowns never cover the shoulder or traffic.
        for (0..20) |i| {
            const size: f32 = @floatFromInt(82 + i * 17 % 43);
            const x: f32 = if (i % 2 == 0) @floatFromInt(3 + (i * 43) % 98) else @floatFromInt(590 + (i * 37) % 87);
            const y = @mod(@as(f32, @floatFromInt(i / 2 * 137 + i % 2 * 67)) + race.distance, 1370) - 150;
            const source = tree_sources[(i * 7 + i / 2) % 4];
            rl.drawTexturePro(self.trees, source, .{ .x = x + 5, .y = y + 7, .width = size, .height = size }, .{ .x = 0, .y = 0 }, 0, .{ .r = 10, .g = 23, .b = 17, .a = 75 });
            rl.drawTexturePro(self.trees, source, .{ .x = x, .y = y, .width = size, .height = size }, .{ .x = 0, .y = 0 }, 0, .{ .r = 207, .g = 221, .b = 197, .a = 255 });
        }
        self.drawParticles(race, false);
        for (race.traffic) |car| {
            if (!car.active) continue;
            self.vehicle(car.sprite, car.x, car.y, car.heading, .white, true);
            lights(car.x, car.y, car.heading, car.braking, if (car.target_lane == car.lane) 0 else if (car.target_lane > car.lane) 1 else -1, race.ticks);
        }
        if (race.state == .playing and ghost.x >= 0) self.vehicle(0, ghost.x, ghost.y, ghost.heading, .{ .r = 169, .g = 220, .b = 239, .a = 75 }, false);
        const tint: rl.Color = if (race.invulnerable > 0 and (race.invulnerable / 6) % 2 == 0) .{ .r = 255, .g = 233, .b = 211, .a = 150 } else .white;
        self.vehicle(0, race.x, race.y, race.heading, tint, true);
        lights(race.x, race.y, race.heading, race.braking, 0, race.ticks);
        self.drawParticles(race, true);
        if (self.impact_tick) |tick| {
            const age = race.ticks - tick;
            if (age < 10) rl.drawRectangle(0, 0, road.width, road.height, .{ .r = 198, .g = 96, .b = 60, .a = @intCast((10 - age) * 3) });
        }
        drawHud(race);
    }

    fn vehicle(self: Renderer, sprite: u32, x: f32, y: f32, heading: f32, tint: rl.Color, shadow: bool) void {
        const source = vehicle_sources[sprite % vehicle_sources.len];
        const origin: rl.Vector2 = .{ .x = road.car_width / 2, .y = road.car_height / 2 };
        const dest: rl.Rectangle = .{ .x = x + origin.x, .y = y + origin.y, .width = road.car_width, .height = road.car_height };
        const degrees = heading * 180.0 / std.math.pi;
        if (shadow) {
            var shade = dest;
            shade.x += 3;
            shade.y += 4;
            rl.drawTexturePro(self.vehicles, source, shade, origin, degrees, .{ .r = 0, .g = 0, .b = 0, .a = 95 });
        }
        rl.drawTexturePro(self.vehicles, source, dest, origin, degrees, tint);
    }

    fn drawParticles(self: Renderer, race: *const sim.Race, foreground: bool) void {
        for (self.particles) |particle| {
            if (particle.life == 0 or particle.born > race.ticks) continue;
            const age = race.ticks - particle.born;
            if (age >= particle.life or (particle.kind != .tire) != foreground) continue;
            const seconds = @as(f32, @floatFromInt(age)) / 60;
            const fade = 1 - @as(f32, @floatFromInt(age)) / @as(f32, @floatFromInt(particle.life));
            const x = particle.x + particle.vx * seconds;
            const y = particle.world_y + race.distance + particle.vy * seconds;
            switch (particle.kind) {
                .tire => rl.drawRectangle(@intFromFloat(x), @intFromFloat(y), 2, particle.length, .{ .r = 14, .g = 20, .b = 21, .a = @intFromFloat(65 * fade) }),
                .dust => rl.drawCircleGradient(.{ .x = x, .y = y }, 4 + seconds * 21, .{ .r = 183, .g = 168, .b = 128, .a = @intFromFloat(100 * fade) }, .{ .r = 183, .g = 168, .b = 128, .a = 0 }),
                .spark => rl.drawLineEx(.{ .x = x, .y = y }, .{ .x = x - particle.vx * 0.035, .y = y - particle.vy * 0.035 }, 1.5, .{ .r = 255, .g = 211, .b = 128, .a = @intFromFloat(230 * fade) }),
            }
        }
    }
};

fn drawTiles(texture: rl.Texture2D, x: f32, width: f32, distance: f32, mirror_x: bool, tint: rl.Color) void {
    var tiles = ground.Tiles.init(256, road.height, distance);
    while (tiles.next()) |tile| {
        rl.drawTexturePro(texture, .{ .x = 0, .y = 0, .width = @as(f32, @floatFromInt(texture.width)) * (if (mirror_x) @as(f32, -1) else 1), .height = @as(f32, @floatFromInt(texture.height)) * (if (tile.mirrored) @as(f32, -1) else 1) }, .{ .x = x, .y = tile.y, .width = width, .height = 256 }, .{ .x = 0, .y = 0 }, 0, tint);
    }
}

fn lamp(x: f32, y: f32, heading: f32, dx: f32, dy: f32, color: rl.Color) void {
    const center: rl.Vector2 = .{ .x = x + road.car_width / 2 + dx * @cos(heading) - dy * @sin(heading), .y = y + road.car_height / 2 + dx * @sin(heading) + dy * @cos(heading) };
    rl.drawCircleGradient(center, 5, .{ .r = color.r, .g = color.g, .b = color.b, .a = 75 }, .{ .r = color.r, .g = color.g, .b = color.b, .a = 0 });
    rl.drawCircleV(center, 1.8, color);
}

fn lights(x: f32, y: f32, heading: f32, braking: bool, signal: i32, ticks: u32) void {
    if (braking) for ([_]f32{ -12, 12 }) |dx| lamp(x, y, heading, dx, 29, .{ .r = 255, .g = 57, .b = 34, .a = 255 });
    if (signal != 0 and ticks % 30 < 18) {
        for ([_]f32{ -26, 27 }) |dy| lamp(x, y, heading, @as(f32, @floatFromInt(signal)) * 17, dy, .{ .r = 255, .g = 193, .b = 59, .a = 255 });
    }
}

fn panel(x: f32, y: f32, width: f32, height: f32) void {
    rl.drawRectangleRounded(.{ .x = x, .y = y, .width = width, .height = height }, 0.12, 12, ink);
}

fn drawHud(race: *const sim.Race) void {
    panel(18, 18, 200, 130);
    rl.drawText("ROUTE  /  90", 32, 32, 13, sage);
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
    if (race.invulnerable > 0) {
        panel(596, 26, 184, 42);
        rl.drawText("RECOVERING", 615, 40, 15, cream);
    }
    if (race.award_ticks > 0) {
        const award = std.fmt.bufPrintZ(&buffer, "+{d}", .{race.last_award}) catch "";
        rl.drawText(award, @intFromFloat(race.x + road.car_width + 8), @intFromFloat(race.y - 8), 18, sage);
    }
}
