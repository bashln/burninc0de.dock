# S1a: Settings schema foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add every S1 tunable to `logic/settings.js` and `services/Settings.qml` with defaults that preserve current behavior, so no visible change until a phase wires a field.

**Architecture:** `logic/settings.js` owns the schema (defaults, ranges, enums, `normalize`). `services/Settings.qml` mirrors the fields and saves them. Phases S1b..S1h read the fields; each adds its own panel control.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- Defaults must preserve current behavior: iconSize 54, spacing 12, spacerWidth 24, mode `always`, magnify true, showMenu true, plus the new fields in the spec table with their defaults.
- Clamp at ingestion. Unknown enum value falls back to the default; non-boolean where a bool is expected falls back to the default.
- `logic/settings.js` keeps the CommonJS guard and takes no QML globals.
- Run `test/run.sh` before committing.

## Review Focus

1. An existing `settings.json` without the new keys loads with defaults for them and never errors.
2. A wrong-typed value (`showDelay: "soon"`, `minAlpha: "x"`) saturates to the default, not NaN.
3. Round trip: `save()` writes every field, and re-loading that file yields the same values.
4. `normalize` still validates `mode` and migrates legacy `hideOnEmpty`.

---

### Task 1: Extend the settings schema

**Files:**
- Modify: `logic/settings.js`
- Modify: `test/settings.test.js`
- Modify: `test/qml/tst_logic.qml`

**Interfaces:**
- Produces: `SettingsLogic.DEFAULTS` with all fields; `SettingsLogic.MODES`, `TRANSPARENCY_MODES`, `INDICATOR_STYLES`, `CLICK_ACTIONS`, `SCROLL_ACTIONS`, `INTELLIHIDE_MODES`, `POSITIONS`; `normalize(raw) -> object` with every field.

- [ ] **Step 1: Write the failing tests in `test/settings.test.js`**

```js
test("normalize returns defaults for a new field", () => {
  const n = S.normalize({});
  assert.strictEqual(n.showDelay, 0);
  assert.strictEqual(n.hideDelay, 500);
  assert.strictEqual(n.animationTime, 200);
  assert.strictEqual(n.transparencyMode, "fixed");
  assert.strictEqual(n.minAlpha, 0.35);
  assert.strictEqual(n.maxAlpha, 0.75);
  assert.strictEqual(n.indicatorStyle, "dot");
  assert.strictEqual(n.clickAction, "minimize");
  assert.strictEqual(n.scrollAction, "nothing");
  assert.strictEqual(n.intellihide, false);
  assert.strictEqual(n.intellihideMode, "focused");
  assert.strictEqual(n.position, "bottom");
  assert.strictEqual(n.urgentWiggle, false);
});

test("normalize falls back for an unknown enum", () => {
  assert.strictEqual(S.normalize({ position: "diagonal" }).position, "bottom");
  assert.strictEqual(S.normalize({ indicatorStyle: "sparkle" }).indicatorStyle, "dot");
  assert.strictEqual(S.normalize({ clickAction: "explode" }).clickAction, "minimize");
  assert.strictEqual(S.normalize({ scrollAction: "zoom" }).scrollAction, "nothing");
  assert.strictEqual(S.normalize({ intellihideMode: "sometimes" }).intellihideMode, "focused");
  assert.strictEqual(S.normalize({ transparencyMode: "glow" }).transparencyMode, "fixed");
});

test("normalize keeps a valid enum", () => {
  assert.strictEqual(S.normalize({ position: "left" }).position, "left");
  assert.strictEqual(S.normalize({ indicatorStyle: "count" }).indicatorStyle, "count");
});

test("normalize clamps the delay and alpha ranges", () => {
  assert.strictEqual(S.normalize({ showDelay: -5 }).showDelay, 0);
  assert.strictEqual(S.normalize({ showDelay: 5000 }).showDelay, 1000);
  assert.strictEqual(S.normalize({ hideDelay: 9000 }).hideDelay, 2000);
  assert.strictEqual(S.normalize({ animationTime: 9000 }).animationTime, 1000);
  assert.strictEqual(S.normalize({ minAlpha: 0.05 }).minAlpha, 0.1);
  assert.strictEqual(S.normalize({ maxAlpha: 5 }).maxAlpha, 1.0);
});

test("normalize falls back for a non-numeric delay or alpha", () => {
  assert.strictEqual(S.normalize({ showDelay: "soon" }).showDelay, 0);
  assert.strictEqual(S.normalize({ minAlpha: "x" }).minAlpha, 0.35);
});

test("normalize falls back for a non-boolean flag", () => {
  assert.strictEqual(S.normalize({ intellihide: "yes" }).intellihide, false);
  assert.strictEqual(S.normalize({ urgentWiggle: 1 }).urgentWiggle, false);
});

test("normalize ignores unknown keys", () => {
  const n = S.normalize({ wat: true });
  assert.strictEqual(n.wat, undefined);
});
```

- [ ] **Step 2: Run the tests and watch them fail**

Run: `node --test test/settings.test.js`
Expected: FAIL, new fields are `undefined`.

- [ ] **Step 3: Implement the schema in `logic/settings.js`**

Extend `DEFAULTS` with the new fields. Add enum arrays. Refactor `normalize` to build every field: ints via a clamp helper, floats via a `clampFloat` helper, enums via `pick(raw[k], LIST, default)`, bools via `typeof === "boolean"` fallback. Keep `resolveMode` for `mode`. Keep the CommonJS guard and export the enum arrays too.

- [ ] **Step 4: Run the tests and watch them pass**

Run: `node --test test/settings.test.js`
Expected: all pass.

- [ ] **Step 5: Extend the QJSEngine test**

Add a `test_settings_s1_fields` case to `test/qml/tst_logic.qml` asserting a couple of the new defaults and one clamp.

- [ ] **Step 6: Run the whole suite**

Run: `test/run.sh`
Expected: node, qmltestrunner and qmllint all clean.

- [ ] **Step 7: Commit**

```bash
git add logic/settings.js test/settings.test.js test/qml/tst_logic.qml
git commit -m "feat: add S1 settings fields to the schema"
```

---

### Task 2: Wire the new fields into the Settings singleton

**Files:**
- Modify: `services/Settings.qml`

**Interfaces:**
- Consumes: `SettingsLogic.normalize`, `StateStore.settings`, `StateStore.writeSettings`.
- Produces: `Settings` properties for every new field; `apply` and `save` cover them.

- [ ] **Step 1: Add the properties and save coverage**

Add a property per new field defaulting to `SettingsLogic.DEFAULTS.<field>`. Set them in `apply`. Include them in the object passed to `StateStore.writeSettings`.

- [ ] **Step 2: Verify the round trip**

Run: `omarchy restart shell`. Then, from the running dock, open Settings and toggle something so `save()` runs, and read `~/.local/state/omarchy/burninc0de.dock/settings.json`. Expected: it contains the new keys with the current values; a restart keeps them.

- [ ] **Step 3: Confirm no behavior change**

Expected: the dock looks and behaves exactly as before, since every default matches current behavior.

- [ ] **Step 4: Commit**

```bash
git add services/Settings.qml
git commit -m "refactor: expose the S1 settings fields on Settings"
```
