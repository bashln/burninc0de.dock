const test = require("node:test");
const assert = require("node:assert");
const U = require("../logic/urgent.js");

test("addressFromEvent reads the address", () => {
  assert.strictEqual(U.addressFromEvent("0x1234"), "0x1234");
});

test("addressFromEvent ignores trailing fields", () => {
  assert.strictEqual(U.addressFromEvent("0x1234,extra"), "0x1234");
});

test("addressFromEvent returns empty for empty input", () => {
  assert.strictEqual(U.addressFromEvent(""), "");
});

test("hasUrgent is true when a toplevel address is in the set", () => {
  const tls = [{ a: "0x1" }, { a: "0x2" }];
  assert.strictEqual(U.hasUrgent(tls, { "0x2": true }, (t) => t.a), true);
});

test("hasUrgent is false when none match", () => {
  const tls = [{ a: "0x1" }];
  assert.strictEqual(U.hasUrgent(tls, { "0x9": true }, (t) => t.a), false);
});

test("shouldReveal only when enabled and urgent", () => {
  assert.strictEqual(U.shouldReveal(true, 1), true);
  assert.strictEqual(U.shouldReveal(false, 1), false);
  assert.strictEqual(U.shouldReveal(true, 0), false);
});
