// Urgent-window rules. Pure over plain data so both QML (QJSEngine) and the
// node test suite exercise them.

function addressFromEvent(data) {
  return String(data || "").trim().split(/[,\s]/)[0];
}

function hasUrgent(toplevels, urgentAddrs, addressOf) {
  if (!urgentAddrs) return false;
  for (const item of toplevels || []) {
    // WindowService.getToplevelsForApp returns { toplevel, pid } wrappers.
    const t = item && item.toplevel ? item.toplevel : item;
    const a = addressOf(t);
    if (a && urgentAddrs[a]) return true;
  }
  return false;
}

function shouldReveal(urgentWiggle, urgentCount) {
  return urgentWiggle === true && urgentCount > 0;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { addressFromEvent, hasUrgent, shouldReveal };
}
