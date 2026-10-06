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
  property int showDelay: SettingsLogic.DEFAULTS.showDelay
  property int hideDelay: SettingsLogic.DEFAULTS.hideDelay
  property int animationTime: SettingsLogic.DEFAULTS.animationTime
  property string transparencyMode: SettingsLogic.DEFAULTS.transparencyMode
  property real minAlpha: SettingsLogic.DEFAULTS.minAlpha
  property real maxAlpha: SettingsLogic.DEFAULTS.maxAlpha
  property string indicatorStyle: SettingsLogic.DEFAULTS.indicatorStyle
  property string clickAction: SettingsLogic.DEFAULTS.clickAction
  property string scrollAction: SettingsLogic.DEFAULTS.scrollAction
  property bool intellihide: SettingsLogic.DEFAULTS.intellihide
  property string intellihideMode: SettingsLogic.DEFAULTS.intellihideMode
  property string position: SettingsLogic.DEFAULTS.position
  property bool urgentWiggle: SettingsLogic.DEFAULTS.urgentWiggle

  function apply(raw) {
    const n = SettingsLogic.normalize(raw)
    iconSize = n.iconSize
    spacing = n.spacing
    spacerWidth = n.spacerWidth
    mode = n.mode
    magnify = n.magnify
    showMenu = n.showMenu
    showDelay = n.showDelay
    hideDelay = n.hideDelay
    animationTime = n.animationTime
    transparencyMode = n.transparencyMode
    minAlpha = n.minAlpha
    maxAlpha = n.maxAlpha
    indicatorStyle = n.indicatorStyle
    clickAction = n.clickAction
    scrollAction = n.scrollAction
    intellihide = n.intellihide
    intellihideMode = n.intellihideMode
    position = n.position
    urgentWiggle = n.urgentWiggle
  }

  function save() {
    StateStore.writeSettings({
      iconSize: iconSize,
      spacing: spacing,
      spacerWidth: spacerWidth,
      mode: mode,
      magnify: magnify,
      showMenu: showMenu,
      showDelay: showDelay,
      hideDelay: hideDelay,
      animationTime: animationTime,
      transparencyMode: transparencyMode,
      minAlpha: minAlpha,
      maxAlpha: maxAlpha,
      indicatorStyle: indicatorStyle,
      clickAction: clickAction,
      scrollAction: scrollAction,
      intellihide: intellihide,
      intellihideMode: intellihideMode,
      position: position,
      urgentWiggle: urgentWiggle,
    })
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
