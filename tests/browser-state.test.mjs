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
function page({ saved = {}, bridgeVersion = 5 } = {}) {
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
    0,
    0,
    0,
    1,
    42,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    20260905,
    381,
    450,
    180,
    bridgeVersion,
    0,
  ];
  values[37] = 0;
  const inputs = [];
  const ghosts = [];
  const requests = [];
  const zooms = [];
  for (const [key, value] of Object.entries(saved))
    window.localStorage.setItem(`tiny-car:${key}`, JSON.stringify(value));
  window.fetch = async (url) => {
    requests.push(url);
    throw new Error("offline");
  };
  runInContext(script, dom.getInternalVMContext());
  Object.assign(window.Module, {
    _tiny_metric: (index) => values[index],
    _tiny_input: (value) => {
      inputs.push(value);
    },
    _tiny_volume() {},
    _tiny_zoom(value) {
      zooms.push(value);
    },
    _tiny_ghost(...value) {
      ghosts.push(value);
    },
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
    ghosts,
    requests,
    zooms,
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

test("two touch pointers steer and accelerate together and release independently", () => {
  const p = page();
  try {
    p.el("playButton").click();
    const gas = p.window.document.querySelector('[data-input="4"]');
    const right = p.window.document.querySelector('[data-input="2"]');
    const pointer = (button, type, id) => {
      button.setPointerCapture = () => {};
      const event = new p.window.Event(type, {
        bubbles: true,
        cancelable: true,
      });
      Object.defineProperty(event, "pointerId", { value: id });
      button.dispatchEvent(event);
    };
    pointer(gas, "pointerdown", 1);
    pointer(right, "pointerdown", 2);
    assert.equal(p.inputs.at(-1), 6);
    p.values[0] = 2;
    p.tick(100);
    assert.equal(p.inputs.at(-1), 6);
    pointer(gas, "pointercancel", 1);
    assert.equal(p.inputs.at(-1), 2);
    pointer(right, "lostpointercapture", 2);
    assert.equal(p.inputs.at(-1), 0);
    assert.equal(right.classList.contains("held"), false);
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
    const key = "tiny-car:best:score-attack-v5:solo:20260905";
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

test("v4 bests stay isolated and a mismatched simulation cannot start", () => {
  const p = page({
    saved: {
      "best:score-attack-v4:solo:20260905": {
        version: "score-attack-v4",
        ticks: 5400,
        seed: 20260905,
        score: 99999,
        ghost: [[384, 430, 0]],
      },
    },
  });
  const old = page({ bridgeVersion: 3 });
  try {
    assert.match(p.el("personalBest").textContent, /—/);
    assert.equal(p.el("playButton").disabled, false);
    assert.equal(old.el("playButton").disabled, true);
    assert.match(old.el("loadingStatus").textContent, /out of date/);
  } finally {
    p.dom.window.close();
    old.dom.window.close();
  }
});

test("ghosts record body heading and interpolate only compatible finite points", () => {
  const key = "best:score-attack-v5:solo:20260905";
  const p = page({
    saved: {
      [key]: {
        version: "score-attack-v5",
        seed: 20260905,
        ticks: 5400,
        score: 100,
        ghost: [
          [370, 450, 0, 0],
          [380, 455, 0.1, 40],
          [null, 455, 0],
          [390, 456],
        ],
      },
    },
  });
  try {
    p.el("playButton").click();
    p.values[0] = 2;
    p.values[2] = 3;
    p.values[18] = 0.04;
    p.tick(100);
    assert.deepEqual(p.ghosts.at(-1), [375, 452.5, 0.05, 20]);
    p.values[2] = 12;
    p.tick(200);
    assert.deepEqual(p.ghosts.at(-1), [-100, -100, 0, 0]);
    p.values[2] = 18;
    p.tick(300);
    assert.deepEqual(p.ghosts.at(-1), [-100, -100, 0, 0]);
    p.values[0] = 4;
    p.values[1] = 200;
    p.values[2] = 5400;
    p.tick(400);
    const saved = JSON.parse(p.window.localStorage.getItem(`tiny-car:${key}`));
    assert.deepEqual(saved.ghost[0], [381, 450, 0.04, 0]);
  } finally {
    p.dom.window.close();
  }
});

test("instructions pause a run and closing them requires an explicit resume", () => {
  const p = page();
  try {
    const help = p.el("helpDialog");
    help.showModal = () => {
      help.open = true;
    };
    help.close = () => {
      help.open = false;
      help.dispatchEvent(new p.window.Event("close"));
    };
    p.values[0] = 2;
    p.el("helpButton").click();
    assert.equal(p.values[0], 3);
    assert.equal(p.inputs.at(-1), 0);
    p.el("canvas").dispatchEvent(
      new p.window.KeyboardEvent("keydown", { code: "ArrowUp", bubbles: true }),
    );
    assert.equal(p.inputs.at(-1), 0);
    help.close();
    assert.equal(p.values[0], 3);
    p.el("resumeButton").click();
    assert.equal(p.values[0], 2);
    assert.equal(p.inputs.at(-1), 0);
  } finally {
    p.dom.window.close();
  }
});

test("pending results from older rules are not retried", async () => {
  const p = page({
    saved: {
      pending: [
        {
          session: { id: "old-run", expiresAt: Date.now() + 60000 },
          result: { version: "score-attack-v4" },
        },
      ],
    },
  });
  try {
    await Promise.resolve();
    assert.equal(p.requests.length, 0);
  } finally {
    p.dom.window.close();
  }
});

test("a v4 ghost inside a v5 storage key cannot enter the new run", () => {
  const p = page({
    saved: {
      "best:score-attack-v5:solo:20260905": {
        version: "score-attack-v4",
        ticks: 5400,
        seed: 20260905,
        score: 500,
        ghost: [[381, 450, 0]],
      },
    },
  });
  try {
    p.el("playButton").click();
    p.values[0] = 2;
    p.tick(100);
    assert.match(p.el("personalBest").textContent, /—/);
    assert.deepEqual(p.ghosts.at(-1), [-100, -100, 0, 0]);
  } finally {
    p.dom.window.close();
  }
});

test("readable crossing and fast-car warnings follow the simulation, including pause", () => {
  const p = page();
  try {
    p.values[0] = 2;
    p.values[28] = 1;
    p.tick(100);
    assert.equal(p.el("pedestrianWarning").hidden, false);
    assert.equal(
      p.el("pedestrianWarningText").textContent,
      "Left shoulder crossing",
    );
    assert.equal(p.el("fastWarning").hidden, true);
    p.values[28] = 2 | 4 | 8 | 16;
    p.tick(200);
    assert.equal(
      p.el("pedestrianWarningText").textContent,
      "Right outer lane crossing",
    );
    assert.match(p.el("fastWarningText").textContent, /yielding/);
    assert.equal(p.el("roadMood").hidden, true);
    p.values[0] = 3;
    p.tick(300);
    assert.equal(p.el("fastWarning").hidden, false);
    p.values[0] = 2;
    p.values[28] = 0;
    p.values[29] = 3;
    p.tick(400);
    assert.equal(p.el("pedestrianWarning").hidden, true);
    assert.equal(p.el("fastWarning").hidden, true);
    assert.match(p.el("roadMood").textContent, /quieter stretch/);
  } finally {
    p.dom.window.close();
  }
});

test("camera keys and buttons clamp and reset without changing driving input", () => {
  const p = page();
  try {
    p.values[0] = 2;
    const press = (code, extra = {}, target = p.el("canvas")) =>
      target.dispatchEvent(
        new p.window.KeyboardEvent("keydown", {
          code,
          bubbles: true,
          cancelable: true,
          ...extra,
        }),
      );
    press("ArrowUp");
    const input = p.inputs.at(-1);
    for (let i = 0; i < 30; i++) press("Equal");
    assert.equal(p.zooms.at(-1), 1.05);
    assert.equal(p.el("zoomIn").disabled, true);
    assert.equal(p.inputs.at(-1), input);
    for (let i = 0; i < 30; i++) press("Minus");
    assert.equal(p.zooms.at(-1), 0.65);
    assert.equal(p.el("zoomOut").disabled, true);
    p.el("zoomReset").click();
    assert.equal(p.zooms.at(-1), 0.82);
    p.el("zoomIn").click();
    assert.ok(p.zooms.at(-1) > 0.82);
    press("Digit0");
    assert.equal(p.zooms.at(-1), 0.82);
    const count = p.zooms.length;
    press("Equal", { ctrlKey: true });
    press("Equal", { metaKey: true });
    press("Minus", {}, p.el("nickname"));
    p.el("helpDialog").open = true;
    press("Minus");
    p.el("zoomOut").click();
    assert.equal(p.zooms.length, count);
  } finally {
    p.dom.window.close();
  }
});

test("wheel zoom is confined to the canvas and preserves browser pinch shortcuts", () => {
  const p = page();
  try {
    const wheel = (target, options = {}) => {
      const event = new p.window.WheelEvent("wheel", {
        deltaY: 20,
        bubbles: true,
        cancelable: true,
        ...options,
      });
      target.dispatchEvent(event);
      return event;
    };
    assert.equal(wheel(p.el("canvas")).defaultPrevented, true);
    assert.ok(Math.abs(p.zooms.at(-1) - 0.78) < 1e-9);
    const count = p.zooms.length;
    assert.equal(
      wheel(p.el("canvas"), { ctrlKey: true }).defaultPrevented,
      false,
    );
    assert.equal(wheel(p.window.document.body).defaultPrevented, false);
    p.el("groupDialog").open = true;
    assert.equal(wheel(p.el("canvas")).defaultPrevented, false);
    assert.equal(p.zooms.length, count);
  } finally {
    p.dom.window.close();
  }
});

test("phone status text follows the same race metrics at every camera scale", () => {
  const p = page();
  try {
    p.values[0] = 2;
    p.values[1] = 1230;
    p.values[2] = 3540;
    p.values[3] = 3;
    p.values[4] = 62.4;
    p.tick(1000);
    assert.equal(p.el("mobileScore").textContent, "1,230");
    assert.equal(p.el("mobileTime").textContent, "31");
    assert.equal(p.el("mobileSpeed").textContent, "62");
    assert.equal(p.el("mobileClean").textContent, "3×");
    p.el("zoomIn").click();
    p.tick(1100);
    assert.equal(p.el("mobileTime").textContent, "31");
    assert.equal(p.values[2], 3540);
  } finally {
    p.dom.window.close();
  }
});
