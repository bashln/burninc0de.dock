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

test("normalize returns defaults for a new field", () => {
  const n = S.normalize({});
  assert.strictEqual(n.showDelay, 0);
  assert.strictEqual(n.hideDelay, 500);
  assert.strictEqual(n.animationTime, 200);
  assert.strictEqual(n.transparencyMode, "fixed");
  assert.strictEqual(n.minAlpha, 0.35);
  assert.strictEqual(n.maxAlpha, 0.75);
  assert.strictEqual(n.indicatorStyle, "dot");
  assert.strictEqual(n.clickAction, "minimize");
  assert.strictEqual(n.scrollAction, "nothing");
  assert.strictEqual(n.intellihide, false);
  assert.strictEqual(n.intellihideMode, "focused");
  assert.strictEqual(n.position, "bottom");
  assert.strictEqual(n.urgentWiggle, false);
});

test("normalize falls back for an unknown enum", () => {
  assert.strictEqual(S.normalize({ position: "diagonal" }).position, "bottom");
  assert.strictEqual(S.normalize({ indicatorStyle: "sparkle" }).indicatorStyle, "dot");
  assert.strictEqual(S.normalize({ clickAction: "explode" }).clickAction, "minimize");
  assert.strictEqual(S.normalize({ scrollAction: "zoom" }).scrollAction, "nothing");
  assert.strictEqual(S.normalize({ intellihideMode: "sometimes" }).intellihideMode, "focused");
  assert.strictEqual(S.normalize({ transparencyMode: "glow" }).transparencyMode, "fixed");
});

test("normalize keeps a valid enum", () => {
  assert.strictEqual(S.normalize({ position: "left" }).position, "left");
  assert.strictEqual(S.normalize({ indicatorStyle: "count" }).indicatorStyle, "count");
});

test("normalize clamps the delay and alpha ranges", () => {
  assert.strictEqual(S.normalize({ showDelay: -5 }).showDelay, 0);
  assert.strictEqual(S.normalize({ showDelay: 5000 }).showDelay, 1000);
  assert.strictEqual(S.normalize({ hideDelay: 9000 }).hideDelay, 2000);
  assert.strictEqual(S.normalize({ animationTime: 9000 }).animationTime, 1000);
  assert.strictEqual(S.normalize({ minAlpha: 0.05 }).minAlpha, 0.1);
  assert.strictEqual(S.normalize({ maxAlpha: 5 }).maxAlpha, 1.0);
});

test("normalize falls back for a non-numeric delay or alpha", () => {
  assert.strictEqual(S.normalize({ showDelay: "soon" }).showDelay, 0);
  assert.strictEqual(S.normalize({ minAlpha: "x" }).minAlpha, 0.35);
});

test("normalize falls back for a non-boolean flag", () => {
  assert.strictEqual(S.normalize({ intellihide: "yes" }).intellihide, false);
  assert.strictEqual(S.normalize({ urgentWiggle: 1 }).urgentWiggle, false);
});

test("normalize ignores unknown keys", () => {
  const n = S.normalize({ wat: true });
  assert.strictEqual(n.wat, undefined);
});

test("normalize is a fixed point on DEFAULTS", () => {
  assert.deepStrictEqual(S.normalize(S.DEFAULTS), S.DEFAULTS);
});
