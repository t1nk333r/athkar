#!/usr/bin/env node
// Regenerates the golden fixtures under spec/ from the PWA's own code.
//
//   node tools/fixtures-generate.mjs
//
// The functions under test are not re-implemented here: their source text is cut verbatim out of the
// application <script> in index.html and evaluated in a `vm` context. Only UI side effects (rendering,
// dialogs, live-region announcements) are replaced by no-op stubs; `Date` is replaced by a subclass whose
// zero-argument form returns a fixed "now", and the process time zone is switched per case via TZ.
// Output is deterministic: running this twice produces byte-identical files.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const generator = "tools/fixtures-generate.mjs";

// ---------------------------------------------------------------------------------------------------
// Extraction from index.html
// ---------------------------------------------------------------------------------------------------

const html = readFileSync(join(root, "index.html"), "utf8");
const appScript = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)]
  .map(match => match[1])
  .find(text => text.includes("const collections ="));
if (!appScript) throw new Error("application <script> not found in index.html");
const lines = appScript.split("\n");

function lineIndex(predicate, what) {
  const index = lines.findIndex(predicate);
  if (index === -1) throw new Error(`${what} not found in index.html`);
  return index;
}

// Top-level declarations are indented four spaces; a function ends at the first `    }` line.
function extractFunction(name) {
  const start = lineIndex(line => line.startsWith(`    function ${name}(`), `function ${name}`);
  for (let end = start + 1; end < lines.length; end += 1) {
    if (lines[end] === "    }") return lines.slice(start, end + 1).join("\n");
  }
  throw new Error(`end of function ${name} not found`);
}

function extractConst(name) {
  const start = lineIndex(line => line.startsWith(`    const ${name} =`), `const ${name}`);
  if (lines[start].trimEnd().endsWith(";")) return lines[start];
  for (let end = start + 1; end < lines.length; end += 1) {
    if (/^    [}\])]+;$/.test(lines[end])) return lines.slice(start, end + 1).join("\n");
  }
  throw new Error(`end of const ${name} not found`);
}

// The adhkar data (ayatAlKursi … eveningAthkar) is everything between "use strict" and `const collections`.
const dataStart = lineIndex(line => line.trim() === '"use strict";', '"use strict"') + 1;
const dataEnd = lineIndex(line => line.startsWith("    const collections ="), "const collections");
const contentData = lines.slice(dataStart, dataEnd).join("\n");

const constants = [
  "collections", "sectionNames", "storageKey", "legacyStorageKey", "remindersStorageKey",
  "legacyRemindersStorageKey", "longDhikrThreshold", "prayerCalculationMethods", "asrShadowFactors",
  "currentIndices", "decks", "reminderTimers", "numberFormatter"
];

const functions = [
  // sessions
  "localDateKey", "emptyState", "normalizeState", "targetForState", "countForState",
  "periodCountersComplete", "periodIsManuallyComplete", "periodIsComplete", "historyEntryFor",
  "rollStateToDate", "loadState", "saveState", "targetFor", "countFor", "isLongDhikr", "buildDeck",
  "deck", "invalidateDecks", "firstIncompleteIndex", "syncCompletionState", "setManualCompletion",
  "hasResettableState", "resetDayProgress", "recentDates", "resetWeek", "resetEverything",
  "dayCountLabel", "formatNumber",
  // prayer times and reminders
  "emptyReminderPreferences", "normalizePrayerLocation", "toRadians", "toDegrees", "normalizeDegrees",
  "solarTerms", "dateAtLocalMinutes", "solarDay", "prayerTimesForDate", "notificationPermission",
  "nextReminderTime", "scheduleReminders"
];

// UI-only collaborators of the functions above. None of them affects the state under test.
const stubs = `
    const liveRegion = { textContent: "" };
    function renderCards() {}
    function updateHistoryView() {}
    function updateManualCompletionControls() {}
    function updateSessionProgress() {}
    function updateDeckNavigation() {}
    // Timer callbacks call showReminder(period); recording the argument identifies which period a timer is for.
    function showReminder(period) { __firedReminders.push(period); }
    // Stands in for the confirm dialog: the user presses the confirm button.
    function openConfirmation(title, copy, callback) { callback(); }
`;

const harnessSource = `
"use strict";
${contentData}
${constants.map(extractConst).join("\n")}
let state = null;
let reminderPreferences = null;
let longAdhkarLast = false;
let activePeriod = "morning";
${stubs}
${functions.map(extractFunction).join("\n\n")}
globalThis.__api = {
  realCollections: { morning: collections.morning, evening: collections.evening },
  setCollections(value) { collections.morning = value.morning; collections.evening = value.evening; },
  getState() { return state; },
  setState(value) { state = value; },
  setReminderPreferences(value) { reminderPreferences = value; },
  setLongAdhkarLast(value) { longAdhkarLast = value; },
  longDhikrThreshold,
  prayerCalculationMethods,
  asrShadowFactors,
  fns: { ${functions.join(", ")} }
};
`;

// ---------------------------------------------------------------------------------------------------
// Sandbox
// ---------------------------------------------------------------------------------------------------

const storage = new Map();
const timers = [];
const firedReminders = [];
const sandbox = {
  console,
  localStorage: {
    getItem: key => (storage.has(key) ? storage.get(key) : null),
    setItem: (key, value) => { storage.set(key, String(value)); },
    removeItem: key => { storage.delete(key); }
  },
  navigator: { serviceWorker: {} },
  Notification: { permission: "granted" },
  setTimeout: (callback, delay) => { timers.push({ callback, delay }); return timers.length; },
  clearTimeout: () => {},
  __firedReminders: firedReminders
};
sandbox.window = sandbox;
const context = vm.createContext(sandbox);
vm.runInContext(`
  const RealDate = Date;
  let fixedNow = 0;
  class FixedClockDate extends RealDate {
    constructor(...args) { if (args.length === 0) super(fixedNow); else super(...args); }
    static now() { return fixedNow; }
  }
  globalThis.Date = FixedClockDate;
  globalThis.__setNow = value => { fixedNow = value; };
`, context);
vm.runInContext(harnessSource, context, { filename: "index.html#app-script" });

const api = context.__api;
const fn = api.fns;
const setNow = context.__setNow;
const ContextDate = context.Date;

function setZone(timeZone) {
  process.env.TZ = timeZone;
}

// Local wall-clock time in `timeZone` → epoch ms (via the host's local-time conversion under TZ).
function localMs(timeZone, y, m, d, h = 0, mi = 0, s = 0, ms = 0) {
  setZone(timeZone);
  return new Date(y, m - 1, d, h, mi, s, ms).getTime();
}

function iso(value) {
  return value ? new Date(value.getTime()).toISOString() : null;
}

function localIso(timeZone, epochMs) {
  setZone(timeZone);
  const date = new Date(epochMs);
  const pad = (value, width = 2) => String(value).padStart(width, "0");
  const offset = -date.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:` +
    `${pad(date.getMinutes())}:${pad(date.getSeconds())}.${pad(date.getMilliseconds(), 3)}` +
    `${sign}${pad(Math.floor(Math.abs(offset) / 60))}:${pad(Math.abs(offset) % 60)}`;
}

// Deep copy across the realm boundary into plain host JSON values.
function plain(value) {
  return value === undefined ? null : JSON.parse(JSON.stringify(value));
}

function intoContext(value) {
  return vm.runInContext(`(${JSON.stringify(value)})`, context);
}

// Rule-relevant projection of adhkar items (text is irrelevant to session rules).
function projectItem(item) {
  const out = { id: item.id };
  if (item.count !== undefined) out.count = item.count;
  if (item.targetOptions !== undefined) out.targetOptions = [...item.targetOptions];
  if (item.defaultTarget !== undefined) out.defaultTarget = item.defaultTarget;
  if (item.review !== undefined) out.review = item.review;
  return out;
}

const realCollections = {
  morning: api.realCollections.morning.map(projectItem),
  evening: api.realCollections.evening.map(projectItem)
};

// Every case runs from a clean slate; returns the effective input.
function prepare(input) {
  setZone(input.timeZone);
  setNow(input.now ? Date.parse(input.now) : 0);
  api.setCollections(intoContext(input.collections));
  api.setState(input.state ? intoContext(input.state) : null);
  api.setLongAdhkarLast(Boolean(input.longAdhkarLast));
  api.setReminderPreferences(intoContext(input.preferences ?? fn.emptyReminderPreferences()));
  context.Notification.permission = input.notificationPermission ?? "granted";
  storage.clear();
  for (const [key, value] of Object.entries(input.storage ?? {})) storage.set(key, value);
  timers.length = 0;
  firedReminders.length = 0;
  fn.invalidateDecks();
}

function fixtureFile(meta, defaultInput, cases) {
  const names = new Set();
  for (const entry of cases) {
    if (names.has(entry.name)) throw new Error(`duplicate case name: ${entry.name}`);
    names.add(entry.name);
  }
  return { ...meta, generator, defaultInput, cases };
}

function writeJson(relativePath, value) {
  const path = join(root, relativePath);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
  return relativePath;
}

// ---------------------------------------------------------------------------------------------------
// Session fixtures
// ---------------------------------------------------------------------------------------------------

const SESSION_ZONE = "Asia/Riyadh";
const sessionDefaults = { timeZone: SESSION_ZONE, collections: realCollections };

function targetOf(item) {
  if (item.targetOptions) return item.defaultTarget;
  return item.count || 1;
}

function fullProgress(items) {
  return Object.fromEntries(items.filter(item => !item.review).map(item => [item.id, targetOf(item)]));
}

function baseState(date, overrides = {}) {
  return {
    date,
    progress: { morning: {}, evening: {} },
    targets: { morning: {}, evening: {} },
    completedAt: { morning: null, evening: null },
    manualCompletion: { morning: false, evening: false },
    history: [],
    ...overrides
  };
}

function historyEntry(date, morning, evening, morningAt = null, eveningAt = null) {
  return { date, morning, evening, morningAt, eveningAt };
}

const morningAllDone = fullProgress(realCollections.morning);
const eveningAllDone = fullProgress(realCollections.evening);
const morningAllButLast = Object.fromEntries(Object.entries(morningAllDone).slice(0, -1));
const tawhidMorningId = realCollections.morning.find(item => item.targetOptions)?.id;
const tawhidEveningId = realCollections.evening.find(item => item.targetOptions)?.id;
if (!tawhidMorningId || !tawhidEveningId) throw new Error("expected an item with targetOptions in each period");

// Synthetic collections exercise rules the shipped content does not currently trigger
// (review items, the 9/10 threshold boundary, decks shorter than three items).
const syntheticCollections = {
  morning: [
    { id: "s-01", count: 3 },
    { id: "s-02", count: 9 },
    { id: "s-03", count: 10 },
    { id: "s-04", targetOptions: [1, 10, 100], defaultTarget: 100 },
    { id: "s-05", review: true, count: 100 },
    { id: "s-06" },
    { id: "s-07", count: 11 },
    { id: "s-08", count: 100 }
  ],
  evening: [
    { id: "t-01", review: true },
    { id: "t-02", count: 50 },
    { id: "t-03" }
  ]
};
const shortCollections = {
  morning: [{ id: "u-01", count: 100 }, { id: "u-02" }],
  evening: []
};

function periodCompletion(input) {
  prepare(input);
  const state = api.getState();
  return Object.fromEntries(["morning", "evening"].map(period => [period, {
    countersComplete: fn.periodCountersComplete(period, state),
    manuallyComplete: fn.periodIsManuallyComplete(period, state),
    complete: fn.periodIsComplete(period, state)
  }]));
}

function periodIsCompleteCases() {
  const cases = [
    ["empty state: nothing complete", {}],
    ["all counters at target in both periods", { progress: { morning: morningAllDone, evening: eveningAllDone } }],
    ["all but the last morning item: morning incomplete", { progress: { morning: morningAllButLast, evening: {} } }],
    ["counters above target are clamped and still complete", {
      progress: {
        morning: Object.fromEntries(Object.entries(morningAllDone).map(([id, value]) => [id, value * 5])),
        evening: {}
      }
    }],
    ["fractional counts are floored (2.9 of 3 is incomplete)", {
      progress: { morning: { ...morningAllDone, [realCollections.morning.find(i => i.count === 3).id]: 2.9 }, evening: {} }
    }],
    ["negative, NaN and string counts count as zero / numeric", {
      progress: {
        morning: { ...morningAllDone, [realCollections.morning[0].id]: -1 },
        evening: { ...eveningAllDone, [realCollections.evening[0].id]: "1", [realCollections.evening[1].id]: "abc" }
      }
    }],
    ["manual completion alone completes the period", { manualCompletion: { morning: true, evening: false } }],
    ["manual completion and counters both complete", {
      progress: { morning: {}, evening: eveningAllDone },
      manualCompletion: { morning: false, evening: true }
    }],
    ["stored target 10 in targetOptions: 10 is enough", {
      progress: { morning: { ...morningAllDone, [tawhidMorningId]: 10 }, evening: {} },
      targets: { morning: { [tawhidMorningId]: 10 }, evening: {} }
    }],
    ["stored target not in targetOptions falls back to defaultTarget 100", {
      progress: { morning: { ...morningAllDone, [tawhidMorningId]: 10 }, evening: {} },
      targets: { morning: { [tawhidMorningId]: 7 }, evening: {} }
    }],
    ["stored target as string '1' is accepted", {
      progress: { morning: { ...morningAllDone, [tawhidMorningId]: 1 }, evening: {} },
      targets: { morning: { [tawhidMorningId]: "1" }, evening: {} }
    }]
  ].map(([name, overrides]) => {
    const input = { ...sessionDefaults, state: baseState("2026-09-23", overrides) };
    return { name, input: { state: input.state }, expected: periodCompletion(input) };
  });

  const syntheticDone = fullProgress(syntheticCollections.morning);
  for (const [name, progress] of [
    ["review item is excluded: complete without counting it", syntheticDone],
    ["review item progress is ignored and non-review gap keeps it incomplete", { ...syntheticDone, "s-05": 100, "s-06": 0 }]
  ]) {
    const input = {
      ...sessionDefaults,
      collections: syntheticCollections,
      state: baseState("2026-09-23", { progress: { morning: progress, evening: { "t-02": 50, "t-03": 1 } } })
    };
    cases.push({ name, input: { collections: syntheticCollections, state: input.state }, expected: periodCompletion(input) });
  }
  const allReviewInput = {
    ...sessionDefaults,
    collections: { morning: [{ id: "r-01", review: true }], evening: [] },
    state: baseState("2026-09-23")
  };
  cases.push({
    name: "a period whose items are all review items (or empty) is vacuously complete",
    input: { collections: allReviewInput.collections, state: allReviewInput.state },
    expected: periodCompletion(allReviewInput)
  });
  return cases;
}

function rollCase(name, state, nextDate, collections) {
  const input = { ...sessionDefaults, state, ...(collections ? { collections } : {}) };
  prepare(input);
  const rolled = fn.rollStateToDate(api.getState(), nextDate);
  return {
    name,
    input: { ...(collections ? { collections } : {}), state, nextDate },
    expected: { state: plain(rolled) }
  };
}

function rollStateToDateCases() {
  const eightDays = Array.from({ length: 8 }, (_, index) => {
    const day = 22 - index;
    return historyEntry(`2026-09-${String(day).padStart(2, "0")}`, index % 2 === 0, index % 3 === 0);
  });
  return [
    rollCase("empty day rolls into an incomplete history entry", baseState("2026-09-23"), "2026-09-24"),
    rollCase("counter-completed morning is recorded with its completedAt", baseState("2026-09-23", {
      progress: { morning: morningAllDone, evening: { [realCollections.evening[0].id]: 1 } },
      completedAt: { morning: "2026-09-23T03:15:00.000Z", evening: null }
    }), "2026-09-24"),
    rollCase("manual completion counts as complete in history", baseState("2026-09-23", {
      manualCompletion: { morning: false, evening: true },
      completedAt: { morning: null, evening: "2026-09-23T15:00:00.000Z" }
    }), "2026-09-24"),
    rollCase("targets, progress and manual flags are cleared for the new day", baseState("2026-09-23", {
      progress: { morning: { [tawhidMorningId]: 5 }, evening: { [tawhidEveningId]: 10 } },
      targets: { morning: { [tawhidMorningId]: 10 }, evening: { [tawhidEveningId]: 10 } },
      manualCompletion: { morning: true, evening: false },
      completedAt: { morning: "2026-09-23T04:00:00.000Z", evening: null }
    }), "2026-09-24"),
    rollCase("new entry is prepended to existing history", baseState("2026-09-23", {
      history: [historyEntry("2026-09-22", true, true, "2026-09-22T03:00:00.000Z", "2026-09-22T14:00:00.000Z"),
        historyEntry("2026-09-21", false, true, null, "2026-09-21T14:00:00.000Z")]
    }), "2026-09-24"),
    rollCase("existing history entry for the same date is replaced, not duplicated", baseState("2026-09-23", {
      progress: { morning: morningAllDone, evening: {} },
      history: [historyEntry("2026-09-23", false, true), historyEntry("2026-09-22", true, false)]
    }), "2026-09-24"),
    rollCase("history is trimmed to 7 entries (newest first)", baseState("2026-09-23", { history: eightDays }), "2026-09-24"),
    rollCase("multi-day gap adds only the stored day; skipped days get no entries", baseState("2026-09-20", {
      progress: { morning: morningAllDone, evening: eveningAllDone }
    }), "2026-09-23"),
    rollCase("review items do not block completion when rolling", baseState("2026-09-23", {
      progress: { morning: fullProgress(syntheticCollections.morning), evening: {} }
    }), "2026-09-24", syntheticCollections)
  ];
}

function loadCase(name, timeZone, nowMs, storageEntries) {
  const now = new Date(nowMs).toISOString();
  const input = { ...sessionDefaults, timeZone, now, storage: storageEntries };
  prepare(input);
  const loaded = fn.loadState();
  return {
    name,
    input: { timeZone, now, nowLocal: localIso(timeZone, nowMs), storage: storageEntries },
    expected: { state: plain(loaded) }
  };
}

function loadStateCases() {
  const z = SESSION_ZONE;
  const stored = baseState("2026-09-23", {
    progress: { morning: morningAllDone, evening: { [realCollections.evening[0].id]: 1 } },
    completedAt: { morning: "2026-09-23T03:15:00.000Z", evening: null },
    history: [historyEntry("2026-09-22", true, false, "2026-09-22T03:00:00.000Z", null)]
  });
  const storedJson = JSON.stringify(stored);
  const ny = "America/New_York";
  const nyStored = JSON.stringify(baseState("2026-03-07", { manualCompletion: { morning: true, evening: false } }));
  return [
    loadCase("same local date: state kept as-is", z, localMs(z, 2026, 9, 23, 23, 59, 59, 999), { "athkar-progress-v2": storedJson }),
    loadCase("first instant of the next local day rolls over", z, localMs(z, 2026, 9, 24, 0, 0, 0, 0), { "athkar-progress-v2": storedJson }),
    loadCase("UTC date differs but local date is the same: no rollover", z, localMs(z, 2026, 9, 24, 1, 30), {
      "athkar-progress-v2": JSON.stringify(baseState("2026-09-24"))
    }),
    loadCase("several days later: single history entry for the stored day", z, localMs(z, 2026, 9, 27, 9, 0), { "athkar-progress-v2": storedJson }),
    loadCase("nothing stored: empty state for today", z, localMs(z, 2026, 9, 23, 8, 0), {}),
    loadCase("malformed JSON: empty state for today", z, localMs(z, 2026, 9, 23, 8, 0), { "athkar-progress-v2": "{not json" }),
    loadCase("non-object JSON (number) → empty state", z, localMs(z, 2026, 9, 23, 8, 0), { "athkar-progress-v2": "42" }),
    loadCase("legacy v1 key is read when v2 is absent; skipped maps to manualCompletion", z, localMs(z, 2026, 9, 23, 8, 0), {
      "athkar-progress-v1": JSON.stringify({
        date: "2026-09-23",
        progress: { morning: { [realCollections.morning[0].id]: 1 } },
        skipped: { morning: false, evening: true },
        history: [{ date: "2026-09-22", morningSkipped: true, evening: false }]
      })
    }),
    loadCase("v2 wins over legacy v1 when both are present", z, localMs(z, 2026, 9, 23, 8, 0), {
      "athkar-progress-v2": JSON.stringify(baseState("2026-09-23", { manualCompletion: { morning: false, evening: true } })),
      "athkar-progress-v1": JSON.stringify(baseState("2026-09-23", { manualCompletion: { morning: true, evening: false } }))
    }),
    loadCase("normalization: invalid date falls back to today (no roll); bad fields and history garbage sanitized", z, localMs(z, 2026, 9, 23, 8, 0), {
      "athkar-progress-v2": JSON.stringify({
        date: "23/09/2026",
        progress: { morning: "oops", evening: null },
        targets: [],
        completedAt: { morning: 123, evening: "2026-09-22T14:00:00.000Z" },
        manualCompletion: { morning: 1, evening: 0 },
        history: [null, { date: 5 }, { date: "2026-09-21", morning: 1, morningAt: 7, eveningAt: "x" },
          ...Array.from({ length: 8 }, (_, i) => ({ date: `2026-09-${String(20 - i).padStart(2, "0")}`, evening: true }))]
      })
    }),
    loadCase("normalization trims stored history to 7 before rolling adds today's predecessor", z, localMs(z, 2026, 9, 24, 8, 0), {
      "athkar-progress-v2": JSON.stringify(baseState("2026-09-23", {
        history: Array.from({ length: 9 }, (_, i) => historyEntry(`2026-09-${String(22 - i).padStart(2, "0")}`, true, true))
      }))
    }),
    loadCase("DST spring-forward night (America/New_York): rolls at local midnight", ny, localMs(ny, 2026, 3, 8, 0, 0, 0, 1), { "athkar-progress-v2": nyStored }),
    loadCase("DST spring-forward day, 03:00 local (just after the gap): same day, no second roll", ny, localMs(ny, 2026, 3, 8, 3, 0), {
      "athkar-progress-v2": JSON.stringify(baseState("2026-03-08"))
    }),
    loadCase("DST fall-back day, second 01:30 local: still the same local date", ny, Date.parse("2026-11-01T06:30:00.000Z"), {
      "athkar-progress-v2": JSON.stringify(baseState("2026-11-01"))
    })
  ];
}

function deckCase(name, collections, longAdhkarLast, targets = { morning: {}, evening: {} }) {
  const input = { ...sessionDefaults, collections, longAdhkarLast, state: baseState("2026-09-23", { targets }) };
  prepare(input);
  const expected = {};
  for (const period of ["morning", "evening"]) {
    expected[period] = {
      deck: fn.buildDeck(period).map(item => item.id),
      longItems: collections[period].filter(item => fn.isLongDhikr(item, period)).map(item => item.id)
    };
  }
  const caseInput = { longAdhkarLast, state: input.state };
  if (collections !== realCollections) caseInput.collections = collections;
  return { name, input: caseInput, expected };
}

function buildDeckCases() {
  return [
    deckCase("real content, longAdhkarLast false: original order", realCollections, false),
    deckCase("real content, longAdhkarLast true: long items (target ≥ 10) moved before the last item", realCollections, true),
    deckCase("real content, longAdhkarLast true, tawhid target 1: tawhid is not long", realCollections, true, {
      morning: { [tawhidMorningId]: 1 }, evening: { [tawhidEveningId]: 1 }
    }),
    deckCase("real content, longAdhkarLast true, tawhid target 10: exactly the threshold is long", realCollections, true, {
      morning: { [tawhidMorningId]: 10 }, evening: { [tawhidEveningId]: 10 }
    }),
    deckCase("threshold boundary: 9 stays, 10 and 11 move, review item with count 100 stays", syntheticCollections, true),
    deckCase("synthetic content, longAdhkarLast false: unchanged", syntheticCollections, false),
    deckCase("synthetic, stored target 1 for the targetOptions item keeps it in place", syntheticCollections, true, {
      morning: { "s-04": 1 }, evening: {}
    }),
    deckCase("decks shorter than 3 items are never reordered", shortCollections, true)
  ];
}

function firstIncompleteCase(name, collections, longAdhkarLast, overrides) {
  const state = baseState("2026-09-23", overrides);
  const input = { ...sessionDefaults, collections, longAdhkarLast, state };
  prepare(input);
  const expected = {};
  for (const period of ["morning", "evening"]) {
    const index = fn.firstIncompleteIndex(period);
    expected[period] = { index, itemId: fn.deck(period)[index]?.id ?? null };
  }
  const caseInput = { longAdhkarLast, state };
  if (collections !== realCollections) caseInput.collections = collections;
  return { name, input: caseInput, expected };
}

function firstIncompleteIndexCases() {
  const firstThree = Object.fromEntries(realCollections.morning.slice(0, 3).map(item => [item.id, targetOf(item)]));
  return [
    firstIncompleteCase("nothing done: index 0", realCollections, false, {}),
    firstIncompleteCase("first three morning items done: index 3", realCollections, false, { progress: { morning: firstThree, evening: {} } }),
    firstIncompleteCase("partially counted item is still incomplete", realCollections, false, {
      progress: { morning: { ...firstThree, [realCollections.morning[3].id]: Math.max(0, targetOf(realCollections.morning[3]) - 1) }, evening: {} }
    }),
    firstIncompleteCase("everything done: last index", realCollections, false, { progress: { morning: morningAllDone, evening: eveningAllDone } }),
    firstIncompleteCase("manual completion does not change the index", realCollections, false, { manualCompletion: { morning: true, evening: true } }),
    firstIncompleteCase("longAdhkarLast true: index is into the reordered deck", realCollections, true, {
      progress: { morning: fullProgress(realCollections.morning.slice(0, 19)), evening: fullProgress(realCollections.evening.slice(0, 19)) }
    }),
    firstIncompleteCase("same progress with longAdhkarLast false: index into the original order", realCollections, false, {
      progress: { morning: fullProgress(realCollections.morning.slice(0, 19)), evening: fullProgress(realCollections.evening.slice(0, 19)) }
    }),
    firstIncompleteCase("all short items done with longAdhkarLast true: first long item", realCollections, true, {
      progress: {
        morning: fullProgress(realCollections.morning.filter(item => targetOf(item) < 10)),
        evening: fullProgress(realCollections.evening.filter(item => targetOf(item) < 10))
      }
    }),
    firstIncompleteCase("leading review item is skipped", syntheticCollections, false, {}),
    firstIncompleteCase("review item in the middle is skipped", syntheticCollections, false, {
      progress: { morning: { "s-01": 3, "s-02": 9, "s-03": 10, "s-04": 100 }, evening: { "t-02": 50 } }
    }),
    firstIncompleteCase("two-item deck and empty deck: empty yields index 0 with no item", shortCollections, false, {})
  ];
}

function completionCase(name, operation, overrides, collections = realCollections) {
  const state = baseState("2026-09-23", overrides);
  const now = new Date(localMs(SESSION_ZONE, 2026, 9, 23, 7, 30)).toISOString();
  const input = { ...sessionDefaults, collections, state, now };
  prepare(input);
  let returned = null;
  if (operation.function === "syncCompletionState") {
    returned = plain(fn.syncCompletionState(operation.period));
  } else {
    fn.setManualCompletion(operation.period, operation.completed);
  }
  const caseInput = { now, state, operation };
  if (collections !== realCollections) caseInput.collections = collections;
  return { name, input: caseInput, expected: { returned, state: plain(api.getState()) } };
}

function completionCases() {
  const sync = { function: "syncCompletionState", period: "morning" };
  const manualOn = { function: "setManualCompletion", period: "morning", completed: true };
  const manualOff = { function: "setManualCompletion", period: "morning", completed: false };
  return [
    completionCase("sync: counters reach target → completedAt stamped with now, newlyCompleted", sync, {
      progress: { morning: morningAllDone, evening: {} }
    }),
    completionCase("sync: counters complete while manually complete → manual flag cleared, not newly completed", sync, {
      progress: { morning: morningAllDone, evening: {} },
      manualCompletion: { morning: true, evening: false },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("sync: already complete with completedAt → timestamp kept, not newly completed", sync, {
      progress: { morning: morningAllDone, evening: {} },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("sync: counter reset below target clears completedAt", sync, {
      progress: { morning: morningAllButLast, evening: {} },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("sync: incomplete counters but manual completion keeps completedAt", sync, {
      progress: { morning: morningAllButLast, evening: {} },
      manualCompletion: { morning: true, evening: false },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("sync: review items ignored when deciding completion", sync, {
      progress: { morning: fullProgress(syntheticCollections.morning), evening: {} }
    }, syntheticCollections),
    completionCase("manual on: sets flag and stamps completedAt with now", manualOn, {}),
    completionCase("manual on: existing completedAt is kept", manualOn, {
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("manual off: clears flag and completedAt", manualOff, {
      manualCompletion: { morning: true, evening: false },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    }),
    completionCase("manual toggle is ignored when counters are already complete", manualOff, {
      progress: { morning: morningAllDone, evening: {} },
      completedAt: { morning: "2026-09-23T02:00:00.000Z", evening: null }
    })
  ];
}

function resetCase(name, scope, timeZone, nowMs, state) {
  const now = new Date(nowMs).toISOString();
  const input = { ...sessionDefaults, timeZone, now, state };
  prepare(input);
  const hasResettableStateBefore = fn.hasResettableState();
  const recentDates = scope === "week" ? plain(fn.recentDates(7)) : undefined;
  if (scope === "day") fn.resetDayProgress(false);
  else if (scope === "week") fn.resetWeek();
  else fn.resetEverything();
  return {
    name,
    input: { timeZone, now, nowLocal: localIso(timeZone, nowMs), scope, state },
    expected: {
      hasResettableStateBefore,
      ...(recentDates ? { deletedHistoryDates: recentDates } : {}),
      state: plain(api.getState())
    }
  };
}

function scopedResetCases() {
  const z = SESSION_ZONE;
  const history = Array.from({ length: 7 }, (_, i) =>
    historyEntry(`2026-09-${String(22 - i * 2).padStart(2, "0")}`, true, i % 2 === 0));
  // dates: 22, 20, 18, 16, 14, 12, 10 — relative to 2026-09-23 the week window is 17..23
  const busy = baseState("2026-09-23", {
    progress: { morning: morningAllDone, evening: { [tawhidEveningId]: 40 } },
    targets: { morning: {}, evening: { [tawhidEveningId]: 100 } },
    completedAt: { morning: "2026-09-23T03:15:00.000Z", evening: null },
    manualCompletion: { morning: false, evening: true },
    history
  });
  const now = localMs(z, 2026, 9, 23, 20, 0);
  const ny = "America/New_York";
  const nyState = baseState("2026-03-10", {
    history: [historyEntry("2026-03-09", true, true), historyEntry("2026-03-08", true, false),
      historyEntry("2026-03-04", false, true), historyEntry("2026-03-03", true, true)]
  });
  return [
    resetCase("day: counters, completedAt and manual flags cleared; targets and history kept", "day", z, now, busy),
    resetCase("week: history entries from the last 7 local dates (today inclusive) removed, then day reset", "week", z, now, busy),
    resetCase("everything: all history removed, then day reset", "everything", z, now, busy),
    resetCase("nothing to reset: hasResettableState false", "day", z, now, baseState("2026-09-23")),
    resetCase("history alone makes state resettable", "everything", z, now, baseState("2026-09-23", {
      history: [historyEntry("2026-09-01", false, false)]
    })),
    resetCase("week window spans a DST change (America/New_York): 7 local dates, boundary entry kept", "week", ny,
      localMs(ny, 2026, 3, 10, 12, 0), nyState)
  ];
}

// ---------------------------------------------------------------------------------------------------
// Prayer-time vectors
// ---------------------------------------------------------------------------------------------------

// Coordinates are rounded to two decimals, matching what the native app persists (NATIVE_APP_PLAN.md §7.4).
const locations = [
  ["mecca", 21.42, 39.83, "Asia/Riyadh"],
  ["medina", 24.47, 39.61, "Asia/Riyadh"],
  ["dubai", 25.2, 55.27, "Asia/Dubai"],
  ["cairo", 30.04, 31.24, "Africa/Cairo"],
  ["istanbul", 41.01, 28.98, "Europe/Istanbul"],
  ["tehran", 35.69, 51.39, "Asia/Tehran"],
  ["karachi", 24.86, 67.01, "Asia/Karachi"],
  ["delhi", 28.61, 77.21, "Asia/Kolkata"],
  ["dhaka", 23.81, 90.41, "Asia/Dhaka"],
  ["kuala-lumpur", 3.14, 101.69, "Asia/Kuala_Lumpur"],
  ["singapore", 1.35, 103.82, "Asia/Singapore"],
  ["jakarta", -6.21, 106.85, "Asia/Jakarta"],
  ["nairobi", -1.29, 36.82, "Africa/Nairobi"],
  ["lagos", 6.52, 3.38, "Africa/Lagos"],
  ["casablanca", 33.57, -7.59, "Africa/Casablanca"],
  ["johannesburg", -26.2, 28.05, "Africa/Johannesburg"],
  ["london", 51.51, -0.13, "Europe/London"],
  ["paris", 48.86, 2.35, "Europe/Paris"],
  ["berlin", 52.52, 13.4, "Europe/Berlin"],
  ["stockholm", 59.33, 18.07, "Europe/Stockholm"],
  ["oslo", 59.91, 10.75, "Europe/Oslo"],
  ["reykjavik", 64.15, -21.94, "Atlantic/Reykjavik"],
  ["tromso", 69.65, 18.96, "Europe/Oslo"],
  ["anchorage", 61.22, -149.9, "America/Anchorage"],
  ["new-york", 40.71, -74.01, "America/New_York"],
  ["toronto", 43.65, -79.38, "America/Toronto"],
  ["los-angeles", 34.05, -118.24, "America/Los_Angeles"],
  ["sao-paulo", -23.55, -46.63, "America/Sao_Paulo"],
  ["sydney", -33.87, 151.21, "Australia/Sydney"],
  ["auckland", -36.85, 174.76, "Pacific/Auckland"]
].map(([id, latitude, longitude, timeZone]) => ({ id, latitude, longitude, timeZone }));

// Solstices, equinoxes, and the 2026 DST transition dates of the US, EU and Australia.
const dates = [
  ["2026-01-15", "northern winter"],
  ["2026-03-08", "US DST starts"],
  ["2026-03-20", "March equinox"],
  ["2026-03-29", "EU DST starts"],
  ["2026-04-05", "Australia/NZ DST ends"],
  ["2026-06-21", "June solstice"],
  ["2026-08-15", "northern summer"],
  ["2026-09-23", "September equinox"],
  ["2026-10-04", "Australia DST starts"],
  ["2026-10-25", "EU DST ends"],
  ["2026-11-01", "US DST ends"],
  ["2026-12-21", "December solstice"]
].map(([date, note]) => ({ date, note }));

function prayerVectors() {
  const vectors = [];
  for (const location of locations) {
    for (const { date } of dates) {
      const [y, m, d] = date.split("-").map(Number);
      for (const method of Object.keys(api.prayerCalculationMethods)) {
        for (const asrSchool of Object.keys(api.asrShadowFactors)) {
          const fajrAngle = api.prayerCalculationMethods[method].fajrAngle;
          const asrShadowFactor = api.asrShadowFactors[asrSchool];
          setZone(location.timeZone);
          setNow(0);
          // The PWA passes "now"; only the local calendar date is used. Local noon avoids DST gaps.
          const day = new ContextDate(y, m - 1, d, 12);
          const preferences = intoContext({
            ...fn.emptyReminderPreferences(),
            calculationMethod: method,
            asrSchool,
            location: { latitude: location.latitude, longitude: location.longitude, updatedAt: null }
          });
          const result = fn.prayerTimesForDate(day, preferences);
          const solar = fn.solarDay(day, fn.normalizePrayerLocation(preferences.location), fajrAngle, asrShadowFactor);
          let fajrRule = null;
          if (result) fajrRule = solar.fajr && solar.fajr.getTime() === result.fajr.getTime() ? "angle" : "night-fraction";
          vectors.push({
            location: location.id,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZone: location.timeZone,
            date,
            method,
            fajrAngle,
            asrSchool,
            asrShadowFactor,
            expected: {
              computed: Boolean(result),
              fajr: result ? iso(result.fajr) : null,
              sunrise: iso(solar.sunrise),
              asr: result ? iso(result.asr) : null,
              sunset: iso(solar.sunset),
              fajrRule
            }
          });
        }
      }
    }
  }
  return vectors;
}

function writeVectors(relativePath) {
  const vectors = prayerVectors();
  const header = {
    about: "PWA prayerTimesForDate/solarDay output. Parity oracle for Fajr, sunrise, Asr and sunset only (NATIVE_APP_PLAN.md §7.1–7.2 P1).",
    source: "index.html: prayerTimesForDate, solarDay (and solarTerms, dateAtLocalMinutes, normalizePrayerLocation)",
    generator,
    tolerance: {
      seconds: 120,
      reference: "NATIVE_APP_PLAN.md §7.2 P1 (2 minutes). A vector outside tolerance fails the gate unless explained in spec/prayer-times/README.md (e.g. PWA night-fraction Fajr clamp vs Adhan's high-latitude rule)."
    },
    fields: {
      fajr: "prayerTimesForDate().fajr — angle-based Fajr, or the night-fraction clamp sunrise − night × fajrAngle/60 when that is later or the angle is unreachable (fajrRule says which).",
      sunrise: "solarDay(date).sunrise — sun at −0.833°. null when the sun does not cross that altitude.",
      asr: "prayerTimesForDate().asr — shadow factor 1 (standard) or 2 (hanafi).",
      sunset: "solarDay(date).sunset — sun at −0.833°.",
      computed: "false when prayerTimesForDate returned null (no sunrise, no Asr, or no Fajr); fajr/asr are then null.",
      date: "Local calendar date in timeZone. Times are UTC instants."
    },
    highLatitudeRule: "Fixed in the PWA (not configurable): Fajr = max(angle Fajr, sunrise − (sunrise − previous day's sunset) × fajrAngle/60). Same portion as Adhan's .twilightAngle, but Adhan measures the night from today's sunset to tomorrow's sunrise.",
    methods: plain(api.prayerCalculationMethods),
    asrShadowFactors: plain(api.asrShadowFactors),
    locations,
    dates,
    vectorCount: vectors.length
  };
  const headerJson = JSON.stringify(header, null, 2);
  const body = vectors.map(vector => `    ${JSON.stringify(vector)}`).join(",\n");
  const text = `${headerJson.slice(0, -2)},\n  "vectors": [\n${body}\n  ]\n}\n`;
  JSON.parse(text);
  const path = join(root, relativePath);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
  return { path: relativePath, count: vectors.length };
}

// ---------------------------------------------------------------------------------------------------
// Reminder fixtures
// ---------------------------------------------------------------------------------------------------

const PERIODS = ["morning", "evening"];

function reminderPreferences(location, overrides = {}) {
  return {
    morning: { enabled: true },
    evening: { enabled: true },
    calculationMethod: "mwl",
    asrSchool: "standard",
    location: location ? { latitude: location.latitude, longitude: location.longitude, updatedAt: "2026-01-01T00:00:00.000Z" } : null,
    lastShown: { morning: null, evening: null },
    ...overrides
  };
}

function reminderCase(name, { timeZone, nowMs, preferences, state, notificationPermission = "granted" }) {
  const now = new Date(nowMs).toISOString();
  const sessionState = state ?? baseState(localIso(timeZone, nowMs).slice(0, 10));
  const input = { ...sessionDefaults, timeZone, now, preferences, state: sessionState, notificationPermission };
  prepare(input);
  const schedule = fn.prayerTimesForDate(new ContextDate());
  const nextReminderTime = {};
  for (const period of PERIODS) nextReminderTime[period] = iso(fn.nextReminderTime(period, new ContextDate()));
  prepare(input);
  fn.scheduleReminders();
  const scheduled = { morning: null, evening: null };
  for (const timer of timers) {
    timer.callback();
    const period = firedReminders.pop();
    scheduled[period] = { delayMs: timer.delay, fireAt: new Date(nowMs + timer.delay).toISOString() };
  }
  return {
    name,
    input: { timeZone, now, nowLocal: localIso(timeZone, nowMs), notificationPermission, preferences, state: sessionState },
    expected: {
      todaySchedule: schedule ? { fajr: iso(schedule.fajr), asr: iso(schedule.asr), morning: iso(schedule.morning), evening: iso(schedule.evening) } : null,
      nextReminderTime,
      scheduled
    }
  };
}

function scheduleFor(timeZone, location, y, m, d, preferences = reminderPreferences(location)) {
  setZone(timeZone);
  setNow(0);
  const result = fn.prayerTimesForDate(new ContextDate(y, m - 1, d, 12), intoContext(preferences));
  return result ? { morning: result.morning.getTime(), evening: result.evening.getTime() } : null;
}

function reminderCases() {
  const mecca = locations.find(l => l.id === "mecca");
  const z = mecca.timeZone;
  const prefs = reminderPreferences(mecca);
  const today = scheduleFor(z, mecca, 2026, 9, 23);
  const MIN = 60 * 1000;
  const cases = [
    reminderCase("before both: fire today at fajr+60 and asr+60", { timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: prefs }),
    reminderCase("morning already shown today: next morning is tomorrow's", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: { ...prefs, lastShown: { morning: "2026-09-23", evening: null } }
    }),
    reminderCase("lastShown yesterday does not suppress today", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: { ...prefs, lastShown: { morning: "2026-09-22", evening: "2026-09-22" } }
    }),
    reminderCase("1 ms before the morning time: exact time today", { timeZone: z, nowMs: today.morning - 1, preferences: prefs }),
    reminderCase("exactly at the morning time (not in the future): catch-up now + 300 ms", { timeZone: z, nowMs: today.morning, preferences: prefs }),
    reminderCase("10 minutes past, not shown: catch-up now + 300 ms", { timeZone: z, nowMs: today.morning + 10 * MIN, preferences: prefs }),
    reminderCase("exactly 15 minutes past: still catch-up (inclusive)", { timeZone: z, nowMs: today.morning + 15 * MIN, preferences: prefs }),
    reminderCase("15 minutes + 1 ms past: tomorrow's", { timeZone: z, nowMs: today.morning + 15 * MIN + 1, preferences: prefs }),
    reminderCase("10 minutes past but already shown today: tomorrow's", {
      timeZone: z, nowMs: today.morning + 10 * MIN, preferences: { ...prefs, lastShown: { morning: "2026-09-23", evening: null } }
    }),
    reminderCase("evening within catch-up window", { timeZone: z, nowMs: today.evening + 5 * MIN, preferences: prefs }),
    reminderCase("late night: both tomorrow's", { timeZone: z, nowMs: localMs(z, 2026, 9, 23, 23, 30), preferences: prefs }),
    reminderCase("just after local midnight with yesterday's lastShown: today's", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 24, 0, 0, 30), preferences: { ...prefs, lastShown: { morning: "2026-09-23", evening: "2026-09-23" } }
    }),
    reminderCase("morning complete by counters: nothing scheduled for morning", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: prefs,
      state: baseState("2026-09-23", { progress: { morning: morningAllDone, evening: {} } })
    }),
    reminderCase("evening complete by manual completion: nothing scheduled for evening", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: prefs,
      state: baseState("2026-09-23", { manualCompletion: { morning: false, evening: true } })
    }),
    reminderCase("morning disabled: only evening scheduled", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: { ...prefs, morning: { enabled: false } }
    }),
    reminderCase("notification permission not granted: nothing scheduled", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: prefs, notificationPermission: "default"
    }),
    reminderCase("no location: no times", { timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: reminderPreferences(null) }),
    reminderCase("method umm-al-qura, hanafi Asr", {
      timeZone: z, nowMs: localMs(z, 2026, 9, 23, 4, 0), preferences: { ...prefs, calculationMethod: "umm-al-qura", asrSchool: "hanafi" }
    })
  ];

  const tromso = locations.find(l => l.id === "tromso");
  cases.push(
    reminderCase("polar day (Tromsø, June): no sunrise → no times", {
      timeZone: tromso.timeZone, nowMs: localMs(tromso.timeZone, 2026, 6, 21, 4, 0), preferences: reminderPreferences(tromso)
    }),
    reminderCase("polar night (Tromsø, December): no sunrise → no times", {
      timeZone: tromso.timeZone, nowMs: localMs(tromso.timeZone, 2026, 12, 21, 4, 0), preferences: reminderPreferences(tromso)
    }),
    reminderCase("high latitude summer (Oslo, June): Fajr from night-fraction clamp", {
      timeZone: "Europe/Oslo", nowMs: localMs("Europe/Oslo", 2026, 6, 21, 1, 0), preferences: reminderPreferences(locations.find(l => l.id === "oslo"))
    })
  );

  // DST transitions: "now" in the evening before the change, so tomorrow's reminder crosses it.
  const dst = [
    ["new-york", 2026, 3, 7, "US spring forward (next day 23h)"],
    ["new-york", 2026, 10, 31, "US fall back (next day 25h)"],
    ["london", 2026, 3, 28, "EU spring forward"],
    ["london", 2026, 10, 24, "EU fall back"],
    ["sydney", 2026, 4, 4, "Australia fall back (southern autumn)"],
    ["sydney", 2026, 10, 3, "Australia spring forward (southern spring)"]
  ];
  for (const [id, y, m, d, label] of dst) {
    const location = locations.find(l => l.id === id);
    const zone = location.timeZone;
    cases.push(reminderCase(`DST ${label}: evening before, both reminders are tomorrow's (${zone})`, {
      timeZone: zone, nowMs: localMs(zone, y, m, d, 22, 0), preferences: reminderPreferences(location)
    }));
    const nextDay = new Date(Date.UTC(y, m - 1, d + 1));
    const [ny, nm, nd] = [nextDay.getUTCFullYear(), nextDay.getUTCMonth() + 1, nextDay.getUTCDate()];
    const times = scheduleFor(zone, location, ny, nm, nd);
    cases.push(reminderCase(`DST ${label}: transition day, 5 minutes past the morning time → catch-up (${zone})`, {
      timeZone: zone, nowMs: times.morning + 5 * MIN, preferences: reminderPreferences(location)
    }));
  }
  return cases;
}

// ---------------------------------------------------------------------------------------------------
// Write everything
// ---------------------------------------------------------------------------------------------------

const written = [];
const sessionDefaultInput = { timeZone: SESSION_ZONE, collections: realCollections };
const sessionMeta = (about, source) => ({ about, source: `index.html: ${source}` });

function writeCases(relativePath, meta, defaultInput, cases) {
  written.push({ path: writeJson(relativePath, fixtureFile(meta, defaultInput, cases)), count: cases.length });
}

writeCases("spec/sessions/fixtures/period-is-complete.json",
  sessionMeta("Period completion: counters (review items excluded, counts clamped/floored, targets validated) OR manualCompletion.",
    "periodIsComplete, periodCountersComplete, periodIsManuallyComplete, targetForState, countForState"),
  sessionDefaultInput, periodIsCompleteCases());
writeCases("spec/sessions/fixtures/roll-state-to-date.json",
  sessionMeta("Day rollover of a normalized athkar-progress-v2 state to a new local date.",
    "rollStateToDate, historyEntryFor, emptyState"),
  sessionDefaultInput, rollStateToDateCases());
writeCases("spec/sessions/fixtures/load-state.json",
  sessionMeta("Startup/midnight path: read localStorage, normalize, roll to today's local date if needed. storage maps localStorage keys to raw strings.",
    "loadState, normalizeState, rollStateToDate, localDateKey"),
  { collections: realCollections }, loadStateCases());
writeCases("spec/sessions/fixtures/build-deck.json",
  sessionMeta(`Deck order. With longAdhkarLast, non-review items whose target ≥ longDhikrThreshold (${api.longDhikrThreshold}) move, in order, to just before the last item; decks shorter than 3 are unchanged.`,
    "buildDeck, isLongDhikr, targetForState"),
  sessionDefaultInput, buildDeckCases());
writeCases("spec/sessions/fixtures/first-incomplete-index.json",
  sessionMeta("Index (into the possibly reordered deck) of the first non-review item below target; last index when none; 0 for an empty deck.",
    "firstIncompleteIndex, deck, buildDeck"),
  sessionDefaultInput, firstIncompleteIndexCases());
writeCases("spec/sessions/fixtures/completion-sync.json",
  sessionMeta("completedAt/manualCompletion bookkeeping after a counter change (syncCompletionState) and after the manual toggle (setManualCompletion). `returned` is syncCompletionState's return value (null for setManualCompletion).",
    "syncCompletionState, setManualCompletion"),
  sessionDefaultInput, completionCases());
writeCases("spec/sessions/fixtures/scoped-reset.json",
  sessionMeta("Scoped reset outcomes (confirmation accepted). day: resetDayProgress; week: resetWeek; everything: resetEverything.",
    "resetDayProgress, resetWeek, recentDates, resetEverything, hasResettableState"),
  sessionDefaultInput, scopedResetCases());
writeCases("spec/reminders/fixtures/next-reminder-time.json",
  {
    about: "Adhkar reminder timing. nextReminderTime: today's time if in the future and not shown today; now+300 ms if ≤15 min past and not shown; else tomorrow's. scheduled: scheduleReminders outcome (skipped when disabled, permission not granted, period complete, or no time).",
    source: "index.html: nextReminderTime, scheduleReminders, prayerTimesForDate, periodIsComplete"
  },
  { collections: realCollections }, reminderCases());
written.push(writeVectors("spec/prayer-times/vectors.json"));

for (const { path, count } of written) console.log(`${path}: ${count}`);
