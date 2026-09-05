const std = @import("std");

pub const Row = struct {
    source_y: f32,
    destination_y: f32,
    height: f32,
};

/// Draw only the visible part of each tile, never sampling past its bottom edge.
pub const Rows = struct {
    texture_height: f32,
    viewport_height: f32,
    source_y: f32,
    destination_y: f32 = 0,

    pub fn init(texture_height: f32, viewport_height: f32, scroll: f32) Rows {
        std.debug.assert(texture_height > 0);
        return .{
            .texture_height = texture_height,
            .viewport_height = viewport_height,
            .source_y = @mod(-scroll, texture_height),
        };
    }

    pub fn next(self: *Rows) ?Row {
        if (self.destination_y >= self.viewport_height) return null;
        const height = @min(self.texture_height - self.source_y, self.viewport_height - self.destination_y);
        const row: Row = .{ .source_y = self.source_y, .destination_y = self.destination_y, .height = height };
        self.destination_y += height;
        self.source_y = 0;
        return row;
    }
};

test "grass rows stay inside the texture and cover the screen without gaps" {
    for ([_]f32{ 1, 249, 640, 1024 }) |texture_height| {
        for ([_]f32{ 0, 1, 137, 248, 249, 500, 1_000_000, -25 }) |scroll| {
            var rows = Rows.init(texture_height, 640, scroll);
            var covered: f32 = 0;
            while (rows.next()) |row| {
                try std.testing.expect(row.source_y >= 0);
                try std.testing.expect(row.height > 0);
                try std.testing.expect(row.source_y + row.height <= texture_height);
                try std.testing.expectEqual(covered, row.destination_y);
                covered += row.height;
            }
            try std.testing.expectEqual(@as(f32, 640), covered);
        }
    }
}

test "positive scroll moves the tile down and wraps cleanly" {
    var rows = Rows.init(249, 640, 10);
    try std.testing.expectEqual(Row{ .source_y = 239, .destination_y = 0, .height = 10 }, rows.next().?);
    try std.testing.expectEqual(Row{ .source_y = 0, .destination_y = 10, .height = 249 }, rows.next().?);
    var wrapped = Rows.init(249, 640, 249);
    try std.testing.expectEqual(@as(f32, 0), wrapped.next().?.source_y);
}
