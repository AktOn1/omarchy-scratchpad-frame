"""framedesign: turns a few words ("calm night forest, mossy green") into a frame recipe by asking the user's own AI.

A recipe is data only: {"name": "Mossy night", "style": "<one of the existing styles>", "colors": {"accent": "#rrggbb", ...}}.
Nothing the AI answers is ever run: the reply is read as JSON, every field is checked against the lists below,
and anything that does not fit is rejected with a plain message. Sent to the AI: the description and the list of
style names with their one-line descriptions. Nothing else (no picture, no window titles, no theme).

Optional (box ticked): the recipe may also carry a short plain-text "ornament" description. Only that sentence goes to the user's own
image model (see ornament.py); the finished recipe then names the stored picture by a 12-digit id, never by a path. If the image
model is down or gives junk, the recipe stays the plain data-only one and a note says so.
"""
import json
import os
import re
import time

import aiprov as P
import framelib as L
import ornament as O

COLOR_KEYS = ("accent", "background", "darker_background", "foreground", "bright_foreground", "muted",
              "red", "green", "yellow", "orange", "blue", "cyan", "magenta", "brown")
SMALL_KEYS = ("accent", "background", "darker_background")
MAX_WORDS = 400
HEX = re.compile(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})")


def _read(name):
    try:
        return open(os.path.join(L.ROOT, name), encoding="utf-8").read()
    except OSError:
        return ""


def styles():
    """{STYLE: one-line description} for every style the picker offers (read from FramePainter.js and MenuModel.js)"""
    src = _read("FramePainter.js")
    m = re.search(r"var PAINTERS = \{(.*?)\}\s*\n", src, re.S)
    names = re.findall(r"\b([A-Z][A-Z0-9]+)\s*:", m.group(1)) if m else []
    pm = re.search(r"var PIXEL = \[(.*?)\]", src)
    names += re.findall(r'"([A-Z0-9]+)"', pm.group(1)) if pm else []
    dm = re.search(r"var DESC = \{(.*?)\n\}", _read("MenuModel.js"), re.S)
    desc = dict(re.findall(r'\b([A-Z][A-Z0-9]+):\s*"([^"]*)"', dm.group(1))) if dm else {}
    return {n: desc.get(n, "") for n in names if not n.startswith("TRY")}


def prompts(description, strong=True, ornament=False):
    """-> (system, user). This is everything that is sent. With ornament=True one more field is asked for."""
    keys = COLOR_KEYS if strong else SMALL_KEYS
    lines = "\n".join("%s: %s" % (n, d) if d else n for n, d in styles().items())
    shape = '{"name": "short title", "style": "STYLE_NAME", "colors": {"accent": "#rrggbb"}%s}\n'
    system = (
        "You design the look of a decorative frame drawn around a desktop window.\n"
        "Pick the ONE existing style below that fits the request best, and optionally give colours to recolour it.\n"
        "Answer with a single JSON object and nothing else:\n"
        + shape % (', "ornament": "short phrase"' if ornament else "") +
        "Rules: style must be exactly one of the names below. colors is optional; allowed keys: %s. "
        "Every colour is #rrggbb. Keep background and darker_background dark and foreground light so text stays readable. "
        % ", ".join(keys)
        + ("ornament: a plain phrase of at most 15 words describing ONE decorative corner ornament that matches the request "
           "(for example: \"curling green vines with small white flowers\"); no letters, no text, no names of artists. "
           "An image model draws it; if that fails the style and colours are used on their own, so still pick the best style. "
           if ornament else "")
        + "Do not add any other fields.\n\nStyles:\n" + lines)
    return system, "Frame I want: " + description


def clean_description(text):
    t = re.sub(r"\s+", " ", str(text or "")).strip()
    if not t:
        raise L.Bad("Describe the frame you want first.")
    if len(t.split()) > MAX_WORDS:
        raise L.Bad("That is too long: keep it under %d words." % MAX_WORDS)
    return t


def extract_json(text):
    """the first complete {...} object in the AI's answer (it may add words or a code fence around it)"""
    text = str(text or "")
    dec = json.JSONDecoder()
    i = text.find("{")
    while i >= 0:
        try:
            d, _ = dec.raw_decode(text, i)
            if isinstance(d, dict):
                return d
        except ValueError:
            pass
        i = text.find("{", i + 1)
    raise L.Bad("The AI did not answer with a frame recipe (no JSON object found).")


def hex6(v):
    if not isinstance(v, str) or not HEX.fullmatch(v.strip()):
        return ""
    h = v.strip().lower()
    return "#" + "".join(c * 2 for c in h[1:]) if len(h) == 4 else h


def validate(obj, known=None, ornament=False):
    """-> a clean recipe or raises L.Bad. Unknown fields are dropped; a wrong style or colour rejects the whole recipe.
    The "ornament" phrase is read only when ornament=True (the box is ticked); it is cleaned to short plain text, never rejected."""
    known = known if known is not None else styles()
    if not isinstance(obj, dict):
        raise L.Bad("The AI's recipe is not an object.")
    style = str(obj.get("style") or "").strip().upper()
    if style not in known:
        raise L.Bad("The AI chose a style that does not exist (“%s”)." % re.sub(r"[^\w .-]", "", str(obj.get("style") or ""))[:30])
    cols = obj.get("colors")
    if cols is None:
        cols = {}
    if not isinstance(cols, dict):
        raise L.Bad("The AI's colours are not a list of name and colour.")
    out = {}
    for k, v in cols.items():
        if k not in COLOR_KEYS:
            continue
        h = hex6(v)
        if not h:
            raise L.Bad("The AI gave a colour for %s that is not #rrggbb." % k)
        out[k] = h
    name = re.sub(r"[^\w .,'&-]", "", str(obj.get("name") or "")).strip()[:40] or style.capitalize()
    rec = {"name": name, "style": style, "colors": out}
    if ornament:
        text = O.clean_prompt(obj.get("ornament"))
        if text:
            rec["ornamentText"] = text
    return rec


def make(description, ch=None, timeout=None, images=None, progress=None):
    """ask the chosen AI -> {"ok": True, "recipe": {...}, "usage": {...}, "seconds": n, "note": "..."}; never raises.
    images: the image-model choice (imgprov.choice()) when the ornament box is ticked, else None and nothing goes to an image model.
    A failed ornament never fails the frame: the data-only recipe is returned with a plain-words "note"."""
    t0 = time.time()
    ch = ch or P.choice()
    say = progress or (lambda m: None)
    note = ""
    try:
        desc = clean_description(description)
        av = P.availability(ch)
        if not av["available"]:
            raise L.Bad(av["hint"])
        system, user = prompts(desc, P.is_strong(ch), images is not None)
        say("ai")
        text, usage = P.call(ch, system, user, None, timeout)
        recipe = validate(extract_json(text), ornament=images is not None)
    except L.Bad as e:
        return {"ok": False, "error": str(e), "seconds": round(time.time() - t0, 1)}
    if images is not None:
        text = recipe.pop("ornamentText", "")
        if not text:
            note = "Your AI gave no ornament description, so this is the normal frame without ornaments."
        else:
            say("image")
            try:
                oid = O.generate(text, images)
                recipe.update(style="OWNART", ornament=oid, ornamentText=text)
            except L.Bad as e:
                note = "Your image model could not make the ornament (%s) so this is the normal frame without it." % str(e).rstrip(".")
            except Exception:
                note = "Something went wrong while making the ornament, so this is the normal frame without it."
    r = {"ok": True, "recipe": recipe, "usage": usage, "provider": ch["provider"], "seconds": round(time.time() - t0, 1)}
    if note:
        r["note"] = note
    return r
