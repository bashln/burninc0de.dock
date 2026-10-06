import QtQml
import Quickshell.Hyprland
import "../config"
import "../services"
import "../logic/model.js" as Model
import "../logic/matching.js" as Matching

// Builds the ordered app list for one panel: config apps, merged pins, hidden
// filtering, running-unpinned entries and the saved order. Pure assembly rules
// live in logic/model.js; this adapts them to the runtime singletons.
QtObject {
  id: dockModel

  function normalize(app, pinned) {
    return {
      // Desktop entry id, only present on pinned apps. It is the key the
      // pin tool unpins by.
      entryId: app.id ?? "",
      pinned: pinned === true,
      name: app.name ?? "",
      icon: app.icon ?? "",
      cmd: app.cmd ?? "",
      // `match` is a reserved-ish name on the QML side, so the role is renamed.
      matchTitle: app.match ?? "",
      appId: app.appId ?? "",
      minimizable: app.minimizable !== false,
      runningOnly: false,
      spacer: app.spacer === true,
    }
  }

  function build(includeRunning) {
    const config = []
    for (const app of DockApps.apps) config.push(normalize(app, false))
    const pins = []
    for (const pin of StateStore.pins) pins.push(normalize(pin, true))

    let apps = Model.mergeApps(config, pins, StateStore.hidden, Matching.isHiddenApp)

    if (includeRunning) {
      const windows = []
      for (const tl of Hyprland.toplevels.values) {
        const cls = tl.lastIpcObject?.class ?? ""
        const aid = tl.wayland?.appId ?? ""
        const key = cls || aid
        if (!key) continue
        const win = { title: tl.title ?? "", appId: aid, class: cls }
        let claimed = false
        for (const app of apps) {
          if (Matching.matchesApp(app, win)) { claimed = true; break }
        }
        if (claimed) continue
        const entry = IconResolver.desktopEntryForWindow(cls, aid)
        const label = (entry && entry.name) ? String(entry.name) : IconResolver.candidateLabel(key, tl.title)
        windows.push({
          key: key,
          cls: cls,
          appId: aid,
          title: tl.title ?? "",
          label: label || key,
          icon: entry ? String(entry.icon || "") : IconResolver.candidateIcon(key, cls, aid),
        })
      }
      apps = apps.concat(Model.runningUnpinned(apps, windows, Matching.matchesApp))
    }

    return Model.applyOrder(apps, StateStore.order)
  }
}
