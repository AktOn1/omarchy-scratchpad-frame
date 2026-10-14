// Offscreen preview renderer. Usage:
//   QT_QPA_PLATFORM=offscreen qml6 tests/render.qml -- OUTDIR STYLE[,STYLE...] [theme.toml] [follow]
// "follow" as last argument recolours the style from the theme. Paint times go to the console.
// Own ornament (style OWNART): add  own=/path/to/ornaments/ID  (the folder that holds ID.png, then /ID) as an argument.
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
  property bool follow: args.indexOf("follow") > 0
  property string themeFile: args.length > sep + 3 && args[sep + 3] !== "follow" && args[sep + 3] !== "fit" ? args[sep + 3] : ""
  property var colors: ({})
  property string own: { for (const a of args) if (a.indexOf("own=") === 0) return a.slice(4); return "" }
  property bool fitted: args.indexOf("fit") > 0   // "fit" as an argument: small window, frame hugs it and may use the outer contour
  property int idx: 0
  property int bleed: fitted ? Painter.bleedFor(styles[idx]) : 0

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
  Rectangle { x: fitted ? 560 : 26; y: fitted ? 290 : 26; width: fitted ? 800 : parent.width - 52; height: fitted ? 500 : parent.height - 52; radius: 8; color: "#0c0e1a"
    Text { anchors.centerIn: parent; color: "#8890b0"; font.pixelSize: 28; text: "terminal window" } }

  Canvas {
    id: cv
    x: win.fitted ? 534 - win.bleed : 0
    y: win.fitted ? 264 - win.bleed : 0
    width: win.fitted ? 852 + 2 * win.bleed : parent.width
    height: win.fitted ? 552 + 2 * win.bleed : parent.height
    renderStrategy: Canvas.Immediate
    onImageLoaded: requestPaint()
    onPaint: {
      const ctx = getContext("2d")
      const t0 = Date.now()
      Painter.paint(ctx, width, height, { bleed: win.bleed, style: win.styles[win.idx], text: "SCRATCHPAD",
        colors: win.colors, px: 3, font: "monospace", follow: win.follow,
        ornament: win.own ? win.own.slice(win.own.lastIndexOf("/") + 1) : "", ornaments: win.own ? "file://" + win.own.slice(0, win.own.lastIndexOf("/") + 1) : "", assets: Qt.resolvedUrl("../assets/").toString() })
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
