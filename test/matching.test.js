const test = require("node:test");
const assert = require("node:assert");
const M = require("../logic/matching.js");

test("execTokenize splits on unquoted whitespace", () => {
  assert.deepStrictEqual(M.execTokenize("foot -e nvim"), ["foot", "-e", "nvim"]);
});

test("execTokenize honors a quoted argument with spaces", () => {
  assert.deepStrictEqual(M.execTokenize('app --name "a b"'), ["app", "--name", "a b"]);
});

test("binaryName takes the first token basename", () => {
  assert.strictEqual(M.binaryName("foot --app-id=foot-nvim -e nvim"), "foot");
});

test("binaryName strips the directory and extension", () => {
  assert.strictEqual(M.binaryName("/usr/lib/firefox/firefox"), "firefox");
});

test("matchesApp matches a title substring by matchTitle", () => {
  assert.strictEqual(M.matchesApp({ matchTitle: "Gmail" }, { title: "Inbox - Gmail" }), true);
});

test("matchesApp accepts a raw match field", () => {
  assert.strictEqual(M.matchesApp({ match: "Gmail" }, { title: "Inbox - Gmail" }), true);
});

test("matchesApp matches an exact appId", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot" }, { appId: "foot" }), true);
});

test("matchesApp does not match a prefix-similar appId", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot-nvim" }, { appId: "foot" }), false);
});

test("matchesApp falls back to the class when appId is empty", () => {
  assert.strictEqual(M.matchesApp({ appId: "foot" }, { appId: "", class: "foot" }), true);
});

test("matchesApp matches the cmd binary against appId", () => {
  assert.strictEqual(M.matchesApp({ cmd: "nautilus" }, { appId: "org.gnome.Nautilus" }), true);
});

test("matchesApp never matches a spacer", () => {
  assert.strictEqual(M.matchesApp({ spacer: true, cmd: "x" }, { appId: "x" }), false);
});

test("isHiddenApp matches by name", () => {
  assert.strictEqual(M.isHiddenApp({ name: "Terminal", entryId: "" }, ["Terminal"]), true);
});

test("isHiddenApp matches by entryId", () => {
  assert.strictEqual(M.isHiddenApp({ name: "X", entryId: "org.x" }, ["org.x"]), true);
});

test("isHiddenApp returns false when neither matches", () => {
  assert.strictEqual(M.isHiddenApp({ name: "Y", entryId: "org.y" }, ["Z"]), false);
});
