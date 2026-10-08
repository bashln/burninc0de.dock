# Dock completion goal

Durable objective: finish the dock so no pending tasks remain, always testing,
auditing, running deslop, and adjusting. Work proceeds until every box below is
checked or explicitly cancelled with a recorded decision.

## Pending

- [ ] S2 integration: Unity LauncherEntry (progress/badge/urgent), notification
      counters, DBusMenu quicklists, mounted volumes, IPC expansion.
- [ ] S3 window previews: assess feasibility on Wayland; implement a scoped
      version or cancel with a recorded decision.
- [ ] Audit/deslop pass over the S0/S1 code.

## Done

- [x] S0 architecture and settings.
- [x] S1a..S1f (settings schema, timing, indicator styles, dynamic transparency,
      click/scroll actions, intellihide).
- [x] S1h urgent feedback (with review and fixes).
- [x] S1g bottom/top horizontal edges (verified by screenshot).

## Decisions

- S1g left/right (vertical edges): cancelled as a deliberate scope decision.
  The dock is a horizontal macOS-style bar. A true vertical dock needs the
  container switched to a column, an axis-aware magnifier and drag, and the five
  menus re-anchored through `logic/edge.js` `placeMenu`/`menuSpace` (about 15
  coordinated spots). High regression risk, low value for this setup. `bottom`
  and `top` cover the useful cases. Reopen on request.
