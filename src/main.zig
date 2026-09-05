const rl = @import("raylib");
const std = @import("std");
const builtin = @import("builtin");
const rendering = @import("render.zig");

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
var race: simulation.Race = .{};
var clock: simulation.Clock = .{};
var web_input: u8 = 0;
var volume: f32 = 0.35;
var ghost_x: f32 = -100;
var ghost_y: f32 = -100;
var ghost_heading: f32 = 0;

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
export fn tiny_ghost(x: f32, y: f32, heading: f32) void {
    const valid = std.math.isFinite(x) and std.math.isFinite(y) and std.math.isFinite(heading);
    ghost_x = if (valid) x else -100;
    ghost_y = if (valid) y else -100;
    ghost_heading = if (valid) std.math.clamp(heading, -simulation.road.max_heading, simulation.road.max_heading) else 0;
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
        18 => race.heading,
        19 => race.lateral_velocity,
        else => 0,
    };
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
    // Packaged desktop launchers may start outside the project root.
    if (!is_wasm and !rl.directoryExists("resources")) _ = rl.changeDirectory(rl.getApplicationDirectory());
    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Tiny Car / Score Attack");
    defer rl.closeWindow();
    rl.setExitKey(.null);
    rl.setTargetFPS(60);
    rl.initAudioDevice();
    defer rl.closeAudioDevice();
    var renderer = try rendering.Renderer.init();
    defer renderer.deinit();
    const music: ?rl.Music = if (rl.isAudioDeviceReady()) rl.loadMusicStream("resources/sound/engine.wav") catch null else null;
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
    var engine_pitch: f32 = 0.8;
    const cream = rl.Color{ .r = 240, .g = 234, .b = 220, .a = 255 };
    const sage = rl.Color{ .r = 185, .g = 211, .b = 147, .a = 255 };
    while (!rl.windowShouldClose()) {
        var tapped: simulation.Input = .{};
        if (!is_wasm) {
            // The event queue retains fast down/up taps within one render frame.
            // Polling only the final key state can miss those taps entirely.
            while (true) {
                const key = rl.getKeyPressed();
                if (key == .null) break;
                switch (key) {
                    .space => if (race.state == .ready or race.state == .finished) {
                        tiny_start(20260905);
                    } else if (race.state == .paused) {
                        tiny_resume();
                    },
                    .escape => if (race.state == .paused) {
                        tiny_resume();
                    } else {
                        tiny_pause();
                    },
                    .m => volume = if (volume > 0) 0 else 0.35,
                    .left, .a => tapped.left = true,
                    .right, .d => tapped.right = true,
                    .up, .w => tapped.accelerate = true,
                    .down, .s => tapped.brake = true,
                    else => {},
                }
            }
            if (!rl.isWindowFocused()) tiny_pause();
        }
        const input: simulation.Input = if (is_wasm) @bitCast(web_input) else .{
            .left = tapped.left or rl.isKeyDown(.left) or rl.isKeyDown(.a),
            .right = tapped.right or rl.isKeyDown(.right) or rl.isKeyDown(.d),
            .accelerate = tapped.accelerate or rl.isKeyDown(.up) or rl.isKeyDown(.w),
            .brake = tapped.brake or rl.isKeyDown(.down) or rl.isKeyDown(.s),
        };
        clock.advance(&race, rl.getFrameTime(), input);
        const running = race.state == .playing;
        rl.setMasterVolume(volume);
        if (music) |m| {
            const target_pitch: f32 = 0.65 + race.speed / 90 * 0.95 + (if (input.accelerate) @as(f32, 0.08) else 0);
            engine_pitch += (target_pitch - engine_pitch) * @min(1, rl.getFrameTime() * 6);
            rl.setMusicPitch(m, engine_pitch);
            rl.setMusicVolume(m, if (running) 0.18 + race.speed / 90 * 0.18 else 0);
            rl.updateMusicStream(m);
            if (running) rl.resumeMusicStream(m) else rl.pauseMusicStream(m);
        }
        if (race.crashes > previous_crashes) {
            if (crash_sound) |sound| rl.playSound(sound);
        }
        previous_crashes = race.crashes;
        if (!running) {
            if (crash_sound) |sound| rl.stopSound(sound);
            if (brake_sound) |sound| rl.stopSound(sound);
        }
        if (running and input.brake and !braking and race.speed > 50) {
            if (brake_sound) |sound| rl.playSound(sound);
        }
        braking = input.brake;
        rl.beginDrawing();
        renderer.draw(&race, .{ .x = ghost_x, .y = ghost_y, .heading = ghost_heading });
        var buf: [96]u8 = undefined;
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
            centered(if (race.state == .paused) "SPACE / ESC TO RESUME" else "SPACE TO RACE / ARROWS OR WASD TO DRIVE", 370, 18, cream);
            centered("UP: GAS   DOWN: BRAKE   M: SOUND", 407, 14, sage);
            centered("Steer gently. Watch turn signals. Keep a clean streak.", 438, 14, cream);
        }
        rl.endDrawing();
    }
}
