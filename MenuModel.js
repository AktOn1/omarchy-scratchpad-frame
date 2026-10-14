.pragma library

// Groups and one-line descriptions for the bar menu. A style that is not listed here still shows up, under "More".
var GROUPS = [
  { id: "clean", label: "Clean", styles: ["OMARCHY", "CYBERPUNK", "HUD", "TERMINAL", "GLASS"] },
  { id: "sky", label: "Nature and sky", styles: ["AURORA", "FOLIAGE", "SAKURA", "DEEPSEA", "CORALREEF", "FROST", "CELESTIAL", "COSMIC"] },
  { id: "mystic", label: "Mystic and cute", styles: ["SACRED", "KAWAII", "HALLOWEEN", "VAPORWAVE"] },
  { id: "worlds", label: "Worlds", styles: ["STEAMPUNK", "MEGACITY", "GILDED", "PASTEUP", "BLUEPRINT"] },
  { id: "game", label: "Game UI", styles: ["RUNEFORGE", "NEXUS", "EMBERGOTH", "ABYSS", "HANAMI", "WILDWOOD"] },
  { id: "natural", label: "Natural", styles: ["DRIFTWOOD", "SLATE", "LEATHER", "TIDEPOOL", "CHERRYBARK", "MOSSWOOD"] },
  { id: "materials", label: "Materials", styles: ["WALNUT", "BAMBOO", "BIRCH", "LINEN", "TERRACOTTA", "BRICK", "SANDSTONE", "MARBLE", "CONCRETE", "RUST"] },
  { id: "pixel", label: "16-bit", styles: ["CRYSTAL", "ROYAL", "WOOD", "DUNGEON"] }
]

var DESC = {
  OMARCHY: "Plain band in your theme colours",
  CYBERPUNK: "Neon edge with corner cuts",
  HUD: "Sci-fi readout brackets",
  TERMINAL: "Green phosphor terminal bezel",
  GLASS: "Frosted glass rim",
  AURORA: "Northern lights ribbon",
  FOLIAGE: "Leaves and vines",
  SAKURA: "Painted cherry blossom branches on a lacquer rail",
  DEEPSEA: "Bubbles, kelp and fish",
  CORALREEF: "Painted coral reef corners with pearls on a dark teal rail",
  FROST: "Painted ice crystals and icicles on a frosted rail",
  CELESTIAL: "Moon, stars and constellations",
  COSMIC: "Neon filigree with a violet planet and stardust",
  SACRED: "Sacred geometry",
  KAWAII: "Pastel clouds and hearts",
  HALLOWEEN: "Bats, cobwebs and pumpkins",
  VAPORWAVE: "Sunset grid and palms",
  STEAMPUNK: "Brass gears and pipes",
  MEGACITY: "Neon city with signs and cables",
  GILDED: "Art nouveau gold",
  PASTEUP: "Notes, tape and stickers on steel",
  BLUEPRINT: "Drafting sheet with dimension lines, rulers and targets",
  RUNEFORGE: "Bronze rail with ruby gems",
  NEXUS: "Carbon fibre with cyan light",
  EMBERGOTH: "Blackened iron with red gems",
  ABYSS: "Deep-sea glass, pearls and cyan glow",
  HANAMI: "Black lacquer, gold and cherry blossom",
  WILDWOOD: "Carved oak with moss and green gems",
  DRIFTWOOD: "Weathered grey wood, like a plain picture frame",
  SLATE: "Dark slate stone",
  LEATHER: "Brown leather with hand stitching",
  TIDEPOOL: "Wet blue-green rock with real shells, starfish and sea glass",
  CHERRYBARK: "Pink-brown cherry bark with real blossom twigs and petals",
  MOSSWOOD: "Mossy forest bark with real ferns, moss and mushrooms",
  WALNUT: "Dark oiled walnut wood",
  BAMBOO: "Pale green bamboo",
  BIRCH: "White birch bark",
  LINEN: "Natural linen weave",
  TERRACOTTA: "Warm unglazed clay",
  BRICK: "Weathered red brick",
  SANDSTONE: "Golden desert sandstone",
  MARBLE: "White veined marble",
  CONCRETE: "Board-marked grey concrete",
  RUST: "Rusted corrugated iron",
  CRYSTAL: "Pixel crystals",
  ROYAL: "Pixel royal gold",
  WOOD: "Pixel carved wood",
  DUNGEON: "Pixel dungeon stone"
}

function pretty(name) {
  return name.charAt(0) + name.slice(1).toLowerCase()
}

// styles: the style names the plugin reports (hidden TRY* ones are skipped).
function categories(styles) {
  var shown = styles.filter(function (n) { return n.indexOf("TRY") !== 0 })
  var used = {}
  var cats = []
  function item(n) { return { id: n, label: pretty(n), desc: DESC[n] || "" } }
  GROUPS.forEach(function (g) {
    var items = g.styles.filter(function (n) { return shown.indexOf(n) >= 0 }).map(item)
    items.forEach(function (it) { used[it.id] = true })
    if (items.length > 0) cats.push({ id: g.id, label: g.label, items: items })
  })
  var rest = shown.filter(function (n) { return !used[n] }).map(item)
  if (rest.length > 0) cats.push({ id: "more", label: "More", items: rest })
  return cats
}

function allStyles(cats) {
  var out = []
  cats.forEach(function (c) { c.items.forEach(function (it) { out.push(it.id) }) })
  return out
}

function parseColors(text) {
  var c = {}
  String(text || "").split("\n").forEach(function (line) {
    var m = line.match(/^\s*([a-z_0-9]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
    if (m) c[m[1]] = m[2]
  })
  return c
}
