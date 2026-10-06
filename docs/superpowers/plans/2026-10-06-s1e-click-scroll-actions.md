# S1e: Click and scroll actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make `clickAction` (minimize|launch|cycle|focus) govern left-clicks on running icons and `scrollAction` (nothing|cycle-windows|switch-workspace) govern the wheel over the dock. Defaults (`minimize`, `nothing`) reproduce today's behavior exactly: clicking a running icon toggles minimize/restore and the wheel does nothing.

**Architecture:** `logic/actions.js` maps `(clickAction, isRunning)` to an operation string, computes wrapped `cycleIndex` positions from `focusHistoryID` arrays, routes `scrollAction`, and accumulates wheel deltas into notches (`scrollStep`). `DockPanel.qml` branches the left-click handler on the routed operation (the existing minimize/restore blob stays the `minimize` operation untouched), adds a `WheelHandler` on `dockBar`, and exposes the two option groups in the Settings panel.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Default `clickAction: minimize` must keep the current minimize/restore blob byte-for-byte as its operation; default `scrollAction: nothing` must not consume the wheel beyond `event.accepted`.
- `logic/actions.js` keeps the CommonJS guard, takes no QML globals, and is pure over plain arrays/strings.
- Non-running icons always launch (busy/runningOnly guards unchanged), regardless of `clickAction`.
- Wheel actions fire once per 120-unit notch (high-res wheels send many small deltas).
- Run `test/run.sh` before committing.

## Review Focus

1. `minimize` (default) routing must land in the pre-existing minimize/restore/focus logic with no edits to that blob's dispatches.
2. `launch` on a running icon launches a second window; runningOnly entries (no cmd) must not exec an empty command.
3. `cycle`/`focus` focus by address with the existing `"0x" + address` fallback and class fallback; cycle wraps.
4. Wheel: `nothing` leaves workspaces/windows untouched; `switch-workspace` uses the omarchy DSL `hl.dsp.focus({ workspace = "e+1" / "e-1" })`; `cycle-windows` only cycles windows on this monitor's active workspace.
5. Settings rows persist via `Settings.save()` and the icons' right-click menus, badges and hover window list still behave.

---

### Task 1: Action routing logic

**Files:**
- Create: `logic/actions.js`
- Create: `test/actions.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `Actions.routeClick(action, running) -> "minimize"|"launch"|"cycle"|"focus"`, `Actions.cycleIndex(focusIds, delta) -> int` (-1 when empty), `Actions.routeScroll(action) -> "nothing"|"cycle-windows"|"switch-workspace"`, `Actions.NOTCH` (120), `Actions.scrollStep(acc, delta) -> {acc, fire}`.

- [ ] **Step 1: Write the failing test `test/actions.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const A = require("../logic/actions.js");

test("a non-running icon always launches", () => {
  assert.strictEqual(A.routeClick("minimize", false), "launch");
  assert.strictEqual(A.routeClick("cycle", false), "launch");
  assert.strictEqual(A.routeClick("focus", false), "launch");
});

test("minimize routes running icons to the minimize toggle", () => {
  assert.strictEqual(A.routeClick("minimize", true), "minimize");
});

test("launch/cycle/focus route running icons accordingly", () => {
  assert.strictEqual(A.routeClick("launch", true), "launch");
  assert.strictEqual(A.routeClick("cycle", true), "cycle");
  assert.strictEqual(A.routeClick("focus", true), "focus");
});

test("an unknown click action falls back to minimize", () => {
  assert.strictEqual(A.routeClick("explode", true), "minimize");
});

test("cycleIndex returns -1 for an empty window list", () => {
  assert.strictEqual(A.cycleIndex([], 1), -1);
  assert.strictEqual(A.cycleIndex([], -1), -1);
});

test("cycleIndex picks the only window", () => {
  assert.strictEqual(A.cycleIndex([0], 1), 0);
  assert.strictEqual(A.cycleIndex([4], -1), 0);
});

test("cycleIndex starts at the most recent window when none is focused", () => {
  assert.strictEqual(A.cycleIndex([5, 9, 2], 1), 2);
  assert.strictEqual(A.cycleIndex([5, 9, 2], -1), 2);
});

test("cycleIndex steps forward from the focused window and wraps", () => {
  // ids[i] = focusHistoryID of window i; 0 = currently focused (index 1)
  assert.strictEqual(A.cycleIndex([5, 0, 9], 1), 0);
  assert.strictEqual(A.cycleIndex([0, 5, 9], 1), 1);
  assert.strictEqual(A.cycleIndex([0, 5, 9], -1), 2);
  assert.strictEqual(A.cycleIndex([7, 0], -1), 0);
});

test("routeScroll maps the enum and rejects unknown values", () => {
  assert.strictEqual(A.routeScroll("cycle-windows"), "cycle-windows");
  assert.strictEqual(A.routeScroll("switch-workspace"), "switch-workspace");
  assert.strictEqual(A.routeScroll("nothing"), "nothing");
  assert.strictEqual(A.routeScroll("nope"), "nothing");
});

test("scrollStep fires once per notch and resets", () => {
  let s = A.scrollStep(0, 30);
  assert.deepStrictEqual(s, { acc: 30, fire: false });
  s = A.scrollStep(s.acc, 30);
  assert.strictEqual(s.fire, false);
  s = A.scrollStep(s.acc, 60);
  assert.deepStrictEqual(s, { acc: 0, fire: true });
  assert.deepStrictEqual(A.scrollStep(0, 120), { acc: 0, fire: true });
});

test("scrollStep accumulates in both directions", () => {
  assert.deepStrictEqual(A.scrollStep(60, -60), { acc: 0, fire: false });
  const up = A.scrollStep(0, -120);
  assert.deepStrictEqual(up, { acc: 0, fire: true });
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/actions.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/actions.js`**

`routeClick`: `!running → "launch"`; then switch on the action (`launch`/`cycle`/`focus` pass through, default → `"minimize"`). `cycleIndex(ids, delta)`: empty → -1; single → 0; order indices by id ascending; if the sorted head has id 0 (a focused window) step by `delta` with wrap, otherwise return the most recent (sorted head). `routeScroll`: pass through the three values, everything else `"nothing"`. `scrollStep(acc, delta)`: sum; if `abs(sum) >= NOTCH` (120) → `{acc: 0, fire: true}` else `{acc: sum, fire: false}`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/actions.test.js`
Expected: 11 passing.

- [ ] **Step 5: Append to `test/qml/tst_logic.qml`**

Add `import "../../logic/actions.js" as ActionsLogic` and a `test_actions` case asserting `routeClick("minimize", true) === "minimize"`, `routeClick("cycle", false) === "launch"`, `cycleIndex([0, 5, 9], -1) === 2`, `scrollStep(0, 120).fire === true`.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint clean.

- [ ] **Step 7: Commit**

```bash
git add logic/actions.js test/actions.test.js test/qml/tst_logic.qml
git commit -m "feat: add click and scroll action routing"
```

---

### Task 2: Route clicks, add the wheel, expose Settings

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Actions.routeClick/cycleIndex/routeScroll/scrollStep`, `Settings.clickAction|scrollAction`, `Hyprland.dispatch`.

- [ ] **Step 1: Extract a shared focus helper and route the left click**

Add `import "logic/actions.js" as Actions`. Add `function focusToplevel(tl)` containing the existing focus dispatch (address fallback `"0x" + tl.address`, then class fallback) and replace the two inline copies inside the running-icon click blob with it (dispatches unchanged). Compute `const op = Actions.routeClick(Settings.clickAction, appItem.isRunning)` at the top of `onSingleTapped`: `op === "minimize"` runs the untouched existing blob; `op === "launch"` sets `busy` and execs when `!busy && !runningOnly && cmdParts.length > 0`, otherwise falls through to focus; `op === "focus"` focuses `toplevels` entry with the lowest `focusHistoryID` then `maybeHideAfterAction()`; `op === "cycle"` picks `Actions.cycleIndex(toplevels.map(t => t.lastIpcObject.focusHistoryID ?? 999), 1)`, focuses it, then `maybeHideAfterAction()`. Non-running path stays the existing launch branch.

- [ ] **Step 2: Add the wheel handler**

Add `property real scrollAcc: 0` on the root. Inside `dockBar` add a `WheelHandler` that accumulates via `Actions.scrollStep(scrollAcc, event.angleDelta.y)`; when `fire` is false just `event.accepted = true`. On fire: `routeScroll(Settings.scrollAction)` → `nothing` no-op; `switch-workspace` dispatches `hl.dsp.focus({ workspace = "e+1" })` for wheel-down and `e-1` for wheel-up; `cycle-windows` collects toplevels on `monitorWsId` sorted by `focusHistoryID`, steps `cycleIndex(ids, up ? -1 : 1)` and focuses. Always `event.accepted = true` so the page behind the dock does not scroll.

- [ ] **Step 3: Add the Settings groups**

After the Transparency group add an "Actions" header with two radio-row groups: "Click" (`minimize` "Minimizar/restaurar", `launch` "Abrir nova janela", `cycle` "Alternar janelas", `focus` "Focar") and "Scroll" (`nothing` "Nada", `cycle-windows` "Alternar janelas", `switch-workspace` "Trocar workspace"), each wired like the Visibility rows.

- [ ] **Step 4: Verify by reload**

Run: `omarchy restart shell`, then grep the newest log:
`LOG=$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog | head -1); strings -n 6 "$LOG" | grep -aiE 'DockPanel|actions|TypeError|ReferenceError|is not defined|unavailable|load failed|Non-existent'`
Expected: no dock errors, a `quickshelldock` openlayer line. Manual: default click still minimizes/restores; `focus` focuses without minimizing; wheel with default `nothing` does nothing; `switch-workspace` moves workspaces per notch.

- [ ] **Step 5: Commit**

```bash
git add DockPanel.qml
git commit -m "feat: wire configurable click and scroll actions"
```
