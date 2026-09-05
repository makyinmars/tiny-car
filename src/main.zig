const rl = @import("raylib");
const std = @import("std");
const builtin = @import("builtin");
const grass = @import("grass.zig");

test {
    _ = @import("grass.zig");
    _ = @import("race.zig");
}

// Compile-time check for WebAssembly target
const is_wasm = builtin.cpu.arch == .wasm32;

// Use c_allocator for WASM (Emscripten provides libc), page_allocator for native
const allocator = if (is_wasm) std.heap.c_allocator else std.heap.page_allocator;

pub const std_options: std.Options = .{
    .logFn = if (is_wasm) webLog else std.log.defaultLog,
};

pub const panic = std.debug.FullPanic(if (is_wasm) webPanic else std.debug.defaultPanic);

fn webPanic(message: []const u8, _: ?usize) noreturn {
    webLog(.err, .default, "panic: {s}", .{message});
    @trap();
}

// Zig 0.16's default logger pulls in unsupported Emscripten process I/O.
fn webLog(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    const prefix = if (scope == .default) "" else "(" ++ @tagName(scope) ++ "): ";
    const message = std.fmt.bufPrintZ(&buffer, prefix ++ format, args) catch "Log message too long";
    rl.traceLog(switch (level) {
        .err => .err,
        .warn => .warning,
        .info => .info,
        .debug => .debug,
    }, "%s", .{message.ptr});
}

const simulation = @import("race.zig");
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 640;
const MAX_SPEED: f32 = 90;
var race: simulation.Race = .{};
var clock: simulation.Clock = .{};
var web_input: u8 = 0;
var volume: f32 = 0.35;
var ghost_x: f32 = -100;
var ghost_y: f32 = -100;

export fn tiny_menu() void {
    race = .{};
    clock = .{};
    web_input = 0;
}
export fn tiny_start(seed: u32) void {
    race = simulation.Race.start(seed);
    clock = .{};
    web_input = 0;
}
export fn tiny_input(input: u32) void {
    web_input = @truncate(input);
}
export fn tiny_pause() void {
    race.pause();
    web_input = 0;
}
export fn tiny_resume() void {
    race.resumeRace();
    clock = .{};
}
export fn tiny_volume(value: f32) void {
    volume = std.math.clamp(value, 0, 1);
}
export fn tiny_ghost(x: f32, y: f32) void {
    ghost_x = x;
    ghost_y = y;
}
export fn tiny_metric(key: u32) f64 {
    return switch (key) {
        0 => @floatFromInt(@intFromEnum(race.state)),
        1 => @floatFromInt(race.score),
        2 => @floatFromInt(race.ticks),
        3 => @floatFromInt(race.multiplier()),
        4 => race.speed,
        5 => @floatFromInt(race.overtakes),
        6 => @floatFromInt(race.near_misses),
        7 => @floatFromInt(race.crashes),
        8 => @floatFromInt(race.base_points),
        9 => @floatFromInt(race.near_points),
        10 => @floatFromInt(race.speed_points),
        11 => @floatFromInt(race.clean_points),
        12 => @floatFromInt(race.best_streak),
        13 => @floatFromInt(race.seed),
        14 => race.x,
        15 => race.y,
        16 => @floatFromInt(race.countdown),
        17 => simulation.version,
        else => 0,
    };
}

// Side enum for grass/roadside rendering
const Side = enum { Left, Right };

// Tile one continuous ground plane; roadside trees provide the depth movement.
fn drawGrass(texture: rl.Texture2D, offset: f32, side: Side) void {
    const roadX = @divFloor(SCREEN_WIDTH, 3);
    const roadRight = roadX * 2;
    const x: f32 = if (side == .Left) 0 else @floatFromInt(roadRight);
    const width: f32 = @floatFromInt(@as(i32, if (side == .Left) roadX else SCREEN_WIDTH - roadRight));
    const tint = rl.Color{ .r = 184, .g = 200, .b = 174, .a = 255 };
    var rows = grass.Rows.init(@floatFromInt(texture.height), SCREEN_HEIGHT, offset);
    while (rows.next()) |row| {
        rl.drawTexturePro(texture, .{ .x = 0, .y = row.source_y, .width = @floatFromInt(texture.width), .height = row.height }, .{ .x = x, .y = row.destination_y, .width = width, .height = row.height }, .{ .x = 0, .y = 0 }, 0, tint);
    }
}

fn drawGrassRoadTransition(scrollOffset: f32) void {
    const roadX = @divFloor(SCREEN_WIDTH, 3);
    const roadWidth = @divFloor(SCREEN_WIDTH, 3);

    // Dirt/gravel transition strip colors
    const dirtColor = rl.Color{ .r = 139, .g = 119, .b = 101, .a = 255 };
    const darkDirtColor = rl.Color{ .r = 100, .g = 85, .b = 70, .a = 255 };

    // Left transition strip (grass to road)
    rl.drawRectangle(roadX - 12, 0, 6, SCREEN_HEIGHT, dirtColor);
    rl.drawRectangle(roadX - 6, 0, 6, SCREEN_HEIGHT, darkDirtColor);

    // Right transition strip (road to grass)
    rl.drawRectangle(roadX + roadWidth, 0, 6, SCREEN_HEIGHT, darkDirtColor);
    rl.drawRectangle(roadX + roadWidth + 6, 0, 6, SCREEN_HEIGHT, dirtColor);

    // Add some animated gravel dots for visual interest
    const dotSpacing: i32 = 40;
    const animOffset = @as(i32, @intFromFloat(@mod(scrollOffset * 0.6, @as(f32, @floatFromInt(dotSpacing)))));

    var y: i32 = -dotSpacing + animOffset;
    while (y < SCREEN_HEIGHT + dotSpacing) : (y += dotSpacing) {
        // Left side gravel dots
        rl.drawCircle(roadX - 9, y, 2, darkDirtColor);
        rl.drawCircle(roadX - 3, y + 20, 1, dirtColor);

        // Right side gravel dots
        rl.drawCircle(roadX + roadWidth + 3, y + 10, 2, darkDirtColor);
        rl.drawCircle(roadX + roadWidth + 9, y + 30, 1, dirtColor);
    }
}

fn drawRoadsideDetails(scrollOffset: f32, side: Side) void {
    const roadX = @divFloor(SCREEN_WIDTH, 3);
    const roadWidth = @divFloor(SCREEN_WIDTH, 3);

    // Seed-based positioning for consistent "random" placement
    const baseX: i32 = if (side == .Left) roadX - 40 else roadX + roadWidth + 20;

    // Draw small roadside markers/posts
    const markerSpacing: i32 = 120;
    const animOffset = @as(i32, @intFromFloat(@mod(scrollOffset * 0.7, @as(f32, @floatFromInt(markerSpacing)))));

    var y: i32 = -markerSpacing + animOffset;
    while (y < SCREEN_HEIGHT + markerSpacing) : (y += markerSpacing) {
        // Road marker post
        const postColor = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 255 };
        const reflectorColor = rl.Color{ .r = 255, .g = 100, .b = 100, .a = 255 };

        rl.drawRectangle(baseX, y, 4, 16, postColor);
        rl.drawRectangle(baseX, y, 4, 4, reflectorColor);
    }

    // Draw grass tufts (darker patches for variety)
    const tuftSpacing: i32 = 60;
    const tuftOffset = @as(i32, @intFromFloat(@mod(scrollOffset * 0.5, @as(f32, @floatFromInt(tuftSpacing)))));

    var ty: i32 = -tuftSpacing + tuftOffset;
    const tuftBaseX: i32 = if (side == .Left) 20 else SCREEN_WIDTH - 60;

    while (ty < SCREEN_HEIGHT + tuftSpacing) : (ty += tuftSpacing) {
        // Darker grass patch
        const darkGrass = rl.Color{ .r = 50, .g = 100, .b = 50, .a = 80 };
        rl.drawEllipse(tuftBaseX + 15, ty, 12, 6, darkGrass);
        rl.drawEllipse(tuftBaseX + 45, ty + 30, 8, 4, darkGrass);
    }
}

fn drawSpeedMotionLines(speed: f32, scrollOffset: f32) void {
    // Only show at high speeds (above 60)
    if (speed < 60) return;

    const intensity = (speed - 60) / (MAX_SPEED - 60); // 0.0 to 1.0
    const alpha = @as(u8, @intFromFloat(intensity * 80));
    const lineColor = rl.Color{ .r = 255, .g = 255, .b = 255, .a = alpha };

    const roadX = @divFloor(SCREEN_WIDTH, 3);

    // Draw motion blur lines on grass areas
    const lineSpacing: i32 = 25;
    const animOffset = @as(i32, @intFromFloat(@mod(scrollOffset * 1.5, @as(f32, @floatFromInt(lineSpacing)))));

    var y: i32 = -lineSpacing + animOffset;
    while (y < SCREEN_HEIGHT + lineSpacing) : (y += lineSpacing) {
        // Left side motion lines
        rl.drawLine(10, y, 10, y + 15, lineColor);
        rl.drawLine(50, y + 8, 50, y + 20, lineColor);
        rl.drawLine(roadX - 30, y + 4, roadX - 30, y + 18, lineColor);

        // Right side motion lines
        rl.drawLine(SCREEN_WIDTH - 10, y + 5, SCREEN_WIDTH - 10, y + 20, lineColor);
        rl.drawLine(SCREEN_WIDTH - 50, y + 12, SCREEN_WIDTH - 50, y + 25, lineColor);
        rl.drawLine(roadX + @divFloor(SCREEN_WIDTH, 3) + 30, y, roadX + @divFloor(SCREEN_WIDTH, 3) + 30, y + 14, lineColor);
    }
}

fn drawRoundedRect(x: i32, y: i32, width: i32, height: i32, roundness: f32, color: rl.Color) void {
    rl.drawRectangleRounded(rl.Rectangle{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(width), .height = @floatFromInt(height) }, roundness, 16, color);
}

fn drawRoad(scrollOffset: f32) void {
    const roadX = @divFloor(SCREEN_WIDTH, 3);
    const roadWidth = @divFloor(SCREEN_WIDTH, 3);

    // Draw main road surface with texture effect
    const roadColor = rl.Color{ .r = 60, .g = 60, .b = 65, .a = 255 };
    rl.drawRectangle(roadX, 0, roadWidth, SCREEN_HEIGHT, roadColor);

    // Draw road shoulders (edges)
    const shoulderColor = rl.Color{ .r = 80, .g = 80, .b = 80, .a = 255 };
    rl.drawRectangle(roadX - 5, 0, 5, SCREEN_HEIGHT, shoulderColor);
    rl.drawRectangle(roadX + roadWidth, 0, 5, SCREEN_HEIGHT, shoulderColor);

    // Draw white side lines (road edges)
    rl.drawRectangle(roadX - 2, 0, 2, SCREEN_HEIGHT, rl.Color.white);
    rl.drawRectangle(roadX + roadWidth, 0, 2, SCREEN_HEIGHT, rl.Color.white);

    // Draw center dashed line
    const lineColor = rl.Color.yellow;
    const dashLength = 30;
    const dashGap = 20;
    const lineWidth = 3;
    const centerX = roadX + @divFloor(roadWidth, 2) - @divFloor(lineWidth, 2);

    // Calculate animation based on scroll offset
    const animatedOffset = @mod(scrollOffset * 2, @as(f32, @floatFromInt(dashLength + dashGap)));

    var y: i32 = -dashLength + @as(i32, @intFromFloat(animatedOffset));
    while (y < SCREEN_HEIGHT + dashLength) : (y += dashLength + dashGap) {
        if (y >= -dashLength and y <= SCREEN_HEIGHT) {
            const drawY = @max(y, 0);
            const drawHeight = @min(y + dashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(centerX, drawY, lineWidth, drawHeight, lineColor);
            }
        }
    }

    // Draw lane dividers (subtle dashed lines)
    const laneColor = rl.Color{ .r = 200, .g = 200, .b = 200, .a = 120 };
    const laneDashLength = 15;
    const laneDashGap = 25;
    const laneWidth = 1;

    // Left lane divider
    const leftLaneX = roadX + @divFloor(roadWidth, 4);
    var laneY: i32 = -laneDashLength + @as(i32, @intFromFloat(animatedOffset * 0.7));
    while (laneY < SCREEN_HEIGHT + laneDashLength) : (laneY += laneDashLength + laneDashGap) {
        if (laneY >= -laneDashLength and laneY <= SCREEN_HEIGHT) {
            const drawY = @max(laneY, 0);
            const drawHeight = @min(laneY + laneDashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(leftLaneX, drawY, laneWidth, drawHeight, laneColor);
            }
        }
    }

    // Right lane divider
    const rightLaneX = roadX + 3 * @divFloor(roadWidth, 4);
    laneY = -laneDashLength + @as(i32, @intFromFloat(animatedOffset * 0.7));
    while (laneY < SCREEN_HEIGHT + laneDashLength) : (laneY += laneDashLength + laneDashGap) {
        if (laneY >= -laneDashLength and laneY <= SCREEN_HEIGHT) {
            const drawY = @max(laneY, 0);
            const drawHeight = @min(laneY + laneDashLength, SCREEN_HEIGHT) - drawY;
            if (drawHeight > 0) {
                rl.drawRectangle(rightLaneX, drawY, laneWidth, drawHeight, laneColor);
            }
        }
    }
}

fn drawSpeedometer(speed: f32, minSpeed: f32, maxSpeed: f32) void {
    const speedoX = SCREEN_WIDTH - 140;
    const speedoY = SCREEN_HEIGHT - 140;
    const speedoRadius = 60;
    const centerX = speedoX + speedoRadius;
    const centerY = speedoY + speedoRadius;

    // Background circle with gradient effect
    const bgColor = rl.Color{ .r = 30, .g = 35, .b = 45, .a = 200 };
    rl.drawCircle(centerX, centerY, @floatFromInt(speedoRadius), bgColor);

    // Outer ring
    rl.drawCircleLines(centerX, centerY, @floatFromInt(speedoRadius), rl.Color{ .r = 100, .g = 150, .b = 255, .a = 255 });
    rl.drawCircleLines(centerX, centerY, @floatFromInt(speedoRadius - 1), rl.Color{ .r = 80, .g = 130, .b = 235, .a = 200 });

    // Speed zones (background arcs)
    const arcStartAngle = 225;
    const arcEndAngle = 495;
    const arcTotalAngle = arcEndAngle - arcStartAngle;

    // Green zone (5-30 MPH)
    const greenEnd = arcStartAngle + (30.0 - minSpeed) / (maxSpeed - minSpeed) * arcTotalAngle;
    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 10), arcStartAngle, greenEnd, 20, rl.Color{ .r = 0, .g = 100, .b = 0, .a = 80 });

    // Yellow zone (30-60 MPH)
    const yellowEnd = arcStartAngle + (60.0 - minSpeed) / (maxSpeed - minSpeed) * arcTotalAngle;
    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 10), greenEnd, yellowEnd, 20, rl.Color{ .r = 100, .g = 100, .b = 0, .a = 80 });

    // Red zone (60-90 MPH)
    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 10), yellowEnd, arcEndAngle, 20, rl.Color{ .r = 100, .g = 0, .b = 0, .a = 80 });

    // Current speed arc
    const speedPercent = (speed - minSpeed) / (maxSpeed - minSpeed);
    const speedAngle = arcStartAngle + (speedPercent * arcTotalAngle);
    const speedColor = if (speed >= 60) rl.Color.red else if (speed >= 30) rl.Color.yellow else rl.Color.green;

    // Draw current speed arc with glow effect
    rl.drawCircleSector(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, @floatFromInt(speedoRadius - 12), arcStartAngle, speedAngle, 16, speedColor);

    // Draw tick marks
    const tickAngles = [_]f32{ 0, 30, 60, 90 };
    for (tickAngles) |tickSpeed| {
        const tickPercent = (tickSpeed - minSpeed) / (maxSpeed - minSpeed);
        const tickAngle = (arcStartAngle + (tickPercent * arcTotalAngle)) * std.math.pi / 180.0;
        const innerRadius = @as(f32, @floatFromInt(speedoRadius - 8));
        const outerRadius = @as(f32, @floatFromInt(speedoRadius - 2));

        const innerX = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerX)) + innerRadius * @cos(tickAngle)));
        const innerY = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerY)) + innerRadius * @sin(tickAngle)));
        const outerX = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerX)) + outerRadius * @cos(tickAngle)));
        const outerY = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerY)) + outerRadius * @sin(tickAngle)));

        rl.drawLineEx(rl.Vector2{ .x = @floatFromInt(innerX), .y = @floatFromInt(innerY) }, rl.Vector2{ .x = @floatFromInt(outerX), .y = @floatFromInt(outerY) }, 2, rl.Color.white);
    }

    // Speed needle with shadow
    const needleAngle = (arcStartAngle + (speedPercent * arcTotalAngle)) * std.math.pi / 180.0;
    const needleLength = @as(f32, @floatFromInt(speedoRadius - 18));
    const needleEndX = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerX)) + needleLength * @cos(needleAngle)));
    const needleEndY = @as(i32, @intFromFloat(@as(f32, @floatFromInt(centerY)) + needleLength * @sin(needleAngle)));

    // Needle shadow
    rl.drawLineEx(rl.Vector2{ .x = @floatFromInt(centerX + 1), .y = @floatFromInt(centerY + 1) }, rl.Vector2{ .x = @floatFromInt(needleEndX + 1), .y = @floatFromInt(needleEndY + 1) }, 4, rl.Color{ .r = 0, .g = 0, .b = 0, .a = 100 });

    // Main needle
    rl.drawLineEx(rl.Vector2{ .x = @floatFromInt(centerX), .y = @floatFromInt(centerY) }, rl.Vector2{ .x = @floatFromInt(needleEndX), .y = @floatFromInt(needleEndY) }, 3, rl.Color.white);

    // Center dot with highlight
    rl.drawCircle(centerX, centerY, 6, rl.Color{ .r = 50, .g = 50, .b = 50, .a = 255 });
    rl.drawCircle(centerX, centerY, 4, rl.Color.white);

    // Digital speed display
    var speedBuffer: [10]u8 = undefined;
    const speedText = std.fmt.bufPrintZ(&speedBuffer, "{d:.0}", .{speed}) catch "?";
    const textWidth = rl.measureText(speedText, 20);
    rl.drawText(speedText, centerX - @divFloor(textWidth, 2), centerY + 20, 20, rl.Color.white);

    // "MPH" label
    rl.drawText("MPH", centerX - 15, centerY + 42, 10, rl.Color.light_gray);
}

fn centered(text: [:0]const u8, y: i32, size: i32, color: rl.Color) void {
    rl.drawText(text, @divFloor(SCREEN_WIDTH - rl.measureText(text, size), 2), y, size, color);
}

pub fn main() if (is_wasm) u8 else anyerror!void {
    if (comptime is_wasm) {
        runGame() catch |err| {
            std.log.err("Game failed: {s}", .{@errorName(err)});
            return 1;
        };
        return 0;
    } else try runGame();
}

fn runGame() !void {
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car / Score Attack");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    rl.setTargetFPS(60);
    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    const car_texture = try rl.loadTexture("resources/textures/car.png");
    defer rl.unloadTexture(car_texture);
    const traffic_texture = try rl.loadTexture("resources/textures/cars.png");
    defer rl.unloadTexture(traffic_texture);
    const grass_texture = try rl.loadTexture("resources/textures/grass.png");
    defer rl.unloadTexture(grass_texture);
    const tree_texture = try rl.loadTexture("resources/textures/trees.png");
    defer rl.unloadTexture(tree_texture);
    const music: ?rl.Music = if (rl.isAudioDeviceReady()) rl.loadMusicStream("resources/sound/speeding.mp3") catch null else null;
    const crash_sound: ?rl.Sound = if (rl.isAudioDeviceReady()) rl.loadSound("resources/sound/car-crash.mp3") catch null else null;
    const brake_sound: ?rl.Sound = if (rl.isAudioDeviceReady()) rl.loadSound("resources/sound/brake.mp3") catch null else null;
    defer {
        if (music) |m| rl.unloadMusicStream(m);
        if (crash_sound) |sound| rl.unloadSound(sound);
        if (brake_sound) |sound| rl.unloadSound(sound);
    }
    if (music) |m| {
        rl.setMusicVolume(m, 0.35);
        rl.playMusicStream(m);
    }
    if (crash_sound) |sound| rl.setSoundVolume(sound, 0.5);
    if (brake_sound) |sound| rl.setSoundVolume(sound, 0.25);
    var previous_crashes: u32 = 0;
    var braking = false;
    const cream = rl.Color{ .r = 240, .g = 234, .b = 220, .a = 255 };
    const sage = rl.Color{ .r = 185, .g = 211, .b = 147, .a = 255 };
    while (!rl.windowShouldClose()) {
        if (!is_wasm) {
            if (rl.isKeyPressed(.space)) {
                if (race.state == .ready or race.state == .finished) tiny_start(20260905) else if (race.state == .paused) tiny_resume();
            }
            if (rl.isKeyPressed(.escape)) {
                if (race.state == .paused) tiny_resume() else tiny_pause();
            }
            if (!rl.isWindowFocused()) tiny_pause();
        }
        const input: simulation.Input = if (is_wasm) @bitCast(web_input) else .{
            .left = rl.isKeyDown(.left) or rl.isKeyDown(.a),
            .right = rl.isKeyDown(.right) or rl.isKeyDown(.d),
            .accelerate = rl.isKeyDown(.up) or rl.isKeyDown(.w),
            .brake = rl.isKeyDown(.down) or rl.isKeyDown(.s),
        };
        clock.advance(&race, rl.getFrameTime(), input);
        const running = race.state == .playing;
        rl.setMasterVolume(volume);
        if (music) |m| {
            rl.setMusicVolume(m, if (running) 0.35 else 0);
            rl.updateMusicStream(m);
        }
        if (race.crashes > previous_crashes) {
            if (crash_sound) |sound| rl.playSound(sound);
        }
        previous_crashes = race.crashes;
        if (running and input.brake and !braking) {
            if (brake_sound) |sound| rl.playSound(sound);
        }
        braking = input.brake;
        rl.beginDrawing();
        rl.clearBackground(.{ .r = 49, .g = 71, .b = 43, .a = 255 });
        const offset = @mod(race.distance, 1920);
        drawGrass(grass_texture, offset, .Left);
        drawGrass(grass_texture, offset, .Right);
        drawGrassRoadTransition(offset);
        drawRoadsideDetails(offset, .Left);
        drawRoadsideDetails(offset, .Right);
        drawRoad(offset);
        drawSpeedMotionLines(race.speed, offset);
        // Decoration has no access to the simulation random stream.
        for (0..22) |i| {
            const x: f32 = if (i % 2 == 0) @floatFromInt(18 + (i * 31) % 182) else @floatFromInt(562 + (i * 29) % 175);
            const y = @mod(@as(f32, @floatFromInt(i * 97)) + race.distance * 0.45, 736) - 64;
            rl.drawTextureRec(tree_texture, .{ .x = @floatFromInt((i % 3) * 48), .y = 0, .width = 48, .height = 48 }, .{ .x = x, .y = y }, .white);
        }
        for (race.traffic) |car| {
            if (!car.active) continue;
            rl.drawTexturePro(traffic_texture, .{ .x = @floatFromInt(car.sprite * 16), .y = 0, .width = 16, .height = 24 }, .{ .x = car.x, .y = car.y, .width = 32, .height = 48 }, .{ .x = 0, .y = 0 }, 0, .white);
        }
        if (running and ghost_x >= 0) {
            rl.drawTexturePro(car_texture, .{ .x = 0, .y = 0, .width = 16, .height = 24 }, .{ .x = ghost_x, .y = ghost_y, .width = 32, .height = 48 }, .{ .x = 0, .y = 0 }, 0, .{ .r = 190, .g = 220, .b = 255, .a = 85 });
        }
        if (race.invulnerable == 0 or (race.invulnerable / 5) % 2 == 0) {
            rl.drawTexturePro(car_texture, .{ .x = 0, .y = 0, .width = 16, .height = 24 }, .{ .x = race.x, .y = race.y, .width = 32, .height = 48 }, .{ .x = 0, .y = 0 }, 0, .white);
        }
        drawRoundedRect(18, 18, 204, 118, 0.12, .{ .r = 20, .g = 33, .b = 29, .a = 235 });
        rl.drawText("SCORE ATTACK / 90 SEC", 32, 31, 12, sage);
        var buf: [96]u8 = undefined;
        const score_text = try std.fmt.bufPrintZ(&buf, "{d}", .{race.score});
        rl.drawText(score_text, 32, 53, 34, cream);
        const time_text = try std.fmt.bufPrintZ(&buf, "{d}s LEFT     x{d} CLEAN", .{ (simulation.duration_ticks - race.ticks + 59) / 60, race.multiplier() });
        rl.drawText(time_text, 32, 104, 14, sage);
        drawSpeedometer(race.speed, 0, 90);
        if (race.award_ticks > 0) {
            const award_text = try std.fmt.bufPrintZ(&buf, "+{d}", .{race.last_award});
            rl.drawText(award_text, @intFromFloat(race.x + 36), @intFromFloat(race.y - 8), 20, sage);
        }
        if (race.state == .countdown) {
            rl.drawRectangle(240, 240, 320, 160, .{ .r = 20, .g = 33, .b = 29, .a = 200 });
            const count = try std.fmt.bufPrintZ(&buf, "{d}", .{(race.countdown + 59) / 60});
            centered(count, 255, 72, cream);
            centered("GET READY", 349, 16, sage);
        }
        if (!is_wasm and (race.state == .ready or race.state == .finished or race.state == .paused)) {
            rl.drawRectangle(0, 0, 800, 640, .{ .r = 14, .g = 26, .b = 21, .a = 200 });
            centered(if (race.state == .ready) "TINY CAR" else if (race.state == .paused) "PAUSED" else "RUN COMPLETE", 245, 40, cream);
            const final_text = try std.fmt.bufPrintZ(&buf, "{d} PTS / {d} PASSES / {d} CRASHES", .{ race.score, race.overtakes, race.crashes });
            if (race.state == .finished) centered(final_text, 315, 20, sage);
            centered(if (race.state == .paused) "SPACE / ESC TO RESUME" else "SPACE TO RACE / ARROWS TO DRIVE", 370, 18, cream);
        }
        rl.endDrawing();
    }
}
