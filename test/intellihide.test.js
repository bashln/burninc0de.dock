const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/intellihide.js");

const dock = { x: 0, y: 900, w: 1920, h: 78 };
const over = { x: 100, y: 850, w: 400, h: 200, focused: false, maximized: false, onTop: false };
const away = { x: 100, y: 100, w: 400, h: 300, focused: true, maximized: false, onTop: false };

test("disabled never hides", () => {
  assert.strictEqual(I.shouldHide(false, "all", [over], dock), false);
});

test("all hides on any overlapping window", () => {
  assert.strictEqual(I.shouldHide(true, "all", [over, away], dock), true);
  assert.strictEqual(I.shouldHide(true, "all", [away], dock), false);
});

test("focused only counts the focused window", () => {
  assert.strictEqual(I.shouldHide(true, "focused", [over], dock), false);
  assert.strictEqual(I.shouldHide(true, "focused", [{ ...over, focused: true }], dock), true);
});

test("maximized only counts a maximized window", () => {
  assert.strictEqual(I.shouldHide(true, "maximized", [{ ...over, maximized: true }], dock), true);
  assert.strictEqual(I.shouldHide(true, "maximized", [{ ...over, focused: true }], dock), false);
});

test("always-on-top only counts a pinned window", () => {
  assert.strictEqual(I.shouldHide(true, "always-on-top", [{ ...over, onTop: true }], dock), true);
  assert.strictEqual(I.shouldHide(true, "always-on-top", [{ ...over, focused: true }], dock), false);
});

test("touching edges is not an overlap", () => {
  const touching = { x: 0, y: 800, w: 100, h: 100, focused: true, maximized: false, onTop: false };
  assert.strictEqual(I.overlaps(touching, dock), false);
  assert.strictEqual(I.shouldHide(true, "all", [touching], dock), false);
});

test("an unknown mode falls back to focused", () => {
  assert.strictEqual(I.shouldHide(true, "sideways", [over], dock), false);
  assert.strictEqual(I.shouldHide(true, "sideways", [{ ...over, focused: true }], dock), true);
});

test("empty window list never hides", () => {
  assert.strictEqual(I.shouldHide(true, "all", [], dock), false);
  assert.strictEqual(I.shouldHide(true, "all", null, dock), false);
});

test("modes list matches the settings schema", () => {
  assert.deepStrictEqual(I.MODES, ["all", "focused", "maximized", "always-on-top"]);
});
