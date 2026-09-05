//! Presentation-only state: never read by Race or its random streams.
const std = @import("std");
const route = @import("route.zig");
pub const minimum: f32 = 0.65;
pub const maximum: f32 = 1.05;
pub const default_zoom: f32 = 0.82;
pub const Camera = struct {
    zoom: f32 = default_zoom,
    requested: f32 = default_zoom,
    target: route.Point = .{},
    heading: f32 = 0,
    initialized: bool = false,

    pub fn setZoom(self: *Camera, value: f32) void {
        if (std.math.isFinite(value)) self.requested = std.math.clamp(value, minimum, maximum);
    }

    pub fn update(self: *Camera, track: *const route.Route, distance: f32, seconds: f32) void {
        const sample = track.sample(distance);
        const blend = 1 - @exp(-6 * std.math.clamp(seconds, 0, 0.1));
        self.zoom += (self.requested - self.zoom) * blend;
        // Track translation is exact so frame stalls cannot lose the player.
        // Heading smoothing eases reversals through the chicanes.
        self.target = sample.center;
        if (!self.initialized) self.heading = sample.heading;
        self.heading += (sample.heading - self.heading) * blend;
        self.initialized = true;
    }
};

test "zoom clamps invalid requests, eases monotonically, resets and never overshoots" {
    const track = route.Route.init(9);
    var camera: Camera = .{};
    camera.setZoom(100);
    try std.testing.expectEqual(maximum, camera.requested);
    camera.update(&track, 2300, 1.0 / 60.0);
    try std.testing.expect(camera.zoom > default_zoom and camera.zoom < maximum);
    camera.setZoom(-100);
    for (0..240) |_| camera.update(&track, 2300, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(minimum, camera.zoom, 0.0001);
    camera.setZoom(std.math.nan(f32));
    try std.testing.expectEqual(minimum, camera.requested);
    camera.setZoom(default_zoom);
    for (0..240) |_| camera.update(&track, 6000, 1.0 / 60.0);
    try std.testing.expectApproxEqAbs(default_zoom, camera.zoom, 0.0001);
}
