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
// Picker: omarchy-shell scratchpad-frame menu  (centered list, Up/Down + Enter, F toggles follow, T toggles the title, W creates a theme from a wallpaper, Esc closes)
// IPC: omarchy-shell scratchpad-frame menu | next | prev | set <name> | current | list | follow [on|off|toggle] | title [on|off|toggle] | newtheme | lead <ms>

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

  readonly property string target: "special:scratchpad"
  readonly property string label: "SCRATCHPAD"
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
  readonly property string shownStyle: menuOpen && preview !== "" ? preview : style

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
  function newThemeFromWallpaper() {
    closeMenu()
    Quickshell.execDetached(["bash", Qt.resolvedUrl("make-theme.sh").toString().replace("file://", "")])
  }
  function setTitle(on) {
    showTitle = on
    titleFile.setText(on ? "on\n" : "off\n")
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
    function newtheme(): string { root.newThemeFromWallpaper(); return "choose a wallpaper" }
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
  function applyGap(n) {
    gapProc.command = ["hyprctl", "eval",
      'hl.workspace_rule({ workspace = "' + root.target + '", gaps_out = ' + Math.round(n) + ' })']
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
  Component.onCompleted: { baseProc.running = true; applyGap(gap) }
  Component.onDestruction: {
    Quickshell.execDetached(["hyprctl", "eval",
      'hl.workspace_rule({ workspace = "' + root.target + '", gaps_out = ' + root.baseGap + ' })'])
  }

  // Monitor name -> is the scratchpad showing there
  property var openOn: ({})

  function setOpen(monitor, open) {
    if (openOn[monitor] === open) return
    const next = Object.assign({}, openOn)
    next[monitor] = open
    openOn = next
    if (open) theme.reload()
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
            root.setOpen(m.name, m.specialWorkspace && m.specialWorkspace.name === root.target)
        } catch (e) {}
      }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.applyGap(root.gap); return }
      // activespecial>>NAME,MONITOR  (NAME empty when closed)
      if (event.name !== "activespecial") return
      const i = event.data.lastIndexOf(",")
      if (i < 0) return
      root.setOpen(event.data.slice(i + 1), event.data.slice(0, i) === root.target)
    }
  }

  // ---- one frame per monitor ----------------------------------------------
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      readonly property bool shown: root.openOn[modelData.name] === true
      property real fromY: modelData.height
      property real toY: modelData.height
      property real prog: 1
      onShownChanged: {
        slide.stop()
        fromY = frame.y
        toY = shown ? 0 : modelData.height
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
          // Hyprland offsets the workspace by the full monitor height, not the
          // (bar-reduced) layer height, so travel the same distance.
          y: win.fromY + (win.toY - win.fromY) * root.ease(win.prog)

          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Connections {
            target: root
            function onColorsChanged() { frame.requestPaint() }
            function onShownStyleChanged() { frame.requestPaint() }
            function onFollowChanged() { frame.requestPaint() }
            function onFlashChanged() { frame.requestPaint() }
            function onShowTitleChanged() { frame.requestPaint() }
          }

          onPaint: Painter.paint(getContext("2d"), width, height, {
            style: root.shownStyle, text: root.flash || (root.showTitle ? root.label : ""), colors: root.colors,
            px: root.px, font: root.fontFamily, follow: root.follow
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
        onThemeFromWallpaper: root.newThemeFromWallpaper()
        onClosed: root.closeMenu()
      }
    }
  }
}
