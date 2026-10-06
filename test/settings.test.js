const test = require("node:test");
const assert = require("node:assert");
const S = require("../logic/settings.js");

test("normalize returns defaults for an empty object", () => {
  assert.deepStrictEqual(S.normalize({}), S.DEFAULTS);
});

test("normalize clamps iconSize above the maximum", () => {
  assert.strictEqual(S.normalize({ iconSize: 1000 }).iconSize, 96);
});

test("normalize clamps iconSize below the minimum", () => {
  assert.strictEqual(S.normalize({ iconSize: 4 }).iconSize, 32);
});

test("normalize clamps spacing to zero", () => {
  assert.strictEqual(S.normalize({ spacing: -5 }).spacing, 0);
});

test("normalize rejects an unknown mode", () => {
  assert.strictEqual(S.normalize({ mode: "weird" }).mode, "always");
});

test("normalize migrates hideOnEmpty true to autohide", () => {
  assert.strictEqual(S.normalize({ hideOnEmpty: true }).mode, "autohide");
});

test("normalize migrates hideOnEmpty false to smart", () => {
  assert.strictEqual(S.normalize({ hideOnEmpty: false }).mode, "smart");
});

test("normalize keeps mode over legacy hideOnEmpty", () => {
  assert.strictEqual(S.normalize({ mode: "autohide", hideOnEmpty: false }).mode, "autohide");
});

test("normalize ignores a non-boolean magnify", () => {
  assert.strictEqual(S.normalize({ magnify: "yes" }).magnify, true);
});

test("normalize does not mutate its input", () => {
  const raw = { iconSize: 1000 };
  S.normalize(raw);
  assert.strictEqual(raw.iconSize, 1000);
});

test("normalize falls back for a non-numeric int", () => {
  assert.strictEqual(S.normalize({ spacing: "abc" }).spacing, S.DEFAULTS.spacing);
});

test("normalize clamps spacerWidth above the maximum", () => {
  assert.strictEqual(S.normalize({ spacerWidth: 500 }).spacerWidth, 96);
});
