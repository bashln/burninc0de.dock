// Settings schema, defaults and clamp. Pure so both QML (QJSEngine) and the
// node test suite exercise the same rules. Clamping happens here, at
// ingestion, so a bad settings.json can only saturate.

const DEFAULTS = {
  iconSize: 54,
  spacing: 12,
  spacerWidth: 24,
  mode: "always",
  magnify: true,
  showMenu: true,
};

const MODES = ["always", "autohide", "smart"];

const RANGES = {
  iconSize: [32, 96],
  spacing: [0, 48],
  spacerWidth: [0, 96],
};

function clampInt(raw, key) {
  const value = Math.round(Number(raw[key]));
  if (isNaN(value)) return DEFAULTS[key];
  const range = RANGES[key];
  return Math.max(range[0], Math.min(range[1], value));
}

function resolveMode(raw) {
  if (typeof raw.mode === "string" && MODES.indexOf(raw.mode) >= 0) return raw.mode;
  if (typeof raw.hideOnEmpty === "boolean") return raw.hideOnEmpty ? "autohide" : "smart";
  if (typeof raw.hideOnEmptyWorkspace === "boolean") return raw.hideOnEmptyWorkspace ? "autohide" : "smart";
  return DEFAULTS.mode;
}

function normalize(raw) {
  const source = raw || {};
  return {
    iconSize: clampInt(source, "iconSize"),
    spacing: clampInt(source, "spacing"),
    spacerWidth: clampInt(source, "spacerWidth"),
    mode: resolveMode(source),
    magnify: typeof source.magnify === "boolean" ? source.magnify : DEFAULTS.magnify,
    showMenu: typeof source.showMenu === "boolean" ? source.showMenu : DEFAULTS.showMenu,
  };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { DEFAULTS, MODES, normalize };
}
