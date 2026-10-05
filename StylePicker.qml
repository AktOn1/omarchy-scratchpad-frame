// Centered style list. Up/Down (or j/k) move, Enter picks, Esc closes, click picks.
// The last rows: switches "Follow Omarchy theme colors" (F) and "Show title" (T), then the button "Create theme from wallpaper..." (W);
// Enter/Space/click toggles the selected switch or presses the button.
// Moving previews the style on the frame (only committed on pick).
import QtQuick

Item {
  id: pk

  property var names: []
  property var colors: ({})
  property string current: ""
  property bool follow: false
  property bool showTitle: true
  property string font: "monospace"
  property int selected: 0

  signal picked(string name)
  signal closed()
  signal followToggled()
  signal titleToggled()
  signal themeFromWallpaper()

  // 36 px rows, squeezed when the list would not fit the screen
  readonly property int rowH: Math.max(22, Math.min(36, Math.floor((height - 200) / (names.length + 3))))

  function c(name, fallback) { return colors[name] || fallback }

  onCurrentChanged: selected = Math.max(0, names.indexOf(current))
  onNamesChanged: selected = Math.max(0, names.indexOf(current))

  function move(d) {
    const n = names.length + 3
    selected = (selected + d + n) % n
  }

  focus: true
  Keys.onPressed: (e) => {
    switch (e.key) {
    case Qt.Key_Up: case Qt.Key_K: case Qt.Key_Backtab: move(-1); break
    case Qt.Key_Down: case Qt.Key_J: case Qt.Key_Tab: move(1); break
    case Qt.Key_Home: selected = 0; break
    case Qt.Key_End: selected = names.length + 2; break
    case Qt.Key_F: pk.followToggled(); break
    case Qt.Key_T: pk.titleToggled(); break
    case Qt.Key_W: pk.themeFromWallpaper(); break
    case Qt.Key_Space:
      if (selected === names.length) pk.followToggled()
      else if (selected === names.length + 1) pk.titleToggled()
      else if (selected === names.length + 2) pk.themeFromWallpaper()
      else return
      break
    case Qt.Key_Return: case Qt.Key_Enter:
      if (selected === names.length) pk.followToggled()
      else if (selected === names.length + 1) pk.titleToggled()
      else if (selected === names.length + 2) pk.themeFromWallpaper()
      else if (names.length) pk.picked(names[selected])
      break
    case Qt.Key_Escape: case Qt.Key_Q: pk.closed(); break
    default: return
    }
    e.accepted = true
  }

  MouseArea { anchors.fill: parent; onClicked: pk.closed() }

  Rectangle {
    id: box
    anchors.centerIn: parent
    width: 460
    height: header.height + (pk.names.length + 3) * pk.rowH + 12 + footer.height + 70
    radius: 12
    color: pk.c("background", "#101018")
    border.width: 2
    border.color: pk.c("accent", "#7d82d9")

    MouseArea { anchors.fill: parent }

    Text {
      id: header
      x: 24; y: 18
      text: "Scratchpad frame"
      color: pk.c("accent", "#7d82d9")
      font.family: pk.font; font.pixelSize: 18; font.bold: true
    }

    Column {
      x: 12; y: header.y + header.height + 14
      width: parent.width - 24

      Repeater {
        model: pk.names
        delegate: Rectangle {
          id: row
          required property int index
          required property string modelData
          width: parent.width; height: pk.rowH
          radius: 8
          readonly property bool sel: pk.selected === index
          color: sel ? pk.c("selection", "#252e56") : "transparent"
          border.width: sel ? 1 : 0
          border.color: pk.c("accent", "#7d82d9")

          Text {
            x: 14; anchors.verticalCenter: parent.verticalCenter
            text: row.modelData
            color: row.sel ? pk.c("bright_foreground", "#ffffff") : pk.c("foreground", "#cccccc")
            font.family: pk.font; font.pixelSize: 15; font.bold: row.sel
          }
          Text {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            visible: pk.current === row.modelData
            text: "●"
            color: pk.c("accent", "#7d82d9")
            font.family: pk.font; font.pixelSize: 13
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: pk.selected = row.index
            onClicked: pk.picked(row.modelData)
          }
        }
      }
    }

    Rectangle {
      id: followRow
      x: 12; width: parent.width - 24; height: pk.rowH
      y: header.y + header.height + 14 + pk.names.length * pk.rowH + 12
      radius: 8
      readonly property bool sel: pk.selected === pk.names.length
      color: sel ? pk.c("selection", "#252e56") : "transparent"
      border.width: sel ? 1 : 0
      border.color: pk.c("accent", "#7d82d9")

      Rectangle {
        x: 0; y: -7; width: parent.width; height: 1
        color: pk.c("muted", "#888888"); opacity: 0.5
      }
      Text {
        x: 14; anchors.verticalCenter: parent.verticalCenter
        text: "Follow Omarchy theme colors"
        color: followRow.sel ? pk.c("bright_foreground", "#ffffff") : pk.c("foreground", "#cccccc")
        font.family: pk.font; font.pixelSize: 14; font.bold: followRow.sel
      }
      Rectangle {
        id: sw
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: 36; height: 18; radius: 9
        color: pk.follow ? pk.c("accent", "#7d82d9") : "transparent"
        border.width: 1.5
        border.color: pk.follow ? pk.c("accent", "#7d82d9") : pk.c("muted", "#888888")
        Rectangle {
          y: 3; width: 12; height: 12; radius: 6
          x: pk.follow ? parent.width - width - 3 : 3
          color: pk.follow ? pk.c("background", "#101018") : pk.c("muted", "#888888")
        }
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: pk.selected = pk.names.length
        onClicked: pk.followToggled()
      }
    }

    Rectangle {
      id: titleRow
      x: 12; width: parent.width - 24; height: pk.rowH
      y: followRow.y + pk.rowH
      radius: 8
      readonly property bool sel: pk.selected === pk.names.length + 1
      color: sel ? pk.c("selection", "#252e56") : "transparent"
      border.width: sel ? 1 : 0
      border.color: pk.c("accent", "#7d82d9")

      Text {
        x: 14; anchors.verticalCenter: parent.verticalCenter
        text: "Show title"
        color: titleRow.sel ? pk.c("bright_foreground", "#ffffff") : pk.c("foreground", "#cccccc")
        font.family: pk.font; font.pixelSize: 14; font.bold: titleRow.sel
      }
      Rectangle {
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: 36; height: 18; radius: 9
        color: pk.showTitle ? pk.c("accent", "#7d82d9") : "transparent"
        border.width: 1.5
        border.color: pk.showTitle ? pk.c("accent", "#7d82d9") : pk.c("muted", "#888888")
        Rectangle {
          y: 3; width: 12; height: 12; radius: 6
          x: pk.showTitle ? parent.width - width - 3 : 3
          color: pk.showTitle ? pk.c("background", "#101018") : pk.c("muted", "#888888")
        }
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: pk.selected = pk.names.length + 1
        onClicked: pk.titleToggled()
      }
    }

    Rectangle {
      id: wallRow
      x: 12; width: parent.width - 24; height: pk.rowH
      y: titleRow.y + pk.rowH + 4
      radius: 8
      readonly property bool sel: pk.selected === pk.names.length + 2
      color: sel ? pk.c("selection", "#252e56") : "transparent"
      border.width: 1
      border.color: sel ? pk.c("accent", "#7d82d9") : pk.c("muted", "#888888")

      Text {
        anchors.centerIn: parent
        text: "+  Create theme from wallpaper…"
        color: wallRow.sel ? pk.c("bright_foreground", "#ffffff") : pk.c("accent", "#7d82d9")
        font.family: pk.font; font.pixelSize: 14; font.bold: true
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: pk.selected = pk.names.length + 2
        onClicked: pk.themeFromWallpaper()
      }
    }

    Text {
      id: footer
      x: 24; anchors.bottom: parent.bottom; anchors.bottomMargin: 16
      text: "↑↓ move  Enter pick  F colors  T title  W theme  Esc close"
      color: pk.c("muted", "#888888")
      font.family: pk.font; font.pixelSize: 12
    }
  }
}
