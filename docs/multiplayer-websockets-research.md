# Multiplayer WebSocket investigation

Checked: 2026-09-05. Scope: library selection and integration advice for Tiny Car's Zig 0.16.0 native and Emscripten builds. This is research, not an implementation or a verified dependency upgrade.

## Zig library recommendation

**First choice for a Zig multiplayer service: `karlseguin/websocket.zig`.** It is focused on WebSockets and provides both server and native client APIs. Add `http.zig` (module name `httpz`) only if that service needs HTTP routes on the same listener. This is a provisional choice: both projects explicitly describe their Zig 0.16 ports as experimental and insufficiently tested. Their documentation also contains stale version references, so a pinned revision and an interoperability spike are necessary before adoption. [websocket.zig](https://github.com/karlseguin/websocket.zig), [http.zig](https://github.com/karlseguin/http.zig)

| Candidate | Role and fit | Compiler/version evidence | License and assessment |
| --- | --- | --- | --- |
| `websocket.zig` | Dedicated server; native client; text/binary messages, ping/pong, connection/message limits. | README explicitly targets 0.16.0. Actual client source uses `std.Io` and `Io.net.Stream`. Manifest has no minimum Zig version. | MIT. Best focused Zig candidate, subject to compile and runtime checks. |
| `http.zig` / `httpz` | HTTP server integrating the same WebSocket implementation through `upgradeWebsocket`. Useful for room creation, health routes, and upgrades together. | Actual source contains active upgrade implementation and `std.Io` initialization; manifest pins WebSocket revision `b70e733bc0d0ba0a98ff5fe5ef64d3017c85f369`. | MIT. Optional wrapper around the first choice, not a competing WebSocket engine. |
| Zap | HTTP/WebSocket server wrapping the C library facil.io; browser chat example and optional OpenSSL TLS. | Current README says 0.16.0, but recommended tag `v0.11.0` release notes and tagged README say 0.15.1. Tagged manifest reports 0.10.6. | MIT. Credible alternative; resolve the tag/compiler discrepancy before selection. No native Windows support. |
| Tokamak | Broader HTTP framework built over httpz. | Inspected manifest pins httpz `00014146eaf9e17750b752fa4905f7623fbe30f7`; that does not establish current 0.16 compatibility. | Not selected; dependency and compiler support need verification, and the framework adds little for this narrow task. License was not independently verified in this pass. |

Evidence for the table: [WebSocket README](https://github.com/karlseguin/websocket.zig), [WebSocket manifest](https://raw.githubusercontent.com/karlseguin/websocket.zig/master/build.zig.zon), [client source](https://raw.githubusercontent.com/karlseguin/websocket.zig/master/src/client/client.zig), [httpz source](https://raw.githubusercontent.com/karlseguin/http.zig/master/src/httpz.zig), [httpz manifest](https://raw.githubusercontent.com/karlseguin/http.zig/master/build.zig.zon), [Zap README](https://github.com/zigzap/zap), [Zap v0.11.0 release](https://github.com/zigzap/zap/releases/tag/v0.11.0), [Zap tagged manifest](https://raw.githubusercontent.com/zigzap/zap/v0.11.0/build.zig.zon), [Tokamak manifest](https://raw.githubusercontent.com/cztomsik/tokamak/main/build.zig.zon).

## Compatibility and maintenance findings

- Source inspection supports that Karl Seguin's libraries have been migrated to Zig 0.16's I/O interfaces. The httpz dependency pin establishes exactly which WebSocket revision it requests; it does **not** prove that revision compiles with Tiny Car. Pinned WebSocket source and CI workflow retrieval were unavailable in this pass. Neither library was compiled or run locally. [Client implementation](https://raw.githubusercontent.com/karlseguin/websocket.zig/master/src/client/client.zig), [httpz dependency pin](https://raw.githubusercontent.com/karlseguin/http.zig/master/build.zig.zon)
- Current httpz source contains the WebSocket upgrade implementation. Its presence does not establish production readiness. [Current upgrade implementation](https://raw.githubusercontent.com/karlseguin/http.zig/master/src/httpz.zig)
- WebSocket build scripts expose a unit-test target and link libc. Documentation includes handler test helpers and the repository includes Autobahn support assets. These are useful maintenance signals, but no passing 0.16 CI or protocol-conformance result was verified. [Build script](https://raw.githubusercontent.com/karlseguin/websocket.zig/master/build.zig), [repository](https://github.com/karlseguin/websocket.zig)
- Native client source explicitly rejects configured compression, despite compression options appearing in documentation. Leave compression off for an initial small-message protocol. Client source also notes that Windows does not enforce its connect timeout and DNS resolution is not bounded; keep networking off the game loop. [Client source](https://raw.githubusercontent.com/karlseguin/websocket.zig/master/src/client/client.zig)
- Zap has tagged releases and a maintained 0.16 claim on its current branch, but the inspected release is explicitly for 0.15.1. Selecting a released version by name alone would give false confidence about toolchain compatibility. [Current README](https://github.com/zigzap/zap), [v0.11.0 release notes](https://github.com/zigzap/zap/releases/tag/v0.11.0)

## Browser and Emscripten boundary

Use the browser's JavaScript `WebSocket` API in `web/app.js` and bridge messages to Zig. A native Zig networking library belongs in the multiplayer server or desktop client; compiling its socket code to WebAssembly does not give it direct browser TCP access. Emscripten offers a WebSocket C interface through `emscripten/websocket.h` and `-lwebsocket.js` if networking must later be driven from Zig, but the existing JavaScript bridge makes direct browser WebSockets the simpler initial integration. Emscripten's POSIX socket emulation requires additional proxying and has limitations, so it is a poor fit for a fresh game protocol. [Emscripten networking](https://emscripten.org/docs/porting/networking.html)

For an eventual desktop client, evaluate `websocket.zig.Client` behind a native-only adapter and queue received messages into the fixed-step simulation boundary. For the server, retain ownership of rooms, players, scheduling, validation, and message limits in application code; these libraries provide transport rather than multiplayer rules. This is an architecture recommendation inferred from the library roles and Tiny Car's pure simulation boundary.

## Fit with the current game

The following are findings from the current working tree, followed by proposed design choices.

- [`src/race.zig`](../src/race.zig) is a single-player, 60 Hz simulation with compact four-button input. [`src/qa_reference.zig`](../src/qa_reference.zig) already runs it without Raylib, so a native Zig server can reuse simulation code without loading graphics or audio.
- The same seed gives the same route and scheduled random draws. It does **not** give identical traffic when players drive differently: following, merges, pedestrian escape checks, and actual spawns depend on the player. Traffic `y` is relative to that player's progress. A shared race needs explicit world positions and a model containing all players.
- [`web/app.js`](../web/app.js) records ghosts every six ticks (10 Hz). [`tiny_ghost`](../src/main.zig) and [the renderer](../src/render.zig) support one visual ghost. This is a useful starting point for one live opponent, but multiple opponents and simultaneous personal-best playback require extending the bridge.
- [The score service](../server/service.mjs) checks submitted totals and duration; it does not simulate inputs. A position relay would retain this trusted-friends model.
- [Browser focus handling](../web/app.js) and [`Clock.advance`](../src/race.zig) currently pause a local race. Shared multiplayer needs a separate room-clock policy. Existing [replay QA](qa/v5/replay-parity.json) reports native/browser metric matches for several runs; this is useful evidence, not a proof of bit-identical state on every platform.

## Recommended architecture

Use a native Zig process with `websocket.zig` for the game server, after the compatibility spike below. Connect it to the browser transport described above, passing decoded data through explicit Zig exports.

For a shared road, clients send button inputs; the server owns the simulation, traffic, collisions, and final scores. Start with two players, retain the 60 Hz simulation, and try snapshots at 20 Hz with smooth interpolation of opponents and immediate local prediction followed by server corrections. These rates are starting design choices to measure, not library performance claims. Keep socket callbacks and clocks outside the pure simulation; one owner updates each room.

Represent cars by route distance, lateral offset, and body angle, independent of each client's camera. Include room ID, protocol/game version, server tick, input sequence, and last accepted input sequence in the protocol. Define how late inputs, missing inputs, and reconnects work before adding collisions. Send a full state on reconnect; never assume two independently driven `Race` instances are the same world.

WebSocket is suitable for an initial small friends race, but its TCP transport means lost packets can delay newer updates. Keep outbound queues bounded and replace unsent obsolete snapshots. The browser API exposes queued bytes but no automatic backpressure; packets already handed to the transport cannot simply be discarded. Test latency and loss before judging driving feel. [RFC 6455](https://www.rfc-editor.org/rfc/rfc6455), [WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)

## Choose the first playable scope

| Scope | What players experience | Main work |
| --- | --- | --- |
| Live ghost race — suggested first playable experiment | Two players join a room, share a countdown and seed, see each other's live ghost and score. Each keeps their own traffic; opponents cannot collide. | Room lifecycle, 10–20 Hz position relay, timestamp interpolation, results, disconnect handling. |
| Shared road — target for interactive multiplayer | Both players encounter the same traffic and affect one world. Player-to-player contact can be added after this works. | Multi-player simulation model, absolute route positions, server authority, prediction/correction, per-player scoring and safety checks. |

A ghost race is a separate mode, not a completed shared-world implementation. If shared traffic or bumping opponents is the core goal, build the shared-road model directly after the networking spike.

For a ghost-only relay, Node [`ws`](https://github.com/websockets/ws) is also a practical choice because [the local server](../server/local.mjs) already uses Node HTTP. It provides server integration and heartbeat examples. It would not reuse the Zig simulation automatically; the browser still uses its own WebSocket API. Prefer the Zig server when running the same simulation code on the server is the intended next step.

For either live mode, propose a fixed room deadline rather than letting one player pause everyone. A first ghost experiment can mark a participant interrupted on focus loss or a long stall. A shared server can clear input, apply braking, and allow reconnecting to current state. These are proposed multiplayer rules; preserve solo pause behavior and give changed rules their own coordinated simulation/browser/API version and result namespace. A zero input mask currently cruises, so clearing buttons alone does not stop a car.

## Hosting implication

The [current Lambda adapter](../server/lambda.mjs) handles HTTP events, and [documented production hosting](../README.md) uses static files plus API Gateway, Lambda, and DynamoDB. Adding a socket library to that handler does not create a persistent race server.

Keep that score API and host the Zig process as a persistent service, initially a single instance with room state in memory, behind HTTPS/WebSocket support. An AWS Application Load Balancer supports WebSocket upgrades and TLS termination. Deployment would be a separate change in the `fjdev` infrastructure project. [AWS listener documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)

AWS API Gateway **does** offer a separate WebSocket API and can invoke Lambda per message. That is an option for lobbies and event relays, but I would choose a persistent process for the 60 Hz game loop: normal Lambda environments can freeze between invocations, and shared room state would need coordination. This is an architecture recommendation, not a claim that AWS cannot host multiplayer. [API Gateway WebSocket overview](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-websocket-api-overview.html), [Lambda lifecycle](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtime-environment.html)

## Next step before implementation

Run a small, isolated compatibility experiment: pin the chosen library revision, build with Zig 0.16.0, connect two browser clients, exchange text and binary messages, and test heartbeat, abrupt disconnect, slow readers, reconnect, and `wss://` through the intended proxy. For the shared-road path, also run the headless simulation beside active connections and check that slow clients cannot delay its ticks.

Then validate the selected mode through a full 90-second two-player race with latency, a backgrounded tab, and a lost connection. Shared simulation changes require the project's native tests, native/browser replay checks, both builds, and manual runtime validation.

This investigation changed only this research note. No WebSocket dependency was installed, no integration was built or benchmarked, and no infrastructure was deployed.
