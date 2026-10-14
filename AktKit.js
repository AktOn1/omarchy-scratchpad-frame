.pragma library

// Pure helpers shared by the AktOn1 plugins (Scratchpad Frame, Fullscreen App Auto Workspace): no Quickshell
// types, so the same file runs under plain node for the tests. The source of truth is the kit folder; every
// plugin carries a copy (tools/sync-kit.sh).

var DEFAULT_KEY = "SUPER + S"
var DEFAULT_MOVE_KEY = "SUPER + ALT + S"
// Hyprland slides a special workspace only from the bottom (vertical) or from the right (horizontal);
// an older "top" or "left" counts as the nearest of those.
var DIRECTIONS = ["bottom", "right"]
var LEGACY_DIRECTIONS = { top: "bottom", left: "right" }

// How a pad appears and disappears. "slide" is Omarchy's own special workspace animation (its speed and curve);
// the others bring their own. style is a Hyprland workspace animation style ("slide" and "slidefade" become their
// vertical variants for the bottom side), "none" switches the animation off. speed is in Hyprland units
// (1 = 100 ms), curve is the cubic bezier x1 y1 x2 y2 (a y above 1 overshoots), sides tells whether the side matters.
var EFFECTS = [
  { id: "slide", label: "Slide", style: "slide", sides: true },
  { id: "bounce", label: "Bounce", style: "slide", sides: true, speed: 5, curve: [0.34, 1.56, 0.64, 1] },
  { id: "springy", label: "Springy", style: "slide", sides: true, speed: 7, curve: [0.2, 2.2, 0.4, 1] },
  { id: "whoosh", label: "Whoosh", style: "slide", sides: true, speed: 2, curve: [0.16, 1, 0.3, 1] },
  { id: "glide", label: "Slow glide", style: "slide", sides: true, speed: 7, curve: [0.65, 0.05, 0.36, 1] },
  { id: "slidefade", label: "Slide and fade", style: "slidefade", sides: true, speed: 4, curve: [0.23, 1, 0.32, 1] },
  { id: "fade", label: "Fade", style: "fade", sides: false, speed: 4, curve: [0.25, 0.1, 0.25, 1] },
  { id: "instant", label: "Instant", style: "none", sides: false, speed: 0 }
]
var DEFAULT_EFFECT = "slide"

function effectInfo(id) {
  for (var i = 0; i < EFFECTS.length; i++) if (EFFECTS[i].id === id) return EFFECTS[i]
  return EFFECTS[0]
}

function cleanEffect(v) {
  for (var i = 0; i < EFFECTS.length; i++) if (EFFECTS[i].id === v) return v
  return ""
}

function cleanSide(v) {
  if (LEGACY_DIRECTIONS[v]) return LEGACY_DIRECTIONS[v]
  return DIRECTIONS.indexOf(v) >= 0 ? v : ""
}

// What a pad does when it comes in and when it goes out ("" = the same as coming in).
function motionOf(pad) {
  var inEffect = cleanEffect(pad.effect) || DEFAULT_EFFECT
  var inSide = cleanSide(pad.direction) || "bottom"
  return { inEffect: inEffect, inSide: inSide,
           outEffect: cleanEffect(pad.outEffect) || inEffect,
           outSide: cleanSide(pad.outDirection) || inSide }
}

function stepText(effect, side) {
  var fx = effectInfo(effect)
  return fx.label.toLowerCase() + (fx.sides ? " " + (side === "right" ? "from the right" : "from the bottom") : "")
}

// "slide from the bottom" or, when it goes out another way, "bounce from the right, out: fade".
function motionText(pad) {
  var m = motionOf(pad)
  var inText = stepText(m.inEffect, m.inSide)
  var out = stepText(m.outEffect, m.outSide)
  if (out === inText) return inText
  var outInfo = effectInfo(m.outEffect)
  return inText + ", out: " + (outInfo.sides ? outInfo.label.toLowerCase() + " " + (m.outSide === "right" ? "to the right" : "to the bottom") : outInfo.label.toLowerCase())
}

// True when the pad moves differently from Omarchy's own scratchpad (so SUPER + S must be taken over to carry it out).
function ownMotion(pad) {
  var m = motionOf(pad)
  return m.inSide !== "bottom" || m.outSide !== "bottom" || m.inEffect !== DEFAULT_EFFECT || m.outEffect !== DEFAULT_EFFECT
}
var FULLSCREEN_ID = "fullscreen"
var SCOPES = ["pads", "layer"]
var LAYOUTS = [
  { value: "", label: "Default" },
  { value: "dwindle", label: "Dwindle" },
  { value: "master", label: "Master" },
  { value: "scrolling", label: "Scrolling" },
  { value: "monocle", label: "Monocle" }
]

// The AktOn1 plugins that can be combined. A plugin can host the others' cards when it ships AktCards.qml.
var PLUGINS = [
  { id: "io.github.akton1.scratchpad-frame", engine: "scratchpad-frame", scope: "pads", name: "Scratchpad Frame", short: "Scratchpads", blurb: "slide-in scratchpads with a frame around them",
    repo: "https://github.com/AktOn1/omarchy-scratchpad-frame.git" },
  { id: "io.github.akton1.fullscreen-app-auto-workspace", engine: "fullscreen-app-auto-workspace", scope: "layer", name: "Fullscreen App Auto Workspace", short: "Fullscreen", blurb: "fullscreen games get their own workspace",
    repo: "https://github.com/AktOn1/omarchy-fullscreen-app-auto-workspace.git" }
]

function pluginInfo(id) {
  for (var i = 0; i < PLUGINS.length; i++) if (PLUGINS[i].id === id) return PLUGINS[i]
  return null
}

// What a user pastes in a terminal to get a plugin.
function installCommand(id) {
  var info = pluginInfo(id)
  return info ? "omarchy plugin add " + info.repo + " --enable" : ""
}

// ---- layer state -------------------------------------------------------------

function builtinPad() {
  return { id: "scratchpad", label: "Scratchpad", builtin: true, key: DEFAULT_KEY, moveKey: DEFAULT_MOVE_KEY,
           direction: "bottom", outDirection: "", effect: "", outEffect: "", style: "", keepMine: false, fit: false, layout: "", apps: [] }
}

function fullscreenLayer() {
  return { id: FULLSCREEN_ID, label: "Fullscreen", layer: true, key: "", direction: "bottom", outDirection: "", effect: "", outEffect: "", layout: "", apps: [] }
}

function defaultState(scope) {
  return scope === "layer" ? { version: 2, layer: fullscreenLayer() } : { version: 2, pads: [builtinPad()] }
}

function cleanText(v, max) {
  return String(v === undefined || v === null ? "" : v).replace(/[\r\n\t]+/g, " ").trim().slice(0, max)
}

function slug(label, taken) {
  var base = cleanText(label, 24).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  if (base === "") base = "pad"
  var id = base
  var n = 2
  while (taken.indexOf(id) >= 0 || id === FULLSCREEN_ID) id = base + "-" + (n++)
  return id
}

// "dwindle", "master", "lua:name": what Hyprland accepts as a workspace layout; anything else is "default".
function cleanLayout(v) {
  var t = cleanText(v, 40)
  return /^[a-z][a-z0-9_-]*(:[A-Za-z0-9_.-]+)?$/.test(t) ? t : ""
}

function cleanApps(list) {
  var apps = []
  if (Array.isArray(list)) {
    for (var i = 0; i < list.length && apps.length < 20; i++) {
      var c = cleanText(list[i], 400)
      if (c !== "") apps.push(c)
    }
  }
  return apps
}

function cleanLayer(raw) {
  var l = fullscreenLayer()
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    l.label = cleanText(raw.label, 24) || l.label
    l.key = normalizeKey(raw.key)
    if (cleanSide(raw.direction)) l.direction = cleanSide(raw.direction)
    l.outDirection = cleanSide(raw.outDirection)
    l.effect = cleanEffect(raw.effect)
    l.outEffect = cleanEffect(raw.outEffect)
    l.layout = cleanLayout(raw.layout)
    l.apps = cleanApps(raw.apps)
  }
  return l
}

function cleanPad(p, taken) {
  if (!p || typeof p !== "object") return null
  var builtin = p.id === "scratchpad"
  var id = builtin ? "scratchpad" : String(p.id || "")
  if (!builtin && (!/^[a-z0-9][a-z0-9-]{0,23}$/.test(id) || id === FULLSCREEN_ID)) id = slug(p.label || id, taken)
  if (taken.indexOf(id) >= 0) return null
  return {
    id: id,
    label: cleanText(p.label, 24) || (builtin ? "Scratchpad" : id),
    builtin: builtin,
    key: p.key === undefined && builtin ? DEFAULT_KEY : normalizeKey(p.key),
    moveKey: builtin ? DEFAULT_MOVE_KEY : normalizeKey(p.moveKey),
    direction: cleanSide(p.direction) || "bottom",
    outDirection: cleanSide(p.outDirection),
    effect: cleanEffect(p.effect),
    outEffect: cleanEffect(p.outEffect),
    style: cleanText(p.style, 40),
    keepMine: p.keepMine === true,
    fit: p.fit === true,
    layout: cleanLayout(p.layout),
    apps: cleanApps(p.apps)
  }
}

// Accepts whatever was on disk (or typed) and returns a complete, valid state for the scope.
function cleanState(scope, raw) {
  var s = defaultState(scope)
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return s
  if (scope === "layer") { s.layer = cleanLayer(raw.layer); return s }
  var pads = []
  var taken = []
  if (Array.isArray(raw.pads)) {
    for (var i = 0; i < raw.pads.length && pads.length < 12; i++) {
      var pad = cleanPad(raw.pads[i], taken)
      if (pad) { pads.push(pad); taken.push(pad.id) }
    }
  }
  if (taken.indexOf("scratchpad") < 0) pads.unshift(builtinPad())
  else pads.sort(function (a, b) { return (b.builtin ? 1 : 0) - (a.builtin ? 1 : 0) })
  s.pads = pads
  return s
}

// The state the AktOn1 Plugin Hub 0.3.0 kept (~/.local/state/akton1-hub/state.json), as the state of one scope.
function fromHubState(scope, raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null
  if (scope === "layer") {
    var l = raw.fullscreen && typeof raw.fullscreen === "object" ? raw.fullscreen : {}
    return cleanState("layer", { layer: { label: l.label, layout: l.layout, apps: l.apps, key: raw.fullscreenKey } })
  }
  return Array.isArray(raw.pads) ? cleanState("pads", { pads: raw.pads }) : null
}

function layersOf(state) {
  return state.pads ? state.pads : [state.layer]
}

function findLayer(state, id) {
  var list = layersOf(state)
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
  return null
}

// Layouts to offer: the stock ones, plus any custom one in use (a Lua layout, or one found on a workspace).
function layoutOptions(inUse) {
  var out = LAYOUTS.slice()
  var seen = {}
  for (var i = 0; i < out.length; i++) seen[out[i].value] = true
  for (var j = 0; j < (inUse || []).length; j++) {
    var v = cleanLayout(inUse[j])
    if (v !== "" && !seen[v]) { seen[v] = true; out.push({ value: v, label: v.replace(/^lua:/, "") + (v.indexOf("lua:") === 0 ? " (Lua)" : "") }) }
  }
  return out
}

// ---- fullscreen magnet (which layer fullscreen games land in) ------------------
// Held by the Fullscreen plugin as its options: layer (the special workspace) and autoMove.
// "" = the Fullscreen layer, "off" = nowhere, otherwise a scratchpad id.

function magnetOf(fsState) {
  var s = fsState || {}
  if (s.autoMove === false) return "off"
  return s.layer && s.layer !== FULLSCREEN_ID ? s.layer : ""
}

// The options that make `target` ("" = the layer, "off", or a pad id) the magnet.
function magnetOptions(target) {
  if (target === "off") return { layer: "unset", autoMove: "false" }
  if (target === "" || target === FULLSCREEN_ID) return { layer: "unset", autoMove: "unset" }
  return { layer: target, autoMove: "unset" }
}

// ---- keys -------------------------------------------------------------------

var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MOD_BITS = { SHIFT: 1, CAPS: 2, CTRL: 4, ALT: 8, SUPER: 64 }
var MOD_ALIAS = { SUPER: "SUPER", META: "SUPER", WIN: "SUPER", MOD4: "SUPER", CTRL: "CTRL", CONTROL: "CTRL",
                  ALT: "ALT", MOD1: "ALT", SHIFT: "SHIFT" }

// "super+shift+f9" -> "SUPER + SHIFT + F9"; "" when it is not a usable key.
function normalizeKey(text) {
  if (text === undefined || text === null) return ""
  var parts = String(text).split(/\s*\+\s*/)
  var mods = {}
  var key = ""
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim().toUpperCase()
    if (p === "") continue
    if (MOD_ALIAS[p] && i < parts.length - 1) mods[MOD_ALIAS[p]] = true
    else if (key === "") key = p
    else return ""
  }
  if (key === "" || !/^[A-Z0-9_]{1,24}$/.test(key)) return ""
  var out = []
  for (var m = 0; m < MOD_ORDER.length; m++) if (mods[MOD_ORDER[m]]) out.push(MOD_ORDER[m])
  out.push(key)
  return out.join(" + ")
}

function keyParts(text) {
  var n = normalizeKey(text)
  if (n === "") return null
  var parts = n.split(" + ")
  var key = parts.pop()
  var mask = 0
  for (var i = 0; i < parts.length; i++) mask |= MOD_BITS[parts[i]]
  return { mask: mask, key: key }
}

var QT_NAMES = {
  0x20: "SPACE", 0x01000000: "ESCAPE", 0x01000001: "TAB", 0x01000004: "RETURN", 0x01000005: "RETURN",
  0x01000003: "BACKSPACE", 0x01000007: "DELETE", 0x01000006: "INSERT", 0x01000010: "HOME", 0x01000011: "END",
  0x01000016: "PRIOR", 0x01000017: "NEXT", 0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT",
  0x01000015: "DOWN", 0x2c: "COMMA", 0x2e: "PERIOD", 0x2f: "SLASH", 0x3b: "SEMICOLON", 0x27: "APOSTROPHE",
  0x5b: "BRACKETLEFT", 0x5d: "BRACKETRIGHT", 0x5c: "BACKSLASH", 0x2d: "MINUS", 0x3d: "EQUAL", 0x60: "GRAVE"
}
var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01000024, 0x01000025, 0x01001103, 0x01000026, 0x01000027]

// A Qt key press (key code + modifier flags) as a Hyprland key string, "" while only a modifier is held.
function keyFromEvent(qtKey, ctrl, alt, shift, meta) {
  if (MODIFIER_KEYS.indexOf(qtKey) >= 0) return ""
  var name = ""
  if (qtKey >= 0x01000030 && qtKey <= 0x01000047) name = "F" + (qtKey - 0x01000030 + 1)
  else if (QT_NAMES[qtKey]) name = QT_NAMES[qtKey]
  else if (qtKey >= 0x41 && qtKey <= 0x5a) name = String.fromCharCode(qtKey)
  else if (qtKey >= 0x30 && qtKey <= 0x39) name = String.fromCharCode(qtKey)
  if (name === "") return ""
  var parts = []
  if (meta) parts.push("SUPER")
  if (ctrl) parts.push("CTRL")
  if (alt) parts.push("ALT")
  if (shift) parts.push("SHIFT")
  parts.push(name)
  return normalizeKey(parts.join(" + "))
}

// A key that would swallow normal typing (no modifier) is refused.
function keyUsable(text) {
  var p = keyParts(text)
  if (!p) return false
  if (p.mask === 0 && !/^F([1-9]|1[0-9]|2[0-4])$/.test(p.key)) return false
  return true
}

// Which existing Hyprland binding already uses this key?
// `binds` is the parsed `hyprctl -j binds`; bindings whose description starts with `ownPrefix` are this engine's own and ignored.
function findConflict(text, binds, ownPrefix) {
  var want = keyParts(text)
  if (!want || !Array.isArray(binds)) return ""
  for (var i = 0; i < binds.length; i++) {
    var b = binds[i]
    if (!b || String(b.key || "").toUpperCase() !== want.key) continue
    if ((Number(b.modmask) & ~2) !== want.mask) continue
    var d = String(b.description || "")
    if (ownPrefix && d.indexOf(ownPrefix) === 0) continue
    return d !== "" ? d : (b.dispatcher || "another binding") + (b.arg ? " " + b.arg : "")
  }
  return ""
}

// ---- bindings the user wrote by hand ------------------------------------------

// Reads ~/.config/hypr/bindings.lua (text only, never written) and reports the
// keys the user already bound for a scratchpad or for the fullscreen layer.
function detectBindings(luaText) {
  var found = { pads: {}, fullscreen: "" }
  var lines = String(luaText || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*--/.test(line)) continue
    var q = /["']([^"']+)["']/.exec(line)
    if (!q) continue
    var key = normalizeKey(q[1])
    if (key === "") continue
    var m = /toggle_special\(\s*["']([a-z0-9_-]+)["']\s*\)/.exec(line) || /togglespecialworkspace[ ,]+([a-z0-9_-]+)/.exec(line)
    if (m && (line.indexOf("bind") >= 0)) found.pads[m[1]] = key
    if (/fullscreen-app-auto-workspace\s+toggle/.test(line)) found.fullscreen = key
  }
  return found
}

// ---- what the engine hands to its Lua runtime ----------------------------------

function sameKey(a, b) { return normalizeKey(a) !== "" && normalizeKey(a) === normalizeKey(b) }

// moveAnim: the window move animation is on. Then even the unchanged built-in SUPER + S is taken over, because the key
// is where the runtime switches that animation off while a pad opens on another monitor (else the windows fly in sideways).
function padNeedsBind(pad, detected, moveAnim) {
  if (pad.keepMine && detected.pads[pad.id]) return false
  if (pad.builtin) return pad.key !== "" && (moveAnim || ownMotion(pad) || !sameKey(pad.key, DEFAULT_KEY))
  return pad.key !== ""
}

function luaConfig(state, anim, detected, label, layerLayout) {
  var pads = []
  var list = state.pads || []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!padNeedsBind(p, detected, !!(anim && anim.windowsMove && anim.windowsMove.enabled))) continue
    var m = motionOf(p)
    pads.push({ id: p.id, key: p.key, moveKey: p.moveKey, direction: m.inSide, outDirection: m.outSide, effect: m.inEffect, outEffect: m.outEffect,
                label: p.label, builtin: p.builtin && sameKey(p.key, DEFAULT_KEY) })
  }
  var commands = []
  if (state.layer && state.layer.key !== "" && !(detected.fullscreen && sameKey(detected.fullscreen, state.layer.key)))
    commands.push({ key: state.layer.key, command: "omarchy-shell fullscreen-app-auto-workspace toggle", label: "toggle fullscreen layer" })
  var layouts = layersOf(state).map(function (l) { return { id: l.id, layout: l.layer && layerLayout === false ? "" : l.layout } })
  var slide = {}
  for (var k in anim || {}) if (k !== "windowsMove") slide[k] = anim[k]
  var motions = {}
  var all = layersOf(state)
  for (var q = 0; q < all.length; q++) {
    var mo = motionOf(all[q])
    motions[all[q].id] = { direction: mo.inSide, outDirection: mo.outSide, effect: mo.inEffect, outEffect: mo.outEffect }
  }
  var effects = {}
  for (var e = 0; e < EFFECTS.length; e++) {
    var fx = EFFECTS[e]
    effects[fx.id] = { style: fx.style, speed: fx.speed, curve: fx.curve }
  }
  return { label: label, pads: pads, commands: commands, anim: slide, move: (anim || {}).windowsMove, layouts: layouts, effects: effects, motions: motions }
}

function luaValue(v) {
  if (v === null || v === undefined) return "nil"
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "number") return String(v)
  if (typeof v === "string") {
    return '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r?\n/g, "\\n") + '"'
  }
  if (Array.isArray(v)) return "{" + v.map(luaValue).join(",") + "}"
  var out = []
  for (var k in v) if (v[k] !== undefined) out.push("[" + luaValue(k) + "]=" + luaValue(v[k]))
  return "{" + out.join(",") + "}"
}

// The Lua runtime keeps itself in a global named after the plugin, so two plugins never share one.
function luaGlobal(name) {
  return "__akton1_" + String(name).replace(/[^a-z0-9]+/g, "_")
}

function luaStart(luaPath, name, cfg) {
  return "local m = dofile(" + luaValue(luaPath) + ")(" + luaValue(luaGlobal(name)) + "); m.start(" + luaValue(cfg) + ")"
}

// First explicitly set value up the chain specialWorkspace > workspaces > global
// (the same rule Hyprland itself uses), for both special workspace leaves.
function animSpec(records) {
  var list = Array.isArray(records) && Array.isArray(records[0]) ? records[0] : records
  var byName = {}
  for (var i = 0; i < (list || []).length; i++) byName[list[i].name] = list[i]
  function inherited(key) {
    var chain = ["specialWorkspace", "workspaces", "global"]
    for (var c = 0; c < chain.length; c++) {
      var rec = byName[chain[c]]
      if (rec && rec.overridden && rec[key] !== "" && rec[key] !== undefined) return rec[key]
    }
    return undefined
  }
  var out = {}
  var leaves = ["specialWorkspaceIn", "specialWorkspaceOut"]
  for (var l = 0; l < leaves.length; l++) {
    var cur = byName[leaves[l]]
    var own = cur && cur.overridden
    out[leaves[l]] = {
      enabled: own ? cur.enabled !== false : inherited("enabled") !== false,
      speed: Number(own ? cur.speed : (inherited("speed") || 1)),
      bezier: (own && cur.bezier) || inherited("bezier") || "default",
      style: (own ? cur.style : inherited("style")) || ""
    }
  }
  var move = byName.windowsMove, windows = byName.windows
  var src = move && (move.overridden || !windows) ? move : windows
  if (src) out.windowsMove = { enabled: src.enabled !== false, speed: Number(src.speed), bezier: src.bezier || "default", style: src.style || "" }
  return out
}

// What Scratchpad Frame draws: one entry per pad.
function framePads(state) {
  return (state.pads || []).map(function (p) {
    var m = motionOf(p)
    return { name: p.id, label: p.label.toUpperCase(), direction: m.inSide, outDirection: m.outSide, effect: m.inEffect, outEffect: m.outEffect,
             style: p.style, fit: p.fit === true }
  })
}

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// A layer's app is either "app:<desktop id>" (picked from the installed apps) or a plain command.
function appId(app) {
  var m = /^app:(.+)$/.exec(String(app))
  return m ? m[1] : ""
}

// Picked apps go through gtk-launch, like Omarchy's own launcher, so terminal apps (cliamp, btop...) get their terminal.
function startupCommand(app) {
  var id = appId(app)
  if (id !== "") return "uwsm-app -- gtk-launch " + shellQuote(id + ".desktop")
  return "uwsm-app -- " + app
}

// Plain object from a Quickshell DesktopEntry.
function entryInfo(e) {
  return {
    id: String(e.id || ""), name: String(e.name || e.id || ""), generic: String(e.genericName || ""),
    comment: String(e.comment || ""), keywords: (e.keywords || []).map(String).join(" "),
    terminal: e.runInTerminal === true, hidden: e.noDisplay === true,
    command: (e.command || []).map(String)
  }
}

function appOptions(entries) {
  return entries.filter(function (e) { return e.id !== "" && !e.hidden })
    .sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
    .map(function (e) {
      var what = e.generic || e.comment
      return { value: "app:" + e.id, label: e.name, description: (what ? what + " - " : "") + (e.terminal ? "terminal app, " : "") + e.id }
    })
}

// Installed apps whose name, kind, id or keywords contain every word of the query (names starting with it first).
function matchApps(entries, query) {
  var words = String(query).toLowerCase().split(/\s+/).filter(function (w) { return w !== "" })
  if (words.length === 0) return []
  var hits = entries.filter(function (e) {
    if (e.id === "" || e.hidden) return false
    var hay = (e.name + " " + e.generic + " " + e.id + " " + e.keywords).toLowerCase()
    return words.every(function (w) { return hay.indexOf(w) >= 0 })
  })
  hits.sort(function (a, b) {
    var pa = a.name.toLowerCase().indexOf(words[0]) === 0 ? 0 : 1
    var pb = b.name.toLowerCase().indexOf(words[0]) === 0 ? 0 : 1
    return pa !== pb ? pa - pb : (a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1)
  })
  return hits.slice(0, 10).map(function (e) { return { app: "app:" + e.id, name: e.name, kind: e.generic, terminal: e.terminal } })
}

// A bare command that is really a terminal app (cliamp, btop) is started through its desktop entry, which opens the terminal.
function resolveApp(app, entries) {
  if (appId(app) !== "" || /\s/.test(String(app).trim())) return app
  var base = String(app).trim().split("/").pop()
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e.terminal && e.command.length === 1 && e.command[0].split("/").pop() === base) return "app:" + e.id
  }
  return app
}

function appTitle(app, entries) {
  var id = appId(app)
  if (id === "") return String(app)
  for (var i = 0; i < entries.length; i++) if (entries[i].id === id) return entries[i].name + (entries[i].terminal ? " (terminal)" : "")
  return id + " (not installed)"
}

// ---- combining plugins ---------------------------------------------------------
// combine.json holds { members: { <member plugin id>: <host plugin id> } }. A member has no window of its own:
// its cards show in the host's window, next to the host's.

function cleanCombine(raw) {
  var out = { members: {} }
  var m = raw && typeof raw === "object" && raw.members && typeof raw.members === "object" ? raw.members : {}
  for (var id in m) {
    if (pluginInfo(id) && pluginInfo(m[id]) && id !== m[id]) out.members[id] = m[id]
  }
  // no chains: a host is never a member itself
  for (var a in out.members) if (out.members[out.members[a]]) out.members[a] = out.members[out.members[a]]
  for (var b in out.members) if (out.members[b] === b) delete out.members[b]
  return out
}

function hostOf(combine, id) {
  return combine.members[id] || id
}

// Combine: `member`'s cards move into `host`'s window (and anything `member` hosted moves along).
function combineWith(combine, host, member) {
  var next = { members: {} }
  var h = hostOf(combine, host)
  for (var id in combine.members) next.members[id] = combine.members[id] === member ? h : combine.members[id]
  if (member !== h) next.members[member] = h
  return cleanCombine(next)
}

function separate(combine, member) {
  var next = { members: {} }
  for (var id in combine.members) if (id !== member) next.members[id] = combine.members[id]
  return next
}

// The plugins whose cards show in `id`'s window, `id` first (a member returns just itself: it has no window).
function groupOf(combine, id) {
  if (combine.members[id]) return [id]
  var out = [id]
  for (var m in combine.members) if (combine.members[m] === id) out.push(m)
  return out
}

if (typeof module !== "undefined") module.exports = {
  DEFAULT_KEY: DEFAULT_KEY, DEFAULT_MOVE_KEY: DEFAULT_MOVE_KEY, FULLSCREEN_ID: FULLSCREEN_ID, DIRECTIONS: DIRECTIONS, EFFECTS: EFFECTS, DEFAULT_EFFECT: DEFAULT_EFFECT, effectInfo: effectInfo, cleanEffect: cleanEffect,
  cleanSide: cleanSide, motionOf: motionOf, motionText: motionText, ownMotion: ownMotion, SCOPES: SCOPES,
  LAYOUTS: LAYOUTS, PLUGINS: PLUGINS, pluginInfo: pluginInfo, installCommand: installCommand, defaultState: defaultState, cleanState: cleanState, cleanPad: cleanPad,
  cleanLayer: cleanLayer, fromHubState: fromHubState, layersOf: layersOf, findLayer: findLayer, slug: slug, cleanLayout: cleanLayout,
  layoutOptions: layoutOptions, magnetOf: magnetOf, magnetOptions: magnetOptions, normalizeKey: normalizeKey, keyParts: keyParts,
  keyFromEvent: keyFromEvent, keyUsable: keyUsable, findConflict: findConflict, detectBindings: detectBindings,
  padNeedsBind: padNeedsBind, luaConfig: luaConfig, luaValue: luaValue, luaGlobal: luaGlobal, luaStart: luaStart, animSpec: animSpec,
  framePads: framePads, startupCommand: startupCommand, appId: appId, entryInfo: entryInfo, appOptions: appOptions,
  matchApps: matchApps, resolveApp: resolveApp, appTitle: appTitle, cleanCombine: cleanCombine, hostOf: hostOf,
  combineWith: combineWith, separate: separate, groupOf: groupOf
}
