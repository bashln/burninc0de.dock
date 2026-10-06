# S1c: Running-indicator styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let `indicatorStyle` switch the running indicator between a single dot (current), one dot per window, one dash per window, a solid bar, and a numeric count.

**Architecture:** `logic/indicator.js` maps `(style, windowCount)` to a render spec (`segments`, `shape`, `showCount`). `DockPanel.qml` renders that spec as a Row of small Rectangles (or a Text for `count`). Default `dot` reproduces today's single 4x4 dot, so nothing changes until the setting is switched.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Default `indicatorStyle` is `dot` and must render exactly as before: one 4x4 dot, radius 2, color `Color.accent`, bottom-center with `bottomMargin: -6`.
- `logic/indicator.js` keeps the CommonJS guard and takes no QML globals.
- Cap multi-segment styles at 4 segments.
- Run `test/run.sh` before committing.

## Review Focus

1. A running app with many windows (10+) must not draw 10 dots: the cap holds.
2. A non-running app must draw no indicator in every style.
3. Switching styles live did not break the count badge or the hover window list.
4. The `count` style must not collide visually with the existing top-left multi-window badge.

---

### Task 1: Indicator spec logic

**Files:**
- Create: `logic/indicator.js`
- Create: `test/indicator.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `Indicator.LIMIT` (4) and `Indicator.spec(style, count) -> { segments: int, shape: "dot"|"dash"|"bar", showCount: bool }`.

- [ ] **Step 1: Write the failing test `test/indicator.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/indicator.js");

test("dot is a single dot and does not show a count", () => {
  assert.deepStrictEqual(I.spec("dot", 3), { segments: 1, shape: "dot", showCount: false });
});

test("dots draws one dot per window", () => {
  assert.deepStrictEqual(I.spec("dots", 3), { segments: 3, shape: "dot", showCount: false });
});

test("dots caps at LIMIT segments", () => {
  assert.deepStrictEqual(I.spec("dots", 10), { segments: I.LIMIT, shape: "dot", showCount: false });
});

test("dashes draws one dash per window", () => {
  assert.deepStrictEqual(I.spec("dashes", 2), { segments: 2, shape: "dash", showCount: false });
});

test("solid is a single bar", () => {
  assert.deepStrictEqual(I.spec("solid", 5), { segments: 1, shape: "bar", showCount: false });
});

test("count shows the number and no segments", () => {
  assert.deepStrictEqual(I.spec("count", 4), { segments: 0, shape: "dot", showCount: true });
});

test("an unknown style falls back to dot", () => {
  assert.deepStrictEqual(I.spec("sparkle", 2), { segments: 1, shape: "dot", showCount: false });
});

test("zero windows yields no segments for every style", () => {
  assert.strictEqual(I.spec("dots", 0).segments, 0);
  assert.strictEqual(I.spec("dashes", 0).segments, 0);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/indicator.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/indicator.js`**

`LIMIT = 4`. `spec(style, count)` switches on style: `dot` -> 1 dot; `dots` -> `Math.min(count, LIMIT)` dots; `dashes` -> `Math.min(count, LIMIT)` dashes; `solid` -> 1 bar; `count` -> 0 segments, `showCount: true`; default -> dot. Clamp `count` to `>= 0`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/indicator.test.js`
Expected: 8 passing.

- [ ] **Step 5: Append to `test/qml/tst_logic.qml`**

Add `import "../../logic/indicator.js" as IndicatorLogic` and a `test_indicator` case asserting `spec("dots", 3).segments === 3` and `spec("count", 1).showCount === true`.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint clean.

- [ ] **Step 7: Commit**

```bash
git add logic/indicator.js test/indicator.test.js test/qml/tst_logic.qml
git commit -m "feat: add indicator spec logic"
```

---

### Task 2: Render the indicator in the dock

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Indicator.spec`, `Settings.indicatorStyle`, `appItem.toplevels.length`.

- [ ] **Step 1: Replace the single dot with the spec-driven indicator**

Add `import "logic/indicator.js" as Indicator` to `DockPanel.qml`. Replace the running-dot `Rectangle` with an `Item` anchored `bottom`/`horizontalCenter`, `bottomMargin: -6`, containing a `Row` (`spacing: 3`) whose `Repeater` model is `Indicator.spec(Settings.indicatorStyle, appItem.toplevels.length).segments`. Each segment is a `Rectangle`: for `dot` 4x4 radius 2; for `dash` 8x3 radius 1.5; for `bar` `root.itemSize * 0.6` wide, 3 tall, radius 1.5; color `Color.accent`. Add a `Text` shown when `showCount` is true, `textFormat: Text.PlainText`, tiny (pixelSize 9), color `Color.accent`.

- [ ] **Step 2: Add a style picker to the Settings panel**

Under the existing "Appearance" area add a labelled row group `Indicator` listing the five styles (`dot`, `dots`, `dashes`, `solid`, `count`) as tappable rows like the Visibility group, calling `Settings.indicatorStyle = <style>` and `settingsSaveTimer.restart()`.

- [ ] **Step 3: Verify by reload**

Run: `omarchy restart shell`, then in Settings switch the indicator style while an app with windows is running.
Expected: the indicator changes shape; `dot` looks exactly as before; no QML errors in `log.qslog`.

- [ ] **Step 4: Commit**

```bash
git add DockPanel.qml
git commit -m "feat: render configurable running-indicator styles"
```
