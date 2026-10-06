// State-file parsing rules. Pure functions over raw text so both QML
// (QJSEngine) and the node test suite can exercise them. `maxBytes` documents
// the byte ceiling the caller applied before calling; parsing does not use it.

function parseJsonArray(raw, maxBytes) {
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (e) {
    return [];
  }
}

function parseJsonObject(raw, maxBytes) {
  try {
    const parsed = JSON.parse(raw);
    return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {};
  } catch (e) {
    return {};
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { parseJsonArray, parseJsonObject };
}
