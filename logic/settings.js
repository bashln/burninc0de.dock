// Settings schema, defaults and clamp. Pure so both QML (QJSEngine) and the
// node test suite exercise the same rules. Clamping happens here, at
// ingestion, so a bad settings.json can only saturate. Defaults preserve the
// dock's current behavior, so adding a field is invisible until it is wired.

const DEFAULTS = {
  iconSize: 54,
  spacing: 12,
  spacerWidth: 24,
  mode: "always",
  magnify: true,
  showMenu: true,
  showDelay: 0,
  hideDelay: 500,
  animationTime: 200,
  transparencyMode: "fixed",
  minAlpha: 0.35,
  maxAlpha: 0.75,
  indicatorStyle: "dot",
  clickAction: "minimize",
  scrollAction: "nothing",
  intellihide: false,
  intellihideMode: "focused",
  position: "bottom",
  urgentWiggle: false,
};

const MODES = ["always", "autohide", "smart"];
const TRANSPARENCY_MODES = ["fixed", "dynamic"];
const INDICATOR_STYLES = ["dot", "dots", "dashes", "solid", "count"];
const CLICK_ACTIONS = ["minimize", "launch", "cycle", "focus"];
const SCROLL_ACTIONS = ["nothing", "cycle-windows", "switch-workspace"];
const INTELLIHIDE_MODES = ["all", "focused", "maximized", "always-on-top"];
const POSITIONS = ["bottom", "top", "left", "right"];

const INT_RANGES = {
  iconSize: [32, 96],
  spacing: [0, 48],
  spacerWidth: [0, 96],
  showDelay: [0, 1000],
  hideDelay: [0, 2000],
  animationTime: [0, 1000],
};

const FLOAT_RANGES = {
  minAlpha: [0.1, 1.0],
  maxAlpha: [0.1, 1.0],
};

function clampInt(raw, key) {
  const value = Math.round(Number(raw[key]));
  if (isNaN(value)) return DEFAULTS[key];
  const range = INT_RANGES[key];
  return Math.max(range[0], Math.min(range[1], value));
}

function clampFloat(raw, key) {
  const value = Number(raw[key]);
  if (isNaN(value)) return DEFAULTS[key];
  const range = FLOAT_RANGES[key];
  return Math.max(range[0], Math.min(range[1], value));
}

function pick(raw, key, allowed) {
  return (typeof raw[key] === "string" && allowed.indexOf(raw[key]) >= 0)
    ? raw[key] : DEFAULTS[key];
}

function flag(raw, key) {
  return typeof raw[key] === "boolean" ? raw[key] : DEFAULTS[key];
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
    magnify: flag(source, "magnify"),
    showMenu: flag(source, "showMenu"),
    showDelay: clampInt(source, "showDelay"),
    hideDelay: clampInt(source, "hideDelay"),
    animationTime: clampInt(source, "animationTime"),
    transparencyMode: pick(source, "transparencyMode", TRANSPARENCY_MODES),
    minAlpha: clampFloat(source, "minAlpha"),
    maxAlpha: clampFloat(source, "maxAlpha"),
    indicatorStyle: pick(source, "indicatorStyle", INDICATOR_STYLES),
    clickAction: pick(source, "clickAction", CLICK_ACTIONS),
    scrollAction: pick(source, "scrollAction", SCROLL_ACTIONS),
    intellihide: flag(source, "intellihide"),
    intellihideMode: pick(source, "intellihideMode", INTELLIHIDE_MODES),
    position: pick(source, "position", POSITIONS),
    urgentWiggle: flag(source, "urgentWiggle"),
  };
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    DEFAULTS,
    MODES,
    TRANSPARENCY_MODES,
    INDICATOR_STYLES,
    CLICK_ACTIONS,
    SCROLL_ACTIONS,
    INTELLIHIDE_MODES,
    POSITIONS,
    normalize,
  };
}
