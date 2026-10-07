// Scratchpad Frame: a frame around the scratchpad special workspace
// (SUPER + S). It rides the scratchpad's own slide animation:
// Hyprland's specialWorkspace anim is "slidevert", speed 3 (300 ms),
// easeOutQuint, entering from the bottom and leaving downwards.
// Smooth (vector) styles: OMARCHY, CYBERPUNK, AURORA, HUD, TERMINAL, GLASS,
//                         FOLIAGE, SACRED, KAWAII, CELESTIAL, VAPORWAVE, SAKURA, DEEPSEA,
//                         STEAMPUNK, FROST, HALLOWEEN, COSMIC, MEGACITY
// 16-bit pixel styles:    CRYSTAL, ROYAL, WOOD, DUNGEON
// "Follow Omarchy theme colors": every style recolours itself from the theme.
// All drawing lives in FramePainter.js (add a style there, list it in NAMES).
// Picker: omarchy-shell scratchpad-frame menu  (centered list, Up/Down + Enter, F toggles follow, T toggles the title, Esc closes)
// IPC: omarchy-shell scratchpad-frame menu | next | prev | set <name> | current | list | follow [on|off|toggle] | title [on|off|toggle] | lead <ms>
//      state (JSON of everything) | pads (JSON) | padsSet '{"pads": [...]}'
// More scratchpads: ~/.local/state/scratchpad-frame/pads.json lists extra special workspaces
// (name, label, slide-in direction, optional own style). Without the file only SUPER + S gets a frame.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "FramePainter.js" as Painter

Scope {
  id: root

  // Host injection (unused, declared so the shell can set them)
  property var omarchyPath
  property var shell
  property var manifest

  // One entry per framed special workspace: special:<name>, slides in from <direction>, own <style> or "" for the shared one.
  readonly property var defaultPads: [{ name: "scratchpad", label: "SCRATCHPAD", direction: "bottom", style: "" }]
  property var pads: defaultPads
  readonly property var directions: ["bottom", "top", "left", "right"]
  readonly property int gap: 26      // outer gap on the scratchpad so the frame sits in the gap
  readonly property int px: 3        // size of one "16-bit" pixel
  readonly property int duration: 300
  readonly property var curve: [0.23, 1, 0.32, 1]  // easeOutQuint (cubic bezier x1 y1 x2 y2)
  // The compositor starts its slide before the event reaches us and our
  // surface commit lands a frame or two later, so start this far into the curve.
  property int lead: 40

  function ease(t) {
    if (t <= 0) return 0
    if (t >= 1) return 1
    const c = curve
    const bx = (u) => 3 * (1 - u) * (1 - u) * u * c[0] + 3 * (1 - u) * u * u * c[2] + u * u * u
    const by = (u) => 3 * (1 - u) * (1 - u) * u * c[1] + 3 * (1 - u) * u * u * c[3] + u * u * u
    let lo = 0, hi = 1
    for (let i = 0; i < 24; i++) {
      const m = (lo + hi) / 2
      if (bx(m) < t) lo = m; else hi = m
    }
    return by((lo + hi) / 2)
  }

  readonly property var styleNames: Painter.NAMES
  readonly property string fontFamily: Qt.fontFamilies().indexOf("JetBrainsMono Nerd Font") >= 0
    ? "'JetBrainsMono Nerd Font'" : "monospace"
  property string style: "CRYSTAL"
  property string flash: ""          // style name shown on the plate for a moment
  property bool follow: false        // recolour every style from the Omarchy theme
  property bool showTitle: true      // draw the SCRATCHPAD label (the style-name flash still shows)

  // Picker menu. While it is open the frame previews the highlighted style.
  property bool menuOpen: false
  property string menuMonitor: ""
  property string preview: ""

  function openMenu() {
    const fm = Hyprland.focusedMonitor
    menuMonitor = fm ? fm.name : (Quickshell.screens.length ? Quickshell.screens[0].name : "")
    preview = style
    theme.reload()
    menuOpen = true
  }
  function closeMenu() { menuOpen = false; preview = "" }

  function setStyle(name, announce) {
    name = String(name).toUpperCase()
    if (styleNames.indexOf(name) < 0) return
    style = name
    if (announce) { flash = name; flashTimer.restart() }
    styleFile.setText(name + "\n")
  }
  function setFollow(on) {
    follow = on
    followFile.setText(on ? "on\n" : "off\n")
  }
  function setTitle(on) {
    showTitle = on
    titleFile.setText(on ? "on\n" : "off\n")
  }
  function cleanPads(list) {
    const out = []
    const seen = {}
    if (!Array.isArray(list)) return defaultPads
    for (const p of list) {
      if (!p || typeof p.name !== "string" || !/^[a-z0-9_-]{1,24}$/.test(p.name) || seen[p.name]) continue
      seen[p.name] = true
      const style = typeof p.style === "string" ? p.style.toUpperCase() : ""
      out.push({
        name: p.name,
        label: typeof p.label === "string" ? p.label.slice(0, 24) : p.name.toUpperCase(),
        direction: directions.indexOf(p.direction) >= 0 ? p.direction : "bottom",
        style: styleNames.indexOf(style) >= 0 ? style : ""
      })
    }
    return out
  }
  function setPads(list) {
    pads = cleanPads(list)
    padsFile.setText(JSON.stringify(pads) + "\n")
    applyGaps()
  }
  function padStyle(pad) {
    const own = pad.style !== "" ? pad.style : root.style
    return menuOpen && preview !== "" && pad.style === "" ? preview : own
  }
  Timer { id: flashTimer; interval: 1400; onTriggered: root.flash = "" }

  FileView {
    id: styleFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/style"
    onLoaded: {
      const n = text().trim().toUpperCase()
      if (root.styleNames.indexOf(n) >= 0) root.style = n
    }
  }

  FileView {
    id: followFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/follow"
    onLoaded: root.follow = text().trim() === "on"
  }

  FileView {
    id: titleFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/title"
    onLoaded: root.showTitle = text().trim() !== "off"
  }

  FileView {
    id: padsFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/pads.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try {
        const next = root.cleanPads(JSON.parse(text()))
        if (JSON.stringify(next) !== JSON.stringify(root.pads)) { root.pads = next; root.applyGaps() }
      } catch (e) {}
    }
  }

  FileView {
    id: leadFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/lead"
    onLoaded: { const n = parseInt(text()); if (n >= 0 && n <= 200) root.lead = n }
  }

  IpcHandler {
    target: "scratchpad-frame"
    function next(): string {
      const i = root.styleNames.indexOf(root.style)
      root.setStyle(root.styleNames[(i + 1) % root.styleNames.length], true)
      return root.style
    }
    function prev(): string {
      const i = root.styleNames.indexOf(root.style)
      root.setStyle(root.styleNames[(i + root.styleNames.length - 1) % root.styleNames.length], true)
      return root.style
    }
    function menu(): string {
      if (root.menuOpen) root.closeMenu(); else root.openMenu()
      return root.menuOpen ? "open" : "closed"
    }
    function list(): string { return root.styleNames.join(" ") }
    function set(name: string): string { root.setStyle(name, true); return root.style }
    function current(): string { return root.style }
    function pads(): string { return JSON.stringify(root.pads) }
    function padsSet(json: string): string {
      // An object {"pads": [...]} is the one-argument form: the shell CLI splits a bare JSON array into several arguments.
      try { const v = JSON.parse(json); root.setPads(Array.isArray(v) ? v : v.pads) } catch (e) { return "error: not valid JSON" }
      return JSON.stringify(root.pads)
    }
    function state(): string {
      return JSON.stringify({ style: root.style, follow: root.follow, title: root.showTitle, lead: root.lead,
                              styles: root.styleNames, pads: root.pads })
    }
    function lead(ms: string): string {
      const n = parseInt(ms)
      if (n >= 0 && n <= 200) { root.lead = n; leadFile.setText(n + "\n") }
      return String(root.lead)
    }
    function title(mode: string): string {
      const m = String(mode).toLowerCase()
      if (m === "on" || m === "off") root.setTitle(m === "on")
      else if (m === "toggle") root.setTitle(!root.showTitle)
      return root.showTitle ? "on" : "off"
    }
    function follow(mode: string): string {
      const m = String(mode).toLowerCase()
      if (m === "on" || m === "off") root.setFollow(m === "on")
      else if (m === "toggle") root.setFollow(!root.follow)
      return root.follow ? "on" : "off"
    }
  }

  // ---- scratchpad gap ------------------------------------------------------
  // Widen gaps_out on the scratchpad at runtime (no config edits). Hyprland
  // drops runtime rules on a config reload, so it is re-applied on
  // configreloaded, and put back to the global gap when the plugin goes away.
  property int baseGap: 10
  property var gapped: []          // pad names whose gap is widened right now
  function gapLua(names, n) {
    return names.map(function(name) {
      return 'hl.workspace_rule({ workspace = "special:' + name + '", gaps_out = ' + Math.round(n) + ' })'
    }).join("; ")
  }
  function applyGaps() {
    const names = pads.map(function(p) { return p.name })
    let code = gapLua(gapped.filter(function(n) { return names.indexOf(n) < 0 }), baseGap)
    code += (code !== "" ? "; " : "") + gapLua(names, gap)
    gapped = names
    if (code === "") return
    gapProc.command = ["hyprctl", "eval", code]
    gapProc.running = true
  }
  Process { id: gapProc }
  Process {
    id: baseProc
    command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const n = parseInt(JSON.parse(text).css.split(" ")[0])
          if (n >= 0) root.baseGap = n
        } catch (e) {}
      }
    }
  }
  Component.onCompleted: { baseProc.running = true; applyGaps() }
  Component.onDestruction: {
    Quickshell.execDetached(["hyprctl", "eval", gapLua(gapped, baseGap)])
  }

  // Monitor name -> name of the special workspace showing there ("" when none)
  property var openOn: ({})

  function setOpen(monitor, name) {
    if (openOn[monitor] === name) return
    const next = Object.assign({}, openOn)
    next[monitor] = name
    openOn = next
    if (name !== "") theme.reload()
  }

  // ---- theme colours -----------------------------------------------------
  property var colors: ({})
  FileView {
    id: theme
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    property string last: ""
    onLoaded: {
      if (text() === last) return   // unchanged: do not repaint every frame
      last = text()
      const c = {}
      for (const line of text().split("\n")) {
        const m = line.match(/^\s*([a-z_0-9]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (m) c[m[1]] = m[2]
      }
      root.colors = c
    }
  }
  function col(name, fallback) { return colors[name] || fallback }

  // ---- Hyprland state ------------------------------------------------------
  Process {
    id: initial
    running: true
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          for (const m of JSON.parse(text))
            root.setOpen(m.name, m.specialWorkspace ? m.specialWorkspace.name : "")
        } catch (e) {}
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.gapped = []; root.applyGaps(); return }
      // activespecial>>NAME,MONITOR  (NAME empty when closed)
      if (event.name !== "activespecial") return
      const i = event.data.lastIndexOf(",")
      if (i < 0) return
      root.setOpen(event.data.slice(i + 1), event.data.slice(0, i))
    }
  }

  // ---- one frame per monitor and pad -----------------------------------------
  readonly property var frameModel: {
    const out = []
    for (const pad of pads)
      for (const screen of Quickshell.screens) out.push({ pad: pad, screen: screen })
    return out
  }

  Variants {
    model: root.frameModel

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData.screen

      readonly property var pad: modelData.pad
      readonly property string workspaceName: "special:" + pad.name
      readonly property string style: root.padStyle(pad)
      readonly property string label: pad.label
      readonly property bool shown: root.openOn[screen.name] === workspaceName
      // Where the pad rests when hidden: one screen length away, on the side it slides in from.
      readonly property real hideX: pad.direction === "left" ? -screen.width : (pad.direction === "right" ? screen.width : 0)
      readonly property real hideY: pad.direction === "top" ? -screen.height : (pad.direction === "bottom" ? screen.height : 0)
      property real fromX: hideX
      property real fromY: hideY
      property real toX: hideX
      property real toY: hideY
      property real prog: 1
      onShownChanged: {
        slide.stop()
        fromX = frame.x
        fromY = frame.y
        toX = shown ? 0 : hideX
        toY = shown ? 0 : hideY
        const lead = Math.min(root.lead, root.duration - 20) / root.duration
        prog = lead
        slide.from = lead
        slide.duration = root.duration * (1 - lead)
        slide.start()
      }
      NumberAnimation {
        id: slide
        target: win
        property: "prog"
        to: 1
        easing.type: Easing.Linear
      }

      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0                      // stay below the bar
      WlrLayershell.layer: WlrLayer.Top
      WlrLayershell.namespace: "scratchpad-frame"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      mask: Region {}                       // fully click-through

      // Always mapped (transparent + click-through) so the slide starts in
      // the same frame as Hyprland's, with no layer map animation in between.
      visible: true

      Item {
        anchors.fill: parent
        clip: true

        Canvas {
          id: frame
          width: parent.width
          height: parent.height
          // Hyprland offsets the workspace by the full monitor size, not the
          // (bar-reduced) layer size, so travel the same distance.
          x: win.fromX + (win.toX - win.fromX) * root.ease(win.prog)
          y: win.fromY + (win.toY - win.fromY) * root.ease(win.prog)

          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onImageLoaded: requestPaint()
          Connections {
            target: root
            function onColorsChanged() { frame.requestPaint() }
            function onFollowChanged() { frame.requestPaint() }
            function onFlashChanged() { frame.requestPaint() }
            function onShowTitleChanged() { frame.requestPaint() }
          }
          Connections {
            target: win
            function onStyleChanged() { frame.requestPaint() }
            function onLabelChanged() { frame.requestPaint() }
          }

          onPaint: Painter.paint(getContext("2d"), width, height, {
            style: win.style, text: root.flash || (root.showTitle ? win.label : ""), colors: root.colors,
            px: root.px, font: root.fontFamily, follow: root.follow, assets: Qt.resolvedUrl("assets/").toString()
          })
        }
      }
    }
  }
  // ---- style picker (centered, on the focused monitor) ----------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: pickWin
      required property var modelData
      screen: modelData
      visible: root.menuOpen && root.menuMonitor === modelData.name

      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "scratchpad-frame-menu"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      color: Qt.rgba(0, 0, 0, 0.45)

      StylePicker {
        anchors.fill: parent
        names: root.styleNames
        colors: root.colors
        current: root.style
        follow: root.follow
        showTitle: root.showTitle
        font: root.fontFamily
        focus: pickWin.visible
        onSelectedChanged: if (pickWin.visible) root.preview = names[selected] || root.style
        onPicked: (name) => { root.setStyle(name, false); root.closeMenu() }
        onFollowToggled: root.setFollow(!root.follow)
        onTitleToggled: root.setTitle(!root.showTitle)
        onClosed: root.closeMenu()
      }
    }
  }
}
