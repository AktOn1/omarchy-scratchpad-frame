import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// "Describe the frame you want": one text box. The user's own AI answers with a recipe (an existing style plus colours),
// it is previewed on the scratchpad, and the user applies or discards it. A recipe is data only; nothing the AI says is run.
// Nothing is sent until the Make button (or Enter in the box) is used. bin/frame-ai does the talking and checks the answer.
Column {
  id: fm

  required property var host
  property string padId: ""
  property color fg: Color.popups.text

  readonly property string font: host.bar.fontFamily
  readonly property string cli: Qt.resolvedUrl("bin/frame-ai").toString().replace(/^file:\/\//, "")

  property bool settingsOpen: false
  property bool busy: false
  property var recipe: null          // the answer waiting for Apply or Discard
  property string msg: ""
  property bool msgBad: false

  property var provRows: []
  property string provId: ""
  property string provModel: ""
  property var provEndpoint: ({ url: "", key_env: "", key_file: "" })
  property bool provImage: false
  property bool provStrong: true
  property string testMsg: ""
  property bool testBad: false

  readonly property var lookNow: host.looks[padId] || null
  readonly property var provRow: rowOf(provId)
  readonly property string provLabel: provRow ? provRow.label : "your AI"

  spacing: Style.space(6)

  function fgA(a) { return Qt.rgba(fg.r, fg.g, fg.b, a) }
  function rowOf(id) { for (var i = 0; i < provRows.length; i++) if (provRows[i].id === id) return provRows[i]; return null }
  readonly property var provOptions: provRows.map(function(r) { return { value: r.id, label: r.label } })
  readonly property var modelOptions: { var r = rowOf(provId); return r ? r.models.map(function(m) { return { value: m.id, label: m.label } }) : [] }
  function say(t, bad) { msg = t; msgBad = !!bad }

  component Btn: Rectangle {
    id: b
    property string label: ""
    property bool toggle: false
    property bool checked: false
    property bool dim: false
    signal clicked()
    height: Style.space(28)
    width: txt.implicitWidth + Style.space(24)
    radius: Style.space(6)
    color: toggle ? fm.fgA(checked ? (ma.containsMouse ? 0.24 : 0.17) : (ma.containsMouse ? 0.1 : 0.03)) : fm.fgA(ma.containsMouse && !dim ? 0.32 : 0.22)
    border.width: toggle ? 1 : 0
    border.color: fm.fgA(checked ? 0.5 : 0.22)
    opacity: dim ? 0.45 : 1
    Text {
      id: txt
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: b.label
      color: fm.fg
      font.family: fm.font
      font.pixelSize: Style.font.body
      font.bold: !b.toggle
    }
    MouseArea {
      id: ma
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: b.dim ? Qt.ArrowCursor : Qt.PointingHandCursor
      onClicked: if (!b.dim) b.clicked()
    }
  }

  component Field: TextField {
    width: fm.width
    height: Style.space(32)
    verticalPadding: Style.space(3)
    foreground: fm.fg
    font.family: fm.font
    font.pixelSize: Style.font.body
    Keys.onEscapePressed: function(e) { fm.parent.forceActiveFocus(); e.accepted = true }
  }

  // ------------------------------------------------------------ make
  function make() {
    if (busy) return
    var t = descField.text.trim()
    if (t === "") { say("Describe the frame you want first.", true); return }
    recipe = null
    host.cmd(["previewEnd"])
    busy = true
    say("Asking " + provLabel + "…", false)
    makeProc.command = ["python3", cli, "make", t, "--json"]
    makeProc.running = true
  }
  function cancel() { if (makeProc.running) makeProc.running = false; busy = false; say("Cancelled. Nothing was changed.", false) }
  Process {
    id: makeProc
    stdout: StdioCollector { id: makeOut; waitForEnd: true }
    onExited: function(code, status) {
      if (!fm.busy) return
      fm.busy = false
      var d = null
      try { d = JSON.parse(String(makeOut.text).trim().split("\n").pop()) } catch (e) { d = null }
      if (d && d.ok && d.recipe) {
        fm.recipe = d.recipe
        fm.showRecipe()
        fm.say("Ready: previewing “" + d.recipe.name + "” on the scratchpad. Apply it or discard it.", false)
      } else {
        fm.say(d && d.error ? d.error : "The frame designer gave no answer.", true)
      }
    }
  }
  function showRecipe() { if (recipe) host.cmd(["previewLook", padId, JSON.stringify(recipe)]) }
  function apply() {
    if (!recipe) return
    host.cmd(["lookSet", padId, JSON.stringify(recipe)])
    host.looks = Object.assign({}, host.looks, (function(o) { o[padId] = recipe; return o })({}))
    say("“" + recipe.name + "” kept for this scratchpad.", false)
    recipe = null
  }
  function discard() {
    host.cmd(["previewEnd"])
    recipe = null
    say("Discarded. Nothing was changed.", false)
  }
  function removeLook() {
    host.cmd(["lookClear", padId])
    var n = Object.assign({}, host.looks)
    delete n[padId]
    host.looks = n
    say("Custom frame removed; the picker's style shows again.", false)
  }

  // ------------------------------------------------------------ the box
  Row {
    width: fm.width
    spacing: Style.space(6)
    Field {
      id: descField
      width: fm.width - makeBtn.width - gearBtn.width - 2 * parent.spacing
      placeholderText: "Describe the frame you want, e.g. calm night forest in mossy greens"
      maximumLength: 300
      readOnly: fm.busy
      onAccepted: fm.make()
    }
    Btn { id: makeBtn; label: fm.busy ? "Cancel" : "Make frame"; onClicked: fm.busy ? fm.cancel() : fm.make() }
    Btn { id: gearBtn; toggle: true; checked: fm.settingsOpen; label: "AI: " + fm.provLabel.replace(/ \(.*$/, "").replace(/…$/, ""); onClicked: fm.settingsOpen = !fm.settingsOpen }
  }

  Text {
    visible: fm.msg !== ""
    width: fm.width
    leftPadding: Style.space(4)
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: fm.msg
    color: fm.msgBad ? "#ff8a80" : fm.fg
    font.family: fm.font
    font.pixelSize: Style.font.body * 0.95
  }

  // the answer, waiting for Apply or Discard
  Row {
    visible: fm.recipe !== null
    width: fm.width
    spacing: Style.space(10)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: fm.recipe ? fm.recipe.name + " · " + fm.host.menu.pretty(fm.recipe.style) : ""
      color: fm.fg
      font.family: fm.font
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      Repeater {
        model: fm.recipe ? Object.keys(fm.recipe.colors) : []
        delegate: Rectangle {
          required property string modelData
          width: Style.space(16); height: Style.space(16); radius: Style.space(3)
          color: fm.recipe ? fm.recipe.colors[modelData] : "transparent"
          border.width: 1; border.color: fm.fgA(0.35)
        }
      }
    }
    Btn { label: "Apply"; onClicked: fm.apply() }
    Btn { label: "Show again"; onClicked: fm.showRecipe() }
    Btn { label: "Discard"; onClicked: fm.discard() }
  }

  Row {
    visible: fm.lookNow !== null && fm.recipe === null
    width: fm.width
    spacing: Style.space(10)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: fm.lookNow ? "This scratchpad uses your frame “" + fm.lookNow.name + "”" : ""
      color: fm.fg
      opacity: 0.8
      font.family: fm.font
      font.pixelSize: Style.font.body
    }
    Btn { label: "Remove it"; onClicked: fm.removeLook() }
  }

  // ------------------------------------------------------------ AI settings
  Column {
    visible: fm.settingsOpen
    width: fm.width
    spacing: Style.space(6)

    Text {
      width: fm.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "The words you type and the list of frame style names go to the AI below, and nothing else. Only AI tools installed on this computer are listed."
      color: fm.fg
      opacity: 0.65
      font.family: fm.font
      font.pixelSize: Style.font.body * 0.9
    }
    Row {
      spacing: Style.space(8)
      Column {
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: "AI tool"; opacity: 0.7; color: fm.fg; font.family: fm.font; font.pixelSize: Style.font.caption }
        Dropdown {
          showLabel: false
          width: Style.space(250)
          foreground: fm.fg
          fontFamily: fm.font
          options: fm.provOptions
          value: fm.provId
          onChanged: function(v) { fm.pickProvider(v) }
        }
      }
      Column {
        visible: fm.modelOptions.length > 1
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: "Model"; opacity: 0.7; color: fm.fg; font.family: fm.font; font.pixelSize: Style.font.caption }
        Dropdown {
          showLabel: false
          width: Style.space(250)
          foreground: fm.fg
          fontFamily: fm.font
          options: fm.modelOptions
          value: fm.provModel
          onChanged: function(v) { fm.pickModel(v) }
        }
      }
      Column {
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: " "; font.pixelSize: Style.font.caption }
        Btn { label: "Test connection"; onClicked: fm.testConnection() }
      }
    }
    Field {
      id: modelField
      visible: fm.provId !== "custom"
      placeholderText: fm.provId === "endpoint" ? "Model name the server expects, e.g. anthropic/claude-3.5-sonnet or llama3.1" : "Model (optional): empty = this tool's own default model"
      maximumLength: 80
      onAccepted: fm.parent.forceActiveFocus()
      onEditingFinished: if (text.trim() !== fm.provModel) fm.pickModel(text.trim())
    }
    Column {
      visible: fm.provId === "endpoint"
      width: fm.width
      spacing: Style.space(6)
      Field {
        id: epUrlField
        placeholderText: "Server address, e.g. https://openrouter.ai/api/v1 or http://localhost:1234/v1 (LM Studio)"
        maximumLength: 200
        onEditingFinished: fm.saveEndpoint()
      }
      Row {
        spacing: Style.space(8)
        Field {
          id: epKeyEnvField
          width: (fm.width - Style.space(8)) / 2
          placeholderText: "Key from this environment variable (name only)"
          maximumLength: 60
          onEditingFinished: fm.saveEndpoint()
        }
        Field {
          id: epKeyFileField
          width: (fm.width - Style.space(8)) / 2
          placeholderText: "or from a private file (chmod 600), e.g. ~/.config/my-ai-key"
          maximumLength: 200
          onEditingFinished: fm.saveEndpoint()
        }
      }
    }
    Row {
      visible: fm.provId === "custom" || fm.provId === "endpoint"
      spacing: Style.space(8)
      Btn { toggle: true; checked: fm.provImage; label: (fm.provImage ? "󰄲 " : "󰄱 ") + "This AI can look at pictures"; onClicked: fm.setCaps(!fm.provImage, fm.provStrong) }
      Btn { toggle: true; checked: fm.provStrong; label: (fm.provStrong ? "󰄲 " : "󰄱 ") + "Strong enough for a full colour palette"; onClicked: fm.setCaps(fm.provImage, !fm.provStrong) }
    }
    Field {
      id: customField
      visible: fm.provId === "custom"
      placeholderText: "Custom command: reads the prompt on stdin and prints text with one JSON object, e.g. my-ai --quiet"
      maximumLength: 300
      onAccepted: { fm.saveCustom(); fm.parent.forceActiveFocus() }
      onEditingFinished: fm.saveCustom()
    }
    Text {
      visible: fm.testMsg !== ""
      width: fm.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: fm.testMsg
      color: fm.testBad ? "#ff8a80" : fm.fg
      font.family: fm.font
      font.pixelSize: Style.font.body * 0.95
    }
  }

  // ------------------------------------------------------------ remembering the pick (bin/frame-ai use)
  function loadProviders() { if (!provProc.running) provProc.running = true }
  Component.onCompleted: loadProviders()
  Process {
    id: provProc
    command: ["python3", fm.cli, "providers", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text).trim())
          fm.provRows = d.providers
          fm.provId = d.choice.provider
          fm.provModel = d.choice.model
          if (d.choice.custom && customField.text === "") customField.text = d.choice.custom
          fm.provEndpoint = d.choice.endpoint || ({ url: "", key_env: "", key_file: "" })
          if (!modelField.activeFocus) modelField.text = fm.provModel
          if (!epUrlField.activeFocus) epUrlField.text = fm.provEndpoint.url
          if (!epKeyEnvField.activeFocus) epKeyEnvField.text = fm.provEndpoint.key_env
          if (!epKeyFileField.activeFocus) epKeyFileField.text = fm.provEndpoint.key_file
          var row = fm.rowOf(fm.provId)
          fm.provStrong = !row || row.strong !== false
          fm.provImage = !row || row.image !== false
        } catch (e) { fm.say("Could not read the list of AI tools.", true) }
      }
    }
  }

  property var useQueue: []
  function runUse(args) { useQueue.push(args); pumpUse() }
  function pumpUse() {
    if (useProc.running || useQueue.length === 0) return
    useProc.command = ["python3", cli, "use"].concat(useQueue.shift()).concat(["--json"])
    useProc.running = true
  }
  Process {
    id: useProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: { if (fm.useQueue.length > 0) fm.pumpUse(); else fm.loadProviders() }
  }
  function pickProvider(id) {
    testMsg = ""
    var r = rowOf(id)
    var a = [id]
    if (id === "custom" && customField.text.trim() !== "") { a.push("--custom"); a.push(customField.text.trim()) }
    if (r && r.default_model !== undefined && r.default_model !== "") { a.push("--model"); a.push(r.default_model) }
    provId = id
    runUse(a)
  }
  function pickModel(m) { testMsg = ""; provModel = m; runUse(["--model", m]) }
  function saveEndpoint() { runUse(["endpoint", "--url", epUrlField.text.trim(), "--key-env", epKeyEnvField.text.trim(), "--key-file", epKeyFileField.text.trim()]) }
  function setCaps(seeing, strong) { testMsg = ""; runUse(["--can-see", seeing ? "1" : "0", "--strong", strong ? "1" : "0"]) }
  function saveCustom() { if (customField.text.trim() !== "") runUse(["custom", "--custom", customField.text.trim()]) }

  function testConnection() {
    if (testProc.running) return
    testMsg = "Testing the connection…"; testBad = false
    testProc.running = true
  }
  Process {
    id: testProc
    command: ["python3", fm.cli, "test", "--json"]
    stdout: StdioCollector { id: testOut; waitForEnd: true }
    onExited: {
      var d = null
      try { d = JSON.parse(String(testOut.text).trim().split("\n").pop()) } catch (e) { d = null }
      fm.testBad = !(d && d.ok)
      fm.testMsg = d ? (d.ok ? "Connection works (" + d.seconds + " s)." : "Test failed: " + (d.error || "no answer")) : "Test failed: no answer."
    }
  }
}
