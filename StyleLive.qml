// Live-reloads FramePainter.js, MenuModel.js and assets/*.png while the shell runs, so adding or editing a style needs no restart.
// The shell has no file watcher (QS_DISABLE_FILE_WATCHER=1) and caches imported .js, so this polls `stat` and re-evaluates the source.
// painter / menu: the current module (the cached import until the first poll finishes, and again if a new source fails to evaluate).
// assetRev: bumps when a picture changed; add it to image URLs (o.rev) so the Canvas image cache is bypassed.
import QtQuick
import Quickshell
import Quickshell.Io
import "FramePainter.js" as StaticPainter
import "MenuModel.js" as StaticMenu

Item {
  id: live

  property var painter: StaticPainter
  property var menu: StaticMenu
  property int assetRev: 0
  property int version: 0   // +1 on every reload of either module; repaint when it changes
  property string error: ""

  readonly property string dir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
  property var seen: ({})

  // Evaluates a `.pragma library` file: every top-level function / var / const / let becomes a member of the result.
  function evaluate(src) {
    const names = []
    const re = /^(?:function\s+(\w+)|(?:var|const|let)\s+(\w+))/gm
    let m
    while ((m = re.exec(src)) !== null) {
      const n = m[1] || m[2]
      if (names.indexOf(n) < 0) names.push(n)
    }
    const body = src.replace(/^\.pragma.*$/m, "") + "\nreturn {" + names.map(function (n) { return n + ": " + n }).join(", ") + "}"
    return new Function(body)()
  }

  function adopt(which, text) {
    try {
      const mod = evaluate(text)
      if (which === "FramePainter.js") live.painter = mod
      else live.menu = mod
      live.error = ""
      live.version++
    } catch (e) {
      live.error = which + ": " + e
      console.warn("[scratchpad-frame] live reload of " + which + " failed, keeping the previous version: " + e)
    }
  }

  FileView {
    id: painterFile
    path: live.dir + "/FramePainter.js"
    onLoaded: live.adopt("FramePainter.js", text())
  }
  FileView {
    id: menuFile
    path: live.dir + "/MenuModel.js"
    onLoaded: live.adopt("MenuModel.js", text())
  }

  Process {
    id: poll
    command: ["sh", "-c", "cd \"$1\" && stat -c '%n %Y %s' FramePainter.js MenuModel.js assets/*.png assets/*/*.png 2>/dev/null", "sh", live.dir]
    stdout: StdioCollector { id: pollOut }
    onExited: {
      const now = {}
      let assetChanged = false
      const first = Object.keys(live.seen).length === 0
      for (const line of pollOut.text.split("\n")) {
        const i = line.indexOf(" ")
        if (i < 0) continue
        const name = line.slice(0, i), sig = line.slice(i + 1)
        now[name] = sig
        if (live.seen[name] === sig) continue
        if (name === "FramePainter.js") painterFile.reload()
        else if (name === "MenuModel.js") menuFile.reload()
        else if (!first) assetChanged = true
      }
      for (const name in live.seen) if (!(name in now) && name.indexOf("assets/") === 0) assetChanged = true
      live.seen = now
      if (assetChanged) { live.assetRev++; live.version++ }
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true
  }
}
