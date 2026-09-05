import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  createService,
  VERSION,
  weekKey,
  validateResult,
  MAX_SPAWNS,
} from "../server/service.mjs";
import { MemoryStore, FileStore } from "../server/file-store.mjs";
const token = (n) => n.toString(16).padStart(32, "0");
const base = {
  version: VERSION,
  ticks: 5400,
  score: 50,
  overtakes: 1,
  nearMisses: 0,
  crashes: 0,
  basePoints: 50,
  nearPoints: 0,
  speedPoints: 0,
  cleanPoints: 0,
  bestStreak: 1,
};
function setup() {
  let time = Date.parse("2026-09-06T23:50:00Z");
  const store = new MemoryStore();
  return {
    store,
    service: createService(store, { now: () => time }),
    advance: (ms) => {
      time += ms;
    },
    setTime: (value) => {
      time = Date.parse(value);
    },
  };
}
async function group(service) {
  const response = await service("POST", "/api/groups", {
    name: "Weekend drivers",
  });
  assert.equal(response.status, 201);
  return response.data;
}
async function run(service, group, player = 1, nickname = "Driver") {
  return (
    await service("POST", `/api/groups/${group.id}/runs`, {
      nickname,
      playerToken: token(player),
    })
  ).data;
}
async function finish(service, race, changes = {}) {
  return service("POST", `/api/runs/${race.id}/result`, {
    ...base,
    seed: race.seed,
    ...changes,
  });
}

test("friends share a seed, one best per identity, ties share rank, correct gaps", async () => {
  const { service, advance } = setup();
  const challenge = await group(service);
  const runs = await Promise.all([
    run(service, challenge, 1, "A"),
    run(service, challenge, 1, "A"),
    run(service, challenge, 2, "B"),
    run(service, challenge, 3, "C"),
  ]);
  for (const race of runs) assert.equal(race.seed, challenge.seed);
  advance(94000);
  assert.equal((await finish(service, runs[0])).status, 200);
  for (const race of runs.slice(1, 3))
    assert.equal(
      (
        await finish(service, race, {
          score: 100,
          overtakes: 2,
          basePoints: 100,
          bestStreak: 2,
        })
      ).status,
      200,
    );
  await finish(service, runs[3]);
  const { data } = await service(
    "GET",
    `/api/groups/${challenge.id}/board`,
    {},
    new URLSearchParams("period=all"),
  );
  assert.equal(data.entries.length, 3);
  assert.deepEqual(
    data.entries.map((row) => [row.rank, row.score, row.gap]),
    [
      [1, 100, 0],
      [1, 100, 0],
      [3, 50, 50],
    ],
  );
  assert.equal(data.entries.filter((row) => row.nickname === "A").length, 1);
  assert.ok(!JSON.stringify(data).includes(runs[0].id));
  assert.ok(!JSON.stringify(data).includes(token(1)));
});

test("rejects premature, incomplete, mismatched and impossible scores", async () => {
  const { service, advance } = setup();
  const challenge = await group(service);
  const race = await run(service, challenge);
  assert.equal((await finish(service, race)).status, 400);
  advance(94000);
  for (const changes of [
    { score: 9999 },
    { seed: race.seed + 1 },
    { version: "old" },
    { ticks: 5399 },
    { nearMisses: 2 },
    { overtakes: -1 },
    { speedPoints: 21, score: 71 },
    { score: null },
    { crashes: 500 },
  ])
    assert.equal((await finish(service, race, changes)).status, 400);
  assert.equal((await finish(service, race)).status, 200);
  advance(1800000);
  assert.equal((await finish(service, race)).status, 410);
});

test("concurrent retries are idempotent and do not overwrite the accepted result", async () => {
  const { service, advance, store } = setup();
  const challenge = await group(service);
  const race = await run(service, challenge);
  advance(94000);
  await Promise.all(Array.from({ length: 10 }, () => finish(service, race)));
  await finish(service, race, {
    score: 100,
    overtakes: 2,
    basePoints: 100,
    bestStreak: 2,
  });
  const records = await store.query(`BOARD#${challenge.id}#${VERSION}`);
  assert.equal(records.length, 1);
  assert.equal(records[0].score, 50);
});

test("weekly board rolls over at Monday UTC while all-time retains records", async () => {
  const { service, advance, setTime } = setup();
  const challenge = await group(service);
  const race = await run(service, challenge);
  advance(94000);
  await finish(service, race);
  setTime("2026-09-07T00:00:00Z");
  const week = await service("GET", `/api/groups/${challenge.id}/board`);
  const all = await service(
    "GET",
    `/api/groups/${challenge.id}/board`,
    {},
    new URLSearchParams("period=all"),
  );
  assert.equal(week.data.entries.length, 0);
  assert.equal(all.data.entries.length, 1);
  assert.equal(weekKey("2026-01-01T00:00:00Z"), "2025-12-29");
});

test("validation handles malformed names, missing groups, versions and periods", async () => {
  const { service, store } = setup();
  for (const name of ["", " ".repeat(5), "a".repeat(41), "<x>\n"])
    assert.equal((await service("POST", "/api/groups", { name })).status, 400);
  assert.equal((await service("GET", "/api/groups/missing")).status, 404);
  assert.equal((await service("POST", "/api/groups", null)).status, 400);
  const challenge = await group(service);
  assert.equal(
    (
      await service("POST", `/api/groups/${challenge.id}/runs`, {
        nickname: "A",
        playerToken: "",
      })
    ).status,
    400,
  );
  assert.equal(
    (
      await service(
        "GET",
        `/api/groups/${challenge.id}/board`,
        {},
        new URLSearchParams("period=bad"),
      )
    ).status,
    400,
  );
  await store.put(`GROUP#${challenge.id}`, "META", {
    ...challenge,
    version: "old",
  });
  assert.equal(
    (await service("GET", `/api/groups/${challenge.id}`)).status,
    409,
  );
});

test("local scores survive server restart and simultaneous writes", async () => {
  const directory = await mkdtemp(join(tmpdir(), "tiny-car-test-"));
  try {
    const file = join(directory, "scores.json");
    const store = await new FileStore(file).load();
    await Promise.all(
      Array.from({ length: 30 }, (_, i) =>
        store.put("GROUP", String(i), { score: i }),
      ),
    );
    const reloaded = await new FileStore(file).load();
    assert.equal((await reloaded.query("GROUP")).length, 30);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("v3 validation uses the spawn ceiling and earned streak multiplier", () => {
  let attempts = 0;
  for (
    let tick = 0;
    tick < 5400;
    tick += 66 - Math.min(Math.floor(tick / 160), 33)
  )
    attempts++;
  assert.equal(MAX_SPAWNS, attempts);
  assert.throws(() => validateResult({ ...base, version: "score-attack-v2" }));
  assert.throws(() =>
    validateResult({
      ...base,
      overtakes: 114,
      basePoints: 5700,
      score: 5700,
      bestStreak: 114,
    }),
  );
  assert.throws(() => validateResult({ ...base, cleanPoints: 50, score: 100 }));
  assert.throws(() => validateResult({ ...base, bestStreak: 0 }));
  assert.equal(
    validateResult({
      ...base,
      overtakes: 6,
      basePoints: 300,
      bestStreak: 6,
      cleanPoints: 50,
      score: 350,
    }).score,
    350,
  );
});
