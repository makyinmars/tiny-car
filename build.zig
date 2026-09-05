const std = @import("std");
const web = @import("emcc.zig");

fn addAssets(b: *std.Build, exe: *std.Build.Step.Compile) void {
    const assets = [_]struct { []const u8, []const u8 }{
        .{ "resources/sound/brake.mp3", "brake" },
        .{ "resources/sound/car-crash.mp3", "car-crash" },
        .{ "resources/sound/engine.wav", "engine" },
        .{ "resources/textures/cars.png", "cars" },
        .{ "resources/textures/grass.png", "grass" },
        .{ "resources/textures/road.png", "road" },
        .{ "resources/textures/trees.png", "trees" },
    };

    for (assets) |asset| {
        const path, const name = asset;
        exe.root_module.addAnonymousImport(name, .{ .root_source_file = b.path(path) });
    }
}

const App = struct {
    name: []const u8,
    path: std.Build.LazyPath,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const is_wasm = target.result.cpu.arch == .wasm32;

    const raylib_optimize = b.option(
        std.builtin.OptimizeMode,
        "raylib-optimize",
        "Prioritize performance, safety, or binary size (-O flag), defaults to value of optimize option",
    ) orelse optimize;

    const strip = b.option(
        bool,
        "strip",
        "Strip debug info to reduce binary size, defaults to false",
    ) orelse false;

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = raylib_optimize,
        .raudio = true,
    });

    const app = App{
        .name = "tiny_car",
        .path = b.path("src/main.zig"),
    };

    if (is_wasm) {
        // Use the bindings without their transitive Emscripten 4.x build steps.
        const raylib = b.createModule(.{
            .root_source_file = raylib_dep.path("lib/raylib.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const wasm_mod = b.createModule(.{
            .root_source_file = app.path,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        wasm_mod.addImport("raylib", raylib);

        const wasm = b.addLibrary(.{
            .linkage = .static,
            .name = app.name,
            .root_module = wasm_mod,
        });

        addAssets(b, wasm);
        const raylib_source = raylib_dep.builder.dependency("raylib", .{});
        web.build(b, wasm, raylib_source, optimize, raylib_optimize);
    } else {
        const raylib = raylib_dep.module("raylib");
        const raylib_artifact = raylib_dep.artifact("raylib");
        const exe_mod = b.createModule(.{
            .root_source_file = app.path,
            .target = target,
            .optimize = optimize,
            .strip = strip,
        });
        exe_mod.addImport("raylib", raylib);

        const exe = b.addExecutable(.{
            .name = app.name,
            .root_module = exe_mod,
        });
        addAssets(b, exe);
        exe.root_module.linkLibrary(raylib_artifact);
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const test_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("raylib", raylib);

        const unit_tests = b.addTest(.{
            .root_module = test_mod,
        });
        addAssets(b, unit_tests);

        const run_unit_tests = b.addRunArtifact(unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
