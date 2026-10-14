"""ornament: asks the user's own image model for ONE corner ornament and turns it into a small transparent PNG for the frame.

  generate(orn_text, ch)   ask the image model, remove the plain background, crop, size-cap, check, store -> the ornament id
  process(raw)             the picture work alone: colour key to alpha, crop, resize, PNG bytes (raises L.Bad when the picture is junk)
  check_png(data)          the checks every stored ornament passes (PNG magic number, sane size and dimensions)
  prune(keep)              delete ornaments no saved look uses, then the oldest ones above the cap
  drop(id)                 delete one ornament that no saved look uses

An ornament lives in <state>/ornaments/<id>.png, never in the plugin folder (that folder may be read-only, and a change there
reloads the shell). A recipe names it by a 12-digit hex id, never by a path; the shell checks the id again before it loads anything.
The image model only ever returns image bytes: they are checked by magic number, decoded by Pillow (or, when that is not installed,
by ImageMagick, which Omarchy ships), and re-saved as a fresh PNG.
Nothing here runs anything the model sent.
"""
import json
import os
import re
import secrets
import shutil
import struct
import subprocess
import tempfile
import time

import framelib as L
import imgprov as I

ID_RE = re.compile(r"[0-9a-f]{12}")
FILE_RE = re.compile(r"([0-9a-f]{12})\.png")
MAX_SETS = 12          # generated ornaments kept at most; the oldest go first
MAX_SIDE = 512         # a stored ornament is a square picture of exactly this size
MAX_FILE = 1_500_000   # bytes
PROMPT_MAX = 140
RAW_SIDE = 1024        # what the image model is asked to draw
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def dir_():
    return os.path.join(L.STATE, "ornaments")


def path_of(oid):
    if not isinstance(oid, str) or not ID_RE.fullmatch(oid):
        raise L.Bad("That is not an ornament id.")
    return os.path.join(dir_(), oid + ".png")


def clean_prompt(text):
    """the short plain-text ornament description the text AI may add to a recipe; "" when there is nothing usable"""
    t = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text or ""))
    t = re.sub(r"[^\w .,'&()/-]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()[:PROMPT_MAX].strip()
    return t if len(re.findall(r"[^\W\d_]", t)) >= 3 else ""


def image_prompt(orn):
    return ("a single ornate decorative corner ornament, %s, a flourish that starts in the top-left corner of the picture and spreads "
            "along the top and left edges, isolated on a plain solid black background, flat even lighting, high contrast, "
            "no text, no letters, no frame" % orn)


NEGATIVE = ("text, letters, watermark, signature, frame, border, picture frame, several separate objects, photograph, person, face, "
            "gradient background, textured background, blurry")


# ------------------------------------------------------------------ the picture work
KEY_LO, KEY_HI = 22, 90          # background distance (0-255) below which a pixel is background and above which it is fully ornament
EDGE_CLEAN, EDGE_MEAN = 0.85, 0.55   # the two cleanest picture edges must be this plain, and the four on average this plain
COVER_MIN, COVER_MAX = 0.012, 0.72   # share of the picture the ornament may cover
BOX_MIN = 48                         # smallest ornament, in pixels of the (at most RAW_SIDE) picture


def _pil():
    try:
        from PIL import Image
        Image.MAX_IMAGE_PIXELS = 40_000_000
        return Image
    except ImportError:
        return None


def _magick():
    return shutil.which("magick")


def process(raw, engine=None):
    """raw image bytes (PNG/JPEG of an ornament on a plain dark or white background) -> PNG bytes with the background keyed out.
    engine: "pillow" or "magick" to force one (tests); by default Pillow, else ImageMagick."""
    if engine is None:
        engine = "pillow" if _pil() else "magick" if _magick() else None
    if engine == "pillow" and _pil():
        return _process_pillow(raw)
    if engine == "magick" and _magick():
        return _process_magick(raw)
    raise L.Bad("Making ornaments needs the Python Pillow library or ImageMagick installed on this system.")


def _process_pillow(raw):
    Image = _pil()
    from PIL import ImageChops, ImageOps, ImageStat
    import io
    try:
        im = Image.open(io.BytesIO(raw))
        im.load()
        im = im.convert("RGB")
    except Exception:
        raise L.Bad("The picture from the image model could not be read.")
    if min(im.size) < 64:
        raise L.Bad("The picture from the image model is too small.")
    if max(im.size) > RAW_SIDE:
        im.thumbnail((RAW_SIDE, RAW_SIDE), Image.LANCZOS)
    w, h = im.size
    # the background colour: the middle of the medians of the four border strips; it must be plain (low spread)
    t = max(3, min(w, h) // 80)
    strips = [im.crop((0, 0, w, t)), im.crop((0, h - t, w, h)), im.crop((0, 0, t, h)), im.crop((w - t, 0, w, h))]
    meds = [ImageStat.Stat(s).median for s in strips]
    bg = tuple((sorted(m[c] for m in meds)[1] + sorted(m[c] for m in meds)[2]) // 2 for c in range(3))
    diff = ImageChops.difference(im, Image.new("RGB", im.size, bg))
    r, g, b = diff.split()
    d = ImageChops.lighter(ImageChops.lighter(r, g), b)
    # the background must be plain: along the picture's edges most pixels are close to the background colour (the ornament itself
    # may touch the top and left edges, so only the two cleanest edges must be almost entirely clean)
    edges = [d.crop((0, 0, w, t)), d.crop((0, h - t, w, h)), d.crop((0, 0, t, h)), d.crop((w - t, 0, w, h))]
    clean = sorted(sum(e.histogram()[:30]) / float(e.size[0] * e.size[1]) for e in edges)
    if clean[2] < EDGE_CLEAN or sum(clean) / 4.0 < EDGE_MEAN:
        raise L.Bad("The picture had no plain background to cut the ornament out of.")
    lo, hi = KEY_LO, KEY_HI
    alpha = d.point([0 if v < lo else 255 if v >= hi else int((v - lo) * 255 / (hi - lo)) for v in range(256)])
    # the ornament must not be the background: very little or nearly everything covered means the key failed
    hist = alpha.point([0 if v < 40 else 255 for v in range(256)]).histogram()
    cover = hist[255] / float(w * h)
    if cover < COVER_MIN:
        raise L.Bad("The picture had no visible ornament in it.")
    if cover > COVER_MAX:
        raise L.Bad("The ornament could not be separated from its background.")
    box = alpha.point([0 if v < 40 else 255 for v in range(256)]).getbbox()
    if not box or box[2] - box[0] < BOX_MIN or box[3] - box[1] < BOX_MIN:
        raise L.Bad("The ornament in the picture is too small to use.")
    pad = 2
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(w, box[2] + pad), min(h, box[3] + pad))
    out = im.crop(box).convert("RGBA")
    out.putalpha(alpha.crop(box))
    # the heavy side of the ornament goes to the top-left, where the frame puts it
    aw, ah = out.size
    col = out.getchannel("A").resize((aw, 1), Image.BOX)
    row = out.getchannel("A").resize((1, ah), Image.BOX)
    cs, rs = list(col.getdata()), list(row.getdata())
    cx = sum(i * v for i, v in enumerate(cs)) / max(1, sum(cs)) / aw
    cy = sum(i * v for i, v in enumerate(rs)) / max(1, sum(rs)) / ah
    if cx > 0.56:
        out = ImageOps.mirror(out)
    if cy > 0.56:
        out = ImageOps.flip(out)
    # always a MAX_SIDE x MAX_SIDE picture with the ornament in its top-left corner (the shell draws it at a fixed square size,
    # it cannot ask a loaded picture how big it is); a small ornament is enlarged at most 2x
    s = min(MAX_SIDE / float(max(out.size)), 2.0)
    out = out.resize((max(1, round(out.width * s)), max(1, round(out.height * s))), Image.LANCZOS)
    sheet = Image.new("RGBA", (MAX_SIDE, MAX_SIDE), (0, 0, 0, 0))
    sheet.paste(out, (0, 0))
    buf = io.BytesIO()
    sheet.save(buf, "PNG", optimize=True)
    data = buf.getvalue()
    check_png(data)
    return data


def _run(argv, data=None, timeout=40):
    try:
        r = subprocess.run(argv, input=data, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        raise L.Bad("The picture from the image model could not be read.")
    if r.returncode != 0:
        raise L.Bad("The picture from the image model could not be read.")
    return r.stdout


def _process_magick(raw):
    """the same picture work as _process_pillow, done by ImageMagick plus a little arithmetic on a 96x96 sample"""
    if raw.startswith(PNG_MAGIC):
        coder = "png"
    elif raw.startswith(b"\xff\xd8\xff"):
        coder = "jpeg"
    elif raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        coder = "webp"
    else:
        raise L.Bad("The picture from the image model could not be read.")
    lim = ["-limit", "memory", "512MiB", "-limit", "map", "1GiB", "-limit", "time", "30", "-limit", "area", "100MP"]
    M = ["magick"] + lim
    with tempfile.TemporaryDirectory(prefix="scratchpad-frame-") as d:
        rgb, alpha = os.path.join(d, "rgb.png"), os.path.join(d, "alpha.png")
        _run(M + [coder + ":-", "-background", "black", "-alpha", "remove", "-alpha", "off", "-resize", "%dx%d>" % (RAW_SIDE, RAW_SIDE),
                  "-depth", "8", "png:" + rgb], raw)
        try:
            w, h = (int(v) for v in _run(["magick", "identify", "-format", "%w %h", rgb]).split())
        except ValueError:
            raise L.Bad("The picture from the image model could not be read.")
        if min(w, h) < 64:
            raise L.Bad("The picture from the image model is too small.")
        N = 96
        px = _run(M + [rgb, "-sample", "%dx%d!" % (N, N), "-depth", "8", "rgb:-"])     # picked pixels, not averaged: noise stays noise
        if len(px) != N * N * 3:
            raise L.Bad("The picture from the image model could not be read.")
        pix = [(px[i], px[i + 1], px[i + 2]) for i in range(0, len(px), 3)]
        edges = [pix[0:N], pix[(N - 1) * N:], pix[0::N], pix[N - 1::N]]

        def med(vals):
            return sorted(vals)[len(vals) // 2]
        meds = [[med([q[c] for q in e]) for c in range(3)] for e in edges]
        bg = tuple((sorted(m[c] for m in meds)[1] + sorted(m[c] for m in meds)[2]) // 2 for c in range(3))

        def dist(q):
            return max(abs(q[0] - bg[0]), abs(q[1] - bg[1]), abs(q[2] - bg[2]))
        clean = sorted(sum(1 for q in e if dist(q) < 30) / float(len(e)) for e in edges)
        if clean[2] < EDGE_CLEAN or sum(clean) / 4.0 < EDGE_MEAN:
            raise L.Bad("The picture had no plain background to cut the ornament out of.")
        _run(M + [rgb, "(", "+clone", "-fill", "rgb(%d,%d,%d)" % bg, "-colorize", "100", ")", "-compose", "Difference", "-composite",
                  "-separate", "-evaluate-sequence", "Max", "-level", "%.2f%%,%.2f%%" % (KEY_LO * 100 / 255.0, KEY_HI * 100 / 255.0),
                  "-depth", "8", "png:" + alpha])
        vis = "%.2f%%" % (40 * 100 / 255.0)
        # how much of the picture the ornament covers, and where: the visible pixels averaged down to a 96x96 grid
        grid = _run(M + [alpha, "-threshold", vis, "-resize", "%dx%d!" % (N, N), "-depth", "8", "gray:-"])
        if len(grid) != N * N:
            raise L.Bad("The picture from the image model could not be read.")
        cover = sum(grid) / 255.0 / (N * N)
        if cover < COVER_MIN:
            raise L.Bad("The picture had no visible ornament in it.")
        if cover > COVER_MAX:
            raise L.Bad("The ornament could not be separated from its background.")
        box = _run(M + [alpha, "-threshold", vis, "-format", "%@", "info:"]).decode("ascii", "replace").strip()
        m = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", box)
        if not m:
            raise L.Bad("The picture had no visible ornament in it.")
        bw, bh, bx, by = (int(v) for v in m.groups())
        if bw < BOX_MIN or bh < BOX_MIN:
            raise L.Bad("The ornament in the picture is too small to use.")
        pad = 2
        x0, y0 = max(0, bx - pad), max(0, by - pad)
        x1, y1 = min(w, bx + bw + pad), min(h, by + bh + pad)
        # the heavy side of the ornament goes to the top-left: its centre of weight inside its bounding box
        tot = float(sum(grid))
        gx = sum((i % N + 0.5) * v for i, v in enumerate(grid)) / tot / N * w      # in picture pixels
        gy = sum((i // N + 0.5) * v for i, v in enumerate(grid)) / tot / N * h
        cx = (gx - bx) / float(bw)
        cy = (gy - by) / float(bh)
        cw, ch_ = x1 - x0, y1 - y0
        sc = min(MAX_SIDE / float(max(cw, ch_)), 2.0)
        nw, nh = max(1, round(cw * sc)), max(1, round(ch_ * sc))
        cmd = M + [rgb, alpha, "-alpha", "off", "-compose", "CopyOpacity", "-composite", "-compose", "Over", "-crop", "%dx%d+%d+%d" % (cw, ch_, x0, y0), "+repage"]
        if cx > 0.56:
            cmd.append("-flop")
        if cy > 0.56:
            cmd.append("-flip")
        cmd += ["-filter", "Lanczos", "-resize", "%dx%d!" % (nw, nh), "-background", "none", "-gravity", "NorthWest",
                "-extent", "%dx%d" % (MAX_SIDE, MAX_SIDE), "-depth", "8", "png:-"]
        data = _run(cmd)
    check_png(data)
    return data


def check_png(data):
    """-> (width, height) of a PNG that is safe to hand to the shell, else raises L.Bad"""
    if not isinstance(data, (bytes, bytearray)) or len(data) < 40 or len(data) > MAX_FILE:
        raise L.Bad("The ornament picture is empty or too large.")
    if not data.startswith(PNG_MAGIC) or data[12:16] != b"IHDR":
        raise L.Bad("The ornament picture is not a PNG.")
    w, h = struct.unpack(">II", data[16:24])
    if (w, h) != (MAX_SIDE, MAX_SIDE):
        raise L.Bad("The ornament picture has an odd size (%dx%d)." % (w, h))
    return w, h


# ------------------------------------------------------------------ storing
def referenced():
    """ornament ids that saved looks use"""
    try:
        d = json.load(open(os.path.join(L.STATE, "looks.json")))
    except (OSError, ValueError):
        return set()
    out = set()
    if isinstance(d, dict):
        for v in d.values():
            o = v.get("ornament") if isinstance(v, dict) else None
            if isinstance(o, str) and ID_RE.fullmatch(o):
                out.add(o)
    return out


def listing():
    """[(id, mtime)] of the stored ornaments, oldest first"""
    rows = []
    try:
        names = os.listdir(dir_())
    except OSError:
        return rows
    for n in names:
        m = FILE_RE.fullmatch(n)
        if m:
            try:
                rows.append((m.group(1), os.stat(os.path.join(dir_(), n)).st_mtime))
            except OSError:
                pass
    return sorted(rows, key=lambda r: (r[1], r[0]))


def _rm(oid):
    try:
        os.remove(path_of(oid))
        return True
    except (OSError, L.Bad):
        return False


def prune(keep=(), cap=MAX_SETS):
    """remove ornaments that no saved look uses (and that are not in keep), then the oldest above the cap; -> the removed ids.
    Looks that use an ornament are only touched when the cap forces it (the frame then shows its plain rail)."""
    keep = {k for k in keep if isinstance(k, str) and ID_RE.fullmatch(k)}
    used = referenced()
    gone = []
    try:
        for n in os.listdir(dir_()):          # leftovers of an interrupted save
            if n.endswith(".tmp"):
                try:
                    if time.time() - os.stat(os.path.join(dir_(), n)).st_mtime > 60:
                        os.remove(os.path.join(dir_(), n))
                except OSError:
                    pass
    except OSError:
        return gone
    for oid, _ in listing():
        if oid not in used and oid not in keep and _rm(oid):
            gone.append(oid)
    for oid, _ in listing():
        if len(listing()) <= cap:
            break
        if oid not in keep and _rm(oid):
            gone.append(oid)
    return gone


def drop(oid):
    """delete one ornament, unless a saved look uses it -> True when it was deleted"""
    path_of(oid)
    if oid in referenced():
        return False
    return _rm(oid)


def store(png):
    check_png(png)
    os.makedirs(dir_(), mode=0o700, exist_ok=True)
    oid = secrets.token_hex(6)
    tmp = os.path.join(dir_(), oid + ".png.tmp")
    with open(tmp, "wb") as f:
        f.write(png)
    os.replace(tmp, path_of(oid))
    return oid


def generate(orn_text, ch, timeout=None):
    """ask the user's image model for one ornament and store it -> its id. Raises L.Bad with a plain message."""
    orn = clean_prompt(orn_text)
    if not orn:
        raise L.Bad("There was no ornament description.")
    if not (_pil() or _magick()):
        raise L.Bad("Making ornaments needs the Python Pillow library or ImageMagick installed on this system.")
    try:
        raw, _mime = I.generate(ch, image_prompt(orn), NEGATIVE, RAW_SIDE, RAW_SIDE, timeout=timeout)
    except I.Bad as e:
        raise L.Bad(str(e))
    oid = store(process(raw))
    prune(keep=[oid])
    return oid
