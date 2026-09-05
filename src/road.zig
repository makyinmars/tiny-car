//! World-space geometry shared by simulation and renderer. Coordinates are pixels.
const std = @import("std");

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

/// Positive rotation turns the nose right. These same centers/angles draw the sprites.
pub const Body = struct {
    x: f32,
    y: f32,
    heading: f32 = 0,

    /// Separating-axis distance for two oriented footprints. Small mirror/bumper
    /// margins avoid punishing transparent corners; the body rotates with the art.
    pub fn gap(a: Body, b: Body) f32 {
        const ax = [2]f32{ @cos(a.heading), @sin(a.heading) };
        const ay = [2]f32{ -ax[1], ax[0] };
        const bx = [2]f32{ @cos(b.heading), @sin(b.heading) };
        const by = [2]f32{ -bx[1], bx[0] };
        const delta = [2]f32{ b.x - a.x, b.y - a.y };
        const half_width = (car_width - 4) / 2;
        const half_height = (car_height - 4) / 2;
        var separation: f32 = -std.math.inf(f32);
        for ([_][2]f32{ ax, ay, bx, by }) |axis| {
            const ar = half_width * @abs(dot(axis, ax)) + half_height * @abs(dot(axis, ay));
            const br = half_width * @abs(dot(axis, bx)) + half_height * @abs(dot(axis, by));
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
