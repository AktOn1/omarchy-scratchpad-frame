import QtQuick
import "AktKit.js" as Model

// Takes the keyboard while a key is being picked: Esc cancels, Backspace clears.
Item {
  id: root

  required property var window
  readonly property bool active: window.capturing !== ""

  onActiveChanged: {
    if (active) forceActiveFocus()
    else if (parent) parent.forceActiveFocus()
  }

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
