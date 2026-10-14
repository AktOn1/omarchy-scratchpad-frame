import QtQuick
import Quickshell
import Quickshell.Io
import "AktKit.js" as Model

// One AktOn1 plugin as the cards window sees it: its published snapshot and the commands it takes.
// The window can hold several (its own plugin's and the plugins combined into it).
Item {
  id: root

  required property var window
  required property string pluginId

  readonly property var info: Model.pluginInfo(pluginId)
  readonly property string name: info.engine
  readonly property string scope: info.scope
  readonly property string title: info.name
  readonly property string short: info.short

  property var snap: ({ scope: scope, state: Model.defaultState(scope), detected: { pads: {}, fullscreen: "" }, styles: [], sharedStyle: "",
                        message: "", running: {}, fullscreen: { on: false, magnet: "", muteOnHide: false } })
  property bool up: false

  readonly property color foreground: window.foreground
  readonly property color dim: window.dim
  readonly property string fontFamily: window.fontFamily
  readonly property var appChoices: window.appChoices
  function appTitle(app) { return window.appTitle(app) }
  readonly property bool hasStyles: snap.styles.length > 0

  function poll() { reader.reload() }

  FileView {
    id: reader
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/" + root.name + "/snapshot.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        const next = JSON.parse(text())
        if (next && next.state) { root.snap = next; root.up = true }
      } catch (e) {}
    }
    onLoadFailed: root.up = false
  }
  // A plugin enabled after this window opened has no file to watch yet.
  Timer { interval: 4000; repeat: true; running: !root.up; onTriggered: reader.reload() }

  property var queue: []
  function run(args) {
    queue.push(args)
    if (!runner.running) next()
  }
  function next() {
    if (queue.length === 0) return
    runner.command = ["omarchy-shell", root.name + ".layers"].concat(queue.shift())
    runner.running = true
  }
  Process {
    id: runner
    stdout: StdioCollector { id: out }
    onExited: {
      const text = out.text.trim()
      if (text.indexOf("error:") === 0) root.window.notify(text.slice(6).trim())
      root.next()
    }
  }

}
