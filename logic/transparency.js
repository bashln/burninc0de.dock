// Dynamic transparency: decide the dock's glass alpha from plain rectangle
// geometry. Pure so the node suite and QML share one rule; no QML globals.
// `fixed` always returns today's theme-derived alpha, so the default setting
// is invisible until the user switches to `dynamic`.

const DEFAULT_SLACK = 120;

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}

// Gap between two rects; 0 when they intersect (or touch).
function distance(a, b) {
  const dx = Math.max(0, Math.max(a.x - (b.x + b.w), b.x - (a.x + a.w)));
  const dy = Math.max(0, Math.max(a.y - (b.y + b.h), b.y - (a.y + a.h)));
  return Math.sqrt(dx * dx + dy * dy);
}

// How near (0..1) the nearest window is to the dock rect: 1 = overlapping,
// 0 = at or beyond `slack`. slack <= 0 falls back to DEFAULT_SLACK.
function nearness(windows, dock, slack) {
  const s = slack > 0 ? slack : DEFAULT_SLACK;
  let best = 0;
  for (const w of windows || []) {
    const f = 1 - clamp(distance(w, dock) / s, 0, 1);
    if (f > best) best = f;
  }
  return best;
}

// Alpha for the bar. Only `dynamic` interpolates between minAlpha and
// maxAlpha (bounds ordered either way); every other mode keeps the fixed
// alpha. Nearness is clamped so a bad caller can only saturate.
function alphaFor(mode, near, minAlpha, maxAlpha, fixedAlpha) {
  if (mode !== "dynamic") return fixedAlpha;
  const lo = Math.min(minAlpha, maxAlpha);
  const hi = Math.max(minAlpha, maxAlpha);
  return lo + (hi - lo) * clamp(near, 0, 1);
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DEFAULT_SLACK,
    distance,
    nearness,
    alphaFor,
  };
}
