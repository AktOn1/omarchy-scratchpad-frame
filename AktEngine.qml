// AktOn1 layer engine, shared by the AktOn1 plugins. Keeps one plugin's scratchpads ("pads") or its Fullscreen
// layer ("layer"), registers their keys inside Hyprland (akt.lua, runtime only, bindings.lua is never written),
// starts their apps and publishes a snapshot that the plugin's cards (AktCardSet.qml) read.
//
// Each plugin creates one engine:  AktEngine { name: "scratchpad-frame"; label: "Scratchpad Frame"; scope: "pads" }
// IPC (target "<name>.layers"): state | padAdd <label> [direction] | padRemove <id>
//   padSet <id> <label|key|moveKey|direction|outDirection|effect|outEffect|style|keepMine|fit|layout> <value>
//     (the Fullscreen layer takes label, key, direction, outDirection, effect, outEffect, layout; outDirection and outEffect "same" = as coming in)
//   appAdd <id> <command> | appRemove <id> <index> | appSearch <words> | appsStart <id> | appsRestart <id>
//   magnet <id|none|off> | toggle <id> | refresh

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "AktKit.js" as Model

Scope {
  id: root

  required property string name
  required property string label
  required property string scope
  property var styles: []
  property string sharedStyle: ""
  // The Fullscreen plugin's options when this engine lives inside it (read over IPC otherwise).
  property var ownFullscreen: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/" + name
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/" + name
  readonly property string luaFile: Qt.resolvedUrl("akt.lua").toString().replace(/^file:\/\//, "")
  readonly property string luaName: Model.luaGlobal(name)
  readonly property string bindPrefix: "AktOn1 " + label + ":"

  property bool ready: false
  property bool loaded: false
  property var state: Model.defaultState(scope)
  property var detected: ({ pads: {}, fullscreen: "" })
  property var binds: []
  property var anim: ({})
  property var fullscreen: ({ on: false, magnet: "", muteOnHide: false })
  property string message: ""
  property bool startupDone: false
  property var clients: []
  property var owned: ({})
  property var tracking: ({})
  property var restarting: ({})
  property bool ownedLoaded: false
  property bool ownedMissing: false
  property bool adoptPending: false

  readonly property bool layerHasApps: scope === "layer" && state.layer.apps.length > 0

  // The Fullscreen layer has a name, apps and a layout only while it is combined into the Scratchpad window; on its own it starts no apps and leaves the layout alone.
  property var combine: ({ members: {} })
  readonly property bool appsAllowed: scope !== "layer" || Model.PLUGINS.some(p => p.engine === name && combine.members[p.id] !== undefined)
  onAppsAllowedChanged: if (loaded && scope === "layer") runLua()
  FileView {
    path: root.home + "/.local/state/akton1/combine.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      root.combine = Model.cleanCombine(raw)
    }
    onLoadFailed: root.combine = ({ members: {} })
  }

  function say(text) {
    message = text
    messageTimer.restart()
    publish()
  }
  Timer { id: messageTimer; interval: 9000; onTriggered: { root.message = ""; root.publish() } }

  // ---- files ------------------------------------------------------------------

  Process {
    id: init
    command: ["mkdir", "-p", root.stateDir, root.runtimeDir]
    onExited: root.ready = true
  }

  FileView {
    id: stateFile
    path: root.ready ? root.stateDir + "/layers.json" : ""
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      let raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      const next = Model.cleanState(root.scope, raw)
      if (JSON.stringify(next) !== JSON.stringify(root.state) || !root.startupDone) {
        root.state = next
        root.scheduleApply()
      }
      root.loaded = true
    }
    onLoadFailed: hubFile.path = root.home + "/.local/state/akton1-hub/state.json"
  }

  // First start without a file of our own: take over what the AktOn1 Plugin Hub kept (read only, the Hub's file stays).
  FileView {
    id: hubFile
    path: ""
    onLoaded: {
      let raw = null
      try { raw = JSON.parse(text()) } catch (e) { raw = null }
      root.state = Model.fromHubState(root.scope, raw) || Model.defaultState(root.scope)
      root.saveState()
      root.scheduleApply()
      root.loaded = true
    }
    onLoadFailed: { root.state = Model.defaultState(root.scope); root.saveState(); root.scheduleApply(); root.loaded = true }
  }

  FileView {
    id: bindingsFile
    path: root.home + "/.config/hypr/bindings.lua"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { root.detected = Model.detectBindings(text()); root.scheduleApply() }
    onLoadFailed: root.detected = ({ pads: {}, fullscreen: "" })
  }

  FileView {
    id: ownedFile
    path: root.ready ? root.runtimeDir + "/owned.json" : ""
    atomicWrites: true
    onLoaded: {
      let raw = {}
      try { raw = JSON.parse(text()) } catch (e) { raw = {} }
      const clean = {}
      for (const id in raw) if (Array.isArray(raw[id])) clean[id] = raw[id].filter(a => /^0x[0-9a-f]+$/.test(a))
      root.owned = clean
      root.ownedLoaded = true
      root.refreshClients()
    }
    onLoadFailed: { root.ownedMissing = true; root.ownedLoaded = true }
  }

  FileView {
    id: snapshotFile
    path: root.ready ? root.runtimeDir + "/snapshot.json" : ""
    atomicWrites: true
  }

  function saveState() {
    stateFile.setText(JSON.stringify(state, null, 2) + "\n")
  }

  function publish() { publishTimer.restart() }
  Timer {
    id: publishTimer
    interval: 60
    onTriggered: if (root.ready) snapshotFile.setText(JSON.stringify(root.snapshot()) + "\n")
  }

  function snapshot() {
    const running = {}
    for (const id in owned) running[id] = owned[id].length
    return { scope: scope, state: state, detected: detected, styles: styles, sharedStyle: sharedStyle, message: message,
             running: running, fullscreen: fullscreen }
  }
  onStylesChanged: publish()
  onSharedStyleChanged: publish()
  onFullscreenChanged: publish()

  // ---- reading the desktop ------------------------------------------------------

  Process {
    id: bindsProc
    command: ["hyprctl", "-j", "binds"]
    stdout: StdioCollector { id: bindsOut }
    onExited: (code) => {
      if (code !== 0) return
      try { root.binds = JSON.parse(bindsOut.text) } catch (e) {}
    }
  }
  function refreshBinds() { bindsProc.running = false; bindsProc.running = true }

  // Where fullscreen games go: the Fullscreen plugin's own options. Asked over IPC (an unreachable plugin answers with no JSON).
  function setFullscreen(opts) {
    const next = { on: opts !== null, magnet: opts ? Model.magnetOf(opts) : "", muteOnHide: !!(opts && opts.muteOnHide === true) }
    if (JSON.stringify(next) !== JSON.stringify(fullscreen)) fullscreen = next
  }
  onOwnFullscreenChanged: if (ownFullscreen) setFullscreen(ownFullscreen)

  Process {
    id: fsProc
    command: ["omarchy-shell", "fullscreen-app-auto-workspace", "state"]
    stdout: StdioCollector { id: fsOut }
    onExited: (code) => {
      let opts = null
      try { opts = JSON.parse(fsOut.text) } catch (e) { opts = null }
      root.setFullscreen(opts && typeof opts === "object" ? opts : null)
    }
  }
  function refreshFullscreen() {
    if (ownFullscreen) { setFullscreen(ownFullscreen); return }
    fsProc.running = false
    fsProc.running = true
  }
  Timer { id: fsLater; interval: 500; onTriggered: root.refreshFullscreen() }

  // ---- which windows belong to a layer's apps -------------------------------------
  // Apps the engine starts are remembered by window address (for this Hyprland session), so Restart
  // closes only those and never a window you put on the scratchpad yourself or a game.

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector { id: clientsOut }
    onExited: (code) => {
      if (code !== 0) return
      let list = []
      try { list = JSON.parse(clientsOut.text) } catch (e) { return }
      root.clients = list.filter(c => c && c.workspace && typeof c.address === "string")
      root.onClients()
    }
  }
  function refreshClients() { clientsProc.running = false; clientsProc.running = true }
  Timer { id: clientsDebounce; interval: 350; onTriggered: root.refreshClients() }
  Timer { id: restartWatch; interval: 1000; repeat: true; running: Object.keys(root.restarting).length > 0; onTriggered: root.refreshClients() }

  // Games are never "the layer's apps": the Fullscreen layer holds them and Restart must not close one.
  function isGame(c) {
    return /\.exe$|^steam_app_|^gamescope$/.test(c.class || "") || (c.tags || []).some(t => String(t).replace(/\*$/, "") === "game")
  }
  function onPad(id) { return root.clients.filter(c => c.workspace.name === "special:" + id && !isGame(c)) }

  function onClients() {
    const now = Date.now()
    const next = {}
    let changed = false
    for (const layer of Model.layersOf(state)) {
      const here = onPad(layer.id).map(c => c.address)
      let mine = (owned[layer.id] || []).filter(a => here.indexOf(a) >= 0)
      const t = tracking[layer.id]
      if (t && now < t.until) {
        for (const a of here) if (t.before.indexOf(a) < 0 && mine.indexOf(a) < 0) mine.push(a)
      } else if (t) {
        delete tracking[layer.id]
      }
      if (adoptPending && layer.apps.length > 0 && layer.id !== Model.FULLSCREEN_ID) mine = here.slice()
      next[layer.id] = mine
      if (JSON.stringify(mine) !== JSON.stringify(owned[layer.id] || [])) changed = true
    }
    adoptPending = false
    if (changed || Object.keys(owned).length !== Object.keys(next).length) {
      owned = next
      ownedFile.setText(JSON.stringify(next) + "\n")
      publish()
    }
    for (const id in restarting) {
      if ((owned[id] || []).length === 0 || now > restarting[id]) {
        delete restarting[id]
        restarting = Object.assign({}, restarting)
        launchApps(id)
      }
    }
  }

  function desktopEntries() {
    return (DesktopEntries.applications.values || []).map(Model.entryInfo)
  }

  function launchApps(id) {
    const layer = Model.findLayer(state, id)
    if (!layer || layer.apps.length === 0 || !appsAllowed) return
    const entries = desktopEntries()
    tracking[id] = { until: Date.now() + 30000, before: clients.map(c => c.address) }
    launchChecks = Object.assign({}, launchChecks, { [id]: true })
    launchCheckTimer.restart()
    let code = ""
    for (const app of layer.apps)
      code += luaName + ".launch(" + Model.luaValue(id) + ", " + Model.luaValue(Model.startupCommand(Model.resolveApp(app, entries))) + "); "
    Quickshell.execDetached(["hyprctl", "eval", code])
    clientsDebounce.restart()
  }

  // A launch that opens no window (wrong command, app not installed, a terminal app started without a terminal) says so.
  property var launchChecks: ({})
  Timer {
    id: launchCheckTimer
    interval: 12000
    onTriggered: {
      const missed = []
      for (const id in root.launchChecks) {
        const layer = Model.findLayer(root.state, id)
        const opened = (root.owned[id] || []).length
        if (layer && opened < layer.apps.length) missed.push(layer.label + " (" + opened + " of " + layer.apps.length + " opened)")
      }
      root.launchChecks = ({})
      if (missed.length > 0) root.say("Some apps did not open: " + missed.join(", ") + ". Remove the app and add it again from the search list.")
    }
  }

  function startApps(id, restart) {
    const layer = Model.findLayer(state, id)
    if (!layer) return "error: no scratchpad '" + id + "'"
    if (layer.apps.length === 0) return "error: " + layer.label + " has no apps listed"
    const mine = owned[id] || []
    if (mine.length > 0 && !restart) return "error: " + layer.label + " apps are already running (use restart)"
    if (restart && mine.length > 0) {
      let code = ""
      for (const a of mine) code += luaName + ".close(" + Model.luaValue(a) + "); "
      Quickshell.execDetached(["hyprctl", "eval", code])
      restarting = Object.assign({}, restarting, { [id]: Date.now() + 6000 })
      return "ok"
    }
    launchApps(id)
    return "ok"
  }

  // ---- applying -----------------------------------------------------------------

  function scheduleApply() { applyTimer.restart() }
  Timer { id: applyTimer; interval: 200; onTriggered: root.apply() }

  function apply() {
    if (!ready) return
    animProc.running = false
    animProc.running = true
  }

  Process {
    id: animProc
    command: ["hyprctl", "-j", "animations"]
    stdout: StdioCollector { id: animOut }
    onExited: (code) => {
      if (code !== 0) { console.warn(root.name + ": could not read Hyprland animations (exit " + code + ")"); return }
      try { root.anim = Model.animSpec(JSON.parse(animOut.text)) } catch (e) { root.anim = ({}) }
      root.runLua()
    }
  }

  function runLua() {
    const cfg = Model.luaConfig(state, anim, detected, label, appsAllowed)
    luaProc.command = ["hyprctl", "eval", Model.luaStart(luaFile, name, cfg)]
    luaProc.running = false
    luaProc.running = true
  }

  Process {
    id: luaProc
    stdout: StdioCollector { id: luaOut }
    stderr: StdioCollector { id: luaErr }
    onExited: (code) => {
      if (code !== 0) {
        console.warn(root.name + ": could not load akt.lua into Hyprland (exit " + code + "). Needs hyprctl and a Hyprland with Lua config support. "
                     + (luaErr.text || luaOut.text).trim())
        root.say("Could not register the keys (see journalctl --user)")
        return
      }
      root.afterLua()
    }
  }

  function afterLua() {
    refreshBinds()
    refreshFullscreen()
    if (!startupDone) { startupDone = true; startupProc.running = true }
    publish()
  }

  // Apps listed for a layer start once per Hyprland session, on that layer, hidden. The AktOn1 Plugin Hub's marker counts too.
  Process {
    id: startupProc
    command: ["sh", "-c", "sig=\"${HYPRLAND_INSTANCE_SIGNATURE:-none}\"; m=\"$1/started-$sig\"; if [ -e \"$m\" ] || [ -e \"$2/akton1-hub/started-$sig\" ]; then echo skip; else : > \"$m\"; echo launch; fi",
              "sh", root.runtimeDir, Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"]
    stdout: StdioCollector { id: startupOut }
    onExited: {
      if (startupOut.text.trim() === "launch") root.launchStartupApps()
      else if (root.ownedMissing) { root.adoptPending = true; root.refreshClients() }
    }
  }

  function launchStartupApps() {
    for (const layer of Model.layersOf(state)) launchApps(layer.id)
  }

  // ---- changing settings -------------------------------------------------------------

  function clone(v) { return JSON.parse(JSON.stringify(v)) }

  // fn edits the copy it is given and returns "" or an error text; on success the new state is saved and applied.
  function mutate(fn) {
    const draft = clone(state)
    const err = fn(draft)
    if (err) return "error: " + err
    const next = Model.cleanState(scope, draft)
    state = next
    saveState()
    scheduleApply()
    publish()
    return "ok"
  }

  function keyOwner(key, draft, exceptPad, exceptField) {
    for (const p of Model.layersOf(draft)) {
      if (p.key === key && !(p.id === exceptPad && exceptField === "key")) return p.label + " (" + root.label + ")"
      if (!p.builtin && p.moveKey === key && !(p.id === exceptPad && exceptField === "moveKey")) return "Move to " + p.label + " (" + root.label + ")"
    }
    return ""
  }

  function checkKey(raw, draft, exceptPad, exceptField, currentOwnKey) {
    const key = Model.normalizeKey(raw)
    if (key === "") return { error: "'" + raw + "' is not a key (example: SUPER + SHIFT + F9)" }
    if (!Model.keyUsable(key)) return { error: key + " would swallow normal typing; add SUPER, CTRL or ALT" }
    if (key === currentOwnKey) return { key: key }
    const own = keyOwner(key, draft, exceptPad, exceptField)
    if (own !== "") return { error: key + " is already used by " + own }
    const other = Model.findConflict(key, binds, bindPrefix)
    if (other !== "") return { error: key + " is already used by: " + other }
    return { key: key }
  }

  function setKey(draft, pad, field, raw) {
    if (raw === "" || raw === "none") {
      if (field === "key" && pad.builtin) pad.key = Model.DEFAULT_KEY
      else pad[field] = ""
      return ""
    }
    if (pad.builtin && field === "key" && raw === "default") { pad.key = Model.DEFAULT_KEY; return "" }
    const res = checkKey(raw, draft, pad.id, field, pad[field])
    if (res.error) return res.error
    pad[field] = res.key
    return ""
  }

  function padAdd(label, direction) {
    if (scope !== "pads") return "error: this plugin has no scratchpads"
    let newId = ""
    const res = mutate(d => {
      if (d.pads.length >= 12) return "twelve scratchpads is the limit"
      const taken = d.pads.map(p => p.id)
      newId = Model.slug(label, taken)
      d.pads.push({ id: newId, label: label !== "" ? label : "Pad " + d.pads.length, key: "", moveKey: "",
                    direction: Model.cleanSide(direction) || "bottom", outDirection: "", effect: "", outEffect: "",
                    style: "", keepMine: false, fit: false, apps: [] })
      return ""
    })
    return res === "ok" ? newId : res
  }

  function padRemove(id) {
    let wasMagnet = false
    const res = mutate(d => {
      if (scope !== "pads") return "this plugin has no scratchpads"
      const i = d.pads.findIndex(p => p.id === id)
      if (i < 0) return "no scratchpad '" + id + "'"
      if (d.pads[i].builtin) return "the original scratchpad stays"
      d.pads.splice(i, 1)
      return ""
    })
    // a removed pad can no longer be where fullscreen games go
    if (res === "ok" && fullscreen.magnet === id) setMagnet("none")
    return res
  }

  function padSet(id, field, value) {
    return mutate(d => {
      const pad = Model.findLayer(d, id)
      if (!pad) return "no scratchpad '" + id + "'"
      if (field === "layout") {
        const v = value.trim().toLowerCase()
        if (v === "" || v === "default" || v === "none") { pad.layout = ""; return "" }
        if (Model.cleanLayout(v) !== v) return "layout is default, dwindle, master, scrolling, monocle or lua:<name>"
        pad.layout = v
        return ""
      }
      if (field === "label") {
        if (value.trim() === "") return "give a name"
        pad.label = value
        return ""
      }
      if (field === "key" || field === "moveKey") {
        if (field === "moveKey" && (pad.builtin || pad.layer)) return "the " + (pad.layer ? "Fullscreen layer" : "original scratchpad") + " has no move key of its own here"
        return setKey(d, pad, field, value)
      }
      if (field === "direction") {
        if (Model.cleanSide(value) === "") return "direction is " + Model.DIRECTIONS.join(", ")
        pad.direction = Model.cleanSide(value)
        return ""
      }
      if (field === "outDirection") {
        const v = value === "same" || value === "default" ? "" : value
        if (v !== "" && Model.cleanSide(v) === "") return "outDirection is same, " + Model.DIRECTIONS.join(", ")
        pad.outDirection = Model.cleanSide(v)
        return ""
      }
      if (field === "effect" || field === "outEffect") {
        const v = value === "same" || value === "default" ? "" : value
        if (v !== "" && Model.cleanEffect(v) === "") return field + " is same, " + Model.EFFECTS.map(e => e.id).join(", ")
        pad[field] = v
        return ""
      }
      if (pad.layer) return "the Fullscreen layer has a name, a key, how it moves in and out, a layout and apps"
      if (field === "style") { pad.style = value === "default" || value === "none" ? "" : value; return "" }
      if (field === "keepMine") { pad.keepMine = value === "true" || value === "on" || value === "1"; return "" }
      if (field === "fit") { pad.fit = value === "true" || value === "on" || value === "1"; return "" }
      return "unknown field '" + field + "' (label, key, moveKey, direction, outDirection, effect, outEffect, style, keepMine, fit, layout)"
    })
  }

  function appAdd(id, command) {
    return mutate(d => {
      const pad = Model.findLayer(d, id)
      if (!pad) return "no scratchpad '" + id + "'"
      const cmd = command.trim()
      if (cmd === "") return "give a command"
      const wanted = Model.appId(cmd)
      if (wanted !== "" && !desktopEntries().some(e => e.id === wanted)) return "no installed app '" + wanted + "' (omarchy-shell " + root.name + ".layers appSearch <name>)"
      pad.apps.push(cmd)
      return ""
    })
  }

  function appRemove(id, index) {
    return mutate(d => {
      const pad = Model.findLayer(d, id)
      const i = parseInt(index)
      if (!pad) return "no scratchpad '" + id + "'"
      if (!(i >= 0 && i < pad.apps.length)) return "no app " + index
      pad.apps.splice(i, 1)
      return ""
    })
  }

  // magnet <id|none|off>: where fullscreen games land. Held by the Fullscreen plugin (its layer and autoMove options).
  function setMagnet(id) {
    if (!fullscreen.on) return "error: Fullscreen App Auto Workspace is not installed"
    if (id !== "off" && id !== "none" && id !== "" && id !== Model.FULLSCREEN_ID && !Model.findLayer(state, id)) {
      // a pad of the other plugin is fine too: the id is only a special workspace name
      if (!/^[a-z0-9_-]{1,24}$/.test(id)) return "error: no scratchpad '" + id + "'"
    }
    const o = Model.magnetOptions(id === "none" ? "" : id)
    Quickshell.execDetached(["sh", "-c", "omarchy-shell fullscreen-app-auto-workspace option layer \"$1\"; omarchy-shell fullscreen-app-auto-workspace option autoMove \"$2\"", "sh", o.layer, o.autoMove])
    fsLater.restart()
    const next = Object.assign({}, fullscreen, { magnet: id === "none" || id === Model.FULLSCREEN_ID ? "" : id })
    fullscreen = next
    return "ok"
  }

  function setMuteOnHide(on) {
    Quickshell.execDetached(["omarchy-shell", "fullscreen-app-auto-workspace", "option", "muteOnHide", on ? "true" : "unset"])
    fullscreen = Object.assign({}, fullscreen, { muteOnHide: on })
    fsLater.restart()
    return "ok"
  }

  function toggle(id) {
    const pad = Model.findLayer(state, id)
    if (!pad) return "error: no scratchpad '" + id + "'"
    if (pad.layer) {
      Quickshell.execDetached(["omarchy-shell", "fullscreen-app-auto-workspace", "toggle"])
      return "ok"
    }
    Quickshell.execDetached(["hyprctl", "eval", luaName + ".toggle(" + Model.luaValue(id) + ", " + Model.luaValue(pad.direction) + ")"])
    return "ok"
  }

  IpcHandler {
    target: root.name + ".layers"
    function state(): string { return JSON.stringify(root.snapshot()) }
    function padAdd(label: string, direction: string): string { return root.padAdd(label, direction) }
    function padRemove(id: string): string { return root.padRemove(id) }
    function padSet(id: string, field: string, value: string): string { return root.padSet(id, field, value) }
    function appAdd(id: string, command: string): string { return root.appAdd(id, command) }
    function appRemove(id: string, index: string): string { return root.appRemove(id, index) }
    function appSearch(words: string): string { return JSON.stringify(Model.matchApps(root.desktopEntries(), words)) }
    function magnet(id: string): string { return root.setMagnet(id) }
    function muteOnHide(value: string): string { return root.setMuteOnHide(value === "on" || value === "true") }
    function toggle(id: string): string { return root.toggle(id) }
    function appsStart(id: string): string { return root.startApps(id, false) }
    function appsRestart(id: string): string { return root.startApps(id, true) }
    function refresh(): string { root.refreshBinds(); root.refreshFullscreen(); bindingsFile.reload(); root.scheduleApply(); return "ok" }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") {
        root.refreshBinds()
        bindingsFile.reload()
        root.scheduleApply()
      } else if (event.name === "openwindow" || event.name === "closewindow" || event.name.indexOf("movewindow") === 0) {
        clientsDebounce.restart()
      }
    }
  }

  Component.onCompleted: {
    init.running = true
    refreshBinds()
  }

  Component.onDestruction: {
    Quickshell.execDetached(["rm", "-f", runtimeDir + "/snapshot.json"])
    Quickshell.execDetached(["hyprctl", "eval", "if " + luaName + " then " + luaName + ".shutdown(); " + luaName + " = nil end"])
  }
}
