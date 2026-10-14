// Offscreen check that EVERY Canvas (one per monitor in the shell) loads the frame pictures.
//   QT_QPA_PLATFORM=offscreen qml6 tests/twocanvas.qml -- OUTDIR STYLE
import QtQuick
import QtQuick.Window
import "../FramePainter.js" as Painter

Window {
  id: win
  width: 1920; height: 540; visible: true; color: "#101018"
  property var args: Qt.application.arguments
  property int sep: args.indexOf("--")
  property string outDir: args[sep + 1]
  property string style: args[sep + 2]
  Repeater {
    model: 2
    Canvas {
      y: index * 270; width: 960; height: 270
      renderStrategy: Canvas.Cooperative
      onImageLoaded: requestPaint()
      onPaint: Painter.paint(getContext("2d"), width, height, { style: win.style, text: "", colors: ({}), px: 3, font: "monospace", follow: false,
        assets: Qt.resolvedUrl("../assets/").toString() })
      Component.onCompleted: requestPaint()
    }
  }
  Timer { interval: 1500; running: true; onTriggered: win.contentItem.grabToImage(function(r) { r.saveToFile(win.outDir + "/two-" + win.style + ".png"); Qt.quit() }) }
}
