const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/indicator.js");

test("dot is a single dot and does not show a count", () => {
  assert.deepStrictEqual(I.spec("dot", 3), { segments: 1, shape: "dot", showCount: false });
});

test("dots draws one dot per window", () => {
  assert.deepStrictEqual(I.spec("dots", 3), { segments: 3, shape: "dot", showCount: false });
});

test("dots caps at LIMIT segments", () => {
  assert.deepStrictEqual(I.spec("dots", 10), { segments: I.LIMIT, shape: "dot", showCount: false });
});

test("dashes draws one dash per window", () => {
  assert.deepStrictEqual(I.spec("dashes", 2), { segments: 2, shape: "dash", showCount: false });
});

test("solid is a single bar", () => {
  assert.deepStrictEqual(I.spec("solid", 5), { segments: 1, shape: "bar", showCount: false });
});

test("count shows the number and no segments", () => {
  assert.deepStrictEqual(I.spec("count", 4), { segments: 0, shape: "dot", showCount: true });
});

test("an unknown style falls back to dot", () => {
  assert.deepStrictEqual(I.spec("sparkle", 2), { segments: 1, shape: "dot", showCount: false });
});

test("zero windows yields no segments for every style", () => {
  assert.strictEqual(I.spec("dots", 0).segments, 0);
  assert.strictEqual(I.spec("dashes", 0).segments, 0);
});
