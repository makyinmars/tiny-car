const std = @import("std");

// Keep this in sync with the emsdk dependency in build.zig.zon.
const sdk_version = "6.0.9";

fn sdkCommand(b: *std.Build, python: []const u8, sdk: *std.Build.Dependency, script: []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{python});
    run.addArg(sdk.path(script).getPath(b));
    // An SDK sourced in the user's shell must not select another toolchain.
    for ([_][]const u8{ "EMSDK", "EMSDK_PYTHON", "EMSDK_NODE", "EM_CACHE", "EMCC_CFLAGS", "EM_COMPILER_WRAPPER" }) |key| {
        run.removeEnvironmentVariable(key);
    }
    run.setEnvironmentVariable("EM_CONFIG", sdk.path(".emscripten").getPath(b));
    return run;
}

fn optimizeFlag(optimize: std.builtin.OptimizeMode) []const u8 {
    return switch (optimize) {
        .Debug => "-O0",
        .ReleaseSafe, .ReleaseFast => "-O3",
        .ReleaseSmall => "-Oz",
    };
}

pub fn build(
    b: *std.Build,
    wasm: *std.Build.Step.Compile,
    raylib: *std.Build.Dependency,
    optimize: std.builtin.OptimizeMode,
    raylib_optimize: std.builtin.OptimizeMode,
) void {
    const sdk = b.dependency("emsdk", .{});
    const python = b.option([]const u8, "python", "Python 3.10+ executable for Emscripten") orelse
        (b.findProgram(&.{ "python3.14", "python3.13", "python3.12", "python3.11", "python3.10", "python3" }, &.{}) catch
            @panic("Emscripten requires Python 3.10+; pass -Dpython=/path/to/python"));

    const install_sdk = sdkCommand(b, python, sdk, "emsdk.py");
    install_sdk.addArgs(&.{ "install", sdk_version });
    const activate_sdk = sdkCommand(b, python, sdk, "emsdk.py");
    activate_sdk.addArgs(&.{ "activate", sdk_version });
    activate_sdk.step.dependOn(&install_sdk.step);

    const emcc = sdkCommand(b, python, sdk, "upstream/emscripten/emcc.py");
    emcc.step.dependOn(&activate_sdk.step);
    emcc.addArgs(&.{
        optimizeFlag(raylib_optimize),
        "-DPLATFORM_WEB",
        "-DGRAPHICS_API_OPENGL_ES2",
        "-DSUPPORT_MODULE_RAUDIO=1",
        "-DSUPPORT_MODULE_RMODELS=0",
        "-sUSE_GLFW=3",
        "-sASYNCIFY=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sINITIAL_MEMORY=134217728",
        "-sMAXIMUM_MEMORY=268435456",
        "-sSTACK_SIZE=1048576",
        "-sEXPORTED_RUNTIME_METHODS=['ccall','requestFullscreen']",
        "-sEXPORTED_FUNCTIONS=['_main','_malloc','_free','_tiny_menu','_tiny_start','_tiny_input','_tiny_pause','_tiny_resume','_tiny_volume','_tiny_metric','_tiny_ghost']",
    });
    if (optimize == .Debug or optimize == .ReleaseSafe) {
        emcc.addArgs(&.{ "-sASSERTIONS=1", "-sSTACK_OVERFLOW_CHECK=2" });
    }
    if (optimize == .Debug) emcc.addArg("-g");
    emcc.addArg("-I");
    emcc.addDirectoryArg(raylib.path("src"));
    for ([_][]const u8{ "rcore.c", "rshapes.c", "rtextures.c", "rtext.c", "raudio.c" }) |source| {
        emcc.addFileArg(raylib.path(b.fmt("src/{s}", .{source})));
    }
    emcc.addArtifactArg(wasm);
    emcc.addArg("--shell-file");
    emcc.addFileArg(b.path("src/shell.html"));
    emcc.addArg("--preload-file");
    emcc.addDecoratedDirectoryArg("", b.path("resources"), "@resources");
    emcc.addArg("-o");
    const html = emcc.addOutputFileArg("index.html");
    const install_web = b.addInstallDirectory(.{
        .source_dir = html.dirname(),
        .install_dir = .{ .custom = "web" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install_web.step);
    const install_ui = b.addInstallDirectory(.{
        .source_dir = b.path("web"),
        .install_dir = .{ .custom = "web" },
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install_ui.step);

    const emrun = sdkCommand(b, python, sdk, "upstream/emscripten/emrun.py");
    emrun.addArg(b.getInstallPath(.{ .custom = "web" }, "index.html"));
    emrun.step.dependOn(b.getInstallStep());
    b.step("emrun", "Build and run in the browser").dependOn(&emrun.step);
}
