import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "AktKit.js" as Kit

// The bar icon and window for Scratchpad Frame (the frame itself is drawn by ScratchpadFrame.qml).
// The icon opens the scratchpads overview (the cards window); a scratchpad's page shows its settings with its frame picker below them (FramePicker.qml).
// Everything goes through the plugin's own commands (omarchy-shell scratchpad-frame ...); this file only reads them.
BarWidget {
  id: root
  moduleName: "io.github.akton1.scratchpad-frame"

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/scratchpad-frame"

  property var styles: []
  property string current: ""
  property bool follow: false
  property bool showTitle: true
  property var themeColors: ({})
  property var pads: []
  StyleLive { id: live }
  readonly property var painter: live.painter   // FramePicker draws its thumbnail with these
  readonly property var menu: live.menu
  readonly property int assetRev: live.assetRev
  readonly property var cats: live.menu.categories(root.styles)
  readonly property var order: live.menu.allStyles(root.cats)

  function cmd(args) {
    Quickshell.execDetached(["omarchy-shell", "-q", "scratchpad-frame"].concat(args))
    refreshTimer.restart()
  }
  Timer { id: refreshTimer; interval: 250; onTriggered: root.refresh() }

  // ---------------------------------------------------------------- state
  Process {
    id: reader
    command: ["omarchy-shell", "scratchpad-frame", "state"]
    stdout: StdioCollector { id: readerOut }
    onExited: function(code) {
      if (code !== 0) return
      try {
        var s = JSON.parse(readerOut.text)
        root.styles = s.styles || []
        root.current = s.style || ""
        root.pads = s.pads || []
        root.follow = !!s.follow
        root.showTitle = s.title !== false
      } catch (e) {}
    }
  }
  function refresh() { if (!reader.running) reader.running = true }
  Component.onCompleted: refresh()

  FileView {
    path: root.stateDir + "/style"
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.themeColors = live.menu.parseColors(text())
  }

  // ---------------------------------------------------------------- actions
  function keep(pad, name) {
    Quickshell.execDetached(["omarchy-shell", "-q", "scratchpad-frame.layers", "padSet", pad, "style", name])
    refreshTimer.restart()
    root.pads = root.pads.map(function(p) { return p.name === pad ? Object.assign({}, p, { style: name }) : p })
  }
  function setShared(name) {
    root.cmd(["set", name])
    root.current = name
  }
  function toggleFollow() {
    root.cmd(["follow", "toggle"])
    root.follow = !root.follow
  }
  function toggleTitle() {
    root.cmd(["title", "toggle"])
    root.showTitle = !root.showTitle
  }
  function surprise() {
    var pool = root.order.filter(function(n) { return n !== root.current })
    if (pool.length === 0) return
    var n = pool[Math.floor(Math.random() * pool.length)]
    root.setShared(n)
  }
  function step(dir) {
    if (root.order.length === 0) return
    var i = root.order.indexOf(root.current)
    var n = root.order[(i + dir + root.order.length) % root.order.length]
    root.setShared(n)
  }
  property bool cardsOpen: false
  readonly property bool opened: cardsOpen
  function open() { root.cardsOpen = true }
  function close() { root.cardsOpen = false }
  function toggle() { root.cardsOpen = !root.cardsOpen }
  function pickPad(name) {
    cards.edit(cards.selfId, name)
    root.cardsOpen = true
  }

  IpcHandler {
    target: "scratchpad-frame.bar"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function pick(pad: string): void { root.pickPad(pad) }
  }
  // The cards window (scratchpads and, when combined, the other AktOn1 plugins' layers).
  IpcHandler {
    target: "scratchpad-frame.panel"
    function toggle(): void { root.toggle() }
    function open(): void { root.open() }
    function close(): void { root.cardsOpen = false }
  }

  AktPresence {
    id: presence
    selfName: "scratchpad-frame"
    hostName: cards.isMember ? Kit.pluginInfo(cards.hostId).engine : ""
  }
  // A member hides while its host's icon is alive (and until that is known); with no live host it shows its own again.
  readonly property bool hiddenAsMember: cards.isMember && (presence.hostAlive || !presence.checked)
  visible: !hiddenAsMember
  onHiddenAsMemberChanged: if (hiddenAsMember) cardsOpen = false

  AktPanel {
    id: cards
    anchorItem: root
    bar: root.bar
    selfId: "io.github.akton1.scratchpad-frame"
    ipcTarget: "scratchpad-frame.cards"
    open: root.cardsOpen
    editBelow: Component { FramePicker { host: root } }
    onCloseRequested: root.cardsOpen = false
  }

  // ---------------------------------------------------------------- the bar icon
  property real wheelAccum: 0
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.cardsOpen
    tooltipText: "Scratchpad Frame\nstyle: " + live.menu.pretty(root.current || "?") + (root.follow ? " · desktop colors" : "")
                 + "\nclick: scratchpads; open one to change its settings and pick its frame · right-click: next style · middle-click: surprise me · scroll: step through the styles"
    iconComponent: Component {
      Item {
        FrameIcon {
          anchors.centerIn: parent
          iconSize: Style.bar.iconCanvas
          color: root.bar.barForeground // bar-icon
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.step(1)
      else if (b === Qt.MiddleButton) root.surprise()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      root.wheelAccum += delta
      if (Math.abs(root.wheelAccum) < 120) return
      root.step(root.wheelAccum > 0 ? -1 : 1)
      root.wheelAccum = 0
    }
  }
}
