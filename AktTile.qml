import QtQuick
import qs.Commons
import qs.Ui
import "AktKit.js" as Model

// One layer as a small rectangle: name, key, the main facts, Show and Edit. Clicking the rectangle edits it.
Rectangle {
  id: root

  required property var source
  required property var entry
  property bool connected: false
  signal edit()

  readonly property bool isLayer: entry.layer === true
  readonly property string userKey: isLayer ? (source.snap.detected.fullscreen || "") : (source.snap.detected.pads[entry.id] || "")
  readonly property string keyText: entry.key !== "" ? entry.key
      : (userKey !== "" ? userKey : (entry.builtin ? "SUPER + S" : "no key yet"))
  readonly property int running: source.snap.running ? (source.snap.running[entry.id] || 0) : 0
  readonly property bool isMagnet: source.snap.fullscreen.on && (isLayer || connected)
      && (isLayer ? source.snap.fullscreen.magnet === "" : source.snap.fullscreen.magnet === entry.id)
  readonly property string facts: Model.motionText(entry) + (isLayer && !connected ? "" : " · " + (entry.layout !== "" ? entry.layout.replace(/^lua:/, "") : "default layout"))
  readonly property color fg: source.foreground

  implicitHeight: info.implicitHeight + buttons.implicitHeight + Style.space(10) + Style.space(8) + Style.space(8)
  radius: Style.space(6)
  color: Qt.rgba(fg.r, fg.g, fg.b, hover.containsMouse ? 0.10 : 0.05)
  border.width: 1
  border.color: Qt.rgba(fg.r, fg.g, fg.b, hover.containsMouse ? 0.5 : 0.25)

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.edit()
  }

  Column {
    id: info
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    spacing: Style.space(3)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.entry.label
      elide: Text.ElideRight
      color: root.fg
      font.family: root.source.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.keyText
      elide: Text.ElideRight
      color: root.entry.key !== "" || root.userKey !== "" || root.entry.builtin ? root.fg : root.source.dim
      font.family: root.source.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: root.facts
      elide: Text.ElideRight
      color: root.source.dim
      font.family: root.source.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: [root.isMagnet ? "games land here" : "", root.running > 0 ? root.running + " app" + (root.running > 1 ? "s" : "") + " open" : ""]
              .filter(t => t !== "").join(" · ")
      visible: text !== ""
      elide: Text.ElideRight
      color: root.source.dim
      font.family: root.source.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    id: buttons
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(8)
    spacing: Style.space(6)
    Button {
      text: "Show"
      bordered: true
      focusable: true
      fontFamily: root.source.fontFamily
      foreground: root.fg
      tooltipText: root.isLayer ? "Show or hide this layer (opens only when something is on it)" : "Slide this scratchpad in or out"
      onClicked: root.source.run(["toggle", root.entry.id])
    }
    Button {
      text: "Edit"
      bordered: true
      focusable: true
      fontFamily: root.source.fontFamily
      foreground: root.fg
      onClicked: root.edit()
    }
  }
}
