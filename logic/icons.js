// Icon and label resolution rules. Pure over the desktop map so both QML
// (QJSEngine) and the node test suite exercise them. The map is
// { keyLowercased: { name, icon } } built from the pin tool's dump-map.

function hostFromClass(cls) {
  const m = String(cls || "").toLowerCase().match(/-([a-z0-9.-]+\.[a-z]+)__/);
  return m ? m[1] : "";
}

function resolveLabel(key, title, map) {
  let label = key;
  if (map) {
    const lower = String(key).toLowerCase();
    if (map[lower] && map[lower].name) {
      label = map[lower].name;
    } else {
      const host = hostFromClass(key);
      if (host && map[host] && map[host].name) label = map[host].name;
    }
    // Final fallback: the window title is more readable than a raw class.
    if (label === key) {
      const t = String(title || "").trim();
      if (t && t.length < 60) label = t;
    }
  }
  return label;
}

function resolveIcon(key, map) {
  if (map && key) {
    const lower = String(key).toLowerCase();
    if (map[lower] && map[lower].icon) return map[lower].icon;
    const host = hostFromClass(key);
    if (host && map[host] && map[host].icon) return map[host].icon;
  }
  return "";
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { hostFromClass, resolveLabel, resolveIcon };
}
