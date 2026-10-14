// Scratchpad Frame: a frame around the scratchpad special workspace
// (SUPER + S). It rides the scratchpad's own animation: by default Hyprland's specialWorkspace
// anim, "slidevert", speed 3 (300 ms), easeOutQuint, entering from the bottom and leaving downwards.
// A pad can come in and go out in its own way (AktKit.js EFFECTS, from the bottom or the right);
// the frame repeats the same step, so it stays glued to the windows.
// Smooth (vector) styles: OMARCHY, CYBERPUNK, AURORA, HUD, TERMINAL, GLASS,
//                         FOLIAGE, SACRED, KAWAII, CELESTIAL, VAPORWAVE, SAKURA, DEEPSEA,
//                         STEAMPUNK, FROST, HALLOWEEN, COSMIC, MEGACITY
// 16-bit pixel styles:    CRYSTAL, ROYAL, WOOD, DUNGEON
// "Follow Omarchy theme colors": every style recolours itself from the theme.
// All drawing lives in FramePainter.js (add a style there with one PAINTERS entry). StyleLive.qml reloads it, MenuModel.js and assets/ while the shell runs.
// Picker: omarchy-shell scratchpad-frame menu  (centered list, Up/Down + Enter, F toggles follow, T toggles the title, Esc closes)
// Bar icon + menu: BarWidget.qml (categories and a live thumbnail; hover previews the style on the open scratchpad).
// IPC: omarchy-shell scratchpad-frame menu | next | prev | set <name> | current | list | follow [on|off|toggle] | title [on|off|toggle] | keepHidden [on|off|toggle] | lead <ms>
//      preview <name> | previewPad <name> <pad> | previewEnd
//      looks (JSON) | previewLook <pad> <recipe JSON> | lookSet <pad> <recipe JSON> | lookClear <pad>   (frames made by bin/frame-ai: a style plus colours)
//      state (JSON of everything) | pads (JSON) | padsSet '{"pads": [...]}'
// Scratchpad keys, directions and startup apps: AktEngine.qml (target scratchpad-frame.layers); the cards window: BarWidget.qml (target scratchpad-frame.panel).
// Per-pad "fit" (AktEngine padSet <pad> fit on): the frame hugs the pad's windows instead of the whole screen.
// More scratchpads: ~/.local/state/scratchpad-frame/pads.json lists extra special workspaces
// (name, label, slide-in direction, optional own style, outDirection, effect, outEffect). Without the file only SUPER + S gets a frame.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "AktKit.js" as Kit

Scope {
  id: root

  // Host injection (unused, declared so the shell can set them)
  property var omarchyPath
  property var shell
  property var manifest

  // One entry per framed special workspace: special:<name>, slides in from <direction>, own <style> or "" for the shared one.
  readonly property var defaultPads: [{ name: "scratchpad", label: "SCRATCHPAD", direction: "bottom", style: "" }]
  property var pads: defaultPads
  readonly property int fsInset: 12     // fullscreen: the frame is drawn this far past the monitor edge, so only a sliver of it covers the window
  readonly property int fsTitleDrop: 14  // the title tab moves down this far so the equal top inset does not cut it off
  readonly property int gap: 26      // outer gap on the scratchpad so the frame sits in the gap
  readonly property int px: 3        // size of one "16-bit" pixel
  readonly property int duration: 300
  readonly property var curve: [0.23, 1, 0.32, 1]  // easeOutQuint (cubic bezier x1 y1 x2 y2), the curve of Omarchy's own slide
  // The compositor starts its slide before the event reaches us and our
  // surface commit lands a frame or two later, so start this far into the curve.
  property int lead: 40

  // The motion of one step (in or out) of a pad: how long, which curve, which way, whether it fades.
  function stepOf(effect, side, w, h) {
    const fx = Kit.effectInfo(effect)
    const slides = fx.style === "slide" || fx.style === "slidefade"
    return {
      instant: fx.style === "none",
      duration: fx.speed ? fx.speed * 100 : duration,
      curve: fx.curve || curve,
      fade: fx.style === "fade" || fx.style === "slidefade",
      x: slides && side === "right" ? w : 0,
      y: slides && side !== "right" ? h : 0
    }
  }

  function ease(t, c) {
    if (t <= 0) return 0
    if (t >= 1) return 1
    const bx = (u) => 3 * (1 - u) * (1 - u) * u * c[0] + 3 * (1 - u) * u * u * c[2] + u * u * u
    const by = (u) => 3 * (1 - u) * (1 - u) * u * c[1] + 3 * (1 - u) * u * u * c[3] + u * u * u
    let lo = 0, hi = 1
    for (let i = 0; i < 24; i++) {
      const m = (lo + hi) / 2
      if (bx(m) < t) lo = m; else hi = m
    }
    return by((lo + hi) / 2)
  }

  StyleLive { id: live }
  readonly property var styleNames: live.painter.NAMES
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

  // The bar menu previews a style on the frame the same way; it clears itself if the bar menu goes away without saying so.
  property bool barPreview: false
  property string previewPad: ""     // the bar menu previews one scratchpad; "" means every pad without its own style
  property var previewLook: null     // a frame-designer recipe being previewed on previewPad instead of a plain style
  function setBarPreview(name, pad) {
    name = String(name).toUpperCase()
    if (styleNames.indexOf(name) < 0 && name !== "OWNART") return
    previewPad = pad || ""
    previewLook = null
    preview = name
    barPreview = true
    barPreviewTimer.restart()
  }
  function endBarPreview() {
    barPreview = false
    previewPad = ""
    previewLook = null
    barPreviewTimer.stop()
    if (!menuOpen) preview = ""
  }
  Timer { id: barPreviewTimer; interval: 60000; onTriggered: root.endBarPreview() }

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
        direction: Kit.cleanSide(p.direction) || "bottom",
        outDirection: Kit.cleanSide(p.outDirection) || Kit.cleanSide(p.direction) || "bottom",
        effect: Kit.cleanEffect(p.effect) || Kit.DEFAULT_EFFECT,
        outEffect: Kit.cleanEffect(p.outEffect) || Kit.cleanEffect(p.effect) || Kit.DEFAULT_EFFECT,
        style: styleNames.indexOf(style) >= 0 ? style : "",
        fit: p.fit === true
      })
    }
    return out
  }
  // The scratchpads (names, keys, directions, own styles, startup apps) are kept by the shared AktOn1 engine; this plugin frames them.
  AktEngine {
    id: layers
    name: "scratchpad-frame"
    label: "Scratchpad Frame"
    scope: "pads"
    styles: root.styleNames
    sharedStyle: root.style
  }
  function syncPads() { if (layers.loaded) setPads(Kit.framePads(layers.state)) }
  Connections {
    target: layers
    function onStateChanged() { root.syncPads() }
    function onLoadedChanged() { root.syncPads() }
  }

  function setPads(list) {
    pads = cleanPads(list)
    padsFile.setText(JSON.stringify(pads) + "\n")
    applyGaps()
  }
  // ---- frames made by the frame designer (bin/frame-ai) --------------------------
  // A look is data only: an existing style plus colours that replace the theme colours. The AI's answer is checked
  // in bin/framedesign.py and again here, so a hand-edited looks.json cannot put anything else into the painter.
  property var looks: ({})            // pad name -> {name, style, colors}
  readonly property var lookColorKeys: ["accent", "background", "darker_background", "foreground", "bright_foreground", "muted",
    "red", "green", "yellow", "orange", "blue", "cyan", "magenta", "brown"]
  function cleanLook(l) {
    if (!l || typeof l !== "object" || typeof l.style !== "string") return null
    const style = l.style.toUpperCase()
    if (styleNames.indexOf(style) < 0 && style !== "OWNART") return null   // OWNART: the designer's own-ornament frame, not in the picker
    const colors = {}
    if (l.colors && typeof l.colors === "object")
      for (const k of lookColorKeys) {
        const v = l.colors[k]
        if (v === undefined) continue
        if (typeof v !== "string" || !/^#[0-9a-fA-F]{6}$/.test(v)) return null
        colors[k] = v.toLowerCase()
      }
    const name = typeof l.name === "string" ? l.name.replace(/[^\w .,'&-]/g, "").trim().slice(0, 40) : ""
    const out = { name: name || style.charAt(0) + style.slice(1).toLowerCase(), style: style, colors: colors }
    if (style === "OWNART") {   // a generated ornament is named by a 12-digit hex id, never by a path
      out.ornament = typeof l.ornament === "string" && /^[0-9a-f]{12}$/.test(l.ornament) ? l.ornament : ""
      out.ornamentText = typeof l.ornamentText === "string" ? l.ornamentText.replace(/[^\w .,'&()\/-]/g, " ").replace(/\s+/g, " ").trim().slice(0, 140) : ""
    }
    return out
  }
  function cleanLooks(o) {
    const out = {}
    if (o && typeof o === "object")
      for (const pad of Object.keys(o)) {
        const l = /^[a-z0-9_-]{1,24}$/.test(pad) ? cleanLook(o[pad]) : null
        if (l) out[pad] = l
      }
    return out
  }
  function saveLooks(next) {
    looks = next
    looksFile.setText(JSON.stringify(next) + "\n")
    pruneDelay.restart()
  }
  // Generated ornaments live in the state folder. Whatever no saved look uses is removed after every save (Apply, Remove, a plain style
  // picked over a custom frame) and once after start; the one being previewed is kept. The newest 12 are the most that are ever stored.
  readonly property string cli: Qt.resolvedUrl("bin/frame-ai").toString().replace(/^file:\/\//, "")
  readonly property string ornamentsUrl: "file://" + Quickshell.env("HOME") + "/.local/state/scratchpad-frame/ornaments/"
  function pruneOrnaments() {
    if (pruneProc.running) { pruneDelay.restart(); return }
    const keep = previewLook && previewLook.ornament ? ["--keep", previewLook.ornament] : []
    pruneProc.command = ["python3", cli, "ornaments", "prune"].concat(keep)
    pruneProc.running = true
  }
  Timer { id: pruneDelay; interval: 800; onTriggered: root.pruneOrnaments() }
  Timer { interval: 6000; running: true; onTriggered: root.pruneOrnaments() }
  Process { id: pruneProc }
  function parseLook(json) { try { return cleanLook(JSON.parse(json)) } catch (e) { return null } }
  // The look a pad's frame shows right now: a previewed recipe, else its saved one, unless a plain style is being previewed on it.
  function lookFor(pad) {
    const previewing = (menuOpen || barPreview) && preview !== ""
    const hit = previewPad !== "" && barPreview ? pad.name === previewPad : pad.style === ""
    if (previewing && hit) return previewLook
    return looks[pad.name] || null
  }
  function padStyle(pad) {
    const own = pad.style !== "" ? pad.style : root.style
    const previewing = (menuOpen || barPreview) && preview !== ""
    const hit = previewPad !== "" && barPreview ? pad.name === previewPad : pad.style === ""
    return previewing && hit ? preview : own
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
    id: looksFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/looks.json"
    printErrors: false
    onLoaded: { try { root.looks = root.cleanLooks(JSON.parse(text())) } catch (e) {} }
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
    atomicWrites: true
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
    function preview(name: string): string { root.setBarPreview(name, ""); return root.preview }
    function previewPad(name: string, pad: string): string { root.setBarPreview(name, pad); return root.preview }
    function previewEnd(): string { root.endBarPreview(); return "ok" }
    function looks(): string { return JSON.stringify(root.looks) }
    function previewLook(pad: string, json: string): string {
      const l = root.parseLook(json)
      if (!l || !root.pads.some(function(p) { return p.name === pad })) return "error: not a valid recipe or pad"
      root.setBarPreview(l.style, pad)
      root.previewLook = l
      return "ok"
    }
    function lookSet(pad: string, json: string): string {
      const l = root.parseLook(json)
      if (!l || !root.pads.some(function(p) { return p.name === pad })) return "error: not a valid recipe or pad"
      const next = Object.assign({}, root.looks)
      next[pad] = l
      root.saveLooks(next)
      root.endBarPreview()
      return "ok"
    }
    function lookClear(pad: string): string {
      const next = Object.assign({}, root.looks)
      delete next[pad]
      root.saveLooks(next)
      return "ok"
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
      return JSON.stringify({ style: root.style, follow: root.follow, title: root.showTitle, keepHidden: root.keepHidden, lead: root.lead,
                              styles: root.styleNames, pads: root.pads, looks: root.looks })
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
    function keepHidden(mode: string): string {
      const m = String(mode).toLowerCase()
      if (m === "on" || m === "off") root.setKeepHidden(m === "on")
      else if (m === "toggle") root.setKeepHidden(!root.keepHidden)
      return root.keepHidden ? "on" : "off"
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
  Component.onDestruction: Quickshell.execDetached(["hyprctl", "eval", gapLua(gapped, baseGap)])

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

  // ---- keep a hidden scratchpad hidden after a flyout closes ---------------
  // When a flyout (a layer surface with keyboard focus, e.g. a bar menu) closes, Hyprland
  // refocuses the last focused window; if that sits on a hidden special workspace, the
  // workspace pops open. Signature: a focus change right before activespecial while a
  // flyout layer is open (or just closed). A real SUPER + S fires activespecial first.
  property bool keepHidden: true
  readonly property var permanentLayers: ["omarchy-background", "omarchy-bar", "omarchy-notifications", "scratchpad-frame", "wallpaper-fx"]
  // Layers of this shell that never take keyboard focus (cursor/shader overlays, drag ghosts, OSD, banners): never a flyout.
  readonly property var passiveLayers: ["omashaders-mouse", "omashaders-bend-marker", "omarchy-osd", "omarchy-bar-drag-ghost", "omarchy-bar-move-ghost",
    "omarchy-lock-preview", "scratch-frame", "background-worker-talk-to-me-shield", "background-worker-talk-to-me-banner", "background-worker-talk-to-me-done"]
  // A flyout is something a person opened a moment ago; a layer that has been open for minutes is a permanent overlay.
  readonly property int flyoutMaxAgeMs: 120000
  property var flyouts: ({})
  property var ownLayers: ({})   // namespaces seen with this shell's process id
  property double lastFocusMs: 0
  property double lastFlyoutCloseMs: 0

  function setKeepHidden(on) {
    keepHidden = on
    keepHiddenFile.setText(on ? "on\n" : "off\n")
  }
  FileView {
    id: keepHiddenFile
    path: Quickshell.env("HOME") + "/.local/state/scratchpad-frame/keep-hidden"
    onLoaded: root.keepHidden = text().trim() !== "off"
  }

  // Other programs keep layers of their own open and close them all the time (mascots, the
  // companion overlay, pills). They are no flyouts of this shell: only layers with this shell's
  // process id count, both when they open and when they close.
  property bool recheckAgain: false
  function checkFlyouts() {
    if (layerProc.running) { recheckAgain = true; return }
    layerProc.running = true
  }
  Process {
    id: layerProc
    command: ["hyprctl", "-j", "layers"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const pids = {}
          let own = 0
          const data = JSON.parse(text)
          for (const mon of Object.keys(data))
            for (const lvl of Object.keys(data[mon].levels))
              for (const l of data[mon].levels[lvl]) {
                pids[l.namespace] = l.pid
                if (l.namespace === "scratchpad-frame") own = l.pid
              }
          if (own) {
            const mine = Object.assign({}, root.ownLayers)
            for (const n of Object.keys(pids)) if (pids[n] === own) mine[n] = true
            root.ownLayers = mine
            const next = Object.assign({}, root.flyouts)
            for (const n of Object.keys(next))
              if (pids[n] !== undefined && pids[n] !== own) delete next[n]
            root.flyouts = next
          }
        } catch (e) {}
        if (root.recheckAgain) { root.recheckAgain = false; layerProc.running = true }
      }
    }
  }

  function flyoutActive() {
    const now = Date.now()
    for (const n of Object.keys(flyouts)) if (now - flyouts[n] < flyoutMaxAgeMs) return true
    return now - lastFlyoutCloseMs < 400
  }
  function isPadWorkspace(name) {
    for (const p of pads) if ("special:" + p.name === name) return true
    return false
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.gapped = []; root.applyGaps(); return }
      if (event.name === "activewindowv2") { root.lastFocusMs = Date.now(); return }
      if (event.name === "fullscreen" || event.name === "closewindow" || event.name === "movewindowv2") { root.checkFullscreen(); return }
      if (event.name === "openlayer" || event.name === "closelayer") {
        if (root.permanentLayers.indexOf(event.data) >= 0 || root.passiveLayers.indexOf(event.data) >= 0) return
        const next = Object.assign({}, root.flyouts)
        if (event.name === "openlayer") { next[event.data] = Date.now(); root.checkFlyouts() }
        else {
          delete next[event.data]
          if (root.ownLayers[event.data]) root.lastFlyoutCloseMs = Date.now()
        }
        root.flyouts = next
        return
      }
      // activespecial>>NAME,MONITOR  (NAME empty when closed)
      if (event.name !== "activespecial") return
      const i = event.data.lastIndexOf(",")
      if (i < 0) return
      const name = event.data.slice(0, i)
      const monitor = event.data.slice(i + 1)
      if (root.keepHidden && name !== "" && root.openOn[monitor] !== name && root.isPadWorkspace(name)
          && Date.now() - root.lastFocusMs < 250 && root.flyoutActive()) {
        // through the engine, so the pad goes out the way it is set to go out
        if (layers.toggle(name.slice(8)) !== "ok")
          Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.workspace.toggle_special("' + name.slice(8) + '")'])
        return
      }
      root.setOpen(monitor, name)
      root.checkFullscreen()
    }
  }

  // ---- fit the frame to the windows ----------------------------------------
  // A pad with "fit" on frames the bounding box of its windows (plus the gap) instead of the whole
  // screen. Hyprland sends no event while a floating window is dragged or resized, so poll while
  // such a pad is open. boxes["special:<pad>|<monitor>"] is {x, y, w, h} in layer coordinates, or
  // {empty: true} when the pad has no windows (the frame stays full-size then).
  property var boxes: ({})
  readonly property bool fitActive: {
    for (const p of pads)
      if (p.fit) for (const m of Object.keys(openOn)) if (openOn[m] === "special:" + p.name) return true
    return false
  }
  // fsOn["special:<pad>|<monitor>"] is true while a window of that open pad is fullscreen: the frame then
  // covers the whole monitor, above the window.
  property var fsOn: ({})
  function checkFullscreen() {
    if (!boxProc.running) boxProc.running = true
  }
  function applyBoxes(monitors, clients) {
    const next = {}
    const nextFs = {}
    for (const m of monitors) {
      const ws = m.specialWorkspace ? m.specialWorkspace.name : ""
      if (ws === "" || !isPadWorkspace(ws)) continue
      let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, n = 0, fs = false
      for (const c of clients) {
        if (!c.mapped || c.monitor !== m.id || !c.workspace || c.workspace.name !== ws) continue
        if (c.fullscreen === 2) fs = true
        x0 = Math.min(x0, c.at[0]); y0 = Math.min(y0, c.at[1])
        x1 = Math.max(x1, c.at[0] + c.size[0]); y1 = Math.max(y1, c.at[1] + c.size[1])
        n++
      }
      if (fs) nextFs[ws + "|" + m.name] = true
      if (!pads.some(function(p) { return p.fit && "special:" + p.name === ws })) continue
      const res = m.reserved || [0, 0, 0, 0]
      next[ws + "|" + m.name] = n === 0 ? { empty: true }
        : { x: x0 - m.x - res[0], y: y0 - m.y - res[1], w: x1 - x0, h: y1 - y0 }
    }
    const merged = Object.assign({}, boxes)
    let changed = false
    for (const k of Object.keys(next))
      if (JSON.stringify(merged[k]) !== JSON.stringify(next[k])) { merged[k] = next[k]; changed = true }
    if (changed) boxes = merged
    if (JSON.stringify(nextFs) !== JSON.stringify(fsOn)) fsOn = nextFs
  }
  Process {
    id: boxProc
    command: ["sh", "-c", "hyprctl monitors -j; echo '@@'; hyprctl clients -j"]
    stdout: StdioCollector {
      onStreamFinished: {
        const i = text.indexOf("\n@@\n")
        if (i < 0) return
        try { root.applyBoxes(JSON.parse(text.slice(0, i)), JSON.parse(text.slice(i + 4))) } catch (e) {}
      }
    }
  }
  Timer {
    interval: 150
    repeat: true
    running: root.fitActive
    triggeredOnStart: true
    onTriggered: if (!boxProc.running) boxProc.running = true
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
      readonly property var look: root.lookFor(pad)
      readonly property string style: look ? look.style : root.padStyle(pad)
      readonly property string label: pad.label
      readonly property bool shown: root.openOn[screen.name] === workspaceName
      // Hyprland slides a special workspace in from the right or the bottom, one whole monitor length away.
      property real fromX: screen.width
      property real fromY: 0
      property real toX: screen.width
      property real toY: 0
      property real fromA: 0
      property real toA: 0
      property var curveNow: root.curve
      property real prog: 1
      property bool atRest: true            // fully out, so the next way in starts from its own side
      // The slide offset and opacity; the frame rests at frameRect when shown.
      readonly property real slideX: fromX + (toX - fromX) * root.ease(prog, curveNow)
      readonly property real slideY: fromY + (toY - fromY) * root.ease(prog, curveNow)
      readonly property real alphaNow: Math.max(0, Math.min(1, fromA + (toA - fromA) * root.ease(prog, curveNow)))
      readonly property var box: pad.fit ? (root.boxes[workspaceName + "|" + screen.name] || null) : null
      readonly property bool fullscreenNow: shown && root.fsOn[workspaceName + "|" + screen.name] === true
      property bool keepOver: false          // stay above the window while the pad slides out
      readonly property bool overWindow: fullscreenNow || keepOver
      onFullscreenNowChanged: { if (fullscreenNow) keepOver = true; else if (shown) keepOver = false }
      readonly property bool fitted: box !== null && box.empty !== true && !overWindow
      readonly property real minFrame: 120   // FramePainter.paint draws nothing below this
      readonly property real inset: overWindow ? root.fsInset : 0
            readonly property real frameW: fitted ? Math.round(Math.min(area.width, Math.max(minFrame, box.w + 2 * root.gap))) : area.width + 2 * inset
      readonly property real frameH: fitted ? Math.round(Math.min(area.height, Math.max(minFrame, box.h + 2 * root.gap))) : area.height + 2 * inset
      readonly property real frameX: fitted ? Math.round(Math.max(0, Math.min(area.width - frameW, box.x + box.w / 2 - frameW / 2))) : -inset
      readonly property real bleed: fitted ? live.painter.bleedFor(style) : 0   // outer contour room on every side
      readonly property real frameY: fitted ? Math.round(Math.max(0, Math.min(area.height - frameH, box.y + box.h / 2 - frameH / 2))) : -inset
      onShownChanged: {
        slide.stop()
        const step = root.stepOf(shown ? pad.effect : pad.outEffect, shown ? pad.direction : pad.outDirection, screen.width, screen.height)
        const wasAtRest = atRest
        fromX = slideX
        fromY = slideY
        fromA = alphaNow
        if (shown && wasAtRest) {
          fromX = step.x
          fromY = step.y
          fromA = step.fade ? 0 : 1
        }
        toX = shown ? 0 : step.x
        toY = shown ? 0 : step.y
        toA = shown ? 1 : (step.fade ? 0 : 1)
        curveNow = step.curve
        atRest = false
        if (step.instant) {
          fromX = toX; fromY = toY; fromA = toA
          prog = 1
          atRest = !shown
          return
        }
        const lead = Math.min(root.lead, step.duration - 20) / step.duration
        prog = lead
        slide.from = lead
        slide.duration = step.duration * (1 - lead)
        slide.start()
      }
      NumberAnimation {
        id: slide
        target: win
        property: "prog"
        to: 1
        easing.type: Easing.Linear
        onFinished: { win.atRest = !win.shown; if (win.atRest) win.keepOver = false }
      }

      anchors { top: true; bottom: true; left: true; right: true }
      // A fullscreen window covers the Top layer and the bar's strip, so the frame goes above it and over the whole monitor, mostly past the edge.
      exclusionMode: overWindow ? ExclusionMode.Ignore : ExclusionMode.Normal
      exclusiveZone: 0                      // stay below the bar
      WlrLayershell.layer: overWindow ? WlrLayer.Overlay : WlrLayer.Top
      WlrLayershell.namespace: "scratchpad-frame"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      mask: Region {}                       // fully click-through

      // Always mapped (transparent + click-through) so the slide starts in
      // the same frame as Hyprland's, with no layer map animation in between.
      visible: true

      Item {
        id: area
        anchors.fill: parent
        clip: true

        Canvas {
          id: frame
          width: win.frameW + 2 * win.bleed
          height: win.frameH + 2 * win.bleed
          // Hyprland offsets the workspace by the full monitor size, not the
          // (bar-reduced) layer size, so travel the same distance.
          x: win.frameX - win.bleed + win.slideX
          y: win.frameY - win.bleed + win.slideY
          opacity: win.alphaNow
          // A fitted pad waits for its first window measurement so the full frame never flashes.
          visible: !win.pad.fit || win.box !== null

          renderStrategy: Canvas.Cooperative
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          onImageLoaded: requestPaint()
          Component.onCompleted: live.painter.preload(frame, Qt.resolvedUrl("assets/").toString(), live.assetRev)
          Connections {
            target: root
            function onColorsChanged() { frame.requestPaint() }
            function onFollowChanged() { frame.requestPaint() }
            function onFlashChanged() { frame.requestPaint() }
            function onShowTitleChanged() { frame.requestPaint() }
          }
          Connections {
            target: live
            function onVersionChanged() { live.painter.preload(frame, Qt.resolvedUrl("assets/").toString(), live.assetRev); frame.requestPaint() }
          }
          Connections {
            target: win
            function onStyleChanged() { frame.requestPaint() }
            function onLabelChanged() { frame.requestPaint() }
            function onOverWindowChanged() { frame.requestPaint() }
            function onLookChanged() { frame.requestPaint() }
          }

          onPaint: live.painter.paint(getContext("2d"), width, height, {
            style: win.style, text: root.flash || (root.showTitle ? win.label : ""),
            colors: win.look ? Object.assign({}, root.colors, win.look.colors) : root.colors,
            titleDrop: win.overWindow ? root.fsTitleDrop : 0, px: root.px, font: root.fontFamily, follow: root.follow || (win.look !== null && Object.keys(win.look.colors).length > 0), bleed: win.bleed, assets: Qt.resolvedUrl("assets/").toString(), rev: live.assetRev,
            ornament: win.look && win.look.ornament ? win.look.ornament : "", ornaments: root.ornamentsUrl
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
        names: root.styleNames.filter(function (n) { return n.indexOf("TRY") !== 0 })
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
