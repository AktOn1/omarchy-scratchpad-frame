import QtQuick
import qs.Commons
import qs.Ui

// A search box with its matches listed right below it (no popup). Replaces the shell's searchable dropdown, whose search
// box is a native text input that reads the clipboard by itself. `options` is [{ value, label, description }].
// Down/Up pick a match, Enter adds the picked (else the first) match, Escape clears the search; a click on a row adds it.
Column {
  id: root

  property var options: []
  property color foreground: "white"
  property string fontFamily: ""
  property string placeholderText: "Search..."
  property string emptyText: "No matches"
  property int maxRows: 6
  signal chosen(string value)

  property int current: -1
  readonly property string query: field.text.trim().toLowerCase()
  readonly property var hits: {
    if (query === "") return []
    var out = []
    for (var i = 0; i < options.length; i++) {
      var o = options[i]
      if (String(o.label).toLowerCase().indexOf(query) !== -1 || String(o.description || "").toLowerCase().indexOf(query) !== -1) out.push(o)
    }
    return out
  }
  readonly property var shown: hits.slice(0, maxRows)

  spacing: Style.spacing.labelGap
  onHitsChanged: current = -1

  function choose(i) {
    if (shown.length === 0) return
    var o = shown[i >= 0 && i < shown.length ? i : 0]
    field.text = ""
    root.chosen(String(o.value))
  }

  PlainField {
    id: field
    width: parent.width
    maximumLength: 80
    placeholderText: root.placeholderText
    foreground: root.foreground
    fontFamily: root.fontFamily
    handleEscape: true
    onEscaped: { text = ""; root.current = -1 }
    onAccepted: root.choose(root.current)
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Down) { root.current = Math.min(root.shown.length - 1, root.current + 1); event.accepted = true }
      else if (event.key === Qt.Key_Up) { root.current = Math.max(-1, root.current - 1); event.accepted = true }
    }
  }

  Text {
    visible: root.query !== "" && root.shown.length === 0
    width: parent.width
    leftPadding: Style.spacing.controlPaddingX
    textFormat: Text.PlainText
    text: root.emptyText
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily !== "" ? root.fontFamily : Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.shown
    delegate: Rectangle {
      required property var modelData
      required property int index
      width: root.width
      height: Math.max(Style.spacing.popupRowHeight, rowText.implicitHeight + Style.spacing.rowPaddingX)
      radius: Style.cornerRadius
      color: index === root.current ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

      Column {
        id: rowText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.controlPaddingX
        anchors.rightMargin: Style.spacing.controlPaddingX
        spacing: Style.spacing.xxs
        Text {
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: String(modelData.label)
          color: root.foreground
          font.family: root.fontFamily !== "" ? root.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }
        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: String(modelData.description || "")
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily !== "" ? root.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPositionChanged: root.current = parent.index
        onClicked: root.choose(parent.index)
      }
    }
  }
}
