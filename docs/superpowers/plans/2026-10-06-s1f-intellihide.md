# S1f: Intellihide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let `intellihide` hide the dock when a window overlaps the bar, filtered by `intellihideMode` (`all` | `focused` | `maximized` | `always-on-top`). Defaults (`false`, `focused`) change nothing: the dock never hides by overlap until the user flips the toggle.

**Architecture:** `logic/intellihide.js` is a pure rule over plain rectangles (`shouldHide(enabled, mode, windows, dockRect)`); the windows carry `focused` / `maximized` / `onTop` flags derived once in `DockPanel.visibleWindowRects()` from Hyprland's IPC (`focusHistoryID`, `fullscreen`, `pinned`). `DockPanel.qml` recomputes a single `intellihideBlocked` flag on the existing `geometryTimer` (the same debounce that drives dynamic transparency) and feeds it into the existing show/hide paths as extra hide pressure: with `mode: always`, an overlap schedules the hide and the close re-shows; hover reveal keeps working, so the dock stays reachable while blocked.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Default `intellihide: false` must make `shouldHide` return `false` for every input; no show/hide path may change behavior while the flag is off.
- `logic/intellihide.js` keeps the CommonJS guard, takes no QML globals, and is pure over plain arrays/objects.
- No polling: the blocked flag is recomputed only from the existing event-driven `geometryTimer`.
- Reveal-on-hover (trigger strip) must keep working while blocked — intellihide hides, it never traps.
- Run `test/run.sh` before committing.

## Review Focus

1. `intellihide: false` (default) leaves `always`/`autohide`/`smart` show/hide byte-for-byte unchanged.
2. Overlap is strict intersection with the bar's global rect (no slack), per mode filter, unknown mode falls back to `focused`.
3. Focus/maximize/pin changes re-trigger the recompute (`activewindow`, `fullscreen`, `movewindow` are already geometry events).
4. Blocked while pointer is on the dock: dock stays up; pointer leaves → hides (no flicker loop).
5. Settings rows persist via `Settings.save()`; no binding loops between `intellihideBlocked` and the show/hide handlers.

---

### Task 1: Intellihide rule

**Files:**
- Create: `logic/intellihide.js`
- Create: `test/intellihide.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `Intellihide.MODES` (["all","focused","maximized","always-on-top"]), `Intellihide.overlaps(a, b)` -> bool, `Intellihide.shouldHide(enabled, mode, windows, dockRect)` -> bool.

- [ ] **Step 1: Write the failing test `test/intellihide.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/intellihide.js");

const dock = { x: 0, y: 900, w: 1920, h: 78 };
const over = { x: 100, y: 850, w: 400, h: 200, focused: false, maximized: false, onTop: false };
const away = { x: 100, y: 100, w: 400, h: 300, focused: true, maximized: false, onTop: false };

test("disabled never hides", () => {
  assert.strictEqual(I.shouldHide(false, "all", [over], dock), false);
});

test("all hides on any overlapping window", () => {
  assert.strictEqual(I.shouldHide(true, "all", [over, away], dock), true);
  assert.strictEqual(I.shouldHide(true, "all", [away], dock), false);
});

test("focused only counts the focused window", () => {
  assert.strictEqual(I.shouldHide(true, "focused", [over], dock), false);
  assert.strictEqual(I.shouldHide(true, "focused", [{ ...over, focused: true }], dock), true);
});

test("maximized only counts a maximized window", () => {
  assert.strictEqual(I.shouldHide(true, "maximized", [{ ...over, maximized: true }], dock), true);
  assert.strictEqual(I.shouldHide(true, "maximized", [{ ...over, focused: true }], dock), false);
});

test("always-on-top only counts a pinned window", () => {
  assert.strictEqual(I.shouldHide(true, "always-on-top", [{ ...over, onTop: true }], dock), true);
  assert.strictEqual(I.shouldHide(true, "always-on-top", [{ ...over, focused: true }], dock), false);
});

test("touching edges is not an overlap", () => {
  const touching = { x: 0, y: 800, w: 100, h: 100, focused: true, maximized: false, onTop: false };
  assert.strictEqual(I.overlaps(touching, dock), false);
  assert.strictEqual(I.shouldHide(true, "all", [touching], dock), false);
});

test("an unknown mode falls back to focused", () => {
  assert.strictEqual(I.shouldHide(true, "sideways", [over], dock), false);
  assert.strictEqual(I.shouldHide(true, "sideways", [{ ...over, focused: true }], dock), true);
});

test("empty window list never hides", () => {
  assert.strictEqual(I.shouldHide(true, "all", [], dock), false);
  assert.strictEqual(I.shouldHide(true, "all", null, dock), false);
});

test("modes list matches the settings schema", () => {
  assert.deepStrictEqual(I.MODES, ["all", "focused", "maximized", "always-on-top"]);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/intellihide.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/intellihide.js`**

Strict rectangle intersection in `overlaps(a, b)` (`a.x < b.x + b.w && a.x + a.w > b.x` on both axes). `shouldHide(enabled, ...)` returns `false` immediately when disabled; unknown mode normalizes to `focused`; each mode filters the window flags (`all` = every window, `focused` = `w.focused`, `maximized` = `w.maximized`, `always-on-top` = `w.onTop`) and returns `true` on the first flag-matching window that overlaps `dockRect`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/intellihide.test.js`
Expected: 9 passing.

- [ ] **Step 5: Append to `test/qml/tst_logic.qml`**

Add `import "../../logic/intellihide.js" as IntellihideLogic` and a `test_intellihide` case asserting `shouldHide(false, "all", [over], dock) === false`, `shouldHide(true, "focused", [{...over, focused: true}], dock) === true`, and `overlaps(touching, dock) === false`.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint clean.

- [ ] **Step 7: Commit**

```bash
git add logic/intellihide.js test/intellihide.test.js test/qml/tst_logic.qml
git commit -m "feat: add intellihide overlap rule"
```

---

### Task 2: Wire intellihide into the dock and Settings

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Intellihide.shouldHide`, `Settings.intellihide|intellihideMode`, `dockBarRect()`, `visibleWindowRects()`.

- [ ] **Step 1: Flag the window rects and compute the blocked flag**

Add `import "logic/intellihide.js" as Intellihide`. Extend `visibleWindowRects()` to also carry `focused` (`focusHistoryID === 0`), `maximized` (`fullscreen >= 1`) and `onTop` (`pinned === true`) — transparency ignores the extra keys. Add `property bool intellihideBlocked: false` and `readonly property bool intellihideHides: Settings.intellihide && intellihideBlocked`, plus `function updateIntellihide()` calling `Intellihide.shouldHide(Settings.intellihide, Settings.intellihideMode, root.visibleWindowRects(), root.dockBarRect())` and assigning only on change. Call it from `geometryTimer.onTriggered` next to `updateDynamicNear()`.

- [ ] **Step 2: Feed the flag into the show/hide paths**

- `scheduleHide()`: early-return only when `dockMode === "always" && !intellihideHides`.
- `hideTimer.onTriggered`: same guard instead of the plain `always` return.
- `maybeHideAfterAction()`: in the `always` branch return unless `intellihideHides`; when it hides, keep the `mouseOverDockArea` guard.
- Add `onIntellihideBlockedChanged`: blocked → `scheduleHide()`; unblocked → `showDockBar()` when `dockMode === "always"` (or `smart` + `workspaceEmpty`).
- `onDockModeChanged` / `onWorkspaceEmptyChanged` `always` branches: show only when `!intellihideHides`.
- `Connections { target: Settings; function onIntellihideChanged() { root.updateIntellihide() } function onIntellihideModeChanged() { root.updateIntellihide() } }` (merge into the existing Settings Connections block).

- [ ] **Step 3: Add the Settings controls**

After the Visibility help text add an "Intellihide" header, a toggle row (magnify-style switch) writing `Settings.intellihide` + `Settings.save()`, and four radio rows wired like the Visibility group: `all` "Qualquer janela", `focused` "Janela focada", `maximized` "Janela maximizada", `always-on-top` "Sempre no topo".

- [ ] **Step 4: Verify by reload**

Run: `omarchy restart shell`, then grep the newest log:
`LOG=$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog | head -1); strings -n 6 "$LOG" | grep -aiE 'DockPanel|intellihide|TypeError|ReferenceError|is not defined|unavailable|load failed|Non-existent'`
Expected: no dock errors. Manual: toggle off → dock behaves exactly as before; toggle on with `maximized` → maximize a window (`hl.dsp.window.toggleMaximize` via a terminal or super+m) → dock slides away, un-maximize → returns; hover reveal still works while blocked.

- [ ] **Step 5: Commit**

```bash
git add DockPanel.qml
git commit -m "feat: wire intellihide visibility"
```

---

### Task 3: Changelog and plan

- [ ] **Step 1:** Append the S1f entry to `CHANGELOG.md` under "### S1: behavior and layout" and update the "Remaining S1 phases" line.
- [ ] **Step 2:** Run `test/run.sh`, then commit:

```bash
git add CHANGELOG.md docs/superpowers/plans/2026-10-06-s1f-intellihide.md
git commit -m "docs: add the S1f intellihide plan and changelog entry"
```
