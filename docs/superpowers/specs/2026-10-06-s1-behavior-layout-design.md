# S1: Dock behavior and layout design

## Context

S0 split `DockPanel.qml` into tested seams: `logic/*.js`, `services/*.qml` (singletons), `model/DockModel.qml`. S1 uses those seams to add the behavior and layout features the reference docks (dash-to-dock, Latte, Noctalia) expose and the dock lacks: configurable timing, indicator styles, dynamic transparency, configurable click/scroll actions, intellihide, dock position on any edge, and urgent feedback.

Every phase preserves current behavior by default: new settings default to what the dock does today, so adding them is invisible until the user changes one.

## Goals

- Extend the settings schema with the new tunables, clamped at ingestion, tested.
- Make show/hide timing and animation duration configurable.
- Add running-indicator styles.
- Add a dynamic transparency mode.
- Make click and scroll actions configurable.
- Add intellihide (hide when a window would overlap the dock).
- Support dock position on the bottom, top, left and right edges.
- Add urgent-app feedback (wiggle) and reveal the dock on urgent.

## Non-goals

- Ecosystem integration (Unity LauncherEntry, notification counters, DBusMenu, mounts): S2.
- Window previews: S3.
- No new runtime dependencies.

## Decisions

### Phases

Each phase is independent and shipped behind its own default. Order is by risk and value:

- **S1a Settings schema**: add every field below to `logic/settings.js` and `Settings`, defaults preserving current behavior. No visible change.
- **S1b Timing**: `showDelay`, `hideDelay`, `animationTime` drive `hideTimer` and the show/hide transition.
- **S1c Indicator styles**: `indicatorStyle` switches the running dot for dots/dashes/solid/count.
- **S1d Dynamic transparency**: `transparencyMode` fixed vs dynamic, with `minAlpha`/`maxAlpha`.
- **S1e Click and scroll actions**: `clickAction`, `scrollAction`.
- **S1f Intellihide**: `intellihide` + `intellihideMode`, hiding when a window overlaps the dock area.
- **S1g Position**: `position` on four edges. Largest change: anchors, `exclusiveZone`, magnifier axis, drag axis, window-list and menu anchoring.
- **S1h Urgent feedback**: `urgentWiggle` and reveal on urgent window.

S1g is the riskiest and touches everything, so it lands after the others.

### Settings schema additions

Ranges and defaults preserve today's behavior.

| Field | Type | Range | Default |
|---|---|---|---|
| `showDelay` | int ms | 0..1000 | 0 |
| `hideDelay` | int ms | 0..2000 | 500 |
| `animationTime` | int ms | 0..1000 | 200 |
| `transparencyMode` | enum | `fixed` / `dynamic` | `fixed` |
| `minAlpha` | number | 0.1..1.0 | 0.35 |
| `maxAlpha` | number | 0.1..1.0 | 0.75 |
| `indicatorStyle` | enum | `dot` / `dots` / `dashes` / `solid` / `count` | `dot` |
| `clickAction` | enum | `minimize` / `launch` / `cycle` / `focus` | `minimize` |
| `scrollAction` | enum | `nothing` / `cycle-windows` / `switch-workspace` | `nothing` |
| `intellihide` | bool | | false |
| `intellihideMode` | enum | `all` / `focused` / `maximized` / `always-on-top` | `focused` |
| `position` | enum | `bottom` / `top` / `left` / `right` | `bottom` |
| `urgentWiggle` | bool | | false |

`normalize` gains enum validation (unknown value falls back to the default) and float clamping for `minAlpha`/`maxAlpha`. Unknown keys in `settings.json` are ignored; missing keys fall back to defaults.

## Module changes

- `logic/settings.js`: new `DEFAULTS`, `RANGES`, enum lists, `normalize` extended.
- `services/Settings.qml`: new properties and `save()` writes them.
- `DockPanel.qml`: per phase, read the new setting.
- Settings panel (`DockPanel.qml`): add controls per phase.

## Testing strategy

- Pure schema rules: node tests in `test/settings.test.js` (enum fallback, float clamp, defaults, no mutation), mirrored in `test/qml/tst_logic.qml` for QJSEngine.
- Behavior phases with pure logic (click/scroll action routing, intellihide decision, edge geometry) get `logic/*.js` modules with tests.
- QML-only wiring (timers, transitions, anchors) verified by `omarchy restart shell` and the dock's manual checks, since it cannot be unit tested.
- `test/run.sh` runs node, qmltestrunner and qmllint before every commit.

## Risks

- Position (S1g) touches magnifier, drag, exclusive zone and menu anchoring. Mitigation: derive a single `position` axis/edge property and centralize the math; test the pure geometry in `logic/`.
- Intellihide (S1f) needs window geometry. Mitigation: compute the overlap decision in `logic/intellihide.js` from plain rectangles, test it, then feed it real geometry from `WindowService`.
- Settings growth: `settings.json` gains keys; old files without them must load to defaults. Covered by the schema tests.
