# S0: Dock architecture and settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the dock's state IO, window queries, icon resolution and app model into tested seams, and centralize settings, without changing visible behavior.

**Architecture:** Pure rules move to `logic/*.js` as functions over plain data, tested with `node --test`. QML singletons in `services/` adapt those rules to the runtime and are shared across the per-screen panels. The app list becomes a per-panel `DockModel` component. `DockPanel.qml` keeps orchestration and the visual tree only.

**Tech Stack:** Quickshell 0.3.1 (QML, `QJSEngine`), Qt Quick Controls, Hyprland IPC, node 26 (`node:test` / `node:assert`).

**Spec:** `docs/superpowers/specs/2026-10-06-s0-dock-architecture-settings-design.md`

## Global Constraints

- No new runtime dependencies. Tests run with `node --test` only.
- Preserve the state-file byte ceiling: reads go through `head -c <maxStateBytes> -- <path>`; truncated or invalid JSON degrades to an empty value.
- Do not load whole state files through `FileView`. `FileView` stays watcher-only (`preload: false`, `watchChanges`).
- Every `logic/*.js` module ends with `if (typeof module !== "undefined" && module.exports) module.exports = { ... }`.
- `logic/*.js` must not reference QML globals (`root`, `Quickshell`, `Hyprland`, `Color`). It takes plain arguments and returns plain data.
- QML singletons are declared in `services/qmldir`, modeled on `config/qmldir`.
- Behavior must not change. Defaults stay: iconSize 40, spacing 12, spacerWidth 24, mode `always`, magnify true, showMenu true.
- Verify each task with `omarchy restart shell` and a clean `log.qslog` before committing.
- Run `test/run.sh` before every commit. It runs the node logic tests, the QJSEngine logic tests through `qmltestrunner`, and `qmllint`.
- `test/run.sh` resolves `qs.Commons` for `qmllint` by creating a temp import dir with a `qs/Commons` symlink to `/usr/share/omarchy/shell/Commons`, then passes `-I` that dir plus `/usr/lib/qt6/qml`.
- `qmllint` gates on errors, not warnings. The unresolved Quickshell types and `PanelWindow` uncreatable warnings are known noise. Fail the gate on any `Error:` line.
- The `qmltestrunner` suite is the cross-runtime proof: it loads each `logic/*.js` under `QJSEngine`, so the CommonJS guard must stay silent there. Later tasks extend `test/qml/tst_logic.qml`.

## Review Focus

1. `settings.json` holds out-of-range or wrong-typed values: the dock clamps and never crashes or mis-sizes.
2. State files are missing, empty or truncated: the dock falls back to defaults and keeps rendering.
3. A hidden config app that is running still resurfaces through running-unpinned after the extraction.
4. Two panels (two monitors) exist: shared services do not duplicate connections, and each panel has its own model.
5. A `logic/*.js` module imported by QML must not throw on the CommonJS guard under `QJSEngine` (`module` is undefined there).

---

### Task 1: State logic and StateStore

**Files:**
- Create: `logic/state.js`
- Create: `test/state.test.js`
- Create: `test/run.sh`
- Create: `test/qml/tst_logic.qml`
- Create: `services/StateStore.qml`
- Create: `services/qmldir`
- Modify: `DockPanel.qml` (remove `readStateFile`, `consumeStateFile`, `parseJsonArray`, `parseJsonObject`, the pending queue, the state `Process`, the watcher `FileView`s for pins/hidden, and the order/settings writers; delegate to `StateStore`)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `StateLogic.parseJsonArray(raw: string, maxBytes: int) -> array`
  - `StateLogic.parseJsonObject(raw: string, maxBytes: int) -> object`
  - `StateStore` singleton: `signal orderChanged()`, `pinsChanged()`, `hiddenChanged()`, `settingsChanged(var data)`; `readonly property var order`, `pins`, `hidden`, `settings`; `function writeOrder(names)`, `function writeSettings(obj)`.

- [ ] **Step 1: Write the failing test `test/state.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const S = require("../logic/state.js");

test("parseJsonArray returns the array for valid JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray('["a","b"]', 4096), ["a", "b"]);
});

test("parseJsonArray returns [] for invalid JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray("not json", 4096), []);
});

test("parseJsonArray returns [] for non-array JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray('{"a":1}', 4096), []);
});

test("parseJsonObject returns the object for valid JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject('{"a":1}', 4096), { a: 1 });
});

test("parseJsonObject returns {} for array JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject("[1,2]", 4096), {});
});

test("parseJsonObject returns {} for invalid JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject("", 4096), {});
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/state.test.js`
Expected: FAIL, module `../logic/state.js` not found.

- [ ] **Step 3: Implement `logic/state.js`**

Two functions. `parseJsonArray` parses, checks `Array.isArray`, returns `[]` otherwise. `parseJsonObject` parses, checks non-null non-array object, returns `{}` otherwise. Both ignore `maxBytes` for parsing, which exists only so the caller passes it and the signature documents the ceiling. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/state.test.js`
Expected: 6 passing.

- [ ] **Step 5: Add the QML-side test `test/qml/tst_logic.qml`**

This proves the modules load and run under `QJSEngine`, which is the runtime risk the node suite cannot catch. Later tasks append the other modules here.

```qml
import QtTest
import "../../logic/state.js" as StateLogic

TestCase {
  name: "LogicQJSEngine"

  function test_state_array() {
    compare(StateLogic.parseJsonArray('["a","b"]', 4096).length, 2);
    compare(StateLogic.parseJsonArray("bad", 4096).length, 0);
  }

  function test_state_object() {
    compare(StateLogic.parseJsonObject('{"a":1}', 4096).a, 1);
    compare(JSON.stringify(StateLogic.parseJsonObject("[1]", 4096)), "{}");
  }
}
```

- [ ] **Step 6: Add `test/run.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
IMPORTS=$(mktemp -d)
trap 'rm -rf "$IMPORTS"' EXIT
mkdir -p "$IMPORTS/qs"
ln -sfn /usr/share/omarchy/shell/Commons "$IMPORTS/qs/Commons"

echo "== node logic tests =="
node --test "$ROOT/test/"

echo "== QJSEngine logic tests =="
QT_QPA_PLATFORM=offscreen qmltestrunner -input "$ROOT/test/qml"

echo "== qmllint =="
qmllint -I "$IMPORTS" -I /usr/lib/qt6/qml \
  "$ROOT"/Dock.qml "$ROOT"/DockPanel.qml \
  "$ROOT"/config/*.qml "$ROOT"/services/*.qml "$ROOT"/model/*.qml \
  > /tmp/qmllint.out 2>&1 || true
if grep -q 'Error:' /tmp/qmllint.out; then
  echo "qmllint reported errors:"; grep 'Error:' /tmp/qmllint.out; exit 1
fi
echo "qmllint: no errors"
```

`chmod +x test/run.sh`.

- [ ] **Step 7: Implement `services/StateStore.qml` and `services/qmldir`**

Move the read machinery from `DockPanel.qml` verbatim: one shared `Process` running `head -c <maxStateBytes> -- <path>`, a FIFO `pendingQueue`, the pins/hidden watcher `FileView`s, and the order/settings writer `FileView`s. Emit `orderChanged`/`pinsChanged`/`hiddenChanged`/`settingsChanged(data)` from `onExited` and from the watcher `onFileChanged`. Property names and defaults must match the current `DockPanel` fields (`savedOrder`, `pinnedApps`, `hiddenApps`).

`services/qmldir`:
```
singleton StateStore 1.0 StateStore.qml
```

- [ ] **Step 8: Wire `DockPanel.qml` to `StateStore`**

Add `import "services"`. Replace every `savedOrder` / `pinnedApps` / `hiddenApps` read with `StateStore.order` / `StateStore.pins` / `StateStore.hidden`. Replace `orderFile.setText(...)` and `settingsFile.setText(...)` with `StateStore.writeOrder(...)` / `StateStore.writeSettings(...)`. Connect to the change signals to trigger `rebuildModel`. Delete the moved code.

- [ ] **Step 9: Verify by reload**

Run: `omarchy restart shell`
Then: `grep -aiE "DockPanel|StateStore|is not defined|TypeError" /run/user/1000/quickshell/by-id/*/log.qslog | tail`
Expected: no QML errors; dock renders. Manually confirm pin, unpin and reorder still work.

- [ ] **Step 10: Commit**

```bash
git add logic/state.js test/state.test.js test/run.sh test/qml/tst_logic.qml services/StateStore.qml services/qmldir DockPanel.qml
git commit -m "refactor: extract state IO into StateStore"
```

---

### Task 2: Settings logic and Settings singleton

**Files:**
- Create: `logic/settings.js`
- Create: `test/settings.test.js`
- Create: `services/Settings.qml`
- Modify: `services/qmldir`, `DockPanel.qml`

**Interfaces:**
- Consumes: `StateStore.settings`, `StateStore.writeSettings(obj)`, `StateStore.settingsChanged`.
- Produces:
  - `SettingsLogic.DEFAULTS`, `SettingsLogic.MODES`
  - `SettingsLogic.normalize(raw) -> { iconSize, spacing, spacerWidth, mode, magnify, showMenu }`
  - `Settings` singleton: `property int iconSize`, `spacing`, `spacerWidth`; `property string mode`; `property bool magnify`, `showMenu`; `function save()`, `function reset()`.

- [ ] **Step 1: Write the failing test `test/settings.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const S = require("../logic/settings.js");

test("normalize returns defaults for an empty object", () => {
  assert.deepStrictEqual(S.normalize({}), S.DEFAULTS);
});

test("normalize clamps iconSize above the maximum", () => {
  assert.strictEqual(S.normalize({ iconSize: 1000 }).iconSize, 96);
});

test("normalize clamps iconSize below the minimum", () => {
  assert.strictEqual(S.normalize({ iconSize: 4 }).iconSize, 32);
});

test("normalize clamps spacing to zero", () => {
  assert.strictEqual(S.normalize({ spacing: -5 }).spacing, 0);
});

test("normalize rejects an unknown mode", () => {
  assert.strictEqual(S.normalize({ mode: "weird" }).mode, "always");
});

test("normalize migrates hideOnEmpty true to autohide", () => {
  assert.strictEqual(S.normalize({ hideOnEmpty: true }).mode, "autohide");
});

test("normalize migrates hideOnEmpty false to smart", () => {
  assert.strictEqual(S.normalize({ hideOnEmpty: false }).mode, "smart");
});

test("normalize keeps mode over legacy hideOnEmpty", () => {
  assert.strictEqual(S.normalize({ mode: "autohide", hideOnEmpty: false }).mode, "autohide");
});

test("normalize ignores a non-boolean magnify", () => {
  assert.strictEqual(S.normalize({ magnify: "yes" }).magnify, true);
});

test("normalize does not mutate its input", () => {
  const raw = { iconSize: 1000 };
  S.normalize(raw);
  assert.strictEqual(raw.iconSize, 1000);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/settings.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/settings.js`**

`DEFAULTS = { iconSize: 40, spacing: 12, spacerWidth: 24, mode: "always", magnify: true, showMenu: true }`. `MODES = ["always", "autohide", "smart"]`. `normalize(raw)` builds a fresh object, rounds and clamps each int to its range, validates `mode` against `MODES`, then falls back through legacy `hideOnEmpty` then `hideOnEmptyWorkspace` mapping `true -> "autohide"`, `false -> "smart"`. Booleans only accept `typeof === "boolean"`. End with the CommonJS guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/settings.test.js`
Expected: 10 passing.

Then append `SettingsLogic` to `test/qml/tst_logic.qml` and run `test/run.sh`.

- [ ] **Step 5: Implement `services/Settings.qml`**

Declare the six typed properties with the `DEFAULTS` values. `Component.onCompleted` applies `StateStore.settings` through `SettingsLogic.normalize`. A `Connections` on `StateStore.settingsChanged` applies new data. `save()` calls `StateStore.writeSettings({ ...six fields... })`. `reset()` writes `DEFAULTS`. Add `singleton Settings 1.0 Settings.qml` to `services/qmldir`.

- [ ] **Step 6: Wire `DockPanel.qml`**

Replace `property int itemSize: defaultItemSize` and the other setting properties with reads of `Settings.iconSize` etc. Point the Settings panel sliders and toggles at the `Settings` singleton and call `Settings.save()`. Keep `defaultItemSize`/`defaultItemSpacing` only if still referenced elsewhere; otherwise remove.

- [ ] **Step 7: Verify by reload**

Run: `omarchy restart shell`
Expected: no QML errors; Settings panel still changes size, spacing, spacer width, mode, magnify and menu, and the values persist across a restart.

- [ ] **Step 8: Commit**

```bash
git add logic/settings.js test/settings.test.js services/Settings.qml services/qmldir DockPanel.qml
git commit -m "refactor: extract settings schema into Settings"
```

---

### Task 3: Matching logic and WindowService

**Files:**
- Create: `logic/matching.js`
- Create: `test/matching.test.js`
- Create: `services/WindowService.qml`
- Modify: `services/qmldir`, `DockPanel.qml`

**Interfaces:**
- Consumes: `Hyprland.toplevels`.
- Produces:
  - `Matching.execTokenize(cmd) -> string[]`
  - `Matching.binaryName(cmd) -> string`
  - `Matching.matchesApp(app, win) -> bool`, `app` has `{ matchTitle, appId, cmd, spacer }`, `win` has `{ title, appId, class }`
  - `Matching.isHiddenApp(app, hidden) -> bool`
  - `WindowService.getToplevelsForApp(app)`, `monitorFor(screen)`, `workspaceEmptyFor(screen)`, `focusWindow(address)`, `execTokenize(cmd)`.

- [ ] **Step 1: Write the failing test `test/matching.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const M = require("../logic/matching.js");

test("binaryName takes the first token basename", () => {
  assert.strictEqual(M.binaryName("foot --app-id=foot-nvim -e nvim"), "foot");
});

test("binaryName strips the directory and extension", () => {
  assert.strictEqual(M.binaryName("/usr/lib/firefox/firefox"), "firefox");
});

test("matchesApp matches a title substring by matchTitle", () => {
  assert.strictEqual(M.matchesApp({ matchTitle: "Gmail" }, { title: "Inbox - Gmail" }), true);
});

test("matchesApp matches an exact appId", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot" }, { appId: "foot" }), true);
});

test("matchesApp does not match a prefix-similar appId", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot-nvim" }, { appId: "foot" }), false);
});

test("matchesApp falls back to the class when appId is empty", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot" }, { appId: "", class: "foot" }), true);
});

test("matchesApp matches the cmd binary against appId", () => {
  assert.strictEqual(M.matchesApp({ cmd: "nautilus" }, { appId: "org.gnome.Nautilus" }), true);
});

test("matchesApp never matches a spacer", () => {
  assert.strictEqual(M.matchesApp({ spacer: true, cmd: "x" }, { appId: "x" }), false);
});

test("isHiddenApp matches by name", () => {
  assert.strictEqual(M.isHiddenApp({ name: "Terminal", entryId: "" }, ["Terminal"]), true);
});

test("isHiddenApp matches by entryId", () => {
  assert.strictEqual(M.isHiddenApp({ name: "X", entryId: "org.x" }, ["org.x"]), true);
});

test("isHiddenApp returns false when neither matches", () => {
  assert.strictEqual(M.isHiddenApp({ name: "Y", entryId: "org.y" }, ["Z"]), false);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/matching.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/matching.js`**

Port the current `getToplevelsForApp` branch logic into `matchesApp(app, win)`: `spacer` returns false; `matchTitle` does a case-insensitive `includes` on `win.title`; `appId` does an `includes` against lowercased `win.appId` or `win.class`; otherwise `cmd` tokenizes, takes `binaryName`, and does the same includes plus the reverse `class in binary` case. `isHiddenApp` checks `hidden.indexOf(app.name) >= 0` then `app.entryId !== "" && hidden.indexOf(app.entryId) >= 0`. End with the guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/matching.test.js`
Expected: 11 passing.

Then append `Matching` to `test/qml/tst_logic.qml` and run `test/run.sh`.

- [ ] **Step 5: Implement `services/WindowService.qml`**

Hold `getToplevelsForApp(app)` (iterate `Hyprland.toplevels.values`, call `Matching.matchesApp`), `monitorFor(screen)` (the current `hlMonitor` lookup), `workspaceEmptyFor(screen)` (move `checkWorkspaceEmpty`/`updateWorkspaceEmpty` and the `clientsJson` Process here), `focusWindow(address)` and `execTokenize`. Add `singleton WindowService 1.0 WindowService.qml` to `services/qmldir`.

- [ ] **Step 6: Wire `DockPanel.qml`**

Replace `getToplevelsForApp`, `focusWindow`, `execTokenize`, `monitorWsId` and the workspace-empty functions with calls into `WindowService`. Keep behavior identical.

- [ ] **Step 7: Verify by reload**

Run: `omarchy restart shell`
Expected: no QML errors; launch, focus, minimize and the smart mode still behave as before.

- [ ] **Step 8: Commit**

```bash
git add logic/matching.js test/matching.test.js services/WindowService.qml services/qmldir DockPanel.qml
git commit -m "refactor: extract window matching into WindowService"
```

---

### Task 4: Icon logic and IconResolver

**Files:**
- Create: `logic/icons.js`
- Create: `test/icons.test.js`
- Create: `services/IconResolver.qml`
- Modify: `services/qmldir`, `DockPanel.qml`

**Interfaces:**
- Consumes: `DesktopEntries`, the dump-map Process, the disk icon scan Process.
- Produces:
  - `Icons.hostFromClass(cls) -> string` (empty when no match)
  - `Icons.resolveLabel(key, title, map) -> string`
  - `Icons.resolveIcon(key, map) -> string` (empty when unknown)
  - `IconResolver.entryIconSource(icon)`, `candidateLabel(key, title)`, `candidateIcon(key, cls, appId)`, `desktopEntryForWindow(cls, aid)`, `desktopNameMap`.

- [ ] **Step 1: Write the failing test `test/icons.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/icons.js");

test("hostFromClass extracts the host from a chrome synthetic class", () => {
  assert.strictEqual(I.hostFromClass("chrome-web.whatsapp.com__-Default"), "web.whatsapp.com");
});

test("hostFromClass returns empty for a plain class", () => {
  assert.strictEqual(I.hostFromClass("foot"), "");
});

test("resolveLabel prefers the desktop name", () => {
  assert.strictEqual(I.resolveLabel("foo", "A Title", { foo: { name: "Foo" } }), "Foo");
});

test("resolveLabel falls back to the window title", () => {
  assert.strictEqual(I.resolveLabel("unknown", "A Title", {}), "A Title");
});

test("resolveLabel falls back to the key when there is no title", () => {
  assert.strictEqual(I.resolveLabel("unknown", "", {}), "unknown");
});

test("resolveIcon returns the mapped icon", () => {
  assert.strictEqual(I.resolveIcon("foo", { foo: { icon: "bar" } }), "bar");
});

test("resolveIcon returns empty when unmapped", () => {
  assert.strictEqual(I.resolveIcon("foo", {}), "");
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/icons.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/icons.js`**

`hostFromClass` applies the escaped regex `/-([a-z0-9.-]+\.[a-z]+)__/` on the lowercased input and returns group 1 or `""`. `resolveLabel` mirrors the current `candidateLabel`: direct map hit by lowercase key, else no chrome substring special case (that lives in `candidateIcon`), else title when shorter than 60 chars, else the key. `resolveIcon` mirrors the current `candidateIcon` map lookup. End with the guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/icons.test.js`
Expected: 7 passing.

Then append `Icons` to `test/qml/tst_logic.qml` and run `test/run.sh`.

- [ ] **Step 5: Implement `services/IconResolver.qml`**

Move `desktopNameMap`, `iconDiskIndex`, `pendingIconDiskIndex`, the dump-map Process, the icon index scan Process, `entryIconSource`, `candidateLabel`, `candidateIcon`, `desktopEntryForWindow` and `pinCandidateIcon`. Use `Icons` for the pure parts. Add `singleton IconResolver 1.0 IconResolver.qml` to `services/qmldir`.

- [ ] **Step 6: Wire `DockPanel.qml`**

Replace the moved functions and properties with `IconResolver` calls.

- [ ] **Step 7: Verify by reload**

Run: `omarchy restart shell`
Expected: no QML errors; icons and labels in the dock, pin menu and window list render as before.

- [ ] **Step 8: Commit**

```bash
git add logic/icons.js test/icons.test.js services/IconResolver.qml services/qmldir DockPanel.qml
git commit -m "refactor: extract icon resolution into IconResolver"
```

---

### Task 5: Model logic and DockModel

**Files:**
- Create: `logic/model.js`
- Create: `test/model.test.js`
- Create: `model/DockModel.qml`
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `Settings`, `StateStore`, `WindowService`, `IconResolver`, `DockApps`.
- Produces:
  - `Model.mergeApps(configApps, pins, hidden) -> array`
  - `Model.applyOrder(apps, savedOrder) -> array`
  - `Model.runningUnpinned(apps, windows) -> array`, `windows` are `{ key, cls, appId, title, label, icon }`
  - `DockModel` component: `property alias apps` (ListModel), `function rebuild()`, `function persistOrder()`.

- [ ] **Step 1: Write the failing test `test/model.test.js`**

```js
const test = require("node:test");
const assert = require("node:assert");
const M = require("../logic/model.js");

test("mergeApps drops a hidden app by name", () => {
  const out = M.mergeApps([{ name: "Terminal" }], [], ["Terminal"]);
  assert.deepStrictEqual(out, []);
});

test("mergeApps drops a hidden app by entryId", () => {
  const out = M.mergeApps([{ name: "X", entryId: "org.x" }], [], ["org.x"]);
  assert.deepStrictEqual(out, []);
});

test("mergeApps appends a pin that does not duplicate", () => {
  const out = M.mergeApps([{ name: "Files" }], [{ name: "Firefox" }], []);
  assert.deepStrictEqual(out.map((a) => a.name), ["Files", "Firefox"]);
});

test("mergeApps does not append a pin already declared by name", () => {
  const out = M.mergeApps([{ name: "Files" }], [{ name: "Files" }], []);
  assert.strictEqual(out.length, 1);
});

test("applyOrder sorts by saved names then appends the rest", () => {
  const apps = [{ name: "A" }, { name: "B" }, { name: "C" }];
  const out = M.applyOrder(apps, ["C", "A"]);
  assert.deepStrictEqual(out.map((a) => a.name), ["C", "A", "B"]);
});

test("runningUnpinned excludes a window an app matches", () => {
  const apps = [{ name: "Terminal", appId: "foot" }];
  const out = M.runningUnpinned(apps, [{ key: "foot", cls: "foot", appId: "foot", title: "", label: "Foot", icon: "foot" }]);
  assert.deepStrictEqual(out, []);
});

test("runningUnpinned returns an unmatched window as runningOnly", () => {
  const out = M.runningUnpinned([], [{ key: "x", cls: "x", appId: "x", title: "", label: "X", icon: "x" }]);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].runningOnly, true);
});

test("runningUnpinned dedups windows sharing a key", () => {
  const w = [{ key: "x", cls: "x", appId: "x", title: "", label: "X", icon: "x" }];
  assert.strictEqual(M.runningUnpinned([], [...w, ...w]).length, 1);
});
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `node --test test/model.test.js`
Expected: FAIL, module not found.

- [ ] **Step 3: Implement `logic/model.js`**

`mergeApps` filters hidden via `isHiddenApp`, then appends pins not matching an existing name or cmd. `applyOrder` maps saved order first (deleting used names) then appends the rest. `runningUnpinned` builds a `used` name set, skips windows matched by any app through `matchesApp`, dedups by `key`, and returns entries `{ entryId: "", pinned: false, runningOnly: true, name: label, icon, cmd: "", matchTitle: "", appId: appId || cls, minimizable: true, spacer: false }`. End with the guard.

- [ ] **Step 4: Run the test and watch it pass**

Run: `node --test test/model.test.js`
Expected: 8 passing.

Then append `Model` to `test/qml/tst_logic.qml` and run `test/run.sh`.

- [ ] **Step 5: Implement `model/DockModel.qml`**

Wrap a `ListModel` exposed as `property alias apps: appModel`. `rebuild()` builds the config list from `DockApps.apps`, calls `Model.mergeApps`, calls `IconResolver` and `WindowService` to build the `windows` array, calls `Model.runningUnpinned`, then `Model.applyOrder`, then repopulates the ListModel. `persistOrder()` skips `runningOnly` entries and calls `StateStore.writeOrder`.

- [ ] **Step 6: Wire `DockPanel.qml`**

Instantiate `DockModel { id: dockModel }` per panel. Point the `Repeater` `model` at `dockModel.apps` and the drag `move()` at `dockModel.apps.move(...)`. Replace `rebuildModel`, `persistOrder`, `appModel` and the running-unpinned block with `dockModel` calls.

- [ ] **Step 7: Verify by reload**

Run: `omarchy restart shell`
Expected: no QML errors; reorder, running-unpinned, hidden apps and ordering persist as before.

- [ ] **Step 8: Commit**

```bash
git add logic/model.js test/model.test.js model/DockModel.qml DockPanel.qml
git commit -m "refactor: extract app list into DockModel"
```

---

### Task 6: IPC, module registration and docs

**Files:**
- Create: `services/DockIpc.qml`
- Modify: `services/qmldir`, `DockPanel.qml`, `AGENTS.md`

**Interfaces:**
- Consumes: `Settings`, `StateStore`, the pin tool path.
- Produces: `DockIpc` singleton with `IpcHandler` target `dock` and functions `toggle()`, `pin(name)`, `settings()`.

- [ ] **Step 1: Implement `services/DockIpc.qml`**

```qml
import Quickshell.Io
import "./" as Services
pragma Singleton

QtObject {
  id: root
  IpcHandler {
    target: "dock"
    function toggle() { /* flip dockVisible through a shared signal */ }
    function pin(name: string) { Quickshell.execDetached([pinTool, "--pin-window", name]) }
    function settings() { /* open the settings panel */ }
  }
}
```

Add `singleton DockIpc 1.0 DockIpc.qml` to `services/qmldir`. Because `IpcHandler` needs `Quickshell` or `Quickshell.Io`, confirm the exact import in `DockPanel.qml` (`import Quickshell.Io`).

- [ ] **Step 2: Verify IPC**

Run: `omarchy restart shell`, then `qs ipc call dock settings`
Expected: command returns without error and the settings panel opens (or a stub logs). Record the working call form in `AGENTS.md`.

- [ ] **Step 3: Update `AGENTS.md`**

Document the new layout (`logic/`, `services/`, `model/`), the singleton registrations in `services/qmldir`, the test command `test/run.sh`, and the `qs ipc call dock` surface.

- [ ] **Step 4: Commit**

```bash
git add services/DockIpc.qml services/qmldir DockPanel.qml AGENTS.md
git commit -m "feat: add dock IPC and document the new layout"
```

---

### Task 7: Full verification and code review

- [ ] **Step 1: Run the full test suite**

Run: `test/run.sh`
Expected: all tests pass.

- [ ] **Step 2: Reload and inspect the log**

Run: `omarchy restart shell`
Then: `grep -aiE "DockPanel|StateStore|Settings|WindowService|IconResolver|DockModel|TypeError|is not defined" /run/user/1000/quickshell/by-id/*/log.qslog | tail`
Expected: no errors.

- [ ] **Step 3: Manual behavior check**

Confirm: launch, focus, minimize, pin, unpin, reorder, hidden app resurfaces while running, all three modes, settings persistence across restart, icons and badges.

- [ ] **Step 4: Request code review**

Dispatch a fresh reviewer over the S0 range with the plan and spec as requirements, covering the Review Focus list.

```bash
BASE_SHA=$(git rev-parse HEAD~6)
HEAD_SHA=$(git rev-parse HEAD)
```

- [ ] **Step 5: Address findings and commit**
