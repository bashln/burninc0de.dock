import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls.Basic
import qs.Commons
import "config"
import "services"
import "model"
import "logic/indicator.js" as Indicator
import "logic/transparency.js" as Transparency
import "logic/actions.js" as Actions
import "logic/intellihide.js" as Intellihide
import "logic/urgent.js" as Urgent
import "logic/edge.js" as Edge
import Quickshell.Io

PanelWindow {
  id: root

  // Declared on the delegate root (not the instance block in Dock.qml) so
  // Variants injects the QScreen exactly like Omarchy's Background does.
  required property var modelData
  screen: modelData

  // Dock edge (S1g). `bottom` is the default; `top` mirrors it. Left and right
  // (vertical) are not wired yet, so they fall back to bottom for now.
  readonly property var edgeInfo: Edge.info(Settings.position)
  readonly property bool edgeTop: edgeInfo.edge === "top"
  readonly property bool edgeBottom: !edgeTop

  anchors.top: edgeTop
  anchors.bottom: edgeBottom
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
  readonly property int panelDepth: 320
  implicitHeight: panelDepth

  readonly property int dockHeight: 68
  readonly property real gap: 6
  readonly property real elevationMargin: -3

  // Icon geometry comes from the Settings singleton. defaultItemSize is the
  // reference the icon image scales against (itemSize * 40 / defaultItemSize).
  readonly property int defaultItemSize: 54
  readonly property int itemSize: Settings.iconSize
  readonly property int itemSpacing: Settings.spacing
  readonly property real itemPitch: itemSize + itemSpacing
  // Visibility mode (see Settings): always / autohide / smart.
  readonly property string dockMode: Settings.mode
  // Hover magnification on/off; toggled in Settings.
  readonly property bool magnifyEnabled: Settings.magnify
  // Leading Omarchy menu button (opens the app menu); toggled in Settings.
  readonly property bool showMenu: Settings.showMenu
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
  readonly property real spacerWidth: Settings.spacerWidth
  // Glass translucency derived from the theme's bar alpha (clamped so it stays
  // a glass surface even with an opaque theme, without going invisible).
  readonly property real glassAlpha: Math.max(0.35, Math.min(0.75, Color.bar.background.a))
  // Dynamic transparency: 0..1 nearness of the nearest visible window to the
  // bar (see logic/transparency.js) and the alpha the bar renders with.
  // `fixed` keeps the theme alpha for every nearness value.
  property real dynamicNear: 0
  property real barAlpha: Transparency.alphaFor(Settings.transparencyMode, dynamicNear, Settings.minAlpha, Settings.maxAlpha, root.glassAlpha)
  Behavior on barAlpha {
    NumberAnimation { duration: 250; easing.type: Easing.InOutQuad }
  }
  // Intellihide (see logic/intellihide.js): true while a qualifying window
  // overlaps the bar. Recomputed from the same event-driven geometry pass as
  // dynamicNear — never polled. `intellihideHides` is the hide pressure the
  // show/hide paths consult; it is false with the default settings.
  property bool intellihideBlocked: false
  readonly property bool intellihideHides: Settings.intellihide && intellihideBlocked
  // Local flag: DockApps singleton may survive plugin reloads without new
  // properties — do not depend on cross-file singleton for this.
  property bool showRunningUnpinned: true
  // Per-instance monitor: QScreen name == Hyprland connector name (HDMI-A-1…).
  // UntypedObjectModel has no .find; .values is the QObjectList (JS array).
  readonly property var hlMonitor: Hyprland.monitors.values.find(m => m.name === root.screen?.name)
  readonly property int monitorWsId: hlMonitor && hlMonitor.activeWorkspace ? hlMonitor.activeWorkspace.id : -1

  property bool dockVisible: true
  property bool mouseOverDockArea: triggerHover.hovered || dockHover.hovered || contextHover.hovered || windowMenuHover.hovered || pinMenuHover.hovered || settingsHover.hovered
  property bool workspaceEmpty: true
  property string clientsJson: ""
  property int _badgeTick: 0
  // Urgent windows (S1h): addresses reported by Hyprland's urgent event, and a
  // tick that re-evaluates the per-icon wiggle binding when the set changes.
  property var urgentAddrs: ({})
  property int _urgentTick: 0

  // Byte ceiling for hyprctl output, which scales with open windows, so it
  // never reaches this long-lived process unbounded. State-file ceilings now
  // live in StateStore.
  readonly property int maxClientsBytes: 1048576

  // Drag-to-reorder state. Only one icon can be dragged at a time, so this
  // lives on the root rather than in the delegates.
  property string dragName: ""
  property real dragPointerX: 0
  property real dragGrabOffset: 0
  readonly property bool dragging: dragName !== ""

  // Wheel accumulation over the dock: one action per 120-unit notch, so a
  // high-resolution wheel does not teleport through workspaces.
  property real scrollAcc: 0

  // Resolved relative to this file, NOT Quickshell.shellDir: Omarchy loads
  // plugins into its own shell instance, so shellDir points at
  // /usr/share/omarchy/shell and every execDetached would silently no-op.
  readonly property string pinTool: {
    const u = Qt.resolvedUrl("./bin/quickshelldock-pin").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

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


  ListModel { id: appModel }

  // StateStore owns the file reads; rebuild when a read lands. Settings loads
  // itself, so a size change reflows without rebuilding the list.
  Connections {
    target: StateStore
    function onOrderLoaded() { if (!root.dragging) root.rebuildModel() }
    function onPinsLoaded() { if (!root.dragging) root.rebuildModel() }
    function onHiddenLoaded() { if (!root.dragging) root.rebuildModel() }
  }

  // External control: `qs ipc call dock toggle|settings|pin <name>`.
  Connections {
    target: DockIpc
    function onToggleRequested() { root.dockVisible = !root.dockVisible }
    function onSettingsRequested() { root.openSettings(dockBar.width / 2) }
    function onPinRequested(name) { Quickshell.execDetached([root.pinTool, "--pin-window", name]) }
  }

  DockModel { id: dockModel }

  // Rebuild the visible app list through the tested model builder. The
  // ListModel stays here because the drag relies on move() keeping delegates
  // alive, and the magnifier reads it by index.
  function rebuildModel() {
    const apps = dockModel.build(root.showRunningUnpinned)
    appModel.clear()
    for (const app of apps) appModel.append(app)
  }

  function persistOrder() {
    let names = []
    for (var i = 0; i < appModel.count; i++) {
      // Transient running-only entries never belong in order.json.
      if (appModel.get(i).runningOnly) continue
      names.push(appModel.get(i).name)
    }
    StateStore.writeOrder(names)
  }

  // Called on every pointer move during a drag: figure out which slot the
  // dragged icon is currently over and shuffle the model if it changed.
  function updateDragTarget(fromIndex) {
    // Map the dragged icon's centre to the nearest base slot, so the target is
    // correct with the leading menu tile and with variable-width spacers.
    const draggedCenter = dragPointerX - dragGrabOffset + appBaseWidth(fromIndex) / 2
    let best = 0
    let bestDist = Infinity
    let off = menuOffset
    for (let i = 0; i < appModel.count; i++) {
      const w = appBaseWidth(i)
      const d = Math.abs(draggedCenter - (off + w / 2))
      if (d < bestDist) { bestDist = d; best = i }
      off += w + itemSpacing
    }
    if (best !== fromIndex) appModel.move(fromIndex, best, 1)
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

  // Global (Hyprland layout) rectangle of this screen's dock bar. The panel
  // window hugs the screen edge; Edge.barRect resolves the origin for the
  // chosen position (bottom is identical to the old inline formula).
  function dockBarRect() {
    const m = root.hlMonitor
    if (!m || !root.screen) return null
    const bar = { x: dockBar.x, y: dockBar.y, w: dockBar.width, h: dockBar.height }
    const monitor = { x: m.x, y: m.y, w: root.screen.width, h: root.screen.height }
    return Edge.barRect(monitor, Settings.position, root.panelDepth, bar)
  }

  // Window position of a menu card hanging off the bar's inner side, centred
  // on `anchor` (bar-relative). Delegates to logic/edge.js so the placement
  // follows Settings.position.
  function placeCard(anchor, size, margin) {
    const bar = { x: dockBar.x, y: dockBar.y, w: dockBar.width, h: dockBar.height }
    return Edge.placeMenu(Settings.position, bar, anchor, size, { w: root.width, h: root.height }, margin)
  }

  // Plain rectangles for the windows actually rendered behind this screen's
  // dock: only windows on the monitor's active workspace (Hyprland reports
  // `visible: true` even for windows parked on inactive workspaces, so the
  // workspace check is the one that matters; special/minimized workspaces
  // never match an active id). The intellihide flags ride along —
  // transparency only reads x/y/w/h.
  function visibleWindowRects() {
    const out = []
    const wsId = root.monitorWsId
    if (wsId == null || wsId < 0) return out
    for (const tl of Hyprland.toplevels.values) {
      const ipc = tl.lastIpcObject
      if (!ipc || ipc.visible === false) continue
      if (tl.monitor !== root.hlMonitor) continue
      if (!ipc.workspace || ipc.workspace.id !== wsId) continue
      const at = ipc.at
      const size = ipc.size
      if (!at || !size || at.length < 2 || size.length < 2) continue
      out.push({
        x: at[0],
        y: at[1],
        w: size[0],
        h: size[1],
        focused: typeof ipc.focusHistoryID === "number" ? ipc.focusHistoryID === 0 : false,
        maximized: typeof ipc.fullscreen === "number" ? ipc.fullscreen >= 1 : false,
        onTop: ipc.pinned === true,
      })
    }
    return out
  }

  function updateDynamicNear() {
    if (Settings.transparencyMode !== "dynamic") {
      if (dynamicNear !== 0) dynamicNear = 0
      return
    }
    const rect = root.dockBarRect()
    if (!rect) return
    const near = Transparency.nearness(root.visibleWindowRects(), rect, Transparency.DEFAULT_SLACK)
    if (near !== dynamicNear) dynamicNear = near
  }

  // Recompute the intellihide decision from the same geometry pass. Disabled
  // settings answer false, so the flag drops to false and stays there.
  function updateIntellihide() {
    const rect = root.dockBarRect()
    const blocked = rect
      ? Intellihide.shouldHide(Settings.intellihide, Settings.intellihideMode, root.visibleWindowRects(), rect)
      : false
    if (blocked !== intellihideBlocked) intellihideBlocked = blocked
  }

  // Tokenizes an XDG desktop-entry Exec value per the freedesktop spec:
  // split on unquoted whitespace, honor double quotes (where \ escapes
  // " \ $ `), single quotes (fully literal), and backslash escapes.
  // A plain split(/\s+/) corrupts any argument containing a quoted space.
  function execTokenize(exec) {
    return WindowService.execTokenize(exec)
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
    return WindowService.getToplevelsForApp(app)
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

  // class/appId (and raw title fallback) → display name via IconResolver.
  function candidateLabel(key, title) {
    return IconResolver.candidateLabel(key, title)
  }

  function candidateIcon(key, cls, appId) {
    return IconResolver.candidateIcon(key, cls, appId)
  }

  function desktopEntryForWindow(cls, aid) {
    return IconResolver.desktopEntryForWindow(cls, aid)
  }

  function entryIconSource(icon) {
    return IconResolver.entryIconSource(icon)
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

  function openPinMenu(xInBar) {
    if (root.pinMenuOpen) {
      root.closePinMenu()
      return
    }
    root.closeContextMenu()
    root.closeHoverMenu()
    // Lazy one-time map: first open loads the cache, then reopens on mapLoaded.
    if (IconResolver.desktopNameMap === null) {
      root.pendingPinAnchorX = xInBar
      root.pendingPinOpen = true
      IconResolver.ensureMapLoaded()
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

  // IconResolver owns the desktop map; react when it lands so running-only
  // labels resolve and a queued pin-menu open can proceed.
  Connections {
    target: IconResolver
    function onMapLoaded() {
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
        if (IconResolver.desktopNameMap) {
          for (const k in resolved) IconResolver.desktopNameMap[k.toLowerCase()] = { name: resolved[k], icon: "" }
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
    WindowService.focusWindow(address)
  }

  // Address of a toplevel, tolerant of the two shapes Quickshell exposes.
  function toplevelAddress(tl) {
    if (!tl) return ""
    var addr = tl.lastIpcObject?.address
    if (!addr || addr === "0") addr = "0x" + tl.address
    return addr || ""
  }

  // Focus a toplevel by address, falling back to its class — the same
  // resolution the click handlers have always used inline.
  function focusToplevel(tl) {
    if (!tl) return
    var addr = tl.lastIpcObject?.address
    if (!addr || addr === "0") addr = "0x" + tl.address
    if (addr && addr !== "0x0") {
      Hyprland.dispatch('hl.dsp.focus({ window = "address:' + addr + '" })')
    } else {
      var cls = tl.lastIpcObject?.class
      if (cls) Hyprland.dispatch('hl.dsp.focus({ window = "class:' + cls + '" })')
    }
  }

  // One focusHistoryID per app toplevel (999 for anything untracked) — the
  // plain input logic/actions.js ranks for the focus/cycle click actions.
  function focusIds(toplevels) {
    const ids = []
    for (const t of toplevels) {
      const v = t.toplevel.lastIpcObject?.focusHistoryID
      ids.push(typeof v === "number" ? v : 999)
    }
    return ids
  }

  // Every window on this screen's active workspace, for scroll-cycling.
  function workspaceWindows() {
    const out = []
    const wsId = root.monitorWsId
    if (wsId == null || wsId < 0) return out
    for (const tl of Hyprland.toplevels.values) {
      const ipc = tl.lastIpcObject
      if (!ipc || !ipc.workspace || ipc.workspace.id !== wsId) continue
      if (tl.monitor !== root.hlMonitor) continue
      out.push(tl)
    }
    return out
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

  // Base left offset of the first app: the leading menu tile plus its gap.
  readonly property real menuOffset: showMenu ? itemSize + itemSpacing : 0

  // Total base width of the Row: the menu tile + every app/spacer + the
  // separator + trash, with one itemSpacing between each adjacent pair.
  function baseContentWidth() {
    let w = 0
    for (let i = 0; i < appModel.count; i++) w += appBaseWidth(i)
    return menuOffset + w + (appModel.count + 1) * itemSpacing + separatorWidth + trashWidth
  }

  function magnifyForIndex(i) {
    if (!magnifyActive || appModel.count === 0) return 1
    if (appModel.get(i).spacer) return 1
    const baseLeft = root.width / 2 - baseContentWidth() / 2
    let off = menuOffset
    for (let j = 0; j < i; j++) off += appBaseWidth(j) + itemSpacing
    const dist = Math.abs(cursorSceneX - (baseLeft + off + itemSize / 2))
    if (dist >= magnifyRadius) return 1
    const t = 1 - dist / magnifyRadius
    return 1 + (magnifyMaxScale - 1) * t * t
  }

  function showDockBar() {
    showTimer.stop()
    hideTimer.stop()
    dockVisible = true
  }

  // Show after showDelay; a zero delay shows at once.
  function requestShow() {
    if (Settings.showDelay <= 0) { showDockBar(); return }
    showTimer.restart()
  }

  function scheduleHide() {
    if (dockMode === "always" && !root.intellihideHides) return
    showTimer.stop()
    hideTimer.restart()
  }

  // After focusing/launching/unpinning: drop the dock when the mode calls for
  // it, using the same rules as the hide timer. In the `always` mode the only
  // hide pressure is an intellihide overlap.
  function maybeHideAfterAction() {
    if (dockMode === "always") {
      if (!root.intellihideHides) return
      if (!root.mouseOverDockArea) root.dockVisible = false
      return
    }
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
    if (dockMode === "always") {
      if (!intellihideHides) showDockBar()
      return
    }
    if (dockMode === "smart") {
      if (workspaceEmpty) showDockBar()
      else scheduleHide()
    }
  }

  // An overlap hides with the usual delay; its end re-shows the dock in the
  // modes where it is meant to be up. Hover reveal is untouched, so the dock
  // stays reachable while blocked.
  onIntellihideBlockedChanged: {
    if (intellihideBlocked) scheduleHide()
    else if (dockMode === "always" || (dockMode === "smart" && workspaceEmpty)) showDockBar()
  }

  onDockModeChanged: {
    if (dockMode === "always") {
      if (!intellihideHides) showDockBar()
      return
    }
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
    geometryTimer.restart()
  }

  onHlMonitorChanged: geometryTimer.restart()

  onMonitorWsIdChanged: geometryTimer.restart()

  Component.onCompleted: {
    rebuildModel()
    updateWorkspaceEmpty()
    updateDynamicNear()
    updateIntellihide()
    // Build the desktop Name cache in the background so the first pin-menu
    // open is synchronous (no flash, no stutter).
    IconResolver.ensureMapLoaded()
  }

  // Switching to dynamic must measure the geometry right away; the bar alpha
  // binding re-evaluates on its own, but `near` would otherwise wait for the
  // next window event. Intellihide re-measures on toggle/mode change so the
  // dock reacts immediately instead of waiting for the next window event.
  Connections {
    target: Settings
    function onTransparencyModeChanged() { root.updateDynamicNear() }
    function onIntellihideChanged() { root.updateIntellihide() }
    function onIntellihideModeChanged() { root.updateIntellihide() }
    // Moving the bar changes its rect, so re-measure the window geometry.
    function onPositionChanged() { root.geometryTimer.restart() }
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
      if (event.name === "urgent" || event.name === "urgentv2") {
        // Only track while the feature is on, so the default stays inert.
        if (Settings.urgentWiggle) {
          const addr = Urgent.addressFromEvent(event.data)
          if (addr) {
            const next = Object.assign({}, root.urgentAddrs)
            next[addr] = true
            root.urgentAddrs = next
            root._urgentTick++
            if (Urgent.shouldReveal(Settings.urgentWiggle, Object.keys(root.urgentAddrs).length)) root.showDockBar()
          }
        }
      }
      if (event.name === "activewindowv2") {
        // Hyprland clears urgency for the window that gains focus.
        const addr = Urgent.addressFromEvent(event.data)
        if (addr && root.urgentAddrs[addr]) {
          const next = Object.assign({}, root.urgentAddrs)
          delete next[addr]
          root.urgentAddrs = next
          root._urgentTick++
        }
      } else if (event.name === "activewindow") {
        // Legacy event carries no address; drop the whole set.
        if (Object.keys(root.urgentAddrs).length > 0) {
          root.urgentAddrs = ({})
          root._urgentTick++
        }
      }
      if (event.name === "closewindow") {
        const addr = Urgent.addressFromEvent(event.data)
        if (addr && root.urgentAddrs[addr]) {
          const next = Object.assign({}, root.urgentAddrs)
          delete next[addr]
          root.urgentAddrs = next
          root._urgentTick++
        }
      }
      if (event.name === "openwindow" || event.name === "closewindow") {
        // Event may arrive before Quickshell registers the toplevel or the
        // monitor's activeWorkspace updates; 80ms settles and coalesces bursts.
        stateRefreshTimer.restart()
      }
      if (["movewindow", "movewindowv2", "openwindow", "closewindow",
           "activewindow", "activewindowv2", "fullscreen", "changefloatingmode",
           "workspace", "workspacev2", "createworkspace", "createworkspacev2",
           "destroyworkspace", "destroyworkspacev2",
           "moveworkspacev2", "focusedmon", "focusedmonv2"].includes(event.name)) {
        geometryTimer.restart()
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

  // Debounced recompute of the geometry-derived state (dynamic transparency
  // and intellihide). Coalesces bursts of window events and the bar's own
  // hover resize.
  Timer {
    id: geometryTimer
    interval: 120
    repeat: false
    onTriggered: {
      root.updateDynamicNear()
      root.updateIntellihide()
    }
  }

  Rectangle {
    id: triggerStrip
    anchors.top: root.edgeTop ? parent.top : undefined
    anchors.bottom: root.edgeBottom ? parent.bottom : undefined
    anchors.horizontalCenter: dockBar.horizontalCenter
    // hot area plus some fat finger margin
    width: dockBar.width + 80
    height: 4
    color: "transparent"

    HoverHandler {
      id: triggerHover
      onHoveredChanged: {
        if (hovered) {
          root.requestShow()
        } else {
          showTimer.stop()
          root.scheduleHide()
        }
      }
    }
  }

  Timer {
    id: showTimer
    interval: Settings.showDelay
    repeat: false
    onTriggered: root.showDockBar()
  }

  Timer {
    id: hideTimer
    interval: Settings.hideDelay
    repeat: false
    onTriggered: {
      if (root.dockMode === "always" && !root.intellihideHides) return
      if (root.mouseOverDockArea || root.dragging || root.contextOpen || root.hoverMenuOpen || root.pinMenuOpen || root.settingsOpen) return
      if (root.dockMode === "smart" && root.workspaceEmpty) return
      root.dockVisible = false
    }
  }

  Rectangle {
    id: dockBar
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: root.edgeTop ? parent.top : undefined
    anchors.bottom: root.edgeBottom ? parent.bottom : undefined
    anchors.topMargin: root.dockOffset
    anchors.bottomMargin: root.dockOffset

    // The hidden/shown offset the anchors follow. Animating this property with
    // a Behavior slides the bar; states+PropertyChanges with two anchor
    // margins is unreliable in QML.
    property real dockOffset: root.dockVisible ? (root.elevationMargin + root.gap) : (root.gap - root.dockHeight - 20)
    Behavior on dockOffset { NumberAnimation { duration: Settings.animationTime; easing.type: Easing.InOutQuad } }

    implicitWidth: row.implicitWidth + 24
    implicitHeight: row.implicitHeight + 24

    // The bar's own footprint feeds the nearness measure, so re-measure when
    // magnification or a settings change resizes it (debounced).
    onWidthChanged: geometryTimer.restart()
    onHeightChanged: geometryTimer.restart()

    // Translucent so the Hyprland layer blur (looknfeel.lua) reads as glass.
    // `barAlpha` keeps the theme's alpha in the default fixed mode and
    // follows window proximity only in the dynamic mode.
    color: Util.alpha(Color.bar.background, root.barAlpha)
    radius: 18
    border.color: Qt.alpha(Color.foreground, 0.18)
    border.width: 1

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

    // scrollAction: one action per wheel notch over the bar (see
    // logic/actions.js). `nothing` (default) consumes the event without
    // acting, so nothing behind the layer surface reacts either.
    WheelHandler {
      onWheel: event => {
        const step = Actions.scrollStep(root.scrollAcc, event.angleDelta.y)
        root.scrollAcc = step.acc
        event.accepted = true
        if (!step.fire) return
        const op = Actions.routeScroll(Settings.scrollAction)
        const up = event.angleDelta.y > 0
        if (op === "switch-workspace") {
          Hyprland.dispatch('hl.dsp.focus({ workspace = "' + (up ? "e-1" : "e+1") + '" })')
        } else if (op === "cycle-windows") {
          const wins = root.workspaceWindows()
          if (wins.length > 0) {
            const ids = []
            for (const t of wins) {
              const v = t.lastIpcObject?.focusHistoryID
              ids.push(typeof v === "number" ? v : 999)
            }
            const wi = Actions.cycleIndex(ids, up ? -1 : 1)
            if (wi >= 0) root.focusToplevel(wins[wi])
          }
        }
      }
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

      // Leading Omarchy menu button. Opens the shell's app menu; hidden items
      // are skipped by Row layout, so no gap is left when it is off.
      Item {
        id: dockMenu
        visible: root.showMenu
        width: root.itemSize
        height: root.itemSize

        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: 12
          color: Color.foreground
          opacity: menuHover.hovered ? 0.15 : 0
          Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        HoverHandler { id: menuHover }

        TapHandler {
          acceptedButtons: Qt.LeftButton
          onSingleTapped: Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "omarchy.menu", '{"menu":"root"}'])
        }

        Text {
          anchors.centerIn: parent
          // Omarchy logo glyph from the "omarchy" font (same as the bar's menu).
          text: "\ue900"
          font.family: "omarchy"
          font.pixelSize: Math.round(root.itemSize * 0.62)
          color: Color.foreground
        }
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
          // Urgent wiggle (S1h): on while a window of this app is urgent.
          readonly property bool urgentNow: {
            root._urgentTick
            return Settings.urgentWiggle && Urgent.hasUrgent(appItem.toplevels, root.urgentAddrs, root.toplevelAddress)
          }
          property real wiggleAngle: 0

          SequentialAnimation {
            running: appItem.busy && !appItem.isRunning
            loops: Animation.Infinite
            NumberAnimation { target: appItem; property: "bounceOffset"; from: 0; to: -10; duration: 160; easing.type: Easing.OutQuad }
            NumberAnimation { target: appItem; property: "bounceOffset"; from: -10; to: 0; duration: 160; easing.type: Easing.InQuad }
          }

          SequentialAnimation {
            running: appItem.urgentNow
            loops: Animation.Infinite
            // A stop mid-swing would leave the icon tilted; restore it.
            onStopped: appItem.wiggleAngle = 0
            NumberAnimation { target: appItem; property: "wiggleAngle"; from: 0; to: -10; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { target: appItem; property: "wiggleAngle"; from: -10; to: 10; duration: 200; easing.type: Easing.InOutQuad }
            NumberAnimation { target: appItem; property: "wiggleAngle"; from: 10; to: 0; duration: 100; easing.type: Easing.InOutQuad }
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
              const op = Actions.routeClick(Settings.clickAction, appItem.isRunning)

              // clickAction "launch": open one more window even though the app
              // is already running. A running-only entry has no command, so it
              // falls back to focusing its most recent window.
              if (appItem.isRunning && op === "launch") {
                if (!appItem.busy && !appItem.runningOnly && cmdParts.length > 0) {
                  appItem.busy = true
                  Quickshell.execDetached(cmdParts)
                } else {
                  const lfi = Actions.mostRecentIndex(root.focusIds(appItem.toplevels))
                  if (lfi >= 0) root.focusToplevel(appItem.toplevels[lfi].toplevel)
                }
                return
              }

              // clickAction "focus": raise the most recent window, never
              // minimize.
              if (appItem.isRunning && op === "focus") {
                const ffi = Actions.mostRecentIndex(root.focusIds(appItem.toplevels))
                if (ffi >= 0) root.focusToplevel(appItem.toplevels[ffi].toplevel)
                root.maybeHideAfterAction()
                return
              }

              // clickAction "cycle": step through this app's windows with
              // wrap-around (0 = focused, next = previously used).
              if (appItem.isRunning && op === "cycle") {
                const cci = Actions.cycleIndex(root.focusIds(appItem.toplevels), 1)
                if (cci >= 0) root.focusToplevel(appItem.toplevels[cci].toplevel)
                root.maybeHideAfterAction()
                return
              }

              if (appItem.isRunning) {
                // clickAction "minimize" (default): today's toggle — move
                // windows to the scratchpad, restore them, or focus.
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
                    root.focusToplevel(appItem.toplevels[0].toplevel)
                    return
                  }
                }

                root.focusToplevel(appItem.toplevels[0].toplevel)
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
            rotation: appItem.wiggleAngle
            source: root.entryIconSource(appItem.icon)
            width: Math.round(appItem.width * 40 / root.defaultItemSize)
            height: width
            fillMode: Image.PreserveAspectFit
            opacity: appItem.isDragged ? 0.85 : 1
          }

          // Running indicator. Shape driven by Settings.indicatorStyle; the
          // default `dot` reproduces the original single dot.
          Item {
            id: indicator
            visible: appItem.isRunning && !appItem.spacer
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -6
            width: 0
            height: 0
            readonly property var spec: Indicator.spec(Settings.indicatorStyle, appItem.toplevels.length)

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              spacing: 3
              Repeater {
                model: indicator.spec.segments
                delegate: Rectangle {
                  width: indicator.spec.shape === "dot" ? 4 : (indicator.spec.shape === "dash" ? 8 : Math.round(root.itemSize * 0.6))
                  height: indicator.spec.shape === "dot" ? 4 : 3
                  radius: indicator.spec.shape === "dot" ? 2 : 1.5
                  color: Color.accent
                }
              }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              visible: indicator.spec.showCount
              text: appItem.toplevels.length.toString()
              textFormat: Text.PlainText
              color: Color.accent
              font.pixelSize: 9
              font.bold: true
            }
          }

          // Multi-window count badge (top-left). Complements the hover window
          // list: you can see at a glance which apps have more than one window.
          Rectangle {
            visible: appItem.toplevels.length >= 2 && !appItem.spacer
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.topMargin: -4
            anchors.leftMargin: -4
            width: Math.max(16, winCountText.implicitWidth + 8)
            height: 16
            radius: 8
            color: Color.accent
            border.color: Color.bar.background
            border.width: 1

            Text {
              id: winCountText
              anchors.centerIn: parent
              text: appItem.toplevels.length > 9 ? "9+" : appItem.toplevels.length.toString()
              textFormat: Text.PlainText
              color: Color.bar.background
              font.pixelSize: 9
              font.bold: true
            }
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

    x: root.placeCard(root.hoverNameAnchorX, { w: width, h: height }, 6).x
    y: root.placeCard(root.hoverNameAnchorX, { w: width, h: height }, 6).y

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
    onTriggered: Settings.save()
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

    x: root.placeCard(root.contextAnchorX, { w: width, h: height }, 2).x
    y: root.placeCard(root.contextAnchorX, { w: width, h: height }, 2).y

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

    x: root.placeCard(root.hoverMenuAnchorX, { w: width, h: height }, 2).x
    y: root.placeCard(root.hoverMenuAnchorX, { w: width, h: height }, 2).y

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

    x: root.placeCard(root.pinMenuAnchorX, { w: width, h: height }, 2).x
    y: root.placeCard(root.pinMenuAnchorX, { w: width, h: height }, 2).y

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

    // Absolute anchor (captured at open time) so the panel stays under the
    // cursor even while dockBar reflows underneath during slider drag.
    x: root.placeCard(root.settingsAnchorX - dockBar.x, { w: width, h: height }, 2).x
    y: root.placeCard(root.settingsAnchorX - dockBar.x, { w: width, h: height }, 2).y

    HoverHandler { id: settingsHover }

    Rectangle {
      id: settingsCard

      // Room for the scroll area: the panel hangs from dockBar.top, so the
      // space above the bar minus the panel margin (2), card padding (24),
      // header (~16) and spacing (10) is what the body may use. The floor
      // keeps the panel usable even if the bar sits unusually low.
      readonly property int scrollMax: Math.max(140, Edge.menuSpace(Settings.position, { x: dockBar.x, y: dockBar.y, w: dockBar.width, h: dockBar.height }, { w: root.width, h: root.height }) - 54)

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

        // Everything below the header scrolls, capped like pinFlick so the
        // card can never outgrow the space above the dock. Column spacing
        // and every row stay as they were; only the viewport is bounded.
        Flickable {
          id: settingsFlick
          width: settingsColumn.width
          height: Math.min(settingsBody.implicitHeight, settingsCard.scrollMax)
          clip: true
          contentHeight: settingsBody.implicitHeight
          flickableDirection: Flickable.VerticalFlick
          boundsBehavior: Flickable.StopAtBounds

          WheelHandler {
            onWheel: event => {
              if (settingsFlick.contentHeight > settingsFlick.height) {
                const dy = event.angleDelta.y > 0 ? -40 : 40
                settingsFlick.contentY = Math.max(0, Math.min(settingsFlick.contentHeight - settingsFlick.height, settingsFlick.contentY + dy))
                event.accepted = true
              }
            }
          }

          Column {
            id: settingsBody
            width: settingsFlick.width
            spacing: 10

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
              Settings.iconSize = value
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
              Settings.spacing = value
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
              Settings.spacerWidth = value
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
          text: "Timing"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
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
              text: "Show delay"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: showDelaySlider.value + " ms"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: showDelaySlider
            width: parent.width
            from: 0
            to: 1000
            stepSize: 10
            value: Settings.showDelay
            onMoved: {
              Settings.showDelay = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: showDelaySlider.leftPadding
              y: showDelaySlider.topPadding + showDelaySlider.availableHeight / 2 - height / 2
              width: showDelaySlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: showDelaySlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: showDelaySlider.leftPadding + showDelaySlider.visualPosition * showDelaySlider.availableWidth - width / 2
              y: showDelaySlider.topPadding + showDelaySlider.availableHeight / 2 - height / 2
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
              text: "Hide delay"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: hideDelaySlider.value + " ms"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: hideDelaySlider
            width: parent.width
            from: 0
            to: 2000
            stepSize: 10
            value: Settings.hideDelay
            onMoved: {
              Settings.hideDelay = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: hideDelaySlider.leftPadding
              y: hideDelaySlider.topPadding + hideDelaySlider.availableHeight / 2 - height / 2
              width: hideDelaySlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: hideDelaySlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: hideDelaySlider.leftPadding + hideDelaySlider.visualPosition * hideDelaySlider.availableWidth - width / 2
              y: hideDelaySlider.topPadding + hideDelaySlider.availableHeight / 2 - height / 2
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
              text: "Animation"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: animationSlider.value + " ms"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: animationSlider
            width: parent.width
            from: 0
            to: 1000
            stepSize: 10
            value: Settings.animationTime
            onMoved: {
              Settings.animationTime = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: animationSlider.leftPadding
              y: animationSlider.topPadding + animationSlider.availableHeight / 2 - height / 2
              width: animationSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: animationSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: animationSlider.leftPadding + animationSlider.visualPosition * animationSlider.availableWidth - width / 2
              y: animationSlider.topPadding + animationSlider.availableHeight / 2 - height / 2
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
          text: "Posição"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { key: "bottom", label: "Embaixo" },
              { key: "top", label: "Em cima" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: posRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: posRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.position = modelData.key
                  Settings.save()
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
                    visible: Settings.position === modelData.key
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
                  Settings.mode = modelData.mode
                  Settings.save()
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

        Text {
          text: "Intellihide"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Item {
          width: parent.width
          height: 22

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              Settings.intellihide = !Settings.intellihide
              Settings.save()
            }
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Esconder quando cobrir a dock"
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
            color: Settings.intellihide ? Color.accent : Qt.alpha(Color.foreground, 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
              x: Settings.intellihide ? parent.width - width - 2 : 2
              y: 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.background
              Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
          }
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { key: "all", label: "Qualquer janela" },
              { key: "focused", label: "Janela focada" },
              { key: "maximized", label: "Janela maximizada" },
              { key: "always-on-top", label: "Sempre no topo" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: ihRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: ihRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.intellihideMode = modelData.key
                  Settings.save()
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
                    visible: Settings.intellihideMode === modelData.key
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

        Item {
          width: parent.width
          height: 22

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              Settings.urgentWiggle = !Settings.urgentWiggle
              Settings.save()
            }
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Wiggle em urgência"
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
            color: Settings.urgentWiggle ? Color.accent : Qt.alpha(Color.foreground, 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
              x: Settings.urgentWiggle ? parent.width - width - 2 : 2
              y: 2
              width: 14
              height: 14
              radius: 7
              color: Color.menu.background
              Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
          }
        }

        Text {
          text: "Indicator"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { style: "dot", label: "Dot" },
              { style: "dots", label: "Dots (por janela)" },
              { style: "dashes", label: "Dashes (por janela)" },
              { style: "solid", label: "Solid (barra)" },
              { style: "count", label: "Count (número)" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: indRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: indRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.indicatorStyle = modelData.style
                  Settings.save()
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
                    visible: Settings.indicatorStyle === modelData.style
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
          text: "Transparency"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { mode: "fixed", label: "Fixa (tema)" },
              { mode: "dynamic", label: "Dinâmica (janela perto)" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: transRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: transRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.transparencyMode = modelData.mode
                  Settings.save()
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
                    visible: Settings.transparencyMode === modelData.mode
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

        Column {
          width: parent.width
          spacing: 6

          Item {
            width: parent.width
            height: 14
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Alpha mínimo"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(minAlphaSlider.value * 100) + " %"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: minAlphaSlider
            width: parent.width
            from: 0.1
            to: 1.0
            stepSize: 0.05
            value: Settings.minAlpha
            onMoved: {
              Settings.minAlpha = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: minAlphaSlider.leftPadding
              y: minAlphaSlider.topPadding + minAlphaSlider.availableHeight / 2 - height / 2
              width: minAlphaSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: minAlphaSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: minAlphaSlider.leftPadding + minAlphaSlider.visualPosition * minAlphaSlider.availableWidth - width / 2
              y: minAlphaSlider.topPadding + minAlphaSlider.availableHeight / 2 - height / 2
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
              text: "Alpha máximo"
              textFormat: Text.PlainText
              color: Color.muted
              font.pixelSize: 12
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(maxAlphaSlider.value * 100) + " %"
              textFormat: Text.PlainText
              color: Color.menu.text
              font.pixelSize: 12
            }
          }

          Slider {
            id: maxAlphaSlider
            width: parent.width
            from: 0.1
            to: 1.0
            stepSize: 0.05
            value: Settings.maxAlpha
            onMoved: {
              Settings.maxAlpha = value
              settingsSaveTimer.restart()
            }

            background: Rectangle {
              x: maxAlphaSlider.leftPadding
              y: maxAlphaSlider.topPadding + maxAlphaSlider.availableHeight / 2 - height / 2
              width: maxAlphaSlider.availableWidth
              height: 4
              radius: 2
              color: Qt.alpha(Color.foreground, 0.2)

              Rectangle {
                width: maxAlphaSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Color.foreground
              }
            }

            handle: Rectangle {
              x: maxAlphaSlider.leftPadding + maxAlphaSlider.visualPosition * maxAlphaSlider.availableWidth - width / 2
              y: maxAlphaSlider.topPadding + maxAlphaSlider.availableHeight / 2 - height / 2
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
          text: "Actions"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 12
        }

        Text {
          text: "Clique em ícone aberto"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 10
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { key: "minimize", label: "Minimizar/restaurar" },
              { key: "launch", label: "Abrir nova janela" },
              { key: "cycle", label: "Alternar janelas" },
              { key: "focus", label: "Focar" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: clickRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: clickRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.clickAction = modelData.key
                  Settings.save()
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
                    visible: Settings.clickAction === modelData.key
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
          text: "Roda do mouse sobre a dock"
          textFormat: Text.PlainText
          color: Color.muted
          font.pixelSize: 10
        }

        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { key: "nothing", label: "Nada" },
              { key: "cycle-windows", label: "Alternar janelas" },
              { key: "switch-workspace", label: "Trocar workspace" },
            ]

            delegate: Rectangle {
              required property var modelData

              width: parent.width
              height: 24
              radius: 6
              color: scrollRowHover.hovered ? Color.menu.selectedBackground : "transparent"

              HoverHandler { id: scrollRowHover }

              TapHandler {
                acceptedButtons: Qt.LeftButton
                onSingleTapped: {
                  Settings.scrollAction = modelData.key
                  Settings.save()
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
                    visible: Settings.scrollAction === modelData.key
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

        Item {
          width: parent.width
          height: 22

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              Settings.magnify = !Settings.magnify
              Settings.save()
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

        Item {
          width: parent.width
          height: 22

          TapHandler {
            acceptedButtons: Qt.LeftButton
            onSingleTapped: {
              Settings.showMenu = !Settings.showMenu
              Settings.save()
            }
          }

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Menu do Omarchy"
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
            color: root.showMenu ? Color.accent : Qt.alpha(Color.foreground, 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
              x: root.showMenu ? parent.width - width - 2 : 2
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
              Settings.reset()
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
  }
}


