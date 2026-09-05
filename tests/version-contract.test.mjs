import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { VERSION } from "../server/service.mjs";

test("simulation, browser handshake, and API share the current rules version", async () => {
  const [race, browser] = await Promise.all([
    readFile(new URL("../src/race.zig", import.meta.url), "utf8"),
    readFile(new URL("../web/app.js", import.meta.url), "utf8"),
  ]);
  const simulation = Number(race.match(/pub const version = (\d+);/)[1]);
  const bridge = Number(browser.match(/const BRIDGE_VERSION = (\d+);/)[1]);
  const browserVersion = browser.match(/const VERSION = "([^"]+)";/)[1];
  assert.equal(bridge, simulation);
  assert.equal(browserVersion, `score-attack-v${simulation}`);
  assert.equal(VERSION, browserVersion);
});
