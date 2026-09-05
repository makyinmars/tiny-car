//! World-space geometry shared by simulation and renderer. Coordinates are pixels.
const std = @import("std");
pub const route = @import("route.zig");

pub const width = 800;
pub const height = 640;
pub const left: f32 = 244;
pub const right: f32 = 556;
pub const lane_count: u32 = 3;
pub const lane_width: f32 = (right - left) / lane_count;
pub const shoulder: f32 = 12;
pub const car_width: f32 = 38;
pub const car_height: f32 = 72;
pub const min_x = left - 8;
pub const max_x = right - car_width + 8;
pub const max_heading: f32 = 8.0 * std.math.pi / 180.0;
pub const pixels_per_mph: f32 = 5;

pub fn laneCenter(lane: u32) f32 {
    std.debug.assert(lane < lane_count);
    return left + (@as(f32, @floatFromInt(lane)) + 0.5) * lane_width;
}

pub fn laneX(lane: u32) f32 {
    return laneCenter(lane) - car_width / 2;
}

pub fn divider(index: u32) f32 {
    return left + @as(f32, @floatFromInt(index)) * lane_width;
}

pub fn onShoulder(x: f32) bool {
    return x < left + 2 or x + car_width > right - 2;
}

/// Local y is a longitudinal station relative to the player's fixed screen-era
/// anchor. Only this conversion gives bodies physical world centers/rotations.
pub fn station(distance: f32, y: f32, body_height: f32) f32 {
    return distance + 486 - y - body_height / 2;
}

pub fn bend(track: *const route.Route, distance: f32, body: Body) Body {
    const sample = track.sample(station(distance, body.y, body.height));
    const center = sample.offset(body.x + body.width / 2 - 400);
    return .{ .x = center.x - body.width / 2, .y = center.y - body.height / 2, .heading = sample.heading + body.heading, .width = body.width, .height = body.height };
}

/// Check the rendered corners against the same curved edge used by the ribbons.
/// Newton projection is bounded near the body's station, away from other bends.
pub fn footprintOnShoulder(track: *const route.Route, distance: f32, local: Body) bool {
    const body = bend(track, distance, local);
    for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sy| {
        const dx = sx * body.width / 2;
        const dy = sy * body.height / 2;
        const point: route.Point = .{ .x = body.x + body.width / 2 + dx * @cos(body.heading) - dy * @sin(body.heading), .y = body.y + body.height / 2 + dx * @sin(body.heading) + dy * @cos(body.heading) };
        var s = station(distance, local.y, local.height) - dy;
        for (0..3) |_| {
            const sample = track.sample(s);
            s += (point.x - sample.center.x) * @sin(sample.heading) - (point.y - sample.center.y) * @cos(sample.heading);
        }
        const sample = track.sample(s);
        const lateral = (point.x - sample.center.x) * @cos(sample.heading) + (point.y - sample.center.y) * @sin(sample.heading);
        if (@abs(lateral) > 154) return true;
    };
    return false;
}

test "curved lane widths and body edges agree at sweeps, corners and chicanes" {
    const track = route.Route.init(20260905);
    for (0..2200) |i| {
        const distance = @as(f32, @floatFromInt(i)) * 20;
        const sample = track.sample(distance);
        const a = sample.offset(-156);
        const b = sample.offset(156);
        try std.testing.expectApproxEqAbs(@as(f32, 312), @sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)), 0.01);
        for (0..3) |lane| {
            const body: Body = .{ .x = laneX(@intCast(lane)), .y = 450 };
            try std.testing.expect(!footprintOnShoulder(&track, distance, body));
            const world = bend(&track, distance, body);
            const center = sample.offset(body.x + car_width / 2 - 400);
            try std.testing.expectApproxEqAbs(center.x, world.x + car_width / 2, 0.001);
            try std.testing.expectApproxEqAbs(center.y, world.y + car_height / 2, 0.005);
        }
        try std.testing.expect(footprintOnShoulder(&track, distance, .{ .x = min_x, .y = 450 }));
        try std.testing.expect(footprintOnShoulder(&track, distance, .{ .x = max_x, .y = 450 }));
    }
}

/// Positive rotation turns the nose right. These same centers/angles draw the sprites.
pub const Body = struct {
    x: f32,
    y: f32,
    heading: f32 = 0,
    width: f32 = car_width,
    height: f32 = car_height,

    /// Separating-axis distance for two oriented footprints. Small mirror/bumper
    /// margins avoid punishing transparent corners; the body rotates with the art.
    pub fn gap(a: Body, b: Body) f32 {
        const ax = [2]f32{ @cos(a.heading), @sin(a.heading) };
        const ay = [2]f32{ -ax[1], ax[0] };
        const bx = [2]f32{ @cos(b.heading), @sin(b.heading) };
        const by = [2]f32{ -bx[1], bx[0] };
        const delta = [2]f32{ b.x + b.width / 2 - a.x - a.width / 2, b.y + b.height / 2 - a.y - a.height / 2 };
        var separation: f32 = -std.math.inf(f32);
        for ([_][2]f32{ ax, ay, bx, by }) |axis| {
            const ar = (a.width - 4) / 2 * @abs(dot(axis, ax)) + (a.height - 4) / 2 * @abs(dot(axis, ay));
            const br = (b.width - 4) / 2 * @abs(dot(axis, bx)) + (b.height - 4) / 2 * @abs(dot(axis, by));
            separation = @max(separation, @abs(dot(delta, axis)) - ar - br);
        }
        return separation;
    }
};

fn dot(a: [2]f32, b: [2]f32) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

test "lane centers sit between the painted dividers" {
    for (0..lane_count) |i| {
        const lane: u32 = @intCast(i);
        try std.testing.expect(laneX(lane) > divider(lane));
        try std.testing.expect(laneX(lane) + car_width < divider(lane + 1));
        try std.testing.expectApproxEqAbs((divider(lane) + divider(lane + 1)) / 2, laneCenter(lane), 0.001);
    }
}

test "collision footprint follows visible rotation and allows clear gaps" {
    const a: Body = .{ .x = 350, .y = 200 };
    const beside: Body = .{ .x = 386, .y = 225 };
    try std.testing.expect(a.gap(beside) > 0);
    try std.testing.expect((Body{ .x = 350, .y = 200, .heading = -max_heading }).gap(beside) < 0);
    try std.testing.expect(a.gap(.{ .x = 350, .y = 267 }) < 0);
    try std.testing.expect(a.gap(.{ .x = 350, .y = 269 }) > 0);
}

test "different sized silhouettes collide about their rendered centers" {
    const player: Body = .{ .x = 300, .y = 300 };
    const fast: Body = .{ .x = 300, .y = 217, .height = 88 };
    try std.testing.expect(player.gap(fast) < 0);
    try std.testing.expectApproxEqAbs(player.gap(fast), fast.gap(player), 0.001);
    const person: Body = .{ .x = 335, .y = 350, .width = 18, .height = 18 };
    try std.testing.expect(player.gap(person) > 0);
    try std.testing.expect((Body{ .x = 300, .y = 300, .heading = -max_heading }).gap(person) < 0);
    try std.testing.expect(player.gap(.{ .x = 311, .y = 332, .width = 18, .height = 18 }) < 0);
}
