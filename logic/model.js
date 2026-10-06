// App-list assembly rules. Pure over plain data. The matching predicates are
// injected because a QML JS import cannot import another JS module at runtime.

function mergeApps(configApps, pins, hidden, isHidden) {
  const apps = [];
  for (const app of configApps) {
    if (!isHidden(app, hidden)) apps.push(app);
  }
  for (const pin of pins) {
    let duplicate = false;
    for (const app of apps) {
      if (app.name === pin.name || (app.cmd && app.cmd === pin.cmd)) {
        duplicate = true;
        break;
      }
    }
    if (!duplicate) apps.push(pin);
  }
  return apps;
}

function applyOrder(apps, savedOrder) {
  if (!savedOrder || savedOrder.length === 0) return apps.slice();
  // Object.create(null) so a name like "constructor" cannot collide with a
  // prototype key.
  const byName = Object.create(null);
  for (const app of apps) byName[app.name] = app;
  const sorted = [];
  for (const name of savedOrder) {
    if (byName[name]) {
      sorted.push(byName[name]);
      delete byName[name];
    }
  }
  for (const app of apps) if (byName[app.name]) sorted.push(app);
  return sorted;
}

function runningUnpinned(apps, windows, matches) {
  const used = Object.create(null);
  for (const app of apps) used[app.name] = true;
  const seen = Object.create(null);
  const out = [];
  for (const w of windows || []) {
    if (!w.key || seen[w.key]) continue;
    seen[w.key] = true;
    let claimed = false;
    for (const app of apps) {
      if (matches(app, { title: w.title, appId: w.appId, class: w.cls })) { claimed = true; break; }
    }
    if (claimed) continue;
    let label = w.label || w.key;
    // byName in the order pass would drop a colliding entry.
    if (used[label]) label = w.key;
    if (used[label]) continue;
    used[label] = true;
    out.push({
      entryId: "",
      pinned: false,
      runningOnly: true,
      name: label,
      icon: w.icon || "",
      cmd: "",
      matchTitle: "",
      appId: w.appId || w.cls,
      minimizable: true,
      spacer: false,
    });
  }
  return out;
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = { mergeApps, applyOrder, runningUnpinned };
}
