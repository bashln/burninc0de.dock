// Click/scroll routing for the dock: which operation a left click runs and
// which operation a wheel notch runs, plus the window index a "cycle" lands
// on. Pure so the node suite and QML share one rule; no QML globals.

// One wheel notch in angleDelta units (a standard wheel reports +/-120 per
// detent; high-resolution wheels report many small deltas that sum here).
const NOTCH = 120;

// Left click on an icon. A non-running icon always launches, whatever the
// setting; unknown actions fall back to today's minimize/restore toggle.
function routeClick(action, running) {
  if (!running) return "launch";
  if (action === "launch") return "launch";
  if (action === "cycle") return "cycle";
  if (action === "focus") return "focus";
  return "minimize";
}

// Index of the window to focus next, given one focusHistoryID per window
// (0 = currently focused). Steps from the focused window with wrap-around;
// when none of this app's windows is focused, start at the most recent one.
function cycleIndex(focusIds, delta) {
  const n = focusIds.length;
  if (n === 0) return -1;
  if (n === 1) return 0;
  const order = focusIds
    .map((id, i) => ({ id, i }))
    .sort((a, b) => a.id - b.id);
  const focusedPos = order.findIndex(o => o.id === 0);
  if (focusedPos === -1) return order[0].i;
  const step = delta >= 0 ? 1 : -1;
  return order[((focusedPos + step) % n + n) % n].i;
}

// Scroll action enum -> operation; unknown values do nothing.
function routeScroll(action) {
  if (action === "cycle-windows") return "cycle-windows";
  if (action === "switch-workspace") return "switch-workspace";
  return "nothing";
}

// Accumulate wheel deltas into notches: fire once when the accumulated
// magnitude reaches NOTCH, then start over.
function scrollStep(acc, delta) {
  const total = (acc || 0) + (delta || 0);
  if (Math.abs(total) >= NOTCH) return { acc: 0, fire: true };
  return { acc: total, fire: false };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    NOTCH,
    routeClick,
    cycleIndex,
    routeScroll,
    scrollStep,
  };
}
