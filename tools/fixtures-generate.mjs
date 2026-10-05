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
import { inflateSync, constants as zlibConstants } from "node:zlib";

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
  const start = lineIndex(line => line.startsWith(`    function ${name}(`) || line.startsWith(`    async function ${name}(`), `function ${name}`);
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
  "currentIndices", "decks", "reminderTimers", "numberFormatter", "suwarStorageKey", "suwarIndices",
  "tasbihStorageKey", "tasbihPresets", "tasbihDefaultTarget", "suwarHistoryDays", "tasbihPresetById",
  "tasbihMaxTarget", "tasbihMaxCount", "tasbihMaxCustom", "tasbihMaxPhraseLength",
  // reset epochs and the transfer (spec/transfer/transfer-v1.md)
  "suwarById", "hapticsStorageKey", "textSizeStorageKey", "lineSpacingStorageKey", "longOrderStorageKey",
  "longOrderPromptStorageKey", "resetEpochDays", "backupDatePattern", "backupInstantPattern", "transferVersion",
  "transferApp", "transferMaxTextLength", "transferMaxInflatedBytes", "transferMaxFrames", "transferFrameChunk",
  "transferBase45", "transferFramePattern", "transferItemIdPattern", "transferSlugPattern", "transferTimeZonePattern",
  "transferForbiddenKeys", "transferStoreKeys", "transferSettingKeys", "transferClockSkewMs", "transferEarliestExport",
  "transferMaxTasbihKeysPerDay", "transferMaxTasbihKeys", "transferMaxResets", "transferPendingKey", "transferInflateSlice"
];

const transferFunctions = [
  "transferSupported", "base45Encode", "base45Decode", "transferChecksum", "transferFrames", "transferTextCode",
  "transferMessageId", "readTransferStream", "deflateTransferBytes", "inflateTransferBytes", "parseTransferFrame",
  "decodeTransferPayload", "decodeTransfer", "decodeTransferFrames", "decodeTransferFile", "validateTransferValue",
  "transferReject", "transferCheck", "transferIsObject", "transferFields", "transferEntries", "transferInstant",
  "transferPhraseIsValid", "transferTasbihKeyIsValid", "transferResets", "validateTransferEnvelope",
  "validateTransferContainer", "transferResetsFor", "buildTransferContainer", "encodeTransfer", "readTransferStorage",
  "transferLocalFromStorage", "readTransferLocal", "earliestInstant", "maxCounts", "laterResets", "transferWinner",
  "transferIncomingProgress", "transferIncomingSuwar", "transferIncomingTasbih", "transferResetsBefore",
  "transferPeriodUnit", "mergeTransferProgress", "transferSuraUnit", "mergeTransferSuwar", "mergeTransferTasbih",
  "mergeTransferSettings", "mergeTransfer", "transferUnitEmpty", "transferUnitCovers", "planTransfer", "applyTransfer",
  "transferKnownItems", "transferInstants", "transferClockIsPlausible", "transferWithinBudget", "recoverTransferPending", "journalHolds",
  "tasbihIdentity", "canonicalTasbihDays", "transferHistoryList", "transferTasbihView", "transferStoredValue", "transferTasbihStore",
  "transferContainerNow",
  "showStoredProgressState", "showStoredSuwarState", "showStoredTasbihState",
  // the envelope (buildBackup) and the stores the transfer reads
  "backupDate", "backupInstant", "finiteCounts", "backupHistory", "buildBackup", "hasAnsweredLongOrderPrompt",
  "ensureCurrentDay", "loadReminderPreferences", "parseStoredState", "normalizeSuwarState", "suraIsComplete",
  "rollSuwarStateToDate", "parseStoredSuwarState", "loadSuwarState", "parseStoredTasbihState", "resetCutoff",
  "normalizeResets", "markReset", "resetEpoch"
];

const functions = [
  // sessions
  "localDateKey", "emptyState", "normalizeState", "targetForState", "countForState",
  "periodCountersComplete", "periodIsManuallyComplete", "periodIsComplete", "historyEntryFor",
  "rollStateToDate", "loadState", "saveState", "targetFor", "countFor", "isLongDhikr", "buildDeck",
  "deck", "invalidateDecks", "firstIncompleteIndex", "syncCompletionState", "setManualCompletion",
  "hasResettableState", "resetDayProgress", "recentDates", "resetWeek", "resetEverything",
  "dayCountLabel", "formatNumber",
  // the scoped resets also clear athkar-suwar-v1 and athkar-tasbih-v1 (kept empty here, so the adhkar state under test
  // is unaffected)
  "emptySuwarState", "saveSuwarState", "suraPagesRead", "suwarHasResettableState", "resetSuwarProgress",
  "deleteSuwarHistory", "emptyTasbihState", "saveTasbihState", "refreshTasbihState", "tasbihHasResettableState",
  "resetTasbihProgress", "deleteTasbihHistory",
  // athkar-tasbih-v1 load: normalisation (phrase-key migration) and rollover
  "trimDailyHistory", "stripTashkeel", "stripTasbihInvisibles", "tasbihMatchKey", "cleanTasbihPhrase", "isRealDateKey",
  "canonicalTasbihKey", "findTasbihPhrase", "normalizeTasbihState", "tasbihDayCounts",
  "rollTasbihStateToDate", "readTasbihState", "loadTasbihState",
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
    // The transfer's UI collaborators (applyTransfer refreshes this tab; buildBackup reads the shown preferences).
    const root = { dataset: { theme: "system", textSize: "medium", lineSpacing: "comfortable" } };
    const tasbihLabelDialog = { open: false };
    const sessionReset = { disabled: false };
    const hapticsToggle = { checked: true };
    const longOrderToggle = { checked: false };
    function refreshTasbihPhraseSheet() {}
    function renderTasbih() {}
    function syncHapticArm() {}
    function updateReminderControls() {}
    function applyTheme(value) { root.dataset.theme = value; }
    function applyTextSize(value) { root.dataset.textSize = value; }
    function applyLineSpacing(value) { root.dataset.lineSpacing = value; }
`;

const harnessSource = `
"use strict";
${contentData}
${constants.map(extractConst).join("\n")}
let state = null;
let reminderPreferences = null;
let longAdhkarLast = false;
let suwarState = emptySuwarState("2000-01-01");
let tasbihState = emptyTasbihState("2000-01-01");
let tasbihStorageWorks = true;
let transferJournal = null;
let hapticsEnabled = true;
let activePeriod = "morning";
${stubs}
${[...functions, ...transferFunctions].map(extractFunction).join("\n\n")}
globalThis.__api = {
  realCollections: { morning: collections.morning, evening: collections.evening },
  setCollections(value) { collections.morning = value.morning; collections.evening = value.evening; },
  getState() { return state; },
  setState(value) { state = value; },
  setReminderPreferences(value) { reminderPreferences = value; },
  setLongAdhkarLast(value) { longAdhkarLast = value; },
  getStores() { return { state, suwarState, tasbihState }; },
  setStores(value) { state = value.state; suwarState = value.suwarState; tasbihState = value.tasbihState; },
  setTasbihStorageWorks(value) { tasbihStorageWorks = value; },
  setTransferJournal(value) { transferJournal = value; },
  getTransferJournal() { return transferJournal; },
  setPreferences(value) { Object.assign(root.dataset, value.dataset); hapticsEnabled = value.haptics; },
  longDhikrThreshold,
  prayerCalculationMethods,
  asrShadowFactors,
  fns: { ${[...functions, ...transferFunctions].join(", ")} }
};
`;

// ---------------------------------------------------------------------------------------------------
// Sandbox
// ---------------------------------------------------------------------------------------------------

// DecompressionStream as the Compression Standard defines it ("decompress and enqueue a chunk": a TransformStream that
// inflates each written chunk at once and enqueues all of its output; readable high-water mark 0, so a write waits
// until the output before it was read), with counters: compressed bytes written, and every inflated byte it ever
// produced. Node's own DecompressionStream buffers ahead of its reader, so it cannot show what the browsers bound.
// The output comes from zlib over the bytes written so far; the platform's stream, fed the same bytes, still decides
// at close whether the whole stream is valid (Adler-32, truncation, trailing data).
const inflateStats = { input: 0, produced: 0 };
class CountingDecompressionStream {
  constructor(format) {
    const fed = [];
    let produced = 0;
    const platform = new DecompressionStream(format);
    const platformWriter = platform.writable.getWriter();
    const platformDone = new Response(platform.readable).arrayBuffer();
    platformDone.catch(() => {});
    const stream = new TransformStream({
      transform(chunk, controller) {
        inflateStats.input += chunk.byteLength;
        fed.push(Buffer.from(chunk));
        platformWriter.write(chunk).catch(() => {});
        let output;
        try {
          output = inflateSync(Buffer.concat(fed), { finishFlush: zlibConstants.Z_SYNC_FLUSH });
        } catch (_) {
          throw new TypeError("invalid deflate data");
        }
        if (output.length > produced) {
          controller.enqueue(new Uint8Array(output.subarray(produced)));
          produced = output.length;
        }
        inflateStats.produced = Math.max(inflateStats.produced, produced);
      },
      async flush() {
        await platformWriter.close();
        await platformDone;
      }
    }, undefined, { highWaterMark: 0 });
    this.readable = stream.readable;
    this.writable = stream.writable;
  }
}

const storage = new Map();
// Fault injection for applyTransfer's storage rules: `read` makes getItem throw; `writesLeft` lets that many setItem
// calls succeed, fails the next one once (as a full quota would), and then lets writes through again (null: never);
// `stuckKeys` keys then keep failing every setItem (a rollback that cannot restore them).
const storageFault = { read: false, writesLeft: null, stuckKeys: [] };
const timers = [];
const firedReminders = [];
// console.warn calls of the code under test (recoverTransferPending logs a conflict).
const warnings = [];
const sandbox = {
  console: { ...console, warn: (...args) => { warnings.push(args.join(" ")); } },
  localStorage: {
    getItem: key => {
      if (storageFault.read) throw new Error("storage read fault");
      return storage.has(key) ? storage.get(key) : null;
    },
    setItem: (key, value) => {
      if (storageFault.writesLeft === null && storageFault.stuckKeys.includes(key)) throw new Error("storage write fault");
      if (storageFault.writesLeft !== null && storageFault.writesLeft-- <= 0) {
        storageFault.writesLeft = null;
        throw new Error("storage write fault");
      }
      storage.set(key, String(value));
    },
    removeItem: key => { storage.delete(key); }
  },
  navigator: { serviceWorker: {} },
  Notification: { permission: "granted" },
  setTimeout: (callback, delay) => { timers.push({ callback, delay }); return timers.length; },
  clearTimeout: () => {},
  __firedReminders: firedReminders,
  // The transfer codec's platform APIs (CompressionStream exists from iOS/Safari 16.4).
  CompressionStream, DecompressionStream: CountingDecompressionStream, Blob, TextEncoder, TextDecoder, MessageChannel,
  // Fixed "random" bytes, so ids (the write-ahead record's) are the same on every run.
  crypto: { getRandomValues: array => array.fill(7) }
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
  storageFault.read = false;
  storageFault.writesLeft = null;
  api.setTasbihStorageWorks(true);
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
    rollCase("history is kept by date for the 31-day window, not trimmed to 7 entries", baseState("2026-09-23", { history: eightDays }), "2026-09-24"),
    rollCase("history days before the 31-day window are dropped", baseState("2026-09-23", { history: [historyEntry("2026-09-01", true, true), historyEntry("2026-08-24", true, true), historyEntry("2026-08-20", true, false)] }), "2026-09-24"),
    rollCase("multi-day gap adds only the stored day; skipped days get no entries", baseState("2026-09-20", {
      progress: { morning: morningAllDone, evening: eveningAllDone }
    }), "2026-09-23"),
    rollCase("review items do not block completion when rolling", baseState("2026-09-23", {
      progress: { morning: fullProgress(syntheticCollections.morning), evening: {} }
    }), "2026-09-24", syntheticCollections)
  ];
}

function loadCase(name, timeZone, nowMs, storageEntries, collections) {
  const now = new Date(nowMs).toISOString();
  const input = { ...sessionDefaults, timeZone, now, storage: storageEntries, ...(collections ? { collections } : {}) };
  prepare(input);
  const loaded = fn.loadState();
  return {
    name,
    input: {
      ...(collections ? { collections } : {}),
      timeZone, now, nowLocal: localIso(timeZone, nowMs), storage: storageEntries
    },
    expected: { state: plain(loaded) }
  };
}

function replaceOnce(text, search, replacement) {
  const parts = text.split(search);
  if (parts.length !== 2) throw new Error(`expected exactly one ${search} in ${text}`);
  return parts.join(replacement);
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
  const riyadh0800 = localMs(z, 2026, 9, 23, 8, 0);
  const [m1, m2] = realCollections.morning.map(item => item.id);
  // Item ids that are array keys: "0" and "1" index an array container, "length" reads its length.
  const arrayKeyCollections = {
    morning: [{ id: "0", count: 5 }, { id: "1", targetOptions: [1, 10], defaultTarget: 10 }, { id: "length", count: 2 }],
    evening: [{ id: "evening-01" }]
  };
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
    loadCase("normalization: invalid date falls back to today (no roll); bad fields and history garbage sanitized (history entries need a real date inside the 31-day window)", z, localMs(z, 2026, 9, 23, 8, 0), {
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
    loadCase("normalization keeps stored history inside the 31-day window (not 7 entries); rolling adds today's predecessor", z, localMs(z, 2026, 9, 24, 8, 0), {
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
    }),
    // The local date uses the zone offset at the instant itself: 1 ms before local midnight on the evening before a
    // DST change, the offset in force a few hours later (or today) would name the next day.
    loadCase("DST spring-forward eve, 1 ms before local midnight (America/Los_Angeles): no rollover", "America/Los_Angeles",
      Date.parse("2026-03-08T07:59:59.999Z"), {
        "athkar-progress-v2": JSON.stringify(baseState("2026-03-07", { manualCompletion: { morning: true, evening: false } }))
      }),
    loadCase("DST fall-back day, 1 ms before local midnight (America/Los_Angeles): no rollover", "America/Los_Angeles",
      Date.parse("2026-11-02T07:59:59.999Z"), {
        "athkar-progress-v2": JSON.stringify(baseState("2026-11-01", { manualCompletion: { morning: true, evening: false } }))
      }),
    loadCase("a stored state followed by trailing text is malformed JSON: empty state for today", z, riyadh0800, {
      "athkar-progress-v2": `${JSON.stringify(baseState("2026-09-23", { manualCompletion: { morning: true, evening: true } }))}x`
    }),
    // JSON.parse edge cases: the native port must parse exactly as the PWA does.
    loadCase("number literal beyond double range parses as Infinity: that count reads as 0, history kept", z, riyadh0800, {
      "athkar-progress-v2": replaceOnce(JSON.stringify(baseState("2026-09-22", {
        progress: { morning: { ...morningAllDone, [m1]: 0 }, evening: {} },
        history: [historyEntry("2026-09-21", true, false, "2026-09-21T03:00:00.000Z", null)]
      })), `"${m1}":0,`, `"${m1}":1e400,`)
    }),
    loadCase("lone surrogate escapes in strings are accepted; escaped pairs combine", z, riyadh0800, {
      "athkar-progress-v2": `{"date":"2026-09-23","progress":{"morning":{"${m1}":"\\ud800"},"evening":{}},` +
        `"targets":{"morning":{},"evening":{}},"completedAt":{"morning":"\\ud83d\\ude00","evening":"\\udc00x"},` +
        `"manualCompletion":{"morning":false,"evening":false},` +
        `"history":[{"date":"2026-09-22","morning":true,"evening":false,"morningAt":"\\ud800\\u0041","eveningAt":null}]}`
    }),
    loadCase("duplicate keys: the last occurrence wins", z, riyadh0800, {
      "athkar-progress-v2": `{"date":"2026-09-22","progress":{"morning":{"${m2}":1,"${m2}":3},"evening":{}},` +
        `"targets":{"morning":{},"evening":{}},"completedAt":{"morning":null,"evening":null},` +
        `"manualCompletion":{"morning":true,"evening":false},"history":[],` +
        `"date":"2026-09-23","manualCompletion":{"morning":false,"evening":true}}`
    }),
    loadCase("array-shaped progress.morning and targets.morning are kept as arrays", z, riyadh0800, {
      "athkar-progress-v2": JSON.stringify(baseState("2026-09-23", {
        progress: { morning: [5, "3"], evening: { [realCollections.evening[0].id]: 1 } },
        targets: { morning: [100], evening: {} }
      }))
    }),
    loadCase("array containers are read by key like JS: \"0\" is an index, \"length\" the length, other ids undefined", z,
      localMs(z, 2026, 9, 24, 8, 0), {
        "athkar-progress-v2": JSON.stringify(baseState("2026-09-23", {
          progress: { morning: [5, "3"], evening: [1] },
          targets: { morning: [null, 1], evening: [] }
        }))
      }, arrayKeyCollections)
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
// Tasbih fixtures (athkar-tasbih-v1)
// ---------------------------------------------------------------------------------------------------

// A stored athkar-tasbih-v1 object; `date` defaults to the fixtures' "today".
function tasbihStored(overrides = {}) {
  return { date: "2026-10-04", selected: "subhan", target: 33, counts: {}, firstUse: [], custom: [], history: {}, ...overrides };
}

// loadTasbihState on `storage`, then again on what it returned (as saved back): a lossy or unstable migration
// shows as a difference between `state` and `reloaded`.
function tasbihLoadCase(name, raw) {
  const timeZone = SESSION_ZONE;
  const nowMs = localMs(timeZone, 2026, 10, 4, 9, 0);
  const now = new Date(nowMs).toISOString();
  const storageEntries = { "athkar-tasbih-v1": typeof raw === "string" ? raw : JSON.stringify(raw) };
  prepare({ ...sessionDefaults, timeZone, now, storage: storageEntries });
  const loaded = plain(fn.loadTasbihState());
  prepare({ ...sessionDefaults, timeZone, now, storage: { "athkar-tasbih-v1": JSON.stringify(loaded) } });
  const reloaded = plain(fn.loadTasbihState());
  return {
    name,
    input: { now, nowLocal: localIso(timeZone, nowMs), storage: storageEntries },
    expected: { state: loaded, reloaded }
  };
}

function tasbihLoadCases() {
  return [
    tasbihLoadCase("empty storage: defaults (subhan, target 33)", null),
    tasbihLoadCase("heh goal «يا اللہ» saved and selected, today 17, yesterday 11: migrates to «يا الله», counts kept",
      tasbihStored({ selected: "c:يا اللہ", custom: ["يا اللہ"], counts: { "c:يا اللہ": 17 }, firstUse: ["c:يا اللہ"], history: { "2026-10-03": { "c:يا اللہ": 11 } } })),
    tasbihLoadCase("heh goal stored the day before: today's counts roll into history under the migrated key",
      tasbihStored({ date: "2026-10-03", selected: "c:يا اللہ", custom: ["يا اللہ"], counts: { "c:يا اللہ": 17 }, firstUse: ["c:يا اللہ"], history: { "2026-10-01": { "c:يا اللہ": 11 } } })),
    tasbihLoadCase("tatweel «سبحـان الله» merges into the subhan preset: counts summed, earliest first use kept",
      tasbihStored({ selected: "c:سبحـان الله", custom: ["سبحـان الله"], counts: { "c:سبحـان الله": 5, hamd: 2, subhan: 3 }, firstUse: ["c:سبحـان الله", "hamd", "subhan"], history: { "2026-10-03": { hamd: 4, "c:سبحـان الله": 2, subhan: 1 } } })),
    tasbihLoadCase("RLM and ZWSP spellings of «ذكر» merge into one saved phrase, counts summed",
      tasbihStored({ selected: "c:ذكر\u200F", custom: ["ذكر\u200F", "ذك\u200Bر"], counts: { "c:ذك\u200Bر": 6, "c:ذكر\u200F": 4 }, firstUse: ["c:ذك\u200Bر", "c:ذكر\u200F"], history: { "2026-10-03": { "c:ذكر\u200F": 1, "c:ذك\u200Bر": 2 } } })),
    tasbihLoadCase("ZWNJ reads as a space: «سبحان‌الله» merges into the preset, «يا‌حي يا قيوم» is saved with a space",
      tasbihStored({ selected: "c:يا\u200Cحي يا قيوم", custom: ["سبحان\u200Cالله", "يا\u200Cحي يا قيوم"], counts: { "c:سبحان\u200Cالله": 7, "c:يا\u200Cحي يا قيوم": 2 }, firstUse: ["c:سبحان\u200Cالله", "c:يا\u200Cحي يا قيوم"] })),
    tasbihLoadCase("deleted custom phrase (not in custom) keeps today's count and history under its migrated key",
      tasbihStored({ counts: { "c:حسبـي الله": 9 }, firstUse: ["c:حسبـي الله"], history: { "2026-10-03": { "c:حسبـي الله": 2 } } })),
    tasbihLoadCase("converging keys are summed and capped at 99,999",
      tasbihStored({ custom: ["ذكر", "ذكـر"], counts: { "c:ذكر": 60000, "c:ذكـر": 50000 }, history: { "2026-10-03": { "c:ذكر": 99999, "c:ذكـر": 1 } } })),
    tasbihLoadCase("invisible-only legacy key keeps its counts and history (not offered in the picker)",
      tasbihStored({ custom: ["\u200B"], counts: { "c:\u200B": 3 }, history: { "2026-10-03": { "c:\u200B": 1 } } })),
    tasbihLoadCase("__proto__ keys and wrong types are dropped without touching prototypes",
      '{"date":"2026-10-04","__proto__":{"target":5,"polluted":true},"selected":"__proto__","target":"33","custom":["__proto__",5,"  سبحان   الله  "],' +
      '"firstUse":"nope","counts":{"__proto__":7,"subhan":"5","hamd":3.5,"takbir":-1,"tahlil":4,"constructor":3},' +
      '"history":{"__proto__":{"subhan":1},"2026-02-30":{"subhan":1},"2026-10-03":{"__proto__":2,"istighfar":6}}}'),
    tasbihLoadCase("future stored date (clock moved back): counts kept as today's, history days at or after today summed into them (first use in day order), earlier history kept",
      tasbihStored({ date: "2026-10-05", counts: { subhan: 7 }, firstUse: ["subhan"], history: { "2026-10-04": { hamd: 5, subhan: 2 }, "2026-10-03": { takbir: 3 } } }))
  ];
}

// ---------------------------------------------------------------------------------------------------
// Transfer fixtures (spec/transfer/transfer-v1.md)
// ---------------------------------------------------------------------------------------------------

const TRANSFER_TODAY = "2026-10-04";
const transferNowMs = localMs(SESSION_ZONE, 2026, 10, 4, 9, 0);
const TRANSFER_NOW = new Date(transferNowMs).toISOString();
const transferDefaults = { timeZone: SESSION_ZONE, now: TRANSFER_NOW, nowLocal: localIso(SESSION_ZONE, transferNowMs) };
const morningIds = realCollections.morning.filter(item => !item.review).map(item => item.id);
const eveningIds = realCollections.evening.filter(item => !item.review).map(item => item.id);

function prepareTransfer() {
  prepare({ ...sessionDefaults, now: TRANSFER_NOW });
}

function adler32(bytes) {
  let low = 1;
  let high = 0;
  for (const byte of bytes) {
    low = (low + byte) % 65521;
    high = (high + low) % 65521;
  }
  return ((high << 16) | low) >>> 0;
}

function zlibTrailer(out, sum) {
  out.push(sum >>> 24, (sum >>> 16) & 255, (sum >>> 8) & 255, sum & 255);
  return Uint8Array.from(out);
}

// A zlib stream of stored (uncompressed) deflate blocks: valid input to any inflater and byte-identical everywhere,
// unlike a compressor's output. `adler` overrides the checksum; `trailing` appends bytes after the stream.
function storedZlib(bytes, { adler = adler32(bytes), trailing = [] } = {}) {
  const out = [0x78, 0x01];
  for (let start = 0; start === 0 || start < bytes.length; start += 65535) {
    const block = bytes.subarray(start, start + 65535);
    out.push(start + 65535 >= bytes.length ? 1 : 0, block.length & 255, block.length >>> 8, ~block.length & 255, (~block.length >>> 8) & 255);
    for (const byte of block) out.push(byte);
  }
  const result = zlibTrailer(out, adler);
  return Uint8Array.from([...result, ...trailing]);
}

// A deflate bomb: one fixed-Huffman block, a literal 0 and then (length 258, distance 1) copies until `size` zeros.
function bombZlib(size) {
  const out = [0x78, 0x01];
  let acc = 0;
  let used = 0;
  const bit = value => {
    acc |= value << used;
    used += 1;
    if (used === 8) {
      out.push(acc);
      acc = 0;
      used = 0;
    }
  };
  const huffman = (code, length) => { for (let i = length - 1; i >= 0; i -= 1) bit((code >> i) & 1); };
  bit(1); bit(1); bit(0); // BFINAL, BTYPE = 01 (fixed Huffman), LSB first
  huffman(0x30, 8); // literal 0
  let produced = 1;
  while (produced + 258 <= size) {
    huffman(0xC5, 8); // length code 285 (258)
    huffman(0, 5); // distance code 0 (1)
    produced += 258;
  }
  huffman(0, 7); // end of block
  if (used) out.push(acc);
  return zlibTrailer(out, adler32(new Uint8Array(produced)));
}

// A text-form code around `bytes` (already a zlib stream), as the PWA writes it.
function codeOf(zlib, { msg = "TEST", app = "A", index = 1, count = 1, textForm = true } = {}) {
  const payload = fn.base45Encode(zlib);
  const body = `AQ1:${app}:${msg}:${index}:${count}:${payload}`;
  const frame = `${body}:${fn.transferChecksum(body)}`;
  return textForm ? frame.replaceAll(" ", "=") : frame;
}

function jsonZlib(value) {
  return storedZlib(new TextEncoder().encode(typeof value === "string" ? value : JSON.stringify(value)));
}

function storageMap() {
  return Object.fromEntries([...storage.entries()].sort(([a], [b]) => a.localeCompare(b)));
}

function loadStorage(map) {
  storage.clear();
  for (const [key, value] of Object.entries(map)) if (value !== null) storage.set(key, value);
}

// A device: raw localStorage values for the stores (each dated today unless overridden) and any setting keys.
function device({ progress = {}, suwar = {}, tasbih = {}, settings = {} } = {}) {
  return {
    "athkar-progress-v2": JSON.stringify({
      date: TRANSFER_TODAY, progress: { morning: {}, evening: {} }, targets: { morning: {}, evening: {} },
      completedAt: { morning: null, evening: null }, manualCompletion: { morning: false, evening: false }, history: [], resets: {},
      ...progress
    }),
    "athkar-suwar-v1": JSON.stringify({
      date: suwar.date ?? TRANSFER_TODAY,
      selected: suwar.selected ?? "kahf",
      read: { ...Object.fromEntries(suwarPack.suwar.map(sura => [sura.id, {}])), ...suwar.read },
      completedAt: { ...Object.fromEntries(suwarPack.suwar.map(sura => [sura.id, null])), ...suwar.completedAt },
      history: suwar.history ?? {},
      resets: suwar.resets ?? {}
    }),
    "athkar-tasbih-v1": JSON.stringify({ ...tasbihStored(), resets: {}, ...tasbih }),
    ...settings
  };
}

function localOf(map) {
  loadStorage(map);
  return fn.transferLocalFromStorage(fn.readTransferStorage());
}

// What encodeTransfer would put in the code for a device (before compression), checked by the PWA's own validator.
function containerOf(map) {
  const local = localOf(map);
  api.setStores({ state: local.progress, suwarState: local.suwar, tasbihState: fn.parseStoredTasbihState(map["athkar-tasbih-v1"] ?? null) });
  api.setReminderPreferences(fn.loadReminderPreferences());
  api.setLongAdhkarLast(map["athkar-long-order-v1"] === "last");
  api.setPreferences({
    dataset: { theme: map["athkar-theme"] ?? "system", textSize: map["athkar-reading-text-size"] ?? "medium", lineSpacing: map["athkar-line-spacing"] ?? "comfortable" },
    haptics: map["athkar-haptics"] !== "off"
  });
  // The container encodeTransfer builds (transferContainerNow: the stores as stored, the tasbih keys with their epochs).
  const container = fn.transferContainerNow();
  const checked = plain(fn.validateTransferValue(container, "code"));
  if (!checked.ok) throw new Error(`the encoder's container is rejected: ${JSON.stringify(checked)}`);
  return plain(container);
}

function planOf(map, decoded) {
  return plain(fn.planTransfer(localOf(map), intoContext(decoded), TRANSFER_NOW));
}

function withWrites(map, plan) {
  const next = { ...map };
  for (const [key, value] of Object.entries(plan.writes)) {
    if (value === null) delete next[key];
    else next[key] = value;
  }
  return Object.fromEntries(Object.entries(next).sort(([a], [b]) => a.localeCompare(b)));
}

// `local` after receiving `incoming`'s code.
function received(local, incoming) {
  return withWrites(local, planOf(local, { ok: true, source: "code", container: containerOf(incoming) }));
}

function sortDeep(value) {
  if (Array.isArray(value)) return value.map(sortDeep);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map(key => [key, sortDeep(value[key])]));
  return value;
}

// The part of a device's stores both sides of a transfer must agree on: everything except what stays the receiver's
// (targets, the selected sura and phrase, the tasbih target, the order and spelling of saved phrases, first-use order).
function convergent(map) {
  const local = plain(localOf(map));
  const tasbih = plain(fn.parseStoredTasbihState(map["athkar-tasbih-v1"] ?? null));
  const key = value => (value.startsWith("c:") ? `c:${fn.tasbihMatchKey(value.slice(2))}` : value);
  const rekey = counts => Object.fromEntries(Object.entries(counts).map(([name, count]) => [key(name), count]));
  const resetKey = name => (name.length > 10 ? `${name.slice(0, 11)}${key(name.slice(11))}` : name);
  const { targets, ...progress } = local.progress;
  const { selected, ...suwar } = local.suwar;
  return JSON.stringify(sortDeep({
    progress,
    suwar,
    tasbih: {
      counts: rekey(tasbih.counts),
      history: Object.fromEntries(Object.entries(tasbih.history).map(([day, counts]) => [day, rekey(counts)])),
      resets: Object.fromEntries(Object.entries(tasbih.resets).map(([name, at]) => [resetKey(name), at])),
      custom: tasbih.custom.map(phrase => fn.tasbihMatchKey(phrase)).sort()
    }
  }));
}

const at = (day, time) => `${day}T${time}:00.000Z`;
const YESTERDAY = "2026-10-03";
const TWO_DAYS_AGO = "2026-10-02";
const resetWindowDays = 31;
// `count` local dates counting back from `from` days before TRANSFER_TODAY.
const daysBack = (count, from = 1) => Array.from({ length: count }, (_, i) => new Date(Date.UTC(2026, 9, 4 - from - i)).toISOString().slice(0, 10));
const suwarPack = JSON.parse(readFileSync(join(root, "content/suwar.v1.json"), "utf8"));
const pagesOf = id => suwarPack.suwar.find(sura => sura.id === id).pages.map(page => page.id);
const readPages = (id, pages) => Object.fromEntries(pages.map(page => [page, true]));
const allMorning = Object.fromEntries(realCollections.morning.filter(item => !item.review).map(item => [item.id, targetOf(item)]));
const allButLastMorning = Object.fromEntries(Object.entries(allMorning).slice(0, -1));
const lastMorningOnly = Object.fromEntries(Object.entries(allMorning).slice(-1));

// `local` builds its container on a clock moved to another day (a code from yesterday, or from a device ahead).
function containerOn(map, y, m, d) {
  setNow(localMs(SESSION_ZONE, y, m, d, 9, 0));
  const container = containerOf(map);
  setNow(transferNowMs);
  return container;
}

// ---- codec ----

async function decodeCase(name, input, run) {
  prepareTransfer();
  const before = storageMap();
  const result = plain(await run());
  if (JSON.stringify(storageMap()) !== JSON.stringify(before)) throw new Error(`${name}: decoding touched storage`);
  return { name, input, result };
}

async function transferCodecFixture() {
  prepareTransfer();
  const hex = bytes => Buffer.from(bytes).toString("hex");
  const base45 = ["AB", "Hello!!", "base-45", "ietf!"].map(text => ({ text, bytes: hex(Buffer.from(text)), encoded: fn.base45Encode(Uint8Array.from(Buffer.from(text))) }));
  const base45Invalid = ["GGW", "ABCD", ":::", "aBC", "BB"].map(text => {
    const bytes = fn.base45Decode(text);
    return { text, bytes: bytes ? hex(bytes) : null };
  });
  const checksum = ["", "AQ1:A:TEST:1:1:BB8", "AQ1:A:TEST:1:1:%69 VD92EX0"].map(text => ({ text, checksum: fn.transferChecksum(text) }));
  const payload = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".repeat(45).slice(0, 2000);
  const frames = plain(fn.transferFrames(payload, "TEST"));

  const typical = device({
    progress: {
      progress: { morning: { [morningIds[0]]: 1, [morningIds[1]]: 1 }, evening: {} },
      history: [historyEntry(YESTERDAY, true, true, at(YESTERDAY, "03:00"), at(YESTERDAY, "15:00"))],
      resets: { [`${TRANSFER_TODAY}|morning`]: at(TRANSFER_TODAY, "04:00") }
    },
    suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(0, 2)) }, history: { [YESTERDAY]: { kahf: at(YESTERDAY, "18:00") } } },
    tasbih: { custom: ["يا حي يا قيوم"], counts: { subhan: 33, "c:يا حي يا قيوم": 7 }, firstUse: ["subhan", "c:يا حي يا قيوم"], history: { [YESTERDAY]: { hamd: 100 } } }
  });
  const container = containerOf(typical);
  const valid = jsonZlib(container);
  const code = codeOf(valid);
  const ok = decoded => (decoded.ok && JSON.stringify(decoded.container) === JSON.stringify(container)
    ? { ok: true, source: decoded.source, container: "equals input container" } : decoded);
  const decodeText = text => async () => {
    const decoded = plain(await fn.decodeTransfer(text));
    return decoded.ok ? ok(decoded) : decoded;
  };
  const decodeFrames = texts => async () => {
    const decoded = plain(await fn.decodeTransferFrames(intoContext(texts)));
    return decoded.ok ? ok(decoded) : decoded;
  };
  const decodeFile = text => async () => {
    const decoded = plain(await fn.decodeTransferFile(text));
    return decoded.ok && decoded.source === "code" ? ok(decoded) : decoded;
  };
  const mutated = change => {
    const copy = structuredClone(container);
    change(copy);
    return codeOf(jsonZlib(copy));
  };
  const textCode = text => codeOf(jsonZlib(text));
  const reframe = body => `${body}:${fn.transferChecksum(body)}`.replaceAll(" ", "=");
  const flipped = `${code.slice(0, 15)}${code[15] === "0" ? "1" : "0"}${code.slice(16)}`;
  const payloadOf = zlib => fn.base45Encode(zlib);
  const qrFrames = plain(fn.transferFrames(payloadOf(valid), "QRQR", 300));
  const otherFrames = plain(fn.transferFrames(payloadOf(valid), "ZZZZ", 300));
  const tooManyFrames = reframe(`AQ1:A:TEST:1:65:${payloadOf(valid)}`);
  const wrapped = `  \n${code.match(/.{1,60}/g).join("\r\n")}\n `;
  const json = JSON.stringify(container);
  const progressPath = `"progress":{"morning":{"${morningIds[0]}":1`;
  if (!json.includes(progressPath)) throw new Error("progress path not found for the 1e400 case");
  const eightHistory = Array.from({ length: 8 }, (_, i) => historyEntry(`2026-09-${String(30 - i).padStart(2, "0")}`, true, false, null, null));
  const nineCustom = Array.from({ length: 9 }, (_, i) => `عبارة ${i + 1}`);
  const athkarExample = readFileSync(join(root, "spec/backup/examples/athkar-pwa.athkarbackup"), "utf8");
  const ruqyahExample = readFileSync(join(root, "spec/backup/examples/ruqyah-pwa.athkarbackup"), "utf8");
  // Deep enough to overflow a recursive validator, small enough for a stored-block code under the 64 KiB text cap.
  const deep = 10000;

  const decode = [
    await decodeCase("text form decodes to the container it was built from", { code }, decodeText(code)),
    await decodeCase("the same frame with spaces (as a QR carries it) is accepted", { code: code.replaceAll("=", " ") }, decodeText(code.replaceAll("=", " "))),
    await decodeCase("line breaks and surrounding whitespace added by a carrier are ignored", { code: wrapped }, decodeText(wrapped)),
    await decodeCase("QR frames in any order, with a repeat, assemble", { frames: [qrFrames[2], qrFrames[0], qrFrames[2], qrFrames[1], ...qrFrames.slice(3)] },
      decodeFrames([qrFrames[2], qrFrames[0], qrFrames[2], qrFrames[1], ...qrFrames.slice(3)])),
    await decodeCase("a missing QR frame: incomplete", { frames: qrFrames.slice(1) }, decodeFrames(qrFrames.slice(1))),
    await decodeCase("frames of two codes: mixed", { frames: [qrFrames[0], ...otherFrames.slice(1)] }, decodeFrames([qrFrames[0], ...otherFrames.slice(1)])),
    await decodeCase("one QR frame pasted as text: one-frame", { code: qrFrames[0] }, decodeText(qrFrames[0])),
    await decodeCase("empty text: not-code", { code: "" }, decodeText("")),
    await decodeCase("other text: not-code", { code: "hello" }, decodeText("hello")),
    await decodeCase("lowercase prefix: not-code", { code: code.replace("AQ1", "aq1") }, decodeText(code.replace("AQ1", "aq1"))),
    await decodeCase("over 64 KiB of text: too-long", { code: `AQ1:${"A".repeat(65533)}` }, decodeText(`AQ1:${"A".repeat(65533)}`)),
    await decodeCase("AQ2: newer", { code: code.replace("AQ1", "AQ2") }, decodeText(code.replace("AQ1", "AQ2"))),
    await decodeCase("a ruqyah code (R) with a valid checksum: wrong-app", { code: codeOf(valid, { app: "R" }) }, decodeText(codeOf(valid, { app: "R" }))),
    await decodeCase("one changed character: corrupt (checksum)", { code: flipped }, decodeText(flipped)),
    await decodeCase("text cut short: not-code", { code: code.slice(0, -5) }, decodeText(code.slice(0, -5))),
    await decodeCase("payload cut short, checksum recomputed: corrupt (inflate)", { code: reframe(`AQ1:A:TEST:1:1:${payloadOf(valid).slice(0, -30)}`) },
      decodeText(reframe(`AQ1:A:TEST:1:1:${payloadOf(valid).slice(0, -30)}`))),
    await decodeCase("base45 group above 65535: corrupt (base45)", { code: reframe(`AQ1:A:TEST:1:1:GGW${payloadOf(valid)}`) },
      decodeText(reframe(`AQ1:A:TEST:1:1:GGW${payloadOf(valid)}`))),
    await decodeCase("one dangling base45 character: corrupt (base45)", { code: reframe(`AQ1:A:TEST:1:1:${payloadOf(valid)}A`) },
      decodeText(reframe(`AQ1:A:TEST:1:1:${payloadOf(valid)}A`))),
    await decodeCase("zlib Adler-32 mismatch: corrupt (inflate)", { code: codeOf(storedZlib(new TextEncoder().encode(json), { adler: 1 })) },
      decodeText(codeOf(storedZlib(new TextEncoder().encode(json), { adler: 1 })))),
    await decodeCase("bytes after the zlib stream: corrupt (inflate)", { code: codeOf(storedZlib(new TextEncoder().encode(json), { trailing: [0, 0] })) },
      decodeText(codeOf(storedZlib(new TextEncoder().encode(json), { trailing: [0, 0] })))),
    await decodeCase("not UTF-8: corrupt (json)", { code: codeOf(storedZlib(Uint8Array.from([0x7B, 0xFF, 0xFE, 0x7D]))) },
      decodeText(codeOf(storedZlib(Uint8Array.from([0x7B, 0xFF, 0xFE, 0x7D]))))),
    await decodeCase("not JSON: corrupt (json)", { code: textCode("not json") }, decodeText(textCode("not json"))),
    await decodeCase("a deflate bomb (300 000 zero bytes from 2 KB): corrupt (inflate-cap)", { code: codeOf(bombZlib(300000)) }, decodeText(codeOf(bombZlib(300000)))),
    await decodeCase("65 frames: too-long", { code: tooManyFrames }, decodeText(tooManyFrames)),
    await decodeCase("frame index above the count: not-code", { code: reframe(`AQ1:A:TEST:3:2:${payloadOf(valid)}`) }, decodeText(reframe(`AQ1:A:TEST:3:2:${payloadOf(valid)}`))),
    await decodeCase("unknown top-level key", { code: mutated(c => { c.extra = 1; }) }, decodeText(mutated(c => { c.extra = 1; }))),
    await decodeCase("__proto__ key", { code: textCode(`{"__proto__":{"polluted":true},${json.slice(1)}`) }, decodeText(textCode(`{"__proto__":{"polluted":true},${json.slice(1)}`))),
    await decodeCase("unknown nested key", { code: mutated(c => { c.envelope.meta.extra = 1; }) }, decodeText(mutated(c => { c.envelope.meta.extra = 1; }))),
    await decodeCase("transfer 2: newer", { code: mutated(c => { c.transfer = 2; }) }, decodeText(mutated(c => { c.transfer = 2; }))),
    await decodeCase("envelope format 2: newer", { code: mutated(c => { c.envelope.meta.format = 2; }) }, decodeText(mutated(c => { c.envelope.meta.format = 2; }))),
    await decodeCase("app ruqyah-pwa: wrong-app", { code: mutated(c => { c.app = "ruqyah-pwa"; }) }, decodeText(mutated(c => { c.app = "ruqyah-pwa"; }))),
    await decodeCase("history date 2026-02-30", { code: mutated(c => { c.envelope.adhkar.history[0].date = "2026-02-30"; }) }, decodeText(mutated(c => { c.envelope.adhkar.history[0].date = "2026-02-30"; }))),
    await decodeCase("instant at 24:00", { code: mutated(c => { c.envelope.adhkar.history[0].morningAt = "2026-10-03T24:00:00Z"; }) }, decodeText(mutated(c => { c.envelope.adhkar.history[0].morningAt = "2026-10-03T24:00:00Z"; }))),
    await decodeCase("history not newest first", { code: mutated(c => { c.envelope.adhkar.history.push(historyEntry("2026-10-03", false, true, null, null)); }) },
      decodeText(mutated(c => { c.envelope.adhkar.history.push(historyEntry("2026-10-03", false, true, null, null)); }))),
    await decodeCase("eight history days", { code: mutated(c => { c.envelope.adhkar.history = eightHistory; }) }, decodeText(mutated(c => { c.envelope.adhkar.history = eightHistory; }))),
    await decodeCase("negative count", { code: mutated(c => { c.envelope.adhkar.today.progress.morning[morningIds[0]] = -1; }) }, decodeText(mutated(c => { c.envelope.adhkar.today.progress.morning[morningIds[0]] = -1; }))),
    await decodeCase("count 1e400 (Infinity)", { code: textCode(json.replace(progressPath, `"progress":{"morning":{"${morningIds[0]}":1e400`)) },
      decodeText(textCode(json.replace(progressPath, `"progress":{"morning":{"${morningIds[0]}":1e400`)))),
    await decodeCase("count above 2^53 - 1", { code: textCode(json.replace(progressPath, `"progress":{"morning":{"${morningIds[0]}":9007199254740993`)) },
      decodeText(textCode(json.replace(progressPath, `"progress":{"morning":{"${morningIds[0]}":9007199254740993`)))),
    await decodeCase("count as a string", { code: mutated(c => { c.envelope.adhkar.today.progress.morning[morningIds[0]] = "1"; }) }, decodeText(mutated(c => { c.envelope.adhkar.today.progress.morning[morningIds[0]] = "1"; }))),
    await decodeCase("item id constructor", { code: mutated(c => { c.envelope.adhkar.today.progress.morning.constructor = 1; }) }, decodeText(mutated(c => { c.envelope.adhkar.today.progress.morning.constructor = 1; }))),
    await decodeCase("location in a code", { code: mutated(c => { c.envelope.reminders.location = { latitude: 21.42, longitude: 39.83, updatedAt: null }; }) },
      decodeText(mutated(c => { c.envelope.reminders.location = { latitude: 21.42, longitude: 39.83, updatedAt: null }; }))),
    await decodeCase("timeZone with a path", { code: mutated(c => { c.envelope.meta.timeZone = "../etc"; }) }, decodeText(mutated(c => { c.envelope.meta.timeZone = "../etc"; }))),
    await decodeCase("suwar dated another day", { code: mutated(c => { c.athkar.suwar.date = YESTERDAY; }) }, decodeText(mutated(c => { c.athkar.suwar.date = YESTERDAY; }))),
    await decodeCase("suwar read mark false", { code: mutated(c => { c.athkar.suwar.read.kahf = { [pagesOf("kahf")[0]]: false }; }) }, decodeText(mutated(c => { c.athkar.suwar.read.kahf = { [pagesOf("kahf")[0]]: false }; }))),
    await decodeCase("tasbih count 100000", { code: mutated(c => { c.athkar.tasbih.counts.subhan = 100000; }) }, decodeText(mutated(c => { c.athkar.tasbih.counts.subhan = 100000; }))),
    await decodeCase("tasbih counts key __proto__", { code: textCode(json.replace('"counts":{"subhan"', '"counts":{"__proto__":5,"subhan"')) },
      decodeText(textCode(json.replace('"counts":{"subhan"', '"counts":{"__proto__":5,"subhan"')))),
    await decodeCase("nine saved phrases", { code: mutated(c => { c.athkar.tasbih.custom = nineCustom; }) }, decodeText(mutated(c => { c.athkar.tasbih.custom = nineCustom; }))),
    await decodeCase("saved phrase with a control character", { code: mutated(c => { c.athkar.tasbih.custom = ["ذكر\u0001"]; }) }, decodeText(mutated(c => { c.athkar.tasbih.custom = ["ذكر\u0001"]; }))),
    await decodeCase("firstUse not an array", { code: mutated(c => { c.athkar.tasbih.firstUse = "subhan"; }) }, decodeText(mutated(c => { c.athkar.tasbih.firstUse = "subhan"; }))),
    await decodeCase("reset epoch older than the 31-day window", { code: mutated(c => { c.athkar.adhkar.resets["2026-09-03"] = at(TRANSFER_TODAY, "01:00"); }) },
      decodeText(mutated(c => { c.athkar.adhkar.resets["2026-09-03"] = at(TRANSFER_TODAY, "01:00"); }))),
    await decodeCase("reset epoch for a later day", { code: mutated(c => { c.athkar.adhkar.resets["2026-10-05"] = at(TRANSFER_TODAY, "01:00"); }) },
      decodeText(mutated(c => { c.athkar.adhkar.resets["2026-10-05"] = at(TRANSFER_TODAY, "01:00"); }))),
    await decodeCase("reset unit that is not a period", { code: mutated(c => { c.athkar.adhkar.resets[`${TRANSFER_TODAY}|noon`] = at(TRANSFER_TODAY, "01:00"); }) },
      decodeText(mutated(c => { c.athkar.adhkar.resets[`${TRANSFER_TODAY}|noon`] = at(TRANSFER_TODAY, "01:00"); }))),
    await decodeCase(`an array nested ${deep} deep in place of the envelope`, { code: textCode(`{"transfer":1,"app":"athkar-pwa","envelope":${"[".repeat(deep)}${"]".repeat(deep)},"athkar":null}`) },
      decodeText(textCode(`{"transfer":1,"app":"athkar-pwa","envelope":${"[".repeat(deep)}${"]".repeat(deep)},"athkar":null}`))),
    await decodeCase("file: a transfer code with a BOM and a final newline", { file: `\uFEFF${code}\n` }, decodeFile(`\uFEFF${code}\n`)),
    await decodeCase("file: an athkar .athkarbackup (spec/backup/examples)", { file: athkarExample }, decodeFile(athkarExample)),
    await decodeCase("file: a ruqyah .athkarbackup: wrong-app", { file: ruqyahExample }, decodeFile(ruqyahExample)),
    await decodeCase("file: other JSON: corrupt", { file: '{"meta":{}}' }, decodeFile('{"meta":{}}')),
    await decodeCase("file: other text: not-code", { file: "notes" }, decodeFile("notes"))
  ];
  // Every rejection names an error; a typo in a case (an unexpected success) fails generation.
  for (const entry of decode) {
    const expectOk = /decodes|accepted|ignored|assemble|BOM|athkar \.athkarbackup/.test(entry.name);
    if (entry.result.ok !== expectOk) throw new Error(`decode case "${entry.name}" gave ${JSON.stringify(entry.result)}`);
  }
  return { container, typical, base45, base45Invalid, checksum, frames: { payloadLength: payload.length, msg: "TEST", frames }, decode };
}

// The largest athkar state the stores hold (plan §3 "worst"). `unitEpochs`: besides a day epoch on every day of the
// window (as after «حذف كل شيء»), an epoch on every unit of every day, which no sequence of taps can exceed.
function worstDevice(unitEpochs) {
  const days = daysBack(7);
  const window = daysBack(resetWindowDays, 0);
  const custom = Array.from({ length: 8 }, (_, i) => `سبحان الله وبحمده سبحان الله العظيم عدد خلقه ورضا نفسه ${i + 1}`.slice(0, 60).trim());
  const keys = [...["subhan", "hamd", "takbir", "tahlil", "istighfar", "subhan-bihamdih", "hawqala", "salawat"], ...custom.map(phrase => `c:${phrase}`)];
  const full = Object.fromEntries(keys.map(key => [key, 99999]));
  const everySura = Object.fromEntries(suwarPack.suwar.map(sura => [sura.id, at(TRANSFER_TODAY, "05:00")]));
  const epochs = units => Object.fromEntries(window.flatMap(day => [[day, at(TRANSFER_TODAY, "01:00")],
    ...(unitEpochs ? units.map(unit => [`${day}|${unit}`, at(TRANSFER_TODAY, "02:00")]) : [])]));
  return device({
    progress: {
      progress: { morning: allMorning, evening: Object.fromEntries(realCollections.evening.filter(item => !item.review).map(item => [item.id, targetOf(item)])) },
      completedAt: { morning: at(TRANSFER_TODAY, "03:00"), evening: at(TRANSFER_TODAY, "15:00") },
      history: days.map(day => historyEntry(day, true, true, at(day, "03:00"), at(day, "15:00"))),
      resets: epochs(["morning", "evening"])
    },
    suwar: {
      read: Object.fromEntries(suwarPack.suwar.map(sura => [sura.id, readPages(sura.id, pagesOf(sura.id))])),
      completedAt: everySura,
      history: Object.fromEntries(days.map(day => [day, everySura])),
      resets: epochs(suwarPack.suwar.map(sura => sura.id))
    },
    tasbih: { custom, counts: full, firstUse: keys, history: Object.fromEntries(days.map(day => [day, full])), resets: epochs(keys) }
  });
}

// encodeTransfer itself (CompressionStream), then both decoders on its output. Sizes depend on the host's zlib, so
// they are printed, not recorded.
async function roundTripCase(name, map) {
  prepareTransfer();
  const container = containerOf(map);
  const encoded = plain(await fn.encodeTransfer("RTRP"));
  if (!encoded.ok || JSON.stringify(encoded.container) !== JSON.stringify(container)) throw new Error(`${name}: encodeTransfer built another container`);
  const fromText = plain(await fn.decodeTransfer(encoded.code));
  const fromFrames = plain(await fn.decodeTransferFrames(intoContext([...encoded.frames].reverse())));
  for (const decoded of [fromText, fromFrames]) {
    if (!decoded.ok || JSON.stringify(decoded.container) !== JSON.stringify(container)) throw new Error(`${name}: round trip failed: ${JSON.stringify(decoded).slice(0, 300)}`);
  }
  const jsonBytes = Buffer.byteLength(JSON.stringify(container));
  const deflated = fn.base45Decode(fn.parseTransferFrame(encoded.code).chunk).length;
  console.log(`transfer size, ${name}: JSON ${jsonBytes} B, deflate ${deflated} B, text code ${encoded.code.length} chars, ` +
    `${encoded.frames.length} QR frame(s) of at most ${Math.max(...encoded.frames.map(frame => frame.length))} chars`);
  return { name, input: { storage: map }, expected: { container, jsonBytes, roundTrip: { text: true, frames: true } } };
}

// ---- merge and plan ----

const hist = historyEntry;

function mergeScenarios() {
  const tasbih = (counts, extra = {}) => ({ counts, firstUse: Object.keys(counts), ...extra });
  const A = {
    join: device({
      progress: { progress: { morning: { [morningIds[0]]: 1, [morningIds[1]]: 1 }, evening: {} }, history: [hist(YESTERDAY, true, false, at(YESTERDAY, "03:00"), null)] },
      suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(0, 4)) } },
      tasbih: tasbih({ subhan: 10, hamd: 3 }, { history: { [YESTERDAY]: { subhan: 33 } } })
    }),
    joinOther: device({
      progress: {
        progress: { morning: { [morningIds[0]]: 2, [morningIds[2]]: 1 }, evening: { [eveningIds[0]]: 1 } },
        history: [hist(YESTERDAY, true, true, at(YESTERDAY, "02:00"), at(YESTERDAY, "15:00")), hist(TWO_DAYS_AGO, true, false, at(TWO_DAYS_AGO, "03:00"), null)]
      },
      suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(2, 5)) }, history: { [YESTERDAY]: { kahf: at(YESTERDAY, "18:00") } } },
      tasbih: tasbih({ subhan: 7, hamd: 9 }, { history: { [YESTERDAY]: { subhan: 20, hamd: 100 } } })
    }),
    completes: device({ progress: { progress: { morning: allButLastMorning, evening: {} } } }),
    stale: device({ progress: { progress: { morning: allMorning, evening: {} }, completedAt: { morning: at(TRANSFER_TODAY, "03:00"), evening: null } }, tasbih: tasbih({ subhan: 70 }) }),
    resetRecount: device({ progress: { resets: { [TRANSFER_TODAY]: at(TRANSFER_TODAY, "04:00") }, progress: { morning: { [morningIds[0]]: 1 }, evening: {} } }, tasbih: tasbih({ subhan: 5 }, { resets: { [TRANSFER_TODAY]: at(TRANSFER_TODAY, "04:00") } }) }),
    tombstone: device({
      progress: { resets: { [YESTERDAY]: at(TRANSFER_TODAY, "04:00"), [TWO_DAYS_AGO]: at(TRANSFER_TODAY, "04:00") } },
      suwar: { resets: { [YESTERDAY]: at(TRANSFER_TODAY, "04:00") } },
      tasbih: tasbih({}, { resets: { [YESTERDAY]: at(TRANSFER_TODAY, "04:00") } })
    }),
    history: device({
      progress: { history: [hist(YESTERDAY, true, true, at(YESTERDAY, "03:00"), at(YESTERDAY, "15:00")), hist(TWO_DAYS_AGO, true, false, at(TWO_DAYS_AGO, "03:00"), null)] },
      suwar: { history: { [YESTERDAY]: { kahf: at(YESTERDAY, "18:00") } } },
      tasbih: tasbih({}, { history: { [YESTERDAY]: { hamd: 100 } } })
    }),
    cardReset: device({ progress: { resets: { [`${TRANSFER_TODAY}|morning`]: at(TRANSFER_TODAY, "04:00") }, progress: { morning: { [morningIds[0]]: 1 }, evening: {} } } }),
    cardFull: device({ progress: { progress: { morning: { [morningIds[0]]: 1, [morningIds[1]]: 1, [morningIds[2]]: 1 }, evening: { [eveningIds[0]]: 1 } } } }),
    suwarA: device({ suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(0, 4)), kahf: readPages("kahf", pagesOf("kahf").slice(0, 1)) }, resets: { [`${TRANSFER_TODAY}|kahf`]: at(TRANSFER_TODAY, "04:00") } } }),
    suwarB: device({ suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(3)), kahf: readPages("kahf", pagesOf("kahf").slice(0, 3)) } } }),
    phraseReset: device({ tasbih: tasbih({ hamd: 2, subhan: 10 }, { resets: { [`${TRANSFER_TODAY}|hamd`]: at(TRANSFER_TODAY, "04:00") } }) }),
    phraseOther: device({ tasbih: tasbih({ hamd: 50, subhan: 40 }) }),
    capLocal: device({ tasbih: tasbih({ "c:عبارة ١": 1 }, { custom: ["عبارة ١", "عبارة ٢", "عبارة ٣", "عبارة ٤", "عبارة ٥", "عبارة ٦"] }) }),
    capIncoming: device({ tasbih: tasbih({ "c:ذكر أ": 4, "c:ذكر ب": 5, "c:ذكر ج": 6, "c:ذكر د": 7 }, { custom: ["ذكر أ", "ذكر ب", "ذكر ج", "ذكر د"], history: { [YESTERDAY]: { "c:ذكر د": 9 } } }) }),
    settingsLocal: device({ settings: { "athkar-theme": "light", "athkar-reading-text-size": "medium" } }),
    settingsIncoming: device({
      settings: { "athkar-theme": "dark", "athkar-reading-text-size": "large", "athkar-line-spacing": "wide", "athkar-haptics": "off",
        "athkar-long-order-v1": "last", "athkar-long-order-prompt-v1": "answered",
        "athkar-reminders-v2": JSON.stringify({ morning: { enabled: true }, evening: { enabled: false }, calculationMethod: "umm-al-qura", asrSchool: "hanafi", location: { latitude: 21.42, longitude: 39.83, updatedAt: null }, lastShown: { morning: TRANSFER_TODAY, evening: null } }) }
    }),
    receiverOwned: device({
      progress: { targets: { morning: { [tawhidMorningId]: 1 }, evening: {} } },
      suwar: { selected: "yasin" },
      tasbih: tasbih({}, { selected: "hamd", target: 100, custom: ["يا رب"] })
    }),
    receiverOwnedIncoming: device({
      progress: { targets: { morning: { [tawhidMorningId]: 10 }, evening: { [tawhidEveningId]: 100 } } },
      suwar: { selected: "mulk" },
      tasbih: tasbih({}, { selected: "takbir", target: null, custom: ["يَا رَبّ", "حسبي الله"] })
    }),
    yesterdayCode: device({ progress: { date: YESTERDAY, progress: { morning: allMorning, evening: {} }, completedAt: { morning: at(YESTERDAY, "03:00"), evening: null } }, suwar: { date: YESTERDAY }, tasbih: { date: YESTERDAY } }),
    aheadCode: device({
      progress: { date: "2026-10-05", progress: { morning: allMorning, evening: {} }, completedAt: { morning: at("2026-10-05", "03:00"), evening: null },
        history: [hist(TRANSFER_TODAY, true, true, at(TRANSFER_TODAY, "03:00"), at(TRANSFER_TODAY, "15:00")), hist(YESTERDAY, false, true, null, at(YESTERDAY, "15:00"))] },
      suwar: { date: "2026-10-05" }, tasbih: { date: "2026-10-05", counts: { subhan: 9 }, firstUse: ["subhan"], history: { [TRANSFER_TODAY]: { hamd: 3 }, [YESTERDAY]: { takbir: 4 } } }
    }),
    fullWeek: device({ progress: { history: daysBack(7).map(day => hist(day, true, false, at(day, "03:00"), null)) } }),
    olderDays: device({ progress: { history: [hist("2026-09-20", true, true, null, null), hist("2026-09-19", true, false, null, null)] } }),
    oldEpochs: device({ progress: { resets: { "2026-08-01": at("2026-08-01", "04:00"), [YESTERDAY]: at(YESTERDAY, "04:00") } } }),
    // Equivalent spellings of one phrase, unsaved (orphan counts) on two devices, saved on a third (the reviewer's triple).
    orphanA: device({ tasbih: tasbih({ "c:يا رب": 1 }) }),
    orphanB: device({ tasbih: tasbih({ "c:يَا رَبّ": 2 }) }),
    savedC: device({ tasbih: tasbih({}, { custom: ["يا رب"] }) }),
    orphanReset: device({ tasbih: tasbih({}, { resets: { [`${TRANSFER_TODAY}|c:يَا رَبّ`]: at(TRANSFER_TODAY, "04:00") } }) }),
    // Two equivalent keys on one side with different epochs: the alias reset later takes the unit whole (2, not 10).
    aliasEpochs: device({ tasbih: tasbih({ "c:يا رب": 10, "c:يَا رَبّ": 2 }, { resets: { [`${TRANSFER_TODAY}|c:يَا رَبّ`]: at(TRANSFER_TODAY, "04:00") },
      history: { [YESTERDAY]: { "c:يا رب": 40, "c:يَا رَبّ": 3 } } }) }),
    // The same in a store whose saved spelling would make the app's own load sum the two keys (a legacy upgrade).
    aliasLegacy: device({ tasbih: tasbih({ "c:يا رب": 10, "c:يَا رَبّ": 2 }, { custom: ["يا رب"], resets: { [`${TRANSFER_TODAY}|c:يَا رَبّ`]: at(TRANSFER_TODAY, "04:00") } }) }),
    // An alias with only a reset, newer than the count of the other spelling on the same side: the unit is reset.
    aliasResetOnly: device({ tasbih: tasbih({ "c:يا رب": 10 }, { resets: { [`${TRANSFER_TODAY}|c:يَا رَبّ`]: at(TRANSFER_TODAY, "04:00"), [`${YESTERDAY}|c:يَا رَبّ`]: at(YESTERDAY, "04:00") },
      history: { [YESTERDAY]: { "c:يا رب": 5 } } }) }),
    // History over the 31-day window: a full week, two older days, and day tombstones on that week (truncation + tombstones).
    weekTombstone: device({ progress: { resets: Object.fromEntries(daysBack(7).map(day => [day, at(TRANSFER_TODAY, "04:00")])) } }),
    // Reset epochs only (a reset that leaves nothing behind), one store each.
    epochAdhkar: device({ progress: { resets: { [TRANSFER_TODAY]: at(TRANSFER_TODAY, "04:00") } } }),
    epochSuwar: device({ suwar: { resets: { [`${TRANSFER_TODAY}|mulk`]: at(TRANSFER_TODAY, "04:00") } } }),
    epochTasbih: device({ tasbih: tasbih({}, { resets: { [`${TRANSFER_TODAY}|subhan`]: at(TRANSFER_TODAY, "04:00") } }) }),
    // Before those resets: today's progress in each store.
    beforeEpochs: device({ progress: { progress: { morning: { [morningIds[0]]: 1 }, evening: {} } }, suwar: { read: { mulk: readPages("mulk", pagesOf("mulk").slice(0, 2)) } }, tasbih: tasbih({ subhan: 7 }) }),
    // A code made on 2026-09-10, whose history reaches before this receiver's window.
    oldHistory: device({ suwar: { date: "2026-09-10" }, tasbih: { date: "2026-09-10" }, progress: { date: "2026-09-10", history: [hist("2026-09-09", true, false, at("2026-09-09", "03:00"), null), hist("2026-09-01", true, true, at("2026-09-01", "03:00"), at("2026-09-01", "15:00"))] } })
  };
  return A;
}

function mergeCase(name, local, incoming, { source = "code", decoded } = {}) {
  prepareTransfer();
  const input = decoded ?? { ok: true, source, container: containerOf(incoming) };
  const plan = planOf(local, input);
  if (plan.error) {
    // A refused code: no plan, and storage is untouched.
    return { name, input: { storage: local, incoming: { source: input.source, container: input.container } }, expected: { plan, storage: local } };
  }
  const { before, ...shown } = plan;
  if (JSON.stringify(before) !== JSON.stringify(plain(fn.readTransferStorage()))) throw new Error(`${name}: plan.before is not the stored values`);
  return { name, input: { storage: local, incoming: { source: input.source, container: input.container } }, expected: { plan: shown, storage: withWrites(local, plan) } };
}

// A container from `map` changed by `edit`, which must still pass the validator (only planTransfer refuses it).
function editedContainer(map, edit) {
  const container = containerOf(map);
  edit(container);
  const checked = plain(fn.validateTransferValue(intoContext(container), "code"));
  if (!checked.ok) throw new Error(`edited container rejected by the validator: ${JSON.stringify(checked)}`);
  return { ok: true, source: "code", container };
}

// `count` distinct saved-phrase-shaped keys (not saved on either side: orphan counts, which the normalizers keep).
const orphanCounts = (prefix, count) => Object.fromEntries(Array.from({ length: count }, (_, index) => [`c:${prefix} ${(index + 1).toLocaleString("ar-EG", { useGrouping: false })}`, 1]));

function transferRefusalCases(s) {
  const later = hours => new Date(transferNowMs + hours * 3600000).toISOString();
  const farFuture = "9999-12-31T23:59:59.999Z";
  return [
    mergeCase("a reset epoch years ahead of this clock: refused before planning (clock), storage untouched", s.join, null, {
      decoded: editedContainer(device(), container => {
        container.athkar.adhkar.resets = { [TRANSFER_TODAY]: farFuture };
        container.athkar.suwar.resets = { [TRANSFER_TODAY]: farFuture };
        container.athkar.tasbih.resets = { [TRANSFER_TODAY]: farFuture, [YESTERDAY]: farFuture };
      })
    }),
    mergeCase("a completion instant more than a day ahead of this clock: refused (clock)", s.join, null, {
      decoded: editedContainer(s.completes, container => { container.envelope.adhkar.today.completedAt.morning = later(25); })
    }),
    mergeCase("exportedAt before 2020: refused (clock)", s.join, null, {
      decoded: editedContainer(s.join, container => { container.envelope.meta.exportedAt = "2019-12-31T23:59:59.000Z"; })
    }),
    mergeCase("a reset epoch less than a day ahead of this clock (skew between devices): accepted", s.stale, null, {
      decoded: editedContainer(s.resetRecount, container => { container.athkar.tasbih.resets = { [TRANSFER_TODAY]: later(23) }; })
    }),
    mergeCase("adhkar item IDs this version does not have are dropped before merging (progress and targets)", s.join,
      device({ progress: { progress: { morning: { [morningIds[0]]: 3, "zz-unknown-item": 5 }, evening: { "zz-other": 1 } }, targets: { morning: { "zz-unknown-item": 9 }, evening: {} } } })),
    mergeCase("the merged tasbih day would hold more than 256 phrase keys: refused whole (too-big), existing counts untouched", device({ tasbih: { counts: orphanCounts("ذكر", 200), firstUse: [] } }), device({ tasbih: { counts: orphanCounts("تسبيح", 200), firstUse: [] } })),
    mergeCase("the merged tasbih store would hold more than 512 phrase keys in all: refused (too-big)",
      device({ tasbih: { counts: orphanCounts("ذكر", 200), firstUse: [], history: { [YESTERDAY]: orphanCounts("حمد", 200) } } }),
      device({ tasbih: { counts: orphanCounts("تسبيح", 50), firstUse: [], history: { [TWO_DAYS_AGO]: orphanCounts("شكر", 200) } } }))
  ];
}

async function transferMergeCases() {
  const s = mergeScenarios();
  prepareTransfer();
  const backup = plain(await fn.decodeTransferFile(readFileSync(join(root, "spec/backup/examples/athkar-pwa.athkarbackup"), "utf8")));
  return [
    mergeCase("join: today's counts take the per-item max, history days union (OR, earliest instant), suwar pages OR, tasbih max", s.join, s.joinOther),
    mergeCase("the union completes a period: completedAt is the merge instant", s.completes, device({ progress: { progress: { morning: lastMorningOnly, evening: {} } } })),
    mergeCase("the sender reset later: the receiver's stale counts are replaced (resets row with before/after)", s.stale, s.resetRecount),
    mergeCase("the receiver reset later: the sender's stale counts are ignored (keptLocal row)", s.resetRecount, s.stale),
    mergeCase("history days deleted on the sender (tombstones) are deleted here", s.history, s.tombstone),
    mergeCase("history days deleted here stay deleted", s.tombstone, s.history),
    mergeCase("a card reset makes the whole period the later side's (limitation: the other side's other cards go)", s.cardFull, s.cardReset),
    mergeCase("suwar: pages OR; a sura reset wins for that sura only", s.suwarB, s.suwarA),
    mergeCase("tasbih: a phrase reset wins for that phrase only; other phrases take the max", s.phraseOther, s.phraseReset),
    mergeCase("tasbih: phrases beyond the cap of 8 are dropped with their counts (warning), never folded into another key", s.capLocal, s.capIncoming),
    mergeCase("settings: imported only where absent here and not the default; reminder switches, lastShown and location never", s.settingsLocal, s.settingsIncoming),
    mergeCase("receiver-owned: targets (absent keys filled), selected sura and phrase, tasbih target; phrases matched by spelling", s.receiverOwned, s.receiverOwnedIncoming),
    mergeCase("a code from yesterday: its today arrives as yesterday's history (stale warning)", s.cardFull, null, { decoded: { ok: true, source: "code", container: containerOn(s.yesterdayCode, 2026, 10, 3) } }),
    mergeCase("a code from a device whose date is ahead: its today and today's history are ignored (future warning)", s.join, null, { decoded: { ok: true, source: "code", container: containerOn(s.aheadCode, 2026, 10, 5) } }),
    mergeCase("history is kept by date for the 31-day window, not by count: a full week and two older days are all kept", s.fullWeek, s.olderDays),
    mergeCase("days before this receiver's 31-day window are not added (trimmed warning)", s.join, null, { decoded: { ok: true, source: "code", container: containerOn(s.oldHistory, 2026, 9, 10) } }),
    mergeCase("reset epochs only (adhkar): nothing visible changes, but the plan is not empty (hidden.resets) and writes the epoch", device(), s.epochAdhkar),
    mergeCase("reset epochs only (suwar): hidden.resets, written", device(), s.epochSuwar),
    mergeCase("reset epochs only (tasbih): hidden.resets, written", device(), s.epochTasbih),
    mergeCase("after the epochs arrived, the code from before the reset changes nothing (keptLocal; empty)", received(received(received(device(), s.epochAdhkar), s.epochSuwar), s.epochTasbih), s.beforeEpochs),
    mergeCase("equivalent unsaved spellings are one unit: max, never the sum", s.orphanA, s.orphanB),
    mergeCase("a saved spelling arriving later names the unit; its count is not added to the orphan's", received(s.orphanA, s.orphanB), s.savedC),
    mergeCase("a reset of one spelling resets the equivalent unit", s.orphanA, s.orphanReset),
    mergeCase("one device's equivalent keys: only those with the latest epoch count, summed (today 2, not 10 or 12; history, no epochs: 40 + 3 = 43)", device(), s.aliasEpochs),
    mergeCase("the same with the spelling saved: 2, as the app's own load shows it", device(), s.aliasLegacy),
    mergeCase("an alias holding only a newer reset counts 0 at its epoch: the unit is reset, today and in history", device(), s.aliasResetOnly),
    mergeCase("nothing new: an empty plan", s.join, s.join),
    mergeCase("reset epochs before the 31-day window are dropped", s.oldEpochs, s.join),
    mergeCase("a backup file: adhkar and settings only (backup warning)", s.join, null, { decoded: backup }),
    ...transferRefusalCases(s)
  ];
}

// Idempotence, commutativity (up to receiver-owned fields), two-way convergence and associativity over devices with
// reset epochs. Generation fails if any property does not hold.
function transferPropertyCases() {
  const s = mergeScenarios();
  const devices = {
    join: s.join, joinOther: s.joinOther, history: s.history, stale: s.stale, resetRecount: s.resetRecount, tombstone: s.tombstone,
    cardReset: s.cardReset, cardFull: s.cardFull, suwarA: s.suwarA, suwarB: s.suwarB, phraseReset: s.phraseReset, phraseOther: s.phraseOther,
    orphanA: s.orphanA, orphanB: s.orphanB, savedC: s.savedC, orphanReset: s.orphanReset,
    aliasEpochs: s.aliasEpochs, aliasLegacy: s.aliasLegacy, aliasResetOnly: s.aliasResetOnly,
    fullWeek: s.fullWeek, olderDays: s.olderDays, weekTombstone: s.weekTombstone,
    epochTasbih: s.epochTasbih, beforeEpochs: s.beforeEpochs
  };
  const names = Object.keys(devices);
  const pairs = [];
  for (const a of names) {
    for (const b of names) {
      if (a === b) continue;
      prepareTransfer();
      const once = received(devices[a], devices[b]);
      const twice = received(once, devices[b]);
      const other = received(devices[b], devices[a]);
      const back = received(devices[b], once);
      const again = received(once, back);
      const result = {
        idempotent: JSON.stringify(once) === JSON.stringify(twice),
        commutative: convergent(once) === convergent(other),
        converges: convergent(again) === convergent(back),
        // Receiving the same code again finds nothing to commit (no hidden epoch or target changes either).
        settled: planOf(once, { ok: true, source: "code", container: containerOf(devices[b]) }).empty === true
      };
      if (!result.idempotent || !result.commutative || !result.converges || !result.settled) throw new Error(`property failed for ${a} ← ${b}: ${JSON.stringify(result)}`);
      pairs.push({ local: a, incoming: b, ...result });
    }
  }
  const triples = [["join", "resetRecount", "tombstone"], ["stale", "resetRecount", "history"], ["cardFull", "cardReset", "join"],
    ["suwarA", "suwarB", "join"], ["phraseReset", "phraseOther", "stale"], ["tombstone", "history", "resetRecount"],
    // The final review's counterexamples: equivalent spellings with a saved one, and history truncation with tombstones.
    ["orphanA", "orphanB", "savedC"], ["orphanB", "savedC", "orphanReset"], ["fullWeek", "olderDays", "weekTombstone"],
    ["weekTombstone", "fullWeek", "olderDays"], ["beforeEpochs", "epochTasbih", "join"],
    ["aliasEpochs", "orphanA", "savedC"], ["orphanA", "aliasResetOnly", "orphanB"], ["aliasLegacy", "orphanB", "aliasEpochs"]].map(([a, b, c]) => {
    prepareTransfer();
    const left = received(received(devices[a], devices[b]), devices[c]);
    const right = received(devices[a], received(devices[b], devices[c]));
    const associative = convergent(left) === convergent(right);
    // Repeated transfers: receiving any of the three again changes nothing that converges.
    const repeated = [a, b, c].every(name => convergent(received(left, devices[name])) === convergent(left));
    if (!associative || !repeated) throw new Error(`associativity failed for ${a}, ${b}, ${c}: ${JSON.stringify({ associative, repeated })}`);
    return { devices: [a, b, c], associative, repeated };
  });
  return { devices, pairs, triples };
}

// ---- apply ----

function applyCase(name, local, incoming, { fault, stuck, change, memoryMode, nextDay } = {}) {
  prepareTransfer();
  api.setTransferJournal(null);
  const plan = planOf(local, { ok: true, source: "code", container: containerOf(incoming) });
  loadStorage(local);
  const stored = fn.transferLocalFromStorage(fn.readTransferStorage());
  api.setStores({ state: stored.progress, suwarState: stored.suwar, tasbihState: fn.parseStoredTasbihState(local["athkar-tasbih-v1"] ?? null) });
  api.setReminderPreferences(fn.loadReminderPreferences());
  if (change) storage.set(...change);
  if (memoryMode) api.setTasbihStorageWorks(false);
  if (fault === "read") storageFault.read = true;
  if (typeof fault === "number") storageFault.writesLeft = fault;
  if (stuck) storageFault.stuckKeys = stuck;
  if (nextDay) setNow(localMs(SESSION_ZONE, 2026, 10, 5, 0, 30));
  const result = plain(fn.applyTransfer(intoContext(plan)));
  storageFault.read = false;
  storageFault.writesLeft = null;
  storageFault.stuckKeys = [];
  const after = storageMap();
  const unchanged = change ? { ...local, [change[0]]: change[1] } : local;
  let nextStart;
  let sessionAfter;
  if (stuck) {
    // The rollback could not restore a key: the record is marked, and the next start puts every key back.
    const record = JSON.parse(after["athkar-transfer-pending-v1"] ?? "null");
    if (!record?.rollback) throw new Error(`${name}: the pending record is not marked for rollback`);
    // The rest of this session: the record's keys are held, so a save and a second transfer write nothing.
    const held = storageMap();
    if (!api.getTransferJournal()) throw new Error(`${name}: the session does not hold the record`);
    fn.saveState();
    fn.saveSuwarState();
    fn.saveTasbihState();
    const secondTransfer = plain(fn.applyTransfer(intoContext(plan)));
    if (secondTransfer.ok || JSON.stringify(storageMap()) !== JSON.stringify(held)) throw new Error(`${name}: the session wrote held keys`);
    sessionAfter = { saves: "nothing written", secondTransfer };
    // The next start, storage working again.
    api.setTransferJournal(null);
    api.setTasbihStorageWorks(true);
    const recovered = plain(fn.recoverTransferPending());
    nextStart = { recovered, storage: storageMap() };
    if (JSON.stringify(sortDeep(nextStart.storage)) !== JSON.stringify(sortDeep(unchanged))) throw new Error(`${name}: the next start did not restore storage`);
  } else {
    const expectedAfter = result.ok ? withWrites(local, plan) : unchanged;
    if (JSON.stringify(sortDeep(after)) !== JSON.stringify(sortDeep(expectedAfter))) throw new Error(`${name}: storage is not ${result.ok ? "the plan's writes" : "unchanged"}`);
  }
  let reapplied;
  if (result.ok) reapplied = plain(fn.applyTransfer(intoContext(plan)));
  return {
    name,
    input: {
      storage: local, ...(change ? { changedBeforeApply: { [change[0]]: change[1] } } : {}), ...(fault !== undefined ? { fault } : {}),
      ...(stuck ? { stuckKeys: stuck } : {}), ...(memoryMode ? { tasbihMemoryMode: true } : {}),
      ...(nextDay ? { now: new Date(localMs(SESSION_ZONE, 2026, 10, 5, 0, 30)).toISOString() } : {}), writes: plan.writes
    },
    expected: { result, storage: after, ...(reapplied ? { sameAgain: reapplied } : {}), ...(sessionAfter ? { sessionAfter } : {}), ...(nextStart ? { nextStart } : {}) }
  };
}

function transferApplyCases() {
  const s = mergeScenarios();
  const writes = planOf(s.join, { ok: true, source: "code", container: containerOf(s.history) }).writes;
  if (Object.keys(writes).length < 3) throw new Error("the apply cases need a plan with at least three writes");
  const [firstKey] = Object.keys(writes);
  return [
    applyCase("all writes land; the same plan again is refused (changed): it was planned on other values", s.join, s.history),
    applyCase("the write-ahead record cannot be written: nothing is written (write)", s.join, s.history, { fault: 0 }),
    applyCase("the second write fails: the first is rolled back and the record removed, storage is byte-identical (write)", s.join, s.history, { fault: 2 }),
    applyCase("the second write fails and the rollback of the first fails too: the record is marked rollback, the rest of the session holds its keys (a save and a second transfer write nothing), and the next start restores every key (write)", s.join, s.history, { fault: 2, stuck: [firstKey] }),
    applyCase("storage cannot be read: nothing is written (write)", s.join, s.history, { fault: "read" }),
    applyCase("tasbih memory mode: nothing is written (write)", s.join, s.history, { memoryMode: true }),
    applyCase("another tab wrote after the plan: nothing is written (changed)", s.join, s.history, { change: ["athkar-tasbih-v1", JSON.stringify({ ...tasbihStored(), counts: { subhan: 11 } })] }),
    applyCase("midnight passed after the plan: nothing is written (changed)", s.join, s.history, { nextDay: true })
  ];
}

// A start that finds athkar-transfer-pending-v1: the tab closed (or crashed) after `landed` of the plan's writes.
function recoverCase(name, local, incoming, { landed, rollback = false, change, record } = {}) {
  prepareTransfer();
  const plan = planOf(local, { ok: true, source: "code", container: containerOf(incoming) });
  loadStorage(local);
  const pending = record ?? JSON.stringify({ id: "TEST", before: plan.before, after: plan.writes, ...(rollback ? { rollback: true } : {}) });
  storage.set("athkar-transfer-pending-v1", pending);
  for (const [key, value] of Object.entries(plan.writes).slice(0, landed ?? 0)) {
    if (value === null) storage.delete(key);
    else storage.set(key, value);
  }
  if (change) storage.set(...change);
  const start = storageMap();
  warnings.length = 0;
  const recovered = plain(fn.recoverTransferPending());
  const after = storageMap();
  const expected = recovered === "forward" ? withWrites(local, plan) : recovered === "back" ? local : { ...start };
  if (recovered === "conflict" || recovered === "invalid") delete expected["athkar-transfer-pending-v1"];
  if (JSON.stringify(sortDeep(after)) !== JSON.stringify(sortDeep(expected))) throw new Error(`${name}: storage after recovery is not as expected (${recovered})`);
  return { name, input: { storage: start }, expected: { recovered, logged: warnings.length > 0, storage: after } };
}

// A start on the next day while one of an interrupted transfer's writes still fails: recovery fails and keeps the
// record; the day's ordinary load, rollover and saves then write none of its keys, so the record stays valid; the next
// start with working storage completes it.
function recoverAfterFailedStartCase(name, local, incoming) {
  prepareTransfer();
  api.setTransferJournal(null);
  const plan = planOf(local, { ok: true, source: "code", container: containerOf(incoming) });
  const keys = Object.keys(plan.writes);
  if (keys.length < 2) throw new Error(`${name}: needs a plan writing two stores`);
  loadStorage(local);
  storage.set("athkar-transfer-pending-v1", JSON.stringify({ id: "TEST", before: plan.before, after: plan.writes }));
  storage.set(keys[0], plan.writes[keys[0]]);
  const start = storageMap();
  const nextDay = localMs(SESSION_ZONE, 2026, 10, 5, 9, 0);
  setNow(nextDay);
  storageFault.stuckKeys = [keys[1]];
  const first = plain(fn.recoverTransferPending());
  const held = api.getTransferJournal() !== null;
  api.setStores({ state: fn.loadState(), suwarState: fn.loadSuwarState(), tasbihState: fn.loadTasbihState() });
  fn.ensureCurrentDay();
  fn.saveState();
  fn.saveSuwarState();
  fn.saveTasbihState();
  const afterDay = storageMap();
  storageFault.stuckKeys = [];
  if (first !== "failed" || !held || JSON.stringify(afterDay) !== JSON.stringify(start)) {
    throw new Error(`${name}: the failed start changed the journal's keys or dropped the record (${first})`);
  }
  api.setTransferJournal(null);
  api.setTasbihStorageWorks(true);
  const second = plain(fn.recoverTransferPending());
  const after = storageMap();
  if (second !== "forward" || JSON.stringify(sortDeep(after)) !== JSON.stringify(sortDeep(withWrites(local, plan)))) {
    throw new Error(`${name}: the next start did not complete the transfer (${second})`);
  }
  setNow(transferNowMs);
  return {
    name,
    input: { storage: start, now: new Date(nextDay).toISOString(), stuckKeys: [keys[1]] },
    expected: { recovered: first, storageAfterTheDay: afterDay, nextStart: { recovered: second, storage: after } }
  };
}

function transferRecoverCases() {
  const s = mergeScenarios();
  const count = Object.keys(planOf(s.join, { ok: true, source: "code", container: containerOf(s.history) }).writes).length;
  return [
    recoverCase("closed before the first write: the next start writes the plan (forward; the user confirmed it)", s.join, s.history, { landed: 0 }),
    recoverCase("closed after the first write: the next start writes the rest (forward)", s.join, s.history, { landed: 1 }),
    recoverCase("closed after every write, before the record was removed: only the record goes (forward)", s.join, s.history, { landed: count }),
    recoverCase("a record marked rollback (its rollback failed): the next start restores every key (back)", s.join, s.history, { landed: 1, rollback: true }),
    recoverCase("another tab wrote a key meanwhile: storage is left as it is, the record dropped and the conflict logged (conflict)", s.join, s.history,
      { landed: 1, change: ["athkar-tasbih-v1", JSON.stringify({ ...tasbihStored(), counts: { subhan: 11 } })] }),
    recoverCase("an unreadable record is dropped and nothing else changes (invalid)", s.join, s.history, { landed: 0, record: "{not json" }),
    recoverAfterFailedStartCase("the next day, a write still fails: recovery keeps the record (failed), the day's load, rollover and saves leave its keys alone, and the start after that completes it (forward)", s.join, s.history)
  ];
}

// ---- the real path: encodeTransfer on the sender, decodeTransfer, planTransfer on the receiver ----

// Equivalent stored tasbih keys with their own epochs, as the app can hold them (a saved spelling whose load would sum
// the keys, or a key with tatweel that cleans to another key), today or on yesterday's history.
function aliasStore(variant, day) {
  const unit = key => `${day}|${key}`;
  const epoch = at(day, "04:00");
  const values = variant === "legacy" || variant === "equal" ? { "c:يا رب": 10, "c:يَا رَبّ": 2 }
    : variant === "tatweel" ? { "c:يا رب": 10, "c:يا ربـ": 2 } : { "c:يا رب": 10 };
  const newer = variant === "legacy" ? "c:يَا رَبّ" : "c:يا ربـ";
  const today = day === TRANSFER_TODAY;
  return device({
    tasbih: {
      custom: variant === "legacy" || variant === "equal" ? ["يا رب"] : [],
      counts: today ? values : {},
      firstUse: today ? Object.keys(values) : [],
      history: today ? {} : { [day]: values },
      resets: variant === "equal" ? {} : { [unit(newer)]: epoch }
    }
  });
}

async function realPathCase(name, sender, receiver, day, expected) {
  prepareTransfer();
  loadStorage(sender);
  const stored = fn.transferLocalFromStorage(fn.readTransferStorage());
  api.setStores({ state: stored.progress, suwarState: stored.suwar, tasbihState: fn.parseStoredTasbihState(sender["athkar-tasbih-v1"] ?? null) });
  api.setReminderPreferences(fn.loadReminderPreferences());
  const encoded = await fn.encodeTransfer("REAL");
  if (!encoded.ok) throw new Error(`${name}: encodeTransfer failed`);
  const decoded = await fn.decodeTransfer(encoded.code);
  if (!decoded.ok) throw new Error(`${name}: decodeTransfer refused the code: ${JSON.stringify(plain(decoded))}`);
  loadStorage(receiver);
  const plan = plain(fn.planTransfer(fn.transferLocalFromStorage(fn.readTransferStorage()), decoded, TRANSFER_NOW));
  const storage = withWrites(receiver, plan);
  const tasbih = JSON.parse(storage["athkar-tasbih-v1"]);
  const values = day === TRANSFER_TODAY ? tasbih.counts : tasbih.history[day] ?? {};
  const unit = Object.entries(values).filter(([key]) => key.startsWith("c:") && fn.tasbihMatchKey(key.slice(2)) === "يا رب");
  const count = unit.reduce((total, [, value]) => total + value, 0);
  if (unit.length > 1 || count !== expected) throw new Error(`${name}: expected ${expected}, got ${JSON.stringify(values)}`);
  return {
    name,
    input: { sender, receiver },
    expected: { codeTasbih: plain(decoded).container.athkar.tasbih, storedTasbih: { counts: tasbih.counts, history: tasbih.history, resets: tasbih.resets }, count }
  };
}

async function transferRealPathCases() {
  const cases = [];
  for (const [variant, expected, about] of [
    ["equal", 12, "two stored spellings of a saved phrase with equal epochs: summed, as on that device: 12"],
    ["legacy", 2, "two stored spellings of a saved phrase, one reset later: only the later counts: 2"],
    ["tatweel", 2, "a tatweel key that cleans to the other key, with the newer epoch: 2"],
    ["reset-only", 0, "a tatweel key holding only a newer reset: the unit is reset, 0"]
  ]) {
    for (const day of [TRANSFER_TODAY, YESTERDAY]) {
      const when = day === TRANSFER_TODAY ? "today" : "in history";
      cases.push(await realPathCase(`sender holds ${about} (${when})`, aliasStore(variant, day), device(), day, expected));
      cases.push(await realPathCase(`receiver holds ${about} (${when})`, device(), aliasStore(variant, day), day, expected));
    }
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
  sessionMeta("Scoped reset outcomes (confirmation accepted). day: resetDayProgress; week: resetWeek; everything: resetEverything. Each records reset epochs in `resets` (spec/transfer/transfer-v1.md §5.1): today for day, the 7 local dates for week, the 31-day window for everything.",
    "resetDayProgress, resetWeek, recentDates, resetEverything, hasResettableState, markReset"),
  sessionDefaultInput, scopedResetCases());
writeCases("spec/sessions/fixtures/tasbih-load-state.json",
  sessionMeta("athkar-tasbih-v1 startup path: parse, normalize (stored phrase keys migrate to today's cleaning: tashkeel-free matching, tatweel and ZWSP/ZWJ/LRM/RLM/ALM dropped, ZWNJ as a space, ہ as ه; converging keys summed, first use kept, capped at 99,999), roll to today's local date (a later stored date, after the clock moved back, sums its history days at or after today into today's counts). `reloaded` is the same load run on the saved result and must equal `state`.",
    "loadTasbihState, normalizeTasbihState, canonicalTasbihKey, cleanTasbihPhrase, tasbihMatchKey, canonicalTasbihDays, rollTasbihStateToDate"),
  { timeZone: SESSION_ZONE }, tasbihLoadCases());
writeCases("spec/reminders/fixtures/next-reminder-time.json",
  {
    about: "Adhkar reminder timing. nextReminderTime: today's time if in the future and not shown today; now+300 ms if ≤15 min past and not shown; else tomorrow's. scheduled: scheduleReminders outcome (skipped when disabled, permission not granted, period complete, or no time).",
    source: "index.html: nextReminderTime, scheduleReminders, prayerTimesForDate, periodIsComplete"
  },
  { collections: realCollections }, reminderCases());
written.push(writeVectors("spec/prayer-times/vectors.json"));

const transferSource = "index.html: base45Encode, base45Decode, transferChecksum, transferFrames, transferTextCode, " +
  "parseTransferFrame, decodeTransfer, decodeTransferFrames, decodeTransferFile, validateTransferContainer, validateTransferEnvelope";
const codec = await transferCodecFixture();
// The deflate-bomb guard: compressed bytes go in in slices and both sides stop once the output passes the cap, so a
// bomb is cut off long before its end and no more than cap + one slice's output (1 032 × slice) is ever read.
async function inflateBound(size) {
  const zlib = bombZlib(size);
  const cap = vm.runInContext("transferMaxInflatedBytes", context);
  const bound = cap + 1032 * vm.runInContext("transferInflateSlice", context);
  inflateStats.input = 0;
  inflateStats.produced = 0;
  const result = plain(await fn.inflateTransferBytes(zlib));
  // Every byte the decompressor ever inflated (read or still queued) is the peak it buffered.
  const produced = inflateStats.produced;
  const entry = { inflatedSize: size, compressedBytes: zlib.length, result: { reason: result.reason ?? null }, compressedFed: inflateStats.input, inflatedProduced: produced, cap, bound };
  if (result.reason !== "inflate-cap" || produced > bound) throw new Error(`deflate bomb not bounded: ${JSON.stringify(entry)}`);
  if (size > 4 * cap && inflateStats.input >= zlib.length) throw new Error(`deflate bomb not cut off early: ${JSON.stringify(entry)}`);
  return entry;
}
const inflateBounds = [await inflateBound(300000), await inflateBound(16 * 1024 * 1024)];
const roundTrips = [
  await roundTripCase("typical: some of today, a day of history, a reset epoch", codec.typical),
  await roundTripCase("full: every store full, a day epoch on each of the 31 window days", worstDevice(false)),
  await roundTripCase("worst case: every store full, epochs on every unit of the 31-day window", worstDevice(true))
];
written.push({
  path: writeJson("spec/transfer/fixtures/codec.json", {
    about: "Transfer code: base45 (RFC 9285) vectors, the frame checksum (Adler-32 of the frame text before it), QR frame splitting, " +
      "decoding of text, frames and files (`result`: { ok, source, container } or { ok: false, error, reason?, path? }), and round trips " +
      "through encodeTransfer's CompressionStream. Codes in `decode` use stored (uncompressed) deflate blocks so they are byte-identical everywhere; " +
      "decoding never touches storage.",
    source: transferSource,
    generator,
    defaultInput: transferDefaults,
    base45: codec.base45,
    base45Invalid: codec.base45Invalid,
    checksum: codec.checksum,
    frames: codec.frames,
    cases: codec.decode,
    roundTrip: roundTrips,
    inflateBounds
  }),
  count: codec.decode.length + roundTrips.length
});
writeCases("spec/transfer/fixtures/merge.json",
  sessionMeta("planTransfer on the receiver's stored values (`storage`) and a decoded code (`incoming`): the plan (additions, resets, keptLocal, settings, warnings, empty, writes; `before` is `storage` and is omitted) and the storage after its writes. Units are (date, period), (date, sura) and (date, phrase key); the later reset epoch takes a unit whole, equal epochs join (max, OR, earliest instant).",
    "planTransfer, mergeTransfer, mergeTransferProgress, mergeTransferSuwar, mergeTransferTasbih, mergeTransferSettings, transferLocalFromStorage, buildTransferContainer"),
  { ...transferDefaults, collections: realCollections }, await transferMergeCases());
const properties = transferPropertyCases();
written.push({
  path: writeJson("spec/transfer/fixtures/properties.json", {
    about: "Merge laws over devices with reset epochs. `local ← incoming` is the receiver's storage after applying the plan of incoming's code. " +
      "idempotent: receiving the same code twice equals once (byte-identical storage). commutative: local ← incoming and incoming ← local hold the same " +
      "convergent stores (everything except receiver-owned fields: targets, selected sura and phrase, tasbih target, saved-phrase order and spelling, first-use order). " +
      "converges: after transfers both ways the two devices hold the same convergent stores. associative: (a ← b) ← c and a ← (b ← c) agree.",
    source: "index.html: planTransfer, mergeTransfer, buildTransferContainer",
    generator,
    defaultInput: transferDefaults,
    devices: properties.devices,
    pairs: properties.pairs,
    triples: properties.triples
  }),
  count: properties.pairs.length + properties.triples.length
});
writeCases("spec/transfer/fixtures/real-path.json",
  sessionMeta("The tasbih through the real path: encodeTransfer on the sender (its stored keys with their own epochs), decodeTransfer, then planTransfer on the receiver; the storage after the plan's writes. One device's equivalent keys are canonicalised as its own load does (only the latest epoch counts, those summed); across devices the later epoch wins, equal epochs take the max. `codeTasbih`: the tasbih part of the decoded code; `count`: the unit «يا رب» after the transfer.",
    "encodeTransfer, transferContainerNow, transferTasbihView, decodeTransfer, planTransfer, mergeTransferTasbih"),
  { ...transferDefaults, collections: realCollections }, await transferRealPathCases());
writeCases("spec/transfer/fixtures/apply.json",
  sessionMeta("applyTransfer commits exactly a plan: every stored value must still be what the plan was made on; the write-ahead record athkar-transfer-pending-v1 is written first and removed last; a failed write rolls the earlier ones back (a rollback that fails too leaves the record marked `rollback` for the next start); a tab in tasbih memory mode or with unreadable storage writes nothing. `fault` n: the (n+1)th setItem fails once, the record's write counting as the first; `stuckKeys`: then every setItem of these keys fails.",
    "applyTransfer, readTransferStorage, recoverTransferPending"),
  { ...transferDefaults, collections: realCollections }, transferApplyCases());
writeCases("spec/transfer/fixtures/recover.json",
  sessionMeta("recoverTransferPending at startup, before the stores load: storage holds a write-ahead record (athkar-transfer-pending-v1) left by a transfer interrupted after some of its writes. `recovered`: forward (every key now holds the plan's value), back (a record marked rollback: every key holds the planned-on value), conflict (a key holds neither: left as stored, record dropped, logged), invalid (unreadable record dropped).",
    "recoverTransferPending"),
  { ...transferDefaults, collections: realCollections }, transferRecoverCases());

for (const { path, count } of written) console.log(`${path}: ${count}`);
