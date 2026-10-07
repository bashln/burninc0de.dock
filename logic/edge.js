// Dock-edge geometry (S1g): every rule that depends on `position` lives
// here, pure over plain rectangles and numbers so node and QJSEngine share
// one implementation. `bottom` is the default and must reproduce the old
// inline formulas exactly; the other edges are mirrors of it.

const POSITIONS = ["bottom", "top", "left", "right"];
const DEFAULT_POSITION = "bottom";

// { position, edge, horizontal } for a known edge; unknown → bottom.
function info(position) {
  const edge = POSITIONS.indexOf(position) >= 0 ? position : DEFAULT_POSITION;
  return {
    position: edge,
    edge: edge,
    horizontal: edge === "bottom" || edge === "top",
  };
}

// Room on the bar's inner side, i.e. the space a menu/label needs without
// leaving the panel window: distance from the bar's inner edge to the
// window's inner boundary. bottom → space above the bar (bar.y).
function menuSpace(position, bar, win) {
  const e = info(position).edge;
  if (e === "bottom") return bar.y;
  if (e === "top") return win.h - (bar.y + bar.h);
  if (e === "left") return bar.x;
  return win.w - (bar.x + bar.w);
}

// Clamp an along-axis centre so the card stays inside the window —
// today's Math.max(0, Math.min(anchor - size/2, limit - size)).
function clampCentre(anchor, size, limit) {
  return Math.max(0, Math.min(anchor - size / 2, limit - size));
}

// Window coordinates of a card that hangs `margin` off the bar's inner side,
// centred on `anchor` (a position along the bar's axis measured from the
// bar's start: bar.x for horizontal docks, bar.y for vertical ones).
// For bottom this is exactly the old `anchors.bottom: dockBar.top` +
// `x: Math.max(0, Math.min(dockBar.x + anchorX - width/2, root.width - width))`.
function placeMenu(position, bar, anchor, size, win, margin) {
  const e = info(position).edge;
  if (e === "bottom") {
    return { x: clampCentre(bar.x + anchor, size.w, win.w), y: bar.y - margin - size.h };
  }
  if (e === "top") {
    return { x: clampCentre(bar.x + anchor, size.w, win.w), y: bar.y + bar.h + margin };
  }
  if (e === "left") {
    return { x: bar.x + bar.w + margin, y: clampCentre(bar.y + anchor, size.h, win.h) };
  }
  return { x: bar.x - margin - size.w, y: clampCentre(bar.y + anchor, size.h, win.h) };
}

// Global (Hyprland layout) rect of the dock bar. The panel window hugs one
// screen edge: its origin depends on `position` (bottom: bottom strip of
// `panelDepth`; top/left: flush at the start; right: last `panelDepth`
// columns). `monitor` is {x, y, w, h}; `bar` is the bar in window
// coordinates. For bottom this equals the old inline `dockBarRect`.
function barRect(monitor, position, panelDepth, bar) {
  const e = info(position).edge;
  let ox = monitor.x;
  let oy = monitor.y;
  if (e === "bottom") oy = monitor.y + monitor.h - panelDepth;
  if (e === "right") ox = monitor.x + monitor.w - panelDepth;
  return { x: ox + bar.x, y: oy + bar.y, w: bar.w, h: bar.h };
}

// Quadratic magnification falloff along one axis (identical numbers for the
// x cursor on a horizontal dock and the y cursor on a vertical one).
function magnifyScale(cursor, centre, radius, maxScale) {
  const dist = Math.abs(cursor - centre);
  if (dist >= radius) return 1;
  const t = 1 - dist / radius;
  return 1 + (maxScale - 1) * t * t;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    POSITIONS,
    info,
    menuSpace,
    clampCentre,
    placeMenu,
    barRect,
    magnifyScale,
  };
}
