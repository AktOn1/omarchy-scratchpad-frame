import QtQuick
import qs.Commons
import qs.Ui

// Shows a key and, when clicked, waits for the next key combination.
Button {
  id: root

  required property var source
  property string slot: ""
  property string value: ""
  property string emptyText: "not set"
  readonly property string tag: source.name + "|" + slot
  readonly property bool waiting: source.window.capturing === tag

  text: waiting ? "press the keys... (Esc cancels, Backspace clears)" : (value !== "" ? value : emptyText)
  bordered: true
  focusable: true
  active: waiting
  fontFamily: source.fontFamily
  foreground: source.foreground
  onClicked: source.window.beginCapture(tag)
}
