# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a 2D car racing game built with Zig and Raylib. The player controls a car that navigates through traffic while avoiding collisions and collecting points. The game features advanced collision detection algorithms (AABB, SAT), spatial partitioning with Quadtrees, physics simulation with gravity and momentum, and audio effects.

## Build Commands

### Current Status (As of June 2025)
**Zig Version**: 0.14.1 (latest stable)  
**Dependencies**: raylib-zig (5.6.0-dev) from Not-Nik/raylib-zig#devel  
**Status**: ⚠️ **Migration in Progress** - Build system updated but API migration incomplete

### Native Build (Desktop)
- `zig build` - Build the application for desktop (currently failing due to API migration)
- `zig build run` - Build and run the desktop version
- `zig build test` - Run unit tests

### WebAssembly Build
- `zig build --sysroot "[path to emsdk]/upstream/emscripten"` - Build for web (requires Emscripten)
- The build system automatically detects WASM target and uses emcc for final compilation
- Output is generated in `zig-out/web/` directory as HTML5 game

## Architecture

### Core Components
- **main.zig**: Contains all game logic, rendering, physics, and collision detection
- **raylib.zig**: Thin wrapper around Raylib C library using `@cImport`
- **shell.html**: HTML template for WebAssembly deployment with canvas setup

### Game Systems
- **Physics Engine**: Custom implementation with velocity, acceleration, mass, friction, and gravity
- **Collision Detection**: Multiple algorithms including AABB, SAT, and Quadtree spatial partitioning
- **Asset Management**: Textures and sounds loaded via build system's `addAssets` function
- **Game State**: Lives (9 max), score (win at 1000), vulnerability system after collisions

### Key Data Structures
- `Car`: Player and NPC vehicles with texture, position, and speed/physics
- `Pear`: Particle effects spawned on collisions with physics simulation
- `Quadtree`: Spatial partitioning for optimized collision detection
- `Physics`: Encapsulates velocity, acceleration, mass, friction, and gravity properties

### Controls
- H/L: Move left/right within road boundaries
- K/J: Move up/down (J plays brake sound)
- Game auto-adjusts car speed when on grass vs road

### Assets Structure
All assets are embedded at build time via `addAssets()` function:
- `resources/textures/`: car.png, cars.png, grass.png, road.png, trees.png, pear.png
- `resources/sound/`: brake.mp3, car-crash.mp3, speeding.mp3

## Development Notes

- The build system supports both native (desktop) and WebAssembly targets
- WebAssembly build requires Emscripten sysroot path via `--sysroot` flag
- Uses page allocator for dynamic allocations (ArrayLists, Quadtree nodes)
- Collision detection can be switched between AABB and SAT algorithms
- Physics system is frame-rate independent using delta time
- Game runs at 60 FPS target with scrolling grass textures for movement effect

## Migration Status & Next Steps

### ✅ Completed (June 2025)
1. **Zig 0.14.1 Update**: Successfully upgraded from 0.14.0 to 0.14.1
2. **Dependency Migration**: Updated from direct raylib to raylib-zig wrapper
3. **Build System**: Updated build.zig and build.zig.zon for new dependency structure
4. **Import Updates**: Changed from custom raylib.zig to module import

### 🚧 In Progress - API Migration Required
**Issue**: raylib-zig uses camelCase function names vs. original PascalCase
**Examples of needed changes**:
- `rl.InitWindow()` → `rl.initWindow()`
- `rl.LoadTexture()` → `rl.loadTexture()`
- `rl.DrawText()` → `rl.drawText()`
- `rl.IsKeyDown()` → `rl.isKeyDown()`

### 📋 Remaining Tasks
1. **Systematic API Migration**: Convert all ~100+ raylib function calls from PascalCase to camelCase
2. **Test Compilation**: Verify all functions work with new API
3. **Runtime Testing**: Test game functionality after migration
4. **WASM Compatibility**: Ensure WebAssembly build still works

### 🔧 Migration Helper
Use find/replace with these patterns:
- `rl.([A-Z])` → `rl.\L$1` (convert first letter to lowercase)
- Check raylib-zig documentation for any API changes beyond naming