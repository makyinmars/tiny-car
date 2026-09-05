//! Deterministic encounter vocabulary and timing; no presentation dependencies.
const std = @import("std");
const road = @import("road.zig");

pub const warning_ticks = 150;
pub const visible_preparation_ticks = 24;
pub const clear_escape_ticks = 60;
pub const pedestrian_size: f32 = 18;
pub const pedestrian_draw_size: f32 = 30;
pub const fast_width: f32 = 38;
pub const fast_height: f32 = 88;
pub const fast_entry_y: f32 = 740;
pub const cycle_ticks = 900;

pub const Pace = enum { opening, building, rush, breather };
pub fn pace(ticks: u32) Pace {
    if (ticks % cycle_ticks >= 660) return .breather;
    return if (ticks < 1800) .opening else if (ticks < 3600) .building else .rush;
}

pub fn interval(ticks: u32) u32 {
    return if (ticks < 1800) 360 else if (ticks < 3600) 270 else 210;
}

pub const Side = enum { left, right };
pub const Phase = enum { inactive, preparing, dashing, waiting, retreating, startled };
pub const Pedestrian = struct {
    phase: Phase = .inactive,
    side: Side = .left,
    outer_lane: bool = false,
    jumping: bool = false,
    appearance: u32 = 0,
    x: f32 = 0,
    y: f32 = 0,
    born: u32 = 0,
    age: u32 = 0,
    phase_ticks: u32 = 0,
    visible_ticks: u32 = 0,
    clear_ticks: u32 = 0,
    entered_tick: ?u32 = null,
    collided: bool = false,

    pub fn active(self: Pedestrian) bool {
        return self.phase != .inactive;
    }

    pub fn lane(self: Pedestrian) u32 {
        return if (self.side == .left) 0 else 2;
    }

    pub fn escapeLane(self: Pedestrian) u32 {
        return if (self.outer_lane) 1 else self.lane();
    }

    pub fn homeX(self: Pedestrian) f32 {
        return if (self.side == .left) road.left - 34 else road.right + 16;
    }

    pub fn targetX(self: Pedestrian) f32 {
        if (self.outer_lane) return road.laneCenter(self.lane()) - pedestrian_size / 2;
        return if (self.side == .left) road.left - 2 else road.right - pedestrian_size + 2;
    }

    pub fn body(self: Pedestrian) road.Body {
        return .{ .x = self.x, .y = self.y, .width = pedestrian_size, .height = pedestrian_size };
    }

    pub fn dangerous(self: Pedestrian) bool {
        return self.phase == .dashing or self.phase == .waiting or self.phase == .retreating;
    }

    pub fn frame(self: Pedestrian) u32 {
        return switch (self.phase) {
            .preparing => if (self.age % 48 < 24) 0 else 1,
            .dashing, .retreating, .startled => 2 + (self.phase_ticks / 7) % 2,
            else => 0,
        };
    }

    pub fn setPhase(self: *Pedestrian, phase: Phase) void {
        self.phase = phase;
        self.phase_ticks = 0;
    }
};

test "pace has a four second lull in every fifteen second wave" {
    for (0..6) |wave| {
        try std.testing.expectEqual(Pace.breather, pace(@intCast(wave * cycle_ticks + 660)));
        try std.testing.expect(pace(@intCast(wave * cycle_ticks)) != .breather);
    }
    try std.testing.expect(interval(0) > interval(2000));
    try std.testing.expect(interval(2000) > interval(4000));
}
