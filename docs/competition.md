# Competition architecture

## Simulation and score contract

`src/race.zig` is the authoritative game simulation. A run has 180 countdown ticks and 5,400 race ticks at 60 Hz. Rendering and audio never draw from the traffic PRNG. Xorshift32 traffic generation consumes the same three values at fixed spawn ticks regardless of driving input or whether the traffic pool has room. Display frames accumulate into simulation ticks; pauses freeze the accumulator and stalls longer than 500 ms pause instead of discarding game time.

Each traffic object remembers whether it has collided or awarded points and its closest gap between rotated collision shapes while beside the player. Only a clean pass behind the player awards. A collision grants 60 recovery ticks, reduces speed, and resets the streak; touching another car during recovery marks that car ineligible for points without adding another crash.

`tiny_*` exports form the browser boundary. Metric 17 is the bridge version (5); state values are ready=0, countdown=1, playing=2, paused=3, finished=4. Input bits are left=1, right=2, accelerate=4, brake=8. Browser code never calculates the live score. UI polling reads Zig metrics; the optional ghost samples x/y/heading/distance every six ticks and only affects rendering. Metric 18 returns body angle in radians. Metric 19 returns sideways velocity. Metrics 20–27 expose encounter counters and the pedestrian phase/position. Metric 28 contains warning flags: left=1, right=2, outer lane=4, fast behind=8, fast yielding=16. Metric 29 is opening=0, building=1, rush=2, breather=3. Metrics 30–36 return active fast-car y, speed, lane, target lane, age, signal, and merge progress; absent cars return y=-1000 and zero for the remaining fields. `Race.metric` supplies both browser metrics and native replay references. `tiny_ghost(x, y, heading, distance)` accepts four floats. Metrics 37–39 return route distance, centerline curvature, and the local speed guide. Metrics 40–42 return preview kind (straight=0, sweep=1, corner=2, chicane=3), distance ahead, and speed guide. `tiny_zoom(value)` clamps presentation scale to 0.65–1.05 (default 0.82). `tiny_camera_metric(0..4)` reads current zoom, requested zoom, heading, target x, and target y; none are simulation state. Playback blends valid samples and hides malformed samples.

The competition version is `score-attack-v5`. Update it in both `web/app.js` and `server/service.mjs`, and increment `simulation.version` plus the bridge check when changing balance, timing, or traffic rules. Existing challenges with a previous competition version are rejected rather than mixed into a new leaderboard.

## Road and traffic

`src/route.zig` generates a seeded route in 20-pixel arc-length samples. `src/road.zig` defines three lane centers, road edges, vehicle size, and rotated collision shapes, and maps every local body to the shared route normal. The renderer draws those same centers and headings. Roadside slowdown checks all four visible body corners against the curved edge. Both simulation and rendering use this file. Vehicle art occupies a 38 by 72 pixel area. Collision shapes allow a two-pixel margin at each side for mirrors and bumpers.

Curves progressively add outward drift proportional to speed squared and the curvature of the chosen line. An inside line has a smaller radius. Runoff slows sustained curb use, especially near tight corners.

Traffic reserves its starting and target lanes throughout a signal and merge. It checks both gaps and closing speeds before choosing a lane. The player can affect traffic responses and available spawn space. Spawn attempt times and random consumption remain independent of input. Each 90-second run makes exactly 113 attempts. A blocked entrance or full pool skips an attempt without another random draw.

A separate encounter PRNG consumes four values per attempt. Fixed intervals shorten from 360 to 270 to 210 ticks across the three 30-second stages. The final 240 ticks of every 900-tick wave skip new ordinary and special spawns while retaining every scheduled random draw. Pedestrian escape reservations can also skip ordinary spawns. The 113-attempt score ceiling remains valid because fast cars never award points.

Pedestrians warn for at least 150 ticks and prepare visibly for at least 24 ticks. They require a clear, reachable escape corridor for 60 consecutive ticks before entry, recheck existing traffic, and reserve the escape lane. The corridor check covers both lanes of merges, a reaction allowance, lateral travel, and possible longitudinal closing. Unsafe crossings remain harmless roadside preparation.

Open-wheel cars start well behind the player and remain below the screen for their 150-tick warning. They use stopping-distance reservations, stronger braking, and the same hard following floors as ordinary traffic. Their sprites and oriented bodies are 38 by 88 pixels.

Pedestrian placement searches forward for a mild section and rechecks the approach before entry. Its conservative visible-preparation window works at maximum zoom, and danger never depends on actual camera settings. Traffic reserves extra longitudinal room before inside lanes compress. Fast cars brake before tight sections; new lane changes wait for sufficiently gentle road.

A one-second signal precedes a two-second merge. The simulation rechecks safety before movement. A nearby player can pause lateral movement during a merge. Following uses a snapshot of the previous tick. Normal braking is gradual. A minimum gap limits movement after a sudden stop.

`src/render.zig` owns textures, shadows, lights, and short-lived visual effects. Every ground layer uses `race.distance`. Mirrored adjacent tiles share edge pixels without requiring repeating textures in WebGL.

## API

The local Node server mounts these under `/api`. API Gateway uses the same handlers at its root. `config.js` selects the base URL.

| Method and path                                           | Behavior                                                      |
| --------------------------------------------------------- | ------------------------------------------------------------- |
| `GET /health`                                             | Current version and availability                              |
| `POST /groups`                                            | Validate a name, create a random invitation ID and seed       |
| `GET /groups/:id`                                         | Challenge name, seed, version                                 |
| `POST /groups/:id/runs`                                   | Start a timed run using nickname and device player token      |
| `GET /groups/:id/board?period=week\|all&player=:publicId` | Best per player, rank, gap, and personal rank; up to 100 rows |
| `POST /runs/:runToken/result`                             | Validate and idempotently accept a completed result           |

Input bodies must be JSON objects. Names are trimmed and length-limited; the frontend renders them with `textContent`. The service validates every numeric stat, the full 5,400 ticks, score-component arithmetic, bounds, seed and version. The pass limit matches the 113 spawn attempts. Multiplier points must fit the reported best streak. It rejects submission earlier than 92 seconds after the server-issued run (allowing one second of timing tolerance around the three-second countdown and 90-second race). Sessions expire 30 minutes from issuance, including pauses.

A random 128-bit token identifies a browser installation. The public player ID is a SHA-256-derived identifier. The token is only sent to create a run; results use an unpredictable 128-bit run token. Neither secret token appears in leaderboard responses. Nicknames are not unique account credentials. Clearing storage creates a new identity.

## Persistence and rankings

Local development uses `.local/scores.json`, ignored by Git, with serialized atomic file replacements. Run one local server per data file. Production uses an on-demand DynamoDB table with `pk`/`sk` keys:

| Partition             | Sort key           | Value                                    |
| --------------------- | ------------------ | ---------------------------------------- |
| `GROUP#id`            | `META`             | Group metadata, seed, version            |
| `RUN#token`           | `META`             | Session, player ID, server start, expiry |
| `BOARD#group#version` | SHA-256(run token) | Immutable accepted result                |

DynamoDB TTL cleans up expired run sessions. A conditional result insert prevents concurrent retries or later resubmissions from replacing an accepted score. Reads use consistent, paginated queries. The best score per player is selected separately for all time and the current UTC Monday-based week. Equal scores share a competition rank; stable order uses finish time then player ID. The API also returns a player's rank outside the first 100 rows.

All results are retained so weekly records and all-time records can be computed independently. This simple query-and-reduce design is for small friend groups. At larger scale, maintain best-score indexes per week and version instead of reading a group's full history. API Gateway throttles requests to 10 per second with a burst of 20.

## Local recovery and trust

Best runs and their ghosts remain on the device even if the API goes offline. Version, challenge, and seed separate storage keys. The browser ignores incompatible bests and does not retry pending submissions from older rules. An online session's failed result is queued in browser storage and retried from the result screen or after reload, until the 30-minute expiry. A run that starts without the API has no server-issued session and stays local. Saving is independent of ranking: a valid worse run is accepted without replacing the best.

Invitation links are bearer access to a group, and device identities are not accounts. Basic validation limits accidents and obvious invalid submissions; it cannot stop fabricated plausible results, multiple identities, or a modified WebAssembly client. Stronger competition would require recording and replaying input on the server, authentication, and abuse controls. There are no prizes or high-trust rankings in this release.

## Browser APIs and hosting references

- [SST HTTP API](https://sst.dev/docs/component/aws/apigatewayv2/)
- [SST static-site environment variables](https://sst.dev/docs/component/aws/static-site/)
- [MDN Page Visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API)
- [MDN pointer events and capture](https://developer.mozilla.org/en-US/docs/Web/API/Pointer_events)
