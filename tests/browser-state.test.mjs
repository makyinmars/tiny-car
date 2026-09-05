import test from "node:test";
import { runInContext } from "node:vm";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { JSDOM } from "jsdom";
const html = await readFile(
  new URL("../src/shell.html", import.meta.url),
  "utf8",
);
const script = await readFile(
  new URL("../web/app.js", import.meta.url),
  "utf8",
);
function page() {
  const dom = new JSDOM(html, {
    url: "http://localhost/",
    runScripts: "outside-only",
    pretendToBeVisual: true,
  });
  const window = dom.window;
  let callback;
  window.requestAnimationFrame = (fn) => {
    callback = fn;
  };
  const values = [
    0, 0, 0, 1, 42, 0, 0, 0, 0, 0, 0, 0, 0, 20260905, 384, 430, 180, 2,
  ];
  const inputs = [];
  window.fetch = async () => {
    throw new Error("offline");
  };
  runInContext(script, dom.getInternalVMContext());
  Object.assign(window.Module, {
    _tiny_metric: (index) => values[index],
    _tiny_input: (value) => {
      inputs.push(value);
    },
    _tiny_volume() {},
    _tiny_ghost() {},
    _tiny_start() {
      values[0] = 1;
    },
    _tiny_pause() {
      if ([1, 2].includes(values[0])) values[0] = 3;
    },
    _tiny_resume() {
      values[0] = 2;
    },
  });
  window.Module.onRuntimeInitialized();
  return {
    dom,
    window,
    values,
    inputs,
    tick: (time) => callback(time),
    el: (id) => window.document.getElementById(id),
  };
}

test("keyboard and touch gas held through countdown reach the simulation", async () => {
  const p = page();
  try {
    p.el("playButton").click();
    p.el("canvas").dispatchEvent(
      new p.window.KeyboardEvent("keydown", { code: "ArrowUp", bubbles: true }),
    );
    assert.equal(p.inputs.at(-1), 4);
    p.values[0] = 2;
    p.tick(100);
    assert.equal(p.inputs.at(-1), 4);
    p.el("canvas").dispatchEvent(
      new p.window.KeyboardEvent("keyup", { code: "ArrowUp", bubbles: true }),
    );
    assert.equal(p.inputs.at(-1), 0);
    const gas = p.window.document.querySelector('[data-input="4"]');
    gas.setPointerCapture = () => {};
    gas.dispatchEvent(
      new p.window.MouseEvent("pointerdown", { bubbles: true }),
    );
    assert.equal(p.inputs.at(-1), 4);
    gas.dispatchEvent(
      new p.window.MouseEvent("pointercancel", { bubbles: true }),
    );
    assert.equal(p.inputs.at(-1), 0);
  } finally {
    p.dom.window.close();
  }
});

test("blur pauses, clears held controls and does not resume automatically", () => {
  const p = page();
  try {
    p.values[0] = 2;
    p.el("canvas").dispatchEvent(
      new p.window.KeyboardEvent("keydown", {
        code: "ArrowLeft",
        bubbles: true,
      }),
    );
    assert.equal(p.inputs.at(-1), 1);
    p.window.dispatchEvent(new p.window.Event("blur"));
    assert.equal(p.values[0], 3);
    assert.equal(p.inputs.at(-1), 0);
    assert.equal(p.el("pauseOverlay").hidden, false);
    p.window.dispatchEvent(new p.window.Event("focus"));
    assert.equal(p.values[0], 3);
  } finally {
    p.dom.window.close();
  }
});

test("finishing saves one personal best, preserves stronger runs, and renders full accounting", () => {
  const p = page();
  try {
    p.el("playButton").click();
    p.values[0] = 4;
    p.values[1] = 120;
    p.values[2] = 5400;
    p.values[5] = 1;
    p.values[6] = 1;
    p.values[8] = 50;
    p.values[9] = 30;
    p.values[10] = 40;
    p.tick(100);
    assert.equal(p.el("resultOvertakes").textContent, "1");
    assert.equal(p.el("nearPoints").textContent, "30");
    assert.match(p.el("submissionStatus").textContent, /Saved on this device/);
    const key = "tiny-car:best:score-attack-v2:solo:20260905";
    assert.equal(JSON.parse(p.window.localStorage.getItem(key)).score, 120);
    p.el("retryButton").click();
    p.values[0] = 4;
    p.values[1] = 50;
    p.tick(200);
    assert.equal(JSON.parse(p.window.localStorage.getItem(key)).score, 120);
    assert.match(p.el("resultImprovement").textContent, /70 points/);
  } finally {
    p.dom.window.close();
  }
});

test("typing a nickname does not steer, and audio preferences persist", () => {
  const p = page();
  try {
    p.values[0] = 2;
    p.el("nickname").dispatchEvent(
      new p.window.KeyboardEvent("keydown", { code: "KeyA", bubbles: true }),
    );
    assert.equal(p.inputs.includes(1), false);
    p.el("muteButton").click();
    p.el("volume").value = 72;
    p.el("volume").dispatchEvent(new p.window.Event("input"));
    const settings = JSON.parse(
      p.window.localStorage.getItem("tiny-car:settings"),
    );
    assert.equal(settings.muted, true);
    assert.equal(settings.volume, 72);
  } finally {
    p.dom.window.close();
  }
});
