import QtQuick
import QtQuick.Window
import qs.Ui

// A one-line text box that only exists while it can be seen and typed into, and ignores paste.
// Why: a native text field reads whatever the clipboard holds every time any other program changes it, even while the
// form is hidden, so a clipboard owner that sends a huge or never-ending value could stall the shell. This box is created
// only while its window is open and it is on screen, and it never reads the clipboard: Ctrl+V, Shift+Insert, Ctrl+Shift+V
// and middle click are swallowed. Typing, selecting, Enter and Escape work as usual. `text` lives here, so it survives the
// box being taken down and is always bounded by maximumLength.
Item {
  id: gf

  property string text: ""
  property string placeholderText: ""
  property int maximumLength: 300
  property bool readOnly: false
  property color foreground: "white"
  property string fontFamily: ""
  property real fontPixelSize: 0          // 0 = the kit's default size
  property real verticalPadding: -1       // -1 = the kit's default padding

  signal accepted()
  signal editingFinished()
  signal escaped()
  property bool handleEscape: false       // true: Escape is taken here and `escaped` fires; false: it goes on to the window

  // The window is open and this box is on screen.
  readonly property bool live: visible && Window.window !== null && Window.window.visible
  readonly property bool typing: loader.item !== null && loader.item.activeFocus   // the cursor is in the box
  property bool _alive: false
  property bool _dirty: false

  implicitHeight: loader.item ? loader.item.implicitHeight : 30
  height: implicitHeight

  function _flush() { if (_dirty) { _dirty = false; editingFinished() } }

  onLiveChanged: { if (live) _alive = true; else { _flush(); _alive = false } }
  Component.onCompleted: _alive = live

  Loader {
    id: loader
    anchors.fill: parent
    active: gf._alive
    sourceComponent: Component {
      TextField {
        id: field
        foreground: gf.foreground
        placeholderText: gf.placeholderText
        maximumLength: gf.maximumLength
        readOnly: gf.readOnly
        font.family: gf.fontFamily !== "" ? gf.fontFamily : Style.font.family
        font.pixelSize: gf.fontPixelSize > 0 ? gf.fontPixelSize : Style.font.body
        verticalPadding: gf.verticalPadding >= 0 ? gf.verticalPadding : Style.spacing.inputPaddingY
        onTextEdited: { gf.text = text; gf._dirty = true }
        Binding { target: field; property: "text"; value: gf.text }
        onAccepted: gf.accepted()
        onEditingFinished: { gf._dirty = false; gf.editingFinished() }
        Keys.onEscapePressed: function(event) { if (gf.handleEscape) { event.accepted = true; gf.escaped() } else event.accepted = false }
        Keys.onPressed: function(event) {
          if (event.matches(StandardKey.Paste)
              || ((event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert)
              || ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_V))
            event.accepted = true
        }
      }
    }
  }
  // middle click would paste the primary selection
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
  }
}
