const test = require("node:test");
const assert = require("node:assert");
const E = require("../logic/edge.js");
const S = require("../logic/settings.js");

const win = { w: 1920, h: 320 };
const bar = { x: 800, y: 239, w: 400, h: 78 };

test("positions list matches the settings schema", () => {
  assert.deepStrictEqual(E.POSITIONS, S.POSITIONS);
});

test("info flags the axis per edge", () => {
  assert.deepStrictEqual(E.info("bottom"), { position: "bottom", edge: "bottom", horizontal: true });
  assert.deepStrictEqual(E.info("top"), { position: "top", edge: "top", horizontal: true });
  assert.deepStrictEqual(E.info("left"), { position: "left", edge: "left", horizontal: false });
  assert.deepStrictEqual(E.info("right"), { position: "right", edge: "right", horizontal: false });
});

test("an unknown position falls back to bottom", () => {
  assert.deepStrictEqual(E.info("diagonal"), E.info("bottom"));
});

test("menu placement on bottom equals the old anchor+clamp formula", () => {
  // old: anchors.bottom: dockBar.top, margin 2; x = max(0, min(bar.x + anchor - w/2, win.w - w))
  const size = { w: 230, h: 400 };
  const anchor = 140;
  const oldX = Math.max(0, Math.min(bar.x + anchor - size.w / 2, win.w - size.w));
  const oldY = bar.y - 2 - size.h;
  const p = E.placeMenu("bottom", bar, anchor, size, win, 2);
  assert.strictEqual(p.x, oldX);
  assert.strictEqual(p.y, oldY);
});

test("menu placement opens on the inner side of each edge", () => {
  const size = { w: 200, h: 100 };
  const top = E.placeMenu("top", { ...bar, y: 0 }, 50, size, win, 2);
  assert.strictEqual(top.y, 0 + 78 + 2);
  const left = E.placeMenu("left", { ...bar, x: 0, y: 400, w: 78, h: 300 }, 150, size, win, 6);
  assert.strictEqual(left.x, 0 + 78 + 6);
  assert.strictEqual(left.y, Math.max(0, Math.min(400 + 150 - size.h / 2, win.h - size.h)));
  const right = E.placeMenu("right", { ...bar, x: 242, y: 400, w: 78, h: 300 }, 150, size, win, 6);
  assert.strictEqual(right.x, 242 - 6 - 200);
});

test("menu placement clamps along the axis", () => {
  const size = { w: 400, h: 100 };
  const p = E.placeMenu("bottom", bar, -1000, size, win, 2);
  assert.strictEqual(p.x, 0);
  const q = E.placeMenu("bottom", bar, 5000, size, win, 2);
  assert.strictEqual(q.x, win.w - size.w);
});

test("menuSpace is the room on the bar's inner side", () => {
  assert.strictEqual(E.menuSpace("bottom", bar, win), 239);
  assert.strictEqual(E.menuSpace("top", { ...bar, y: 0 }, win), 320 - 0 - 78);
  assert.strictEqual(E.menuSpace("left", { ...bar, x: 0 }, win), 0);
  assert.strictEqual(E.menuSpace("right", { ...bar, x: 100, w: 78 }, win), 1920 - 100 - 78);
});

test("barRect on bottom equals the old dockBarRect formula", () => {
  const monitor = { x: 0, y: 0, w: 1920, h: 1080 };
  const old = {
    x: monitor.x + bar.x,
    y: monitor.y + monitor.h - 320 + bar.y,
    w: bar.w,
    h: bar.h,
  };
  assert.deepStrictEqual(E.barRect(monitor, "bottom", 320, bar), old);
});

test("barRect follows the window origin of each edge", () => {
  const monitor = { x: 1920, y: 0, w: 1440, h: 900 };
  const top = E.barRect(monitor, "top", 320, { ...bar, y: 20 });
  assert.deepStrictEqual(top, { x: 1920 + 800, y: 0 + 20, w: 400, h: 78 });
  const right = E.barRect(monitor, "right", 320, { x: 10, y: 40, w: 78, h: 300 });
  assert.deepStrictEqual(right, { x: 1920 + 1440 - 320 + 10, y: 0 + 40, w: 78, h: 300 });
  const left = E.barRect(monitor, "left", 320, { x: 10, y: 40, w: 78, h: 300 });
  assert.deepStrictEqual(left, { x: 1920 + 10, y: 40, w: 78, h: 300 });
});

test("magnifyScale matches the old quadratic falloff", () => {
  const old = (cursor, center) => {
    const radius = 140, max = 1.6;
    const dist = Math.abs(cursor - center);
    if (dist >= radius) return 1;
    const t = 1 - dist / radius;
    return 1 + (max - 1) * t * t;
  };
  for (const [cursor, center] of [[500, 500], [430, 500], [640, 500], [-10000, 500], [9999, 500]]) {
    assert.strictEqual(E.magnifyScale(cursor, center, 140, 1.6), old(cursor, center));
  }
});

test("magnifyScale is axis-agnostic: y-cursor works the same", () => {
  assert.strictEqual(E.magnifyScale(100, 170, 140, 1.6), E.magnifyScale(170, 100, 140, 1.6));
});
