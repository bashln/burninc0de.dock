pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import qs.Commons
import "../logic/icons.js" as Icons

// Shared desktop-entry and icon resolution. One instance for every panel.
// Label/icon heuristics live in logic/icons.js for unit testing.
Singleton {
  id: icons

  // class/appId/host (lowercased) -> { name, icon }. Null until the dump-map
  // has loaded once.
  property var desktopNameMap: null
  property bool desktopMapLoading: false
  // name -> absolute icon path, from the on-disk icon scan.
  property var iconDiskIndex: ({})
  property var pendingIconDiskIndex: ({})

  readonly property string pinTool: {
    const u = Qt.resolvedUrl("../bin/quickshelldock-pin").toString()
    return decodeURIComponent(u.replace(/^file:\/\//, ""))
  }

  signal mapLoaded()

  function ensureMapLoaded() {
    if (desktopNameMap !== null || desktopMapLoading) return
    desktopMapLoading = true
    desktopMapProcess.running = true
  }

  // class/appId (and raw title fallback) -> display name via the desktop cache.
  function candidateLabel(key, title) {
    return Icons.resolveLabel(key, title, desktopNameMap)
  }

  // Desktop Icon= for a class/appId via the cache; falls back to the host
  // heuristic then the raw class (iconPath may still miss).
  function candidateIcon(key, cls, appId) {
    const found = Icons.resolveIcon(key, desktopNameMap)
    if (found) return found
    return pinCandidateIcon({ cls: cls, appId: appId })
  }

  // Window class/appId -> DesktopEntry, same source the Omarchy app menu uses.
  // id -> StartupWMClass -> Exec basename (all case-insensitive).
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
  // without kind "menu"): absolute/file URL -> disk index -> themed -> generic.
  // Never returns empty, so an Image source can't go blank.
  function entryIconSource(icon) {
    var v = String(icon || "")
    if (v.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (v.indexOf("file://") === 0 || v.indexOf("image://") === 0) return v
    if (v.charAt(0) === "/") return Util.fileUrl(v)
    var found = iconDiskIndex[v]
    if (found) return Util.fileUrl(found)
    var themed = Quickshell.iconPath(v, true)
    if (themed && themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Webapps report a synthetic class like chrome-web.whatsapp.com__-Default
  // with no icon theme entry; the host's second-level domain does. Fall back
  // so the pin menu does not show a blank icon.
  function pinCandidateIcon(entry) {
    if (entry.empty) return ""
    const raw = entry.cls || entry.appId || ""
    if (!raw) return ""
    const host = Icons.hostFromClass(raw)
    if (host) {
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
    if (name.length > 0 && pendingIconDiskIndex[name] === undefined)
      pendingIconDiskIndex[name] = file
  }

  // One-time desktop Name+Icon cache from the pin tool's dump-map.
  Process {
    id: desktopMapProcess
    command: [icons.pinTool, "--dump-map"]
    stdout: StdioCollector {
      onStreamFinished: {
        const map = {}
        for (const line of this.text.trim().split("\n")) {
          if (!line) continue
          const parts = line.split("\t")
          if (parts.length >= 2) map[parts[0]] = { name: parts[1], icon: parts[2] || "" }
        }
        icons.desktopNameMap = map
        icons.desktopMapLoading = false
        icons.mapLoaded()
      }
    }
  }

  Process {
    id: iconIndexScan
    command: ["bash", "-c", icons.iconIndexScanCommand()]
    stdout: SplitParser {
      onRead: function(line) { icons.indexIconLine(line) }
    }
    onStarted: icons.pendingIconDiskIndex = ({})
    // Swapping the property re-evaluates every entryIconSource() binding.
    onExited: icons.iconDiskIndex = icons.pendingIconDiskIndex
  }

  Component.onCompleted: {
    if (!iconIndexScan.running) iconIndexScan.running = true
  }
}
