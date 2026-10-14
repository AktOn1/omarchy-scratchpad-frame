import QtQuick
import qs.Commons

// SHARED SOURCE (omarchy-plugins/shared/menu/MenuRow.qml). Do not edit the copy inside a plugin; edit the shared file and run
// omarchy-plugins/tools/sync-shared.sh. A small button row for the menu header (toggles and actions).
Rectangle {
  id: row
  property string label: ""
  property bool dim: false
  property color fg: "white"
  property string fontFamily: ""
  signal clicked()
  width: parent ? parent.width : 0
  height: Style.space(28)
  radius: Style.space(6)
  color: mouse.containsMouse && !dim ? Qt.rgba(fg.r, fg.g, fg.b, 0.14) : Qt.rgba(fg.r, fg.g, fg.b, 0.06)
  opacity: dim ? 0.4 : 1

  Text {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    textFormat: Text.PlainText
    text: row.label
    color: row.fg
    font.family: row.fontFamily
    font.pixelSize: Style.font.body
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: row.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: if (!row.dim) row.clicked()
  }
}
