// Running-indicator render spec. Pure so both QML (QJSEngine) and the node
// test suite exercise it. `dot` reproduces the original single dot.

const LIMIT = 4;

function spec(style, count) {
  const n = Math.max(0, Math.floor(Number(count) || 0));
  switch (style) {
    case "dots":
      return { segments: Math.min(n, LIMIT), shape: "dot", showCount: false };
    case "dashes":
      return { segments: Math.min(n, LIMIT), shape: "dash", showCount: false };
    case "solid":
      return { segments: 1, shape: "bar", showCount: false };
    case "count":
      return { segments: 0, shape: "dot", showCount: true };
    case "dot":
    default:
      return { segments: 1, shape: "dot", showCount: false };
  }
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { LIMIT, spec };
}
