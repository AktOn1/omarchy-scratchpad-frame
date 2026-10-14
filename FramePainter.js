.pragma library

// Frame painters for the Scratchpad Frame plugin.
// paint(ctx, W, H, o): o = { style, text, colors, px, font, follow, scale?, bleed? }  (empty text = no label; bleed: see OUTER below)
// follow: true = recolour every style from the Omarchy theme; false = the style's own palette.
// (OMARCHY, AURORA, HUD, GLASS and CRYSTAL always use the theme.) (scale: draw W x H logical px shrunk, for thumbnails)
// Smooth styles are anti-aliased vector art (no pixel grid). The plain ones stay inside a 22 px band
// on every edge (the plugin widens the scratchpad gap to 26); FOLIAGE, SACRED, KAWAII, CELESTIAL,
// VAPORWAVE, SAKURA, DEEPSEA, STEAMPUNK, FROST, HALLOWEEN, COSMIC, MEGACITY, GILDED, RUNEFORGE, NEXUS, EMBERGOTH, ABYSS, HANAMI and WILDWOOD also draw decoration over the window area (the frame window is click-through).

var PIXEL = ["CRYSTAL", "ROYAL", "WOOD", "DUNGEON"]
// SMOOTH and NAMES are built from PAINTERS (below): a style that has a PAINTERS entry is in the picker, nothing else to register.
var SMOOTH = []
var NAMES = []
var BAND = 22
// Outer contour: a fitted frame (around a small window) may paint BLEED px outside the W x H rectangle
// so it is not just a box. Only the styles in OUTER do; the plugin grows the canvas by bleedFor(style)
// on every side, and paint() hands the style o.bleed with the origin still at the rectangle's corner,
// so the style draws at negative x/y and past W/H. o.bleed is 0 when the frame fills the screen.
var BLEED = 28
var OUTER = { CORALREEF: true, FROST: true, SAKURA: true, COSMIC: true, OMARCHY: true, CYBERPUNK: true, BLUEPRINT: true, DEEPSEA: true }
function bleedFor(style) { return OUTER[style] ? BLEED : 0 }

// ---- colour helpers --------------------------------------------------------
function rgb(h) {
  return { r: parseInt(h.slice(1, 3), 16), g: parseInt(h.slice(3, 5), 16), b: parseInt(h.slice(5, 7), 16) }
}
function hex2(n) { n = Math.max(0, Math.min(255, Math.round(n))); return (n < 16 ? "0" : "") + n.toString(16) }
function toHex(c) { return "#" + hex2(c.r) + hex2(c.g) + hex2(c.b) }
function rgba(h, a) { const c = rgb(h); return "rgba(" + c.r + "," + c.g + "," + c.b + "," + a + ")" }
function mix(a, b, t) {
  const x = rgb(a), y = rgb(b)
  return toHex({ r: x.r + (y.r - x.r) * t, g: x.g + (y.g - x.g) * t, b: x.b + (y.b - x.b) * t })
}
function toHsv(c) {
  const r = c.r / 255, g = c.g / 255, b = c.b / 255
  const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn
  let h = 0
  if (d > 0) {
    if (mx === r) h = ((g - b) / d) % 6
    else if (mx === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6; if (h < 0) h += 1
  }
  return { h: h, s: mx === 0 ? 0 : d / mx, v: mx }
}
function fromHsv(h, s, v) {
  const i = Math.floor(h * 6), f = h * 6 - i
  const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
  const m = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]
  return toHex({ r: m[0] * 255, g: m[1] * 255, b: m[2] * 255 })
}
// Same maths as QColor::lighter / darker.
function lighter(hx, f) {
  const c = toHsv(rgb(hx))
  let v = c.v * f, s = c.s
  if (v > 1) { s = Math.max(0, s - (v - 1)); v = 1 }
  return fromHsv(c.h, s, v)
}
function darker(hx, f) { const c = toHsv(rgb(hx)); return fromHsv(c.h, c.s, c.v * 100 / (f * 100)) }

function vivid(h) {
  const c = toHsv(rgb(h))
  return fromHsv(c.h, c.s < 0.12 ? c.s : Math.max(c.s, 0.55), Math.max(c.v, 0.92))
}
function lum(h) { const c = rgb(h); return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) / 255 }
function readable(bg, light, dark) { return lum(bg) > 0.55 ? dark : light }
function pastel(h, t) { return mix(h, "#ffffff", t) }
function hueDist(a, b) {
  const d = Math.abs(toHsv(rgb(a)).h - toHsv(rgb(b)).h)
  return Math.min(d, 1 - d)
}
// Seven-band ramp for the pixel styles: ink, three tints, base, shade, ink.
function ramp(base, ink, light) {
  return [ink, mix(base, light, 0.85), mix(base, light, 0.55), mix(base, light, 0.25), base, mix(base, "#000000", 0.4), ink]
}

// Theme colour lookup. Omarchy themes name keys "darker_background" or the
// older "darker_bg"; take whichever exists.
function pick(c, names, fallback) {
  for (const n of names) if (c[n]) return c[n]
  return fallback
}
function palette(c) {
  const accent = pick(c, ["accent"], "#7265f6")
  return {
    accent: accent,
    bg: pick(c, ["background", "bg"], "#0b0b1a"),
    dark: pick(c, ["darker_background", "darker_bg", "dark_background"], "#000014"),
    fg: pick(c, ["foreground", "fg"], "#dddddd"),
    bright: pick(c, ["bright_foreground", "bright_fg"], "#ffffff"),
    muted: pick(c, ["muted", "dark_foreground"], mix(accent, "#000000", 0.4)),
    red: pick(c, ["red"], "#ed5b5a"),
    green: pick(c, ["green"], "#92a593"),
    yellow: pick(c, ["yellow"], "#8d7541"),
    orange: pick(c, ["orange"], "#d9824a"),
    brown: pick(c, ["brown"], ""),
    byellow: pick(c, ["bright_yellow"], "#e0b050"),
    blue: pick(c, ["blue"], accent),
    cyan: pick(c, ["cyan"], "#88c0d0"),
    magenta: pick(c, ["magenta"], "#c89dc1")
  }
}

// ---- path helpers ----------------------------------------------------------
function rrPath(ctx, x, y, w, h, r, ccw) {
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  const PI = Math.PI
  ctx.beginPath()
  ctx.moveTo(x + r, y)
  if (!ccw) {
    ctx.lineTo(x + w - r, y); ctx.arc(x + w - r, y + r, r, -PI / 2, 0, false)
    ctx.lineTo(x + w, y + h - r); ctx.arc(x + w - r, y + h - r, r, 0, PI / 2, false)
    ctx.lineTo(x + r, y + h); ctx.arc(x + r, y + h - r, r, PI / 2, PI, false)
    ctx.lineTo(x, y + r); ctx.arc(x + r, y + r, r, PI, PI * 1.5, false)
  } else {
    ctx.arc(x + r, y + r, r, PI * 1.5, PI, true)
    ctx.lineTo(x, y + h - r); ctx.arc(x + r, y + h - r, r, PI, PI / 2, true)
    ctx.lineTo(x + w - r, y + h); ctx.arc(x + w - r, y + h - r, r, PI / 2, 0, true)
    ctx.lineTo(x + w, y + r); ctx.arc(x + w - r, y + r, r, 0, -PI / 2, true)
  }
  ctx.closePath()
}
function chamferPts(x, y, w, h, k) {
  return [[x + k, y], [x + w - k, y], [x + w, y + k], [x + w, y + h - k],
          [x + w - k, y + h], [x + k, y + h], [x, y + h - k], [x, y + k]]
}
function polyPath(ctx, pts, ccw) {
  const p = ccw ? pts.slice().reverse() : pts
  ctx.beginPath()
  ctx.moveTo(p[0][0], p[0][1])
  for (let i = 1; i < p.length; i++) ctx.lineTo(p[i][0], p[i][1])
  ctx.closePath()
}
function chPath(ctx, x, y, w, h, k, ccw) { polyPath(ctx, chamferPts(x, y, w, h, k), ccw) }

// Glow as stacked translucent strokes. Canvas shadowBlur on a full-frame path
// costs 0.5 - 3 s per paint at 1080p on the GUI thread, this costs a few ms.
function glowStroke(ctx, style, lw, blur, glow) {
  const g = glow || style
  const prev = ctx.globalAlpha
  ctx.strokeStyle = g
  const layers = [[1.7, 0.07], [1.2, 0.10], [0.75, 0.16], [0.4, 0.26]]
  for (const l of layers) {
    ctx.globalAlpha = prev * l[1]
    ctx.lineWidth = lw + blur * l[0]
    ctx.stroke()
  }
  ctx.globalAlpha = prev
  ctx.lineWidth = lw
  ctx.strokeStyle = style
  ctx.stroke()
}

function hash(a, b) {
  const v = Math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return v - Math.floor(v)
}

// Text with letter spacing (Canvas has none). Returns the drawn width.
function spaced(ctx, text, x, y, spacing, align) {
  let w = 0
  for (let i = 0; i < text.length; i++) w += ctx.measureText(text[i]).width + (i < text.length - 1 ? spacing : 0)
  let cx = align === "right" ? x - w : align === "center" ? x - w / 2 : x
  for (let i = 0; i < text.length; i++) {
    ctx.fillText(text[i], cx, y)
    cx += ctx.measureText(text[i]).width + spacing
  }
  return w
}
function spacedWidth(ctx, text, spacing) {
  let w = 0
  for (let i = 0; i < text.length; i++) w += ctx.measureText(text[i]).width + (i < text.length - 1 ? spacing : 0)
  return w
}
function setFont(ctx, o, size, bold) { ctx.font = (bold ? "bold " : "") + size + "px " + o.font }

// Band as a single path: outer clockwise, inner counter-clockwise.
function band(ctx, W, H, fill, outerR, innerR, chamfer) {
  const B = BAND
  ctx.beginPath()
  if (chamfer) {
    const o = chamferPts(0, 0, W, H, outerR), i = chamferPts(B, B, W - 2 * B, H - 2 * B, innerR).reverse()
    ctx.moveTo(o[0][0], o[0][1]); for (let n = 1; n < o.length; n++) ctx.lineTo(o[n][0], o[n][1]); ctx.closePath()
    ctx.moveTo(i[0][0], i[0][1]); for (let n = 1; n < i.length; n++) ctx.lineTo(i[n][0], i[n][1]); ctx.closePath()
  } else {
    arcRect(ctx, 0, 0, W, H, outerR, false)
    arcRect(ctx, B, B, W - 2 * B, H - 2 * B, innerR, true)
  }
  ctx.fillStyle = fill
  ctx.fill()
}
// Sub-path version of rrPath (no beginPath) so two rects can share one fill.
function arcRect(ctx, x, y, w, h, r, ccw) {
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  const PI = Math.PI
  ctx.moveTo(x + r, y)
  if (!ccw) {
    ctx.lineTo(x + w - r, y); ctx.arc(x + w - r, y + r, r, -PI / 2, 0, false)
    ctx.lineTo(x + w, y + h - r); ctx.arc(x + w - r, y + h - r, r, 0, PI / 2, false)
    ctx.lineTo(x + r, y + h); ctx.arc(x + r, y + h - r, r, PI / 2, PI, false)
    ctx.lineTo(x, y + r); ctx.arc(x + r, y + r, r, PI, PI * 1.5, false)
  } else {
    ctx.arc(x + r, y + r, r, PI * 1.5, PI, true)
    ctx.lineTo(x, y + h - r); ctx.arc(x + r, y + h - r, r, PI, PI / 2, true)
    ctx.lineTo(x + w - r, y + h); ctx.arc(x + w - r, y + h - r, r, PI / 2, 0, true)
    ctx.lineTo(x + w, y + r); ctx.arc(x + w - r, y + r, r, 0, -PI / 2, true)
  }
  ctx.closePath()
}

// ---- OMARCHY: theme-driven, clean -----------------------------------------
function omarchy(ctx, W, H, o) {
  const p = palette(o.colors)
  const B = o.bleed || 0
  if (B) {
    // outer contour: round ears on the corners and a tab on each edge, painted before the band covers their roots
    const ear = Math.min(B * 0.7, 18), tab = B * 0.6
    ctx.fillStyle = p.dark; ctx.strokeStyle = rgba(p.accent, 0.7); ctx.lineWidth = 1.5
    for (let i = 0; i < 4; i++) {
      ctx.beginPath(); ctx.arc(i % 2 ? W : 0, i < 2 ? 0 : H, ear, 0, Math.PI * 2); ctx.fill(); ctx.stroke()
    }
    const tabs = [[W / 2, 0, 0], [W / 2, H, 0], [0, H / 2, 1], [W, H / 2, 1]]
    for (let i = 0; i < 4; i++) {
      const t = tabs[i], len = Math.min(90, (t[2] ? H : W) * 0.3), sgn = (i === 0 || i === 2) ? -1 : 1
      ctx.save(); ctx.translate(t[0], t[1]); if (t[2]) ctx.rotate(Math.PI / 2)
      rrPath(ctx, -len / 2, sgn < 0 ? -tab : -8, len, tab + 8, tab * 0.45)
      ctx.fill(); ctx.stroke(); ctx.restore()
    }
  }
  band(ctx, W, H, p.dark, 16, 7, false)
  // hairline on the very edge, accent line hugging the windows
  rrPath(ctx, 1.5, 1.5, W - 3, H - 3, 15)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(p.muted, 0.55); ctx.stroke()
  const g = ctx.createLinearGradient(0, 0, W, H)
  g.addColorStop(0, p.accent); g.addColorStop(0.5, lighter(p.accent, 1.35)); g.addColorStop(1, p.accent)
  rrPath(ctx, 15, 15, W - 30, H - 30, 9)
  glowStroke(ctx, g, 2, 8, rgba(p.accent, 0.55))
  // label breaks the accent line
  if (o.text) {
    setFont(ctx, o, 11, true)
    const t = o.text, sp = 3
    const tw = spacedWidth(ctx, t, sp), x0 = 34
    ctx.fillStyle = p.dark
    rrPath(ctx, x0 - 6, 4, tw + 36, 15, 7.5); ctx.fill()
    ctx.beginPath(); ctx.arc(x0 + 3, 11.5, 2.6, 0, Math.PI * 2); ctx.fillStyle = p.accent; ctx.fill()
    ctx.fillStyle = p.bright
    spaced(ctx, t, x0 + 13, 15.5, sp, "left")
  }
  // three small pager dots, bottom right
  for (let i = 0; i < 3; i++) {
    ctx.beginPath(); ctx.arc(W - 40 + i * 9, H - 11, 2, 0, Math.PI * 2)
    ctx.fillStyle = i === 0 ? p.accent : rgba(p.muted, 0.7); ctx.fill()
  }
}

// ---- CYBERPUNK: neon, chamfered, circuit traces ------------------------------
function cyberpunk(ctx, W, H, o) {
  const p = palette(o.colors)
  let dark = "#07070f", cy = "#00f0ff", mg = "#ff2a6d", yl = "#fcee0a"
  if (o.follow) {
    dark = p.dark; cy = vivid(p.accent); yl = vivid(p.byellow)
    mg = vivid(hueDist(p.magenta, cy) > 0.08 ? p.magenta : p.red)
  }
  const B = o.bleed || 0
  if (B) {
    // outer contour: a chamfered neon bracket round each corner, painted before the band covers its roots
    const k = 14, a = B - 6, L = 56
    ctx.fillStyle = dark; ctx.lineWidth = 1.5
    for (let i = 0; i < 4; i++) {
      ctx.save(); ctx.translate(i % 2 ? W : 0, i < 2 ? 0 : H); ctx.scale(i % 2 ? -1 : 1, i < 2 ? 1 : -1)
      ctx.beginPath()
      ctx.moveTo(-a, L); ctx.lineTo(-a, -a + k); ctx.lineTo(-a + k, -a); ctx.lineTo(L, -a)
      ctx.lineTo(L, 4); ctx.lineTo(4, 4); ctx.lineTo(4, L); ctx.closePath()
      ctx.fill(); glowStroke(ctx, (i % 2) ? mg : cy, 1.5, 8); ctx.restore()
    }
  }
  band(ctx, W, H, dark, 18, 8, true)

  // faint scan grid inside the band
  ctx.lineWidth = 1
  ctx.strokeStyle = rgba(cy, 0.06)
  ctx.beginPath()
  for (let x = 24; x < W - 24; x += 12) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, BAND); ctx.moveTo(x + 0.5, H - BAND); ctx.lineTo(x + 0.5, H) }
  for (let y = 24; y < H - 24; y += 12) { ctx.moveTo(0, y + 0.5); ctx.lineTo(BAND, y + 0.5); ctx.moveTo(W - BAND, y + 0.5); ctx.lineTo(W, y + 0.5) }
  ctx.stroke()

  // circuit traces between the neon lines: horizontal run, 45 degree jog, node
  ctx.lineWidth = 1
  const trace = (pts, c, a) => {
    ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
    ctx.strokeStyle = rgba(c, a); ctx.stroke()
    const e = pts[pts.length - 1]
    ctx.beginPath(); ctx.arc(e[0], e[1], 2.2, 0, Math.PI * 2); ctx.fillStyle = rgba(c, a); ctx.fill()
  }
  for (let i = 0; i < 4; i++) {
    const x = W * (0.42 + 0.14 * i) + Math.floor(hash(i, 3) * 40)
    const l = 40 + Math.floor(hash(i, 9) * 60)
    trace([[x, 8.5], [x + l, 8.5], [x + l + 6, 14.5], [x + l + 40, 14.5]], i % 2 ? mg : cy, 0.75)
    const y = H * (0.2 + 0.2 * i)
    trace([[W - 8.5, y], [W - 8.5, y + l * 0.5], [W - 14.5, y + l * 0.5 + 6], [W - 14.5, y + l]], i % 2 ? cy : mg, 0.6)
    const x2 = W * (0.1 + 0.2 * i)
    trace([[x2, H - 8.5], [x2 + l, H - 8.5], [x2 + l + 6, H - 14.5], [x2 + l + 30, H - 14.5]], i % 2 ? mg : cy, 0.6)
  }

  // hazard stripe block, bottom left
  ctx.save()
  ctx.beginPath(); ctx.rect(44, H - 17, 96, 11); ctx.clip()
  ctx.fillStyle = yl; ctx.fillRect(44, H - 17, 96, 11)
  ctx.strokeStyle = dark; ctx.lineWidth = 5
  ctx.beginPath()
  for (let x = 30; x < 160; x += 13) { ctx.moveTo(x, H - 6); ctx.lineTo(x + 11, H - 17) }
  ctx.stroke()
  ctx.restore()

  // neon lines
  chPath(ctx, 3, 3, W - 6, H - 6, 15)
  glowStroke(ctx, cy, 2, 12)
  chPath(ctx, 18.5, 18.5, W - 37, H - 37, 5)
  glowStroke(ctx, mg, 1.5, 9)

  // label tab: yellow, slanted right edge, glitch ghost text
  if (o.text) {
    setFont(ctx, o, 11, true)
    const t = o.text, sp = 2, tw = spacedWidth(ctx, t, sp), x0 = 46
    ctx.beginPath()
    ctx.moveTo(x0, 2); ctx.lineTo(x0 + tw + 26, 2); ctx.lineTo(x0 + tw + 16, 20); ctx.lineTo(x0, 20); ctx.closePath()
    ctx.fillStyle = yl; ctx.fill()
    ctx.fillStyle = rgba(mg, 0.9); spaced(ctx, t, x0 + 10 + 1.2, 15, sp, "left")
    ctx.fillStyle = rgba(cy, 0.9); spaced(ctx, t, x0 + 10 - 1.2, 15, sp, "left")
    ctx.fillStyle = dark; spaced(ctx, t, x0 + 10, 15, sp, "left")
  }

  // status text, bottom right
  setFont(ctx, o, 9, true)
  ctx.fillStyle = rgba(cy, 0.9)
  spaced(ctx, "SYS//ONLINE", W - 46, H - 7.5, 2, "right")
  ctx.fillStyle = mg; ctx.fillRect(W - 40, H - 16, 3, 9); ctx.fillRect(W - 35, H - 16, 3, 9)
}

// ---- AURORA: soft glowing gradient ring ----------------------------------------
function aurora(ctx, W, H, o) {
  const p = palette(o.colors)
  band(ctx, W, H, rgba(p.dark, 0.6), 18, 8, false)
  const g1 = ctx.createLinearGradient(0, 0, W, H)
  g1.addColorStop(0, p.accent); g1.addColorStop(0.3, p.cyan); g1.addColorStop(0.55, p.green)
  g1.addColorStop(0.8, p.magenta); g1.addColorStop(1, p.accent)
  const g2 = ctx.createLinearGradient(W, 0, 0, H)
  g2.addColorStop(0, p.magenta); g2.addColorStop(0.5, p.blue); g2.addColorStop(1, p.cyan)
  rrPath(ctx, 7, 7, W - 14, H - 14, 14)
  glowStroke(ctx, g1, 3, 18, rgba(p.accent, 0.9))
  rrPath(ctx, 14.5, 14.5, W - 29, H - 29, 8)
  ctx.globalAlpha = 0.8
  glowStroke(ctx, g2, 1, 4, rgba(p.cyan, 0.5))
  ctx.globalAlpha = 1
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0 = 40
    ctx.fillStyle = rgba(p.dark, 0.95)
    rrPath(ctx, x0 - 10, 3, tw + 20, 17, 8.5); ctx.fill()
    ctx.fillStyle = rgba(p.bright, 0.92)
    spaced(ctx, t, x0, 15, sp, "left")
  }
}

// ---- HUD: sci-fi readout with brackets and ruler ticks ------------------------
function hud(ctx, W, H, o) {
  const p = palette(o.colors)
  const line = p.cyan !== "#88c0d0" ? p.cyan : p.accent
  band(ctx, W, H, rgba(p.dark, 0.7), 4, 0, false)
  // inner and outer hairlines
  ctx.lineWidth = 1
  ctx.strokeStyle = rgba(line, 0.7)
  ctx.beginPath(); ctx.rect(BAND - 0.5, BAND - 0.5, W - 2 * BAND + 1, H - 2 * BAND + 1); ctx.stroke()
  ctx.strokeStyle = rgba(line, 0.25)
  ctx.beginPath(); ctx.rect(1.5, 1.5, W - 3, H - 3); ctx.stroke()
  // ruler ticks growing outwards from the inner line
  const skipTop = (x) => x > 20 && x < 262
  ctx.beginPath()
  for (let x = 30; x < W - 30; x += 10) {
    const L = x % 100 === 0 ? 8 : x % 50 === 0 ? 6 : 3
    if (!skipTop(x)) { ctx.moveTo(x + 0.5, BAND); ctx.lineTo(x + 0.5, BAND - L) }
    ctx.moveTo(x + 0.5, H - BAND); ctx.lineTo(x + 0.5, H - BAND + L)
  }
  for (let y = 30; y < H - 30; y += 10) {
    const L = y % 100 === 0 ? 8 : y % 50 === 0 ? 6 : 3
    ctx.moveTo(BAND, y + 0.5); ctx.lineTo(BAND - L, y + 0.5)
    ctx.moveTo(W - BAND, y + 0.5); ctx.lineTo(W - BAND + L, y + 0.5)
  }
  ctx.strokeStyle = rgba(line, 0.75); ctx.stroke()
  // coordinates along the top and bottom edges
  setFont(ctx, o, 8, false)
  ctx.fillStyle = rgba(line, 0.65)
  for (let x = 300; x < W - 60; x += 200) {
    spaced(ctx, String(x), x + 3, 9, 1, "left")
    spaced(ctx, String(x), x + 3, H - 3, 1, "left")
  }
  // corner brackets
  const arm = 46, c = 4
  ctx.beginPath()
  ctx.moveTo(c, c + arm); ctx.lineTo(c, c); ctx.lineTo(c + arm, c)
  ctx.moveTo(W - c - arm, c); ctx.lineTo(W - c, c); ctx.lineTo(W - c, c + arm)
  ctx.moveTo(c, H - c - arm); ctx.lineTo(c, H - c); ctx.lineTo(c + arm, H - c)
  ctx.moveTo(W - c - arm, H - c); ctx.lineTo(W - c, H - c); ctx.lineTo(W - c, H - c - arm)
  ctx.lineJoin = "miter"
  glowStroke(ctx, lighter(line, 1.3), 2.5, 7, rgba(line, 0.9))
  // edge-centre markers
  const tri = (x, y, dx, dy) => {
    ctx.beginPath(); ctx.moveTo(x - dy * 6, y - dx * 6); ctx.lineTo(x + dy * 6, y + dx * 6); ctx.lineTo(x + dx * 7, y + dy * 7)
    ctx.closePath(); ctx.fillStyle = lighter(line, 1.2); ctx.fill()
  }
  tri(W / 2, 4, 0, 1); tri(W / 2, H - 4, 0, -1); tri(4, H / 2, 1, 0); tri(W - 4, H / 2, -1, 0)
  // label + status
  if (o.text) {
    setFont(ctx, o, 11, true)
    ctx.beginPath(); ctx.moveTo(60, 6); ctx.lineTo(60, 16); ctx.lineTo(67, 11); ctx.closePath(); ctx.fillStyle = line; ctx.fill()
    ctx.fillStyle = p.bright
    spaced(ctx, o.text, 74, 16, 2, "left")
  }
  setFont(ctx, o, 9, true)
  ctx.fillStyle = rgba(line, 0.9)
  spaced(ctx, "LINK OK", W - 60, H - 8, 2, "right")
  ctx.beginPath(); ctx.arc(W - 52, H - 11.5, 2.5, 0, Math.PI * 2); ctx.fillStyle = p.green; ctx.fill()
}

// ---- TERMINAL: phosphor green console ------------------------------------------
function terminal(ctx, W, H, o) {
  const p = palette(o.colors)
  let ph = "#3dff7f", dim = "#17803f", bgc = "#020a05"
  if (o.follow) { ph = vivid(p.green); dim = mix(ph, p.dark, 0.6); bgc = p.dark }
  band(ctx, W, H, bgc, 10, 3, false)
  // scanlines
  ctx.fillStyle = "rgba(0,0,0,0.5)"
  for (let y = 0; y < H; y += 3) {
    if (y < BAND || y > H - BAND) ctx.fillRect(0, y, W, 1)
    else { ctx.fillRect(0, y, BAND, 1); ctx.fillRect(W - BAND, y, BAND, 1) }
  }
  rrPath(ctx, 4, 4, W - 8, H - 8, 7)
  glowStroke(ctx, ph, 1.5, 7)
  rrPath(ctx, 17.5, 17.5, W - 35, H - 35, 2)
  ctx.lineWidth = 1; ctx.strokeStyle = dim; ctx.stroke()
  const x0 = 24
  if (o.text) {
    setFont(ctx, o, 11, true)
    const t = "[ " + o.text + " ]"
    const tw = spacedWidth(ctx, t, 1)
    ctx.fillStyle = bgc; ctx.fillRect(x0 - 5, 2, tw + 10, 15)
    ctx.fillStyle = ph; ctx.shadowColor = ph; ctx.shadowBlur = 6
    spaced(ctx, t, x0, 15, 1, "left")
    ctx.shadowBlur = 0; ctx.shadowColor = "rgba(0,0,0,0)"
  }
  // prompt and block cursor, bottom
  setFont(ctx, o, 10, true)
  ctx.fillStyle = bgc; ctx.fillRect(x0 - 5, H - 17, 62, 14)
  ctx.fillStyle = dim; spaced(ctx, "~ $", x0, H - 7, 1, "left")
  ctx.fillStyle = ph; ctx.shadowColor = ph; ctx.shadowBlur = 8
  ctx.fillRect(x0 + 30, H - 16, 7, 11)
  ctx.shadowBlur = 0; ctx.shadowColor = "rgba(0,0,0,0)"
}

// ---- GLASS: frosted translucent frame ------------------------------------------
function glass(ctx, W, H, o) {
  const p = palette(o.colors)
  band(ctx, W, H, rgba(p.dark, 0.38), 17, 7, false)
  const g = ctx.createLinearGradient(0, 0, 0, H)
  g.addColorStop(0, "rgba(255,255,255,0.26)"); g.addColorStop(0.35, "rgba(255,255,255,0.09)")
  g.addColorStop(1, "rgba(255,255,255,0.14)")
  band(ctx, W, H, g, 17, 7, false)
  const e = ctx.createLinearGradient(0, 0, W, H)
  e.addColorStop(0, "rgba(255,255,255,0.8)"); e.addColorStop(0.5, "rgba(255,255,255,0.15)"); e.addColorStop(1, "rgba(255,255,255,0.5)")
  rrPath(ctx, 0.75, 0.75, W - 1.5, H - 1.5, 16)
  ctx.lineWidth = 1.5; ctx.strokeStyle = e; ctx.stroke()
  rrPath(ctx, BAND - 0.5, BAND - 0.5, W - 2 * BAND + 1, H - 2 * BAND + 1, 7)
  ctx.lineWidth = 1; ctx.strokeStyle = "rgba(0,0,0,0.4)"; ctx.stroke()
  rrPath(ctx, BAND - 1.5, BAND - 1.5, W - 2 * BAND + 3, H - 2 * BAND + 3, 8)
  ctx.strokeStyle = "rgba(255,255,255,0.18)"; ctx.stroke()
  // top sheen highlight
  const s = ctx.createLinearGradient(W * 0.1, 0, W * 0.9, 0)
  s.addColorStop(0, "rgba(255,255,255,0)"); s.addColorStop(0.5, "rgba(255,255,255,0.55)"); s.addColorStop(1, "rgba(255,255,255,0)")
  ctx.fillStyle = s; ctx.fillRect(W * 0.1, 2.5, W * 0.8, 1.2)
  if (o.text) {
    setFont(ctx, o, 10, true)
    ctx.fillStyle = "rgba(255,255,255,0.88)"
    ctx.shadowColor = "rgba(0,0,0,0.5)"; ctx.shadowBlur = 3
    spaced(ctx, o.text, W / 2, 15, 4, "center")
    ctx.shadowBlur = 0; ctx.shadowColor = "rgba(0,0,0,0)"
  }
}

// ---- shared shapes for the decorative styles -----------------------------------
// Point on edge e (0 top, 1 right, 2 bottom, 3 left, clockwise), t px along it, off px in from the outside.
function edgeXY(W, H, e, t, off) {
  switch (e) {
  case 0: return [t, off]
  case 1: return [W - off, t]
  case 2: return [W - t, H - off]
  default: return [off, H - t]
  }
}
function edgeLen(W, H, e) { return e % 2 === 0 ? W : H }
function bandClip(ctx, W, H, outerR, innerR) {
  ctx.beginPath()
  arcRect(ctx, 0, 0, W, H, outerR, false)
  arcRect(ctx, BAND, BAND, W - 2 * BAND, H - 2 * BAND, innerR, true)
  ctx.clip()
}
function leafShape(ctx, x, y, ang, len, wid, fill, vein) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(ang)
  ctx.beginPath(); ctx.moveTo(0, 0)
  ctx.bezierCurveTo(len * 0.25, -wid * 1.3, len * 0.8, -wid, len, 0)
  ctx.bezierCurveTo(len * 0.8, wid, len * 0.25, wid * 1.3, 0, 0)
  ctx.fillStyle = fill; ctx.fill()
  if (vein) {
    ctx.beginPath(); ctx.moveTo(1, 0); ctx.lineTo(len * 0.85, 0)
    ctx.lineWidth = 0.6; ctx.strokeStyle = vein; ctx.stroke()
  }
  ctx.restore()
}
function heartShape(ctx, x, y, s, fill) {
  ctx.beginPath(); ctx.moveTo(x, y + s * 0.9)
  ctx.bezierCurveTo(x - s * 1.7, y - s * 0.1, x - s * 0.8, y - s * 1.3, x, y - s * 0.4)
  ctx.bezierCurveTo(x + s * 0.8, y - s * 1.3, x + s * 1.7, y - s * 0.1, x, y + s * 0.9)
  ctx.fillStyle = fill; ctx.fill()
}
function sparkleShape(ctx, x, y, R, fill) {
  const k = R * 0.14
  ctx.beginPath(); ctx.moveTo(x, y - R)
  ctx.quadraticCurveTo(x + k, y - k, x + R, y)
  ctx.quadraticCurveTo(x + k, y + k, x, y + R)
  ctx.quadraticCurveTo(x - k, y + k, x - R, y)
  ctx.quadraticCurveTo(x - k, y - k, x, y - R)
  ctx.fillStyle = fill; ctx.fill()
}
function starShape(ctx, x, y, R, fill) {
  ctx.beginPath()
  for (let i = 0; i < 10; i++) {
    const a = -Math.PI / 2 + i * Math.PI / 5, r = i % 2 ? R * 0.45 : R
    if (i) ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); else ctx.moveTo(x + Math.cos(a) * r, y + Math.sin(a) * r)
  }
  ctx.closePath(); ctx.fillStyle = fill; ctx.fill()
}
function dotShape(ctx, x, y, r, fill) {
  ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fillStyle = fill; ctx.fill()
}
function pill(ctx, x, y, w, h, fill, stroke, lw) {
  rrPath(ctx, x, y, w, h, h / 2)
  ctx.fillStyle = fill; ctx.fill()
  if (stroke) { ctx.lineWidth = lw || 1; ctx.strokeStyle = stroke; ctx.stroke() }
}

// 3x5 pixel font shared by the pixel styles and the foliage plank
var PIXFONT = {
  A: "010101111101101", B: "110101110101110", C: "111100100100111", D: "110101101101110",
  E: "111100110100111", F: "111100110100100", G: "011100101101011", H: "101101111101101",
  I: "111010010010111", J: "001001001101010", K: "101101110101101", L: "100100100100111",
  M: "101111111101101", N: "110101101101101", O: "010101101101010", P: "110101110100100",
  Q: "010101101110011", R: "110101110101101", S: "111100111001111", T: "111010010010010",
  U: "101101101101111", V: "101101101101010", W: "101101111111101", X: "101101010101101",
  Y: "101101010010010", Z: "111001010100111", " ": "000000000000000"
}

// ---- FOLIAGE: 16-bit jungle. Layered pixel-art vines hang from the top and sides, ferns and
// big leaves climb from the bottom and corners. Leaves overlap into the window area (the
// frame window is click-through, so nothing is hindered); a mossy backdrop fills the band. ----
function foliage(ctx, W, H, o) {
  const p = palette(o.colors)
  const C = o.px || 3
  const GW = Math.ceil(W / C), GH = Math.ceil(H / C)
  const BG = 8                                        // backdrop band, in cells (24 px)
  const mkLayer = (ol, d, b, l, hi) => ({ ol: ol, d: d, b: b, l: l, hi: hi })
  let K
  if (o.follow) {
    const g = p.green, dk = p.dark
    K = {
      bgA: mix(g, dk, 0.84), bgB: mix(g, dk, 0.74), bgC: mix(g, dk, 0.92), rim: mix(g, dk, 0.4),
      layers: [
        mkLayer(mix(g, dk, 0.94), mix(g, dk, 0.82), mix(g, dk, 0.7), mix(g, dk, 0.58), mix(g, dk, 0.46)),
        mkLayer(mix(g, dk, 0.9), mix(g, dk, 0.66), mix(g, dk, 0.48), mix(g, dk, 0.3), mix(g, dk, 0.1)),
        mkLayer(mix(g, dk, 0.86), mix(g, dk, 0.5), g, lighter(g, 1.25), lighter(g, 1.55))
      ],
      stem: mix(g, dk, 0.62), flowers: [p.magenta, p.red, p.byellow, p.orange, p.cyan], core: p.byellow,
      wood: [mix(p.orange, dk, 0.88), lighter(p.orange, 1.2), p.orange, mix(p.orange, dk, 0.4)],
      wtext: readable(p.orange, p.bright, p.dark)
    }
  } else {
    K = {
      bgA: "#0e3a28", bgB: "#14503a", bgC: "#082a1c", rim: "#3f8a50",
      layers: [
        mkLayer("#06140b", "#0d3a22", "#145232", "#1d6c40", "#28854d"),
        mkLayer("#08200f", "#135f31", "#1d8a42", "#31b457", "#54d46c"),
        mkLayer("#0a2a12", "#1a7a38", "#2fb34f", "#63dc6a", "#b8f58a")
      ],
      stem: "#3d5a24", flowers: ["#ff7fae", "#ff5a4f", "#ffd75a", "#ff9a3c", "#c98cff"], core: "#fff2a8",
      wood: ["#1a0e06", "#d8a060", "#a86a34", "#6c4018"], wtext: "#fff0c0"
    }
  }

  // ---- cell drawing, merged into horizontal runs ----
  let rx = 0, ry = 0, rw = 0, rc = ""
  const flush = () => { if (rw > 0) { ctx.fillStyle = rc; ctx.fillRect(rx * C, ry * C, rw * C, C); rw = 0 } }
  const dot = (x, y, c) => {
    if (x < 0 || y < 0 || x >= GW || y >= GH) return
    if (rw > 0 && y === ry && c === rc && x === rx + rw) { rw++; return }
    flush(); rx = x; ry = y; rw = 1; rc = c
  }
  const rect = (x, y, w, h, c) => { flush(); ctx.fillStyle = c; ctx.fillRect(x * C, y * C, w * C, h * C) }

  let seed = 1
  const rnd = () => hash(seed++, 7.31)
  const rng = (a, b) => a + (b - a) * rnd()

  // ---- one leaf, rasterised cell by cell with an outline and three shades ----
  // kind 0 pointed leaf, kind 1 slit leaf (monstera / banana). bend curls the tip.
  function leafPix(S, x0, y0, ang, len, wid, kind, bend, flat) {
    const ca = Math.cos(ang), sa = Math.sin(ang)
    const half = (u, v) => {
      if (u < 0 || u > len) return -1
      const t = u / len
      let w = wid * Math.pow(Math.sin(Math.PI * Math.pow(t, 0.75)), 0.85)
      const vv = Math.abs(v - bend * t * t)
      if (kind === 1 && t > 0.2 && t < 0.92) {
        const per = len / 5, f = (u / per) % 1
        if (f > 0.42 && f < 0.62 && vv > w * 0.4) return -1
      }
      return vv <= w ? w : -1
    }
    const test = (x, y) => {
      const dx = x + 0.5 - x0, dy = y + 0.5 - y0
      return half(dx * ca + dy * sa, -dx * sa + dy * ca) >= 0
    }
    const ex = [0, len, 0, len], ey = [-wid - Math.abs(bend), -wid - Math.abs(bend), wid + Math.abs(bend), wid + Math.abs(bend)]
    let x1 = 1e9, x2 = -1e9, y1 = 1e9, y2 = -1e9
    for (let i = 0; i < 4; i++) {
      const wx = x0 + ex[i] * ca - ey[i] * sa, wy = y0 + ex[i] * sa + ey[i] * ca
      x1 = Math.min(x1, wx); x2 = Math.max(x2, wx); y1 = Math.min(y1, wy); y2 = Math.max(y2, wy)
    }
    x1 = Math.max(0, Math.floor(x1) - 1); x2 = Math.min(GW - 1, Math.ceil(x2) + 1)
    y1 = Math.max(0, Math.floor(y1) - 1); y2 = Math.min(GH - 1, Math.ceil(y2) + 1)
    const lit = 0.6 * sa - 0.8 * ca > 0 ? 1 : -1
    for (let y = y1; y <= y2; y++) {
      for (let x = x1; x <= x2; x++) {
        const dx = x + 0.5 - x0, dy = y + 0.5 - y0
        const u = dx * ca + dy * sa, v = -dx * sa + dy * ca
        const w = half(u, v)
        if (w < 0) continue
        let c
        if (flat) {
          const vc = v - bend * (u / len) * (u / len)
          c = Math.abs(vc) < 0.5 ? S.d : (vc * lit > 0 ? S.l : S.b)
        } else if (!test(x - 1, y) || !test(x + 1, y) || !test(x, y - 1) || !test(x, y + 1)) c = S.ol
        else {
          const vc = v - bend * (u / len) * (u / len)
          const t = vc / Math.max(w, 0.5) * lit
          if (Math.abs(vc) < 0.55 && u > 1.5 && u < len * 0.88) c = S.d
          else if (t > 0.45) c = (t > 0.8 && hash(x, y) > 0.78) ? S.hi : S.l
          else if (t > -0.35) c = S.b
          else c = S.d
        }
        dot(x, y, c)
      }
    }
    flush()
  }

  function flower(x, y, c) {
    const L = K.layers[0].ol
    dot(x, y - 2, L); dot(x - 1, y - 2, L); dot(x + 1, y - 2, L)
    for (let j = -1; j <= 1; j++) { dot(x - 2, y + j, L); dot(x + 2, y + j, L) }
    dot(x - 1, y + 2, L); dot(x, y + 2, L); dot(x + 1, y + 2, L)
    for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) dot(x + i, y + j, c)
    dot(x, y, K.core)
    flush()
  }

  // ---- a curving stem with leaves on both sides. ang 0 right, PI/2 down. ----
  function branch(S, x, y, ang, len, b) {
    const pts = []
    const ph = rnd() * 6.28, fr = rng(0.12, 0.3)
    for (let i = 0; i < len; i++) {
      pts.push([x, y, ang])
      let d = Math.PI / 2 - ang
      while (d > Math.PI) d -= 2 * Math.PI
      while (d < -Math.PI) d += 2 * Math.PI
      ang += d * b.grav + b.sway * Math.sin(i * fr + ph)
      x += Math.cos(ang); y += Math.sin(ang)
    }
    for (let i = 0; i < pts.length; i++) {
      const q = pts[i]
      dot(Math.round(q[0]), Math.round(q[1]), K.stem)
      if (b.thick && i < len * 0.4) dot(Math.round(q[0]) + 1, Math.round(q[1]), K.stem)
    }
    flush()
    let side = rnd() < 0.5 ? 1 : -1
    for (let i = b.every; i < pts.length; i += b.every) {
      const q = pts[i], k = 1 - 0.55 * i / len
      const big = b.leaf[1] * k, sm = b.leaf[0] * k
      const kind = rnd() < b.slit ? 1 : 0
      const l = Math.max(4, rng(sm, big))
      const a = q[2] + side * rng(b.spread[0], b.spread[1])
      const ca = Math.cos(a)
      leafPix(S, q[0], q[1], a, l, Math.max(1.4, l * b.fat), kind, (ca >= 0 ? 1 : -1) * l * 0.12)
      if (b.flowers && rnd() < b.flowers) {
        const fx = q[0] + Math.cos(q[2] - side * 1.5) * 4, fy = q[1] + Math.sin(q[2] - side * 1.5) * 4
        flower(Math.round(fx), Math.round(fy), K.flowers[Math.floor(rnd() * K.flowers.length)])
      }
      side = -side
    }
    const t = pts[pts.length - 1]
    if (t && b.tip) leafPix(S, t[0], t[1], t[2], b.tip, b.tip * b.fat, 0, 0)
  }

  // fern frond: a drooping rib with many small paired pinnae
  function frond(S, x, y, ang, len, grav) {
    const pts = []
    for (let i = 0; i < len; i++) {
      pts.push([x, y, ang])
      let d = Math.PI / 2 - ang
      ang += d * grav
      x += Math.cos(ang); y += Math.sin(ang)
    }
    for (const q of pts) dot(Math.round(q[0]), Math.round(q[1]), S.d)
    flush()
    for (let i = 2; i < pts.length; i++) {
      const q = pts[i], k = 1 - i / len, l = 3 + 6.5 * Math.sqrt(k)
      leafPix(S, q[0], q[1], q[2] + 1.1, l, 1.3, 0, 0, true)
      leafPix(S, q[0], q[1], q[2] - 1.1, l, 1.3, 0, 0, true)
    }
  }

  // ---- 1. backdrop: dithered mossy band with a lit inner rim ----
  const rimR = 4
  const inInner = (x, y) => {
    if (x < BG || y < BG || x >= GW - BG || y >= GH - BG) return false
    const cx = x < BG + rimR ? BG + rimR : (x >= GW - BG - rimR ? GW - BG - rimR - 1 : x)
    const cy = y < BG + rimR ? BG + rimR : (y >= GH - BG - rimR ? GH - BG - rimR - 1 : y)
    const dx = x - cx, dy = y - cy
    return dx * dx + dy * dy <= rimR * rimR
  }
  for (let y = 0; y < GH; y++) {
    const edgeRow = y < BG + rimR || y >= GH - BG - rimR
    for (let x = 0; x < GW; x++) {
      if (!edgeRow && x >= BG && x < GW - BG) { x = GW - BG - 1; continue }
      if (inInner(x, y)) continue
      const rim = inInner(x - 1, y) || inInner(x + 1, y) || inInner(x, y - 1) || inInner(x, y + 1)
      const h = hash(x, y)
      let c = K.bgA
      if (rim) c = K.rim
      else if (h > 0.86) c = K.bgB
      else if (h < 0.18) c = K.bgC
      else if (((x + y) & 1) === 0 && h > 0.55) c = K.bgB
      dot(x, y, c)
    }
  }
  flush()

  // ---- 2. back layer: dark leaves lining the band, dark vines ----
  const S0 = K.layers[0], S1 = K.layers[1], S2 = K.layers[2]
  seed = 100
  for (let x = 4; x < GW - 4; x += Math.round(rng(9, 15))) {
    leafPix(S0, x, 1, rng(1.0, 2.1), rng(9, 15), rng(2.6, 3.8), 0, 0)
    leafPix(S0, x + 2, GH - 1, -rng(1.0, 2.1), rng(9, 15), rng(2.6, 3.8), 0, 0)
  }
  for (let y = 6; y < GH - 6; y += Math.round(rng(9, 15))) {
    leafPix(S0, 1, y, rng(-0.5, 0.5), rng(9, 14), rng(2.6, 3.6), 0, 0)
    leafPix(S0, GW - 1, y, Math.PI + rng(-0.5, 0.5), rng(9, 14), rng(2.6, 3.6), 0, 0)
  }
  const hang = (S, x, len, b) => branch(S, x, -1, Math.PI / 2 + rng(-0.25, 0.25), len, b)
  const vineB = { grav: 0.02, sway: 0.05, every: 3, leaf: [5, 11], spread: [0.6, 1.2], fat: 0.34, slit: 0.1, tip: 7 }
  for (let x = 10; x < GW - 10; x += Math.round(rng(7, 12)))
    hang(S0, x, Math.round(6 + Math.pow(rnd(), 2) * 38), vineB)

  // ---- 3. middle layer: side and bottom growth, vines from the top ----
  seed = 300
  const sideB = { grav: 0.07, sway: 0.08, every: 3, leaf: [5, 10], spread: [0.6, 1.2], fat: 0.36, slit: 0.15, tip: 7, thick: true }
  for (let y = 40; y < GH - 40; y += Math.round(rng(16, 30))) {
    branch(S1, -1, y, rng(-0.25, 0.3), Math.round(rng(14, 28)), sideB)
    branch(S1, GW, y + rng(-6, 6), Math.PI + rng(-0.3, 0.25), Math.round(rng(14, 28)), sideB)
  }
  for (let x = 30; x < GW - 30; x += Math.round(rng(22, 40)))
    branch(S1, x, GH, -Math.PI / 2 + rng(-0.45, 0.45), Math.round(rng(10, 20)), { grav: 0.05, sway: 0.1, every: 3, leaf: [6, 11], spread: [0.6, 1.1], fat: 0.34, slit: 0.2, tip: 8, thick: true })
  for (let x = 14; x < GW - 14; x += Math.round(rng(9, 15)))
    hang(S1, x, Math.round(8 + Math.pow(rnd(), 1.8) * 52), { grav: 0.02, sway: 0.06, every: 3, leaf: [6, 13], spread: [0.55, 1.15], fat: 0.34, slit: 0.15, tip: 9, flowers: 0.05 })

  // ---- 4. front layer: long lush vines, corner clusters, ferns ----
  seed = 500
  const frontB = { grav: 0.015, sway: 0.07, every: 3, leaf: [6, 14], spread: [0.55, 1.2], fat: 0.36, slit: 0.2, tip: 10, flowers: 0.11, thick: true }
  for (let x = 6; x < GW - 6; x += Math.round(rng(14, 26)))
    hang(S2, x, Math.round(10 + Math.pow(rnd(), 1.5) * 62), frontB)

  const corners = [[-2, -2, Math.PI / 4], [GW + 2, -2, 3 * Math.PI / 4], [GW + 2, GH + 2, -3 * Math.PI / 4], [-2, GH + 2, -Math.PI / 4]]
  corners.forEach((c, ci) => {
    seed = 700 + ci * 40
    const down = ci < 2
    for (let i = 0; i < 6; i++) {
      const sp = rng(-1.05, 1.05)
      leafPix(i < 3 ? S1 : S2, c[0], c[1], c[2] + sp, rng(30, 48), rng(7, 11), i % 3 === 2 ? 0 : 1, (Math.cos(c[2] + sp) >= 0 ? 1 : -1) * rng(2, 6))
    }
    for (let i = 0; i < 3; i++)
      frond(S2, c[0], c[1], c[2] + rng(-0.9, 0.9), Math.round(rng(22, 34)), 0.05)
    for (let i = 0; i < 3; i++) {
      const a = down ? Math.PI / 2 + (ci === 0 ? -1 : 1) * rng(0.1, 0.6) : -Math.PI / 2 + (ci === 3 ? 1 : -1) * rng(0.1, 0.6)
      branch(S2, c[0] + (ci === 0 || ci === 3 ? 6 : -6) * rnd(), c[1] + (down ? 4 : -4), a, Math.round(rng(40, 66)), { grav: 0.02, sway: 0.06, every: 3, leaf: [7, 14], spread: [0.55, 1.15], fat: 0.36, slit: 0.2, tip: 11, flowers: 0.14, thick: true })
    }
    for (let i = 0; i < 4; i++)
      leafPix(S2, c[0], c[1], c[2] + rng(-0.9, 0.9), rng(22, 34), rng(6, 9), i === 1 ? 0 : 1, (Math.cos(c[2]) >= 0 ? 1 : -1) * rng(2, 5))
  })

  seed = 900
  for (let x = 40; x < GW - 40; x += Math.round(rng(22, 40)))
    frond(S2, x, GH, -Math.PI / 2 + rng(-0.55, 0.55), Math.round(rng(18, 30)), 0.04)
  for (let x = 50; x < GW - 50; x += Math.round(rng(50, 90))) {
    const a = -Math.PI / 2 + rng(-0.6, 0.6)
    leafPix(S2, x, GH + 1, a, rng(16, 24), rng(5, 7.5), 1, (Math.cos(a) >= 0 ? 1 : -1) * rng(1, 5))
  }
  // big elephant-ear leaves hanging from the top
  seed = 950
  for (let x = 70; x < GW - 70; x += Math.round(rng(55, 95))) {
    const a = Math.PI / 2 + rng(-0.5, 0.5)
    leafPix(S2, x, -1, a, rng(18, 30), rng(5, 8), 1, (Math.cos(a) >= 0 ? 1 : -1) * rng(1, 5))
  }
  // lush growth hanging in from the sides
  const sideF = { grav: 0.05, sway: 0.08, every: 3, leaf: [7, 15], spread: [0.55, 1.15], fat: 0.38, slit: 0.25, tip: 11, flowers: 0.1, thick: true }
  for (let y = 60; y < GH - 60; y += Math.round(rng(36, 64))) {
    branch(S2, -1, y, rng(-0.2, 0.4), Math.round(rng(14, 26)), sideF)
    branch(S2, GW, y + rng(-10, 10), Math.PI + rng(-0.4, 0.2), Math.round(rng(14, 26)), sideF)
  }

  // ---- plank sign hanging in the top-left, behind the front vines ----
  if (o.text) {
    const font = PIXFONT
    const text = o.text
    const tw = text.length * 4 - 1, plx = 44, plw = tw + 8
    rect(plx, 0, plw, 9, K.wood[0])
    rect(plx + 1, 0, plw - 2, 8, K.wood[2])
    rect(plx + 1, 0, plw - 2, 1, K.wood[1])
    rect(plx + 1, 7, plw - 2, 1, K.wood[3])
    for (let i = 0; i < 6; i++) dot(plx + 3 + Math.floor(hash(i, 3) * (plw - 6)), 1 + (i % 6), K.wood[3])
    dot(plx + 1, 1, K.wood[0]); dot(plx + plw - 2, 1, K.wood[0])
    for (let i = 0; i < text.length; i++) {
      const g = font[text[i]]
      if (!g) continue
      for (let r = 0; r < 5; r++)
        for (let c = 0; c < 3; c++)
          if (g[r * 3 + c] === "1") { dot(plx + 4 + i * 4 + c, 2 + r, K.wood[0]); dot(plx + 4 + i * 4 + c, 1 + r, K.wtext) }
    }
  }
  flush()

  flush()
}

// ---- SACRED: temple gate. Gold flower-of-life lattice on indigo, with great mandalas, fans and a
// lotus that open into the window area as fading gold line-work (click-through), plus a halo wash. ----
function hexagram(ctx, cx, cy, R, c, lw) {
  ctx.beginPath()
  for (let k = 0; k < 2; k++)
    for (let i = 0; i < 3; i++) {
      const a = -Math.PI / 2 + (k ? Math.PI / 3 : 0) + i * 2 * Math.PI / 3
      const x = cx + Math.cos(a) * R, y = cy + Math.sin(a) * R
      if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y)
      if (i === 2) ctx.closePath()
    }
  ctx.lineWidth = lw; ctx.strokeStyle = c; ctx.stroke()
}
function glowDisc(ctx, x, y, r, c, a) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r)
  g.addColorStop(0, rgba(c, a)); g.addColorStop(1, rgba(c, 0))
  ctx.fillStyle = g; ctx.fillRect(x - r, y - r, 2 * r, 2 * r)
}
// Gold line-work around the origin that fades out with distance. mode 0: flower-of-life lattice
// (corners), mode 1: twelve-circle flower with spokes (edge midpoints). Only the part with
// x >= -r and y >= -r is built, so mirror/rotate before calling.
function mandala(ctx, R, K, mode) {
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, R)
  g.addColorStop(0, rgba(K.gold, 0.95)); g.addColorStop(0.5, rgba(K.gold, 0.5)); g.addColorStop(1, rgba(K.gold, 0))
  ctx.strokeStyle = g; ctx.fillStyle = g; ctx.lineWidth = 1
  ctx.beginPath()
  if (mode === 0) {
    const r = 22, dy = r * 0.866, lim = (R - r * 0.4) * (R - r * 0.4)
    for (let j = 0; j <= 8; j++)
      for (let i = -Math.ceil(j / 2) - 1; i <= 9; i++) {
        const x = r * (i + j / 2), y = dy * j
        if (x < -r || x * x + y * y > lim) continue
        ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, Math.PI * 2)
      }
  } else {
    const c = R * 0.27
    for (let k = 0; k < 12; k++) {
      const a = k * Math.PI / 6, x = Math.cos(a) * c, y = Math.sin(a) * c
      ctx.moveTo(x + c, y); ctx.arc(x, y, c, 0, Math.PI * 2)
    }
  }
  ctx.stroke()
  ctx.beginPath()
  for (const f of [0.2, 0.47, 0.74, 0.97]) { ctx.moveTo(R * f, 0); ctx.arc(0, 0, R * f, 0, Math.PI * 2) }
  ctx.stroke()
  ctx.lineWidth = 0.6; ctx.beginPath()
  for (let k = 0; k < 24; k++) {
    const a = k * Math.PI / 12
    ctx.moveTo(Math.cos(a) * R * 0.2, Math.sin(a) * R * 0.2); ctx.lineTo(Math.cos(a) * R * 0.97, Math.sin(a) * R * 0.97)
  }
  ctx.stroke()
  ctx.beginPath()
  for (let k = 0; k < 24; k++) {
    const a = k * Math.PI / 12 + Math.PI / 24, x = Math.cos(a) * R * 0.6, y = Math.sin(a) * R * 0.6
    ctx.moveTo(x + 1.6, y); ctx.arc(x, y, 1.6, 0, Math.PI * 2)
  }
  ctx.fill()
}
function lotus(ctx, cx, cy, K) {
  ctx.save(); ctx.translate(cx, cy); ctx.scale(1.3, 1.3)
  const layers = [[11, 1.45, 96, 14], [9, 1.1, 78, 13], [7, 0.78, 62, 12], [5, 0.44, 46, 10]]
  layers.forEach((L, li) => {
    for (let i = 0; i < L[0]; i++) {
      const a = L[0] === 1 ? 0 : -L[1] + 2 * L[1] * i / (L[0] - 1), len = L[2], w = L[3]
      ctx.save(); ctx.rotate(a)
      ctx.beginPath(); ctx.moveTo(0, 0)
      ctx.bezierCurveTo(-w, -len * 0.3, -w * 0.7, -len * 0.78, 0, -len)
      ctx.bezierCurveTo(w * 0.7, -len * 0.78, w, -len * 0.3, 0, 0)
      const g = ctx.createLinearGradient(0, 0, 0, -len)
      g.addColorStop(0, rgba(K.dark, 0.85)); g.addColorStop(1, rgba(li % 2 ? K.mid : K.gold, li % 2 ? 0.55 : 0.22))
      ctx.fillStyle = g; ctx.fill()
      ctx.lineWidth = 1; ctx.strokeStyle = rgba(li ? K.hi : K.gold, 0.9 - li * 0.1); ctx.stroke()
      ctx.beginPath(); ctx.moveTo(0, -len * 0.18); ctx.lineTo(0, -len * 0.72)
      ctx.lineWidth = 0.6; ctx.strokeStyle = rgba(K.gold, 0.5); ctx.stroke()
      ctx.restore()
    }
  })
  glowDisc(ctx, 0, -14, 30, K.hi, 0.55)
  dotShape(ctx, 0, -14, 3.2, K.hi)
  ctx.restore()
}
function sacred(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { dark: p.dark, mid: mix(p.dark, p.accent, 0.3), gold: p.accent, hi: lighter(p.accent, 1.5) }
    : { dark: "#0a0820", mid: "#241a66", gold: "#d9b45a", hi: "#fff0b3" }

  // halo wash spilling inward from the rim (the band is painted over its outer half)
  rrPath(ctx, BAND, BAND, W - 2 * BAND, H - 2 * BAND, 7)
  ctx.strokeStyle = K.gold
  for (let i = 0; i < 16; i++) { ctx.globalAlpha = 0.012; ctx.lineWidth = 100 - i * 6; ctx.stroke() }
  ctx.globalAlpha = 1

  band(ctx, W, H, K.dark, 14, 6, false)

  ctx.save(); bandClip(ctx, W, H, 14, 6)
  const r = 7, dy = r * 0.866
  ctx.beginPath()
  const ring = (cx, cy) => { ctx.moveTo(cx + r, cy); ctx.arc(cx, cy, r, 0, Math.PI * 2, false) }
  for (let j = 0; j < 4; j++) {
    const off = j * dy + 1, sh = (j % 2) * r / 2
    for (let x = -r + sh; x < W + r; x += r) { ring(x, off); ring(x, H - off) }
    for (let y = -r + sh; y < H + r; y += r) { ring(off, y); ring(W - off, y) }
  }
  ctx.lineWidth = 0.8; ctx.strokeStyle = rgba(K.gold, 0.34); ctx.stroke()
  rrPath(ctx, BAND - 3.5, BAND - 3.5, W - 2 * BAND + 7, H - 2 * BAND + 7, 8)
  ctx.lineWidth = 5; ctx.strokeStyle = rgba(K.dark, 0.92); ctx.stroke()
  ctx.restore()

  rrPath(ctx, 2.5, 2.5, W - 5, H - 5, 12)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.85); ctx.stroke()
  rrPath(ctx, BAND - 3.5, BAND - 3.5, W - 2 * BAND + 7, H - 2 * BAND + 7, 8)
  glowStroke(ctx, K.gold, 1.3, 7, rgba(K.gold, 0.8))

  // great mandalas open from the four corners; half-mandalas from the top and side midpoints
  for (const c of [[0, 0, 1, 1], [W, 0, -1, 1], [0, H, 1, -1], [W, H, -1, -1]]) {
    ctx.save(); ctx.translate(c[0], c[1]); ctx.scale(c[2], c[3])
    glowDisc(ctx, 0, 0, 190, K.mid, 0.55)
    mandala(ctx, 185, K, 0)
    ctx.restore()
  }
  for (const e of [[W / 2, 0, 0], [W, H / 2, Math.PI / 2], [0, H / 2, -Math.PI / 2]]) {
    ctx.save(); ctx.translate(e[0], e[1]); ctx.rotate(e[2])
    glowDisc(ctx, 0, 0, 140, K.mid, 0.45)
    mandala(ctx, 125, K, 1)
    ctx.restore()
  }
  lotus(ctx, W / 2, H - 6, K)

  // seed-of-life rosettes in the corners, three-circle venn at the edge midpoints
  const disc = (cx, cy, R) => {
    ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fillStyle = K.dark; ctx.fill()
    ctx.lineWidth = 1.2; ctx.strokeStyle = K.gold; ctx.stroke()
  }
  const rosette = (cx, cy) => {
    disc(cx, cy, 10.2)
    const s = 3.7
    ctx.beginPath()
    ctx.moveTo(cx + s, cy); ctx.arc(cx, cy, s, 0, Math.PI * 2)
    for (let i = 0; i < 6; i++) {
      const x = cx + Math.cos(i * Math.PI / 3) * s, y = cy + Math.sin(i * Math.PI / 3) * s
      ctx.moveTo(x + s, y); ctx.arc(x, y, s, 0, Math.PI * 2)
    }
    ctx.lineWidth = 0.9; ctx.strokeStyle = K.hi; ctx.stroke()
    dotShape(ctx, cx, cy, 1.1, K.hi)
  }
  rosette(11, 11); rosette(W - 11, 11); rosette(11, H - 11); rosette(W - 11, H - 11)
  const venn = (cx, cy) => {
    disc(cx, cy, 9.6)
    ctx.beginPath()
    for (let i = 0; i < 3; i++) {
      const a = -Math.PI / 2 + i * 2 * Math.PI / 3
      const x = cx + Math.cos(a) * 2.4, y = cy + Math.sin(a) * 2.4
      ctx.moveTo(x + 4.6, y); ctx.arc(x, y, 4.6, 0, Math.PI * 2)
    }
    ctx.lineWidth = 0.9; ctx.strokeStyle = K.hi; ctx.stroke()
  }
  venn(W / 2, 11); venn(11, H / 2); venn(W - 11, H / 2)

  // label
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 3.5, tw = spacedWidth(ctx, t, sp), x0 = 40
    pill(ctx, x0 - 4, 3, tw + 38, 17, K.dark, K.gold, 1)
    hexagram(ctx, x0 + 9, 11.5, 6, K.gold, 1)
    ctx.fillStyle = K.hi
    spaced(ctx, t, x0 + 22, 15, sp, "left")
  }
}

// ---- KAWAII: pastel dreamland. Stitched ribbon with scalloped edge and sprinkles, plus a rainbow,
// fluffy clouds, a bunting garland, bubbles and a peeking cat that overlap into the window area
// (click-through). ----
function bow(ctx, x, y, s, fill, edge) {
  const loop = (dir) => {
    ctx.beginPath(); ctx.moveTo(x, y)
    ctx.bezierCurveTo(x + dir * s * 0.5, y - s * 1.1, x + dir * s * 1.7, y - s * 1.0, x + dir * s * 1.6, y)
    ctx.bezierCurveTo(x + dir * s * 1.7, y + s * 1.0, x + dir * s * 0.5, y + s * 1.1, x, y)
    ctx.fillStyle = fill; ctx.fill(); ctx.lineWidth = 0.9; ctx.strokeStyle = edge; ctx.stroke()
  }
  for (const d of [-1, 1]) {
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d * s * 0.5, y + s * 1.9); ctx.lineTo(x + d * s * 1.1, y + s * 1.5); ctx.lineTo(x + d * s * 0.5, y + s * 0.3)
    ctx.closePath(); ctx.fillStyle = fill; ctx.fill(); ctx.lineWidth = 0.9; ctx.strokeStyle = edge; ctx.stroke()
  }
  loop(-1); loop(1)
  dotShape(ctx, x, y, s * 0.42, fill)
  ctx.lineWidth = 0.9; ctx.strokeStyle = edge; ctx.stroke()
}
function catFace(ctx, cx, cy, R, face, edge, ink, blush) {
  for (const d of [-1, 1]) {
    ctx.beginPath()
    ctx.moveTo(cx + d * R * 0.95, cy - R * 0.2); ctx.lineTo(cx + d * R * 0.75, cy - R * 1.15); ctx.lineTo(cx + d * R * 0.1, cy - R * 0.85)
    ctx.closePath(); ctx.fillStyle = face; ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = edge; ctx.stroke()
    ctx.beginPath()
    ctx.moveTo(cx + d * R * 0.78, cy - R * 0.4); ctx.lineTo(cx + d * R * 0.68, cy - R * 0.92); ctx.lineTo(cx + d * R * 0.3, cy - R * 0.74)
    ctx.closePath(); ctx.fillStyle = blush; ctx.fill()
  }
  ctx.beginPath(); ctx.arc(cx, cy, R, 0, Math.PI * 2); ctx.fillStyle = face; ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = edge; ctx.stroke()
  dotShape(ctx, cx - R * 0.42, cy - R * 0.05, R * 0.14, ink); dotShape(ctx, cx + R * 0.42, cy - R * 0.05, R * 0.14, ink)
  dotShape(ctx, cx - R * 0.37, cy - R * 0.1, R * 0.05, face); dotShape(ctx, cx + R * 0.47, cy - R * 0.1, R * 0.05, face)
  dotShape(ctx, cx - R * 0.68, cy + R * 0.3, R * 0.17, blush); dotShape(ctx, cx + R * 0.68, cy + R * 0.3, R * 0.17, blush)
  ctx.beginPath(); ctx.arc(cx - R * 0.12, cy + R * 0.22, R * 0.12, 0, Math.PI); ctx.arc(cx + R * 0.12, cy + R * 0.22, R * 0.12, 0, Math.PI)
  ctx.lineWidth = Math.max(0.8, R * 0.08); ctx.strokeStyle = ink; ctx.stroke()
  if (R > 14) {
    ctx.beginPath()
    for (const d of [-1, 1]) for (const k of [-1, 0, 1]) {
      ctx.moveTo(cx + d * R * 0.95, cy + R * 0.25 + k * R * 0.12); ctx.lineTo(cx + d * R * 1.5, cy + R * 0.18 + k * R * 0.3)
    }
    ctx.lineWidth = 0.9; ctx.strokeStyle = edge; ctx.stroke()
  }
}
function cloud(ctx, x, y, s, fill, shade, edge) {
  const puffs = [[-1.9, 0.2, 0.9], [-0.9, -0.4, 1.2], [0.4, -0.7, 1.45], [1.6, -0.2, 1.1], [2.5, 0.25, 0.8]]
  const body = () => {
    ctx.beginPath()
    for (const q of puffs) { ctx.moveTo(x + q[0] * s + q[2] * s, y + q[1] * s); ctx.arc(x + q[0] * s, y + q[1] * s, q[2] * s, 0, Math.PI * 2) }
    ctx.rect(x - 1.9 * s, y, 4.4 * s, s * 0.9)
  }
  ctx.save(); ctx.translate(0, s * 0.18); body(); ctx.fillStyle = shade; ctx.fill(); ctx.restore()
  body(); ctx.fillStyle = fill; ctx.fill()
  ctx.beginPath(); ctx.arc(x + 0.4 * s, y - 0.7 * s, 1.45 * s, Math.PI * 1.15, Math.PI * 1.7)
  ctx.lineWidth = Math.max(1, s * 0.16); ctx.lineCap = "round"; ctx.strokeStyle = edge; ctx.stroke()
}
function kawaii(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow ? {
    base: pastel(p.magenta, 0.72), edge: pastel(p.magenta, 0.35), white: pastel(p.bright, 0.7),
    ink: mix(p.accent, p.dark, 0.5), blush: pastel(p.red, 0.45), shade: pastel(p.cyan, 0.6),
    sprinkle: [pastel(p.magenta, 0.4), pastel(p.green, 0.5), pastel(p.blue, 0.5), pastel(p.byellow, 0.4), pastel(p.cyan, 0.45)],
    rainbow: [pastel(p.red, 0.45), pastel(p.orange, 0.45), pastel(p.byellow, 0.45), pastel(p.green, 0.45), pastel(p.cyan, 0.45), pastel(p.magenta, 0.45)]
  } : {
    base: "#ffd9ea", edge: "#ff9fc8", white: "#fffafc", ink: "#8a3f6e", blush: "#ff9db8", shade: "#dff0ff",
    sprinkle: ["#ff8fc0", "#8fe6c0", "#b9a6ff", "#ffe27a", "#8fd0ff"],
    rainbow: ["#ff9db8", "#ffc58f", "#ffe27a", "#9ae6b8", "#8fd0ff", "#c4b0ff"]
  }

  // soft pastel haze spilling inward from the ribbon
  rrPath(ctx, 9, 9, W - 18, H - 18, 12)
  ctx.strokeStyle = K.edge
  for (let i = 0; i < 12; i++) { ctx.globalAlpha = 0.022; ctx.lineWidth = 84 - i * 6; ctx.stroke() }
  ctx.globalAlpha = 1

  band(ctx, W, H, K.base, 18, 9, false)

  // stitched line along the outside
  ctx.lineWidth = 1.4; ctx.lineCap = "round"; ctx.strokeStyle = K.white
  ctx.beginPath()
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 20; t < L - 24; t += 7) {
      const a = edgeXY(W, H, e, t, 4.5), b = edgeXY(W, H, e, t + 3.6, 4.5)
      ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1])
    }
  }
  ctx.stroke()

  // scalloped inner edge: outlined bumps on the inside of the ribbon
  const bump = (cx, cy, r) => { ctx.moveTo(cx + r, cy); ctx.arc(cx, cy, r, 0, Math.PI * 2) }
  for (const pass of [0, 1]) {
    ctx.beginPath()
    for (let e = 0; e < 4; e++) {
      const L = edgeLen(W, H, e)
      for (let t = 22; t < L - 22; t += 8) { const q = edgeXY(W, H, e, t, 19.5); bump(q[0], q[1], pass ? 4.2 : 5) }
    }
    ctx.fillStyle = pass ? K.white : K.edge; ctx.fill()
  }

  // sprinkles between stitches and scallops
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 44, i = 0; t < L - 40; t += 24 + Math.floor(hash(t, e) * 10), i++) {
      const q = edgeXY(W, H, e, t, 11.5 + (hash(i, e + 3) - 0.5) * 3)
      const c = K.sprinkle[Math.floor(hash(t * 0.7, e + 11) * 5)], k = Math.floor(hash(t, e * 7 + 2) * 4)
      if (k === 0) heartShape(ctx, q[0], q[1], 3, c)
      else if (k === 1) starShape(ctx, q[0], q[1], 3.6, c)
      else if (k === 2) sparkleShape(ctx, q[0], q[1], 4.2, c)
      else dotShape(ctx, q[0], q[1], 2, c)
    }
  }

  // ---- into the window area ----
  // rainbow arching over the top-right corner, a cloud at each foot
  const rcx = W - 4, rcy = 4
  ctx.lineCap = "butt"
  K.rainbow.forEach((c, i) => {
    ctx.beginPath(); ctx.arc(rcx, rcy, 190 - i * 13, Math.PI / 2, Math.PI)
    ctx.lineWidth = 13.6; ctx.strokeStyle = c; ctx.stroke()
  })
  cloud(ctx, rcx - 182, 26, 14, K.white, K.shade, K.edge)
  cloud(ctx, rcx - 28, 180, 12, K.white, K.shade, K.edge)

  // clouds rising from the bottom edge
  for (let x = 120, i = 0; x < W - 60; x += 230 + Math.floor(hash(i, 5) * 170), i++) {
    if (Math.abs(x - (W - 110)) < 120) continue
    cloud(ctx, x, H - 22, 9 + hash(i, 9) * 6, K.white, K.shade, K.edge)
  }

  // bunting along the top: a sagging string with pennants and hearts
  const bx0 = 250, bx1 = W - 340
  for (let seg = 0; seg < 5; seg++) {
    const a = bx0 + (bx1 - bx0) * seg / 5, b = bx0 + (bx1 - bx0) * (seg + 1) / 5, sag = 34
    const at = (t) => [a + (b - a) * t, 18 + Math.sin(Math.PI * t) * sag]
    ctx.beginPath(); ctx.moveTo(a, 18)
    for (let t = 0.05; t <= 1.001; t += 0.05) { const q = at(t); ctx.lineTo(q[0], q[1]) }
    ctx.lineWidth = 1.2; ctx.strokeStyle = K.edge; ctx.stroke()
    for (let k = 1; k <= 6; k++) {
      const t = k / 7, q = at(t), c = K.sprinkle[(seg + k) % 5], w = 8
      ctx.beginPath(); ctx.moveTo(q[0] - w, q[1]); ctx.lineTo(q[0] + w, q[1]); ctx.lineTo(q[0], q[1] + 17)
      ctx.closePath(); ctx.fillStyle = c; ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = K.white; ctx.stroke()
      if (k % 2) heartShape(ctx, q[0], q[1] + 5.5, 2.2, K.white)
      else dotShape(ctx, q[0], q[1] + 5, 1.8, K.white)
    }
  }

  // bubbles and sparkles drifting in from the side ribbons
  for (let e = 1; e < 4; e += 2) {
    const L = edgeLen(W, H, e)
    for (let t = 150, i = 0; t < L - 140; t += 64 + Math.floor(hash(t, e + 21) * 70), i++) {
      const q = edgeXY(W, H, e, t, 28 + hash(i, e) * 46), r = 4 + hash(t, e + 4) * 8
      const cx = q[0], cy = q[1], c = K.sprinkle[i % 5]
      if (i % 3 === 2) { sparkleShape(ctx, cx, cy, r * 0.9, c); continue }
      ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.globalAlpha = 0.28; ctx.fillStyle = c; ctx.fill(); ctx.globalAlpha = 1
      ctx.lineWidth = 1.2; ctx.strokeStyle = c; ctx.stroke()
      ctx.beginPath(); ctx.arc(cx, cy, r * 0.62, Math.PI * 1.15, Math.PI * 1.55)
      ctx.lineWidth = 1.3; ctx.strokeStyle = K.white; ctx.stroke()
    }
  }

  // corners
  starShape(ctx, 11, 11, 6.5, K.sprinkle[3])
  ctx.lineWidth = 0.8; ctx.strokeStyle = K.edge; ctx.stroke()
  bow(ctx, 20, H - 22, 8, K.sprinkle[2], K.ink)
  bow(ctx, W - 20, H - 150, 6, K.sprinkle[0], K.ink)

  // the cat peeks over the bottom ribbon, paws on the edge
  const cxc = W - 110, cyc = H - 10
  catFace(ctx, cxc, cyc, 28, K.white, K.edge, K.ink, K.blush)
  for (const d of [-1, 1]) {
    ctx.beginPath(); ctx.ellipse(cxc + d * 20, H - 4, 9, 6, 0, 0, Math.PI * 2)
    ctx.fillStyle = K.white; ctx.fill(); ctx.lineWidth = 1; ctx.strokeStyle = K.edge; ctx.stroke()
    dotShape(ctx, cxc + d * 20, H - 3.5, 2.6, K.blush)
  }

  // label
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 2.5, tw = spacedWidth(ctx, t, sp), x0 = 40
    pill(ctx, x0 - 6, 3, tw + 34, 17, K.white, K.edge, 1.5)
    heartShape(ctx, x0 + 3, 11.5, 3.2, K.edge)
    ctx.fillStyle = K.ink
    spaced(ctx, t, x0 + 13, 15, sp, "left")
  }
}

// ---- CELESTIAL: deep-space frame. Star band and constellations, plus nebula washes, a big crescent
// moon, a ringed planet, a shooting star and drifting stars that open into the window area
// (click-through). ----
function moonPhase(ctx, cx, cy, r, lit, K, dx) {
  ctx.save()
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.clip()
  ctx.fillStyle = K.dark2; ctx.fillRect(cx - r, cy - r, 2 * r, 2 * r)
  if (dx > 0) {
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.fillStyle = K.moon; ctx.fill()
    if (dx < 2 * r) { ctx.beginPath(); ctx.arc(cx - dx, cy, r, 0, Math.PI * 2); ctx.fillStyle = K.dark2; ctx.fill() }
  }
  ctx.restore()
  ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2)
  ctx.lineWidth = 0.8; ctx.strokeStyle = rgba(K.moon, 0.7); ctx.stroke()
}
function brightStar(ctx, x, y, R, K) {
  glowDisc(ctx, x, y, R * 3.2, K.star, 0.35)
  sparkleShape(ctx, x, y, R * 1.6, rgba(K.star, 0.55))
  ctx.beginPath(); ctx.moveTo(x - R * 2.4, y); ctx.lineTo(x + R * 2.4, y); ctx.moveTo(x, y - R * 2.4); ctx.lineTo(x, y + R * 2.4)
  ctx.lineWidth = 0.6; ctx.strokeStyle = rgba(K.star, 0.5); ctx.stroke()
  dotShape(ctx, x, y, R * 0.55, K.star)
}
function celestial(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { dark: p.dark, dark2: mix(p.bg, p.accent, 0.15), star: p.bright, gold: p.byellow, line: lighter(p.accent, 1.3), moon: mix(p.bright, p.byellow, 0.35),
        neb1: mix(p.magenta, p.dark, 0.35), neb2: mix(p.cyan, p.dark, 0.35), planet: mix(p.orange, p.dark, 0.35), planet2: mix(p.magenta, p.dark, 0.5) }
    : { dark: "#060919", dark2: "#151b4a", star: "#fff6d8", gold: "#f2d27a", line: "#8fb0ff", moon: "#fbf1cf",
        neb1: "#6a35c8", neb2: "#2d6bd6", planet: "#c0733d", planet2: "#6c3a8c" }

  // nebula washes bleeding in from the sky band (the band is painted over their outer part)
  const nebs = [[0.12, 0, K.neb1, 260], [0.4, 1, K.neb2, 220], [0.74, 0, K.neb1, 280], [0.93, 1, K.neb2, 230]]
  for (const n of nebs) glowDisc(ctx, W * n[0], n[1] ? H : 0, n[3], n[2], 0.36)
  glowDisc(ctx, 0, H * 0.55, 230, K.neb2, 0.3); glowDisc(ctx, W, H * 0.4, 240, K.neb1, 0.3)

  const g = ctx.createLinearGradient(0, 0, W, H)
  g.addColorStop(0, K.dark); g.addColorStop(0.5, K.dark2); g.addColorStop(1, K.dark)
  band(ctx, W, H, g, 16, 7, false)

  ctx.save(); bandClip(ctx, W, H, 16, 7)
  // small stars
  ctx.beginPath()
  const faint = []
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 6, i = 0; t < L - 6; t += 9, i++) {
      const h1 = hash(t, e * 3 + 1), h2 = hash(e + 7, t * 0.31)
      const q = edgeXY(W, H, e, t + h1 * 8, 2 + h2 * 18)
      if (h1 > 0.93) faint.push(q)
      else { ctx.moveTo(q[0] + 0.5 + h2, q[1]); ctx.arc(q[0], q[1], 0.5 + h2 * 0.8, 0, Math.PI * 2) }
    }
  }
  ctx.fillStyle = rgba(K.star, 0.75); ctx.fill()
  for (const q of faint) sparkleShape(ctx, q[0], q[1], 3.6, K.star)

  // constellations
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let c = 0; c < 3; c++) {
      let t = L * (0.18 + 0.3 * c) + hash(e, c) * 60
      const pts = []
      for (let i = 0; i < 5; i++) {
        pts.push(edgeXY(W, H, e, t, 5 + hash(e * 5 + c, i) * 12))
        t += 22 + hash(i, c + e * 4) * 18
      }
      ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1])
      for (let i = 1; i < 5; i++) ctx.lineTo(pts[i][0], pts[i][1])
      ctx.lineWidth = 0.7; ctx.strokeStyle = rgba(K.line, 0.45); ctx.stroke()
      for (let i = 0; i < 5; i++) dotShape(ctx, pts[i][0], pts[i][1], i % 2 ? 1.4 : 1.9, K.star)
    }
  }
  ctx.restore()

  rrPath(ctx, 15.5, 15.5, W - 31, H - 31, 8)
  glowStroke(ctx, rgba(K.line, 0.85), 1.2, 8, rgba(K.line, 0.8))
  rrPath(ctx, 1.5, 1.5, W - 3, H - 3, 15)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.7); ctx.stroke()

  // ---- into the window area ----
  // drifting stars that thin out away from the edge
  ctx.beginPath()
  const twinkle = []
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 20, i = 0; t < L - 20; t += 11, i++) {
      const h1 = hash(t * 1.7, e * 5 + 2), h2 = hash(e + 3, t * 0.53), h3 = hash(t, e + 17)
      const depth = 22 + h2 * h2 * 120
      if (h1 > 0.5 - depth / 400) continue
      const q = edgeXY(W, H, e, t + h3 * 10, depth)
      if (h3 > 0.93) twinkle.push(q)
      else { const r = 0.5 + (1 - depth / 140) * h3 * 1.4; ctx.moveTo(q[0] + r, q[1]); ctx.arc(q[0], q[1], r, 0, Math.PI * 2) }
    }
  }
  ctx.fillStyle = rgba(K.star, 0.7); ctx.fill()
  for (const q of twinkle) brightStar(ctx, q[0], q[1], 2.2, K)

  // constellations reaching into the window from the corners
  const figs = [
    [[40, 60], [78, 92], [120, 84], [150, 128], [196, 138], [228, 176]],
    [[W - 50, 70], [W - 96, 56], [W - 140, 96], [W - 184, 88], [W - 214, 128]],
    [[56, H - 56], [96, H - 96], [90, H - 150], [132, H - 168], [170, H - 150]],
    [[W - 60, H - 60], [W - 108, H - 88], [W - 150, H - 74], [W - 178, H - 120], [W - 226, H - 130], [W - 258, H - 100]]
  ]
  figs.forEach((f) => {
    ctx.beginPath(); ctx.moveTo(f[0][0], f[0][1])
    for (let i = 1; i < f.length; i++) ctx.lineTo(f[i][0], f[i][1])
    ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.line, 0.5); ctx.stroke()
    f.forEach((q, i) => { if (i % 2 === 0) brightStar(ctx, q[0], q[1], 2.4, K); else dotShape(ctx, q[0], q[1], 1.8, K.star) })
  })

  // shooting star
  const sx = W * 0.64, sy = 92
  const tg = ctx.createLinearGradient(sx + 170, sy - 62, sx, sy)
  tg.addColorStop(0, rgba(K.star, 0)); tg.addColorStop(1, rgba(K.star, 0.9))
  ctx.beginPath(); ctx.moveTo(sx + 170, sy - 64); ctx.lineTo(sx, sy - 1.2); ctx.lineTo(sx, sy + 1.2); ctx.closePath()
  ctx.fillStyle = tg; ctx.fill()
  brightStar(ctx, sx, sy, 3, K)

  // big crescent moon with a halo, top right
  const mx = W - 150, my = 118, mr = 52
  glowDisc(ctx, mx, my, 170, K.moon, 0.22)
  ctx.save()
  ctx.beginPath(); ctx.arc(mx, my, mr, 0, Math.PI * 2); ctx.clip()
  const mg = ctx.createLinearGradient(mx - mr, my - mr, mx + mr, my + mr)
  mg.addColorStop(0, K.moon); mg.addColorStop(1, mix(K.moon, K.gold, 0.6))
  ctx.beginPath(); ctx.rect(mx - 2 * mr, my - 2 * mr, 4 * mr, 4 * mr); ctx.arc(mx + mr * 0.42, my - mr * 0.18, mr * 0.84, 0, Math.PI * 2, true)
  ctx.fillStyle = mg; ctx.fill()
  ctx.restore()
  ctx.beginPath(); ctx.arc(mx, my, mr + 12, 0.35 * Math.PI, 1.55 * Math.PI)
  ctx.lineWidth = 0.8; ctx.setLineDash && ctx.setLineDash([2, 5]); ctx.strokeStyle = rgba(K.moon, 0.5); ctx.stroke()
  ctx.setLineDash && ctx.setLineDash([])
  sparkleShape(ctx, mx + 70, my + 26, 6, K.moon); sparkleShape(ctx, mx - 34, my - 62, 4, K.star)

  // ringed planet, bottom left
  const px = 170, py = H - 118, pr = 30
  glowDisc(ctx, px, py, 110, K.planet, 0.2)
  const ring = (front) => {
    ctx.save(); ctx.translate(px, py); ctx.rotate(-0.38); ctx.scale(1, 0.28)
    for (const rr of [pr * 1.55, pr * 1.85]) {
      ctx.beginPath(); ctx.arc(0, 0, rr, front ? 0 : Math.PI, front ? Math.PI : Math.PI * 2)
      ctx.lineWidth = rr > pr * 1.7 ? 4 : 7; ctx.strokeStyle = rgba(rr > pr * 1.7 ? K.gold : K.moon, 0.75); ctx.stroke()
    }
    ctx.restore()
  }
  ring(false)
  ctx.save(); ctx.beginPath(); ctx.arc(px, py, pr, 0, Math.PI * 2); ctx.clip()
  const pg = ctx.createRadialGradient(px - pr * 0.4, py - pr * 0.4, 2, px, py, pr * 1.1)
  pg.addColorStop(0, mix(K.planet, "#ffffff", 0.35)); pg.addColorStop(0.55, K.planet); pg.addColorStop(1, K.planet2)
  ctx.fillStyle = pg; ctx.fillRect(px - pr, py - pr, 2 * pr, 2 * pr)
  ctx.lineWidth = 3; ctx.strokeStyle = rgba(K.planet2, 0.55)
  for (const b of [-0.35, 0.05, 0.4]) { ctx.beginPath(); ctx.moveTo(px - pr, py + b * pr); ctx.quadraticCurveTo(px, py + b * pr + 7, px + pr, py + b * pr); ctx.stroke() }
  ctx.restore()
  ring(true)
  dotShape(ctx, px + 78, py - 52, 4, K.moon); dotShape(ctx, px - 92, py + 34, 2.6, K.line)

  // moon phases along the bottom, big crescent next to the label
  const mpx = W / 2 - 55
  for (let i = 0; i < 5; i++) {
    ctx.beginPath(); ctx.arc(mpx + i * 27, H - 11, 6.5, 0, Math.PI * 2); ctx.fillStyle = K.dark; ctx.fill()
    moonPhase(ctx, mpx + i * 27, H - 11, 5.5, 0, K, [0, 3, 5.5, 8, 12][i])
  }
  ctx.beginPath(); ctx.arc(30, 11, 9, 0, Math.PI * 2); ctx.fillStyle = K.dark; ctx.fill()
  moonPhase(ctx, 30, 11, 7.5, 0, K, 5)
  sparkleShape(ctx, W - 14, 10, 5, K.gold); sparkleShape(ctx, 14, H - 10, 5, K.gold)

  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0 = 48
    ctx.fillStyle = rgba(K.dark, 0.9); rrPath(ctx, x0 - 8, 3, tw + 16, 17, 8.5); ctx.fill()
    ctx.fillStyle = K.moon
    spaced(ctx, t, x0, 15, sp, "left")
  }
}

// ---- VAPORWAVE: neon frame. Neon double line with checker edge, plus a glow wash, a perspective grid
// floor, a striped sunset sun, palm trees and memphis confetti that open into the window area
// (click-through), a VHS readout and a sun badge label. ----
function palm(ctx, x, y, h, lean, K) {
  const tx = x + lean, ty = y - h
  ctx.beginPath(); ctx.moveTo(x - 5, y); ctx.quadraticCurveTo(x + lean * 0.1, y - h * 0.55, tx - 2, ty)
  ctx.lineTo(tx + 2, ty); ctx.quadraticCurveTo(x + lean * 0.1 + 6, y - h * 0.55, x + 5, y); ctx.closePath()
  ctx.fillStyle = K.silhouette; ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = K.pink; ctx.stroke()
  const fr = [[-2.7, 66], [-2.1, 78], [-1.5, 62], [-0.6, 50], [0.2, 52], [0.8, 64], [1.6, 76], [2.2, 68]]
  for (const f of fr) {
    const a = f[0], L = f[1] * (h / 150)
    const ex = tx + Math.cos(a) * L, ey = ty + Math.sin(a) * L * 0.55 + L * 0.35
    const cx = tx + Math.cos(a) * L * 0.55, cy = ty - L * 0.3 + Math.sin(a) * L * 0.1
    ctx.beginPath(); ctx.moveTo(tx, ty)
    ctx.quadraticCurveTo(cx, cy - 14, ex, ey)
    ctx.quadraticCurveTo(cx, cy + 12, tx, ty + 2)
    ctx.closePath(); ctx.fillStyle = K.silhouette; ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = K.cyan; ctx.stroke()
  }
  dotShape(ctx, tx - 2, ty + 5, 2.6, K.pink); dotShape(ctx, tx + 3, ty + 6, 2.6, K.pink)
}
function vaporwave(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow ? {
    dark: p.dark, purple: mix(p.dark, p.blue, 0.5), pink: vivid(p.magenta), cyan: vivid(p.cyan === "#88c0d0" ? p.accent : p.cyan),
    orange: vivid(p.orange), yellow: vivid(p.byellow), white: p.bright, silhouette: mix(p.dark, p.blue, 0.2)
  } : {
    dark: "#150a33", purple: "#3b1a78", pink: "#ff4fd8", cyan: "#31f2ff", orange: "#ff9a3c", yellow: "#ffe45c", white: "#ffffff", silhouette: "#1c0f45"
  }

  // neon wash: pink from the top, cyan from the bottom, magenta/cyan from the sides
  const wash = (x0, y0, x1, y1, c, a) => {
    const g = ctx.createLinearGradient(x0, y0, x1, y1)
    g.addColorStop(0, rgba(c, a)); g.addColorStop(1, rgba(c, 0))
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H)
  }
  wash(0, 0, 0, 120, K.pink, 0.3); wash(0, H, 0, H - 140, K.cyan, 0.22)
  wash(0, 0, 100, 0, K.pink, 0.18); wash(W, 0, W - 100, 0, K.cyan, 0.18)

  // perspective grid floor along the bottom
  const hy = H - 130, vx = W / 2
  ctx.save()
  ctx.beginPath(); ctx.rect(0, hy, W, H - hy); ctx.clip()
  const fade = ctx.createLinearGradient(0, hy, 0, H)
  fade.addColorStop(0, rgba(K.pink, 0)); fade.addColorStop(1, rgba(K.pink, 0.85))
  ctx.strokeStyle = fade; ctx.lineWidth = 1.2
  ctx.beginPath()
  for (let i = -24; i <= 24; i++) { ctx.moveTo(vx + i * 6, hy); ctx.lineTo(vx + i * 150, H) }
  for (let k = 1; k <= 8; k++) { const y = hy + (H - hy) * Math.pow(k / 8, 1.9); ctx.moveTo(0, y); ctx.lineTo(W, y) }
  ctx.stroke()
  ctx.restore()

  // checker strip on the outside edge
  band(ctx, W, H, K.dark, 12, 5, false)
  ctx.save(); bandClip(ctx, W, H, 12, 5)
  ctx.fillStyle = rgba(K.purple, 0.9)
  ctx.beginPath()
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 0, i = 0; t < L; t += 5, i++) {
      const a = edgeXY(W, H, e, t, 0)
      const r = e === 0 ? [a[0], 0 + (i % 2) * 5, 5, 5] : e === 2 ? [a[0] - 5, H - 5 - (i % 2) * 5, 5, 5]
        : e === 1 ? [W - 5 - (i % 2) * 5, a[1], 5, 5] : [(i % 2) * 5, a[1] - 5, 5, 5]
      ctx.rect(r[0], r[1], r[2], r[3])
    }
  }
  ctx.fill()
  ctx.restore()

  // memphis confetti between the neon lines
  ctx.lineCap = "round"; ctx.lineJoin = "round"
  const cols = [K.pink, K.cyan, K.yellow, K.orange]
  const confetti = (qx, qy, c, k, s) => {
    ctx.strokeStyle = c; ctx.fillStyle = c; ctx.lineWidth = 1.3 * Math.sqrt(s)
    if (k === 0) { ctx.beginPath(); ctx.moveTo(qx - 3 * s, qy + 3 * s); ctx.lineTo(qx, qy - 3 * s); ctx.lineTo(qx + 3 * s, qy + 3 * s); ctx.closePath(); ctx.stroke() }
    else if (k === 1) { ctx.beginPath(); ctx.arc(qx, qy, 2.6 * s, 0, Math.PI * 2); ctx.stroke() }
    else if (k === 2) { ctx.beginPath(); ctx.moveTo(qx - 3 * s, qy); ctx.lineTo(qx + 3 * s, qy); ctx.moveTo(qx, qy - 3 * s); ctx.lineTo(qx, qy + 3 * s); ctx.stroke() }
    else if (k === 3) {
      ctx.beginPath(); ctx.moveTo(qx - 5 * s, qy)
      ctx.quadraticCurveTo(qx - 2.5 * s, qy - 4 * s, qx, qy); ctx.quadraticCurveTo(qx + 2.5 * s, qy + 4 * s, qx + 5 * s, qy); ctx.stroke()
    } else { dotShape(ctx, qx, qy, 1.8 * s, c) }
  }
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 90, i = 0; t < L - 60; t += 30 + Math.floor(hash(t, e + 5) * 20), i++)
      { const q = edgeXY(W, H, e, t, 12.7); confetti(q[0], q[1], cols[Math.floor(hash(t * 0.3, e + 2) * 4)], Math.floor(hash(t, e * 5 + 9) * 5), 1) }
  }

  // neon lines
  const gr = ctx.createLinearGradient(0, 0, W, H)
  gr.addColorStop(0, K.pink); gr.addColorStop(0.5, K.purple); gr.addColorStop(1, K.cyan)
  rrPath(ctx, 8, 8, W - 16, H - 16, 9)
  glowStroke(ctx, gr, 2.2, 11, rgba(K.pink, 0.75))
  const gr2 = ctx.createLinearGradient(W, 0, 0, H)
  gr2.addColorStop(0, K.cyan); gr2.addColorStop(1, K.pink)
  rrPath(ctx, 17.5, 17.5, W - 35, H - 35, 5)
  glowStroke(ctx, gr2, 1.2, 6, rgba(K.cyan, 0.7))

  // ---- into the window area ----
  // big striped sun sinking behind the grid horizon, bottom right
  const sunx = W - 190, sunr = 92
  glowDisc(ctx, sunx, hy, 190, K.pink, 0.3)
  ctx.save()
  ctx.beginPath(); ctx.rect(0, 0, W, hy); ctx.clip()
  ctx.beginPath(); ctx.arc(sunx, hy, sunr, 0, Math.PI * 2); ctx.clip()
  const bg = ctx.createLinearGradient(0, hy - sunr, 0, hy)
  bg.addColorStop(0, K.yellow); bg.addColorStop(0.5, K.orange); bg.addColorStop(1, K.pink)
  ctx.globalAlpha = 0.92; ctx.fillStyle = bg; ctx.fillRect(sunx - sunr, hy - sunr, 2 * sunr, sunr)
  ctx.globalAlpha = 1; ctx.fillStyle = K.dark
  for (let i = 0; i < 7; i++) ctx.fillRect(sunx - sunr, hy - 6 - i * 11, 2 * sunr, 1.5 + i * 0.9)
  ctx.restore()
  ctx.beginPath(); ctx.moveTo(0, hy); ctx.lineTo(W, hy); ctx.lineWidth = 1.4; ctx.strokeStyle = rgba(K.cyan, 0.8); ctx.stroke()

  // palms in the bottom-left corner
  palm(ctx, 60, H - 14, 190, 54, K); palm(ctx, 128, H - 14, 130, -34, K)

  // large memphis shapes drifting in from the top and sides
  for (let t = 200, i = 0; t < W - 260; t += 110 + Math.floor(hash(t, 3) * 90), i++) {
    const c = cols[Math.floor(hash(t * 0.3, 8) * 4)], k = Math.floor(hash(t, 12) * 5)
    confetti(t, 42 + hash(t, 6) * 54, c, k, 2.4 + hash(t, 4) * 1.6)
  }
  for (let e = 1; e < 4; e += 2) {
    const L = edgeLen(W, H, e)
    for (let t = 240, i = 0; t < L - 330; t += 160 + Math.floor(hash(t, e + 9) * 110), i++) {
      const q = edgeXY(W, H, e, t, 44 + hash(t, e) * 50)
      confetti(q[0], q[1], cols[Math.floor(hash(t * 0.3, e + 2) * 4)], Math.floor(hash(t, e * 5 + 9) * 5), 2.2 + hash(t, 4) * 1.4)
    }
  }

  // sunset sun with slats, as the label badge
  const sx = 40, sy = 11.5, sr = 9.5
  ctx.save()
  ctx.beginPath(); ctx.arc(sx, sy, sr, 0, Math.PI * 2); ctx.clip()
  const sg = ctx.createLinearGradient(0, sy - sr, 0, sy + sr)
  sg.addColorStop(0, K.yellow); sg.addColorStop(0.5, K.orange); sg.addColorStop(1, K.pink)
  ctx.fillStyle = sg; ctx.fillRect(sx - sr, sy - sr, 2 * sr, 2 * sr)
  ctx.fillStyle = K.dark
  for (let i = 0; i < 4; i++) ctx.fillRect(sx - sr, sy + 1 + i * 2.6, 2 * sr, 0.6 + i * 0.35)
  ctx.restore()
  if (o.text) {
    setFont(ctx, o, 11, true)
    const t = o.text, sp = 5, tw = spacedWidth(ctx, t, sp), x0 = sx + sr + 8
    ctx.fillStyle = rgba(K.dark, 0.92); rrPath(ctx, x0 - 8, 4, tw + 14, 15, 7.5); ctx.fill()
    ctx.fillStyle = K.pink; spaced(ctx, t, x0 + 1, 15.5, sp, "left")
    ctx.fillStyle = K.white; spaced(ctx, t, x0, 15, sp, "left")
  }

  // VHS readout, bottom right
  setFont(ctx, o, 9, true)
  ctx.fillStyle = rgba(K.dark, 0.92); rrPath(ctx, W - 118, H - 18, 80, 14, 7); ctx.fill()
  ctx.fillStyle = K.cyan
  ctx.beginPath(); ctx.moveTo(W - 110, H - 15); ctx.lineTo(W - 110, H - 7); ctx.lineTo(W - 103, H - 11); ctx.closePath(); ctx.fill()
  spaced(ctx, "PLAY", W - 97, H - 7.5, 3, "left")
  dotShape(ctx, W - 48, H - 11, 2, K.pink)
}

// ---- shared by the motif styles -------------------------------------------------
function seeded(seed) {
  let s = seed >>> 0
  return function (a, b) { s = (s * 1664525 + 1013904223) % 4294967296; return a + (b - a) * (s / 4294967296) }
}

// ---- DEEPSEA: underwater. Wave-lined water band, plus light rays, swaying kelp, corals, a jellyfish,
// a school of fish and rising bubbles that reach into the window area (click-through). ----
function fishShape(ctx, x, y, s, dir, body, fin) {
  ctx.save(); ctx.translate(x, y); ctx.scale(dir * s, s)
  ctx.beginPath(); ctx.moveTo(-9, 0); ctx.lineTo(-15, -6); ctx.lineTo(-13, 0); ctx.lineTo(-15, 6); ctx.closePath()
  ctx.fillStyle = fin; ctx.fill()
  ctx.beginPath(); ctx.moveTo(-10, 0)
  ctx.bezierCurveTo(-5, -9, 7, -8, 11, 0); ctx.bezierCurveTo(7, 8, -5, 9, -10, 0)
  ctx.fillStyle = body; ctx.fill()
  ctx.beginPath(); ctx.moveTo(-2, -6); ctx.lineTo(1, -11); ctx.lineTo(4, -6); ctx.fillStyle = fin; ctx.fill()
  dotShape(ctx, 6, -1.5, 1.4, "#ffffff"); dotShape(ctx, 6.4, -1.5, 0.7, "#06182a")
  ctx.restore()
}
function kelp(ctx, x, y, h, ph, w, K) {
  const n = Math.round(h / 8)
  const pts = []
  for (let i = 0; i <= n; i++) pts.push([x + Math.sin(i * 0.5 + ph) * (4 + i * 0.55), y - i * (h / n)])
  ctx.beginPath(); ctx.moveTo(pts[0][0] - w / 2, pts[0][1])
  for (let i = 1; i <= n; i++) ctx.lineTo(pts[i][0] - w * (1 - i / n) / 2, pts[i][1])
  for (let i = n; i >= 0; i--) ctx.lineTo(pts[i][0] + w * (1 - i / n) / 2, pts[i][1])
  ctx.closePath()
  const g = ctx.createLinearGradient(0, y - h, 0, y)
  g.addColorStop(0, K.kelpLight); g.addColorStop(1, K.kelp)
  ctx.fillStyle = g; ctx.fill()
  for (let i = 2; i < n; i += 3) {
    const q = pts[i], s = i % 2 ? 1 : -1
    leafShape(ctx, q[0], q[1], -Math.PI / 2 + s * 1.0, 18 + (n - i) * 0.6, 4, K.kelp, null)
  }
}
function coral(ctx, rnd, x, y, ang, len, w, depth, col) {
  ctx.lineCap = "round"; ctx.strokeStyle = col
  const ex = x + Math.cos(ang) * len, ey = y + Math.sin(ang) * len
  ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(ex, ey); ctx.lineWidth = w; ctx.stroke()
  if (depth < 4) {
    coral(ctx, rnd, ex, ey, ang - rnd(0.35, 0.7), len * 0.72, w * 0.72, depth + 1, col)
    coral(ctx, rnd, ex, ey, ang + rnd(0.35, 0.7), len * 0.72, w * 0.72, depth + 1, col)
  } else dotShape(ctx, ex, ey, w * 0.9, col)
}
function jellyfish(ctx, x, y, r, K) {
  glowDisc(ctx, x, y, r * 3, K.jelly, 0.25)
  for (let i = -3; i <= 3; i++) {
    ctx.beginPath(); ctx.moveTo(x + i * r * 0.28, y + 2)
    for (let k = 1; k <= 8; k++) ctx.lineTo(x + i * r * 0.28 + Math.sin(k * 0.9 + i) * 4, y + 2 + k * r * 0.5)
    ctx.lineWidth = 1.3; ctx.strokeStyle = rgba(K.jelly, 0.6); ctx.stroke()
  }
  ctx.beginPath(); ctx.moveTo(x - r, y + 2); ctx.bezierCurveTo(x - r, y - r * 1.5, x + r, y - r * 1.5, x + r, y + 2)
  ctx.quadraticCurveTo(x + r * 0.5, y + r * 0.35, x, y + 2); ctx.quadraticCurveTo(x - r * 0.5, y + r * 0.35, x - r, y + 2)
  const g = ctx.createRadialGradient(x, y - r * 0.4, 1, x, y, r * 1.2)
  g.addColorStop(0, rgba("#ffffff", 0.75)); g.addColorStop(0.5, rgba(K.jelly, 0.7)); g.addColorStop(1, rgba(K.jelly, 0.35))
  ctx.fillStyle = g; ctx.fill()
}
function deepsea(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { deep: p.dark, mid: mix(p.dark, p.blue, 0.35), wave: p.cyan, ray: p.cyan, kelp: mix(p.green, p.dark, 0.35), kelpLight: p.green,
        coral1: p.red, coral2: p.magenta, coral3: p.orange, jelly: p.magenta, fish1: p.orange, fish2: p.byellow, fin: p.red, sand: mix(p.byellow, p.dark, 0.45), bub: p.bright }
    : { deep: "#04162a", mid: "#0b4268", wave: "#58d6e0", ray: "#8fe8ff", kelp: "#1d7a58", kelpLight: "#58c28a",
        coral1: "#ff7a6b", coral2: "#ff9fc0", coral3: "#ffb04a", jelly: "#d58cff", fish1: "#ffa23a", fish2: "#ffd84a", fin: "#e8543c", sand: "#8a7a52", bub: "#d8f6ff" }

  // a frame fitted to a small window (bleed > 0) gets a thinner overlap and an outer contour; full screen is unchanged
  const B = o.bleed || 0
  const k = B ? Math.max(0.5, Math.min(1, Math.min(W, H * 1.6) / 1400)) : 1
  ctx.save()
  if (B) { ctx.beginPath(); ctx.rect(0, 0, W, H); ctx.clip() }
  // light rays from the surface
  for (let i = 0; i < 9; i++) {
    const x = W * (0.05 + i * 0.115) + hash(i, 3) * 40, w = 40 + hash(i, 5) * 60, L = 380 + hash(i, 8) * 260
    const g = ctx.createLinearGradient(x, 0, x - L * 0.25, L)
    g.addColorStop(0, rgba(K.ray, 0.16)); g.addColorStop(1, rgba(K.ray, 0))
    ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + w, 0); ctx.lineTo(x + w - L * 0.25 - w * 1.6, L); ctx.lineTo(x - L * 0.25, L); ctx.closePath()
    ctx.fillStyle = g; ctx.fill()
  }
  glowDisc(ctx, W / 2, 0, 520, K.ray, 0.12); glowDisc(ctx, W * 0.15, H, 260, K.deep, 0.5); glowDisc(ctx, W * 0.85, H, 260, K.deep, 0.5)
  ctx.restore()

  if (B) {
    // outer contour, painted before the band covers its roots: a wave crest on top, bubble clusters on the
    // corners, kelp blades on both sides and a sand bank with a starfish below
    const ro = seeded(41)
    ctx.beginPath(); ctx.moveTo(0, 6)
    for (let x = 0; x <= W; x += 6) ctx.lineTo(x, -(11 + Math.sin(x * 0.06) * 4 + Math.sin(x * 0.17 + 1) * 2))
    ctx.lineTo(W, 6); ctx.closePath()
    ctx.fillStyle = rgba(K.mid, 0.95); ctx.fill()
    ctx.beginPath()
    for (let x = 0; x <= W; x += 6) { const y = -(11 + Math.sin(x * 0.06) * 4 + Math.sin(x * 0.17 + 1) * 2); if (x) ctx.lineTo(x, y); else ctx.moveTo(x, y) }
    ctx.lineWidth = 1.4; ctx.strokeStyle = rgba(K.wave, 0.85); ctx.stroke()
    for (let i = 0; i < 9; i++) {
      const x = ro(20, W - 20), r = ro(1.2, 2.6), y = -(B - 5 - ro(0, 6))
      ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.bub, 0.7); ctx.stroke()
    }
    ctx.beginPath(); ctx.moveTo(0, H - 6)
    for (let x = 0; x <= W; x += 8) ctx.lineTo(x, H + 8 + Math.sin(x * 0.03) * 4 + hash(x, 9) * 4)
    ctx.lineTo(W, H - 6); ctx.closePath()
    ctx.fillStyle = rgba(K.sand, 0.95); ctx.fill()
    for (let i = 0; i < 7; i++) dotShape(ctx, ro(30, W - 30), H + 10 + ro(0, 8), ro(1.2, 2.4), rgba(K.bub, 0.35))
    ctx.beginPath()
    for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, rr = i % 2 ? 3.5 : 9, qx = W * 0.62 + Math.cos(a) * rr, qy = H + 14 + Math.sin(a) * rr; i ? ctx.lineTo(qx, qy) : ctx.moveTo(qx, qy) }
    ctx.closePath(); ctx.fillStyle = K.coral3; ctx.fill()
    for (let i = 0; i < 4; i++) {
      const sx = i % 2 ? W : 0, sy = i < 2 ? 0 : H, dx = i % 2 ? 1 : -1, dy = i < 2 ? -1 : 1
      for (const c of [[6, 6, 9], [15, 1, 5], [3, 16, 4]]) {
        const bx = sx + dx * c[0], by = sy + dy * c[1]
        ctx.beginPath(); ctx.arc(bx, by, c[2], 0, Math.PI * 2); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.bub, 0.75); ctx.stroke()
        ctx.fillStyle = rgba(K.mid, 0.9); ctx.fill()
        dotShape(ctx, bx - c[2] * 0.35, by - c[2] * 0.35, Math.max(0.6, c[2] * 0.2), rgba("#ffffff", 0.9))
      }
    }
    const rs = seeded(17)
    for (let i = 0; i < 3; i++) for (const side of [-1, 1]) {
      const y = H * (0.3 + i * 0.22) + rs(-20, 20)
      ctx.save(); ctx.translate(side < 0 ? 10 : W - 10, y); ctx.rotate(side * (Math.PI / 2 - 0.5))
      kelp(ctx, 0, 0, 33, rs(0, 6), 6, K); ctx.restore()
    }
  }

  const g = ctx.createLinearGradient(0, 0, 0, H)
  g.addColorStop(0, K.mid); g.addColorStop(1, K.deep)
  band(ctx, W, H, g, 16, 7, false)

  ctx.save(); bandClip(ctx, W, H, 16, 7)
  ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.wave, 0.3)
  const wavy = (y0, ph) => { ctx.beginPath(); for (let x = 0; x <= W; x += 6) { const y = y0 + Math.sin(x * 0.045 + ph) * 2.2; if (x) ctx.lineTo(x, y); else ctx.moveTo(x, y) } ctx.stroke() }
  wavy(6, 0); wavy(12, 1.7); wavy(H - 6, 2.4); wavy(H - 13, 0.6)
  const wavyV = (x0, ph) => { ctx.beginPath(); for (let y = 0; y <= H; y += 6) { const x = x0 + Math.sin(y * 0.05 + ph) * 2.2; if (y) ctx.lineTo(x, y); else ctx.moveTo(x, y) } ctx.stroke() }
  wavyV(6, 1); wavyV(13, 3); wavyV(W - 6, 2); wavyV(W - 13, 4.2)
  ctx.restore()

  rrPath(ctx, 15.5, 15.5, W - 31, H - 31, 8)
  glowStroke(ctx, rgba(K.wave, 0.8), 1.2, 8, rgba(K.wave, 0.7))
  rrPath(ctx, 1.5, 1.5, W - 3, H - 3, 15)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.ray, 0.45); ctx.stroke()

  // sand and corals along the bottom
  ctx.beginPath(); ctx.moveTo(0, H)
  for (let x = 0; x <= W; x += 20) ctx.lineTo(x, H - 18 - Math.sin(x * 0.012) * 8 - hash(x, 5) * 6)
  ctx.lineTo(W, H); ctx.closePath()
  ctx.fillStyle = rgba(K.sand, 0.85); ctx.fill()
  const cr = seeded(13)
  const corners = [[70 * k, K.coral1], [190 * k, K.coral2], [W - 90 * k, K.coral3], [W - 220 * k, K.coral1], [W * 0.5, K.coral2]]
  corners.forEach((c) => { for (let n = 0; n < 2; n++) coral(ctx, cr, c[0] + n * 22 * k, H - 14, -Math.PI / 2 + cr(-0.4, 0.4), cr(26, 38) * k, 6 * k, 0, c[1]) })
  // kelp forest, taller at the corners
  const rk = seeded(3)
  for (let x = 24; x < W - 24; x += rk(26, 46)) {
    const edge = Math.min(x, W - x) / k
    const h = k * (edge < 340 ? 120 + (340 - edge) * 0.55 + rk(0, 60) : (hash(x, 7) > 0.8 ? 50 + rk(0, 40) : 0))
    if (h > 40 * k) kelp(ctx, x, H - 12, h, rk(0, 6), 7, K)
  }
  // starfish
  for (const q of [[W * 0.5 + 60, H - 14], [W * 0.3, H - 10]]) {
    ctx.beginPath()
    for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + i * Math.PI / 5, r = (i % 2 ? 4 : 11) * k; i ? ctx.lineTo(q[0] + Math.cos(a) * r, q[1] + Math.sin(a) * r) : ctx.moveTo(q[0] + Math.cos(a) * r, q[1] + Math.sin(a) * r) }
    ctx.closePath(); ctx.fillStyle = K.coral3; ctx.fill()
  }

  // jellyfish drifting at the top right, a school of fish at the left
  jellyfish(ctx, W - 180 * k, 112 * k, 22 * k, K); jellyfish(ctx, W - 250 * k, 168 * k, 13 * k, K)
  const rf = seeded(29)
  for (let i = 0; i < 11; i++) {
    const fx = 90 + rf(0, 230) + i * 4, fy = 200 + (i % 4) * 22 + rf(-8, 8), fs = rf(0.7, 1.15)
    if (!B || i < 6) fishShape(ctx, fx * k, fy * k, fs * Math.max(k, 0.7), 1, i % 3 ? K.fish1 : K.fish2, K.fin)
  }
  fishShape(ctx, W * 0.45, 70 * k, 1.5 * Math.max(k, 0.7), -1, K.fish2, K.fin)

  // bubbles
  const rb = seeded(61)
  for (let i = 0; i < (B ? 40 : 70); i++) {
    const side = i % 2, x = side ? W - 24 - rb(0, 300) * k * rb(0.2, 1) : 24 + rb(0, 300) * k * rb(0.2, 1)
    const y = H - 40 - rb(0, 1) * rb(0, 1) * (H - 120), r = rb(1.2, 5)
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.bub, 0.7); ctx.stroke()
    ctx.fillStyle = rgba(K.bub, 0.1); ctx.fill()
    dotShape(ctx, x - r * 0.35, y - r * 0.35, Math.max(0.5, r * 0.22), rgba("#ffffff", 0.9))
  }

  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 3.5, tw = spacedWidth(ctx, t, sp), x0 = 40
    pill(ctx, x0 - 4, 3, tw + 34, 17, rgba(K.deep, 0.95), K.wave, 1)
    ctx.beginPath(); ctx.arc(x0 + 7, 12, 4, 0, Math.PI * 2); ctx.lineWidth = 1; ctx.strokeStyle = K.bub; ctx.stroke()
    dotShape(ctx, x0 + 5.8, 10.6, 1, K.bub)
    ctx.fillStyle = K.bub
    spaced(ctx, t, x0 + 18, 15, sp, "left")
  }
}

// ---- STEAMPUNK: brass and iron. Riveted plate band, plus big cogs, pipes with flanges, a pressure gauge
// and steam puffs that reach into the window area (click-through). ----
function gear(ctx, cx, cy, R, teeth, rot, K, spokes) {
  const tooth = R * 0.17, ri = R * 0.58
  ctx.beginPath()
  for (let i = 0; i < teeth; i++) {
    const a0 = rot + i * 2 * Math.PI / teeth, w = Math.PI / teeth
    const pts = [[a0 - w * 0.5, R - tooth], [a0 - w * 0.3, R], [a0 + w * 0.3, R], [a0 + w * 0.5, R - tooth]]
    pts.forEach((q, k) => { const x = cx + Math.cos(q[0]) * q[1], y = cy + Math.sin(q[0]) * q[1]; if (i === 0 && k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y) })
  }
  ctx.closePath()
  ctx.moveTo(cx + ri, cy); ctx.arc(cx, cy, ri, 0, Math.PI * 2, true)
  const g = ctx.createLinearGradient(cx - R, cy - R, cx + R, cy + R)
  g.addColorStop(0, K.brassHi); g.addColorStop(0.5, K.brass); g.addColorStop(1, K.brassLow)
  ctx.fillStyle = g; ctx.fill()
  ctx.lineWidth = 1; ctx.strokeStyle = K.iron; ctx.stroke()
  ctx.beginPath(); ctx.arc(cx, cy, ri, 0, Math.PI * 2); ctx.lineWidth = 1.5; ctx.strokeStyle = K.brassLow; ctx.stroke()
  ctx.lineCap = "butt"
  for (let i = 0; i < spokes; i++) {
    const a = rot + i * 2 * Math.PI / spokes
    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a) * ri, cy + Math.sin(a) * ri)
    ctx.lineWidth = R * 0.11; ctx.strokeStyle = K.brass; ctx.stroke()
    ctx.lineWidth = R * 0.03; ctx.strokeStyle = K.brassHi; ctx.stroke()
  }
  dotShape(ctx, cx, cy, R * 0.17, K.brassLow); dotShape(ctx, cx, cy, R * 0.12, K.brass); dotShape(ctx, cx, cy, R * 0.05, K.iron)
}
function rivet(ctx, x, y, r, K) {
  dotShape(ctx, x, y, r, K.brassLow); dotShape(ctx, x - r * 0.15, y - r * 0.15, r * 0.7, K.brass); dotShape(ctx, x - r * 0.35, y - r * 0.35, r * 0.3, K.brassHi)
}
function pipe(ctx, pts, w, K) {
  ctx.lineJoin = "round"; ctx.lineCap = "butt"
  const trace = () => { ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]); for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]) }
  trace(); ctx.lineWidth = w + 3; ctx.strokeStyle = K.iron; ctx.stroke()
  trace(); ctx.lineWidth = w; ctx.strokeStyle = K.copper; ctx.stroke()
  trace(); ctx.lineWidth = w * 0.45; ctx.strokeStyle = K.copperHi; ctx.stroke()
  trace(); ctx.lineWidth = w * 0.14; ctx.strokeStyle = rgba("#ffffff", 0.35); ctx.stroke()
  // flanges at the joints, drawn square to each leg
  for (let i = 0; i < pts.length; i++) {
    const a = i < pts.length - 1 ? Math.atan2(pts[i + 1][1] - pts[i][1], pts[i + 1][0] - pts[i][0]) : Math.atan2(pts[i][1] - pts[i - 1][1], pts[i][0] - pts[i - 1][0])
    const x = pts[i][0], y = pts[i][1]
    ctx.save(); ctx.translate(x, y); ctx.rotate(a)
    ctx.fillStyle = K.iron; ctx.fillRect(-3, -w * 0.8, 6, w * 1.6)
    ctx.fillStyle = K.brass; ctx.fillRect(-2, -w * 0.8 + 1, 4, w * 1.6 - 2)
    ctx.restore()
    if (i > 0 && i < pts.length - 1) rivet(ctx, x, y, 3.2, K)
  }
}
function steam(ctx, x, y, s, a) {
  const r = seeded(Math.round(x * 3 + y))
  for (let i = 0; i < 7; i++) {
    const rr = s * r(0.5, 1) * (1 + i * 0.16), cx = x + r(-8, 8) * (i + 1) * 0.5, cy = y - i * s * 0.7
    glowDisc(ctx, cx, cy, rr, "#ffffff", a * (1 - i / 9))
  }
}
function gauge(ctx, cx, cy, R, needle, K) {
  dotShape(ctx, cx, cy, R + 5, K.iron); dotShape(ctx, cx, cy, R + 3.5, K.brass); dotShape(ctx, cx, cy, R + 1.5, K.brassLow)
  const g = ctx.createRadialGradient(cx - R * 0.3, cy - R * 0.3, 2, cx, cy, R)
  g.addColorStop(0, "#fff8e0"); g.addColorStop(1, "#d9c490")
  dotShape(ctx, cx, cy, R, g)
  ctx.lineWidth = 1.2; ctx.strokeStyle = K.iron
  for (let i = 0; i <= 10; i++) {
    const a = Math.PI * 0.75 + i * Math.PI * 1.5 / 10, l = i % 5 === 0 ? 0.28 : 0.15
    ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * R * 0.86, cy + Math.sin(a) * R * 0.86); ctx.lineTo(cx + Math.cos(a) * R * (0.86 - l), cy + Math.sin(a) * R * (0.86 - l)); ctx.stroke()
  }
  ctx.beginPath(); ctx.arc(cx, cy, R * 0.86, Math.PI * 2.0, Math.PI * 2.25); ctx.lineWidth = 3; ctx.strokeStyle = rgba(K.redZone, 0.85); ctx.stroke()
  const na = Math.PI * 0.75 + needle * Math.PI * 1.5
  ctx.beginPath(); ctx.moveTo(cx - Math.cos(na) * R * 0.18, cy - Math.sin(na) * R * 0.18); ctx.lineTo(cx + Math.cos(na) * R * 0.78, cy + Math.sin(na) * R * 0.78)
  ctx.lineWidth = 1.8; ctx.strokeStyle = K.redZone; ctx.stroke()
  dotShape(ctx, cx, cy, 3, K.iron)
  ctx.beginPath(); ctx.arc(cx, cy, R, Math.PI * 1.15, Math.PI * 1.7); ctx.lineWidth = 2; ctx.strokeStyle = rgba("#ffffff", 0.55); ctx.stroke()
}
function steampunk(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { iron: p.dark, plate: mix(p.dark, p.bg, 0.5), brass: mix(p.byellow, p.dark, 0.2), brassHi: mix(p.byellow, p.bright, 0.45), brassLow: mix(p.byellow, p.dark, 0.6),
        copper: mix(p.orange, p.dark, 0.25), copperHi: mix(p.orange, p.bright, 0.4), redZone: p.red, glass: p.byellow, ink: p.dark }
    : { iron: "#1d140f", plate: "#2c2019", brass: "#c48b2c", brassHi: "#f3d27a", brassLow: "#7a4f16",
        copper: "#b0592f", copperHi: "#e49060", redZone: "#c8352c", glass: "#f2b04a", ink: "#1d140f" }

  glowDisc(ctx, 0, H, 300, K.glass, 0.14); glowDisc(ctx, W, 0, 300, K.glass, 0.12)

  const g = ctx.createLinearGradient(0, 0, 0, H)
  g.addColorStop(0, mix(K.plate, "#ffffff", 0.06)); g.addColorStop(0.5, K.plate); g.addColorStop(1, K.iron)
  band(ctx, W, H, g, 14, 6, false)
  // brass trim on the inner and outer edge
  rrPath(ctx, 3, 3, W - 6, H - 6, 12)
  ctx.lineWidth = 2; ctx.strokeStyle = K.brassLow; ctx.stroke()
  rrPath(ctx, 15.5, 15.5, W - 31, H - 31, 7)
  ctx.lineWidth = 2.4; ctx.strokeStyle = K.brass; ctx.stroke()
  ctx.lineWidth = 0.8; ctx.strokeStyle = K.brassHi; ctx.stroke()
  // rivets along the plates
  for (let x = 24; x < W - 20; x += 36) { rivet(ctx, x, 9, 2.8, K); rivet(ctx, x, H - 9, 2.8, K) }
  for (let y = 24; y < H - 20; y += 36) { rivet(ctx, 9, y, 2.8, K); rivet(ctx, W - 9, y, 2.8, K) }

  // pipes along the left edge and across the bottom right, into the window area
  pipe(ctx, [[34, 150], [34, 330], [74, 370], [74, 520]], 12, K)
  pipe(ctx, [[W - 140, H - 34], [W - 330, H - 34], [W - 360, H - 70], [W - 360, H - 150]], 12, K)
  pipe(ctx, [[W - 34, 260], [W - 34, 420]], 10, K)
  steam(ctx, 74, 520, 30, 0.35); steam(ctx, W - 360, H - 150, 28, 0.3)

  // cogs at the corners, meshing in pairs
  gear(ctx, 52, 56, 74, 16, 0.2, K, 6); gear(ctx, 142, 128, 44, 10, 0.2 + Math.PI / 10, K, 5)
  gear(ctx, W - 56, H - 60, 82, 18, 0.1, K, 6); gear(ctx, W - 176, H - 120, 40, 9, 0.1 + Math.PI / 9, K, 4)
  gear(ctx, W - 60, 60, 52, 12, 0.5, K, 5)
  gear(ctx, 60, H - 56, 46, 11, 0.3, K, 5)

  // pressure gauge and a small lamp, top
  gauge(ctx, W * 0.62, 46, 24, 0.72, K)
  glowDisc(ctx, W * 0.62 + 62, 40, 36, K.glass, 0.45); dotShape(ctx, W * 0.62 + 62, 40, 8, K.glass)
  ctx.lineWidth = 1.2; ctx.strokeStyle = K.iron; ctx.beginPath(); ctx.arc(W * 0.62 + 62, 40, 8, 0, Math.PI * 2); ctx.stroke()
  steam(ctx, W * 0.62 - 90, 30, 22, 0.28)

  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 3.5, tw = spacedWidth(ctx, t, sp), x0 = 166
    ctx.fillStyle = K.brassLow; rrPath(ctx, x0 - 8, 2, tw + 28, 19, 3); ctx.fill()
    const pg = ctx.createLinearGradient(0, 2, 0, 21)
    pg.addColorStop(0, K.brassHi); pg.addColorStop(0.5, K.brass); pg.addColorStop(1, K.brassLow)
    ctx.fillStyle = pg; rrPath(ctx, x0 - 7, 3, tw + 26, 17, 3); ctx.fill()
    rivet(ctx, x0 - 2, 11.5, 1.8, K); rivet(ctx, x0 + tw + 14, 11.5, 1.8, K)
    ctx.fillStyle = K.iron
    spaced(ctx, t, x0 + 6, 15, sp, "left")
  }
}

// ---- HALLOWEEN: spooky night. Midnight band with orange stitching and bats, plus cobwebs with hanging
// spiders, jack-o'-lanterns, a full moon, a ghost and flying bats that reach into the window area
// (click-through). ----
function batShape(ctx, x, y, s, flap, col) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s)
  ctx.beginPath(); ctx.moveTo(0, -3)
  for (const d of [1, -1]) {
    const ex = d * 18, ey = -6 + flap * 5
    ctx.moveTo(0, -3)
    ctx.quadraticCurveTo(d * 8, -10 - flap * 4, ex, ey)
    ctx.quadraticCurveTo(d * 15, ey + 4, d * 12, ey + 7)
    ctx.quadraticCurveTo(d * 8, ey + 3, d * 7, ey + 8)
    ctx.quadraticCurveTo(d * 4, ey + 3, d * 2, 5)
  }
  ctx.fillStyle = col; ctx.fill()
  ctx.beginPath(); ctx.ellipse(0, 0, 3.4, 5, 0, 0, Math.PI * 2); ctx.fill()
  ctx.beginPath(); ctx.moveTo(-2.8, -3); ctx.lineTo(-2, -8); ctx.lineTo(0, -4); ctx.lineTo(2, -8); ctx.lineTo(2.8, -3); ctx.fill()
  ctx.restore()
}
function cobweb(ctx, cx, cy, R, a0, K) {
  const spokes = 7
  ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.web, 0.75)
  for (let i = 0; i <= spokes; i++) {
    const a = a0 + i * (Math.PI / 2) / spokes
    ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(cx + Math.cos(a) * R, cy + Math.sin(a) * R); ctx.stroke()
  }
  for (let r = R * 0.16; r <= R; r += R * 0.14) {
    ctx.beginPath()
    for (let i = 0; i <= spokes; i++) {
      const a = a0 + i * (Math.PI / 2) / spokes, rr = r * (i % 2 ? 0.93 : 1)
      const x = cx + Math.cos(a) * rr, y = cy + Math.sin(a) * rr
      if (i) { const am = a - (Math.PI / 2) / spokes / 2, rm = r * 0.8; ctx.quadraticCurveTo(cx + Math.cos(am) * rm * 1.1, cy + Math.sin(am) * rm * 1.1, x, y) } else ctx.moveTo(x, y)
    }
    ctx.stroke()
  }
}
function spider(ctx, x, y, s, K) {
  ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, y - 6 * s); ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.web, 0.8); ctx.stroke()
  ctx.lineWidth = 1.3 * s; ctx.strokeStyle = K.ink; ctx.lineCap = "round"
  for (const d of [-1, 1]) for (let i = 0; i < 4; i++) {
    const a = (i - 1.5) * 0.45
    ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + d * 9 * s, y + a * 9 * s - 4 * s); ctx.lineTo(x + d * 14 * s, y + a * 14 * s + 4 * s); ctx.stroke()
  }
  ctx.beginPath(); ctx.ellipse(x, y + 3 * s, 5 * s, 6.5 * s, 0, 0, Math.PI * 2); ctx.fillStyle = K.ink; ctx.fill()
  dotShape(ctx, x, y - 3 * s, 3.4 * s, K.ink)
  dotShape(ctx, x - 1.3 * s, y - 3.6 * s, 0.9 * s, K.green); dotShape(ctx, x + 1.3 * s, y - 3.6 * s, 0.9 * s, K.green)
  ctx.beginPath(); ctx.moveTo(x - 2 * s, y + 1 * s); ctx.lineTo(x, y + 7 * s); ctx.lineTo(x + 2 * s, y + 1 * s); ctx.fillStyle = K.orange; ctx.fill()
}
function pumpkin(ctx, x, y, R, K, face) {
  glowDisc(ctx, x, y - R * 0.1, R * 2.2, K.orange, face ? 0.28 : 0.1)
  ctx.beginPath(); ctx.moveTo(x - 2, y - R * 0.85); ctx.quadraticCurveTo(x - 4, y - R * 1.4, x + 8, y - R * 1.35); ctx.lineWidth = 5; ctx.lineCap = "round"; ctx.strokeStyle = K.stem; ctx.stroke()
  const lobes = [[-0.62, 0.58], [0.62, 0.58], [-0.3, 0.78], [0.3, 0.78], [0, 0.86]]
  for (const l of lobes) {
    ctx.beginPath(); ctx.ellipse(x + l[0] * R, y, R * l[1], R * 0.82, 0, 0, Math.PI * 2)
    const g = ctx.createLinearGradient(x + (l[0] - l[1]) * R, 0, x + (l[0] + l[1]) * R, 0)
    g.addColorStop(0, K.orangeDeep); g.addColorStop(0.45, K.orange); g.addColorStop(1, K.orangeDeep)
    ctx.fillStyle = g; ctx.fill()
    ctx.lineWidth = 0.9; ctx.strokeStyle = rgba(K.orangeDeep, 0.9); ctx.stroke()
  }
  if (face) {
    ctx.fillStyle = K.glow
    for (const d of [-1, 1]) {
      ctx.beginPath(); ctx.moveTo(x + d * R * 0.5, y - R * 0.45); ctx.lineTo(x + d * R * 0.18, y - R * 0.05); ctx.lineTo(x + d * R * 0.62, y - R * 0.05); ctx.closePath(); ctx.fill()
    }
    ctx.beginPath(); ctx.moveTo(x, y + R * 0.02); ctx.lineTo(x - R * 0.1, y + R * 0.2); ctx.lineTo(x + R * 0.1, y + R * 0.2); ctx.closePath(); ctx.fill()
    ctx.beginPath(); ctx.moveTo(x - R * 0.62, y + R * 0.3)
    const n = 6
    for (let i = 0; i <= n; i++) { const t = i / n; ctx.lineTo(x - R * 0.62 + t * R * 1.24, y + R * 0.3 + (i % 2 ? 0.2 : 0) * R + Math.sin(t * Math.PI) * R * 0.2) }
    for (let i = n; i >= 0; i--) { const t = i / n; ctx.lineTo(x - R * 0.62 + t * R * 1.24, y + R * 0.3 + (i % 2 ? 0.2 : 0.0) * R + Math.sin(t * Math.PI) * R * 0.2 - R * 0.07) }
    ctx.closePath(); ctx.fill()
  }
}
function ghost(ctx, x, y, s, K) {
  glowDisc(ctx, x, y, 60 * s, K.green, 0.18)
  ctx.beginPath(); ctx.moveTo(x - 17 * s, y + 24 * s); ctx.lineTo(x - 17 * s, y - 4 * s)
  ctx.bezierCurveTo(x - 17 * s, y - 32 * s, x + 17 * s, y - 32 * s, x + 17 * s, y - 4 * s)
  ctx.lineTo(x + 17 * s, y + 24 * s)
  for (let i = 0; i < 4; i++) ctx.quadraticCurveTo(x + (17 - i * 8.5 - 4.25) * s, y + (i % 2 ? 24 : 32) * s, x + (17 - (i + 1) * 8.5) * s, y + 24 * s)
  ctx.closePath()
  ctx.fillStyle = rgba(K.bone, 0.9); ctx.fill()
  ctx.fillStyle = K.ink
  ctx.beginPath(); ctx.ellipse(x - 6 * s, y - 6 * s, 2.6 * s, 3.8 * s, 0, 0, Math.PI * 2); ctx.fill()
  ctx.beginPath(); ctx.ellipse(x + 6 * s, y - 6 * s, 2.6 * s, 3.8 * s, 0, 0, Math.PI * 2); ctx.fill()
  ctx.beginPath(); ctx.ellipse(x, y + 4 * s, 3 * s, 4 * s, 0, 0, Math.PI * 2); ctx.fill()
}
function halloween(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { night: p.dark, night2: mix(p.dark, p.magenta, 0.3), orange: p.orange, orangeDeep: darker(p.orange, 1.7), glow: p.byellow, web: p.bright, bone: p.bright,
        green: p.green, stem: mix(p.green, p.dark, 0.4), purple: p.magenta, ink: p.dark }
    : { night: "#0e0716", night2: "#2a1048", orange: "#ff7a1a", orangeDeep: "#b23c08", glow: "#ffd54a", web: "#e7e0f0", bone: "#efe6cf",
        green: "#8be04a", stem: "#4a6a22", purple: "#7a35c0", ink: "#06030a" }

  glowDisc(ctx, W * 0.82, 120, 340, K.purple, 0.3); glowDisc(ctx, 0, H, 260, K.orange, 0.16); glowDisc(ctx, W, H, 260, K.orange, 0.16)

  const g = ctx.createLinearGradient(0, 0, W, H)
  g.addColorStop(0, K.night); g.addColorStop(0.5, K.night2); g.addColorStop(1, K.night)
  band(ctx, W, H, g, 16, 7, false)

  ctx.save(); bandClip(ctx, W, H, 16, 7)
  for (let e = 0; e < 4; e++) {
    const L = edgeLen(W, H, e)
    for (let t = 40, i = 0; t < L - 20; t += 80 + hash(t, e) * 40, i++) {
      const q = edgeXY(W, H, e, t, 11)
      if (i % 2) batShape(ctx, q[0], q[1], 0.42, hash(t, 1) > 0.5 ? 1 : -0.3, rgba(K.ink, 0.9))
      else { ctx.save(); ctx.translate(q[0], q[1]); ctx.rotate(e * Math.PI / 2); pumpkin(ctx, 0, 0, 5, K, false); ctx.restore() }
    }
  }
  ctx.restore()

  // stitched orange line inside the band
  rrPath(ctx, 15.5, 15.5, W - 31, H - 31, 8)
  ctx.setLineDash && ctx.setLineDash([7, 5]); ctx.lineWidth = 1.8; ctx.strokeStyle = K.orange; ctx.stroke()
  ctx.setLineDash && ctx.setLineDash([])
  rrPath(ctx, 1.5, 1.5, W - 3, H - 3, 15)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.orange, 0.6); ctx.stroke()

  // full moon with a bat across it
  const mx = W - 190, my = 120
  glowDisc(ctx, mx, my, 150, K.glow, 0.28)
  const mg = ctx.createRadialGradient(mx - 14, my - 14, 4, mx, my, 54)
  mg.addColorStop(0, "#fffbe6"); mg.addColorStop(1, mix(K.glow, "#ffffff", 0.45))
  dotShape(ctx, mx, my, 50, mg)
  for (const c of [[-16, -10, 9], [14, 14, 12], [18, -20, 5], [-20, 22, 6]]) dotShape(ctx, mx + c[0], my + c[1], c[2], rgba(K.orangeDeep, 0.16))
  batShape(ctx, mx - 6, my - 8, 1.6, 1, K.ink)
  batShape(ctx, mx - 130, my + 56, 1.0, -0.4, K.ink); batShape(ctx, mx - 170, my + 22, 0.7, 1, K.ink)

  // cobwebs with spiders in the corners
  cobweb(ctx, 0, 0, 230, 0.0, K); cobweb(ctx, W, 0, 200, Math.PI / 2, K)
  cobweb(ctx, 0, H, 150, -Math.PI / 2, K); cobweb(ctx, W, H, 170, Math.PI, K)
  spider(ctx, 150, 128, 1.3, K); spider(ctx, W - 56, 168, 1.0, K); spider(ctx, 340, 60, 0.8, K)

  // pumpkin patch along the bottom, vines and all
  for (let x = 40; x < W - 40; x += 30) if (hash(x, 3) > 0.35 && (x < 420 || x > W - 420)) {
    ctx.lineWidth = 2; ctx.strokeStyle = K.stem
    ctx.beginPath(); ctx.moveTo(x, H - 16); ctx.bezierCurveTo(x + 12, H - 40, x + 30, H - 22, x + 40, H - 34); ctx.stroke()
    leafShape(ctx, x + 14, H - 32, -0.6, 12, 4.5, K.stem, null)
  }
  pumpkin(ctx, 78, H - 46, 36, K, true); pumpkin(ctx, 160, H - 32, 22, K, false); pumpkin(ctx, 214, H - 36, 26, K, true)
  pumpkin(ctx, W - 84, H - 50, 40, K, true); pumpkin(ctx, W - 176, H - 34, 24, K, false); pumpkin(ctx, W - 236, H - 36, 20, K, true)
  ghost(ctx, 52, H * 0.46, 1.3, K); ghost(ctx, W - 48, H * 0.62, 1.0, K)

  // bats in flight
  const rb = seeded(21)
  for (let i = 0; i < 9; i++) batShape(ctx, 420 + i * 120 + rb(0, 60), 52 + rb(0, 90) * rb(0, 1), rb(0.6, 1.1), i % 2 ? 1 : -0.4, mix(K.purple, K.ink, 0.3))

  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 3.5, tw = spacedWidth(ctx, t, sp), x0 = 40
    pill(ctx, x0 - 4, 3, tw + 38, 17, K.night, K.orange, 1)
    batShape(ctx, x0 + 9, 11.5, 0.5, 1, K.orange)
    ctx.fillStyle = K.glow
    spaced(ctx, t, x0 + 22, 15, sp, "left")
  }
}

// ---- 16-bit pixel styles (unchanged look) ----------------------------------------
function pixel(ctx, width, height, o) {
  const P = o.px
  const W = Math.floor(width / P), H = Math.floor(height / P)
  if (W < 20 || H < 20) return
  const col = (name, fb) => o.colors[name] || fb

  const dot = (x, y, c) => { ctx.fillStyle = c; ctx.fillRect(x * P, y * P, P, P) }
  const rect = (x, y, w, h, c) => { ctx.fillStyle = c; ctx.fillRect(x * P, y * P, w * P, h * P) }
  // Right/bottom edges snap to the real window size, not the unit grid.
  const RX = (width / P) - 1, BY = (height / P) - 1
  const hline = (x0, x1, y, c) => rect(x0, y, x1 - x0 + 1, 1, c)
  const vline = (x, y0, y1, c) => rect(x, y0, 1, y1 - y0 + 1, c)

  const accent = col("accent", "#7265f6")
  const darkBg = pick(o.colors, ["darker_background", "darker_bg"], "#000014")
  const brightFg = pick(o.colors, ["bright_foreground", "bright_fg"], "#ffffff")
  const styles = {
    CRYSTAL: {
      ink: darkBg,
      bands: [darkBg, lighter(accent, 1.55), accent, accent, accent, darker(accent, 1.7), darkBg],
      bevel: [lighter(accent, 1.55), darker(accent, 1.7)],
      stud: "gem", gem: [col("bright_yellow", "#e0b050"), col("yellow", "#8d7541"), brightFg],
      edgeStuds: "mid",
      plate: [darkBg, darker(accent, 1.7)],
      text: [lighter(accent, 1.55), brightFg]
    },
    ROYAL: {
      ink: "#080818",
      bands: ["#080818", "#f8f8f8", "#c8c8d8", "#8890b0", "#3058c8", "#1c3488", "#080818"],
      bevel: null,
      stud: "gem", gem: ["#e8e8f0", "#9098b0", "#ffffff"],
      edgeStuds: "mid",
      plate: ["#1c3488", "#c8c8d8"],
      text: ["#ffffff", "#f0f0f8"],
      tex: (k, t, e) => {
        if (k === 4 && (t % 2 === 0)) return "#4870d8"
        if (k === 3 && (t % 2 === 1)) return "#a0a8c8"
        return null
      }
    },
    WOOD: {
      ink: "#1a0e06",
      bands: ["#1a0e06", "#d8a060", "#a86a34", "#9a5e2c", "#8a5226", "#553014", "#1a0e06"],
      bevel: null,
      stud: "rivet", rivet: ["#9a9aa6", "#50505c", "#e8e8f0"],
      edgeStuds: "every",
      plate: ["#2a180a", "#d8a060"],
      text: ["#ffe0a0", "#f0c880"],
      tex: (k, t, e) => {
        if (k < 2 || k > 4) return null
        const seg = Math.floor((t + k * 5 + e * 3) / 5)
        const r = hash(seg, k * 7 + e)
        if (r > 0.78) return "#6c4018"
        if (r < 0.06) return "#c08040"
        if (hash(t, e * 13 + k) > 0.996) return "#3a2010"
        return null
      }
    },
    DUNGEON: {
      ink: "#0a0a0e",
      bands: ["#0a0a0e", "#b4b4bc", "#84848e", "#7a7a84", "#6c6c76", "#3a3a42", "#0a0a0e"],
      bevel: null,
      stud: "gem", gem: ["#50d890", "#1e8850", "#e0fff0"],
      edgeStuds: "none",
      plate: ["#1a1a20", "#6c6c76"],
      text: ["#a0f0c0", "#d8d8e0"],
      tex: (k, t, e) => {
        if (k < 1 || k > 5) return null
        const tt = Math.floor(t)
        if (k <= 2 && hash(tt, e + 31) > 0.9) return hash(tt, e + 5) > 0.5 ? "#4c8a3c" : "#2e6030"
        if (k === 5) return null
        const off = k === 4 ? 6 : 0
        if ((tt + off) % 12 === 0) return "#34343c"
        if ((tt + off) % 12 === 1) return "#9a9aa4"
        const r = hash(tt, k * 17 + e)
        if (r > 0.94) return "#5a5a64"
        if (r < 0.04) return "#a4a4ae"
        return null
      }
    }
  }
  if (o.follow) {
    const p = palette(o.colors)
    const ink = mix(p.dark, "#000000", 0.35), white = "#ffffff"
    {
      const base = p.blue, b = ramp(base, ink, white)
      styles.ROYAL = {
        ink: ink, bands: b, bevel: null,
        stud: "gem", gem: [pastel(p.fg, 0.4), mix(p.fg, p.dark, 0.5), white],
        edgeStuds: "mid",
        plate: [mix(base, "#000000", 0.45), b[2]],
        text: [white, pastel(base, 0.85)],
        tex: (k, t, e) => {
          if (k === 4 && (t % 2 === 0)) return mix(base, white, 0.18)
          if (k === 3 && (t % 2 === 1)) return mix(base, white, 0.5)
          return null
        }
      }
    }
    {
      const base = p.brown ? mix(p.brown, p.orange, 0.3) : mix(p.orange, p.dark, 0.5)
      const light = mix(base, p.bright, 0.5), b = ramp(base, ink, light)
      const dk = mix(base, ink, 0.35), lt = mix(base, light, 0.45), knot = mix(base, ink, 0.75)
      styles.WOOD = {
        ink: ink, bands: b, bevel: null,
        stud: "rivet", rivet: ["#9a9aa6", "#50505c", "#e8e8f0"],
        edgeStuds: "every",
        plate: [mix(base, ink, 0.7), b[1]],
        text: [p.byellow, p.yellow],
        tex: (k, t, e) => {
          if (k < 2 || k > 4) return null
          const seg = Math.floor((t + k * 5 + e * 3) / 5)
          const r = hash(seg, k * 7 + e)
          if (r > 0.78) return dk
          if (r < 0.06) return lt
          if (hash(t, e * 13 + k) > 0.996) return knot
          return null
        }
      }
    }
    {
      const base = mix(p.fg, p.dark, 0.62), light = p.fg, b = ramp(base, ink, light)
      const mortar = mix(base, ink, 0.5), edge = mix(base, light, 0.35)
      const sp1 = mix(base, ink, 0.25), sp2 = mix(base, light, 0.5)
      const moss1 = p.green, moss2 = mix(p.green, p.dark, 0.45)
      styles.DUNGEON = {
        ink: ink, bands: b, bevel: null,
        stud: "gem", gem: [lighter(p.green, 1.3), darker(p.green, 1.5), p.bright],
        edgeStuds: "none",
        plate: [mix(base, ink, 0.7), base],
        text: [pick(o.colors, ["bright_green"], lighter(p.green, 1.5)), p.fg],
        tex: (k, t, e) => {
          if (k < 1 || k > 5) return null
          const tt = Math.floor(t)
          if (k <= 2 && hash(tt, e + 31) > 0.9) return hash(tt, e + 5) > 0.5 ? moss1 : moss2
          if (k === 5) return null
          const off = k === 4 ? 6 : 0
          if ((tt + off) % 12 === 0) return mortar
          if ((tt + off) % 12 === 1) return edge
          const r = hash(tt, k * 17 + e)
          if (r > 0.94) return sp1
          if (r < 0.04) return sp2
          return null
        }
      }
    }
  }
  const st = styles[o.style] || styles.CRYSTAL

  for (let k = 0; k < st.bands.length; k++) {
    const cut = Math.max(0, 2 - k)
    const x0 = k, y0 = k, x1 = RX - k, y1 = BY - k
    const c = st.bands[k]
    hline(x0 + cut, x1 - cut, y0, c)
    hline(x0 + cut, x1 - cut, y1, c)
    vline(x0, y0 + cut, y1 - cut, c)
    vline(x1, y0 + cut, y1 - cut, c)
    if (cut === 2) {
      dot(x0 + 1, y0 + 1, c); dot(x1 - 1, y0 + 1, c)
      dot(x0 + 1, y1 - 1, c); dot(x1 - 1, y1 - 1, c)
    }
  }
  if (st.bevel) {
    hline(3, RX - 3, 2, st.bevel[0]); vline(2, 3, BY - 3, st.bevel[0])
    hline(3, RX - 3, BY - 2, st.bevel[1]); vline(RX - 2, 3, BY - 3, st.bevel[1])
  }

  if (st.tex) {
    for (let k = 1; k <= 5; k++) {
      for (let t = k + 1; t <= RX - k - 1; t++) {
        const a = st.tex(k, t, 0); if (a) dot(t, k, a)
        const b = st.tex(k, t, 1); if (b) dot(t, BY - k, b)
      }
      for (let t = k + 1; t <= BY - k - 1; t++) {
        const a = st.tex(k, t, 2); if (a) dot(k, t, a)
        const b = st.tex(k, t, 3); if (b) dot(RX - k, t, b)
      }
    }
  }

  const gem = (cx, cy, g) => {
    for (let dy = -3; dy <= 3; dy++)
      for (let dx = -3; dx <= 3; dx++) {
        const d = Math.abs(dx) + Math.abs(dy)
        if (d === 3) dot(cx + dx, cy + dy, st.ink)
        else if (d < 3) dot(cx + dx, cy + dy, (dx + dy > 0) ? g[1] : g[0])
      }
    dot(cx - 1, cy - 1, g[2])
  }
  const rivet = (cx, cy, g, big) => {
    const r = big ? 2 : 1
    rect(cx - r, cy - r - 1, 2 * r + 1, 1, st.ink); rect(cx - r, cy + r + 1, 2 * r + 1, 1, st.ink)
    rect(cx - r - 1, cy - r, 1, 2 * r + 1, st.ink); rect(cx + r + 1, cy - r, 1, 2 * r + 1, st.ink)
    rect(cx - r, cy - r, 2 * r + 1, 2 * r + 1, g[0])
    hline(cx - r + 1, cx + r, cy + r, g[1]); vline(cx + r, cy - r + 1, cy + r, g[1])
    dot(cx - r, cy - r, g[2])
  }
  const corners = [[3, 3], [RX - 3, 3], [3, BY - 3], [RX - 3, BY - 3]]
  for (const [cx, cy] of corners)
    st.stud === "rivet" ? rivet(cx, cy, st.rivet, true) : gem(cx, cy, st.gem)

  const mini = (cx, cy) => {
    if (st.stud === "rivet") { rivet(cx, cy, st.rivet, false); return }
    dot(cx, cy - 1, st.ink); dot(cx - 1, cy, st.ink)
    dot(cx + 1, cy, st.ink); dot(cx, cy + 1, st.ink)
    dot(cx, cy, st.gem[0])
  }
  if (st.edgeStuds === "mid") {
    const mx = Math.round(RX / 2), my = Math.round(BY / 2)
    mini(mx, 3); mini(mx, BY - 3); mini(3, my); mini(RX - 3, my)
  } else if (st.edgeStuds === "every") {
    const step = 48
    for (let x = step; x < RX - 10; x += step) { if (x > 60) mini(x, 3); mini(x, BY - 3) }
    for (let y = step; y < BY - 10; y += step) { mini(3, y); mini(RX - 3, y) }
  }

  // name plate on the top edge, 3x5 pixel font
  if (o.text) {
    const font = PIXFONT
    const text = o.text
    const tw = text.length * 4 - 1
    const plx = 12, plw = tw + 6
    rect(plx, 0, plw, 7, st.ink)
    hline(plx + 1, plx + plw - 2, 1, st.plate[1])
    vline(plx + 1, 1, 5, st.plate[1])
    vline(plx + plw - 2, 1, 5, st.plate[1])
    rect(plx + 2, 2, plw - 4, 4, st.plate[0])
    for (let i = 0; i < text.length; i++) {
      const g = font[text[i]]
      if (!g) continue
      for (let r = 0; r < 5; r++)
        for (let c = 0; c < 3; c++)
          if (g[r * 3 + c] === "1") dot(plx + 3 + i * 4 + c, 1 + r, r === 0 ? st.text[0] : st.text[1])
    }
  }
}

// ---- MEGACITY: a rain-dark cyberpunk megacity. Palette: cyan strip lights, amber windows, orange and red signs, blue and violet billboards, a green/pink screen.
// Motifs: steel scaffold truss band with a cyan strip-light rim, sagging cables, hanging neon signs, tilted billboards,
// lit apartment blocks standing on the bottom edge, a glowing skybridge, flying taxis and a haze beam
// (click-through decoration over the window area). ----
function neonLine(ctx, pts, col, w, a) {
  const trace = () => { ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]); for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]) }
  ctx.lineJoin = "round"; ctx.lineCap = "round"
  trace(); ctx.lineWidth = w * 5; ctx.strokeStyle = rgba(col, 0.07 * (a || 1)); ctx.stroke()
  trace(); ctx.lineWidth = w * 2.6; ctx.strokeStyle = rgba(col, 0.2 * (a || 1)); ctx.stroke()
  trace(); ctx.lineWidth = w; ctx.strokeStyle = rgba(mix(col, "#ffffff", 0.45), a || 1); ctx.stroke()
}
function cable(ctx, x0, y0, x1, y1, sag, K) {
  const mx = (x0 + x1) / 2, my = (y0 + y1) / 2 + sag
  ctx.lineCap = "round"
  ctx.beginPath(); ctx.moveTo(x0, y0); ctx.quadraticCurveTo(mx, my + sag * 0.0, x1, y1)
  ctx.lineWidth = 2.4; ctx.strokeStyle = K.cable; ctx.stroke()
  ctx.beginPath(); ctx.moveTo(x0, y0 - 1); ctx.quadraticCurveTo(mx, my - 1, x1, y1 - 1)
  ctx.lineWidth = 0.8; ctx.strokeStyle = rgba(K.cyan, 0.28); ctx.stroke()
}
// vertical glyph-like marks, so a sign reads as kanji without needing a font
function glyphs(ctx, x, y, w, h, col, seed) {
  const r = seeded(seed), cells = Math.max(1, Math.floor(h / (w * 0.95)))
  const cw = w * 0.62, ch = h / cells
  ctx.lineCap = "round"
  for (let i = 0; i < cells; i++) {
    const cx = x + w / 2 - cw / 2, cy = y + i * ch + ch * 0.18, gh = ch * 0.64, n = 3 + Math.floor(r(0, 3))
    ctx.beginPath()
    for (let k = 0; k < n; k++) {
      const horiz = r(0, 1) > 0.45, p = r(0.1, 0.9)
      if (horiz) { ctx.moveTo(cx, cy + gh * p); ctx.lineTo(cx + cw * r(0.5, 1), cy + gh * p) }
      else { ctx.moveTo(cx + cw * p, cy); ctx.lineTo(cx + cw * p, cy + gh * r(0.5, 1)) }
    }
    ctx.lineWidth = 3.2; ctx.strokeStyle = rgba(col, 0.25); ctx.stroke()
    ctx.lineWidth = 1.3; ctx.strokeStyle = mix(col, "#ffffff", 0.55); ctx.stroke()
  }
}
function hangSign(ctx, x, y0, y1, w, h, col, seed, K) {
  ctx.lineWidth = 1.4; ctx.strokeStyle = K.cable
  ctx.beginPath(); ctx.moveTo(x + 5, y0); ctx.lineTo(x + 5, y1); ctx.moveTo(x + w - 5, y0); ctx.lineTo(x + w - 5, y1); ctx.stroke()
  glowDisc(ctx, x + w / 2, y1 + h / 2, Math.max(w, h) * 0.9, col, 0.22)
  rrPath(ctx, x, y1, w, h, 3); ctx.fillStyle = K.ink; ctx.fill()
  rrPath(ctx, x + 2, y1 + 2, w - 4, h - 4, 2); ctx.lineWidth = 1; ctx.strokeStyle = rgba(col, 0.9); ctx.stroke()
  glyphs(ctx, x + 3, y1 + 5, w - 6, h - 10, col, seed)
}
function billboard(ctx, cx, cy, w, h, rot, kind, K) {
  glowDisc(ctx, cx, cy, Math.max(w, h) * 1.1, kind === 1 ? K.orange : kind === 2 ? K.green : K.blue, 0.3)
  ctx.save(); ctx.translate(cx, cy); ctx.rotate(rot)
  rrPath(ctx, -w / 2 - 3, -h / 2 - 3, w + 6, h + 6, 3); ctx.fillStyle = K.ink; ctx.fill()
  ctx.save(); rrPath(ctx, -w / 2, -h / 2, w, h, 2); ctx.clip()
  if (kind === 0) {   // blue-violet panel, a face-like disc and a neon title bar
    const g = ctx.createLinearGradient(0, -h / 2, 0, h / 2)
    g.addColorStop(0, mix(K.blue, "#ffffff", 0.12)); g.addColorStop(1, mix(K.violet, K.ink, 0.45))
    ctx.fillStyle = g; ctx.fillRect(-w / 2, -h / 2, w, h)
    for (let i = 0; i < 9; i++) { ctx.fillStyle = rgba(K.cyan, 0.18 + (i % 3) * 0.08); ctx.fillRect(-w / 2 + 4 + i * (w / 9), -h / 2 + 3, w / 18, h * (0.25 + 0.08 * ((i * 5) % 4))) }
    dotShape(ctx, 0, -h * 0.02, h * 0.2, K.ink); dotShape(ctx, 0, -h * 0.07, h * 0.17, rgba(K.pink, 0.9))
    ctx.fillStyle = K.ink; ctx.fillRect(-w * 0.28, h * 0.18, w * 0.56, h * 0.34)
    ctx.fillStyle = K.cyan; ctx.fillRect(-w * 0.34, h * 0.3, w * 0.68, 3); ctx.fillRect(-w * 0.34, h * 0.38, w * 0.4, 3)
  } else if (kind === 1) {   // orange sunburst
    ctx.fillStyle = mix(K.orange, K.amber, 0.35); ctx.fillRect(-w / 2, -h / 2, w, h)
    for (let i = 0; i < 12; i++) {
      const a0 = i * Math.PI / 6, a1 = a0 + Math.PI / 12
      ctx.beginPath(); ctx.moveTo(0, h * 0.1)
      ctx.lineTo(Math.cos(a0) * w * 1.4, h * 0.1 + Math.sin(a0) * w * 1.4); ctx.lineTo(Math.cos(a1) * w * 1.4, h * 0.1 + Math.sin(a1) * w * 1.4); ctx.closePath()
      ctx.fillStyle = rgba("#ffffff", 0.2); ctx.fill()
    }
    dotShape(ctx, 0, h * 0.05, h * 0.22, K.ink); dotShape(ctx, 0, h * 0.05, h * 0.17, mix(K.orange, "#ffffff", 0.25))
    ctx.fillStyle = K.ink; ctx.fillRect(-w * 0.4, h * 0.34, w * 0.8, h * 0.1)
  } else {   // tall green screen with a pink diagonal and dots
    const g = ctx.createLinearGradient(0, -h / 2, 0, h / 2)
    g.addColorStop(0, K.green); g.addColorStop(0.55, K.lime); g.addColorStop(1, mix(K.cyan, K.blue, 0.4))
    ctx.fillStyle = g; ctx.fillRect(-w / 2, -h / 2, w, h)
    ctx.beginPath(); ctx.moveTo(w * 0.05, -h / 2); ctx.lineTo(w * 0.3, -h / 2); ctx.lineTo(-w * 0.1, h / 2); ctx.lineTo(-w * 0.35, h / 2); ctx.closePath()
    ctx.fillStyle = rgba(K.pink, 0.85); ctx.fill()
    for (let i = 0; i < 7; i++) dotShape(ctx, -w * 0.3 + ((i * 37) % 60) / 60 * w * 0.7, -h * 0.4 + i * h * 0.13, 4 + (i % 3) * 2, rgba(K.lime, 0.55))
    ctx.fillStyle = rgba(K.ink, 0.55); for (let i = 0; i < 5; i++) ctx.fillRect(-w / 2 + 6, -h / 2 + 10 + i * 18, 5, 12)
  }
  const sh = ctx.createLinearGradient(-w / 2, -h / 2, w / 2, h / 2)
  sh.addColorStop(0, "rgba(255,255,255,0.18)"); sh.addColorStop(0.4, "rgba(255,255,255,0)")
  ctx.fillStyle = sh; ctx.fillRect(-w / 2, -h / 2, w, h)
  ctx.restore()
  ctx.restore()
}
function tower(ctx, x, yBase, w, h, K, rnd, far) {
  const g = ctx.createLinearGradient(0, yBase - h, 0, yBase)
  g.addColorStop(0, far ? mix(K.steel, K.ink, 0.5) : K.steelHi); g.addColorStop(1, far ? K.ink : K.steel)
  ctx.fillStyle = g; ctx.fillRect(x, yBase - h, w, h)
  ctx.fillStyle = rgba(K.cyan, far ? 0.18 : 0.35); ctx.fillRect(x, yBase - h, w, 1.5)
  ctx.fillStyle = rgba("#000000", 0.35); for (let px = x + 14; px < x + w - 4; px += 14 + rnd(0, 8)) ctx.fillRect(px, yBase - h, 1, h)
  if (!far) {
    ctx.fillStyle = K.steel; ctx.fillRect(x + w * 0.15, yBase - h - 6, w * 0.25, 6)
    if (rnd(0, 1) > 0.4) {
      const ax = x + w * rnd(0.55, 0.9)
      ctx.fillStyle = K.steelHi; ctx.fillRect(ax, yBase - h - 22, 1.6, 22)
      glowDisc(ctx, ax + 0.8, yBase - h - 22, 7, K.red, 0.7)
    }
    ctx.fillStyle = K.ink; ctx.fillRect(x + w - 4, yBase - h, 3, h)   // drain pipe
  }
  const cw = 8, ch = 10, lit = far ? 0.9 : 0.58
  for (let wy = yBase - h + 8; wy < yBase - 8; wy += ch + 3) {
    const rowLit = rnd(0, 1) > 0.9
    for (let wx = x + 5; wx < x + w - cw - 4; wx += cw + 4) {
      const v = rowLit ? rnd(0.6, 0.9) : rnd(0, 1)
      if (v < lit) continue
      const c = v > 0.96 ? K.cyan : v > 0.9 ? K.orange : v > 0.7 ? K.amber : mix(K.amber, K.orange, 0.5)
      const a = far ? 0.35 : 0.5 + 0.4 * rnd(0, 1)
      ctx.fillStyle = rgba(c, 0.14 * a / 0.5); ctx.fillRect(wx - 1.5, wy - 1.5, cw + 3, ch + 3)
      ctx.fillStyle = rgba(c, a); ctx.fillRect(wx, wy, cw, ch)
    }
  }
  if (!far && rnd(0, 1) > 0.45) {   // neon sign stuck to the facade
    const c = [K.red, K.pink, K.cyan][Math.floor(rnd(0, 3))], sx = x + w - 16, sy = yBase - h * rnd(0.35, 0.8)
    glowDisc(ctx, sx + 4, sy + 14, 22, c, 0.35); ctx.fillStyle = c; ctx.fillRect(sx, sy, 8, 28)
    ctx.fillStyle = K.ink; for (let i = 0; i < 4; i++) ctx.fillRect(sx + 2, sy + 3 + i * 6, 4, 1.4)
  }
}
function girder(ctx, x0, y0, x1, h, K) {
  ctx.fillStyle = K.steel2; ctx.fillRect(x0, y0, x1 - x0, h)
  ctx.fillStyle = K.steelHi; ctx.fillRect(x0, y0, x1 - x0, 2.5); ctx.fillRect(x0, y0 + h - 2.5, x1 - x0, 2.5)
  ctx.lineWidth = 1.4; ctx.strokeStyle = K.steelHi
  ctx.beginPath()
  for (let x = x0; x < x1 - h; x += h) { ctx.moveTo(x, y0 + 2); ctx.lineTo(x + h, y0 + h - 2); ctx.moveTo(x + h, y0 + 2); ctx.lineTo(x, y0 + h - 2) }
  ctx.stroke()
  ctx.fillStyle = K.ink; ctx.fillRect(x0, y0 + h, x1 - x0, 2)
  let t = x0 + 8
  const r = seeded(Math.round(x0))
  while (t < x1 - 8) { const len = r(8, 40); neonLine(ctx, [[t, y0 + h + 3], [Math.min(t + len, x1 - 8), y0 + h + 3]], K.cyan, 1.3, 0.8); t += len + r(10, 40) }
}
function taxi(ctx, x, y, dir, K) {
  glowDisc(ctx, x, y + 3, 22, K.amber, 0.28)
  rrPath(ctx, x - 9, y - 4, 18, 8, 3); ctx.fillStyle = K.taxi; ctx.fill()
  ctx.fillStyle = K.ink; ctx.fillRect(x - 4, y - 3, 8, 3)
  glowDisc(ctx, x + dir * 10, y, 9, "#ffffff", 0.75); glowDisc(ctx, x - dir * 10, y, 6, K.red, 0.8)
  ctx.fillStyle = rgba(K.cyan, 0.5); ctx.fillRect(x - 7, y + 6, 14, 1.5)   // hover glow
}
function megacity(ctx, W, H, o) {
  const p = palette(o.colors), B = BAND
  const K = o.follow
    ? { ink: mix(p.dark, "#000000", 0.45), steel: mix(p.dark, p.bg, 0.35), steel2: mix(p.dark, p.bg, 0.7), steelHi: mix(p.bg, p.fg, 0.14), cable: mix(p.dark, "#000000", 0.5),
        cyan: p.cyan, orange: p.orange, amber: p.byellow, red: p.red, pink: p.magenta, blue: p.blue, violet: p.magenta, green: p.green, lime: mix(p.green, p.byellow, 0.5), taxi: p.byellow }
    : { ink: "#07090d", steel: "#12161d", steel2: "#1b212b", steelHi: "#2b3441", cable: "#07090c",
        cyan: "#3fd8ff", orange: "#ff8a3d", amber: "#ffd36b", red: "#ff4f6d", pink: "#ff7ab8", blue: "#4a6dff", violet: "#7a5cff", green: "#58d68a", lime: "#d6f26b", taxi: "#ffc928" }
  const rnd = seeded(5331)

  // haze: a cool beam from the top centre-right, warm glow low left, teal glow low right
  const beam = ctx.createLinearGradient(0, B, 0, B + 420)
  beam.addColorStop(0, rgba(K.cyan, 0.13)); beam.addColorStop(1, rgba(K.cyan, 0))
  ctx.beginPath(); ctx.moveTo(W * 0.6, B); ctx.lineTo(W * 0.66, B); ctx.lineTo(W * 0.74, B + 420); ctx.lineTo(W * 0.52, B + 420); ctx.closePath()
  ctx.fillStyle = beam; ctx.fill()
  glowDisc(ctx, 140, H - 60, 380, K.orange, 0.13); glowDisc(ctx, W - 200, H - 40, 420, K.cyan, 0.1); glowDisc(ctx, 120, 90, 300, K.cyan, 0.09)
  glowDisc(ctx, W - 160, 120, 300, K.blue, 0.12)

  // apartment blocks on the bottom edge, left and right
  let bx = B
  while (bx < Math.min(W * 0.3, 580)) { const w = rnd(60, 110), h = rnd(150, 270); tower(ctx, bx, H - B + 2, w, h, K, rnd, true); bx += w * 0.8 }
  bx = W - B
  while (bx > W - Math.min(W * 0.22, 440)) { const w = rnd(60, 110), h = rnd(130, 240); bx -= w * 0.8; tower(ctx, bx, H - B + 2, w, h, K, rnd, true) }
  bx = B
  while (bx < Math.min(W * 0.27, 520)) { const w = rnd(46, 84), h = rnd(70, 190); tower(ctx, bx, H - B + 2, w, h, K, rnd); bx += w + rnd(2, 8) }
  bx = W - B
  while (bx > W - Math.min(W * 0.2, 400)) { const w = rnd(46, 84), h = rnd(60, 160); bx -= w; tower(ctx, bx, H - B + 2, w, h, K, rnd); bx -= rnd(2, 8) }

  // the billboard in front of the left blocks
  billboard(ctx, 78, H - 150, 92, 168, 0, 2, K)

  // steel truss band
  const g = ctx.createLinearGradient(0, 0, 0, H)
  g.addColorStop(0, K.steel2); g.addColorStop(0.5, K.steel); g.addColorStop(1, K.steel2)
  band(ctx, W, H, g, 6, 3, false)
  ctx.save(); bandClip(ctx, W, H, 6, 3)
  ctx.lineWidth = 2; ctx.strokeStyle = mix(K.steelHi, K.cyan, 0.12)
  const zig = (x0, y0, x1, y1, n) => {
    const dx = (x1 - x0) / n, dy = (y1 - y0) / n
    ctx.beginPath()
    for (let i = 0; i <= n; i++) {
      const horiz = Math.abs(dx) > Math.abs(dy), up = i % 2 === 0
      const px = x0 + dx * i + (horiz ? 0 : (up ? 0 : 12)), py = y0 + dy * i + (horiz ? (up ? 0 : 12) : 0)
      if (i === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py)
    }
    ctx.stroke()
  }
  zig(0, 4, W, 4, Math.round(W / 14)); zig(0, H - 16, W, H - 16, Math.round(W / 14))
  zig(4, 0, 4, H, Math.round(H / 14)); zig(W - 16, 0, W - 16, H, Math.round(H / 14))
  ctx.restore()
  ctx.lineWidth = 1; ctx.strokeStyle = rgba("#000000", 0.7)
  ctx.beginPath(); ctx.rect(B - 0.5, B - 0.5, W - 2 * B + 1, H - 2 * B + 1); ctx.stroke()

  // cyan strip-light rim: dashes of different lengths, as on the skybridge
  const dash = (e, from, to) => {
    let t = from
    while (t < to) {
      const len = rnd(6, 34), c = rnd(0, 1) > 0.72 ? "#ffffff" : K.cyan
      const a = edgeXY(W, H, e, t, B - 1), b = edgeXY(W, H, e, Math.min(t + len, to), B - 1)
      neonLine(ctx, [a, b], c, 1.5, c === K.cyan ? 0.9 : 0.95)
      t += len + rnd(5, 22)
    }
  }
  dash(0, B + 6, W - B - 6); dash(3, B + 6, H - B - 6); dash(1, B + 6, H - B - 6)
  // bottom rim in amber and cyan (the lit street below)
  { let t = B + 6; while (t < W - B - 6) { const len = rnd(10, 40), c = rnd(0, 1) > 0.5 ? K.amber : K.cyan; neonLine(ctx, [[t, H - B + 1], [Math.min(t + len, W - B - 6), H - B + 1]], c, 1.4, 0.75); t += len + rnd(8, 26) } }

  // sagging cables
  cable(ctx, 0, 70, 340, B, 70, K); cable(ctx, 300, B, 700, B, 46, K); cable(ctx, 640, B, 1010, B, 62, K)
  cable(ctx, W * 0.55, B, W - 30, 96, 80, K); cable(ctx, W - B, 300, W - B, 520, 44, K); cable(ctx, B, 330, B, 560, 36, K)
  cable(ctx, 380, H - B, 700, H - B, -44, K)

  // steel girder across the top (cables and signs hang from it)
  girder(ctx, W * 0.3, B, W - B, 26, K)
  hangSign(ctx, W * 0.36, B + 28, B + 38, 28, 84, K.pink, 11, K)
  hangSign(ctx, W * 0.47, B + 28, B + 34, 26, 66, K.cyan, 29, K)
  hangSign(ctx, W * 0.7, B + 28, B + 66, 30, 96, K.orange, 47, K)
  hangSign(ctx, W - 210, B + 28, B + 40, 24, 60, K.red, 71, K)

  // billboards from the top: a tilted pair on the left and a tall blue one at the top right
  billboard(ctx, 226, 74, 138, 82, -0.2, 0, K)
  billboard(ctx, 360, 96, 78, 96, 0.25, 1, K)
  billboard(ctx, W - 74, 100, 92, 156, 0, 0, K)

  // side signs jutting out of the right band
  ;[[0.42, K.red], [0.62, K.cyan]].forEach((s, i) => {
    const y = H * s[0], x = W - B - 34
    glowDisc(ctx, x + 14, y + 20, 34, s[1], 0.3)
    ctx.fillStyle = K.ink; ctx.fillRect(x, y, 28, 42); ctx.lineWidth = 1; ctx.strokeStyle = rgba(s[1], 0.9); ctx.strokeRect(x + 1.5, y + 1.5, 25, 39)
    glyphs(ctx, x + 3, y + 4, 22, 34, s[1], 91 + i * 13)
    ctx.fillStyle = K.steelHi; ctx.fillRect(x + 28, y + 18, 6, 3)
  })

  // skybridge across the bottom with a strip-light deck and pole lamps
  const bx0 = W * 0.5, bx1 = W * 0.78, by = H - B - 4
  ctx.fillStyle = K.steel2; ctx.fillRect(bx0, by - 9, bx1 - bx0, 9)
  { let t = bx0 + 4; while (t < bx1 - 4) { const len = rnd(8, 30), c = rnd(0, 1) > 0.35 ? "#ffffff" : K.cyan; neonLine(ctx, [[t, by - 5], [Math.min(t + len, bx1 - 4), by - 5]], c, 2, 0.95); t += len + rnd(5, 12) } }
  ctx.strokeStyle = K.steelHi; ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(bx0, by - 22); ctx.lineTo(bx1, by - 22); ctx.stroke()
  for (let x = bx0 + 6; x <= bx1; x += 22) { ctx.beginPath(); ctx.moveTo(x, by - 9); ctx.lineTo(x, by - 22); ctx.stroke() }
  for (let x = bx0 + 40; x < bx1; x += 110) { ctx.fillStyle = K.steelHi; ctx.fillRect(x, by - 40, 1.6, 18); glowDisc(ctx, x + 0.8, by - 40, 12, K.amber, 0.75) }

  // flying taxis in the lanes above the bridge and in the lower right
  taxi(ctx, W * 0.58, H - 110, 1, K); taxi(ctx, W * 0.66, H - 150, -1, K); taxi(ctx, W * 0.88, H - 190, 1, K); taxi(ctx, W * 0.93, H - 120, -1, K)
  taxi(ctx, W * 0.31, H - 90, 1, K)

  // top-left corner: stacked cyan light strips
  ;[[30, 40, 150, 30], [50, 62, 120, 55], [20, 88, 70, 80]].forEach((s) => neonLine(ctx, [[B + s[0], s[1] + B], [B + s[0] + s[2] - 20, s[3] + B]], K.cyan, 1.6, 0.85))

  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0 = W * 0.4 - tw / 2
    ctx.fillStyle = K.ink; rrPath(ctx, x0 - 14, H - 21, tw + 28, 19, 3); ctx.fill()
    rrPath(ctx, x0 - 13, H - 20, tw + 26, 17, 3); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.pink, 0.9); ctx.stroke()
    ctx.fillStyle = rgba(K.pink, 0.3); spaced(ctx, t, x0 + 0.5, H - 7, sp, "left")
    ctx.fillStyle = mix(K.pink, "#ffffff", 0.6); spaced(ctx, t, x0, H - 7.5, sp, "left")
  }
}

// ---- GILDED: art nouveau gold, ornaments made with ComfyUI (assets/*.png) -----
// Image loading is per Canvas (one per monitor), so ask each Canvas itself, never a shared flag.
function artUrl(ctx, o, name) {
  const cv = ctx.canvas
  if (!o.assets || !cv || !cv.isImageLoaded) return ""
  const u = o.assets + name + (o.rev ? "?r=" + o.rev : "")   // o.rev: bumps when a picture changed, bypasses the Canvas image cache
  if (cv.isImageLoaded(u)) return u
  if (!cv.isImageLoading(u) && !cv.isImageError(u)) cv.loadImage(u)
  return ""
}
function gilded(ctx, W, H, o) {
  const p = palette(o.colors), B = BAND
  const K = o.follow
    ? { ink: mix(p.dark, "#000000", 0.3), gold: mix(p.accent, "#ffffff", 0.3), deep: p.accent, tint: p.accent }
    : { ink: "#0a0b18", gold: "#ecc977", deep: "#b3822f", tint: "" }
  const S = 400
  // 1) ornaments first: they are the only thing on the canvas, so a source-atop fill can tint them
  const ca = artUrl(ctx, o, "corner_a.png"), cb = artUrl(ctx, o, "corner_b.png"), md = artUrl(ctx, o, "medallion.png")
  if (ca) { ctx.drawImage(ca, 0, 0, S, S); ctx.save(); ctx.translate(W, 0); ctx.scale(-1, 1); ctx.drawImage(ca, 0, 0, S, S); ctx.restore() }
  if (cb) {
    ctx.save(); ctx.translate(0, H); ctx.scale(1, -1); ctx.drawImage(cb, 0, 0, S, S); ctx.restore()
    ctx.save(); ctx.translate(W, H); ctx.scale(-1, -1); ctx.drawImage(cb, 0, 0, S, S); ctx.restore()
  }
  if (md) ctx.drawImage(md, W / 2 - 100, -55, 200, 200)
  if (K.tint) {
    ctx.globalCompositeOperation = "source-atop"
    ctx.fillStyle = rgba(K.tint, 0.72); ctx.fillRect(0, 0, W, H)
    ctx.globalCompositeOperation = "source-over"
  }
  if (md) {   // soft dark backing so the medallion reads over bright windows
    ctx.globalCompositeOperation = "destination-over"
    const g = ctx.createRadialGradient(W / 2, 40, 10, W / 2, 40, 100)
    g.addColorStop(0, rgba(K.ink, 0.8)); g.addColorStop(0.8, rgba(K.ink, 0.6)); g.addColorStop(1, rgba(K.ink, 0))
    ctx.fillStyle = g; ctx.fillRect(W / 2 - 100, 0, 200, 140)
    ctx.globalCompositeOperation = "source-over"
  }
  // 2) the band, drawn over the ornaments so they grow out from under it
  band(ctx, W, H, K.ink, 16, 7, false)
  rrPath(ctx, 3.5, 3.5, W - 7, H - 7, 13)
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.deep, 0.9); ctx.stroke()
  const g2 = ctx.createLinearGradient(0, 0, W, H)
  g2.addColorStop(0, K.gold); g2.addColorStop(0.5, K.deep); g2.addColorStop(1, K.gold)
  rrPath(ctx, 18.5, 18.5, W - 37, H - 37, 5)
  ctx.lineWidth = 2; ctx.strokeStyle = g2; ctx.stroke()
  // a thin gold vine with diamonds along the middle of the band
  const vine = function (x0, y0, x1, y1) {
    const len = Math.hypot(x1 - x0, y1 - y0), ux = (x1 - x0) / len, uy = (y1 - y0) / len
    ctx.beginPath()
    for (let t = 0; t <= len; t += 3) {
      const a = Math.sin(t / 60 * Math.PI * 2) * 2.2
      const x = x0 + ux * t - uy * a, y = y0 + uy * t + ux * a
      if (t === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
    }
    ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.5); ctx.stroke()
    ctx.fillStyle = rgba(K.gold, 0.9)
    for (let t = 15; t < len; t += 60) {
      const x = x0 + ux * t - uy * 2.2, y = y0 + uy * t + ux * 2.2
      ctx.beginPath(); ctx.moveTo(x, y - 3); ctx.lineTo(x + 2.4, y); ctx.lineTo(x, y + 3); ctx.lineTo(x - 2.4, y); ctx.closePath(); ctx.fill()
    }
  }
  const m = B + 4
  vine(S * 0.55, 11, W - S * 0.55, 11)
  vine(S * 0.55, H - 11, W - S * 0.55, H - 11)
  vine(11, S * 0.55, 11, H - S * 0.55)
  vine(W - 11, S * 0.55, W - 11, H - S * 0.55)
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0 = W * 0.4 - tw / 2
    ctx.fillStyle = K.ink; rrPath(ctx, x0 - 14, H - 21, tw + 28, 19, 9.5); ctx.fill()
    rrPath(ctx, x0 - 13, H - 20, tw + 26, 17, 8.5); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.9); ctx.stroke()
    ctx.fillStyle = K.gold; spaced(ctx, t, x0, H - 7.5, sp, "left")
  }
}

// ---- PASTEUP: a city paste-up wall around the window. The dark panel band comes from the ComfyUI graph `frame_object_bezel`
// (assets/pasteup_band.png); the notes, tape and holo stickers are cut-outs from the graph `frame_prop` (assets/pasteup_props.png,
// placed by tools/compose-props.py) and overlap only a little. Follow mode tints the band only. ----
function pasteup(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow ? { ink: mix(p.dark, "#000000", 0.4), line: p.accent, tint: p.accent } : { ink: "#080a12", line: "#ffb347", tint: "" }
  const bandImg = artUrl(ctx, o, "pasteup_band.png"), props = artUrl(ctx, o, "pasteup_props.png")
  if (bandImg) {
    ctx.drawImage(bandImg, 0, 0, W, H)
    if (K.tint) {
      ctx.globalCompositeOperation = "source-atop"
      ctx.fillStyle = rgba(K.tint, 0.25); ctx.fillRect(0, 0, W, H)
      ctx.globalCompositeOperation = "source-over"
    }
  } else band(ctx, W, H, mix(K.ink, K.line, 0.15), 14, 6, false)
  if (props) ctx.drawImage(props, 0, 0, W, H)
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0t = W * 0.5 - tw / 2
    ctx.fillStyle = rgba(K.ink, 0.92); rrPath(ctx, x0t - 14, H - 21, tw + 28, 19, 4); ctx.fill()
    rrPath(ctx, x0t - 13, H - 20, tw + 26, 17, 3); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.line, 0.85); ctx.stroke()
    ctx.fillStyle = mix(K.line, "#ffffff", 0.6); spaced(ctx, t, x0t, H - 7.5, sp, "left")
  }
}

// ---- RUNEFORGE / NEXUS / EMBERGOTH: game-UI frames. The 1920x1080 frame (assets/<style>_frame.png) is assembled by the ComfyUI graph
// `frame_ui_assemble` from a rail strip (`frame_ui_rail`), a corner piece and a crest (`frame_ui_piece`); here it is cut like a 9-slice so any window size
// keeps the corners and the crest undistorted and only stretches the rails along their length. Follow mode tints it with the theme accent. ----
var UIFRAME = {
  RUNEFORGE: { file: "runeforge_frame.png", cs: 160, crest: 250, trim: "#ff9a3c", ink: "#120c08" },
  NEXUS: { file: "nexus_frame.png", cs: 160, crest: 250, trim: "#35e0ff", ink: "#070d14" },
  EMBERGOTH: { file: "embergoth_frame.png", cs: 160, crest: 250, trim: "#ff3a2d", ink: "#0d0808" },
  ABYSS: { file: "abyss_frame.png", cs: 160, crest: 250, trim: "#3fe0d0", ink: "#06121a" },
  HANAMI: { file: "hanami_frame.png", cs: 160, crest: 250, trim: "#f58fb0", ink: "#0e0a10" },
  WILDWOOD: { file: "wildwood_frame.png", cs: 160, crest: 250, trim: "#7ddc5a", ink: "#0c120a" },
  DRIFTWOOD: { file: "driftwood_frame.png", cs: 30, crest: 0, trim: "#cfc8ba", ink: "#14130f" },
  SLATE: { file: "slate_frame.png", cs: 30, crest: 0, trim: "#a9bdb2", ink: "#0d1214" },
  LEATHER: { file: "leather_frame.png", cs: 30, crest: 0, trim: "#dcc9a2", ink: "#140b08" },
  TIDEPOOL: { file: "tidepool_frame.png", cs: 160, crest: 250, trim: "#8fc7d8", ink: "#08121a" },
  CHERRYBARK: { file: "cherrybark_frame.png", cs: 160, crest: 250, trim: "#e7b3bf", ink: "#140c0e" },
  MOSSWOOD: { file: "mosswood_frame.png", cs: 160, crest: 250, trim: "#a6c46a", ink: "#0c120a" },
  WALNUT: { file: "walnut_frame.png", cs: 30, crest: 0, trim: "#c9a27a", ink: "#140c08" },
  BAMBOO: { file: "bamboo_frame.png", cs: 30, crest: 0, trim: "#d7e39a", ink: "#0e140a" },
  BIRCH: { file: "birch_frame.png", cs: 30, crest: 0, trim: "#e6e0d2", ink: "#14130f" },
  LINEN: { file: "linen_frame.png", cs: 30, crest: 0, trim: "#d9c7a3", ink: "#14110c" },
  TERRACOTTA: { file: "terracotta_frame.png", cs: 30, crest: 0, trim: "#f0a070", ink: "#180d08" },
  BRICK: { file: "brick_frame.png", cs: 30, crest: 0, trim: "#d99a85", ink: "#150a08" },
  SANDSTONE: { file: "sandstone_frame.png", cs: 30, crest: 0, trim: "#f2c58a", ink: "#16100a" },
  MARBLE: { file: "marble_frame.png", cs: 30, crest: 0, trim: "#e4e6ea", ink: "#0e1014" },
  CONCRETE: { file: "concrete_frame.png", cs: 30, crest: 0, trim: "#b8bbbd", ink: "#0e0f10" },
  RUST: { file: "rust_frame.png", cs: 30, crest: 0, trim: "#e8864a", ink: "#150a06" }
}
function uiframe(ctx, W, H, o, spec) {
  const p = palette(o.colors)
  const trim = o.follow ? p.accent : spec.trim
  const img = artUrl(ctx, o, spec.file)
  const SW = 1920, SH = 1080
  if (img) {
    const sc = Math.max(0.5, Math.min(1, W / 1500, H / 850))
    const cs = spec.cs, cd = cs * sc, cw = spec.crest
    const d = function (sx, sy, sw, sh, dx, dy, dw, dh) { if (sw > 0 && sh > 0 && dw > 0 && dh > 0) ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh) }
    const cx0 = SW / 2 - cw / 2, dcx0 = W / 2 - cw * sc / 2
    d(0, 0, cs, cs, 0, 0, cd, cd); d(SW - cs, 0, cs, cs, W - cd, 0, cd, cd)
    d(0, SH - cs, cs, cs, 0, H - cd, cd, cd); d(SW - cs, SH - cs, cs, cs, W - cd, H - cd, cd, cd)
    d(cs, 0, cx0 - cs, cs, cd, 0, dcx0 - cd, cd)
    d(cx0 + cw, 0, SW - cs - cx0 - cw, cs, dcx0 + cw * sc, 0, W - cd - dcx0 - cw * sc, cd)
    d(cx0, 0, cw, cs, dcx0, 0, cw * sc, cd)
    d(cs, SH - cs, SW - 2 * cs, cs, cd, H - cd, W - 2 * cd, cd)
    d(0, cs, cs, SH - 2 * cs, 0, cd, cd, H - 2 * cd); d(SW - cs, cs, cs, SH - 2 * cs, W - cd, cd, cd, H - 2 * cd)
    if (o.follow) {
      ctx.globalCompositeOperation = "source-atop"
      ctx.fillStyle = rgba(p.accent, 0.3); ctx.fillRect(0, 0, W, H)
      ctx.globalCompositeOperation = "source-over"
    }
  } else band(ctx, W, H, mix(spec.ink, trim, 0.2), 12, 6, false)
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0t = W * 0.5 - tw / 2
    ctx.fillStyle = rgba(spec.ink, 0.94); rrPath(ctx, x0t - 14, H - 21, tw + 28, 19, 3); ctx.fill()
    rrPath(ctx, x0t - 13, H - 20, tw + 26, 17, 2); ctx.lineWidth = 1; ctx.strokeStyle = rgba(trim, 0.9); ctx.stroke()
    ctx.fillStyle = mix(trim, "#ffffff", 0.55); spaced(ctx, t, x0t, H - 7.5, sp, "left")
  }
}
function runeforge(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.RUNEFORGE) }
function nexus(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.NEXUS) }
function embergoth(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.EMBERGOTH) }
function abyss(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.ABYSS) }
function hanami(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.HANAMI) }
function wildwood(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.WILDWOOD) }
function driftwood(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.DRIFTWOOD) }
function slate(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.SLATE) }
function leather(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.LEATHER) }
function tidepool(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.TIDEPOOL) }
function cherrybark(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.CHERRYBARK) }
function mosswood(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.MOSSWOOD) }
function walnut(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.WALNUT) }
function bamboo(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.BAMBOO) }
function birch(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.BIRCH) }
function linen(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.LINEN) }
function terracotta(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.TERRACOTTA) }
function brick(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.BRICK) }
function sandstone(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.SANDSTONE) }
function marble(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.MARBLE) }
function concrete(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.CONCRETE) }
function rust(ctx, W, H, o) { uiframe(ctx, W, H, o, UIFRAME.RUST) }

// ---- BLUEPRINT: drafting sheet, grid, dimension lines; fitted: ruler strips and registration targets outside ----
function blueprint(ctx, W, H, o) {
  const p = palette(o.colors)
  let bg = "#0a2748", ln = "#a8d8ff", gr = "#2d6aa6"
  if (o.follow) { bg = mix(p.dark, p.accent, 0.22); ln = mix(p.accent, "#ffffff", 0.55); gr = mix(bg, p.accent, 0.45) }
  const B = o.bleed || 0
  if (B) {
    // outer contour: a ruler strip along each edge and a registration target on each corner
    const r = 13
    ctx.fillStyle = rgba(bg, 0.96); ctx.strokeStyle = rgba(ln, 0.8); ctx.lineWidth = 1
    ctx.fillRect(24, -r, W - 48, r + 2); ctx.fillRect(24, H - 2, W - 48, r + 2)
    ctx.fillRect(-r, 24, r + 2, H - 48); ctx.fillRect(W - 2, 24, r + 2, H - 48)
    ctx.beginPath()
    ctx.moveTo(24, -r + 0.5); ctx.lineTo(W - 24, -r + 0.5); ctx.moveTo(24, H + r - 0.5); ctx.lineTo(W - 24, H + r - 0.5)
    ctx.moveTo(-r + 0.5, 24); ctx.lineTo(-r + 0.5, H - 24); ctx.moveTo(W + r - 0.5, 24); ctx.lineTo(W + r - 0.5, H - 24)
    ctx.stroke()
    ctx.beginPath()
    for (let x = 24, n = 0; x <= W - 24; x += 10, n++) {
      const l = n % 5 === 0 ? 8 : 4
      ctx.moveTo(x + 0.5, -2); ctx.lineTo(x + 0.5, -2 - l); ctx.moveTo(x + 0.5, H + 2); ctx.lineTo(x + 0.5, H + 2 + l)
    }
    for (let y = 24, n = 0; y <= H - 24; y += 10, n++) {
      const l = n % 5 === 0 ? 8 : 4
      ctx.moveTo(-2, y + 0.5); ctx.lineTo(-2 - l, y + 0.5); ctx.moveTo(W + 2, y + 0.5); ctx.lineTo(W + 2 + l, y + 0.5)
    }
    ctx.strokeStyle = rgba(ln, 0.75); ctx.stroke()
    setFont(ctx, o, 8, false); ctx.fillStyle = rgba(ln, 0.85)
    for (let x = 24, n = 0; x <= W - 70; x += 50, n++) if (n % 2 === 0 && n > 0) ctx.fillText(String(n * 50), x + 3, -4)
    for (let i = 0; i < 4; i++) {
      const cx = i % 2 ? W + 9 : -9, cy = i < 2 ? -9 : H + 9
      ctx.beginPath(); ctx.moveTo(cx, cy); ctx.lineTo(i % 2 ? W - 4 : 4, i < 2 ? 4 : H - 4)
      ctx.lineWidth = 3; ctx.strokeStyle = rgba(bg, 1); ctx.stroke()
      ctx.beginPath(); ctx.arc(cx, cy, 8, 0, Math.PI * 2); ctx.fillStyle = bg; ctx.fill()
      ctx.lineWidth = 1; ctx.strokeStyle = ln; ctx.stroke()
      ctx.beginPath(); ctx.moveTo(cx - 14, cy); ctx.lineTo(cx + 14, cy); ctx.moveTo(cx, cy - 14); ctx.lineTo(cx, cy + 14); ctx.stroke()
      ctx.beginPath(); ctx.arc(cx, cy, 2.2, 0, Math.PI * 2); ctx.fillStyle = ln; ctx.fill()
    }
  }
  band(ctx, W, H, bg, 3, 2, false)
  // paper grid inside the band
  ctx.save(); bandClip(ctx, W, H, 3, 2)
  ctx.beginPath()
  for (let x = 0; x < W; x += 11) { ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, H) }
  for (let y = 0; y < H; y += 11) { ctx.moveTo(0, y + 0.5); ctx.lineTo(W, y + 0.5) }
  ctx.lineWidth = 1; ctx.strokeStyle = rgba(gr, 0.35); ctx.stroke()
  ctx.restore()
  // sheet border: heavy outer line, light inner line, bright line hugging the windows
  rrPath(ctx, 3.5, 3.5, W - 7, H - 7, 2); ctx.lineWidth = 1.5; ctx.strokeStyle = rgba(ln, 0.9); ctx.stroke()
  rrPath(ctx, 7.5, 7.5, W - 15, H - 15, 1); ctx.lineWidth = 1; ctx.strokeStyle = rgba(ln, 0.35); ctx.stroke()
  rrPath(ctx, BAND - 0.5, BAND - 0.5, W - 2 * BAND + 1, H - 2 * BAND + 1, 2); ctx.lineWidth = 1.5; ctx.strokeStyle = ln; ctx.stroke()
  // dimension line along the bottom: arrows at both ends, the window width in the gap
  const dim = function (x0, x1, y, txt, vert) {
    ctx.save()
    if (vert) { ctx.translate(y, x0); ctx.rotate(Math.PI / 2); x1 -= x0; x0 = 0; y = 0 } else { ctx.translate(0, y); x1 -= 0 }
    setFont(ctx, o, 9, false)
    const tw = ctx.measureText(txt).width, mid = (x0 + x1) / 2
    ctx.strokeStyle = rgba(ln, 0.9); ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(x0, 0); ctx.lineTo(mid - tw / 2 - 5, 0); ctx.moveTo(mid + tw / 2 + 5, 0); ctx.lineTo(x1, 0)
    ctx.moveTo(x0, -4); ctx.lineTo(x0, 4); ctx.moveTo(x1, -4); ctx.lineTo(x1, 4)
    ctx.stroke()
    ctx.fillStyle = ln
    ctx.beginPath(); ctx.moveTo(x0, 0); ctx.lineTo(x0 + 7, -2.5); ctx.lineTo(x0 + 7, 2.5); ctx.closePath()
    ctx.moveTo(x1, 0); ctx.lineTo(x1 - 7, -2.5); ctx.lineTo(x1 - 7, 2.5); ctx.closePath(); ctx.fill()
    ctx.fillText(txt, mid - tw / 2, 3.5)
    ctx.restore()
  }
  dim(130, W - 60, H - 11, String(Math.round(W - 2 * BAND)) + " px", false)
  dim(60, H - 60, 11, String(Math.round(H - 2 * BAND)) + " px", true)
  // registration crosshairs, middle of the top and right edges
  const cross = function (cx, cy) {
    ctx.beginPath(); ctx.arc(cx, cy, 4.5, 0, Math.PI * 2)
    ctx.moveTo(cx - 8, cy); ctx.lineTo(cx + 8, cy); ctx.moveTo(cx, cy - 8); ctx.lineTo(cx, cy + 8)
    ctx.lineWidth = 1; ctx.strokeStyle = rgba(ln, 0.8); ctx.stroke()
  }
  cross(W / 2, 12); cross(W - 11, H / 2)
  // title block, top left
  if (o.text) {
    setFont(ctx, o, 11, true)
    const t = o.text, sp = 2, tw = spacedWidth(ctx, t, sp), x0 = 34
    ctx.fillStyle = bg; ctx.fillRect(x0 - 6, 3, tw + 62, 17)
    ctx.lineWidth = 1; ctx.strokeStyle = ln; ctx.strokeRect(x0 - 5.5, 3.5, tw + 61, 16)
    ctx.beginPath(); ctx.moveTo(x0 + tw + 8.5, 3.5); ctx.lineTo(x0 + tw + 8.5, 19.5); ctx.stroke()
    ctx.fillStyle = ln; spaced(ctx, t, x0 + 1, 15.5, sp, "left")
    setFont(ctx, o, 8, false); ctx.fillText("REV A", x0 + tw + 13, 14.5)
  }
}

// ---- CORALREEF: Flux concept art (assets/coralreef_corners.png, cut by tools/coral-corners.py). Four coral corner pieces sit on a
// dark teal rail; fitted to a small window they stick BLEED px out past the rectangle. Follow mode tints with the theme accent. ----
var CORAL_PIECES = [[0, 0, 430, 300], [430, 0, 430, 300], [860, 0, 380, 328], [1240, 0, 380, 328]]
function coralreef(ctx, W, H, o) {
  const p = palette(o.colors)
  const K = o.follow
    ? { rail: mix(p.dark, "#000000", 0.25), glow: p.accent, gold: mix(p.accent, "#ffffff", 0.35), tint: p.accent }
    : { rail: "#06222c", glow: "#3fe0d0", gold: "#e8a33a", tint: "" }
  const B = o.bleed || 0
  band(ctx, W, H, K.rail, 6, 4, false)
  ctx.save(); bandClip(ctx, W, H, 6, 4)
  ctx.lineWidth = 3; ctx.strokeStyle = rgba(K.glow, 0.18); rrPath(ctx, BAND - 3, BAND - 3, W - 2 * BAND + 6, H - 2 * BAND + 6, 5); ctx.stroke()
  ctx.restore()
  rrPath(ctx, BAND - 1.5, BAND - 1.5, W - 2 * BAND + 3, H - 2 * BAND + 3, 4); ctx.lineWidth = 1.5; ctx.strokeStyle = rgba(K.glow, 0.9); ctx.stroke()
  rrPath(ctx, 3.5, 3.5, W - 7, H - 7, 5); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.75); ctx.stroke()
  const pearl = function (x, y) {
    ctx.beginPath(); ctx.arc(x, y, 3.4, 0, Math.PI * 2); ctx.fillStyle = mix(K.glow, "#ffffff", 0.7); ctx.fill()
    ctx.beginPath(); ctx.arc(x - 1, y - 1, 1.2, 0, Math.PI * 2); ctx.fillStyle = "rgba(255,255,255,0.95)"; ctx.fill()
  }
  const step = 88
  for (let x = 190 + step / 2; x < W - 190; x += step) { pearl(x, 11); pearl(x, H - 11) }
  for (let y = 150 + step / 2; y < H - 150; y += step) { pearl(11, y); pearl(W - 11, y) }
  const img = artUrl(ctx, o, "coralreef_corners.png")
  if (img) {
    const sc = Math.max(0.3, Math.min(0.75, Math.min(W, H) * 0.34 / 300))
    for (let i = 0; i < 4; i++) {
      const s = CORAL_PIECES[i], w = s[2] * sc, h = s[3] * sc
      ctx.drawImage(img, s[0], s[1], s[2], s[3], i % 2 ? W + B - w : -B, i < 2 ? -B : H + B - h, w, h)
    }
  }
  if (K.tint) {
    ctx.globalCompositeOperation = "source-atop"
    ctx.fillStyle = rgba(K.tint, 0.22); ctx.fillRect(-B, -B, W + 2 * B, H + 2 * B)
    ctx.globalCompositeOperation = "source-over"
  }
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0t = W * 0.5 - tw / 2
    ctx.fillStyle = rgba(K.rail, 0.95); rrPath(ctx, x0t - 14, H - 21, tw + 28, 19, 9.5); ctx.fill()
    rrPath(ctx, x0t - 13, H - 20, tw + 26, 17, 8.5); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.gold, 0.9); ctx.stroke()
    ctx.fillStyle = mix(K.glow, "#ffffff", 0.55); spaced(ctx, t, x0t, H - 7.5, sp, "left")
  }
}

// ---- FROST / SAKURA / COSMIC: Flux concept art cut by tools/corner-pieces.py into transparent pieces (assets/<name>_pieces.png) on a drawn rail.
// Pieces 0-3 are the corners (TL, TR, BL, BR); mid = indices of pieces centred on an edge. Fitted to a small window they stick BLEED px out. ----
var PIECED = {
  FROST: { file: "frost_pieces.png", dot: "diamond", mid: { l: 4, r: 5, t: 6, b: 7 },
    pieces: [[0, 0, 340, 300], [340, 0, 340, 300], [680, 0, 340, 328], [1020, 0, 340, 328], [1360, 0, 170, 158], [1530, 0, 170, 158], [1700, 0, 224, 135], [1924, 0, 224, 150]],
    rail: "#0a1a2e", glow: "#8fd4ff", line: "#e6f5ff" },
  SAKURA: { file: "sakura_pieces.png", dot: "petal", mid: { l: 4, r: 5 },
    pieces: [[0, 0, 480, 222], [480, 0, 480, 222], [960, 0, 300, 235], [1260, 0, 350, 235], [1610, 0, 200, 253], [1810, 0, 200, 253]],
    rail: "#1a0a10", glow: "#f58fb0", line: "#d9a441" },
  COSMIC: { file: "cosmic_pieces.png", dot: "star", mid: {},
    pieces: [[0, 0, 430, 300], [430, 0, 340, 300], [770, 0, 340, 338], [1110, 0, 340, 338]],
    rail: "#060818", glow: "#3fb6ff", line: "#a45cff" }
}
function pieced(ctx, W, H, o, S) {
  const p = palette(o.colors)
  const K = o.follow
    ? { rail: mix(p.dark, "#000000", 0.25), glow: p.accent, line: mix(p.accent, "#ffffff", 0.35), tint: p.accent }
    : { rail: S.rail, glow: S.glow, line: S.line, tint: "" }
  const B = o.bleed || 0
  band(ctx, W, H, K.rail, 6, 4, false)
  ctx.save(); bandClip(ctx, W, H, 6, 4)
  ctx.lineWidth = 3; ctx.strokeStyle = rgba(K.glow, 0.16); rrPath(ctx, BAND - 3, BAND - 3, W - 2 * BAND + 6, H - 2 * BAND + 6, 5); ctx.stroke()
  ctx.restore()
  rrPath(ctx, BAND - 1.5, BAND - 1.5, W - 2 * BAND + 3, H - 2 * BAND + 3, 4); ctx.lineWidth = 1.5; ctx.strokeStyle = rgba(K.glow, 0.85); ctx.stroke()
  rrPath(ctx, 3.5, 3.5, W - 7, H - 7, 5); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.line, 0.7); ctx.stroke()
  const dot = function (x, y) {
    ctx.fillStyle = mix(K.line, "#ffffff", 0.5)
    if (S.dot === "diamond") {
      ctx.beginPath(); ctx.moveTo(x, y - 4.5); ctx.lineTo(x + 3, y); ctx.lineTo(x, y + 4.5); ctx.lineTo(x - 3, y); ctx.closePath(); ctx.fill()
    } else if (S.dot === "petal") {
      ctx.save(); ctx.translate(x, y); ctx.rotate(0.7); ctx.fillStyle = mix(K.glow, "#ffffff", 0.35)
      ctx.beginPath(); ctx.ellipse(0, 0, 4, 2.4, 0, 0, Math.PI * 2); ctx.fill(); ctx.restore()
    } else {
      ctx.beginPath(); ctx.moveTo(x, y - 5); ctx.quadraticCurveTo(x, y, x + 5, y); ctx.quadraticCurveTo(x, y, x, y + 5)
      ctx.quadraticCurveTo(x, y, x - 5, y); ctx.quadraticCurveTo(x, y, x, y - 5); ctx.fill()
    }
  }
  const step = 88
  for (let x = 190 + step / 2; x < W - 190; x += step) { dot(x, 11); dot(x, H - 11) }
  for (let y = 150 + step / 2; y < H - 150; y += step) { dot(11, y); dot(W - 11, y) }
  const img = artUrl(ctx, o, S.file)
  if (img) {
    const sc = Math.max(0.3, Math.min(0.75, Math.min(W, H) * 0.34 / 300))
    const put = function (i, x, y) { const s = S.pieces[i]; ctx.drawImage(img, s[0], s[1], s[2], s[3], x, y, s[2] * sc, s[3] * sc) }
    const sz = function (i) { return [S.pieces[i][2] * sc, S.pieces[i][3] * sc] }
    for (let i = 0; i < 4; i++) put(i, i % 2 ? W + B - sz(i)[0] : -B, i < 2 ? -B : H + B - sz(i)[1])
    const m = S.mid
    if (m.l !== undefined) put(m.l, -B, H / 2 - sz(m.l)[1] / 2)
    if (m.r !== undefined) put(m.r, W + B - sz(m.r)[0], H / 2 - sz(m.r)[1] / 2)
    if (m.t !== undefined) put(m.t, W / 2 - sz(m.t)[0] / 2, -B)
    if (m.b !== undefined) put(m.b, W / 2 - sz(m.b)[0] / 2, H + B - sz(m.b)[1])
  }
  if (K.tint) {
    ctx.globalCompositeOperation = "source-atop"
    ctx.fillStyle = rgba(K.tint, 0.22); ctx.fillRect(-B, -B, W + 2 * B, H + 2 * B)
    ctx.globalCompositeOperation = "source-over"
  }
  if (o.text) {
    setFont(ctx, o, 10, true)
    const t = o.text, sp = 4, tw = spacedWidth(ctx, t, sp), x0t = W * 0.5 - tw / 2
    ctx.fillStyle = rgba(K.rail, 0.95); rrPath(ctx, x0t - 14, H - 21, tw + 28, 19, 9.5); ctx.fill()
    rrPath(ctx, x0t - 13, H - 20, tw + 26, 17, 8.5); ctx.lineWidth = 1; ctx.strokeStyle = rgba(K.line, 0.9); ctx.stroke()
    ctx.fillStyle = mix(K.glow, "#ffffff", 0.55); spaced(ctx, t, x0t, H - 7.5, sp, "left")
  }
}
function frost(ctx, W, H, o) { pieced(ctx, W, H, o, PIECED.FROST) }
function sakura(ctx, W, H, o) { pieced(ctx, W, H, o, PIECED.SAKURA) }
function cosmic(ctx, W, H, o) { pieced(ctx, W, H, o, PIECED.COSMIC) }

var PAINTERS = { CORALREEF: coralreef,OMARCHY: omarchy, CYBERPUNK: cyberpunk, AURORA: aurora, HUD: hud, TERMINAL: terminal, GLASS: glass,
  FOLIAGE: foliage, SACRED: sacred, KAWAII: kawaii, CELESTIAL: celestial, VAPORWAVE: vaporwave,
  SAKURA: sakura, DEEPSEA: deepsea, STEAMPUNK: steampunk, FROST: frost, HALLOWEEN: halloween, COSMIC: cosmic, MEGACITY: megacity, GILDED: gilded, PASTEUP: pasteup, BLUEPRINT: blueprint,
  RUNEFORGE: runeforge, NEXUS: nexus, EMBERGOTH: embergoth, ABYSS: abyss, HANAMI: hanami, WILDWOOD: wildwood, DRIFTWOOD: driftwood, SLATE: slate, LEATHER: leather, TIDEPOOL: tidepool, CHERRYBARK: cherrybark, MOSSWOOD: mosswood, WALNUT: walnut, BAMBOO: bamboo, BIRCH: birch, LINEN: linen, TERRACOTTA: terracotta, BRICK: brick, SANDSTONE: sandstone, MARBLE: marble, CONCRETE: concrete, RUST: rust }
for (const n in PAINTERS) SMOOTH.push(n)
NAMES = SMOOTH.concat(PIXEL)

function paint(ctx, W, H, o) {
  ctx.reset()
  const b = o.bleed || 0
  W -= 2 * b; H -= 2 * b
  if (W < 120 || H < 120) return
  if (b) ctx.translate(b, b)
  if (o.scale) ctx.scale(o.scale, o.scale)
  const f = PAINTERS[o.style]
  if (f) f(ctx, W, H, o)
  else pixel(ctx, W, H, o)
}
