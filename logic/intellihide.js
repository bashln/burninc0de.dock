// Intellihide: decide whether the dock must hide because a window overlaps
// it. Pure over plain rectangles so node and QJSEngine share one rule; no
// QML globals. Disabled (the default) always answers "no", so the feature is
// invisible until the user turns it on.

const MODES = ["all", "focused", "maximized", "always-on-top"];
const DEFAULT_MODE = "focused";

// Strict rectangle intersection. Touching edges do not count: a window that
// merely reaches the bar's border leaves the dock alone.
function overlaps(a, b) {
  if (!a || !b) return false;
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

// True when the dock should hide: `enabled`, a known `mode` (unknown values
// fall back to the schema default), and at least one flag-matching window
// intersecting `dockRect`.
function shouldHide(enabled, mode, windows, dockRect) {
  if (!enabled) return false;
  const m = MODES.indexOf(mode) >= 0 ? mode : DEFAULT_MODE;
  const list = windows || [];
  for (const w of list) {
    if (m === "all") {
      if (overlaps(w, dockRect)) return true;
    } else if (m === "focused") {
      if (w.focused && overlaps(w, dockRect)) return true;
    } else if (m === "maximized") {
      if (w.maximized && overlaps(w, dockRect)) return true;
    } else if (m === "always-on-top") {
      if (w.onTop && overlaps(w, dockRect)) return true;
    }
  }
  return false;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    MODES,
    overlaps,
    shouldHide,
  };
}
