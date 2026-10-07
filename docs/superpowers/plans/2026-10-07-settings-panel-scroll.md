# Settings panel scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Bound `settingsCard` height and scroll its content, so the Settings panel never grows taller than the space above the dock (top rows no longer run off screen) and right-aligned value labels stay inside the card.

**Architecture:** Mirror the pin menu's approach (`pinCard` ~line 1702): the card's column keeps its header, everything below it moves into a `Flickable` capped at `min(contentHeight, scrollMax)` where `scrollMax` is the space above `dockBar` minus the header/padding overhead. `settingsCard.implicitHeight` then derives from the capped column, so `settingsPanel` (anchored `bottom: dockBar.top`) can never extend past the screen top. A `WheelHandler` mirrors `pinFlick`'s.

**Tech Stack:** Quickshell QML (QML-only wiring — verified by `omarchy restart shell` + log grep + manual open, since it has no pure rule to unit test).

**Spec:** `docs/superpowers/specs/2026-10-06-s1-behavior-layout-design.md` (Known issues entry in CHANGELOG.md)

## Global Constraints

- All existing Settings groups/rows must keep working (toggles, sliders, radio rows, reset) — no reordering, no behavioural change when the content fits (no scrollbar visible, same layout).
- The pin menu's Flickable pattern is the reference: `clip: true`, `contentHeight` bound to the inner column, `Flickable.VerticalFlick`, `boundsBehavior: Flickable.StopAtBounds`, `WheelHandler` clamping `contentY`.
- Do not touch `logic/*.js` (nothing pure here). `qmllint` must stay clean; indentation of the moved rows stays as-is to keep the diff reviewable.
- Run `test/run.sh` before committing.

## Review Focus

1. Card height: with the panel open, the card's top edge is on screen (never negative `y`); when content fits, height is unchanged from before.
2. Scroll: wheel over the panel scrolls the content and stops at bounds; the header ("Dock settings") stays visible above the scroll area.
3. All rows still act: a slider drag, a radio row tap, the intellihide toggle, Reset to defaults.
4. No binding loop / no anchor loop (`settingsColumn` stays `centerIn`; `Flickable` height must not depend on `settingsCard.height`).

---

### Task 1: Wrap the settings body in a capped Flickable

**Files:**
- Modify: `DockPanel.qml`

**Interfaces:**
- Consumes: `dockBar.y` (space above the bar), existing `settingsColumn` / `settingsCard`.

- [ ] **Step 1:** Add `readonly property int scrollMax: Math.max(140, dockBar.y - 54)` to `settingsCard` (`-2` panel margin, `-24` card padding, `-16` header, `-10` spacing ≈ 54 overhead; floor 140 keeps a short panel usable if the bar is low).

- [ ] **Step 2:** After the header `Text`, open `Flickable { id: settingsFlick; width: settingsColumn.width; height: Math.min(settingsBody.implicitHeight, settingsCard.scrollMax); clip: true; contentHeight: settingsBody.implicitHeight; flickableDirection: Flickable.VerticalFlick; boundsBehavior: Flickable.StopAtBounds }` with the pin menu's `WheelHandler`, and inside it `Column { id: settingsBody; width: settingsFlick.width; spacing: 10 }`.

- [ ] **Step 3:** Close the new `Column`/`Flickable` before `settingsColumn`'s closing brace (the rows in between move in unchanged).

- [ ] **Step 4:** Verify: `./test/run.sh` (qmllint clean), `omarchy restart shell`, grep the newest log for dock errors + `openlayer>>quickshelldock`. Then open Settings (`qs ipc -p /usr/share/omarchy/shell call dock settings`): card top on screen, wheel scrolls, rows act, header visible.

- [ ] **Step 5:** Update CHANGELOG (drop the Known issues entry) and commit:

```bash
git add DockPanel.qml CHANGELOG.md
git commit -m "fix: bound and scroll the settings panel"
```
