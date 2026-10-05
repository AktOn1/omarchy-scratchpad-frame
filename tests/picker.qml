// Offscreen render of the picker. Usage:
//   QT_QPA_PLATFORM=offscreen qml6 tests/picker.qml -- OUT.png [theme.toml]
import QtQuick
import QtQuick.Window
import ".."
import "../FramePainter.js" as Painter

Window {
  id: win
  width: 1920; height: 1080; visible: true; color: "#101018"
  property var args: Qt.application.arguments
  property int sep: args.indexOf("--")
  property var colors: ({})
  Component.onCompleted: {
    if (args.length > sep + 2) {
      const x = new XMLHttpRequest()
      x.open("GET", "file://" + args[sep + 2], false); x.send()
      const c = {}
      for (const line of x.responseText.split("\n")) {
        const m = line.match(/^\s*([a-z_0-9]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (m) c[m[1]] = m[2]
      }
      colors = c
    }
    t.start()
  }
  Rectangle { anchors.fill: parent; color: "#0c0e1a" }
  StylePicker {
    anchors.fill: parent
    names: Painter.NAMES
    colors: win.colors
    current: "CRYSTAL"
    follow: true
    selected: 2
  }
  Timer { id: t; interval: 800; onTriggered: win.contentItem.grabToImage(function(r) {
    r.saveToFile(win.args[win.sep + 1]); Qt.quit() }) }
}
