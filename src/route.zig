//! Seeded, arc-length road coordinates. Shared by physics, scenery and camera.
const std = @import("std");
pub const spacing: f32 = 20;
pub const count = 2401; // 48 km-equivalent pixels: beyond a maximum-speed run + sightline.
pub const Point = struct { x: f32 = 0, y: f32 = 0 };
pub const Sample = struct {
    center: Point,
    heading: f32,
    curvature: f32,

    pub fn offset(self: Sample, lateral: f32) Point {
        return .{ .x = self.center.x + @cos(self.heading) * lateral, .y = self.center.y + @sin(self.heading) * lateral };
    }
};
pub const Kind = enum { straight, sweep, corner, chicane };
pub const Section = struct { kind: Kind, start: f32, length: f32, amplitude: f32, direction: f32 };
pub const Preview = struct { kind: Kind, lead: f32, guide: f32 };

pub fn section(seed: u32, distance: f32) Section {
    if (distance < 1800) return .{ .kind = .straight, .start = 0, .length = 1800, .amplitude = 0, .direction = 1 };
    const block = @floor((distance - 1800) / 8800);
    const local = distance - 1800 - block * 8800;
    const hash = (seed *% 0x85ebca6b) ^ (@as(u32, @intFromFloat(block)) *% 0x9e3779b9);
    const sign: f32 = if ((hash ^ (hash >> 16)) & 1 == 0) 1 else -1;
    const variation = 0.9 + @as(f32, @floatFromInt((hash >> 8) % 6)) * 0.02;
    const starts = [_]f32{ 0, 2200, 3200, 4800, 5800, 7600 };
    const lengths = [_]f32{ 2200, 1000, 1600, 1000, 1800, 1200 };
    const kinds = [_]Kind{ .sweep, .straight, .corner, .straight, .chicane, .straight };
    const amplitudes = [_]f32{ 0.52, 0, 0.78, 0, 0.48, 0 };
    var index: usize = 0;
    for (starts, 0..) |start, i| if (local >= start) {
        index = i;
    };
    return .{ .kind = kinds[index], .start = 1800 + block * 8800 + starts[index], .length = lengths[index], .amplitude = amplitudes[index] * variation * (if (block == 0) @as(f32, 0.65) else 1), .direction = sign };
}

pub fn angle(seed: u32, distance: f32) f32 {
    const part = section(seed, distance);
    if (part.kind == .straight) return 0;
    const phase = (distance - part.start) / part.length * 2 * std.math.pi * (if (part.kind == .chicane) @as(f32, 2) else 1);
    const wave = @sin(phase);
    // Cubic sine joins straight sections with zero curvature and no steering jolt.
    return part.direction * part.amplitude * wave * wave * wave;
}

pub const Route = struct {
    seed: u32 = 1,
    centers: [count]Point = @splat(.{}),
    headings: [count]f32 = @splat(0),
    curvatures: [count]f32 = @splat(0),

    pub fn init(seed: u32) Route {
        var route: Route = .{ .seed = seed };
        for (0..count) |i| {
            const s = @as(f32, @floatFromInt(i)) * spacing;
            route.headings[i] = angle(seed, s);
            route.curvatures[i] = (angle(seed, s + 2) - angle(seed, s - 2)) / 4;
        }
        for (1..count) |i| {
            const heading = angle(seed, (@as(f32, @floatFromInt(i)) - 0.5) * spacing);
            const previous = route.centers[i - 1];
            route.centers[i] = .{ .x = previous.x + @sin(heading) * spacing, .y = previous.y - @cos(heading) * spacing };
        }
        return route;
    }

    pub fn sample(self: *const Route, distance: f32) Sample {
        if (distance < 0) return .{ .center = .{ .y = -distance }, .heading = 0, .curvature = 0 };
        const clamped = @min(distance, (count - 1) * spacing - 0.01);
        const index: usize = @intFromFloat(clamped / spacing);
        const t = (clamped - @as(f32, @floatFromInt(index)) * spacing) / spacing;
        const a = self.centers[index];
        const b = self.centers[index + 1];
        return .{
            .center = .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t },
            .heading = self.headings[index] + (self.headings[index + 1] - self.headings[index]) * t,
            .curvature = self.curvatures[index] + (self.curvatures[index + 1] - self.curvatures[index]) * t,
        };
    }

    pub fn maxCurvature(self: *const Route, distance: f32, horizon: f32) f32 {
        var peak: f32 = 0;
        var s = distance;
        while (s <= distance + horizon) : (s += 40) peak = @max(peak, @abs(self.sample(s).curvature));
        return peak;
    }

    pub fn safeSpeed(self: *const Route, distance: f32) f32 {
        const curvature = self.maxCurvature(distance, 220);
        return @min(90, @sqrt(150 / @max(curvature, 0.00001)) / 5);
    }

    pub fn preview(self: *const Route, distance: f32) Preview {
        var upcoming = section(self.seed, distance + 260);
        if (upcoming.kind == .straight) upcoming = section(self.seed, upcoming.start + upcoming.length + 1);
        return .{ .kind = upcoming.kind, .lead = @max(0, upcoming.start - distance), .guide = self.safeSpeed(@max(distance, upcoming.start + 180)) };
    }
};

test "route is repeatable, continuous, bounded and leaves every lane unfolded" {
    const route = Route.init(20260905);
    try std.testing.expectEqualDeep(route, Route.init(20260905));
    var peak: f32 = 0;
    var previous = route.sample(0);
    for (1..46000) |i| {
        const sample = route.sample(@floatFromInt(i));
        const dx = sample.center.x - previous.center.x;
        const dy = sample.center.y - previous.center.y;
        try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt(dx * dx + dy * dy), 0.006);
        try std.testing.expect(@abs(sample.curvature) * 180 < 0.75);
        try std.testing.expect(@abs(sample.heading - previous.heading) < 0.005);
        peak = @max(peak, @abs(sample.curvature));
        previous = sample;
    }
    try std.testing.expect(peak > 0.003);
    try std.testing.expect(route.safeSpeed(1800) > route.safeSpeed(12100));
}
