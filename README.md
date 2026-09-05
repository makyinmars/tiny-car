# Tiny Car

Tiny Car is a 2D racing game built with Zig and Raylib. Pass traffic and score as many points as possible in 90 seconds.

## Gameplay

Each run starts with a three-second countdown. Passing a car without a collision earns 50 base points. Close passes and higher speeds earn bonus points.

Consecutive passes without a collision raise the points multiplier to a maximum of 5×. A crash slows your car and resets that streak. The run ends when time runs out.

Steering depends on speed. The car carries a little sideways momentum and settles when you release the steering key. It cannot slide sideways while stopped. Hold gas to accelerate toward 90 mph, or release it to settle toward a gentle 42 mph cruise. Hold brake to stop. Brake takes priority when both pedals are held.

Traffic uses three marked lanes, slows behind other vehicles, and signals for one second before a lane change. A lane change takes two seconds. Traffic leaves room for approaching vehicles and cancels a signal when the target lane becomes unsafe. During a merge, it yields sideways to a nearby player. Leave space and watch the amber lights.

The gravel shoulder reduces speed. Brake lights, small tire marks, dust, and crash sparks provide feedback. Engine pitch follows speed. These effects do not change traffic randomness or scoring.

## Desktop controls

| Key              | Action                                                        |
| ---------------- | ------------------------------------------------------------- |
| Up arrow or W    | Accelerate toward 90 mph |
| Down arrow or S  | Brake to a stop |
| Left arrow or A  | Steer left |
| Right arrow or D | Steer right |
| Space            | Start a run, start again after a run, or resume after a pause |
| Escape           | Pause or resume |
| M | Mute or restore sound |

The game also pauses when its window loses focus.

## Requirements

The build needs these tools and connections:

- Zig 0.16.0.
- Python 3.10+ for browser builds.
- An internet connection for the first build to download dependencies, which are the external packages that the game needs.

The project uses Raylib 6.0.0 and raylib-zig 6.0.0. You do not need to install Raylib separately. The browser build downloads and activates Emscripten 6.0.9 automatically.

## Build and run

Run the commands below from the project root, the directory that contains `build.zig`.

### Desktop

Build the game:

```bash
zig build
```

The build puts the executable in `zig-out/bin/`. Run it from the project root so that the game can load files from `resources/`. Packaged desktop copies can also place `resources/` beside the executable.

Build and run the game:

```bash
zig build run
```

Run the tests:

```bash
zig build test
```

The tests cover scoring, inertial steering, braking, traffic gaps, safe merges, pause behavior, race timing, rotated collisions, and ground tiles.

### Browser

The browser supports arrow keys/WASD, visible Play/Retry buttons, touch steering and pedals, fullscreen, mute and volume, and automatic pause when you switch tabs or open instructions. Resume is always explicit. Your nickname, settings, road-specific personal best, and a visual ghost of that best run are saved on this device.

Build the browser files:

```bash
zig build -Dtarget=wasm32-emscripten
```

Build and open the page in your browser:

```bash
zig build emrun -Dtarget=wasm32-emscripten
```

For an optimized build that keeps runtime safety protections, run:

```bash
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSafe
```

If the build cannot find Python, pass `-Dpython=/path/to/python3`. You do not need `--sysroot` or shell activation. The first browser build downloads the Emscripten tools and can take a few minutes.

For the complete game and persistent local friends leaderboard, install Bun 1.3.14 and Node.js 24.15+ (22.22.2+ is also supported). Bun installs dependencies and runs package scripts; Node runs the server, build scripts, and tests:

```bash
bun install --frozen-lockfile
bun run build:web
bun run dev
```

Open <http://localhost:8081/>. The local server stores shared results in `.local/scores.json`; restarting it preserves groups and records. Use `PORT=8080 bun run dev` to select a different port. To test from another device on your network, use `HOST=0.0.0.0 bun run dev` and open your computer’s LAN address. A localhost invitation only works on your own computer; deploy the API and website for friends on the internet.

For solo play only, any static server works:

```bash
python3 -m http.server 8080 --directory zig-out/web
```

Then open <http://localhost:8080/> in your browser.

You can also serve the files with Node.js:

```bash
bunx serve zig-out/web
```

Use the address that the command prints.

Host the entire `zig-out/web/` directory: `index.html`, `index.js`, `index.wasm`, `index.data`, `app.js`, `app.css`, and `config.js`. `zig build` copies the UI automatically. `bun run build:web` also writes the public API URL from `TINY_CAR_API_URL` (default `/api`) into `config.js`. Never put secrets in that file.

The page supports reduced motion. Browser audio requires a key press, click, or touch before playback can start.

## Production hosting

The hosting address is <https://tiny-car.franklinj.dev>. The `TinyCar` site in the `fjdev` SST project manages hosting.

To rebuild and publish updates from this machine, run:

```bash
cd /Users/franklin/Development/WebDev/SST/fjdev
bun run diff:tiny-car
bun run deploy:tiny-car
```

SST builds the game in ReleaseSafe mode, injects the score API URL, and uploads the browser files to S3. CloudFront serves the files over HTTPS. Cloudflare manages DNS, which connects the domain name to the site.

These commands exclude the portfolio (`MyWeb`) and include the Tiny Car site, API Gateway, score Lambda, and DynamoDB table. Run `bun install --frozen-lockfile` in the game repository before deploying. If the AWS session expires, run `bun sso`.

If you use another directory layout, set `TINY_CAR_PATH` to the absolute path of this repository. Read the `fjdev` README for setup and local `sst dev` instructions.

## Friends challenges and scoring

Create a challenge, copy its invitation link, and have each friend choose a nickname. Everyone plays the same seeded traffic schedule under the same game version. The board shows one best result per browser identity, shared ranks for tied scores, and the points needed to reach the next rank. The weekly board resets Mondays at 00:00 UTC; all-time records remain.

- Each clean overtake earns **50** points, once per traffic car.
- Passing within **12 game pixels** without contact earns **30** extra points.
- Passing at **60–79 mph** earns **20** extra; **80+ mph** earns **40** extra.
- Every **five** clean passes increases the multiplier for the next pass by 1×, up to **5×**. It applies to all pass bonuses and resets after a crash.
- Collisions slow you down and give one second of recovery. The race continues for the full **90 seconds**.

The post-run receipt separates overtakes, close calls, speed points, and multiplier points. It also reports crashes and improvement over the previous personal best. The optional ghost is a local visual replay on this exact road. It records position and body angle and has no collision or scoring effects. Playback blends between valid samples.

Rules version `score-attack-v3` separates these runs from previous records. Old challenges require a new invitation. Old bests and ghosts remain in their previous storage keys. The browser does not load them into v3 or retry old result submissions. Nickname and sound preferences remain available.

Runs started while the API is unreachable remain local. If submission fails after an online start, the result is queued locally for retry for up to 30 minutes from the start. A visible retry button and automatic retry on reload handle transient failures. Browser storage being cleared also clears your local player identity; a nickname alone does not recover old records.

The server checks run duration, seed, version, numeric limits, score accounting, and duplicate submissions. This is intended for a small trusted group: browser-submitted scores are **not cheat-proof**, and invitation links grant access to nicknames and scores. [Competition architecture](docs/competition.md) describes the API, persistence, and versioning.

## Verification

```bash
bun run lint
bun run format:check
zig build test
zig build
bun run test
bun run build:web
```

Use `bun run format` to format JavaScript, `.mjs` files, CSS, and tooling JSON with Oxfmt. Oxlint checks JavaScript and `.mjs` files; it does not lint CSS. Use `zig fmt` for Zig files. Run `bun run test` to use the project's Node test command; `bun test` selects Bun's own test runner.

Zig tests cover deterministic simulation at 30, 60, and 144 Hz, scoring, handling, safe traffic movement, pause/restart behavior, and traffic scheduling. Node tests cover the API, persistence, ranking, retries, browser inputs, personal bests, and saved settings. Also play a full run in the browser and check phone controls when changing the integration.

## Visual update

The renderer uses a shared road layout, detailed overhead vehicle sprites, four tree crowns, and tiled grass and asphalt. All ground layers use the same traveled distance. The car collision shapes rotate with the visible bodies.

[Before/after captures and runtime notes](docs/driving-v3.md) document the update. [Asset prompts and source rectangles](docs/art-v3.md) describe the new art.

![Tiny Car v3 native gameplay](docs/qa/after-native.jpg)
