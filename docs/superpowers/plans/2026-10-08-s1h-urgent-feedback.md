# S1h: Urgent feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline). Steps use checkbox (`- [ ]`) syntax.

**Goal:** When `urgentWiggle` is on, an app whose window is urgent wiggles its icon, and the dock reveals when an urgent window appears. Default false keeps today's behavior.

**Architecture:** `logic/urgent.js` holds the pure rules (parse the Hyprland urgent address, decide whether a set of toplevels contains an urgent one, decide whether to reveal). `DockPanel.qml` tracks urgent addresses from the `urgent`/`urgentv2` raw events, clears them on focus, and wiggles the matching icon.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Default `urgentWiggle` is false and must change nothing.
- `logic/urgent.js` keeps the CommonJS guard and takes no QML globals.
- Run `test/run.sh` before committing.

## Review Focus

1. With `urgentWiggle` off, nothing wiggles and no dock reveal happens.
2. An urgent window on a non-running app does not wiggle an unrelated icon.
3. Focus clears urgency so the wiggle stops.
4. The wiggle animation does not fight the launch bounce or the magnifier.

---

### Task 1: Urgent rules

**Files:**
- Create: `logic/urgent.js`
- Create: `test/urgent.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `Urgent.addressFromEvent(data) -> string`; `Urgent.hasUrgent(toplevels, urgentAddrs, addressOf) -> bool`; `Urgent.shouldReveal(urgentWiggle, urgentCount) -> bool`.

- [ ] **Step 1: Write the failing test `test/urgent.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const U = require("../logic/urgent.js");

test("addressFromEvent reads the address", () => {
  assert.strictEqual(U.addressFromEvent("0x1234"), "0x1234");
});

test("addressFromEvent ignores trailing fields", () => {
  assert.strictEqual(U.addressFromEvent("0x1234,extra"), "0x1234");
});

test("addressFromEvent returns empty for empty input", () => {
  assert.strictEqual(U.addressFromEvent(""), "");
});

test("hasUrgent is true when a toplevel address is in the set", () => {
  const tls = [{ a: "0x1" }, { a: "0x2" }];
  assert.strictEqual(U.hasUrgent(tls, { "0x2": true }, (t) => t.a), true);
});

test("hasUrgent is false when none match", () => {
  const tls = [{ a: "0x1" }];
  assert.strictEqual(U.hasUrgent(tls, { "0x9": true }, (t) => t.a), false);
});

test("shouldReveal only when enabled and urgent", () => {
  assert.strictEqual(U.shouldReveal(true, 1), true);
  assert.strictEqual(U.shouldReveal(false, 1), false);
  assert.strictEqual(U.shouldReveal(true, 0), false);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/urgent.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/urgent.js`**

`addressFromEvent` trims and takes the first comma/whitespace token. `hasUrgent` iterates toplevels, calls `addressOf`, and returns true on the first address present in `urgentAddrs`. `shouldReveal` returns `urgentWiggle === true && urgentCount > 0`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/urgent.test.js`
Expected: 6 passing.

- [ ] **Step 5: Append to `test/qml/tst_logic.qml`**

Add `import "../../logic/urgent.js" as UrgentLogic` and a `test_urgent` case.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint clean.

- [ ] **Step 7: Commit**

```bash
git add logic/urgent.js test/urgent.test.js test/qml/tst_logic.qml
git commit -m "feat: add urgent-window rules"
```

---

### Task 2: Wire urgency into the dock

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Urgent.*`, `Settings.urgentWiggle`.

- [ ] **Step 1: Track urgent addresses**

Add `import "logic/urgent.js" as Urgent`, `property var urgentAddrs: ({})`, `property int _urgentTick: 0`, and a `toplevelAddress(tl)` helper. In `onRawEvent`, handle `urgent`/`urgentv2` (add the address, bump `_urgentTick`, and `showDockBar()` when `Settings.urgentWiggle`), and clear `urgentAddrs` on `activewindow`/`activewindowv2`.

- [ ] **Step 2: Wiggle the matching icon**

In the app delegate add `readonly property bool urgentNow: { root._urgentTick; return Settings.urgentWiggle && Urgent.hasUrgent(appItem.toplevels, root.urgentAddrs, root.toplevelAddress) }`, a `property real wiggleAngle: 0`, and a `SequentialAnimation` (`running: appItem.urgentNow`, infinite) that sweeps `wiggleAngle` 0 to -10 to 10 to 0. Apply `rotation: appItem.wiggleAngle` to the icon `Image`.

- [ ] **Step 3: Verify by reload**

Run: `omarchy restart shell`. Expected: no dock errors; with `urgentWiggle` off the dock is unchanged.

- [ ] **Step 4: Commit**

```bash
git add DockPanel.qml CHANGELOG.md
git commit -m "feat: wiggle and reveal on urgent windows"
```
