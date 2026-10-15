import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// "Describe the frame you want": one text box. The user's own AI answers with a recipe (an existing style plus colours),
// it is previewed on the scratchpad, and the user applies or discards it. A recipe is data only; nothing the AI says is run.
// Nothing is sent until the Make button (or Enter in the box) is used. bin/frame-ai does the talking and checks the answer.
// Optional, off by default: "Ornaments from my own image model (less predictable)". When ticked, Make frame also asks the user's own
// image model for one corner ornament; only a short ornament description goes to it. If that fails the normal frame is still made.
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

  // the optional image model (ornaments)
  property bool imgOn: false
  property bool imgOpen: false
  property var imgRows: []
  property string imgId: "comfyui"
  property var imgComfy: ({ url: "", workflow: "", checkpoint: "" })
  property var imgEndpoint: ({ url: "", model: "", key_env: "", key_file: "", size: "" })
  property var ckptList: []
  property string ckptMsg: ""
  property string imgTestMsg: ""
  property bool imgTestBad: false
  readonly property bool imgShown: imgOn || imgOpen
  readonly property var imgOptions: imgRows.map(function(r) { return { value: r.id, label: r.label } })
  readonly property var ckptOptions: ckptList.map(function(c) { return { value: c, label: c.replace(/\.(safetensors|ckpt|pt)$/, "") } })
  readonly property string imgLabel: { for (var i = 0; i < imgRows.length; i++) if (imgRows[i].id === imgId) return imgRows[i].label.replace(/ \(.*$/, "").replace(/…$/, ""); return "ComfyUI" }

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

  // Text boxes are drawn by the plugin and never read the clipboard on their own (see PlainField.qml).
  component Field: PlainField {
    width: fm.width
    height: Style.space(32)
    verticalPadding: Style.space(3)
    foreground: fm.fg
    fontFamily: fm.font
    fontPixelSize: Style.font.body
    handleEscape: true
    onEscaped: fm.parent.forceActiveFocus()
  }

  // ------------------------------------------------------------ make
  function make() {
    if (busy) return
    var t = descField.text.trim()
    if (t === "") { say("Describe the frame you want first.", true); return }
    discardPending()
    recipe = null
    makeResult = null
    host.cmd(["previewEnd"])
    busy = true
    say("Asking " + provLabel + "…", false)
    makeProc.command = ["python3", cli, "make", t, "--json"].concat(imgOn ? ["--ornaments"] : [])
    makeProc.running = true
  }
  function cancel() { if (makeProc.running) makeProc.running = false; busy = false; say("Cancelled. Nothing was changed.", false) }
  property var makeResult: null
  Process {
    id: makeProc
    // one JSON line per step: {"progress": "ai"|"image"} while it works, then the answer
    stdout: SplitParser {
      onRead: function(line) {
        var d = null
        try { d = JSON.parse(line) } catch (e) { return }
        if (d && d.progress === "image") fm.say("Asking your image model (" + fm.imgLabel + ") for an ornament. This can take a minute…", false)
        else if (d && d.ok !== undefined) fm.makeResult = d
      }
    }
    onExited: function(code, status) {
      if (!fm.busy) return
      fm.busy = false
      var d = fm.makeResult
      if (d && d.ok && d.recipe) {
        fm.recipe = d.recipe
        fm.showRecipe()
        fm.say("Ready: previewing “" + d.recipe.name + "” on the scratchpad. Apply it or discard it." + (d.recipe.ornament && d.recipe.ornamentText ? " Ornament made from: " + d.recipe.ornamentText + "." : "") + (d.note ? " " + d.note : ""), false)
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
    discardPending()
    recipe = null
    say("Discarded. Nothing was changed.", false)
  }
  // a made-but-not-applied ornament is deleted right away (the saved ones are never touched: bin/frame-ai ornaments drop refuses those)
  function discardPending() {
    if (recipe && recipe.ornament && !dropProc.running) {
      dropProc.command = ["python3", cli, "ornaments", "drop", recipe.ornament]
      dropProc.running = true
    }
  }
  Process { id: dropProc }
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

  // ------------------------------------------------------------ optional: ornaments from the user's own image model
  Row {
    width: fm.width
    spacing: Style.space(6)
    Btn {
      toggle: true
      checked: fm.imgOn
      label: (fm.imgOn ? "󰄲 " : "󰄱 ") + "Ornaments from my own image model (less predictable)"
      onClicked: fm.setOrnaments(!fm.imgOn)
    }
    Btn { toggle: true; checked: fm.imgOpen; label: "Image model: " + fm.imgLabel; onClicked: fm.imgOpen = !fm.imgOpen }
  }
  Text {
    visible: fm.imgOn
    width: fm.width
    leftPadding: Style.space(4)
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "On: Make frame also asks your image model for one corner ornament that matches your words. It will not look like the shipped art, and it can be odd or ugly. If it fails you still get the normal frame (a style plus colours)."
    color: fm.fg
    opacity: 0.7
    font.family: fm.font
    font.pixelSize: Style.font.body * 0.9
  }
  Column {
    visible: fm.imgShown
    width: fm.width
    spacing: Style.space(6)

    Text {
      width: fm.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: "Only a short ornament description goes to the image model you pick here, and only when Make frame is pressed with the box ticked. No window titles, pictures or theme colours are sent. The made picture is stored on this computer and checked before it is used."
      color: fm.fg
      opacity: 0.65
      font.family: fm.font
      font.pixelSize: Style.font.body * 0.9
    }
    Row {
      spacing: Style.space(8)
      Column {
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: "Image model"; opacity: 0.7; color: fm.fg; font.family: fm.font; font.pixelSize: Style.font.caption }
        Dropdown {
          showLabel: false
          width: Style.space(250)
          foreground: fm.fg
          fontFamily: fm.font
          options: fm.imgOptions
          value: fm.imgId
          onChanged: function(v) { fm.pickImgProvider(v) }
        }
      }
      Column {
        visible: fm.imgId === "comfyui" && fm.ckptOptions.length > 0
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: "Checkpoint (from your ComfyUI)"; opacity: 0.7; color: fm.fg; font.family: fm.font; font.pixelSize: Style.font.caption }
        Dropdown {
          showLabel: false
          width: Style.space(300)
          foreground: fm.fg
          fontFamily: fm.font
          options: fm.ckptOptions
          value: fm.imgComfy.checkpoint
          onChanged: function(v) { fm.runImgUse(["--checkpoint", v]) }
        }
      }
      Column {
        spacing: Style.space(2)
        Text { textFormat: Text.PlainText; text: " "; font.pixelSize: Style.font.caption }
        Btn { label: "Test connection"; onClicked: fm.testImage() }
      }
    }
    Column {
      visible: fm.imgId === "comfyui"
      width: fm.width
      spacing: Style.space(6)
      Field {
        id: comfyUrlField
        placeholderText: "ComfyUI address, e.g. http://127.0.0.1:8188"
        maximumLength: 200
        onEditingFinished: { if (text.trim() !== fm.imgComfy.url) fm.runImgUse(["--comfy-url", text.trim()]); fm.loadCheckpoints() }
      }
      Field {
        id: comfyFlowField
        placeholderText: "Workflow file in API format (optional; empty = the plain built-in text-to-image one)"
        maximumLength: 300
        onEditingFinished: if (text.trim() !== fm.imgComfy.workflow) fm.runImgUse(["--workflow", text.trim()])
      }
      Text {
        visible: fm.ckptMsg !== ""
        width: fm.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: fm.ckptMsg
        color: fm.fg
        opacity: 0.8
        font.family: fm.font
        font.pixelSize: Style.font.body * 0.9
      }
    }
    Column {
      visible: fm.imgId === "endpoint"
      width: fm.width
      spacing: Style.space(6)
      Field {
        id: imgEpUrlField
        placeholderText: "Server address of an OpenAI-compatible images endpoint, e.g. http://localhost:8080/v1"
        maximumLength: 200
        onEditingFinished: fm.saveImgEndpoint()
      }
      Field {
        id: imgEpModelField
        placeholderText: "Model name the server expects"
        maximumLength: 80
        onEditingFinished: fm.saveImgEndpoint()
      }
      Row {
        spacing: Style.space(8)
        Field {
          id: imgEpKeyEnvField
          width: (fm.width - Style.space(8)) / 2
          placeholderText: "Key from this environment variable (name only)"
          maximumLength: 60
          onEditingFinished: fm.saveImgEndpoint()
        }
        Field {
          id: imgEpKeyFileField
          width: (fm.width - Style.space(8)) / 2
          placeholderText: "or from a private file (chmod 600), e.g. ~/.config/my-image-key"
          maximumLength: 200
          onEditingFinished: fm.saveImgEndpoint()
        }
      }
    }
    Field {
      id: imgCustomField
      visible: fm.imgId === "custom"
      placeholderText: "Custom command, no shell: e.g. my-image-tool --prompt {prompt} --out {out}   (also {width} {height} {seed})"
      maximumLength: 300
      onAccepted: { fm.saveImgCustom(); fm.parent.forceActiveFocus() }
      onEditingFinished: fm.saveImgCustom()
    }
    Text {
      visible: fm.imgTestMsg !== ""
      width: fm.width
      wrapMode: Text.WordWrap
      textFormat: Text.PlainText
      text: fm.imgTestMsg
      color: fm.imgTestBad ? "#ff8a80" : fm.fg
      font.family: fm.font
      font.pixelSize: Style.font.body * 0.95
    }
  }

  // the answer, waiting for Apply or Discard
  Row {
    visible: fm.recipe !== null
    width: fm.width
    spacing: Style.space(10)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: fm.recipe ? fm.recipe.name + " · " + (fm.recipe.style === "OWNART" ? "your own ornament" : fm.host.menu.pretty(fm.recipe.style)) : ""
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
          if (!modelField.typing) modelField.text = fm.provModel
          if (!epUrlField.typing) epUrlField.text = fm.provEndpoint.url
          if (!epKeyEnvField.typing) epKeyEnvField.text = fm.provEndpoint.key_env
          if (!epKeyFileField.typing) epKeyFileField.text = fm.provEndpoint.key_file
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

  // ------------------------------------------------------------ remembering the image-model pick (bin/frame-ai image ...)
  function loadImg() { if (!imgProc.running) imgProc.running = true }
  function loadCheckpoints() { if (imgShown && imgId === "comfyui" && !ckptProc.running) ckptProc.running = true }
  onImgShownChanged: { if (imgShown) loadCheckpoints() }
  Component.onCompleted: { loadProviders(); loadImg() }
  Process {
    id: imgProc
    command: ["python3", fm.cli, "image", "providers", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text).trim())
          fm.imgRows = d.providers
          fm.imgOn = !!d.ornaments
          var was = fm.imgId
          fm.imgId = d.choice.provider
          fm.imgComfy = d.choice.comfy
          fm.imgEndpoint = d.choice.endpoint
          if (!comfyUrlField.typing) comfyUrlField.text = fm.imgComfy.url
          if (!comfyFlowField.typing) comfyFlowField.text = fm.imgComfy.workflow
          if (!imgEpUrlField.typing) imgEpUrlField.text = fm.imgEndpoint.url
          if (!imgEpModelField.typing) imgEpModelField.text = fm.imgEndpoint.model
          if (!imgEpKeyEnvField.typing) imgEpKeyEnvField.text = fm.imgEndpoint.key_env
          if (!imgEpKeyFileField.typing) imgEpKeyFileField.text = fm.imgEndpoint.key_file
          if (d.choice.custom && imgCustomField.text === "") imgCustomField.text = d.choice.custom
          if (was !== fm.imgId || fm.ckptList.length === 0) fm.loadCheckpoints()
        } catch (e) { fm.say("Could not read the image model settings.", true) }
      }
    }
  }
  Process {
    id: ckptProc
    command: ["python3", fm.cli, "image", "checkpoints", "--json"]
    stdout: StdioCollector { id: ckptOut; waitForEnd: true }
    onExited: {
      var d = null
      try { d = JSON.parse(String(ckptOut.text).trim().split("\n").pop()) } catch (e) { d = null }
      if (d && d.ok) {
        fm.ckptList = d.checkpoints
        fm.ckptMsg = d.checkpoints.length === 0 ? "ComfyUI answers but has no checkpoints." : ""
        if (d.checkpoints.length > 0 && d.checkpoints.indexOf(fm.imgComfy.checkpoint) < 0) fm.runImgUse(["--checkpoint", d.suggest])
      } else {
        fm.ckptList = []
        fm.ckptMsg = "Could not list checkpoints: " + (d && d.error ? d.error : "no answer") + " Start ComfyUI, or fix the address, then press Test connection."
      }
    }
  }

  property var imgQueue: []
  function runImgUse(args) { imgQueue.push(args); pumpImg() }
  function pumpImg() {
    if (imgUseProc.running || imgQueue.length === 0) return
    imgUseProc.command = ["python3", cli, "image", "use"].concat(imgQueue.shift()).concat(["--json"])
    imgUseProc.running = true
  }
  Process {
    id: imgUseProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: { if (fm.imgQueue.length > 0) fm.pumpImg(); else fm.loadImg() }
  }
  function setOrnaments(on) { imgOn = on; imgTestMsg = ""; runImgUse(["--ornaments", on ? "1" : "0"]) }
  function pickImgProvider(id) {
    imgTestMsg = ""
    imgId = id
    var a = [id]
    if (id === "custom" && imgCustomField.text.trim() !== "") { a.push("--custom"); a.push(imgCustomField.text.trim()) }
    runImgUse(a)
  }
  function saveImgEndpoint() {
    runImgUse(["endpoint", "--endpoint-url", imgEpUrlField.text.trim(), "--model", imgEpModelField.text.trim(),
               "--key-env", imgEpKeyEnvField.text.trim(), "--key-file", imgEpKeyFileField.text.trim()])
  }
  function saveImgCustom() { if (imgCustomField.text.trim() !== "") runImgUse(["custom", "--custom", imgCustomField.text.trim()]) }
  function testImage() {
    if (imgTestProc.running) return
    imgTestMsg = "Testing the connection…"; imgTestBad = false
    imgTestProc.running = true
  }
  Process {
    id: imgTestProc
    command: ["python3", fm.cli, "image", "test", "--json"]
    stdout: StdioCollector { id: imgTestOut; waitForEnd: true }
    onExited: {
      var d = null
      try { d = JSON.parse(String(imgTestOut.text).trim().split("\n").pop()) } catch (e) { d = null }
      fm.imgTestBad = !(d && d.ok)
      fm.imgTestMsg = d ? (d.ok ? "Connection works: " + d.message : "Test failed: " + (d.error || "no answer")) : "Test failed: no answer."
      if (d && d.ok) fm.loadCheckpoints()
    }
  }
}
