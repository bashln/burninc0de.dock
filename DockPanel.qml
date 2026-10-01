import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls.Basic
import qs.Commons
import "config"
import Quickshell.Io

PanelWindow {
  id: root

  // Declared on the delegate root (not the instance block in Dock.qml) so
  // Variants injects the QScreen exactly like Omarchy's Background does.
  required property var modelData
  screen: modelData

  anchors.bottom: true
  anchors.left: true
  anchors.right: true
  WlrLayershell.namespace: "quickshelldock"
  WlrLayershell.layer: WlrLayer.Top
  // Reserve screen space only in the fixed mode, so tiling windows stop above
  // the dock (macOS without auto-hide). Auto-hide/smart float over content.
  // Uses the base size, not the hover-magnified one, so hovering never
  // reflows the windows. `-1` = no reservation.
  exclusiveZone: dockMode === "always" ? Math.round(itemSize + 24 + gap + 4) : -1
  color: "transparent"
  focusable: false

  mask: Region {
    Region { item: triggerStrip }
    Region { item: dockBar }
    Region { item: contextMenu }
    Region { item: windowMenu }
    Region { item: pinMenu }
    Region { item: settingsPanel }
  }

  // The window is intentionally oversized so menus have room to grow above
  // the dock bar without clipping or dynamic height flicker. exclusiveZone
  // is -1 either way, so nothing on screen gets pushed around.
  // 320 fits ~8 pin rows (8*26+7*1+16 = 231) + dock bar (78) + gap/margin (9).
  implicitHeight: 320

  readonly property int dockHeight: 68
  readonly property real gap: 6
  readonly property real elevationMargin: -3

  // Icon geometry is user-tunable from the Settings panel; the defaults are
  // also what "Reset" restores and what applies before settings.json loads.
  readonly property int defaultItemSize: 54
  readonly property int defaultItemSpacing: 12
  property int itemSize: defaultItemSize
  property int itemSpacing: defaultItemSpacing
  readonly property real itemPitch: itemSize + itemSpacing
  // Visibility mode:
  //   "always"   fixed — never hides (macOS dock with auto-hide off)
  //   "autohide" hidden — reveals on bottom-edge hover (macOS auto-hide)
  //   "smart"    visible on empty workspaces only (previous behaviour)
  property string dockMode: "always"
  // Hover magnification can be switched off entirely (Settings / settings.json).
  property bool magnifyEnabled: true
  // macOS-style hover magnification. Only off while dragging, so the reorder
  // math (itemPitch) stays stable — menus must NOT disable it, otherwise
  // hovering a multi-window icon (which opens the window list) collapses the
  // magnification.
  property real cursorSceneX: -10000
  readonly property real magnifyMaxScale: 1.6
  readonly property real magnifyRadius: itemSize * 2.6
  readonly property bool magnifyActive: magnifyEnabled && dockHover.hovered && !dragging
  // Name bubble above the hovered icon (single-window apps; multi-window apps
  // show the window list instead).
  property string hoverName: ""
  property real hoverNameAnchorX: 0
  // Trailing separator + trash geometry. Kept in the base-layout math so the
  // magnification slots line up with the unmagnified icons.
  readonly property real separatorWidth: 1
  readonly property real trashWidth: itemSize
  // A "spacer" entry (a config app with `spacer: true`) renders as a fixed gap
  // to group icons macOS-style. Its width is tunable from the Settings panel.
  property real spacerWidth: 24
  // Glass translucency derived from the theme's bar alpha (clamped so it stays
  // a glass surface even with an opaque theme, without going invisible).
  readonly property real glassAlpha: Math.max(0.35, Math.min(0.75, Color.bar.background.a))
  // Local flag: DockApps singleton may survive plugin reloads without new
  // properties — do not depend on cross-file singleton for this.
  property bool showRunningUnpinned: true
  // Per-instance monitor: QScreen name == Hyprland connector name (HDMI-A-1…).
  // UntypedObjectModel has no .find; .values is the QObjectList (JS array).
  readonly property var hlMonitor: Hyprland.monitors.values.find(m => m.name === root.screen?.name)
  readonly property int monitorWsId: hlMonitor && hlMonitor.activeWorkspace ? hlMonitor.activeWorkspace.id : -1
  // Disk icon index (name → path), same idea as AppLibrary.iconIndex: Qt's
  // themed lookup misses names like "x", the menu's disk scan does not.
  property var iconDiskIndex: ({})
  property var pendingIconDiskIndex: ({})

  property bool dockVisible: true
  property bool mouseOverDockArea: triggerHover.hovered || dockHover.hovered || contextHover.hovered || windowMenuHover.hovered || pinMenuHover.hovered || settingsHover.hovered
  property bool workspaceEmpty: true
  property string clientsJson: ""
  property int _badgeTick: 0

  // Byte ceilings for everything whose length the dock doesn't control:
  // state files are user-writable and hyprctl output scales with open
  // windows, so neither may reach this long-lived process unbounded. Both
  // are orders of magnitude above any legitimate data.
  readonly property int maxStateBytes: 65536
  readonly property int maxClientsBytes: 1048576

  // Drag-to-reorder state. Only one icon can be dragged at a time, so this
  // lives on the root rather than in the delegates.
  property string dragName: ""
  property real dragPointerX: 0
  property real dragGrabOffset: 0
  readonly property bool dragging: dragName !== ""

  // Icon order survives restarts here. Kept out of the config dir so a
  // git pull never fights with it. State lives under XDG_STATE_HOME/omarchy/burninc0de.dock
  // (i.e. ~/.local/state/omarchy/burninc0de.dock) — namespaced under omarchy/
  // and using the plugin id so it's 100% collision-free.
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/burninc0de.dock"
  // Legacy locations before the final burninc0de.dock namespacing — migrated on startup.
  readonly property string legacyStateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/quickshelldock"
  readonly property string legacyStateDir2: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/dock"
  readonly property string legacyStateDir3: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/stealthdock"
  readonly property string orderPath: stateDir + "/order.json"
  readonly property string pinsPath: stateDir + "/pins.json"
  readonly property string hiddenPath: stateDir + "/hidden.json"
  readonly property string settingsPath: stateDir + "/settings.json"
  // Resolved relative to this file, NOT Quickshell.shellDir: Omarchy loads
  // plugins into its own shell instance, so shellDir points at
  // /usr/share/omarchy/shell and every execDetached would silently no-op.
  readonly property string pinTool: {
    const u = Qt.resolvedUrl("./bin/quickshelldock-pin").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }
  property var savedOrder: []
  property var pinnedApps: []
  property var hiddenApps: []

  // Right-click context menu state.
  property bool contextOpen: false
  property string contextKey: ""
  property var contextAppData: null
  property bool contextRunning: false
  property real contextAnchorX: 0

  // Hover window list state.
  property bool hoverMenuOpen: false
  property string hoverMenuKey: ""
  property var hoverMenuWindows: []
  property real hoverMenuAnchorX: 0

  // Settings panel state (opened from the empty-space right-click menu).
  property bool settingsOpen: false
  // Absolute PanelWindow X of the cursor that opened the panel. Stored
  // absolute (not dockBar-relative) so changing icon size/spacing, which
  // reflows dockBar.width/x, doesn't drag the panel away mid-slider.
  property real settingsAnchorX: 0

  // Right-click-on-empty-space menu: running apps not already on the dock.
  property bool pinMenuOpen: false
  property var pinCandidates: []
  property real pinMenuAnchorX: 0
  // Show-more pagination: keep the card bounded (~5 rows) and expand on demand.
  // The window is already oversized, so expanding does not resize the surface.
  readonly property int pinMenuPageSize: 5
  property bool pinMenuExpanded: false
  readonly property bool pinMenuHasMore: pinCandidates.length > pinMenuPageSize
  readonly property var pinMenuVisibleCandidates: pinMenuExpanded ? pinCandidates : pinCandidates.slice(0, pinMenuPageSize)
  // Lazy one-time desktop Name cache: class/appId/host (lowercased) → Name.
  // Built on first pin-menu open so the menu is synchronous after. Null =
  // not yet loaded.
  property var desktopNameMap: null
  property bool desktopMapLoading: false
  property real pendingPinAnchorX: 0
  property bool pendingPinOpen: false

  // Matches what other docks offer: GNOME's dash-to-dock, the macOS Dock and
  // KDE's task manager all agree on new-window / pin-unpin / quit. Window
  // lists and "App Details" are deliberately left out — out of scope here.
  readonly property var contextActions: {
    if (root.contextAppData && root.contextAppData.runningOnly) {
      return [{ label: "Pin to dock", act: "pin" }]
    }
    let actions = [{ label: "Open new window", act: "new" }]
    if (root.contextRunning) actions.push({ label: "Quit", act: "quit" })
    actions.push({ label: "Unpin from dock", act: "unpin" })
    return actions
  }

  Process {
    id: clientsProcess
    // Piped through head -c so the collector's buffer is capped even for a
    // pathological client list. Truncation is unreachable below ~2000
    // windows; if it ever happened, JSON.parse fails and the workspace
    // counts as empty — degraded cosmetics, not a ballooning shell.
    command: ["sh", "-c", "hyprctl clients -j | head -c " + root.maxClientsBytes]
    stdout: StdioCollector {
      onStreamFinished: { root.clientsJson = this.text }
    }
  }

  Process {
    id: mkdirProcess
    // Ensures the new state dir exists and migrates any files from legacy
    // locations (quickshelldock, omarchy/dock, omarchy/stealthdock). Only copies
    // files that don't already exist so a fresh install never clobbers data.
    command: ["sh", "-c", "mkdir -p \"$1\"; for legacy in \"$2\" \"$3\" \"$4\"; do if [ -d \"$legacy\" ]; then for f in order.json pins.json hidden.json; do [ -f \"$legacy/$f\" ] && [ ! -e \"$1/$f\" ] && cp -n -- \"$legacy/$f\" \"$1/$f\" 2>/dev/null; done; fi; done", "sh", root.stateDir, root.legacyStateDir, root.legacyStateDir2, root.legacyStateDir3]
    running: true
  }

  // State files are user-writable, so their byte length is untrusted: the
  // dock never loads them through FileView (which buffers whole files) but
  // reads through head -c. The FileViews below are watchers only —
  // preload: false keeps them from buffering any text while still firing
  // fileChanged. bin/quickshelldock-pin renames fully-written temp files
  // into place, so a read started by fileChanged always sees complete JSON.
  Process {
    id: stateReader
    property string kind: ""
    // Reads requested while one is in flight drain here, oldest first. A
    // single slot would drop every request but the last: startup fires all
    // three reads back-to-back and pins would lose to hidden.
    property var pendingQueue: []
    stdout: StdioCollector {
      onStreamFinished: root.consumeStateFile(stateReader.kind, this.text)
    }
    // Missing files at first boot are normal; keep head's stderr out of the log.
    stderr: StdioCollector {}
    onExited: {
      if (stateReader.pendingQueue.length === 0) return
      const next = stateReader.pendingQueue.shift()
      root.readStateFile(next.kind, next.path)
    }
  }

  function readStateFile(kind, path) {
    if (stateReader.running) {
      stateReader.pendingQueue.push({ kind: kind, path: path })
      return
    }
    stateReader.kind = kind
    stateReader.command = ["head", "-c", String(root.maxStateBytes), "--", path]
    stateReader.running = true
  }

  function parseJsonArray(raw, label) {
    try {
      const parsed = JSON.parse(raw)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      if (raw.length >= root.maxStateBytes)
        console.warn("quickshelldock:", label, "is at or over the",
          root.maxStateBytes, "byte read ceiling; ignoring it")
      return []
    }
  }

  function consumeStateFile(kind, raw) {
    if (kind === "order") savedOrder = parseJsonArray(raw, "order.json")
    else if (kind === "pins") pinnedApps = parseJsonArray(raw, "pins.json")
    else if (kind === "hidden") hiddenApps = parseJsonArray(raw, "hidden.json")
    else if (kind === "settings") {
      applySettings(parseJsonObject(raw, "settings.json"))
      return
    }
    else return
    if (!dragging) rebuildModel()
  }

  function parseJsonObject(raw, label) {
    try {
      const parsed = JSON.parse(raw)
      return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {}
    } catch (e) {
      if (raw.length >= root.maxStateBytes)
        console.warn("quickshelldock:", label, "is at or over the",
          root.maxStateBytes, "byte read ceiling; ignoring it")
      return {}
    }
  }

  // Clamped at ingestion like every other untrusted input: settings.json is
  // user-writable, so a bogus value can only saturate, not break layout.
  function applySettings(s) {
    const size = Math.round(Number(s.iconSize))
    const spacing = Math.round(Number(s.spacing))
    const spacer = Math.round(Number(s.spacerWidth))
    if (!isNaN(size)) itemSize = Math.max(32, Math.min(96, size))
    if (!isNaN(spacing)) itemSpacing = Math.max(0, Math.min(48, spacing))
    if (!isNaN(spacer)) spacerWidth = Math.max(0, Math.min(96, spacer))
    // `mode` wins; legacy hideOnEmpty maps to the closest mode.
    if (typeof s.mode === "string" && ["always", "autohide", "smart"].indexOf(s.mode) >= 0)
      dockMode = s.mode
    else if (typeof s.hideOnEmpty === "boolean")
      dockMode = s.hideOnEmpty ? "autohide" : "smart"
    else if (typeof s.hideOnEmptyWorkspace === "boolean")
      dockMode = s.hideOnEmptyWorkspace ? "autohide" : "smart"
    if (typeof s.magnify === "boolean") magnifyEnabled = s.magnify
  }

  function persistSettings() {
    settingsFile.setText(JSON.stringify(
      { iconSize: itemSize, spacing: itemSpacing, spacerWidth: spacerWidth, mode: dockMode, magnify: magnifyEnabled }, null, 2) + "\n")
  }

  // Write-only handle for drag order. Never loaded, so nothing from disk is
  // buffered here either.
  FileView {
    id: orderFile
    path: root.orderPath
    preload: false
    printErrors: false
    atomicWrites: true
  }

  // Config apps removed from the dock. Suppressed here rather than by
  // rewriting UserConfig.qml, which is the user's to own.
  FileView {
    id: hiddenFile
    path: root.hiddenPath
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: readStateFile("hidden", root.hiddenPath)
  }

  // Written by bin/quickshelldock-pin, never by the dock. Watching it is what
  // makes a pin from the Omarchy menu show up without a restart.
  FileView {
    id: pinsFile
    path: root.pinsPath
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: readStateFile("pins", root.pinsPath)
  }

  // Settings are written only by this process (Settings panel / reset), so
  // unlike pins/hidden there is no external writer to watch for.
  FileView {
    id: settingsFile
    path: root.settingsPath
    preload: false
    printErrors: false
    atomicWrites: true
  }


  ListModel { id: appModel }

  function normalizeApp(app, pinned) {
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

  // Declaration order in the config is the baseline; anything the user has
  // dragged wins over it. Apps added to the config after the last drag land
  // at the end.
  function rebuildModel() {
    let apps = []
    for (const app of DockApps.apps) apps.push(normalizeApp(app, false))

    // Pins append after the configured apps. An app already declared in
    // UserConfig.qml wins, so pinning something that is already on the dock
    // is a no-op rather than a duplicate icon.
    for (const pin of pinnedApps) {
      const entry = normalizeApp(pin, true)
      let duplicate = false
      for (const app of apps) {
        if (app.name === entry.name || (app.cmd && app.cmd === entry.cmd)) {
          duplicate = true
          break
        }
      }
      if (!duplicate) apps.push(entry)
    }

    // Running apps no config/pinned entry claims, same scan as the pin menu.
    // Surface them on the bar so unpinned work is visible without right-click.
    if (root.showRunningUnpinned) {
      let claimed = []
      for (const app of apps) {
        const tls = root.getToplevelsForApp({ match: app.matchTitle, appId: app.appId, cmd: app.cmd })
        for (const t of tls) claimed.push(t.toplevel)
      }
      const used = {}
      for (const app of apps) used[app.name] = true
      const seen = {}
      for (const tl of Hyprland.toplevels.values) {
        if (claimed.indexOf(tl) >= 0) continue
        const cls = tl.lastIpcObject?.class ?? ""
        const aid = tl.wayland?.appId ?? ""
        const key = cls || aid
        if (!key || seen[key]) continue
        seen[key] = true
        const entry = root.desktopEntryForWindow(cls, aid)
        let label = entry ? String(entry.name || "") : root.candidateLabel(key, tl.title)
        if (!label) label = key
        // byName in the order pass below would drop a colliding entry.
        if (used[label]) label = key
        if (used[label]) continue
        used[label] = true
        apps.push({
          entryId: "",
          pinned: false,
          runningOnly: true,
          name: label,
          icon: entry ? String(entry.icon || "") : root.candidateIcon(key, cls, aid),
          cmd: "",
          matchTitle: "",
          appId: aid || cls,
          minimizable: true,
          spacer: false,
        })
      }
    }

    if (savedOrder.length > 0) {
      let byName = {}
      for (const app of apps) byName[app.name] = app
      let sorted = []
      for (const name of savedOrder) {
        if (byName[name]) {
          sorted.push(byName[name])
          delete byName[name]
        }
      }
      for (const app of apps) if (byName[app.name]) sorted.push(app)
      apps = sorted
    }

    appModel.clear()
    for (const app of apps) {
      if (hiddenApps.indexOf(app.name) >= 0) continue
      if (app.entryId && hiddenApps.indexOf(app.entryId) >= 0) continue
      appModel.append(app)
    }
  }

  function persistOrder() {
    let names = []
    for (var i = 0; i < appModel.count; i++) {
      // Transient running-only entries never belong in order.json.
      if (appModel.get(i).runningOnly) continue
      names.push(appModel.get(i).name)
    }
    savedOrder = names
    orderFile.setText(JSON.stringify(names, null, 2) + "\n")
  }

  // Called on every pointer move during a drag: figure out which slot the
  // dragged icon is currently over and shuffle the model if it changed.
  function updateDragTarget(fromIndex) {
    const desiredLeft = dragPointerX - dragGrabOffset
    let target = Math.round(desiredLeft / itemPitch)
    if (target < 0) target = 0
    if (target > appModel.count - 1) target = appModel.count - 1
    if (target !== fromIndex) appModel.move(fromIndex, target, 1)
  }

  function checkWorkspaceEmpty() {
    // Scoped to THIS dock's monitor, not the globally focused workspace.
    const wsId = root.monitorWsId
    if (wsId == null) return true
    try {
      const clients = JSON.parse(clientsJson)
      for (const c of clients) {
        if (c.workspace?.id !== wsId) continue
        if (DockApps.showOnFloating && c.floating) continue
        return false
      }
    } catch (e) {}
    return true
  }

  function updateWorkspaceEmpty() {
    const wsId = root.monitorWsId
    if (wsId == null) return

    var hasToplevels = false
    for (const tl of Hyprland.toplevels.values) {
      if (tl.workspace?.id === wsId) {
        hasToplevels = true
        break
      }
    }

    if (!hasToplevels) {
      if (workspaceEmpty !== true) workspaceEmpty = true
      return
    }

    if (!DockApps.showOnFloating) {
      if (workspaceEmpty !== false) workspaceEmpty = false
      return
    }

    if (!clientsProcess.running) {
      clientsJson = ""
      clientsProcess.running = true
    }
  }

  onClientsJsonChanged: {
    if (clientsJson.length === 0) return
    const empty = checkWorkspaceEmpty()
    if (empty !== workspaceEmpty) workspaceEmpty = empty
  }

  // Tokenizes an XDG desktop-entry Exec value per the freedesktop spec:
  // split on unquoted whitespace, honor double quotes (where \ escapes
  // " \ $ `), single quotes (fully literal), and backslash escapes.
  // A plain split(/\s+/) corrupts any argument containing a quoted space.
  function execTokenize(exec) {
    const parts = []
    let cur = "", has = false, i = 0
    while (i < exec.length) {
      const c = exec[i]
      if (c === " " || c === "\t") {
        if (has) { parts.push(cur); cur = ""; has = false }
        i++
        continue
      }
      if (c === '"') {
        has = true; i++
        while (i < exec.length && exec[i] !== '"') {
          if (exec[i] === "\\" && '"\\$`'.includes(exec[i + 1] ?? "")) i++
          cur += exec[i++] ?? ""
        }
        i++
        continue
      }
      if (c === "'") {
        has = true; i++
        while (i < exec.length && exec[i] !== "'") cur += exec[i++]
        i++
        continue
      }
      if (c === "\\" && exec[i + 1]) { cur += exec[i + 1]; i += 2; has = true; continue }
      cur += c; has = true; i++
    }
    if (has) parts.push(cur)
    return parts
  }

  function getUnreadCount(toplevels) {
    for (const tl of toplevels) {
      const title = tl.toplevel?.title || ""
      const m = title.match(/Inbox \((\d[\d,]*)\)/)
      if (m) {
        const n = parseInt(m[1].replace(/,/g, ""), 10)
        if (!isNaN(n) && n > 0) return n
      }
    }
    return 0
  }

  function getToplevelsForApp(app) {
    // Spacers never match a window; an empty cmd would otherwise match all.
    if (app.spacer) return []
    let results = []
    for (const tl of Hyprland.toplevels.values) {
      let matched = false
      if (app.match) {
        const title = tl.title.toLowerCase()
        if (title.includes(app.match.toLowerCase())) matched = true
      } else if (app.appId) {
        const needle = app.appId.toLowerCase()
        const appId = (tl.wayland?.appId ?? "").toLowerCase()
        const cls = (tl.lastIpcObject?.class ?? "").toLowerCase()
        // Class fallback: XWayland windows often report an empty wayland appId,
        // and running-only entries key on class.
        if (appId.includes(needle) || cls.includes(needle)) matched = true
      } else if (app.cmd) {
        const exe = root.execTokenize(app.cmd)[0].split("/").pop().replace(/\.[^/.]+$/, "").toLowerCase()
        const appId = (tl.wayland?.appId ?? "").toLowerCase()
        const cls = (tl.lastIpcObject?.class ?? "").toLowerCase()
        if (appId.includes(exe) || cls.includes(exe) || (cls && exe.includes(cls))) matched = true
      }
      if (matched) {
        results.push({ toplevel: tl, pid: tl.lastIpcObject?.pid ?? -1 })
      }
    }
    return results
  }

  function openContextMenu(item) {
    if (root.contextOpen && root.contextKey === (item.entryId || item.name)) {
      root.closeContextMenu()
      return
    }
    root.closePinMenu()
    // Pinned apps unpin by desktop id; config apps have none, so they unpin by
    // name and the pin tool suppresses them instead of editing UserConfig.qml.
    root.contextKey = item.entryId || item.name
    root.contextAppData = item.appData
    root.contextRunning = item.isRunning
    root.contextAnchorX = dockBar.mapFromItem(item, item.width / 2, 0).x
    root.contextOpen = true
  }

  function closeContextMenu() {
    root.contextOpen = false
    if (!root.mouseOverDockArea) root.scheduleHide()
  }

  // class/appId (and raw title fallback) → display name via the desktop Name
  // cache. Shared by the pin menu and running-only bar entries.
  function candidateLabel(key, title) {
    const map = root.desktopNameMap
    let label = key
    if (map) {
      const lower = key.toLowerCase()
      // Direct class/appId match
      if (map[lower] && map[lower].name) label = map[lower].name
      else {
        // For chrome-host webapps also try host substring (e.g. google.com)
        const m = lower.match(/-([a-z0-9.-]+\.[a-z]+)__/)
        if (m && map[m[1]] && map[m[1]].name) label = map[m[1]].name
      }
      // Final fallback: window title is more readable than raw class
      if (label === key) {
        const t = (title || "").trim()
        if (t && t.length < 60) label = t
      }
    }
    return label
  }

  // Desktop Icon= for a class/appId via the dump-map cache; falls back to
  // the chrome-host heuristic then the raw class (iconPath may still miss).
  function candidateIcon(key, cls, appId) {
    const map = root.desktopNameMap
    if (map && key) {
      const lower = key.toLowerCase()
      if (map[lower] && map[lower].icon) return map[lower].icon
      const m = lower.match(/-([a-z0-9.-]+.[a-z]+)__/)
      if (m && map[m[1]] && map[m[1]].icon) return map[m[1]].icon
    }
    return root.pinCandidateIcon({ cls: cls, appId: appId })
  }

  // Window class/appId → DesktopEntry, same source the Omarchy app menu uses.
  // id → StartupWMClass → Exec basename (all case-insensitive).
  function desktopEntryForWindow(cls, aid) {
    const idKey = String(aid || "")
    const clsKey = String(cls || "")
    if (idKey) {
      const byAid = DesktopEntries.byId(idKey)
      if (byAid) return byAid
    }
    if (clsKey && clsKey !== idKey) {
      const byCls = DesktopEntries.byId(clsKey)
      if (byCls) return byCls
    }
    const key = (clsKey || idKey).toLowerCase()
    if (!key) return null
    const vals = DesktopEntries.applications.values || []
    for (const e of vals) {
      if (!e) continue
      if (String(e.id).toLowerCase() === key) return e
      if (String(e.startupClass || "").toLowerCase() === key) return e
      const bin = String(e.execString || "").split(/[\s]+/)[0].split("/").pop().toLowerCase()
      if (bin && bin === key) return e
    }
    return null
  }

  // Omarchy AppLibrary.iconSource replica (plugin shell.appLibrary is null
  // without kind "menu"): absolute/file URL → disk index → themed → generic.
  // Never returns empty, so an Image source can't go blank.
  function entryIconSource(icon) {
    var v = String(icon || "")
    if (v.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return Util.fileUrl(v)
    var found = root.iconDiskIndex[v]
    if (found) return Util.fileUrl(found)
    var themed = Quickshell.iconPath(v, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Same scan as AppLibrary.iconIndexScanCommand: app/device icons across
  // XDG icon dirs + /usr/share/pixmaps, SVG lines before PNG so the parser
  // (first hit per name wins) prefers scalable icons.
  function iconIndexScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  function indexIconLine(line) {
    var file = String(line || "").trim()
    if (file.length === 0) return
    var slash = file.lastIndexOf("/")
    var base = slash >= 0 ? file.slice(slash + 1) : file
    var dot = base.lastIndexOf(".")
    var name = dot > 0 ? base.slice(0, dot) : base
    if (name.length > 0 && root.pendingIconDiskIndex[name] === undefined)
      root.pendingIconDiskIndex[name] = file
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", root.iconIndexScanCommand()]
    stdout: SplitParser {
      onRead: function(line) { root.indexIconLine(line) }
    }
    onStarted: root.pendingIconDiskIndex = ({})
    // Swapping the property re-evaluates every entryIconSource() binding.
    onExited: root.iconDiskIndex = root.pendingIconDiskIndex
  }

  // Running apps that no dock icon claims, deduped by class/appId. A toplevel
  // counts as claimed when any configured or pinned app matches it. Labels
  // are resolved synchronously via desktopNameMap (cached) so the menu
  // opens with correct names and no flash.
  function buildPinCandidates() {
    let claimed = []
    for (let i = 0; i < appModel.count; i++) {
      const m = appModel.get(i)
      const tls = root.getToplevelsForApp({ match: m.matchTitle, appId: m.appId, cmd: m.cmd })
      for (const t of tls) claimed.push(t.toplevel)
    }
    const seen = {}
    const out = []
    for (const tl of Hyprland.toplevels.values) {
      if (claimed.indexOf(tl) >= 0) continue
      const cls = tl.lastIpcObject?.class ?? ""
      const aid = tl.wayland?.appId ?? ""
      const key = cls || aid
      if (!key || seen[key]) continue
      seen[key] = true
      const entry = root.desktopEntryForWindow(cls, aid)
      out.push({
        label: (entry && entry.name) ? String(entry.name) : root.candidateLabel(key, tl.title),
        icon: entry ? String(entry.icon || "") : root.candidateIcon(key, cls, aid),
        cls: cls,
        appId: aid,
      })
    }
    // Stable alphabetical order so the list does not reshuffle after resolve.
    out.sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase()))
    return out
  }

  // Resolves an icon name for the pin menu. Webapps report a synthetic class
  // like chrome-web.whatsapp.com__-Default which has no icon theme entry;
  // the host's second-level domain (whatsapp) does. Fall back to that so the
  // menu doesn't show a blank icon while the pinned dock icon (resolved via
  // the desktop file) will be correct.
  function pinCandidateIcon(entry) {
    if (entry.empty) return ""
    const raw = entry.cls || entry.appId || ""
    if (!raw) return ""
    const lower = raw.toLowerCase()
    const m = lower.match(/-([a-z0-9.-]+.[a-z]+)__/)
    if (m) {
      const host = m[1]
      const parts = host.split(".")
      const ignore = ["www", "com", "net", "org", "io", "co", "app", "chrome"]
      for (let i = parts.length - 1; i >= 0; i--) {
        const p = parts[i]
        if (!p || ignore.includes(p)) continue
        return p
      }
    }
    return raw
  }

  function openPinMenu(xInBar) {
    if (root.pinMenuOpen) {
      root.closePinMenu()
      return
    }
    root.closeContextMenu()
    root.closeHoverMenu()
    // Lazy one-time map: first open builds the cache, then reopens.
    if (root.desktopNameMap === null) {
      if (!root.desktopMapLoading) {
        root.desktopMapLoading = true
        root.pendingPinAnchorX = xInBar
        root.pendingPinOpen = true
        desktopMapProcess.running = true
      } else {
        // Already loading (started at init) — queue this open.
        root.pendingPinAnchorX = xInBar
        root.pendingPinOpen = true
      }
      return
    }
    root.pinCandidates = root.buildPinCandidates()
    root.pinMenuAnchorX = xInBar
    root.pinMenuExpanded = false
    root.pinMenuOpen = true
    // Cache miss fallback: a desktop file created after the map was built
    // will still have a raw label; resolve just those in background.
    if (root.pinCandidates.length > 0) {
      var misses = []
      for (var i = 0; i < root.pinCandidates.length; i++) {
        var c = root.pinCandidates[i]
        var key = c.cls || c.appId
        if (key && c.label === key) misses.push(key)
      }
      if (misses.length > 0) {
        resolveProcess.command = [root.pinTool, "--resolve-windows"].concat(misses)
        resolveProcess.running = true
      }
    }
  }

  function closePinMenu() {
    root.pinMenuOpen = false
    root.pinMenuExpanded = false
    if (!root.mouseOverDockArea) root.scheduleHide()
  }

  function openSettings(anchorX) {
    root.closePinMenu()
    root.settingsAnchorX = dockBar.x + anchorX
    root.settingsOpen = true
  }

  function closeSettings() {
    root.settingsOpen = false
    if (!root.mouseOverDockArea) root.scheduleHide()
  }

  // One-time desktop Name cache. Built at startup so first pin-menu open
  // is synchronous (no flash, no stutter). Also used as fallback if a
  // later menu opens before the map is ready.
  Process {
    id: desktopMapProcess
    command: [root.pinTool, "--dump-map"]
    stdout: StdioCollector {
      onStreamFinished: {
        const map = {}
        for (const line of this.text.trim().split("\n")) {
          if (!line) continue
          const parts = line.split("\t")
          if (parts.length >= 2) map[parts[0]] = { name: parts[1], icon: parts[2] || "" }
        }
        root.desktopNameMap = map
        root.desktopMapLoading = false
        // Running-only labels fall back to raw class until this cache lands.
        if (root.showRunningUnpinned && !root.dragging) root.rebuildModel()
        if (root.pendingPinOpen) {
          root.pendingPinOpen = false
          root.pinCandidates = root.buildPinCandidates()
          root.pinMenuAnchorX = root.pendingPinAnchorX
          root.pinMenuExpanded = false
          root.pinMenuOpen = true
        }
      }
    }
  }

  // Fallback per-open resolver for cache misses (e.g. a desktop file
  // created after the map was built). Kept for correctness, rarely hit.
  Process {
    id: resolveProcess
    stdout: StdioCollector {
      onStreamFinished: {
        const lines = this.text.trim().split("\n")
        const resolved = {}
        for (const line of lines) {
          const parts = line.split("\t")
          if (parts.length >= 2) resolved[parts[1]] = parts[0]
        }
        const updated = []
        for (const c of root.pinCandidates) {
          const name = resolved[c.cls] || resolved[c.appId] || c.label
          updated.push({ label: name, icon: c.icon || "", cls: c.cls, appId: c.appId })
        }
        root.pinCandidates = updated
        // Also backfill the cache so next open is instant.
        if (root.desktopNameMap) {
          for (const k in resolved) root.desktopNameMap[k.toLowerCase()] = { name: resolved[k], icon: "" }
        }
      }
    }
  }

  function runPinAction(entry) {
    root.closePinMenu()
    const key = entry.cls || entry.appId
    if (!key) return
    Quickshell.execDetached([root.pinTool, "--pin-window", key])
    root.maybeHideAfterAction()
  }

  function runContextAction(act) {
    const app = root.contextAppData
    root.closeContextMenu()
    if (!app) return

    if (act === "new") {
      Quickshell.execDetached(root.execTokenize(app.cmd))
    } else if (act === "pin") {
      Quickshell.execDetached([root.pinTool, "--pin-window", app.appId || app.name])
    } else if (act === "quit") {
      for (const t of root.getToplevelsForApp(app)) {
        let addr = t.toplevel.lastIpcObject?.address
        if (!addr || addr === "0") addr = "0x" + t.toplevel.address
        if (addr && addr !== "0x0") {
          Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + addr + '" })')
        }
      }
    } else if (act === "unpin" && root.contextKey) {
      // The CLI owns pins.json and hidden.json; the watchers pick the change up.
      Quickshell.execDetached([root.pinTool, "--unpin", root.contextKey])
      // The icon is gone and the pointer sits on now-empty bar; without this
      // the hover handoff keeps the dock up indefinitely.
      root.maybeHideAfterAction()
    }
  }

  function focusWindow(address) {
    if (!address || address === "0x0") return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  // macOS-style magnification: scale falls off with distance from the cursor
  // slot. Computed against the *base* (unmagnified) layout so a growing icon
  // can't move its own target and oscillate. Apps are the leading Row children,
  // so app `i`'s base centre is `i*itemPitch + itemSize/2` from the content's
  // left edge, and the content is centered in the window.
  // Base (unmagnified) width of appModel row `i` — spacers render narrower.
  function appBaseWidth(i) {
    return appModel.get(i).spacer ? spacerWidth : itemSize
  }

  // Total base width of the Row: every app/spacer + the separator + trash,
  // with one itemSpacing between each adjacent pair.
  function baseContentWidth() {
    let w = 0
    for (let i = 0; i < appModel.count; i++) w += appBaseWidth(i)
    return w + (appModel.count + 1) * itemSpacing + separatorWidth + trashWidth
  }

  function magnifyForIndex(i) {
    if (!magnifyActive || appModel.count === 0) return 1
    if (appModel.get(i).spacer) return 1
    const baseLeft = root.width / 2 - baseContentWidth() / 2
    let off = 0
    for (let j = 0; j < i; j++) off += appBaseWidth(j) + itemSpacing
    const dist = Math.abs(cursorSceneX - (baseLeft + off + itemSize / 2))
    if (dist >= magnifyRadius) return 1
    const t = 1 - dist / magnifyRadius
    return 1 + (magnifyMaxScale - 1) * t * t
  }

  function showDockBar() {
    hideTimer.stop()
    dockVisible = true
  }

  function scheduleHide() {
    if (dockMode === "always") return
    hideTimer.restart()
  }

  // After focusing/launching/unpinning: drop the dock when the mode calls for
  // it, using the same rules as the hide timer.
  function maybeHideAfterAction() {
    if (dockMode === "always") return
    if (dockMode === "autohide") {
      if (!root.mouseOverDockArea) root.dockVisible = false
      return
    }
    if (!root.workspaceEmpty) root.dockVisible = false
  }

  onMouseOverDockAreaChanged: {
    if (mouseOverDockArea) {
      contextCloseTimer.stop()
      hoverCloseTimer.stop()
      pinMenuCloseTimer.stop()
      settingsCloseTimer.stop()
    } else {
      contextCloseTimer.restart()
      hoverCloseTimer.restart()
      pinMenuCloseTimer.restart()
      settingsCloseTimer.restart()
      root.hoverName = ""
      scheduleHide()
    }
  }

  onWorkspaceEmptyChanged: {
    if (dockMode === "always") { showDockBar(); return }
    if (dockMode === "smart") {
      if (workspaceEmpty) showDockBar()
      else scheduleHide()
    }
  }

  onDockModeChanged: {
    if (dockMode === "always") { showDockBar(); return }
    if (dockMode === "autohide") {
      if (!mouseOverDockArea && !dragging && !contextOpen && !hoverMenuOpen
          && !pinMenuOpen && !settingsOpen) {
        hideTimer.stop()
        dockVisible = false
      }
      return
    }
    // smart
    if (workspaceEmpty) showDockBar()
    else scheduleHide()
  }

  onContextOpenChanged: {
    if (contextOpen) closeHoverMenu()
  }

  onDockVisibleChanged: {
    if (!dockVisible) closeHoverMenu()
  }

  Component.onCompleted: {
    readStateFile("order", root.orderPath)
    readStateFile("pins", root.pinsPath)
    readStateFile("hidden", root.hiddenPath)
    readStateFile("settings", root.settingsPath)
    rebuildModel()
    updateWorkspaceEmpty()
    // Build desktop Name cache in background so first pin-menu open is
    // synchronous (no flash, no stutter).
    if (root.desktopNameMap === null && !root.desktopMapLoading) {
      root.desktopMapLoading = true
      desktopMapProcess.running = true
    }
    // Disk icon index so themed misses (e.g. Icon=x) resolve like the menu.
    if (!iconIndexScan.running) iconIndexScan.running = true
  }

  Connections {
    target: DockApps
    function onAppsChanged() {
      if (!root.dragging) root.rebuildModel()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (["workspace", "workspacev2", "activewindow", "activewindowv2",
           "createworkspace", "createworkspacev2",
            "destroyworkspace", "destroyworkspacev2",
            "focusedmon", "focusedmonv2", "moveworkspacev2"].includes(event.name)) {
        updateWorkspaceEmpty()
        closeHoverMenu()
        closePinMenu()
        closeSettings()
      }
      if (event.name === "windowtitle") {
        root._badgeTick++
      }
      if (event.name === "openwindow" || event.name === "closewindow") {
        // Event may arrive before Quickshell registers the toplevel or the
        // monitor's activeWorkspace updates; 80ms settles and coalesces bursts.
        stateRefreshTimer.restart()
      }
    }
  }

  Timer {
    id: stateRefreshTimer
    interval: 80
    repeat: false
    onTriggered: {
      root.updateWorkspaceEmpty()
      if (root.showRunningUnpinned && !root.dragging) root.rebuildModel()
    }
  }

  Rectangle {
    id: triggerStrip
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: dockBar.horizontalCenter
    // hot area plus some fat finger margin
    width: dockBar.width + 80
    height: 4
    color: "transparent"

    HoverHandler {
      id: triggerHover
      onHoveredChanged: hovered ? root.showDockBar() : root.scheduleHide()
    }
  }

  Timer {
    id: hideTimer
    interval: 500
    repeat: false
    onTriggered: {
      if (root.dockMode === "always") return
      if (root.mouseOverDockArea || root.dragging || root.contextOpen || root.hoverMenuOpen || root.pinMenuOpen || root.settingsOpen) return
      if (root.dockMode === "smart" && root.workspaceEmpty) return
      root.dockVisible = false
    }
  }

  Rectangle {
    id: dockBar
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: root.gap - root.dockHeight - 20

    implicitWidth: row.implicitWidth + 24
    implicitHeight: row.implicitHeight + 24

    // Translucent so the Hyprland layer blur (looknfeel.lua) reads as glass.
    // Alpha follows the active theme's bar surface.
    color: Util.alpha(Color.bar.background, root.glassAlpha)
    radius: 18
    border.color: Qt.alpha(Color.foreground, 0.18)
    border.width: 1

    states: State {
      name: "visible"
      when: root.dockVisible
      PropertyChanges {
        target: dockBar
        anchors.bottomMargin: root.elevationMargin + root.gap
      }
    }

    transitions: Transition {
      NumberAnimation {
        property: "anchors.bottomMargin"
        duration: 200
        easing.type: Easing.InOutQuad
      }
    }

    Rectangle {
      anchors.fill: parent
      anchors.topMargin: 4
      radius: 18
      color: "#000000"
      opacity: 0.3
      z: -1
    }

    HoverHandler {
      id: dockHover
      onHoveredChanged: {
        if (hovered) {
          hideTimer.stop()
        } else {
          root.cursorSceneX = -10000
          root.scheduleHide()
        }
      }
      onPointChanged: root.cursorSceneX = point.scenePosition.x
    }

    TapHandler {
      acceptedButtons: Qt.RightButton
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onSingleTapped: root.openPinMenu(point.position.x)
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: root.itemSpacing

      // Icons displaced by a drag slide to their new slot. Set duration to 0
      // for fully instant reordering.
      move: Transition {
        NumberAnimation { properties: "x"; duration: 120; easing.type: Easing.OutCubic }
      }

      Repeater {
        id: appRepeater
        model: appModel

        delegate: Item {
          id: appItem

          required property int index
          required property string entryId
          required property bool pinned
          required property string name
          required property string icon
          required property string cmd
          required property string matchTitle
          required property string appId
          required property bool minimizable
          required property bool runningOnly
          required property bool spacer

          readonly property var appData: ({
            name: appItem.name,
            icon: appItem.icon,
            cmd: appItem.cmd,
            match: appItem.matchTitle,
            appId: appItem.appId,
            minimizable: appItem.minimizable,
            runningOnly: appItem.runningOnly,
            spacer: appItem.spacer,
          })

          readonly property bool isDragged: root.dragName === appItem.name
          readonly property real magnifyScale: appItem.spacer ? 1 : root.magnifyForIndex(appItem.index)

          width: appItem.spacer ? root.spacerWidth : Math.round(root.itemSize * magnifyScale)
          height: appItem.spacer ? 1 : width
          z: isDragged ? 10 : 0
          Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

          // Glued to the pointer while dragged. Because this reads appItem.x,
          // it re-solves whenever the Row re-lays the icon out mid-drag, so
          // the icon stays under the cursor through a reorder.
          transform: Translate {
            x: appItem.isDragged ? root.dragPointerX - root.dragGrabOffset - appItem.x : 0
          }

          property bool busy: false
          // macOS launch bounce: the icon hops while the app is starting.
          property real bounceOffset: 0

          SequentialAnimation {
            running: appItem.busy && !appItem.isRunning
            loops: Animation.Infinite
            NumberAnimation { target: appItem; property: "bounceOffset"; from: 0; to: -10; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: appItem; property: "bounceOffset"; from: -10; to: 0; duration: 160; easing.type: Easing.InQuad }
          }

          // Debounce guard against double-launch. Normally cleared when a
          // matching toplevel appears; this timer is the fallback for a launch
          // that never produces one (bad binary, instant crash), so the icon
          // can't stay dead until the next shell restart.
          Timer {
            interval: 5000
            running: appItem.busy
            onTriggered: appItem.busy = false
          }

          readonly property var toplevels: root.getToplevelsForApp(appItem.appData)
          readonly property bool isRunning: toplevels.length > 0
          readonly property int pid: isRunning ? toplevels[0].pid : 0
          readonly property int unreadCount: {
            var _ = root._badgeTick
            if (!isRunning) return 0
            return root.getUnreadCount(toplevels)
          }

          HoverHandler {
            id: itemHover
            enabled: !appItem.spacer
            onHoveredChanged: {
              if (hovered) {
                // Switching icons must drop the previous icon's window list:
                // hoverCloseTimer only fires once the pointer leaves the whole
                // dock area, so it can't handle icon-to-icon moves.
                if (root.hoverMenuOpen && root.hoverMenuKey !== appItem.name)
                  root.closeHoverMenu()
                if (appItem.toplevels.length >= 2 && !root.contextOpen && !root.pinMenuOpen) {
                  root.hoverMenuKey = appItem.name
                  root.hoverMenuWindows = appItem.toplevels.map(t => ({
                    title: t.toplevel.title || appItem.name,
                    address: t.toplevel.lastIpcObject?.address || ("0x" + t.toplevel.address)
                  }))
                  root.hoverMenuAnchorX = row.mapFromItem(appItem, appItem.width / 2, 0).x
                  hoverDelayTimer.restart()
                } else if (!root.contextOpen && !root.pinMenuOpen) {
                  // Single-window app: show the name bubble instead.
                  root.hoverName = appItem.name
                  root.hoverNameAnchorX = row.mapFromItem(appItem, appItem.width / 2, 0).x
                }
              } else {
                if (root.hoverName === appItem.name) root.hoverName = ""
                hoverCloseTimer.restart()
              }
            }
          }

          Rectangle {
            visible: !appItem.spacer
            anchors.fill: parent
            anchors.margins: 2
            radius: 12
            color: Color.foreground
            opacity: appItem.isDragged ? 0.22 : (itemHover.hovered ? 0.15 : 0)
            Behavior on opacity { NumberAnimation { duration: 150 } }
          }

          DragHandler {
            id: dragHandler
            target: null
            yAxis.enabled: false
            enabled: !appItem.spacer

            onActiveChanged: {
              if (active) {
                hideTimer.stop()
                root.closeHoverMenu()
                const p = row.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
                root.dragPointerX = p.x
                root.dragGrabOffset = p.x - appItem.x
                root.dragName = appItem.name
              } else {
                root.dragName = ""
                root.persistOrder()
                if (!root.mouseOverDockArea) root.scheduleHide()
              }
            }

            onCentroidChanged: {
              if (!active) return
              const p = row.mapFromItem(null, centroid.scenePosition.x, centroid.scenePosition.y)
              root.dragPointerX = p.x
              root.updateDragTarget(appItem.index)
            }
          }

          TapHandler {
            acceptedButtons: Qt.RightButton
            enabled: !appItem.spacer
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onSingleTapped: {
              root.closeHoverMenu()
              root.openContextMenu(appItem)
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            enabled: !appItem.spacer
            // Releases the press to the DragHandler once the pointer moves
            // past the drag threshold, so a drag never fires a launch.
            gesturePolicy: TapHandler.DragThreshold
            onSingleTapped: {
              root.closeHoverMenu()
              if (root.contextOpen) {
                root.closeContextMenu()
                return
              }
              var cmdParts = root.execTokenize(appItem.cmd)
              if (appItem.isRunning) {
                var minimizable = appItem.minimizable
                if (minimizable) {
                  var anyOnCurrent = false
                  var anyOnSpecial = false
                  var ws = root.monitorWsId
                  for (var _i = 0; _i < appItem.toplevels.length; _i++) {
                    var tws = appItem.toplevels[_i].toplevel.workspace?.id
                    if (tws === ws) anyOnCurrent = true
                    if (tws != null && tws < 0) anyOnSpecial = true
                  }

                  if (anyOnCurrent) {
                    for (var _j = 0; _j < appItem.toplevels.length; _j++) {
                      var tl = appItem.toplevels[_j].toplevel
                      if (tl.workspace?.id !== ws) continue
                      var addr = tl.lastIpcObject?.address
                      if (!addr || addr === "0") addr = "0x" + tl.address
                      if (addr && addr !== "0x0") {
                        Hyprland.dispatch('hl.dsp.window.move({ workspace = "special:dock_minimize", follow = false, window = "address:' + addr + '" })')
                      }
                    }
                    root.maybeHideAfterAction()
                    return
                  }

                  if (anyOnSpecial) {
                    for (var _k = 0; _k < appItem.toplevels.length; _k++) {
                      var tl = appItem.toplevels[_k].toplevel
                      if (tl.workspace?.id == null || tl.workspace.id >= 0) continue
                      var addr = tl.lastIpcObject?.address
                      if (!addr || addr === "0") addr = "0x" + tl.address
                      if (addr && addr !== "0x0") {
                        Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + (ws ?? 1) + ', window = "address:' + addr + '" })')
                      }
                    }
                    var addr = appItem.toplevels[0].toplevel.lastIpcObject?.address
                    if (!addr || addr === "0") addr = "0x" + appItem.toplevels[0].toplevel.address
                    if (addr && addr !== "0x0") {
                      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
                    } else {
                      var cls = appItem.toplevels[0].toplevel.lastIpcObject?.class
                      if (cls) Hyprland.dispatch('hl.dsp.focus({ window = "class:' + cls + '" })')
                    }
                    return
                  }
                }

                var addr = appItem.toplevels[0].toplevel.lastIpcObject?.address
                if (!addr || addr === "0") addr = "0x" + appItem.toplevels[0].toplevel.address
                if (addr && addr !== "0x0") {
                  Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
                } else {
                  var cls = appItem.toplevels[0].toplevel.lastIpcObject?.class
                  if (cls) Hyprland.dispatch('hl.dsp.focus({ window = "class:' + cls + '" })')
                }
                root.maybeHideAfterAction()
              } else if (!appItem.busy && !appItem.runningOnly) {
                appItem.busy = true
                Quickshell.execDetached(cmdParts)
              }
            }
          }

          onIsRunningChanged: {
            if (isRunning) busy = false
          }

          Image {
            id: iconImg
            visible: !appItem.spacer
            anchors.centerIn: parent
            // Rides the magnified item size (54 → 40 keeps the original look)
            // and the launch bounce.
            anchors.verticalCenterOffset: appItem.bounceOffset
            source: root.entryIconSource(appItem.icon)
            width: Math.round(appItem.width * 40 / root.defaultItemSize)
            height: width
            fillMode: Image.PreserveAspectFit
            opacity: appItem.isDragged ? 0.85 : 1
          }

          Rectangle {
            visible: appItem.isRunning && !appItem.spacer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -6
            width: 4
            height: 4
            radius: 2
            // Running-app indicator uses the theme accent.
            color: Color.accent
          }

          Rectangle {
            visible: appItem.unreadCount > 0 && !appItem.spacer
            anchors.top: parent.top
            anchors.topMargin: -4
            anchors.right: parent.right
            anchors.rightMargin: -4
            width: Math.max(18, badgeText.implicitWidth + 10)
            height: 18
            radius: 9
            // Unread badge uses the theme's urgent colour.
            color: Color.urgent
            border.color: Color.bar.background
            border.width: 1.5

            Text {
              id: badgeText
              anchors.centerIn: parent
              text: appItem.unreadCount > 99 ? "99+" : appItem.unreadCount.toString()
              // Numeric today, but derived from titles — keep it plain.
              textFormat: Text.PlainText
              color: "#ffffff"
              font.pixelSize: 10
              font.bold: true
            }
          }
        }
      }

      // macOS-style trailing separator + trash. Kept as Row children so the
      // bar's width, centering, and the magnification slots stay consistent.
      Rectangle {
        id: dockSeparator
        width: root.separatorWidth
        height: Math.round(root.itemSize * 0.6)
        color: Qt.alpha(Color.foreground, 0.18)
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        id: dockTrash
        width: root.trashWidth
        height: root.trashWidth

        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: 12
          color: Color.foreground
          opacity: trashHover.hovered ? 0.15 : 0
          Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        HoverHandler { id: trashHover }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onSingleTapped: Quickshell.execDetached(["nautilus", "trash:///"])
        }

        Image {
          anchors.centerIn: parent
          source: Quickshell.iconPath("user-trash", true)
          width: Math.round(root.itemSize * 40 / root.defaultItemSize)
          height: width
          fillMode: Image.PreserveAspectFit
        }
      }
    }
  }

  // macOS-style name bubble above the hovered single-window icon.
  Item {
    id: appLabel

    width: root.hoverName !== "" ? labelCard.width : 0
    height: root.hoverName !== "" ? labelCard.height : 0
    visible: root.hoverName !== ""

    anchors.bottom: dockBar.top
    anchors.bottomMargin: 6
    x: Math.max(0, Math.min(dockBar.x + root.hoverNameAnchorX - width / 2, root.width - width))

    Rectangle {
      id: labelCard
      implicitWidth: labelText.implicitWidth + 16
      implicitHeight: labelText.implicitHeight + 8
      color: Color.tooltip.background
      radius: 7
      border.color: Qt.alpha(Color.foreground, 0.18)
      border.width: 1

      Text {
        id: labelText
        anchors.centerIn: parent
        text: root.hoverName
        textFormat: Text.PlainText
        color: Color.tooltip.text
        font.pixelSize: 12
      }
    }
  }

  Timer {
    id: contextCloseTimer
    interval: 180
    repeat: false
    onTriggered: if (!root.mouseOverDockArea) root.closeContextMenu()
  }

  Timer {
    id: hoverDelayTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (!root.contextOpen && !root.pinMenuOpen) root.hoverMenuOpen = true
    }
  }

  Timer {
    id: hoverCloseTimer
    interval: 180
    repeat: false
    onTriggered: {
      if (!root.mouseOverDockArea && !windowMenuHover.hovered) root.closeHoverMenu()
    }
  }

  // The pin menu has no click-outside path (input outside the mask passes
  // through the layer surface), so leaving the dock area is the close signal,
  // same idiom as contextCloseTimer/hoverCloseTimer.
  Timer {
    id: pinMenuCloseTimer
    interval: 180
    repeat: false
    onTriggered: if (!root.mouseOverDockArea) root.closePinMenu()
  }

  Timer {
    id: settingsCloseTimer
    interval: 180
    repeat: false
    onTriggered: if (!root.mouseOverDockArea) root.closeSettings()
  }

  // Debounced write-through while a slider drags; one rename per gesture
  // instead of one per pixel.
  Timer {
    id: settingsSaveTimer
    interval: 400
    repeat: false
    onTriggered: root.persistSettings()
  }

  function closeHoverMenu() {
    hoverDelayTimer.stop()
    hoverCloseTimer.stop()
    hoverMenuOpen = false
    root.hoverName = ""
    if (!root.mouseOverDockArea) root.scheduleHide()
  }

  Item {
    id: contextMenu

    // Collapsed to nothing when closed so it contributes no input region.
    width: root.contextOpen ? contextCard.width : 0
    height: root.contextOpen ? contextCard.height : 0
    visible: root.contextOpen

    anchors.bottom: dockBar.top
    anchors.bottomMargin: 2
    x: Math.max(0, Math.min(dockBar.x + root.contextAnchorX - width / 2, root.width - width))

    HoverHandler { id: contextHover }

    Rectangle {
      id: contextCard

      implicitWidth: Math.max(150, widthProbe.implicitWidth + 24)
      implicitHeight: contextColumn.implicitHeight + 16

      color: Color.menu.background
      radius: 10
      border.color: Qt.alpha(Color.foreground, 0.18)
      border.width: 1

      Column {
        id: contextColumn
        anchors.centerIn: parent
        spacing: 1

        Repeater {
          model: root.contextActions

          delegate: Rectangle {
            required property var modelData

            width: contextCard.width - 8
            height: 26
            radius: 6
            color: rowHover.hovered ? Color.menu.selectedBackground : "transparent"

            HoverHandler { id: rowHover }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              onSingleTapped: root.runContextAction(modelData.act)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 8
              text: modelData.label
              color: Color.menu.text
              font.pixelSize: 12
            }
          }
        }
      }

      // Sizes the card without reading the Column back, which would be a
      // polish loop since the rows take their width from the card.
      Text {
        id: widthProbe
        visible: false
        text: "Open new window"
        font.pixelSize: 12
      }
    }
  }

  Item {
    id: windowMenu

    width: root.hoverMenuOpen ? windowCard.width : 0
    height: root.hoverMenuOpen ? windowCard.height : 0
    visible: root.hoverMenuOpen

    anchors.bottom: dockBar.top
    anchors.bottomMargin: 2
    x: Math.max(0, Math.min(dockBar.x + root.hoverMenuAnchorX - width / 2, root.width - width))

    HoverHandler { id: windowMenuHover }

    Rectangle {
      id: windowCard

      // Capped so long titles elide instead of stretching the menu; the
      // probe alone would size the card to the longest title in full.
      implicitWidth: Math.max(150, Math.min(windowWidthProbe.implicitWidth + 24, 320))
      implicitHeight: windowColumn.implicitHeight + 16

      color: Color.menu.background
      radius: 10
      border.color: Qt.alpha(Color.foreground, 0.18)
      border.width: 1

      Column {
        id: windowColumn
        anchors.centerIn: parent
        spacing: 1

        Repeater {
          model: root.hoverMenuWindows

          delegate: Rectangle {
            required property var modelData

            width: windowCard.width - 8
            height: 26
            radius: 6
            color: windowRowHover.hovered ? Color.menu.selectedBackground : "transparent"

            HoverHandler { id: windowRowHover }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              onSingleTapped: {
                root.focusWindow(modelData.address)
                root.closeHoverMenu()
                root.maybeHideAfterAction()
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              x: 8
              text: modelData.title
              // Titles are app-controlled; AutoText would sniff markup and
              // let <img> etc. pull resources into the shell.
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
              elide: Text.ElideRight
              width: parent.width - 16
            }
          }
        }
      }

      Text {
        id: windowWidthProbe
        visible: false
        // Same untrusted titles as the rows above; invisible still parses.
        textFormat: Text.PlainText
        text: {
          var longest = ""
          for (var i = 0; i < root.hoverMenuWindows.length; i++) {
            if (root.hoverMenuWindows[i].title.length > longest.length) {
              longest = root.hoverMenuWindows[i].title
            }
          }
          return longest
        }
        font.pixelSize: 12
      }
    }
  }

  Item {
    id: pinMenu

    width: root.pinMenuOpen ? pinCard.width : 0
    height: root.pinMenuOpen ? pinCard.height : 0
    visible: root.pinMenuOpen

    anchors.bottom: dockBar.top
    anchors.bottomMargin: 2
    x: Math.max(0, Math.min(dockBar.x + root.pinMenuAnchorX - width / 2, root.width - width))

    HoverHandler { id: pinMenuHover }

    Rectangle {
      id: pinCard

      // +42 covers the app-icon column and the right-aligned pin glyph;
      // capped like the other cards so long names elide instead of stretching.
      implicitWidth: Math.max(150, Math.min(pinWidthProbe.implicitWidth + 24 + 42, 320))
      // +30: divider + Settings row under the list.
      implicitHeight: pinCardColumn.implicitHeight + 16

      color: Color.menu.background
      radius: 10
      border.color: Qt.alpha(Color.foreground, 0.18)
      border.width: 1

      Column {
        id: pinCardColumn
        anchors.centerIn: parent
        spacing: 1

        Flickable {
          id: pinFlick
          width: pinCard.width - 8
          // Cap at 8 rows (8*26+7*1 = 215) so the card never outgrows the
          // oversized window. Collapsed state shows 5 + "Show more" and fits
          // without scrolling.
          height: Math.min(pinColumn.implicitHeight, 215)
          clip: true
          contentHeight: pinColumn.implicitHeight
          flickableDirection: Flickable.VerticalFlick
          boundsBehavior: Flickable.StopAtBounds

          WheelHandler {
            onWheel: event => {
              if (pinFlick.contentHeight > pinFlick.height) {
                const dy = event.angleDelta.y > 0 ? -40 : 40
                pinFlick.contentY = Math.max(0, Math.min(pinFlick.contentHeight - pinFlick.height, pinFlick.contentY + dy))
                event.accepted = true
              }
            }
          }

        Column {
          id: pinColumn
          width: parent.width
          spacing: 1

          Repeater {
            model: root.pinCandidates.length > 0
              ? root.pinMenuVisibleCandidates
              : [{ label: "No unpinned apps running", empty: true }]

            delegate: Rectangle {
              required property var modelData

              width: pinColumn.width
              height: 26
              radius: 6
              color: !modelData.empty && pinRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: pinRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                enabled: !modelData.empty
                onSingleTapped: root.runPinAction(modelData)
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                spacing: 8

                Image {
                  source: modelData.empty ? "" : root.entryIconSource(modelData.icon || root.candidateIcon(modelData.cls || modelData.appId, modelData.cls, modelData.appId))
                  width: 16
                  height: 16
                  visible: !modelData.empty
                  anchors.verticalCenter: parent.verticalCenter
                  fillMode: Image.PreserveAspectFit
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  // Labels are window class/appId, i.e. outside data.
                  textFormat: Text.PlainText
                  color: modelData.empty ? Color.muted : Color.menu.text
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  // Reserve room for the pin glyph only on pinnable rows; the
                  // empty-state row has no icon column either.
                  width: modelData.empty ? pinCard.width - 40 : pinCard.width - 64
                }
              }

              Text {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                // Same glyph the pin tool uses for its notifications.
                text: "󰐃"
                color: pinRowHover.hovered ? Color.menu.text : Color.muted
                font.pixelSize: 13
                visible: !modelData.empty
              }
            }
          }

          Rectangle {
            visible: !root.pinMenuExpanded && root.pinMenuHasMore
            width: pinColumn.width
            height: visible ? 26 : 0
            radius: 6
            color: showMoreHover.hovered ? Color.menu.selectedBackground : "transparent"

            HoverHandler { id: showMoreHover }

            TapHandler {
              acceptedButtons: Qt.LeftButton
              onSingleTapped: root.pinMenuExpanded = true
            }

            Text {
              anchors.centerIn: parent
              text: "Show " + (root.pinCandidates.length - root.pinMenuPageSize) + " more…"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
          }
        }
      }

      Rectangle {
        width: pinCard.width - 16
        height: 1
        color: Qt.alpha(Color.foreground, 0.12)
      }

      Rectangle {
        width: pinCard.width - 8
        height: 26
        radius: 6
        color: settingsRowHover.hovered ? Color.menu.selectedBackground : "transparent"

        HoverHandler { id: settingsRowHover }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onSingleTapped: root.openSettings(root.pinMenuAnchorX)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          x: 8
          text: "Settings"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.pixelSize: 12
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          // Cogwheel (nf-cod gear), same nerd font as the pin glyph.
          text: ""
          color: settingsRowHover.hovered ? Color.menu.text : Color.muted
          font.pixelSize: 13
        }
      }
    }

    Text {
      id: pinWidthProbe
      visible: false
      text: "No unpinned apps running"
      font.pixelSize: 12
    }
  }
  }

  Item {
    id: settingsPanel

    width: root.settingsOpen ? settingsCard.width : 0
    height: root.settingsOpen ? settingsCard.height : 0
    visible: root.settingsOpen

    anchors.bottom: dockBar.top
    anchors.bottomMargin: 2
    // Absolute anchor (captured at open time) so the panel stays under the
    // cursor even while dockBar reflows underneath during slider drag.
    x: Math.max(0, Math.min(root.settingsAnchorX - width / 2, root.width - width))

    HoverHandler { id: settingsHover }

    Rectangle {
      id: settingsCard

      implicitWidth: 230
      implicitHeight: settingsColumn.implicitHeight + 24

      color: Color.menu.background
      radius: 10
      border.color: Qt.alpha(Color.foreground, 0.18)
      border.width: 1

      Column {
        id: settingsColumn
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 10

        Text {
          text: "Dock settings"
          textFormat: Text.PlainText
          color: Color.menu.text
          font.pixelSize: 13
          font.bold: true
        }

        Column {
          width: parent.width
          spacing: 6

          Item {
            width: parent.width
            height: 14
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Icon size"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: sizeSlider.value + " px"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: sizeSlider
            width: parent.width
            from: 32
            to: 96
            stepSize: 2
            value: root.itemSize
            onMoved: {
              root.itemSize = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: sizeSlider.leftPadding
              y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
              width: sizeSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: sizeSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: sizeSlider.leftPadding + sizeSlider.visualPosition * sizeSlider.availableWidth - width / 2
              y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.text
              border.color: Color.menu.background
              border.width: 1
            }
          }
        }

        Column {
          width: parent.width
          spacing: 6

          Item {
            width: parent.width
            height: 14
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Icon spacing"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: spacingSlider.value + " px"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: spacingSlider
            width: parent.width
            from: 0
            to: 48
            stepSize: 2
            value: root.itemSpacing
            onMoved: {
              root.itemSpacing = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: spacingSlider.leftPadding
              y: spacingSlider.topPadding + spacingSlider.availableHeight / 2 - height / 2
              width: spacingSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: spacingSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: spacingSlider.leftPadding + spacingSlider.visualPosition * spacingSlider.availableWidth - width / 2
              y: spacingSlider.topPadding + spacingSlider.availableHeight / 2 - height / 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.text
              border.color: Color.menu.background
              border.width: 1
            }
          }
        }

        Column {
          width: parent.width
          spacing: 6

          Item {
            width: parent.width
            height: 14
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Spacer width"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: spacerSlider.value + " px"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: spacerSlider
            width: parent.width
            from: 0
            to: 96
            stepSize: 2
            value: root.spacerWidth
            onMoved: {
              root.spacerWidth = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: spacerSlider.leftPadding
              y: spacerSlider.topPadding + spacerSlider.availableHeight / 2 - height / 2
              width: spacerSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: spacerSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: spacerSlider.leftPadding + spacerSlider.visualPosition * spacerSlider.availableWidth - width / 2
              y: spacerSlider.topPadding + spacerSlider.availableHeight / 2 - height / 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.text
              border.color: Color.menu.background
              border.width: 1
            }
          }
        }

        Text {
          text: "Visibility"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { mode: "always", label: "Fixa (sempre visível)" },
              { mode: "autohide", label: "Auto-hide (revela no hover)" },
              { mode: "smart", label: "Inteligente (por workspace)" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: modeRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: modeRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  root.dockMode = modelData.mode
                  root.persistSettings()
                }
              }

              Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 6
                spacing: 8

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 12
                  height: 12
                  radius: 6
                  color: "transparent"
                  border.color: Qt.alpha(Color.foreground, 0.45)
                  border.width: 1

                  Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: Color.foreground
                    visible: root.dockMode === modelData.mode
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  textFormat: Text.PlainText
                  color: Color.menu.text
                  font.pixelSize: 12
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          text: "Fixa nunca esconde. Auto-hide revela pela borda inferior. Inteligente mantém a dock visível em workspaces vazios."
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 10
          wrapMode: Text.WordWrap
        }

        Item {
          width: parent.width
          height: 22

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              root.magnifyEnabled = !root.magnifyEnabled
              root.persistSettings()
            }
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Magnificar no hover"
            textFormat: Text.PlainText
            color: Color.menu.text
            font.pixelSize: 12
          }

          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 18
            radius: 9
            color: root.magnifyEnabled ? Color.accent : Qt.alpha(Color.foreground, 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
              x: root.magnifyEnabled ? parent.width - width - 2 : 2
              y: 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.background
              Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.alpha(Color.foreground, 0.12)
        }

        Rectangle {
          width: parent.width
          height: 22
          radius: 6
          color: resetHover.hovered ? Color.menu.selectedBackground : "transparent"

          HoverHandler { id: resetHover }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              root.itemSize = root.defaultItemSize
              root.itemSpacing = root.defaultItemSpacing
              root.spacerWidth = 24
              root.dockMode = "always"
              root.magnifyEnabled = true
              root.persistSettings()
            }
          }

          Text {
            anchors.centerIn: parent
            text: "Reset to defaults"
            textFormat: Text.PlainText
            color: Color.muted
            font.pixelSize: 11
          }
        }
      }
    }
  }
}


