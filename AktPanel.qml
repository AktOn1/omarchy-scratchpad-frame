import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "AktKit.js" as Model

// The window of an AktOn1 plugin. On its own it shows only this plugin's layers (a plugin with a single layer opens
// straight into it). The connection control sits in the top pane: Connect when the sibling plugin is installed, a button that
// copies its install command when it is not. When connected, the top pane says the two are combined into one icon and offers
// "Separate into icons"; the sibling's layers appear below this plugin's own, each under its own heading.
//
// The owner widget sets `open` and handles closeRequested. Connect state is shared by the AktOn1 plugins in
// ~/.local/state/akton1/combine.json.
Item {
  id: root

  required property Item anchorItem
  required property QtObject bar
  required property string selfId
  property bool open: false
  property string ipcTarget: ""
  // Optional pane shown below a scratchpad's settings while it is edited. The item it creates gets
  // `padId` set to the scratchpad being edited. Only offered for scratchpads of a plugin that has frame styles.
  property Component editBelow: null
  signal closeRequested()

  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar.urgent
  readonly property string fontFamily: bar.fontFamily
  readonly property string combinePath: Quickshell.env("HOME") + "/.local/state/akton1/combine.json"

  property var combine: ({ members: {} })
  readonly property string hostId: Model.hostOf(combine, selfId)
  readonly property bool isMember: hostId !== selfId
  readonly property var group: Model.groupOf(combine, selfId)
  readonly property var sources: group.map(id => sourceFor(id))

  readonly property var siblingInfo: Model.PLUGINS.find(p => p.id !== selfId)
  readonly property var siblingSrc: sourceFor(siblingInfo.id)
  readonly property string separateId: isMember ? selfId : siblingInfo.id

  property string view: "grid"
  property string editSource: ""
  property string editLayer: ""
  property string capturing: ""
  property string notice: ""
  property bool noticeIsInfo: false

  function sourceFor(id) { return id === Model.PLUGINS[0].id ? srcA : srcB }
  function glyph(cp) { return String.fromCodePoint(cp) }

  readonly property var appEntries: (DesktopEntries.applications.values || []).map(Model.entryInfo)
  readonly property var appChoices: Model.appOptions(appEntries)
  function appTitle(app) { return Model.appTitle(app, appEntries) }

  function notify(text) { noticeIsInfo = false; notice = text; noticeTimer.restart() }
  function inform(text) { noticeIsInfo = true; notice = text; noticeTimer.restart() }
  Timer { id: noticeTimer; interval: 7000; onTriggered: root.notice = "" }

  // ---- combine ----------------------------------------------------------------
  FileView {
    id: combineFile
    path: root.combinePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      root.combine = Model.cleanCombine(raw)
    }
    onLoadFailed: root.combine = ({ members: {} })
  }
  Process {
    id: mkdir
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/akton1"]
  }
  function saveCombine(next) {
    combine = next
    mkdir.running = true
    combineSave.restart()
    goHome()
  }
  Timer { id: combineSave; interval: 150; onTriggered: combineFile.setText(JSON.stringify(root.combine, null, 2) + "\n") }
  function combineIn(otherId) {
    saveCombine(Model.combineWith(combine, selfId, otherId))
    const info = Model.pluginInfo(otherId)
    inform(info.short + " joined this window. Its own bar icon is hidden.")
  }
  function separateOut(memberId) {
    const fs = sourceFor(Model.PLUGINS.find(p => p.scope === "layer").id)
    const magnet = fs.snap.fullscreen.magnet
    // games that landed in a scratchpad go back to the Fullscreen layer once the scratchpads are no longer here
    const reset = fs.up && magnet !== "" && magnet !== "off"
    saveCombine(Model.separate(combine, memberId))
    if (reset) fs.run(["magnet", "none"])
    inform(Model.pluginInfo(memberId).short + " has its own icon again." + (reset ? " Games land in the Fullscreen layer." : ""))
  }
  function copyInstall(otherId) {
    const cmd = Model.installCommand(otherId)
    Quickshell.execDetached(["wl-copy", cmd])
    inform("Copied: " + cmd + "  Paste it in a terminal.")
  }

  // ---- sources ----------------------------------------------------------------
  AktSource { id: srcA; window: root; pluginId: Model.PLUGINS[0].id }
  AktSource { id: srcB; window: root; pluginId: Model.PLUGINS[1].id }

  readonly property bool connected: group.length > 1
  readonly property bool soloLayer: !connected && sources[0].scope === "layer"
  readonly property string homeView: soloLayer ? "edit" : "grid"
  readonly property bool atHome: view === homeView
  function goHome() {
    if (soloLayer) edit(selfId, Model.FULLSCREEN_ID)
    else view = "grid"
  }

  // ---- picking a key ------------------------------------------------------------
  function beginCapture(tag) { capturing = tag }
  function cancelCapture() { capturing = "" }
  function finishCapture(key) {
    const parts = capturing.split("|")
    capturing = ""
    const src = sources.find(s => s.name === parts[0])
    if (src) src.run(["padSet", parts[1], parts[2], key])
  }

  function edit(pid, id) {
    editSource = pid
    editLayer = id
    view = "edit"
  }
  readonly property var editSrc: editSource !== "" ? sourceFor(editSource) : null
  readonly property var editPad: editSrc ? Model.findLayer(editSrc.snap.state, editLayer) : null
  onEditPadChanged: if (view === "edit" && !editPad) goHome()

  onOpenChanged: {
    if (open) { goHome(); srcA.poll(); srcB.poll(); if (!combineSave.running) combineFile.reload() }
    else { capturing = ""; goHome() }
  }

  readonly property bool belowShown: editBelow !== null && view === "edit" && editPad !== null && editPad.layer !== true
      && editSrc !== null && editSrc.hasStyles
  readonly property bool editingOther: view === "edit" && editPad !== null && !soloLayer
  readonly property string heroTitle: editingOther ? editPad.label
      : (connected ? sources.map(s => s.short).join(" + ") : Model.pluginInfo(selfId).name)
  readonly property string heroMeta: editingOther ? Model.pluginInfo(editSource).short + " layer"
      : (connected ? "combined into one bar icon" : Model.pluginInfo(selfId).blurb)

  // omarchy-shell <ipcTarget> show grid|edit [plugin engine name] [layer id]   (switches the open window's page; "settings" is the grid)
  IpcHandler {
    enabled: root.ipcTarget !== ""
    target: root.ipcTarget
    function show(page: string, plugin: string, id: string): string {
      if (page === "edit") {
        const src = root.sources.find(s => s.name === plugin)
        if (!src || !Model.findLayer(src.snap.state, id)) return "error: no such layer"
        root.edit(src.pluginId, id)
      } else if (page === "grid" || page === "settings") {
        root.goHome()
      } else {
        return "error: page is grid or edit"
      }
      return root.view
    }
    function combine(plugin: string, mode: string): string {
      const info = Model.PLUGINS.find(p => p.engine === plugin)
      if (!info || info.id === root.selfId) return "error: no such plugin"
      if (mode === "off") root.separateOut(info.id); else root.combineIn(info.id)
      return "ok"
    }
  }

  Item {
    id: ownerKey
    visible: false
    property bool popoutSwitchClosing: false
    function close() { root.closeRequested() }
    function closeForPopoutSwitch() {
      popoutSwitchClosing = true
      root.closeRequested()
      Qt.callLater(function() { ownerKey.popoutSwitchClosing = false })
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: ownerKey
    bar: root.bar
    open: root.open
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(root.belowShown ? 920 : 660))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(root.belowShown ? 940 : 640))

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: { if (!root.atHome) root.goHome(); else root.closeRequested() }

      AktKeyCapture { window: root }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        AktWheel { view: flick }

        Column {
          id: body
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: root.heroTitle
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.glyph(root.connected ? 0xf0337 : 0xf0570)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(8)
                Button {
                  visible: !root.atHome
                  text: "Back"
                  bordered: true
                  focusable: true
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  onClicked: root.goHome()
                }
                Button {
                  iconText: root.glyph(root.connected || root.isMember ? 0xf0338 : 0xf0337)
                  text: root.connected || root.isMember ? "Separate into icons"
                      : (root.siblingSrc.up ? "Connect" : "Copy install command")
                  bordered: true
                  focusable: true
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  tooltipText: root.connected || root.isMember ? "Give each plugin its own bar icon and window again"
                      : (root.siblingSrc.up ? "Show " + root.siblingInfo.short + " in this window; one bar icon for both"
                      : Model.installCommand(root.siblingInfo.id))
                  onClicked: root.connected || root.isMember ? root.separateOut(root.separateId)
                      : (root.siblingSrc.up ? root.combineIn(root.siblingInfo.id) : root.copyInstall(root.siblingInfo.id))
                }
              }
            }
          }

          Text {
            visible: root.atHome && !root.connected && !root.isMember && !root.siblingSrc.up
            textFormat: Text.PlainText
            width: parent.width
            text: "Pairs with " + root.siblingInfo.name + ": " + root.siblingInfo.blurb + "."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: text !== ""
            textFormat: Text.PlainText
            width: parent.width
            text: root.notice !== "" ? root.notice : root.sources.map(s => s.snap.message).filter(m => m !== "").join(" ")
            color: root.notice !== "" && !root.noticeIsInfo ? root.urgent : (root.notice !== "" ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.sources.every(s => s.up)
            textFormat: Text.PlainText
            width: parent.width
            text: "Waiting for " + root.sources.filter(s => !s.up).map(s => s.title).join(" and ") + " to start. Check that it is enabled."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            id: gridView
            visible: root.view === "grid"
            width: parent.width
            spacing: Style.space(16)

            Repeater {
              model: root.sources
              delegate: Column {
                id: section
                required property var modelData
                readonly property var src: modelData
                readonly property bool isHost: src.pluginId === root.selfId
                width: gridView.width
                spacing: Style.space(8)
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                Text {
                  visible: root.connected
                  width: parent.width
                  textFormat: Text.PlainText
                  text: section.src.title.toUpperCase()
                  elide: Text.ElideRight
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Flow {
                  id: wrap
                  width: parent.width
                  spacing: Style.space(10)
                  readonly property real minTile: Style.space(190)
                  readonly property int cols: Math.max(1, Math.floor((width + spacing) / (minTile + spacing)))
                  readonly property real tileWidth: Math.floor((width - spacing * (cols - 1)) / cols)

                  Repeater {
                    model: section.src.up ? Model.layersOf(section.src.snap.state).map(l => l.id) : []
                    delegate: AktTile {
                      required property string modelData
                      source: section.src
                      entry: Model.findLayer(section.src.snap.state, modelData) || Model.layersOf(section.src.snap.state)[0]
                      connected: root.connected
                      width: wrap.tileWidth
                      onEdit: root.edit(section.src.pluginId, modelData)
                    }
                  }
                }

                TextField {
                  visible: section.src.scope === "pads" && section.src.up
                  width: parent.width
                  placeholderText: "New scratchpad name, then Enter"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  onAccepted: { if (text.trim() !== "") section.src.run(["padAdd", text.trim(), "bottom"]); text = "" }
                }
              }
            }
          }

          Column {
            id: editView
            visible: root.view === "edit" && root.editPad !== null
            width: parent.width
            spacing: Style.space(16)

            Loader {
              active: root.view === "edit" && root.editPad !== null
              width: parent.width
              sourceComponent: AktPadCard {
                source: root.editSrc
                pad: root.editPad
                connected: root.connected
                framePane: root.belowShown
                wide: root.belowShown
              }
            }
            Loader {
              active: root.belowShown
              visible: active
              width: parent.width
              sourceComponent: root.editBelow
              onLoaded: item.padId = Qt.binding(function() { return root.editPad ? root.editPad.id : "" })
            }
          }
        }
      }
    }
  }
}
