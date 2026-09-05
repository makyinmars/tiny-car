"use strict";
const BRIDGE_VERSION = 5;
const VERSION = "score-attack-v5";
const SOLO_SEED = 20260905;
const $ = (id) => document.getElementById(id);
const fmt = (value) => Number(value).toLocaleString();
const storage = {
  read(key, fallback) {
    try {
      return JSON.parse(localStorage.getItem(`tiny-car:${key}`)) ?? fallback;
    } catch {
      return fallback;
    }
  },
  write(key, value) {
    try {
      localStorage.setItem(`tiny-car:${key}`, JSON.stringify(value));
      return true;
    } catch {
      return false;
    }
  },
};
const token = () =>
  Array.from(crypto.getRandomValues(new Uint8Array(16)), (n) =>
    n.toString(16).padStart(2, "0"),
  ).join("");
let playerToken = storage.read("player", null);
if (!/^[a-f0-9]{32}$/.test(playerToken)) {
  playerToken = token();
  storage.write("player", playerToken);
}
let settings = storage.read("settings", {});
if (!settings || typeof settings !== "object") settings = {};
settings = {
  nickname:
    typeof settings.nickname === "string" ? settings.nickname.slice(0, 20) : "",
  volume: Number.isFinite(settings.volume)
    ? Math.max(0, Math.min(100, settings.volume))
    : 35,
  muted: settings.muted === true,
  ghost: settings.ghost !== false,
};
let ready = false;
let group = null;
let groupLoading = false;
let groupInvalid = false;
let starting = false;
let period = "week";
let currentSession = null;
let lastResult = null;
let runGroup = null;
let runKey = "";
let runGhost = null;
let ghostRecording = [];
let lastTickSample = -1;
let processedFinish = false;
let state = 0;
let pollTime = 0;
let boardRequest = 0;
let playerId = "";
let noticeTimer;
let lastWarningKey = "";
const DEFAULT_ZOOM = 0.82;
let zoom = DEFAULT_ZOOM;

function setZoom(value) {
  if (!ready || anyDialog() || !Number.isFinite(value)) return;
  zoom = Math.max(0.65, Math.min(1.05, value));
  Module._tiny_zoom(zoom);
  $("zoomReset").textContent =
    `${Math.round((zoom / DEFAULT_ZOOM) * 100)}% · Reset`;
  $("zoomOut").disabled = zoom <= 0.65;
  $("zoomIn").disabled = zoom >= 1.05;
}
const keys = new Set();
const pointers = new Map();
const keyBits = {
  ArrowLeft: 1,
  KeyA: 1,
  ArrowRight: 2,
  KeyD: 2,
  ArrowUp: 4,
  KeyW: 4,
  ArrowDown: 8,
  KeyS: 8,
};
const apiBase = (window.TINY_CAR_CONFIG?.apiUrl || "/api").replace(/\/$/, "");
const bestKey = () =>
  `best:${VERSION}:${group?.id || "solo"}:${group?.seed || SOLO_SEED}`;
const validGhostPoint = (point) =>
  Array.isArray(point) &&
  point.length === 4 &&
  point.every(Number.isFinite) &&
  point[0] >= 236 &&
  point[0] <= 526 &&
  point[1] >= 400 &&
  point[1] <= 510 &&
  Math.abs(point[2]) <= 0.14 &&
  point[3] >= 0 &&
  point[3] <= 40500;

function compatibleBest(key) {
  const best = storage.read(key, null);
  return best?.version === VERSION &&
    best.ticks === 5400 &&
    best.seed === (group?.seed || SOLO_SEED) &&
    Number.isSafeInteger(best.score) &&
    best.score >= 0
    ? best
    : null;
}
const metric = (key) => Module._tiny_metric(key);
const gameState = () => (ready ? metric(0) : 0);
const anyDialog = () => $("helpDialog").open || $("groupDialog").open;
const saveSettings = () => storage.write("settings", settings);
function notice(message, duration = 5000) {
  $("notice").textContent = message;
  $("notice").hidden = false;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => {
    $("notice").hidden = true;
  }, duration);
}
async function api(path, body) {
  let response;
  try {
    response = await fetch(`${apiBase}${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: body === undefined ? {} : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    throw new Error(
      "Could not reach the leaderboard. Check your connection and retry.",
    );
  }
  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error(
      "The score API is unavailable. Run the local API server or check the deployed API configuration.",
    );
  }
  if (!response.ok)
    throw new Error(data.error || "Unable to save this request. Please retry.");
  return data;
}
function updateBest() {
  const best = compatibleBest(bestKey());
  $("personalBest").replaceChildren(
    document.createTextNode(
      best && Number.isFinite(best.score) ? fmt(best.score) + " " : "— ",
    ),
  );
  const unit = document.createElement("small");
  unit.textContent = "PTS";
  $("personalBest").append(unit);
}
function syncSound() {
  $("muteButton").textContent = settings.muted ? "Sound off" : "Sound on";
  $("muteButton").setAttribute("aria-pressed", String(settings.muted));
  if (ready) Module._tiny_volume(settings.muted ? 0 : settings.volume / 100);
}
function unlockAudio() {
  window.miniaudio?.unlock?.();
}
function applyInput() {
  let mask = 0;
  for (const key of keys) mask |= keyBits[key] || 0;
  for (const bit of pointers.values()) mask |= bit;
  if (ready)
    Module._tiny_input([1, 2].includes(gameState()) && !anyDialog() ? mask : 0);
}
function clearInput() {
  keys.clear();
  pointers.clear();
  document
    .querySelectorAll("[data-input]")
    .forEach((button) => button.classList.remove("held"));
  if (ready) Module._tiny_input(0);
}
function pauseGame() {
  clearInput();
  if (ready) Module._tiny_pause();
  updateState();
}
function resumeGame() {
  if (!ready || document.hidden || anyDialog()) return;
  unlockAudio();
  clearInput();
  Module._tiny_resume();
  updateState();
  $("canvas").focus({ preventScroll: true });
}
function updateState() {
  if (!ready) return;
  state = gameState();
  $("startOverlay").hidden = state !== 0;
  $("pauseOverlay").hidden = state !== 3;
  $("resultOverlay").hidden = state !== 4;
  $("pauseButton").disabled = ![1, 2, 3].includes(state);
  $("pauseButton").textContent = state === 3 ? "Resume →" : "Pause Ⅱ";
  $("nickname").disabled = starting || [1, 2, 3].includes(state);
  $("playButton").disabled = starting || groupLoading || groupInvalid;
  $("retryButton").disabled = starting || groupLoading || groupInvalid;
}
async function startRun() {
  if (
    !ready ||
    starting ||
    groupLoading ||
    groupInvalid ||
    anyDialog() ||
    ![0, 4].includes(gameState())
  )
    return;
  const nickname = $("nickname").value.trim();
  if (group && !nickname) {
    notice("Pick a nickname before joining the board.");
    $("nickname").focus();
    return;
  }
  settings.nickname = nickname;
  saveSettings();
  starting = true;
  updateState();
  $("playButton").textContent = "Getting your road ready…";
  $("retryButton").textContent = "Getting your road ready…";
  unlockAudio();
  runGroup = group;
  currentSession = null;
  if (group) {
    try {
      currentSession = await api(`/groups/${group.id}/runs`, {
        nickname,
        playerToken,
      });
      playerId = currentSession.playerId;
      storage.write("public-player", playerId);
    } catch (error) {
      notice(
        `${error.message} This run will be saved on this device only.`,
        8000,
      );
    }
  }
  runKey = bestKey();
  const previous = compatibleBest(runKey);
  runGhost = Array.isArray(previous?.ghost) ? previous.ghost : null;
  ghostRecording = [];
  lastTickSample = -1;
  processedFinish = false;
  Module._tiny_ghost(-100, -100, 0, 0);
  Module._tiny_start(group?.seed || SOLO_SEED);
  $("runMode").textContent =
    group && currentSession ? "FRIENDS CHALLENGE" : "LOCAL RUN";
  starting = false;
  $("playButton").textContent = "Play 90-second run →";
  $("retryButton").textContent = "One more run ↻";
  updateState();
  if (document.hidden || anyDialog()) pauseGame();
  else $("canvas").focus({ preventScroll: true });
}
function emptyBoard(title, message) {
  const box = document.createElement("div");
  box.className = "empty-board";
  const symbol = document.createElement("span");
  symbol.className = "empty-road";
  symbol.textContent = "↗";
  symbol.setAttribute("aria-hidden", "true");
  const heading = document.createElement("h3");
  heading.textContent = title;
  const copy = document.createElement("p");
  copy.textContent = message;
  box.append(symbol, heading, copy);
  $("boardContent").replaceChildren(box);
}
async function refreshBoard() {
  if (!group) return;
  const request = ++boardRequest;
  const expectedGroup = group.id;
  $("refreshButton").disabled = true;
  try {
    const result = await api(
      `/groups/${group.id}/board?period=${period}&player=${playerId}`,
    );
    if (request !== boardRequest || group?.id !== expectedGroup) return;
    $("rankHint").hidden = true;
    $("boardFootnote").textContent =
      period === "week"
        ? `Week of ${result.week} · resets Monday, 00:00 UTC`
        : "All-time bests · current game rules";
    if (!result.entries.length) {
      emptyBoard(
        period === "week"
          ? "A fresh week. An open road."
          : "Set the score to beat.",
        "Finish a run to take the first spot. Then send the link to your friends.",
      );
      return;
    }
    const table = document.createElement("table");
    table.className = "board-table";
    const caption = document.createElement("caption");
    caption.textContent = `${group.name} ${period === "week" ? "weekly" : "all-time"} leaderboard`;
    caption.hidden = true;
    table.append(caption);
    const head = document.createElement("thead");
    const hr = document.createElement("tr");
    for (const title of ["#", "DRIVER", "BEST RUN"]) {
      const th = document.createElement("th");
      th.scope = "col";
      th.textContent = title;
      hr.append(th);
    }
    head.append(hr);
    table.append(head);
    const tbody = document.createElement("tbody");
    for (const entry of result.entries) {
      const tr = document.createElement("tr");
      if (entry.playerId === playerId) tr.className = "is-you";
      const rank = document.createElement("td");
      rank.textContent = String(entry.rank).padStart(2, "0");
      const name = document.createElement("td");
      name.className = "driver-name";
      name.textContent = entry.nickname;
      if (entry.playerId === playerId) {
        const you = document.createElement("small");
        you.textContent = "YOU";
        name.append(you);
      }
      const score = document.createElement("td");
      score.className = "board-score";
      score.textContent = fmt(entry.score);
      if (entry.gap) {
        const gap = document.createElement("small");
        gap.textContent = `${fmt(entry.gap)} to next rank`;
        score.append(gap);
      }
      tr.append(rank, name, score);
      tbody.append(tr);
    }
    table.append(tbody);
    $("boardContent").replaceChildren(table);
    if (result.personal) {
      $("rankHint").hidden = false;
      $("rankHint").textContent =
        result.personal.rank === 1
          ? "You’re setting the pace. Send someone a challenge."
          : `You’re #${result.personal.rank}. ${fmt(result.personal.gap)} points to the next rank.`;
    }
  } catch (error) {
    if (request === boardRequest)
      emptyBoard("The board is taking a pit stop.", error.message);
  } finally {
    if (request === boardRequest) $("refreshButton").disabled = false;
  }
}
async function loadGroup(id) {
  groupLoading = true;
  groupInvalid = false;
  updateState();
  try {
    group = await api(`/groups/${id}`);
    $("trackName").textContent = group.name;
    $("groupName").textContent = group.name;
    $("runMode").textContent = "FRIENDS CHALLENGE";
    $("createButton").hidden = true;
    $("shareButton").hidden = false;
    $("groupTools").hidden = false;
    updateBest();
    await refreshBoard();
  } catch (error) {
    groupInvalid = true;
    emptyBoard("Couldn’t open this challenge.", error.message);
    $("trackName").textContent = "Challenge unavailable";
    notice(error.message, 8000);
  } finally {
    groupLoading = false;
    updateState();
  }
}
function setPeriod(next) {
  period = next;
  $("weekTab").setAttribute("aria-pressed", String(period === "week"));
  $("allTab").setAttribute("aria-pressed", String(period === "all"));
  refreshBoard();
}
function openDialog(id) {
  pauseGame();
  $(id).showModal();
}
function closeDialog(id) {
  $(id).close();
  clearInput();
}
async function submitResult(pending) {
  if (!pending?.session) return;
  const active = () => lastResult?.id === pending.id;
  if (active()) {
    $("submissionStatus").textContent = "Saving your place on the board…";
    $("retrySubmit").hidden = true;
  }
  try {
    await api(`/runs/${pending.session.id}/result`, pending.result);
    const stored = storage.read("pending", []);
    storage.write(
      "pending",
      (Array.isArray(stored) ? stored : []).filter(
        (item) => item.id !== pending.id,
      ),
    );
    if (active())
      $("submissionStatus").textContent =
        "Saved to the friends board. Your best run counts.";
    if (group?.id === pending.session.groupId) refreshBoard();
  } catch (error) {
    if (active()) {
      $("submissionStatus").textContent = `Saved locally. ${error.message}`;
      $("retrySubmit").hidden = false;
    }
  }
}
function finishRun() {
  if (processedFinish) return;
  processedFinish = true;
  clearInput();
  const result = {
    version: VERSION,
    seed: metric(13),
    ticks: metric(2),
    score: metric(1),
    overtakes: metric(5),
    nearMisses: metric(6),
    crashes: metric(7),
    basePoints: metric(8),
    nearPoints: metric(9),
    speedPoints: metric(10),
    cleanPoints: metric(11),
    bestStreak: metric(12),
  };
  const old = compatibleBest(runKey);
  const improved = !old || result.score > old.score;
  let saved = true;
  if (improved)
    saved = storage.write(runKey, { ...result, ghost: ghostRecording });
  $("resultScore").replaceChildren(
    document.createTextNode(`${fmt(result.score)} `),
  );
  const unit = document.createElement("small");
  unit.textContent = "PTS";
  $("resultScore").append(unit);
  $("resultImprovement").textContent = !old
    ? "Your first finish. A new score to chase."
    : improved
      ? `New personal best · +${fmt(result.score - old.score)} points`
      : result.score === old.score
        ? "You matched your personal best."
        : `${fmt(old.score - result.score)} points from your personal best.`;
  for (const [id, value] of Object.entries({
    resultOvertakes: result.overtakes,
    resultNear: result.nearMisses,
    resultCrashes: result.crashes,
    basePoints: result.basePoints,
    nearPoints: result.nearPoints,
    speedPoints: result.speedPoints,
    cleanPoints: result.cleanPoints,
  }))
    $(id).textContent = fmt(value);
  updateBest();
  lastResult = { id: token(), session: currentSession, result };
  $("retrySubmit").hidden = true;
  if (currentSession) {
    const previousPending = storage.read("pending", []);
    const pending = (
      Array.isArray(previousPending) ? previousPending : []
    ).filter(
      (item) =>
        item?.session?.expiresAt > Date.now() &&
        item?.result?.version === VERSION,
    );
    pending.push(lastResult);
    storage.write("pending", pending.slice(-10));
    submitResult(lastResult);
  } else
    $("submissionStatus").textContent = runGroup
      ? "Saved on this device. This run started offline and could not be ranked."
      : "Saved on this device. Create a challenge to race your friends.";
  if (!saved)
    notice(
      "Browser storage is unavailable. This personal best will not survive a reload.",
      9000,
    );
}
function updateEncounters(next) {
  for (const [id, text] of [
    ["mobileScore", fmt(metric(1))],
    ["mobileTime", String(Math.max(0, Math.ceil((5400 - metric(2)) / 60)))],
    ["mobileSpeed", String(Math.round(metric(4)))],
    ["mobileClean", `${metric(3)}×`],
  ]) {
    if ($(id).textContent !== text) $(id).textContent = text;
  }
  const corner =
    ["Short straight", "Sweeping bends", "Tight corners", "Chicane"][
      metric(40)
    ] || "Racing route";
  const guide = Math.round(metric(42) || 90);
  const lead = Math.max(0, Math.round((metric(41) || 0) / 50) * 10);
  const cue = `${corner} ${lead ? `in ${lead}m` : "ahead"} · ${guide} mph guide`;
  if ($("routeCue").textContent !== cue) $("routeCue").textContent = cue;
  $("routeCue").classList.toggle("brake-cue", metric(4) > guide + 5);
  const flags = metric(28) || 0;
  const pace = metric(29) || 0;
  const key = `${next}:${flags}:${pace}`;
  if (key === lastWarningKey) return;
  lastWarningKey = key;
  const active = next === 2 || next === 3;
  const crossing = active && (flags & 3) !== 0;
  const fast = active && (flags & 8) !== 0;
  $("pedestrianWarning").hidden = !crossing;
  $("fastWarning").hidden = !fast;
  $("roadMood").hidden = crossing || fast;
  if (crossing)
    $("pedestrianWarningText").textContent =
      `${flags & 1 ? "Left" : "Right"} ${flags & 4 ? "outer lane" : "shoulder"} crossing`;
  if (fast)
    $("fastWarningText").textContent =
      flags & 16
        ? "Fast car yielding · hold your line"
        : "Fast car behind · hold your line";
  if (!crossing && !fast)
    $("roadMood").textContent =
      next === 3
        ? "Paused. Resume when you’re ready."
        : next === 2
          ? [
              "Settle in. Watch the signals.",
              "Picking up. Find your rhythm.",
              "Final push. Keep it clean.",
              "Take a breath. A quieter stretch.",
            ][pace]
          : "Watch the signals. Keep it clean.";
}

function poll(now) {
  if (ready && now - pollTime >= 50) {
    pollTime = now;
    const next = gameState();
    updateEncounters(next);
    if (next !== state) {
      if (next !== 2) clearInput();
      updateState();
      if (next === 2) applyInput();
    }
    if (next === 2) {
      const sample = Math.floor(metric(2) / 6);
      if (sample !== lastTickSample) {
        ghostRecording[sample] = [
          Math.round(metric(14) * 10) / 10,
          Math.round(metric(15) * 10) / 10,
          Math.round(metric(18) * 10000) / 10000,
          Math.round(metric(37) * 10) / 10,
        ];
        lastTickSample = sample;
      }
      let point = settings.ghost && runGhost?.[sample];
      const nextPoint = settings.ghost && runGhost?.[sample + 1];
      if (validGhostPoint(point) && validGhostPoint(nextPoint)) {
        const fraction = metric(2) / 6 - sample;
        point = point.map(
          (value, index) => value + (nextPoint[index] - value) * fraction,
        );
      }
      Module._tiny_ghost(
        validGhostPoint(point) ? point[0] : -100,
        validGhostPoint(point) ? point[1] : -100,
        validGhostPoint(point) ? point[2] : 0,
        validGhostPoint(point) ? point[3] : 0,
      );
    }
    if (next === 4) finishRun();
  }
  requestAnimationFrame(poll);
}
$("nickname").value = settings.nickname;
$("volume").value = settings.volume;
$("ghostToggle").checked = settings.ghost;
playerId = storage.read("public-player", "");
syncSound();
updateBest();
$("nickname").addEventListener("input", () => {
  settings.nickname = $("nickname").value.trim();
  saveSettings();
});
$("volume").addEventListener("input", () => {
  settings.volume = Number($("volume").value);
  syncSound();
  saveSettings();
});
$("muteButton").addEventListener("click", () => {
  unlockAudio();
  settings.muted = !settings.muted;
  syncSound();
  saveSettings();
});
$("ghostToggle").addEventListener("change", () => {
  settings.ghost = $("ghostToggle").checked;
  saveSettings();
  if (!settings.ghost && ready) Module._tiny_ghost(-100, -100, 0, 0);
});
$("playButton").addEventListener("click", startRun);
$("retryButton").addEventListener("click", startRun);
$("resumeButton").addEventListener("click", resumeGame);
$("pauseButton").addEventListener("click", () =>
  gameState() === 3 ? resumeGame() : pauseGame(),
);
$("retrySubmit").addEventListener("click", () => submitResult(lastResult));
$("helpButton").addEventListener("click", () => openDialog("helpDialog"));
$("createButton").addEventListener("click", () => openDialog("groupDialog"));
$("newGroupButton").addEventListener("click", () => openDialog("groupDialog"));
document
  .querySelectorAll("[data-close]")
  .forEach((button) =>
    button.addEventListener("click", () => closeDialog(button.dataset.close)),
  );
document
  .querySelectorAll("dialog")
  .forEach((dialog) => dialog.addEventListener("close", clearInput));
$("weekTab").addEventListener("click", () => setPeriod("week"));
$("allTab").addEventListener("click", () => setPeriod("all"));
$("refreshButton").addEventListener("click", refreshBoard);
$("shareButton").addEventListener("click", async () => {
  if (!group) return;
  const url = new URL(location.href);
  url.search = "";
  url.searchParams.set("challenge", group.id);
  url.hash = "";
  try {
    await navigator.clipboard.writeText(url.href);
    notice("Challenge link copied. Send it to your friends.");
  } catch {
    notice("Copy the challenge link from your browser’s address bar.", 7000);
  }
});
$("groupForm").addEventListener("submit", async (event) => {
  event.preventDefault();
  const button = $("saveGroupButton");
  button.disabled = true;
  $("groupError").textContent = "";
  try {
    const created = await api("/groups", {
      name: $("challengeName").value.trim(),
    });
    if (ready) {
      Module._tiny_menu();
      clearInput();
    }
    currentSession = null;
    const url = new URL(location.href);
    url.search = "";
    url.searchParams.set("challenge", created.id);
    history.pushState(null, "", url);
    await loadGroup(created.id);
    closeDialog("groupDialog");
    notice("Challenge ready. Copy its link to invite your friends.");
  } catch (error) {
    $("groupError").textContent = error.message;
  } finally {
    button.disabled = false;
    updateState();
  }
});
$("fullscreenButton").addEventListener("click", async () => {
  try {
    if (document.fullscreenElement) await document.exitFullscreen();
    else await $("gameStage").closest(".race-panel").requestFullscreen();
  } catch {
    notice("Fullscreen isn’t available in this browser.");
  }
});
$("reloadButton").addEventListener("click", () => location.reload());
window.addEventListener("popstate", () => location.reload());
window.addEventListener("blur", pauseGame);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) pauseGame();
});
window.addEventListener("keydown", (event) => {
  if (
    event.target.closest("input, textarea, select, [contenteditable]") ||
    anyDialog() ||
    event.ctrlKey ||
    event.metaKey ||
    event.altKey
  )
    return;
  if (
    [
      "Minus",
      "NumpadSubtract",
      "Equal",
      "NumpadAdd",
      "Digit0",
      "Numpad0",
    ].includes(event.code)
  ) {
    event.preventDefault();
    setZoom(
      ["Digit0", "Numpad0"].includes(event.code)
        ? DEFAULT_ZOOM
        : zoom +
            (["Minus", "NumpadSubtract"].includes(event.code) ? -0.05 : 0.05),
    );
    return;
  }
  if (event.code in keyBits) {
    event.preventDefault();
    unlockAudio();
    keys.add(event.code);
    applyInput();
  }
  if (event.repeat) return;
  if (event.code === "Space" && !event.target.closest("button")) {
    event.preventDefault();
    if ([0, 4].includes(gameState())) startRun();
    else if (gameState() === 3) resumeGame();
    else pauseGame();
  }
  if (event.code === "Escape") {
    event.preventDefault();
    if (gameState() === 3) resumeGame();
    else pauseGame();
  }
  if (event.key === "?") {
    event.preventDefault();
    openDialog("helpDialog");
  }
});
window.addEventListener("keyup", (event) => {
  keys.delete(event.code);
  applyInput();
});
$("zoomOut").addEventListener("click", () => setZoom(zoom - 0.05));
$("zoomIn").addEventListener("click", () => setZoom(zoom + 0.05));
$("zoomReset").addEventListener("click", () => setZoom(DEFAULT_ZOOM));
$("canvas").addEventListener(
  "wheel",
  (event) => {
    if (
      !ready ||
      anyDialog() ||
      event.ctrlKey ||
      event.metaKey ||
      event.deltaY === 0
    )
      return;
    event.preventDefault();
    setZoom(zoom - Math.sign(event.deltaY) * 0.04);
  },
  { passive: false },
);
for (const button of document.querySelectorAll("[data-input]")) {
  button.addEventListener("pointerdown", (event) => {
    if (![1, 2].includes(gameState())) return;
    event.preventDefault();
    unlockAudio();
    button.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId, Number(button.dataset.input));
    button.classList.add("held");
    applyInput();
  });
  const release = (event) => {
    pointers.delete(event.pointerId);
    if (![...pointers.values()].includes(Number(button.dataset.input)))
      button.classList.remove("held");
    applyInput();
  };
  button.addEventListener("pointerup", release);
  button.addEventListener("pointercancel", release);
  button.addEventListener("lostpointercapture", release);
  button.addEventListener("contextmenu", (event) => event.preventDefault());
}
function fatal(message) {
  ready = false;
  $("loadingOverlay").hidden = false;
  $("loadingStatus").textContent = message;
  $("loadingProgress").hidden = true;
  $("reloadButton").hidden = false;
  $("playButton").disabled = true;
}
var Module = {
  canvas: $("canvas"),
  print: (...args) => console.log(...args),
  printErr: (...args) => console.error(...args),
  onAbort: () => fatal("The game couldn’t start. Please reload to try again."),
  setStatus(text) {
    if (ready) return;
    const progress = text?.match(/\((\d+(?:\.\d+)?)\/(\d+)\)/);
    if (progress)
      $("loadingProgress").value =
        (Number(progress[1]) / Number(progress[2])) * 100;
    if (text)
      $("loadingStatus").textContent = text.replace(/\(.*\)/, "").trim();
  },
  onRuntimeInitialized() {
    if (
      typeof Module._tiny_metric !== "function" ||
      Module._tiny_metric(17) !== BRIDGE_VERSION
    ) {
      fatal("The game files are out of date. Reload to get matching rules.");
      return;
    }
    ready = true;
    setZoom(DEFAULT_ZOOM);
    $("loadingOverlay").hidden = true;
    $("playButton").disabled = false;
    syncSound();
    updateState();
    if (document.hidden) pauseGame();
  },
};
$("canvas").addEventListener("webglcontextlost", (event) => {
  event.preventDefault();
  pauseGame();
  fatal("The graphics context was lost. Reload to drive again.");
});
window.addEventListener("error", (event) => {
  if (/index\.(js|wasm)/.test(event.filename || ""))
    fatal("The game hit a problem. Reload to try again.");
});
const challenge = new URL(location.href).searchParams.get("challenge");
if (challenge) loadGroup(challenge);
const pending = storage.read("pending", []);
if (Array.isArray(pending))
  for (const item of pending)
    if (
      item?.session?.expiresAt > Date.now() &&
      item?.result?.version === VERSION
    )
      submitResult(item);
setInterval(() => {
  if (!document.hidden && ![1, 2].includes(gameState())) refreshBoard();
}, 20000);
requestAnimationFrame(poll);
