const test = require("node:test");
const assert = require("node:assert");
const A = require("../logic/actions.js");

test("a non-running icon always launches", () => {
  assert.strictEqual(A.routeClick("minimize", false), "launch");
  assert.strictEqual(A.routeClick("cycle", false), "launch");
  assert.strictEqual(A.routeClick("focus", false), "launch");
});

test("minimize routes running icons to the minimize toggle", () => {
  assert.strictEqual(A.routeClick("minimize", true), "minimize");
});

test("launch/cycle/focus route running icons accordingly", () => {
  assert.strictEqual(A.routeClick("launch", true), "launch");
  assert.strictEqual(A.routeClick("cycle", true), "cycle");
  assert.strictEqual(A.routeClick("focus", true), "focus");
});

test("an unknown click action falls back to minimize", () => {
  assert.strictEqual(A.routeClick("explode", true), "minimize");
});

test("cycleIndex returns -1 for an empty window list", () => {
  assert.strictEqual(A.cycleIndex([], 1), -1);
  assert.strictEqual(A.cycleIndex([], -1), -1);
});

test("cycleIndex picks the only window", () => {
  assert.strictEqual(A.cycleIndex([0], 1), 0);
  assert.strictEqual(A.cycleIndex([4], -1), 0);
});

test("cycleIndex starts at the most recent window when none is focused", () => {
  assert.strictEqual(A.cycleIndex([5, 9, 2], 1), 2);
  assert.strictEqual(A.cycleIndex([5, 9, 2], -1), 2);
});

test("cycleIndex steps forward from the focused window and wraps", () => {
  // ids[i] = focusHistoryID of window i; 0 = currently focused (index 1)
  assert.strictEqual(A.cycleIndex([5, 0, 9], 1), 0);
  assert.strictEqual(A.cycleIndex([0, 5, 9], 1), 1);
  assert.strictEqual(A.cycleIndex([0, 5, 9], -1), 2);
  assert.strictEqual(A.cycleIndex([7, 0], -1), 0);
});

test("routeScroll maps the enum and rejects unknown values", () => {
  assert.strictEqual(A.routeScroll("cycle-windows"), "cycle-windows");
  assert.strictEqual(A.routeScroll("switch-workspace"), "switch-workspace");
  assert.strictEqual(A.routeScroll("nothing"), "nothing");
  assert.strictEqual(A.routeScroll("nope"), "nothing");
});

test("mostRecentIndex picks the lowest focusHistoryID", () => {
  assert.strictEqual(A.mostRecentIndex([]), -1);
  assert.strictEqual(A.mostRecentIndex([3]), 0);
  assert.strictEqual(A.mostRecentIndex([5, 0, 9]), 1);
  assert.strictEqual(A.mostRecentIndex([5, 9, 2]), 2);
});

test("scrollStep fires once per notch and resets", () => {
  let s = A.scrollStep(0, 30);
  assert.deepStrictEqual(s, { acc: 30, fire: false });
  s = A.scrollStep(s.acc, 30);
  assert.strictEqual(s.fire, false);
  s = A.scrollStep(s.acc, 60);
  assert.deepStrictEqual(s, { acc: 0, fire: true });
  assert.deepStrictEqual(A.scrollStep(0, 120), { acc: 0, fire: true });
});

test("scrollStep accumulates in both directions", () => {
  assert.deepStrictEqual(A.scrollStep(60, -60), { acc: 0, fire: false });
  const up = A.scrollStep(0, -120);
  assert.deepStrictEqual(up, { acc: 0, fire: true });
});
