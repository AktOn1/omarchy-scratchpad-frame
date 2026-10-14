import QtQuick
import Quickshell
import qs.Commons

// The frame picker for one scratchpad, shown below that scratchpad's settings.
// Categories on the left, styles in the middle (the shared SectionMenu), a close-up of the highlighted style's top-left corner below.
// Hovering or moving onto a style previews it on the scratchpad; Enter or a click keeps it.
// The bar widget (`host`) owns the state read from the plugin's own commands; this file only shows it.
Column {
  id: pick

  required property var host
  property string padId: ""

  readonly property color fg: Color.popups.text
  readonly property string boxOn: "󰄲"
  readonly property string boxOff: "󰄱"
  readonly property real thumbSpan: 760   // the thumbnail shows the top-left 760 px of the screen, where the corner art is

  readonly property var padInfo: {
    for (var i = 0; i < host.pads.length; i++) if (host.pads[i].name === padId) return host.pads[i]
    return null
  }
  readonly property string padLabel: padInfo ? padInfo.label : "SCRATCHPAD"
  readonly property bool ownStyle: padInfo !== null && padInfo.style !== ""
  readonly property string padCurrent: ownStyle ? padInfo.style : host.current

  property string shownStyle: padCurrent
  property string previewId: ""
  property string flash: ""

  spacing: Style.space(6)

  function say(t) { flash = t; flashTimer.restart() }
  Timer { id: flashTimer; interval: 2500; onTriggered: pick.flash = "" }

  function keep(name) {
    host.keep(padId, name)
    say(host.menu.pretty(name) + " kept for " + padLabel)
  }

  Timer {
    id: previewTimer
    interval: 250
    onTriggered: if (pick.previewId !== "" && pick.padId !== "") host.cmd(["previewPad", pick.previewId, pick.padId])
  }
  onPadCurrentChanged: if (previewId === "") shownStyle = padCurrent
  onPadIdChanged: { previewId = ""; shownStyle = padCurrent; Qt.callLater(sec.sync) }
  Component.onCompleted: { host.refresh(); sec.sync() }
  Component.onDestruction: {
    previewTimer.stop()
    Quickshell.execDetached(["omarchy-shell", "-q", "scratchpad-frame", "previewEnd"])
  }

  Keys.onPressed: function(e) {
    var t = e.text
    if (e.key === Qt.Key_Left || t === "h") sec.move(-1, 0)
    else if (e.key === Qt.Key_Right || t === "l") { if (sec.move(1, 0) === 1) sec.activate() }
    else if (e.key === Qt.Key_Down || t === "j") sec.move(0, 1)
    else if (e.key === Qt.Key_Up || t === "k") sec.move(0, -1)
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) sec.activate()
    else if (e.key === Qt.Key_Tab && sec.cats.length > 0) sec.gotoCat((sec.catIdx + 1) % sec.cats.length)
    else if (e.key === Qt.Key_Backtab && sec.cats.length > 0) sec.gotoCat((sec.catIdx - 1 + sec.cats.length) % sec.cats.length)
    else if (t === "g") sec.jump(false)
    else if (t === "G") sec.jump(true)
    else if (t === "f") { host.toggleFollow(); say(host.follow ? "Following desktop colors" : "Each style keeps its own colors") }
    else if (t === "t") { host.toggleTitle(); say(host.showTitle ? "Title shown" : "Title hidden") }
    else if (t >= "1" && t <= "9") sec.gotoCat(parseInt(t) - 1)
    else return
    e.accepted = true
  }

  Row {
    id: header
    width: pick.width
    height: Style.space(28)
    spacing: Style.space(6)
    readonly property real cell: (width - spacing) / 2

    MenuRow {
      width: header.cell
      fg: pick.fg
      fontFamily: host.bar.fontFamily
      label: (host.follow ? pick.boxOn : pick.boxOff) + "  Follow desktop colors  (f)"
      onClicked: { host.toggleFollow(); pick.say(host.follow ? "Following desktop colors" : "Each style keeps its own colors") }
    }
    MenuRow {
      width: header.cell
      fg: pick.fg
      fontFamily: host.bar.fontFamily
      label: (host.showTitle ? pick.boxOn : pick.boxOff) + "  Show title  (t)"
      onClicked: { host.toggleTitle(); pick.say(host.showTitle ? "Title shown" : "Title hidden") }
    }
  }

  Rectangle { width: pick.width; height: 1; color: Qt.rgba(pick.fg.r, pick.fg.g, pick.fg.b, 0.2) }

  FrameDesigner { width: pick.width; host: pick.host; padId: pick.padId; fg: pick.fg }

  Rectangle { width: pick.width; height: 1; color: Qt.rgba(pick.fg.r, pick.fg.g, pick.fg.b, 0.2) }

  Row {
    id: body
    width: pick.width
    spacing: Style.space(14)

    SectionMenu {
      id: sec
      width: Math.round((pick.width - body.spacing) * 0.56)
      title: "Frame for " + pick.padLabel
      fg: pick.fg
      fontFamily: host.bar.fontFamily
      cats: host.cats
      saved: pick.padCurrent
      favs: []
      focused: true
      visibleRows: 7
      onFocusRequested: pick.forceActiveFocus()
      onPointed: function(item) {
        pick.shownStyle = item.id
        pick.previewId = item.id
        previewTimer.restart()
      }
      onChosen: function(item, keepOpen) { pick.forceActiveFocus(); pick.keep(item.id) }
      onActed: function(id) {}
    }

    Column {
      id: side
      width: pick.width - body.spacing - sec.width
      spacing: Style.space(6)

      Rectangle {
        id: thumb
        width: Math.min(pick.width, Style.space(300))
        height: Math.round(width * 9 / 16)
        radius: Style.space(6)
        clip: true
        color: Qt.rgba(pick.fg.r, pick.fg.g, pick.fg.b, 0.08)

        Rectangle {
          x: parent.width * 26 / pick.thumbSpan
          y: x
          width: parent.width - x + 10
          height: parent.height - y + 10
          radius: 3
          color: Qt.rgba(0, 0, 0, 0.55)
        }
        Canvas {
          id: thumbCanvas
          anchors.fill: parent
          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          Connections {
            target: pick
            function onShownStyleChanged() { thumbCanvas.requestPaint() }
          }
          Connections {
            target: pick.host
            function onFollowChanged() { thumbCanvas.requestPaint() }
            function onThemeColorsChanged() { thumbCanvas.requestPaint() }
            function onPainterChanged() { thumbCanvas.requestPaint() }
            function onAssetRevChanged() { thumbCanvas.requestPaint() }
          }
          onPaint: host.painter.paint(getContext("2d"), 1920, 1080, {
            style: pick.shownStyle, text: "", colors: pick.host.themeColors, px: 3,
            font: "monospace", follow: pick.host.follow, scale: width / pick.thumbSpan,
            assets: Qt.resolvedUrl("assets/").toString(), rev: host.assetRev
          })
          onImageLoaded: requestPaint()
          Component.onCompleted: requestPaint()
          Timer {
            interval: 400
            repeat: true
            running: true
            property int n: 0
            onTriggered: { thumbCanvas.requestPaint(); if (++n >= 3) stop() }
          }
        }
      }

      Text {
        width: side.width
        leftPadding: Style.space(4)
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: {
          if (pick.flash !== "") return pick.flash
          if (host.styles.length === 0) return "Loading the style list…"
          var it = sec.selected
          if (it) return it.label + (it.desc ? ": " + it.desc : "")
          return "Style: " + host.menu.pretty(pick.padCurrent || "?") + (host.follow ? " · desktop colors" : "")
        }
        color: pick.fg
        font.family: host.bar.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        width: side.width
        leftPadding: Style.space(4)
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: "Click or hjkl and ⏎ to keep · tab group · f follow desktop colors · t show title"
        opacity: 0.6
        color: pick.fg
        font.family: host.bar.fontFamily
        font.pixelSize: Style.font.body * 0.85
      }
    }
  }
}
