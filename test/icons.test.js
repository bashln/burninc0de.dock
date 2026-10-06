const test = require("node:test");
const assert = require("node:assert");
const I = require("../logic/icons.js");

test("hostFromClass extracts the host from a chrome synthetic class", () => {
  assert.strictEqual(I.hostFromClass("chrome-web.whatsapp.com__-Default"), "web.whatsapp.com");
});

test("hostFromClass returns empty for a plain class", () => {
  assert.strictEqual(I.hostFromClass("foot"), "");
});

test("resolveLabel prefers the desktop name", () => {
  assert.strictEqual(I.resolveLabel("foo", "A Title", { foo: { name: "Foo" } }), "Foo");
});

test("resolveLabel resolves a chrome host", () => {
  assert.strictEqual(I.resolveLabel("chrome-web.whatsapp.com__-Default", "", { "web.whatsapp.com": { name: "WhatsApp" } }), "WhatsApp");
});

test("resolveLabel falls back to the window title", () => {
  assert.strictEqual(I.resolveLabel("unknown", "A Title", {}), "A Title");
});

test("resolveLabel falls back to the key when there is no title", () => {
  assert.strictEqual(I.resolveLabel("unknown", "", {}), "unknown");
});

test("resolveLabel returns the key when there is no map", () => {
  assert.strictEqual(I.resolveLabel("unknown", "A Title", null), "unknown");
});

test("resolveIcon returns the mapped icon", () => {
  assert.strictEqual(I.resolveIcon("foo", { foo: { icon: "bar" } }), "bar");
});

test("resolveIcon returns empty when unmapped", () => {
  assert.strictEqual(I.resolveIcon("foo", {}), "");
});

test("resolveIcon returns empty without a map", () => {
  assert.strictEqual(I.resolveIcon("foo", null), "");
});
