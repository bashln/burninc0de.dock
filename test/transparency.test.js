const test = require("node:test");
const assert = require("node:assert");
const T = require("../logic/transparency.js");

const dock = { x: 0, y: 1000, w: 1920, h: 78 };

test("distance is 0 for intersecting rects", () => {
  assert.strictEqual(T.distance({ x: 0, y: 990, w: 100, h: 50 }, dock), 0);
});

test("distance is the gap between separated rects", () => {
  assert.strictEqual(T.distance({ x: 0, y: 900, w: 100, h: 60 }, dock), 40);
});

test("nearness is 1 for an overlapping window", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 950, w: 1920, h: 130 }], dock, 100), 1);
});

test("nearness is 0 for an empty window list", () => {
  assert.strictEqual(T.nearness([], dock, 100), 0);
});

test("nearness interpolates inside the slack", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 850, w: 100, h: 100 }], dock, 100), 0.5);
});

test("nearness is 0 at or beyond the slack", () => {
  assert.strictEqual(T.nearness([{ x: 0, y: 800, w: 100, h: 100 }], dock, 100), 0);
});

test("fixed mode returns the fixed alpha for every nearness", () => {
  assert.strictEqual(T.alphaFor("fixed", 1, 0.35, 0.75, 0.6), 0.6);
  assert.strictEqual(T.alphaFor("fixed", 0, 0.35, 0.75, 0.6), 0.6);
});

test("dynamic mode maps nearness onto min..max", () => {
  assert.strictEqual(T.alphaFor("dynamic", 0, 0.35, 0.75, 0.6), 0.35);
  assert.strictEqual(T.alphaFor("dynamic", 1, 0.35, 0.75, 0.6), 0.75);
  assert.strictEqual(T.alphaFor("dynamic", 0.5, 0.35, 0.75, 0.6), 0.55);
});

test("dynamic mode clamps out-of-range nearness", () => {
  assert.strictEqual(T.alphaFor("dynamic", 2, 0.35, 0.75, 0.6), 0.75);
  assert.strictEqual(T.alphaFor("dynamic", -1, 0.35, 0.75, 0.6), 0.35);
});

test("inverted min/max still stays inside the bounds", () => {
  assert.strictEqual(T.alphaFor("dynamic", 0, 0.75, 0.35, 0.6), 0.35);
  assert.strictEqual(T.alphaFor("dynamic", 1, 0.75, 0.35, 0.6), 0.75);
});

test("an unknown mode behaves like fixed", () => {
  assert.strictEqual(T.alphaFor("blur", 1, 0.35, 0.75, 0.6), 0.6);
});
