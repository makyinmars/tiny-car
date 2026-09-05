# Project Guide

Tiny Car is a 2D score attack racing game built with Zig and Raylib, with native and WebAssembly build targets. Use the current source as the authority when older README or browser instructions disagree with gameplay.

## Toolchain and Commands

- Zig **0.16.0**; minimum version and dependency pins live in `build.zig.zon`.
- raylib-zig **6.0.0** at a pinned revision, with Raylib **6.0.0**.
- Emscripten **6.0.9**, installed and activated by `emcc.zig`. Keep its `sdk_version` in sync with the `emsdk` dependency.
- Web builds require Python **3.10+**; override detection with `-Dpython=/path/to/python3`. Initial builds need network access to fetch dependencies and the SDK.
- Use Bun **1.3.14** for dependencies and package scripts (`bun install --frozen-lockfile`). Keep `bun.lock` as the package lockfile. Node remains the runtime; supported versions are in `package.json`.
- Run `bun run lint` for Oxlint and `bun run format:check` / `bun run format` for Oxfmt. These cover JavaScript and `.mjs` files; Oxfmt also formats CSS and tooling JSON. Use `zig fmt` for Zig. Use `bun run test`, not Bun's built-in `bun test` runner.

Run commands from the project root:

| Command                                               | Purpose                                                     |
| ----------------------------------------------------- | ----------------------------------------------------------- |
| `zig build`                                           | Build the native executable in `zig-out/bin/`               |
| `zig build run`                                       | Build and run the desktop game                              |
| `zig build test`                                      | Run native unit tests, including race and grass regressions |
| `zig build -Dtarget=wasm32-emscripten`                | Build the browser files in `zig-out/web/`                   |
| `zig build emrun -Dtarget=wasm32-emscripten`          | Build and launch the browser version                        |
| `python3 -m http.server 8080 --directory zig-out/web` | Serve the web build at `http://localhost:8080/`             |

Use `-Doptimize=ReleaseSafe` for an optimized build with safety checks. Host the entire `zig-out/web/` directory, including `app.js`, `app.css`, and `config.js`. `bun run build:web` generates the public API configuration. `bun run dev` serves the full game plus file-backed API on port 8081; `bun run test` runs browser-state and API tests.

## Source Map

- `src/race.zig`: Versioned, deterministic simulation with no rendering, audio, clock API, or browser dependencies. Defines `Race`, `Traffic`, packed `Input`, state transitions, scoring, seeded traffic, collision checks, and the fixed-step `Clock` accumulator.
- `src/main.zig`: Raylib initialization, resource lifetime, native input, rendering, audio, simulation integration, and exported `tiny_*` browser functions. Imports the race and grass tests.
- `src/grass.zig`: Pure texture-row iterator for scrolling grass. Tests ensure samples stay within the texture and cover the viewport without gaps.
- `src/shell.html`: Semantic HTML shell for the game, controls, dialogs, results, and friends board.
- `web/app.js` / `web/app.css`: Browser bridge, challenge UI, local storage, controls, ghost sampling, and responsive forest-themed styles.
- `server/service.mjs`: Versioned score API and validation shared by local Node and AWS Lambda adapters.
- `server/file-store.mjs` / `server/lambda.mjs`: Persistent local storage and DynamoDB storage. Production infrastructure lives in the separate `fjdev` SST project.
- `tests/`: Node regression tests for API and browser state.
- `build.zig`: Native executable/test setup and WebAssembly static-library setup.
- `build.zig.zon`: Package metadata and pinned dependencies.
- `emcc.zig`: SDK setup, Raylib C compilation (including `raudio.c`), Emscripten exports, resource preloading, and browser linking. Isolates inherited SDK environment settings and bypasses upstream Emscripten 4.x build steps.

## Gameplay and Invariants

- A run has a three-second countdown followed by **90 seconds at 60 simulation ticks per second**. States are `ready`, `countdown`, `playing`, `paused`, and `finished`.
- Traffic uses a seeded PRNG and a fixed pool of 24 slots. Preserve input-independent spawn timing and random-number consumption, including when the pool is full.
- Clean passes award 50 base points, with near-miss and speed bonuses. Clean streaks raise the multiplier up to 5×. Each traffic car can award only once; collided cars cannot award.
- Collisions use axis-aligned overlap/gap checks. A crash reduces speed, resets the streak, and grants 60 ticks of recovery. Runs end on time; there is no lives counter or score-to-win threshold.
- `Clock.advance` accumulates frame time into fixed steps. Pausing/countdown must not consume race time; frame stalls over 0.5 seconds pause the run.
- Keep simulation behavior independent of rendering and audio. Existing tests cover scoring, seeded replay, pause/restart behavior, traffic scheduling, and equivalent runs at 30, 60, and 144 Hz.

## Controls and Browser Integration

Native controls:

- Arrow keys or WASD: steer; up/W accelerates and moves up, down/S brakes and moves down.
- Space: start from ready/finished, or resume from paused.
- Escape: toggle pause/resume. Losing window focus also pauses.
- Native starts currently use the fixed seed `20260905`.

The browser path takes a packed input mask through `tiny_input`; it does not poll Raylib keyboard input. `tiny_start`, `tiny_pause`, `tiny_resume`, `tiny_volume`, `tiny_metric`, and `tiny_ghost` provide the remaining bridge. Keep the Zig exports, `emcc.zig` export list, and JavaScript callers aligned, including input bits, state values, and metric indices.

Browser inputs are wired through `web/app.js`, including touch pointer capture with cancellation cleanup. Opening instructions, losing focus, or hiding the page pauses the simulation and clears input. Returning does not resume automatically. Keyboard events in nickname fields must never drive the car. Preserve input held through countdown into the race.

Browser audio requires a user gesture. Nickname, volume, mute, ghost preference, and personal bests are persisted locally. Bests and ghosts are scoped to game version, challenge, and seed. Online run tokens and failed submissions are kept out of public leaderboard responses. Always increment the simulation bridge version, browser version, and API version together when changing scoring or simulation rules.

## Assets and Validation

- Raylib loads relative `resources/` paths at runtime. Run the desktop executable from the project root; the web build preloads this directory at `resources` in its virtual filesystem.
- Rendering currently loads `car.png`, `cars.png`, `grass.png`, and `trees.png` from `resources/textures/`. `road.png` and `pear.png` remain packaged but are not loaded by the current renderer.
- Audio uses `brake.mp3`, `car-crash.mp3`, and `speeding.mp3` from `resources/sound/`.
- Preserve the web-specific logging, panic handler, and entry-point handling in `src/main.zig`; Zig 0.16 default process I/O paths are unsupported on Emscripten.
- For simulation changes, run `zig build test`. For build or platform integration changes, check both native and WebAssembly builds. For rendering, controls, or audio changes, also verify the affected runtime manually.
