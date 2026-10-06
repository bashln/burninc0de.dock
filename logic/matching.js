// Window-matching rules. Pure over plain data so both QML (QJSEngine) and the
// node test suite exercise the same logic. `win` is { title, appId, class },
// `app` is the normalized form { matchTitle, appId, cmd, spacer }.

// Tokenizes an XDG desktop-entry Exec value per the freedesktop spec:
// split on unquoted whitespace, honor double quotes (where \ escapes
// " \ $ `), single quotes (fully literal), and backslash escapes.
// A plain split(/\s+/) corrupts any argument containing a quoted space.
function execTokenize(exec) {
  const parts = [];
  let cur = "", has = false, i = 0;
  while (i < exec.length) {
    const c = exec[i];
    if (c === " " || c === "\t") {
      if (has) { parts.push(cur); cur = ""; has = false; }
      i++;
      continue;
    }
    if (c === '"') {
      has = true; i++;
      while (i < exec.length && exec[i] !== '"') {
        if (exec[i] === "\\" && '"\\$`'.includes(exec[i + 1] ?? "")) i++;
        cur += exec[i++] ?? "";
      }
      i++;
      continue;
    }
    if (c === "'") {
      has = true; i++;
      while (i < exec.length && exec[i] !== "'") cur += exec[i++];
      i++;
      continue;
    }
    if (c === "\\" && exec[i + 1]) { cur += exec[i + 1]; i += 2; has = true; continue; }
    cur += c; has = true; i++;
  }
  if (has) parts.push(cur);
  return parts;
}

function binaryName(cmd) {
  const first = execTokenize(cmd)[0] ?? "";
  return first.split("/").pop().replace(/\.[^/.]+$/, "").toLowerCase();
}

function matchesApp(app, win) {
  // Spacers never match a window; an empty cmd would otherwise match all.
  if (app.spacer) return false;
  const title = String(win.title ?? "").toLowerCase();
  const appId = String(win.appId ?? "").toLowerCase();
  const cls = String(win.class ?? "").toLowerCase();
  // Normalized apps carry `matchTitle`; callers that pass raw entry data use
  // `match`. Accept both.
  const matcher = app.matchTitle ? String(app.matchTitle) : (app.match ? String(app.match) : "");
  if (matcher) {
    return title.includes(matcher.toLowerCase());
  }
  if (app.appId) {
    const needle = String(app.appId).toLowerCase();
    // Class fallback: XWayland windows often report an empty wayland appId,
    // and running-only entries key on class.
    return appId.includes(needle) || cls.includes(needle);
  }
  if (app.cmd) {
    const exe = binaryName(app.cmd);
    if (!exe) return false;
    return appId.includes(exe) || cls.includes(exe) || (!!cls && exe.includes(cls));
  }
  return false;
}

function isHiddenApp(app, hidden) {
  if (hidden.indexOf(app.name) >= 0) return true;
  return app.entryId !== "" && app.entryId != null && hidden.indexOf(app.entryId) >= 0;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { execTokenize, binaryName, matchesApp, isHiddenApp };
}
