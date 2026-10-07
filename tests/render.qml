// Offscreen preview renderer. Usage:
//   QT_QPA_PLATFORM=offscreen qml6 tests/render.qml -- OUTDIR STYLE[,STYLE...] [theme.toml] [follow]
// "follow" as last argument recolours the style from the theme. Paint times go to the console.
// Writes OUTDIR/STYLE.png: a 1920x1080 fake desktop with a window inset 26 px and the frame drawn on top.
import QtQuick
import QtQuick.Window
import "../FramePainter.js" as Painter

Window {
  id: win
  width: 1920; height: 1080; visible: true; color: "#101018"
  property var args: Qt.application.arguments
  property int sep: args.indexOf("--")
  property string outDir: args[sep + 1]
  property var styles: args[sep + 2].split(",")
  property bool follow: args[args.length - 1] === "follow"
  property string themeFile: args.length > sep + 3 && args[sep + 3] !== "follow" ? args[sep + 3] : ""
  property var colors: ({})
  property int idx: 0

  Component.onCompleted: {
    if (themeFile) {
      const x = new XMLHttpRequest()
      x.open("GET", "file://" + themeFile, false); x.send()
      const c = {}
      for (const line of x.responseText.split("\n")) {
        const m = line.match(/^\s*([a-z_0-9]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (m) c[m[1]] = m[2]
      }
      colors = c
    }
    next()
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: "#2a3358" }
      GradientStop { position: 1; color: "#6b3f5e" }
    }
  }
  Rectangle { x: 26; y: 26; width: parent.width - 52; height: parent.height - 52; radius: 8; color: "#0c0e1a"
    Text { anchors.centerIn: parent; color: "#8890b0"; font.pixelSize: 28; text: "terminal window" } }

  Canvas {
    id: cv
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    onImageLoaded: requestPaint()
    onPaint: {
      const ctx = getContext("2d")
      const t0 = Date.now()
      Painter.paint(ctx, width, height, { style: win.styles[win.idx], text: "SCRATCHPAD",
        colors: win.colors, px: 3, font: "monospace", follow: win.follow, assets: Qt.resolvedUrl("../assets/").toString() })
      console.log("paint " + win.styles[win.idx] + " " + (Date.now() - t0) + " ms")
    }
  }

  Timer {
    id: t; interval: 400; onTriggered: {
      win.contentItem.grabToImage(function(r) {
        r.saveToFile(win.outDir + "/" + win.styles[win.idx] + ".png")
        win.idx++
        if (win.idx >= win.styles.length) Qt.quit(); else next()
      })
    }
  }
  function next() { cv.requestPaint(); t.restart() }
}
