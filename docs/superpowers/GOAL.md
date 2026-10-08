# Dock completion goal

Durable objective: finish the dock so no pending tasks remain, always testing,
auditing, running deslop, and adjusting. Work proceeds until every box below is
checked or explicitly cancelled with a recorded decision.

## Pending

- [ ] S2 integration, split after a feasibility check:
      - S2a notification counters: feasible via `Quickshell.Services.Notifications`.
      - S2b DBusMenu quicklists: feasible via the `Quickshell.DBusMenu` module.
      - S2c Unity LauncherEntry (progress/badge/urgent): NOT feasible directly.
        Quickshell 0.3.1 exposes no generic DBus client in its core; it needs an
        external helper process (dbus-monitor/daemon) to bridge the signals.
      - S2d mounted volumes: needs a UDisks2 bridge (same generic-DBus gap).
      - S2e IPC expansion: feasible, additive to the existing `dock` target.
- [ ] S3 window previews: Wayland toplevel capture; needs a feasibility decision.
- [ ] Settings-panel component extraction (`SettingRow`/`SettingSlider`): the six
      radio rows and five sliders repeat ~500 lines in DockPanel.qml.

## Done

- [x] S0 architecture and settings.
- [x] S1a..S1f (settings schema, timing, indicator styles, dynamic transparency,
      click/scroll actions, intellihide).
- [x] S1h urgent feedback (with review and fixes).
- [x] S1g bottom/top horizontal edges (verified by screenshot, menus included).
- [x] S1 audit + deslop pass (Critical menu/geometry fix, edge.js wired,
      AGENTS.md refreshed).

## Decisions

- S1g left/right (vertical edges): cancelled as a deliberate scope decision.
  The dock is a horizontal macOS-style bar. A true vertical dock needs the
  container switched to a column, an axis-aware magnifier and drag, and the five
  menus re-anchored through `logic/edge.js` `placeMenu`/`menuSpace` (about 15
  coordinated spots). High regression risk, low value for this setup. `bottom`
  and `top` cover the useful cases. Reopen on request.
- S2c/S2d need an external DBus bridge because Quickshell 0.3.1 has no generic
  DBus client. Decide the bridge approach (a small helper binary/script) before
  implementing; S2a/S2b/S2e can proceed without it.
