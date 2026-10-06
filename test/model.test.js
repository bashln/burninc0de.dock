const test = require("node:test");
const assert = require("node:assert");
const M = require("../logic/model.js");
const Match = require("../logic/matching.js");

test("mergeApps drops a hidden app by name", () => {
  const out = M.mergeApps([{ name: "Terminal" }], [], ["Terminal"], Match.isHiddenApp);
  assert.deepStrictEqual(out, []);
});

test("mergeApps drops a hidden app by entryId", () => {
  const out = M.mergeApps([{ name: "X", entryId: "org.x" }], [], ["org.x"], Match.isHiddenApp);
  assert.deepStrictEqual(out, []);
});

test("mergeApps appends a pin that does not duplicate", () => {
  const out = M.mergeApps([{ name: "Files" }], [{ name: "Firefox" }], [], Match.isHiddenApp);
  assert.deepStrictEqual(out.map((a) => a.name), ["Files", "Firefox"]);
});

test("mergeApps does not append a pin already declared by name", () => {
  const out = M.mergeApps([{ name: "Files" }], [{ name: "Files" }], [], Match.isHiddenApp);
  assert.strictEqual(out.length, 1);
});

test("mergeApps does not append a pin that duplicates a cmd", () => {
  const out = M.mergeApps([{ name: "Files", cmd: "nautilus" }], [{ name: "Nautilus", cmd: "nautilus" }], [], Match.isHiddenApp);
  assert.strictEqual(out.length, 1);
});

test("applyOrder sorts by saved names then appends the rest", () => {
  const apps = [{ name: "A" }, { name: "B" }, { name: "C" }];
  const out = M.applyOrder(apps, ["C", "A"]);
  assert.deepStrictEqual(out.map((a) => a.name), ["C", "A", "B"]);
});

test("applyOrder returns the apps untouched without a saved order", () => {
  const apps = [{ name: "A" }, { name: "B" }];
  assert.deepStrictEqual(M.applyOrder(apps, []).map((a) => a.name), ["A", "B"]);
});

test("runningUnpinned excludes a window an app matches", () => {
  const apps = [{ name: "Terminal", appId: "foot" }];
  const out = M.runningUnpinned(apps, [
    { key: "foot", cls: "foot", appId: "foot", title: "", label: "Foot", icon: "foot" },
  ], Match.matchesApp);
  assert.deepStrictEqual(out, []);
});

test("runningUnpinned returns an unmatched window as runningOnly", () => {
  const out = M.runningUnpinned([], [
    { key: "x", cls: "x", appId: "x", title: "", label: "X", icon: "x" },
  ], Match.matchesApp);
  assert.strictEqual(out.length, 1);
  assert.strictEqual(out[0].runningOnly, true);
  assert.strictEqual(out[0].name, "X");
});

test("runningUnpinned dedups windows sharing a key", () => {
  const w = { key: "x", cls: "x", appId: "x", title: "", label: "X", icon: "x" };
  assert.strictEqual(M.runningUnpinned([], [w, w], Match.matchesApp).length, 1);
});

test("runningUnpinned falls back to the key when the label collides", () => {
  const apps = [{ name: "X" }];
  const out = M.runningUnpinned(apps, [
    { key: "x", cls: "x", appId: "x", title: "", label: "X", icon: "x" },
  ], Match.matchesApp);
  assert.strictEqual(out[0].name, "x");
});

test("runningUnpinned skips a window with no key", () => {
  const out = M.runningUnpinned([], [{ key: "", cls: "", appId: "", title: "", label: "", icon: "" }], Match.matchesApp);
  assert.deepStrictEqual(out, []);
});

test("applyOrder handles a name that shadows an object prototype key", () => {
  const out = M.applyOrder([{ name: "constructor" }], ["constructor"]);
  assert.strictEqual(out.length, 1);
});

test("runningUnpinned handles a prototype-shadowing label", () => {
  const out = M.runningUnpinned([{ name: "constructor" }], [
    { key: "x", cls: "x", appId: "x", title: "", label: "constructor", icon: "" },
  ], Match.matchesApp);
  assert.strictEqual(out[0].name, "x");
});
