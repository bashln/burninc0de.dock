pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../logic/state.js" as StateLogic

// Sole reader/writer of the dock's state files. Shared across every per-screen
// panel so there is one set of file watchers and one read queue. Reads go
// through `head -c` (byte ceiling), never through FileView, which keeps
// user-writable files from buffering whole into the shell.
Singleton {
  id: store

  readonly property int maxStateBytes: 65536

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/burninc0de.dock"
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

  property var order: []
  property var pins: []
  property var hidden: []
  property var settings: ({})

  // Emitted after each read, even when the parsed value is empty, so consumers
  // rebuild on startup and on every watcher-triggered re-read.
  signal orderLoaded()
  signal pinsLoaded()
  signal hiddenLoaded()
  signal settingsLoaded()

  Process {
    id: stateReader
    property string kind: ""
    // Reads requested while one is in flight drain here, oldest first. A
    // single slot would drop every request but the last: startup fires all
    // four reads back-to-back and pins would lose to hidden.
    property var pendingQueue: []
    stdout: StdioCollector {
      onStreamFinished: store.consumeStateFile(stateReader.kind, this.text)
    }
    // Missing files at first boot are normal; keep head's stderr out of the log.
    stderr: StdioCollector {}
    onExited: {
      if (stateReader.pendingQueue.length === 0) return
      const next = stateReader.pendingQueue.shift()
      store.readStateFile(next.kind, next.path)
    }
  }

  Process {
    id: mkdirProcess
    // Ensures the new state dir exists and migrates any files from legacy
    // locations (quickshelldock, omarchy/dock, omarchy/stealthdock). Only copies
    // files that don't already exist so a fresh install never clobbers data.
    command: ["sh", "-c", "mkdir -p \"$1\"; for legacy in \"$2\" \"$3\" \"$4\"; do if [ -d \"$legacy\" ]; then for f in order.json pins.json hidden.json; do [ -f \"$legacy/$f\" ] && [ ! -e \"$1/$f\" ] && cp -n -- \"$legacy/$f\" \"$1/$f\" 2>/dev/null; done; fi; done", "sh", store.stateDir, store.legacyStateDir, store.legacyStateDir2, store.legacyStateDir3]
    running: true
  }

  // Write-only handle for drag order. Never loaded.
  FileView {
    id: orderFile
    path: store.orderPath
    preload: false
    printErrors: false
    atomicWrites: true
  }

  // Config apps removed from the dock. Suppressed here rather than by
  // rewriting UserConfig.qml, which is the user's to own.
  FileView {
    id: hiddenFile
    path: store.hiddenPath
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: store.readStateFile("hidden", store.hiddenPath)
  }

  // Written by bin/quickshelldock-pin, never by the dock. Watching it is what
  // makes a pin from the Omarchy menu show up without a restart.
  FileView {
    id: pinsFile
    path: store.pinsPath
    preload: false
    printErrors: false
    watchChanges: true
    onFileChanged: store.readStateFile("pins", store.pinsPath)
  }

  // Settings are written only by this process (Settings panel / reset), so
  // unlike pins/hidden there is no external writer to watch for.
  FileView {
    id: settingsFile
    path: store.settingsPath
    preload: false
    printErrors: false
    atomicWrites: true
  }

  function readStateFile(kind, path) {
    if (stateReader.running) {
      stateReader.pendingQueue.push({ kind: kind, path: path })
      return
    }
    stateReader.kind = kind
    stateReader.command = ["head", "-c", String(store.maxStateBytes), "--", path]
    stateReader.running = true
  }

  function consumeStateFile(kind, raw) {
    if (raw.length >= store.maxStateBytes)
      console.warn("quickshelldock:", kind + ".json", "is at or over the",
        store.maxStateBytes, "byte read ceiling; ignoring it")
    if (kind === "order") {
      order = StateLogic.parseJsonArray(raw, store.maxStateBytes)
      orderLoaded()
    } else if (kind === "pins") {
      pins = StateLogic.parseJsonArray(raw, store.maxStateBytes)
      pinsLoaded()
    } else if (kind === "hidden") {
      hidden = StateLogic.parseJsonArray(raw, store.maxStateBytes)
      hiddenLoaded()
    } else if (kind === "settings") {
      settings = StateLogic.parseJsonObject(raw, store.maxStateBytes)
      settingsLoaded()
    }
  }

  function writeOrder(names) {
    order = names
    orderFile.setText(JSON.stringify(names, null, 2) + "\n")
  }

  function writeSettings(obj) {
    settings = obj
    settingsFile.setText(JSON.stringify(obj, null, 2) + "\n")
  }

  Component.onCompleted: {
    readStateFile("order", orderPath)
    readStateFile("pins", pinsPath)
    readStateFile("hidden", hiddenPath)
    readStateFile("settings", settingsPath)
  }
}
