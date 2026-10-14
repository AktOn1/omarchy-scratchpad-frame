import QtQuick
import Quickshell
import "AktKit.js" as Model

// Takes the keyboard while a key is being picked: Esc cancels, Backspace clears.
Item {
  id: root

  required property var window
  readonly property bool active: window.capturing !== ""

  // Hyprland takes every bound key (Super+...) before the window sees it. An empty submap lets them through while picking.
  function hold(on) {
    const code = on
      ? 'if not AktCaptureMap then AktCaptureMap = true; hl.define_submap("akt_capture", function() hl.bind("XF86Launch9", hl.dsp.no_op()) end) end; '
        + 'hl.dispatch(hl.dsp.submap("akt_capture"))'
      : 'hl.dispatch(hl.dsp.submap("reset"))'
    Quickshell.execDetached(["hyprctl", "eval", code])
  }

  onActiveChanged: {
    hold(active)
    if (active) { forceActiveFocus(); giveUp.restart() }
    else { giveUp.stop(); if (parent) parent.forceActiveFocus() }
  }
  Component.onDestruction: if (active) hold(false)

  Timer { id: giveUp; interval: 20000; onTriggered: root.window.cancelCapture() }

  Keys.onPressed: function(event) {
    if (!active) return
    event.accepted = true
    if (event.key === Qt.Key_Escape) { window.cancelCapture(); return }
    if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { window.finishCapture("none"); return }
    const m = event.modifiers
    const key = Model.keyFromEvent(event.key, (m & Qt.ControlModifier) !== 0, (m & Qt.AltModifier) !== 0,
                                   (m & Qt.ShiftModifier) !== 0, (m & Qt.MetaModifier) !== 0)
    if (key !== "") window.finishCapture(key)
  }
}
