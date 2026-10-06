const test = require("node:test");
const assert = require("node:assert");
const S = require("../logic/state.js");

test("parseJsonArray returns the array for valid JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray('["a","b"]', 4096), ["a", "b"]);
});

test("parseJsonArray returns [] for invalid JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray("not json", 4096), []);
});

test("parseJsonArray returns [] for non-array JSON", () => {
  assert.deepStrictEqual(S.parseJsonArray('{"a":1}', 4096), []);
});

test("parseJsonObject returns the object for valid JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject('{"a":1}', 4096), { a: 1 });
});

test("parseJsonObject returns {} for array JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject("[1,2]", 4096), {});
});

test("parseJsonObject returns {} for invalid JSON", () => {
  assert.deepStrictEqual(S.parseJsonObject("", 4096), {});
});
