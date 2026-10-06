pragma Singleton

import QtQml
import Quickshell
import Quickshell.Hyprland
import "../logic/matching.js" as Matching

// Shared window queries. One instance for every per-screen panel. Matching
// rules live in logic/matching.js so they stay unit-testable.
Singleton {
  id: windows

  function execTokenize(exec) {
    return Matching.execTokenize(exec)
  }

  function matchesApp(app, win) {
    return Matching.matchesApp(app, win)
  }

  function getToplevelsForApp(app) {
    let results = []
    for (const tl of Hyprland.toplevels.values) {
      const win = {
        title: tl.title ?? "",
        appId: tl.wayland?.appId ?? "",
        class: tl.lastIpcObject?.class ?? "",
      }
      if (Matching.matchesApp(app, win)) {
        results.push({ toplevel: tl, pid: tl.lastIpcObject?.pid ?? -1 })
      }
    }
    return results
  }

  function focusWindow(address) {
    if (!address || address === "0x0") return
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }
}
