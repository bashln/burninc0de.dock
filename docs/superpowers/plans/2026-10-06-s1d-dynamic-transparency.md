# S1d: Dynamic transparency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let `transparencyMode` switch the dock glass between today's fixed theme alpha and a dynamic alpha that gets more opaque as a window nears/overlaps the dock and more translucent when the area is free, between `minAlpha` and `maxAlpha`.

**Architecture:** `logic/transparency.js` turns plain rectangles into a 0..1 "nearness" value (rect distance vs a slack) and maps `(mode, nearness, minAlpha, maxAlpha, fixedAlpha)` to the bar alpha. `DockPanel.qml` builds the dock's global rectangle from the Hyprland monitor + `dockBar` geometry, collects visible window rectangles from `Hyprland.toplevels`, and feeds the helper; the result drives `dockBar.color` through a `Behavior` so alpha changes glide.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Default `transparencyMode` is `fixed`: the bar keeps using `glassAlpha` (theme-derived, clamped 0.35..0.75) byte-for-byte.
- `logic/transparency.js` keeps the CommonJS guard and takes no QML globals.
- Geometry inputs are plain data: `{x, y, w, h}` rectangles only.
- No new runtime dependencies; no polling timers (recompute on Hyprland raw events + bar geometry changes, debounced).
- Run `test/run.sh` before committing.

## Review Focus

1. `fixed` mode must be provably identical to today: alpha equals `glassAlpha` for every nearness value.
2. `dynamic` alpha never leaves `[minAlpha, maxAlpha]`, even if the settings file hands in min > max.
3. Hidden/minimized windows (e.g. on `special:dock_minimize`) must not count as "near" — only windows with `visible !== false`.
4. Alpha updates must not thrash: debounced event recompute, `Behavior` smooths steps, no binding loops (`barAlpha` must not feed the geometry it is computed from).
5. Settings sliders for `minAlpha`/`maxAlpha` must persist through `settings.json` and clamp on load (schema already tested).

---

### Task 1: Transparency logic

**Files:**
- Create: `logic/transparency.js`
- Create: `test/transparency.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `Transparency.DEFAULT_SLACK` (120), `Transparency.distance(a, b) -> number` (0 when rects intersect), `Transparency.nearness(windows, dock, slack) -> 0..1`, `Transparency.alphaFor(mode, near, minAlpha, maxAlpha, fixedAlpha) -> number`.

- [ ] **Step 1: Write the failing test `test/transparency.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const T = require("../logic/transparency.js");

const dock = { x: 0, y: 1000, w: 1920, h: 78 };

test("distance is 0 for intersecting rects", () => {
  assert.strictEqual(T.distance({ x: 0, y: 990, w: 100, h: 50 }, dock), 0);
});

test("distance is the gap between separated rects", () => {
  assert.strictEqual(T.distance({ x: 0, y: 900, w: 100, h: 60 }, dock), 40);
});

test("nearness is 1 for an overlapping window", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 950, w: 1920, h: 130 }], dock, 100), 1);
});

test("nearness is 0 for an empty window list", () => {
  assert.strictEqual(T.nearness([], dock, 100), 0);
});

test("nearness interpolates inside the slack", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 850, w: 100, h: 50 }], dock, 100), 0.5);
});

test("nearness is 0 at or beyond the slack", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 800, w: 100, h: 100 }], dock, 100), 0);
});

test("fixed mode returns the fixed alpha for every nearness", () => {
  assert.strictEqual(T.alphaFor("fixed", 1, 0.35, 0.75, 0.6), 0.6);
  assert.strictEqual(T.alphaFor("fixed", 0, 0.35, 0.75, 0.6), 0.6);
});

test("dynamic mode maps nearness onto min..max", () => {
  assert.strictEqual(T.alphaFor("dynamic", 0, 0.35, 0.75, 0.6), 0.35);
  assert.strictEqual(T.alphaFor("dynamic", 1, 0.35, 0.75, 0.6), 0.75);
  assert.strictEqual(T.alphaFor("dynamic", 0.5, 0.35, 0.75, 0.6), 0.55);
});

test("dynamic mode clamps out-of-range nearness", () => {
  assert.strictEqual(T.alphaFor("dynamic", 2, 0.35, 0.75, 0.6), 0.75);
  assert.strictEqual(T.alphaFor("dynamic", -1, 0.35, 0.75, 0.6), 0.35);
});

test("inverted min/max still stays inside the bounds", () => {
  assert.strictEqual(T.alphaFor("dynamic", 0, 0.75, 0.35, 0.6), 0.35);
  assert.strictEqual(T.alphaFor("dynamic", 1, 0.75, 0.35, 0.6), 0.75);
});

test("an unknown mode behaves like fixed", () => {
  assert.strictEqual(T.alphaFor("blur", 1, 0.35, 0.75, 0.6), 0.6);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/transparency.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/transparency.js`**

Rect distance (axis gaps, hypotenuse; 0 when intersecting). `nearness(windows, dock, slack)`: max over windows of `1 - clamp(distance/slack, 0, 1)`; `slack <= 0` falls back to `DEFAULT_SLACK` (120). `alphaFor(mode, near, min, max, fixed)`: only `dynamic` interpolates, between `min(min,max)` and `max(min,max)`, nearness clamped to 0..1; everything else returns `fixed`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/transparency.test.js`
Expected: 11 passing.

- [ ] **Step 5: Append to `test/qml/tst_logic.qml`**

Add `import "../../logic/transparency.js" as TransparencyLogic` and a `test_transparency` case asserting `alphaFor("fixed", 1, .35, .75, .6) === .6`, `alphaFor("dynamic", .5, .35, .75, 0) === .55`, `nearness([], dock, 100) === 0`.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint clean.

- [ ] **Step 7: Commit**

```bash
git add logic/transparency.js test/transparency.test.js test/qml/tst_logic.qml
git commit -m "feat: add transparency alpha logic"
```

---

### Task 2: Feed real geometry and add the Settings control

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Transparency.nearness/alphaFor`, `Settings.transparencyMode|minAlpha|maxAlpha`, `Hyprland.toplevels`, `hlMonitor`, `dockBar` geometry.

- [ ] **Step 1: Compute the dock rectangle and window nearness**

Add `import "logic/transparency.js" as Transparency` and a `readonly property int panelDepth: 320` used by `implicitHeight`. Add properties `dynamicNear` (real, 0) and `barAlpha` (binding through `Transparency.alphaFor(...)`, with a 250ms InOutQuad `Behavior`). Add `dockBarRect()` returning the bar's global rectangle (`x: hlMonitor.x + dockBar.x`, `y: hlMonitor.y + screenHeight - panelDepth + dockBar.y`, `w/h: dockBar.width/height`) and `updateDynamicNear()` collecting visible windows on this monitor (`tl.lastIpcObject.visible !== false`, `tl.monitor === hlMonitor`, `at`/`size` arrays) into plain rects and assigning `dynamicNear`. `dockBar.color` switches from `glassAlpha` to `barAlpha`.

- [ ] **Step 2: Recompute on change, debounced**

In the existing `Connections { target: Hyprland onRawEvent }`, restart a new 120ms `geometryTimer` for `movewindow`, `movewindowv2`, `openwindow`, `closewindow`, `activewindow`, `fullscreen`, `changefloatingmode`, `moveworkspacev2`, `focusedmon`, `focusedmonv2`; its `onTriggered` calls `updateDynamicNear()`. Also call it from `onDockVisibleChanged` and from `dockBar.onWidthChanged`/`onHeightChanged`, and once in `Component.onCompleted`. Add `Connections { target: Settings; function onTransparencyModeChanged() { updateDynamicNear() } }`.

- [ ] **Step 3: Add the Settings panel group**

After the Indicator group add a "Transparency" header, two radio-style rows (`fixed` "Fixa (tema)", `dynamic` "Dinâmica (janela perto)") wired like the Visibility rows (`Settings.transparencyMode = ...; Settings.save()`), and two sliders `minAlpha`/`maxAlpha` (0.1..1.0, step 0.05, `Settings.minAlpha`/`Settings.maxAlpha`, `settingsSaveTimer.restart()` on `onMoved`) labelled "Alpha mínimo"/"Alpha máximo".

- [ ] **Step 4: Verify by reload**

Run: `omarchy restart shell`, then grep the newest log:
`LOG=$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog | head -1); strings -n 6 "$LOG" | grep -aiE 'DockPanel|transparency|TypeError|ReferenceError|is not defined|unavailable|load failed|Non-existent'`
Expected: no dock errors, a `quickshelldock` openlayer line. In Settings, switch Transparency to `Dinâmica` and watch the bar get translucent on an empty workspace / opaque with a window near it; switch back to `Fixa` and confirm the original look.

- [ ] **Step 5: Commit**

```bash
git add DockPanel.qml
git commit -m "feat: apply dynamic dock transparency"
```
