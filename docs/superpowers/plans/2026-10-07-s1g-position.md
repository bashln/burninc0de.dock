# S1g: Dock position on four edges Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** `position: bottom | top | left | right` (default `bottom`, byte-identical to today) moves the dock to any screen edge: panel window anchors, bar anchoring and slide direction, row orientation (vertical on the side edges), magnifier axis, drag axis, menu/label/window-list placement, `dockBarRect` and the Settings panel scroll cap all follow one edge/axis abstraction.

**Architecture:** `logic/edge.js` holds the pure geometry: `info(position)` → `{position, horizontal, edge}`, `menuSpace(...)` (room on the bar's inner side, feeds the settings scroll cap), `placeMenu(...)` (window coordinates of a menu/card anchored `margin` from the bar on its inner side, clamped along the axis — for `bottom` it evaluates exactly to today's `anchors.bottom: dockBar.top` + `x: clamp(dockBar.x + anchor − w/2, …)`), `barRect(...)` (global bar rect per edge, bottom = today's `dockBarRect`), and `magnifyScale(...)` (the quadratic falloff moved out of `magnifyForIndex`, operating on one axis). `DockPanel.qml` derives `edge` once (`Edge.info(Settings.position)`) and everything else is written against `horizontalDock` / `edgeBottom|Top|Left|Right`:

- PanelWindow: bottom → `bottom+left+right` (today), top → `top+left+right`, left/right → that edge + `top+bottom`; `implicitHeight: horizontalDock ? panelDepth : 0` and `implicitWidth: horizontalDock ? 0 : panelDepth` (compositor stretches the anchored axis).
- dockBar: keeps `horizontalCenter` on horizontal docks; side docks get `verticalCenter` + the edge anchor. All four margins bind to one animated `barMargin` (hidden `gap − dockHeight − 20`, shown `elevationMargin + gap` — same values as today); the existing State/Transition animates `barMargin`.
- `row.orientation: horizontalDock ? Row.Horizontal : Row.Vertical`; item `width/height` swap which one carries `spacerWidth`/`magSize`; separator swaps its thin axis.
- Magnifier: `cursorSceneY` joins `cursorSceneX`; centering span is `root.width`/`root.height`; the falloff comes from `Edge.magnifyScale` (bottom values identical).
- Drag: `xAxis.enabled/yAxis.enabled` pick the axis; pointer/grab/Translate use the row-space along coordinate (`p.x`/`p.y`, `appItem.x`/`appItem.y`).
- Menus and the label (`appLabel`, context, window list, pin, settings) drop the `anchors.bottom` and position through `Edge.placeMenu` (x **and** y), with the along-anchor captured axis-aware (`row/dockBar mapFromItem` on the right coordinate).
- `dockBarRect()` delegates to `Edge.barRect`; the settings `scrollMax` uses `Edge.menuSpace − 54`.

**Tech Stack:** Quickshell QML, node `node:test`, `qmltestrunner`.

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md`

## Global Constraints

- `position: bottom` (default) must render and behave exactly as before: same anchors, same margin values, same clamp formulas, same magnify numbers. Unknown position falls back to `bottom`.
- `logic/edge.js` is pure (plain rects/numbers), CommonJS-guarded, no QML globals; QML injects the live rects.
- Settings control: four rows (Inferior / Superior / Esquerda / Direita) in the Visibility area, `Settings.save()` — like every other group.
- Run `test/run.sh` before committing; verify with `omarchy restart shell` + log grep after each QML pass.

## Review Focus

1. Bottom: before/after screenshots + log identical; animation of show/hide unchanged (barMargin value stream equals old bottomMargin).
2. Top/left/right: bar slides in/out of its edge, exclusive zone reserves on that edge, magnifier tracks the right axis, drag reorders, menus open on the inner side without leaving the window.
3. `placeMenu(bottom, …)` equals today's formula (unit-tested).
4. `dockBarRect` per edge matches window-origin math (unit-tested); intellihide/transparency keep working on bottom.
5. Settings rows persist; switching position live re-anchors everything without QML errors.

---

### Task 1: `logic/edge.js` + tests

**Files:** Create `logic/edge.js`, `test/edge.test.js`; modify `test/qml/tst_logic.qml`.

**Interfaces:** `Edge.POSITIONS`, `Edge.info(position)`, `Edge.menuSpace(position, bar, win)`, `Edge.placeMenu(position, bar, anchor, size, win, margin)`, `Edge.barRect(monitor, position, panelDepth, bar)`, `Edge.magnifyScale(cursor, center, radius, maxScale)`.

- [ ] Write the failing node test (fallback to bottom, axis flags, bottom menu place = old clamp formula, bottom barRect = old dockBarRect formula, per-edge menuSpace, magnify falloff equivalence), run → fail.
- [ ] Implement `logic/edge.js`, run → pass, add QML case to `tst_logic.qml`, run `test/run.sh` → green, commit `feat: add edge geometry rules`.

### Task 2: panel window, bar, strip, row

- [ ] `DockPanel.qml`: import Edge; `edge`/`horizontalDock`/`edge*` properties; PanelWindow anchors + implicit sizes; dockBar anchors + `barMargin` state/transition; triggerStrip axis swap; row orientation + item sizing + separator swap. Bottom path keeps today's values.
- [ ] `test/run.sh`, reload + log clean; screenshot on bottom unchanged. Commit `feat: anchor the dock to the active edge`.

### Task 3: axis-aware behavior

- [ ] magnify (cursor Y, span, `Edge.magnifyScale`), drag (`xAxis/yAxis`, pointer along-axis, Translate), anchor captures (`rowAnchorOf`), menu/label placement via `placeMenu`, `dockBarRect` via `barRect`, settings `scrollMax` via `menuSpace`.
- [ ] `test/run.sh`, reload + log clean. Commit `feat: move magnifier, drag and menus onto the dock axis`.

### Task 4: Settings control, changelog, review

- [ ] Position rows in the Settings panel (Visibility area), `Settings.save()`.
- [ ] Manual pass per edge (open via IPC, move windows, hover magnify, drag reorder, right-click menu, pin menu, settings panel, wheel).
- [ ] CHANGELOG entry, ledger, run suite, commit `feat: add dock position setting`.
