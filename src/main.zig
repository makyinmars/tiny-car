const rl = @import("raylib");
const std = @import("std");
const builtin = @import("builtin");
const rendering = @import("render.zig");
const camera = @import("camera.zig");

test {
    _ = @import("grass.zig");
    _ = @import("race.zig");
    _ = @import("camera.zig");
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
var ghost_distance: f32 = 0;
var view: camera.Camera = .{};

export fn tiny_zoom(value: f32) void {
    view.setZoom(value);
}
export fn tiny_camera_metric(key: u32) f64 {
    return switch (key) {
        0 => view.zoom,
        1 => view.requested,
        2 => view.heading,
        3 => view.target.x,
        4 => view.target.y,
        else => 0,
    };
}

export fn tiny_menu() void {
    race = simulation.Race.start(1);
    race.state = .ready;
    view.initialized = false;
    clock = .{};
    web_input = 0;
}
export fn tiny_start(seed: u32) void {
    race = simulation.Race.start(seed);
    view.initialized = false;
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
export fn tiny_ghost(x: f32, y: f32, heading: f32, distance: f32) void {
    const valid = std.math.isFinite(x) and std.math.isFinite(y) and std.math.isFinite(heading) and std.math.isFinite(distance) and distance >= 0 and distance <= 40500;
    ghost_x = if (valid) x else -100;
    ghost_y = if (valid) y else -100;
    ghost_heading = if (valid) std.math.clamp(heading, -simulation.road.max_heading, simulation.road.max_heading) else 0;
    ghost_distance = if (valid) distance else 0;
}
export fn tiny_metric(key: u32) f64 {
    return race.metric(key);
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
    tiny_menu();
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
    const fast_music: ?rl.Music = if (rl.isAudioDeviceReady()) rl.loadMusicStream("resources/sound/open-wheel.wav") catch null else null;
    const pedestrian_alert: ?rl.Sound = if (rl.isAudioDeviceReady()) rl.loadSound("resources/sound/pedestrian-alert.wav") catch null else null;
    const fast_alert: ?rl.Sound = if (rl.isAudioDeviceReady()) rl.loadSound("resources/sound/fast-alert.wav") catch null else null;
    const whoops: ?rl.Sound = if (rl.isAudioDeviceReady()) rl.loadSound("resources/sound/whoops.wav") catch null else null;
    defer {
        if (music) |m| rl.unloadMusicStream(m);
        if (crash_sound) |sound| rl.unloadSound(sound);
        if (brake_sound) |sound| rl.unloadSound(sound);
        if (fast_music) |m| rl.unloadMusicStream(m);
        for ([_]?rl.Sound{ pedestrian_alert, fast_alert, whoops }) |sound| if (sound) |s| rl.unloadSound(s);
    }
    if (music) |m| {
        rl.setMusicVolume(m, 0.35);
        rl.playMusicStream(m);
    }
    if (crash_sound) |sound| rl.setSoundVolume(sound, 0.5);
    if (brake_sound) |sound| rl.setSoundVolume(sound, 0.25);
    if (fast_music) |m| rl.playMusicStream(m);
    for ([_]?rl.Sound{ pedestrian_alert, fast_alert, whoops }) |sound| if (sound) |s| rl.setSoundVolume(s, 0.45);
    var previous_crashes: u32 = 0;
    var previous_pedestrians: u32 = 0;
    var previous_fast: u32 = 0;
    var previous_contacts: u32 = 0;
    var braking = false;
    var reported_finish = false;
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
                    .minus, .kp_subtract => tiny_zoom(view.requested - 0.05),
                    .equal, .kp_add => tiny_zoom(view.requested + 0.05),
                    .zero, .kp_0 => tiny_zoom(camera.default_zoom),
                    .left, .a => tapped.left = true,
                    .right, .d => tapped.right = true,
                    .up, .w => tapped.accelerate = true,
                    .down, .s => tapped.brake = true,
                    else => {},
                }
            }
            if (!rl.isWindowFocused()) tiny_pause();
            const wheel = rl.getMouseWheelMove();
            if (wheel != 0) tiny_zoom(view.requested + wheel * 0.04);
            if (rl.isMouseButtonPressed(.left)) {
                const mouse = rl.getMousePosition();
                if (mouse.y >= 568 and mouse.y <= 622 and mouse.x >= 18 and mouse.x <= 196) {
                    tiny_zoom(if (mouse.x < 65) view.requested - 0.05 else if (mouse.x > 147) view.requested + 0.05 else camera.default_zoom);
                }
            }
        }
        const input: simulation.Input = if (is_wasm) @bitCast(web_input) else .{
            .left = tapped.left or rl.isKeyDown(.left) or rl.isKeyDown(.a),
            .right = tapped.right or rl.isKeyDown(.right) or rl.isKeyDown(.d),
            .accelerate = tapped.accelerate or rl.isKeyDown(.up) or rl.isKeyDown(.w),
            .brake = tapped.brake or rl.isKeyDown(.down) or rl.isKeyDown(.s),
        };
        clock.advance(&race, rl.getFrameTime(), input);
        if (!is_wasm) {
            if (race.state != .finished) reported_finish = false;
            if (race.state == .finished and !reported_finish) {
                std.debug.print("TINY_RECEIPT {{\"version\":{d},\"metrics\":[", .{simulation.version});
                for (0..43) |key| std.debug.print("{s}{d}", .{ if (key == 0) "" else ",", race.metric(@intCast(key)) });
                std.debug.print("]}}\n", .{});
                reported_finish = true;
            }
        }
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
        if (fast_music) |m| {
            var loudness: f32 = 0;
            var pitch: f32 = 1;
            for (race.traffic) |car| if (car.active and car.fast) {
                const distance = @abs(car.y - race.y);
                const proximity = std.math.clamp(1 - distance / 1300, 0, 1);
                loudness = proximity * proximity * 0.32;
                pitch = 0.7 + car.speed / 1200 * 0.6 + (if (car.y > race.y) @as(f32, 0.12) else -0.08);
            };
            rl.setMusicVolume(m, if (running) loudness else 0);
            rl.setMusicPitch(m, pitch);
            rl.updateMusicStream(m);
            if (running) rl.resumeMusicStream(m) else rl.pauseMusicStream(m);
        }
        if (running and race.pedestrian_spawns > previous_pedestrians) {
            if (pedestrian_alert) |sound| rl.playSound(sound);
        }
        if (running and race.fast_spawns > previous_fast) {
            if (fast_alert) |sound| rl.playSound(sound);
        }
        if (race.crashes > previous_crashes) {
            if (race.pedestrian_contacts > previous_contacts) {
                if (whoops) |sound| rl.playSound(sound);
            } else if (crash_sound) |sound| rl.playSound(sound);
        }
        previous_crashes = race.crashes;
        previous_pedestrians = race.pedestrian_spawns;
        previous_fast = race.fast_spawns;
        previous_contacts = race.pedestrian_contacts;
        if (!running) {
            if (crash_sound) |sound| rl.stopSound(sound);
            if (brake_sound) |sound| rl.stopSound(sound);
            for ([_]?rl.Sound{ pedestrian_alert, fast_alert, whoops }) |sound| if (sound) |s| rl.stopSound(s);
        }
        if (running and input.brake and !braking and race.speed > 50) {
            if (brake_sound) |sound| rl.playSound(sound);
        }
        braking = input.brake;
        rl.beginDrawing();
        renderer.view = view;
        renderer.draw(&race, .{ .x = ghost_x, .y = ghost_y, .heading = ghost_heading, .distance = ghost_distance });
        view = renderer.view;
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
            centered("Amber: roadside dash. Cyan: fast car behind. Watch signals.", 438, 14, cream);
            centered("BRAKE BEFORE CORNERS / ZOOM: - + / RESET: 0 / MOUSE WHEEL", 471, 13, sage);
        }
        rl.endDrawing();
    }
}
