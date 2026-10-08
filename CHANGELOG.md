# Changelog

## Unreleased (branch `local-customizations`)

### S1: behavior and layout

- S1a: settings schema for show/hide delays, animation time, transparency mode
  and alpha, indicator style, click and scroll actions, intellihide, dock
  position and urgent wiggle. Every default preserves the previous behavior.
- S1b: configurable show delay, hide delay and animation time, with sliders in
  the Settings panel.
- S1c: configurable running-indicator styles (dot, dots, dashes, solid,
  count), selectable from a Settings group. `dot` is the default and looks
  exactly as before.
- S1d: dynamic transparency. `transparencyMode: dynamic` eases the bar's
  alpha between `minAlpha` and `maxAlpha` with the distance of the nearest
  window on the active workspace to the dock (`logic/transparency.js`,
  tested); `fixed` (default) keeps today's theme alpha. Settings panel gains
  the mode rows and min/max alpha sliders.
- S1e: configurable click and scroll actions. Left-click on a running icon
  can minimize/restore (default, unchanged), open another window, cycle the
  app's windows or just focus; a wheel notch over the dock can do nothing
  (default), cycle the workspace's windows or switch workspaces. Routing
  lives in `logic/actions.js` (tested); Settings gains the two groups.
- S1f: intellihide. `logic/intellihide.js` decides whether a window overlaps
  the dock bar (modes: all / focused / maximized / always-on-top, tested); the
  flag feeds the existing show/hide paths so an overlap hides the dock while
  hover reveal keeps working. The Settings panel gains the toggle and the four
  mode rows. Default `false` keeps the feature inert.
- S1h: urgent feedback. `logic/urgent.js` (tested) parses the Hyprland urgent
  address and decides the wiggle and the reveal. With `urgentWiggle` on, an
  urgent window wiggles its icon and the dock reveals; focus clears it. Default
  `false` keeps the feature inert.

Remaining S1 phases: S1g dock position on four edges (edge geometry committed in
`logic/edge.js`; the `DockPanel.qml` wiring is still pending).

### Known issues

- None open. (Previously: the Settings panel clipped — the card is now height-bounded and scrolls, mirroring the pin menu's Flickable; fixed by the `fix:` commit below.)

### S0: architecture and settings

- Split `DockPanel.qml` into tested seams: `logic/*.js` (pure rules),
  `services/*.qml` singletons (`StateStore`, `Settings`, `WindowService`,
  `IconResolver`, `DockIpc`), and `model/DockModel.qml` (per-panel builder).
- Added dock IPC: `qs ipc -p /usr/share/omarchy/shell call dock <toggle|settings|pin>`.
- Added a test harness: `test/run.sh` runs node logic tests, QJSEngine tests
  through `qmltestrunner`, and `qmllint`.
- Fixed hidden-but-running config apps not resurfacing through
  running-unpinned.

### Fixes

- Settings panel clipping: the card is height-bounded to the space above the
  dock and its body scrolls (Flickable mirroring the pin menu's), so the top
  rows no longer run off the screen edge and value labels stay inside.
- Hidden config apps that are running now reappear on the dock while open.
- Escaped the dots in the chrome-host icon regex.
