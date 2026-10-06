# S0: Dock architecture and settings design

## Context

`DockPanel.qml` is 2505 lines. It owns state IO, Hyprland queries, icon
resolution, the app model, every menu and every visual. S1 (behavior and
layout) and S2 (ecosystem integration) both need stable seams to hang new
code on. S0 creates those seams and centralizes settings, without changing
what the dock does.

This is subproject S0 of four. S1 covers dock position, intellihide, delays,
dynamic transparency, indicator styles, click/scroll actions and urgent
handling. S2 covers Unity LauncherEntry, notification counters, DBusMenu
quicklists, mounts and IPC. S3 covers window previews.

## Goals

- Move state IO out of `DockPanel.qml` into a shared `StateStore`.
- Move Hyprland and window queries into a shared `WindowService`.
- Move desktop lookup and icon resolution into a shared `IconResolver`.
- Move the app list build into a per-panel `DockModel`.
- Introduce a `Settings` singleton with a schema, defaults and clamp.
- Add an `Ipc` handler so external tools can drive the dock.
- Give each extracted seam a node-based unit test for its pure logic.

## Non-goals

- No visible behavior change. Same defaults, same interactions.
- No dock position changes, intellihide, dynamic transparency, indicator
  styles, click/scroll actions or urgent handling. Those are S1.
- No DBus integration, mounts or previews. Those are S2 and S3.

## Decisions

### Shared state uses singletons

There is one `DockPanel` per screen (`Variants` in `Dock.qml`). Today each
panel repeats Hyprland, DBus and file connections. Services become QML
singletons in `services/`, declared in `services/qmldir`, so N panels share
one instance. `DockPanel.qml` imports `"services"`.

### The app model stays per panel

`DockModel` is a component, not a singleton, instantiated once per panel. S1
adds per-monitor dock configuration, so the model may diverge per screen. The
model wraps the existing `ListModel` and exposes it as a property so the
`Repeater` and the drag handlers keep working.

### Pure logic lives in plain JS

QML is hard to unit test. The parts that carry rules (settings clamp and
migration, JSON parse, app matching, model merge and order, icon and label
resolution) move to `logic/*.js` as pure functions over plain data. QML
singletons import them with `import "logic/x.js" as X`. Each module ends with
a CommonJS guard so `node --test` can require it:

```js
if (typeof module !== "undefined" && module.exports) module.exports = { ... }
```

`QJSEngine` has no `module`, so the guard is false at runtime and the
functions stay reachable through the QML import namespace.

### Settings schema

`Settings` holds typed properties and delegates parsing to
`SettingsLogic.normalize`. Clamp happens at ingestion, so a bad file can only
saturate, never break layout.

| Field | Type | Range | Default |
|---|---|---|---|
| `iconSize` | int | 32..96 | 40 |
| `spacing` | int | 0..48 | 12 |
| `spacerWidth` | int | 0..96 | 24 |
| `mode` | enum `always` / `autohide` / `smart` | | `always` |
| `magnify` | bool | | true |
| `showMenu` | bool | | true |

Legacy `hideOnEmpty` and `hideOnEmptyWorkspace` migrate to the closest mode.
S1 adds fields to this schema through the same mechanism.

## Module map

- `logic/settings.js`: `DEFAULTS`, `MODES`, `normalize(raw)`.
- `logic/state.js`: `parseJsonArray(raw, maxBytes)`, `parseJsonObject(raw, maxBytes)`.
- `logic/matching.js`: `execTokenize(cmd)`, `binaryName(cmd)`, `matchesApp(app, win)`, `isHiddenApp(app, hidden)`.
- `logic/icons.js`: `hostFromClass(cls)`, `resolveLabel(key, title, map)`, `resolveIcon(key, map)`.
- `logic/model.js`: `mergeApps(configApps, pins, hidden)`, `applyOrder(apps, savedOrder)`, `runningUnpinned(apps, windows)`.
- `services/StateStore.qml` (singleton): reads the four state files, writes
  `order.json` and `settings.json`, emits change signals.
- `services/Settings.qml` (singleton): schema properties, `load`, `save`, `reset`.
- `services/WindowService.qml` (singleton): toplevels and matching
  (`getToplevelsForApp`), `focusWindow`, `execTokenize`. Workspace and monitor
  lookup stay in `DockPanel` until S1.
- `services/IconResolver.qml` (singleton): `desktopNameMap`, disk icon index,
  `entryIconSource`, `candidateLabel`, `candidateIcon`, `desktopEntryForWindow`.
- `services/DockIpc.qml` (singleton): `IpcHandler` with `toggle`, `pin`, `settings`.
- `model/DockModel.qml` (component, per panel): `build(includeRunning)` returns
  the assembled app array. `DockPanel` owns the `ListModel`.
- `test/run.sh`, `test/*.test.js`: node test runner and tests.

## Data flow

`StateStore` reads disk and emits `pinsChanged`, `hiddenChanged`,
`orderChanged`, `settingsChanged`. `Settings` consumes `settingsChanged`.
`DockModel.rebuild` reads `Settings`, `DockApps`, `StateStore` and
`WindowService`, calls `ModelLogic.mergeApps` and `ModelLogic.applyOrder`,
then fills its `ListModel`. `DockPanel` keeps only orchestration and the
visual tree, and reacts to model and settings signals.

## Testing strategy

- Pure logic: `node --test test/` with one test file per logic module. Each
  test is written first and watched to fail before the function exists.
- QML wiring: no unit test available. Verify with `omarchy restart shell` and
  check `log.qslog` for errors, plus manual checks of pin/unpin, reorder,
  modes, settings, icons and badges.
- IPC: verify with `qs ipc call dock toggle`.

Tests are the source of truth for the rules. The QML layer is a thin adapter
over the tested logic.

## Rollout

Incremental, one service per task, each task ends with a reload and a commit.
The dock keeps working after every task.

## Risks

- QML JS import scope and CommonJS guard behavior in `QJSEngine`. Mitigation:
  first task proves the guard across both runtimes with a trivial function.
- Singleton module resolution in a Quickshell plugin (`services/qmldir`).
  Mitigation: model it on the existing `config/qmldir`, verify by reload.
- Behavior drift while moving code. Mitigation: characterization tests pin the
  rules before wiring, and reload checks catch wiring mistakes.

## Open questions

- Should `Theme` become its own seam? Deferred. Color tokens already come from
  `qs.Commons`; only `glassAlpha` is local.
