import { createHash, randomBytes, randomInt } from "node:crypto";

export const VERSION = "score-attack-v2";
export const TICKS = 5400;
const id = () => randomBytes(16).toString("hex");
const fail = (status, message) => {
  throw Object.assign(new Error(message), { status });
};
const validId = (value) =>
  typeof value === "string" && /^[a-f0-9]{32}$/.test(value);
const text = (value, max, label) => {
  if (
    typeof value !== "string" ||
    !value.trim() ||
    value.trim().length > max ||
    // oxlint-disable-next-line no-control-regex -- Reject control characters in user-provided names.
    /[\x00-\x1f\x7f]/.test(value)
  )
    fail(400, `${label} must be 1–${max} characters.`);
  return value.trim();
};
export function weekKey(date) {
  const d = new Date(date);
  const days = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}
export function validateResult(result) {
  if (!result || result.version !== VERSION || result.ticks !== TICKS)
    fail(400, "Complete a 90-second run with the current game version.");
  const limits = {
    score: 90000,
    overtakes: 180,
    nearMisses: 180,
    crashes: 90,
    basePoints: 9000,
    nearPoints: 5400,
    speedPoints: 7200,
    cleanPoints: 72000,
    bestStreak: 180,
  };
  for (const [key, max] of Object.entries(limits)) {
    if (
      !Number.isSafeInteger(result[key]) ||
      result[key] < 0 ||
      result[key] > max
    )
      fail(400, `Invalid ${key}.`);
  }
  if (
    result.nearMisses > result.overtakes ||
    result.bestStreak > result.overtakes ||
    result.basePoints !== result.overtakes * 50 ||
    result.nearPoints !== result.nearMisses * 30 ||
    result.speedPoints > result.overtakes * 40 ||
    result.speedPoints % 20 !== 0 ||
    result.cleanPoints >
      (result.basePoints + result.nearPoints + result.speedPoints) * 4 ||
    result.score !==
      result.basePoints +
        result.nearPoints +
        result.speedPoints +
        result.cleanPoints
  )
    fail(400, "Score breakdown does not match the run.");
  return Object.fromEntries(
    ["version", "ticks", ...Object.keys(limits)].map((key) => [
      key,
      result[key],
    ]),
  );
}

export function createService(store, { now = () => Date.now() } = {}) {
  async function groupById(groupId) {
    if (!validId(groupId))
      fail(404, "Challenge not found. Check the invitation link.");
    const group = await store.get(`GROUP#${groupId}`, "META");
    if (!group) fail(404, "Challenge not found. Check the invitation link.");
    if (group.version !== VERSION)
      fail(
        409,
        "This challenge uses an older game version. Create a new challenge.",
      );
    return group;
  }
  return async function handle(
    method,
    path,
    body = {},
    query = new URLSearchParams(),
  ) {
    try {
      if (body === null || typeof body !== "object" || Array.isArray(body))
        fail(400, "Request must be a JSON object.");
      const parts = path
        .replace(/^\/api\/?/, "/")
        .split("/")
        .filter(Boolean);
      let data;
      let status = 200;
      if (method === "GET" && parts.join("/") === "health") {
        data = { ok: true, version: VERSION };
      } else if (method === "POST" && parts.join("/") === "groups") {
        const name = text(body.name, 40, "Challenge name");
        const group = {
          id: id(),
          name,
          seed: randomInt(1, 0x7fffffff),
          version: VERSION,
          createdAt: now(),
        };
        await store.put(`GROUP#${group.id}`, "META", group);
        data = group;
        status = 201;
      } else if (parts[0] === "groups" && parts.length >= 2) {
        const group = await groupById(parts[1]);
        if (method === "GET" && parts.length === 2) {
          data = group;
        } else if (
          method === "POST" &&
          parts[2] === "runs" &&
          parts.length === 3
        ) {
          const nickname = text(body.nickname, 20, "Nickname");
          if (!validId(body.playerToken)) fail(400, "Invalid player identity.");
          const playerId = createHash("sha256")
            .update(body.playerToken)
            .digest("hex")
            .slice(0, 24);
          const run = {
            id: id(),
            groupId: group.id,
            playerId,
            nickname,
            seed: group.seed,
            version: VERSION,
            startedAt: now(),
            expiresAt: now() + 30 * 60 * 1000,
          };
          await store.put(`RUN#${run.id}`, "META", {
            ...run,
            ttl: Math.floor(run.expiresAt / 1000),
          });
          data = run;
          status = 201;
        } else if (
          method === "GET" &&
          parts[2] === "board" &&
          parts.length === 3
        ) {
          const period = query.get("period") || "week";
          if (!["week", "all"].includes(period))
            fail(400, "Unknown leaderboard period.");
          const week = weekKey(now());
          const rows = await store.query(`BOARD#${group.id}#${VERSION}`);
          const best = new Map();
          for (const row of rows) {
            if (period === "week" && weekKey(row.finishedAt) !== week) continue;
            const old = best.get(row.playerId);
            if (
              !old ||
              row.score > old.score ||
              (row.score === old.score && row.finishedAt < old.finishedAt)
            )
              best.set(row.playerId, row);
          }
          const ranked = [...best.values()].sort(
            (a, b) =>
              b.score - a.score ||
              a.finishedAt - b.finishedAt ||
              a.playerId.localeCompare(b.playerId),
          );
          let rank = 0;
          let previousScore;
          let gap = 0;
          const entries = ranked.map((row, i) => {
            if (row.score !== previousScore) {
              rank = i + 1;
              gap = previousScore === undefined ? 0 : previousScore - row.score;
              previousScore = row.score;
            }
            return {
              playerId: row.playerId,
              nickname: row.nickname,
              score: row.score,
              rank,
              gap,
              finishedAt: row.finishedAt,
              overtakes: row.overtakes,
              nearMisses: row.nearMisses,
              crashes: row.crashes,
            };
          });
          data = {
            entries: entries.slice(0, 100),
            total: entries.length,
            personal:
              entries.find((row) => row.playerId === query.get("player")) ||
              null,
            period,
            week,
            version: VERSION,
          };
        } else fail(404, "Endpoint not found.");
      } else if (
        method === "POST" &&
        parts[0] === "runs" &&
        parts[2] === "result" &&
        parts.length === 3
      ) {
        if (!validId(parts[1])) fail(404, "Run not found.");
        const run = await store.get(`RUN#${parts[1]}`, "META");
        if (!run) fail(404, "Run expired. Start a new run.");
        const result = validateResult(body);
        if (body.seed !== run.seed || body.version !== run.version)
          fail(400, "Challenge seed or version mismatch.");
        if (run.expiresAt < now())
          fail(410, "This run expired. Your local record is still saved.");
        if (now() - run.startedAt < 92000)
          fail(400, "Run finished too quickly.");
        // Conditional insert makes concurrent retries idempotent. The run token is never public.
        const key = `BOARD#${run.groupId}#${VERSION}`;
        const resultKey = createHash("sha256").update(run.id).digest("hex");
        const entry = {
          ...result,
          seed: run.seed,
          playerId: run.playerId,
          nickname: run.nickname,
          finishedAt: now(),
        };
        await store.putOnce(key, resultKey, entry);
        data = { saved: true };
      } else fail(404, "Endpoint not found.");
      return { status, data };
    } catch (error) {
      if (!error.status) console.error("Score API failed:", error.message);
      return {
        status: error.status || 500,
        data: {
          error: error.status
            ? error.message
            : "The leaderboard is unavailable. Please retry.",
        },
      };
    }
  };
}
