pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io

// External control surface: `qs ipc call dock <fn> [args]`. The singleton only
// emits requests; each panel decides what to do with them.
Singleton {
  id: ipc

  signal toggleRequested()
  signal settingsRequested()
  signal pinRequested(string name)

  IpcHandler {
    target: "dock"
    function toggle() { ipc.toggleRequested() }
    function settings() { ipc.settingsRequested() }
    function pin(name: string) { ipc.pinRequested(name) }
  }
}
