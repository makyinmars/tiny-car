# Competition architecture

## Simulation and score contract

`src/race.zig` is the authoritative game simulation. A run has 180 countdown ticks and 5,400 race ticks at 60 Hz. Rendering and audio never draw from the traffic PRNG. Xorshift32 traffic generation consumes the same three values at fixed spawn ticks regardless of driving input or whether the traffic pool has room. Display frames accumulate into simulation ticks; pauses freeze the accumulator and stalls longer than 500 ms pause instead of discarding game time.

Each traffic object remembers whether it has collided or awarded points and its closest horizontal gap while beside the player. Only a clean pass behind the player awards. A collision grants 60 recovery ticks, reduces speed, and resets the streak; touching another car during recovery marks that car ineligible for points without adding another crash.

`tiny_*` exports form the browser boundary. Metric 17 is the bridge version (2); state values are ready=0, countdown=1, playing=2, paused=3, finished=4. Input bits are left=1, right=2, accelerate=4, brake=8. Browser code never calculates the live score. UI polling reads Zig metrics; the optional ghost samples x/y every six ticks and only affects rendering.

The competition version is `score-attack-v2`. Update it in both `web/app.js` and `server/service.mjs`, and increment `simulation.version` plus the bridge check when changing balance, timing, or traffic rules. Existing challenges with a previous competition version are rejected rather than mixed into a new leaderboard.

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

Input bodies must be JSON objects. Names are trimmed and length-limited; the frontend renders them with `textContent`. The service validates every numeric stat, the full 5,400 ticks, score-component arithmetic, bounds, seed and version. It rejects submission earlier than 92 seconds after the server-issued run (allowing one second of timing tolerance around the three-second countdown and 90-second race). Sessions expire 30 minutes from issuance, including pauses.

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

Best runs and their ghosts remain on the device even if the API goes offline. An online session's failed result is queued in browser storage and retried from the result screen or after reload, until the 30-minute expiry. A run that starts without the API has no server-issued session and stays local. Saving is independent of ranking: a valid worse run is accepted without replacing the best.

Invitation links are bearer access to a group, and device identities are not accounts. Basic validation limits accidents and obvious invalid submissions; it cannot stop fabricated plausible results, multiple identities, or a modified WebAssembly client. Stronger competition would require recording and replaying input on the server, authentication, and abuse controls. There are no prizes or high-trust rankings in this release.

## Browser APIs and hosting references

- [SST HTTP API](https://sst.dev/docs/component/aws/apigatewayv2/)
- [SST static-site environment variables](https://sst.dev/docs/component/aws/static-site/)
- [MDN Page Visibility API](https://developer.mozilla.org/en-US/docs/Web/API/Page_Visibility_API)
- [MDN pointer events and capture](https://developer.mozilla.org/en-US/docs/Web/API/Pointer_events)
