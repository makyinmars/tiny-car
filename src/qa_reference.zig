//! Native reference for the real-time browser checks. Run:
//! zig run src/qa_reference.zig 2> docs/qa/v5/native-reference.json
const std = @import("std");
const sim = @import("race.zig");

pub fn main() void {
    const cases = [_]struct { name: []const u8, input: sim.Input }{
        .{ .name = "cruise", .input = .{} },
        .{ .name = "gas", .input = .{ .accelerate = true } },
        .{ .name = "left-shoulder", .input = .{ .accelerate = true, .left = true } },
        .{ .name = "right-shoulder", .input = .{ .accelerate = true, .right = true } },
    };
    std.debug.print("[\n", .{});
    for (cases, 0..) |case, index| {
        var race = sim.Race.start(20260905);
        for (0..sim.duration_ticks + 180) |_| race.step(case.input);
        std.debug.print("{{\"name\":\"{s}\",\"metrics\":[", .{case.name});
        for (0..43) |key| std.debug.print("{s}{d}", .{ if (key == 0) "" else ",", race.metric(@intCast(key)) });
        std.debug.print("]}}{s}\n", .{if (index == cases.len - 1) "" else ","});
    }
    std.debug.print("]\n", .{});
}
