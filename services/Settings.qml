pragma Singleton

import QtQml
import Quickshell
import "../logic/settings.js" as SettingsLogic

// Live settings shared across every panel. Holds the schema, applies the
// clamp from SettingsLogic at ingestion, and writes through StateStore.
Singleton {
  id: settings

  property int iconSize: SettingsLogic.DEFAULTS.iconSize
  property int spacing: SettingsLogic.DEFAULTS.spacing
  property int spacerWidth: SettingsLogic.DEFAULTS.spacerWidth
  property string mode: SettingsLogic.DEFAULTS.mode
  property bool magnify: SettingsLogic.DEFAULTS.magnify
  property bool showMenu: SettingsLogic.DEFAULTS.showMenu

  function apply(raw) {
    const n = SettingsLogic.normalize(raw)
    iconSize = n.iconSize
    spacing = n.spacing
    spacerWidth = n.spacerWidth
    mode = n.mode
    magnify = n.magnify
    showMenu = n.showMenu
  }

  function save() {
    StateStore.writeSettings({ iconSize: iconSize, spacing: spacing, spacerWidth: spacerWidth, mode: mode, magnify: magnify, showMenu: showMenu })
  }

  function reset() {
    apply(SettingsLogic.DEFAULTS)
    save()
  }

  Component.onCompleted: apply(StateStore.settings)

  Connections {
    target: StateStore
    function onSettingsLoaded() { settings.apply(StateStore.settings) }
  }
}
