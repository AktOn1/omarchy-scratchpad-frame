#!/usr/bin/env python3
"""Place generated cut-outs (assets/src/pasteup/*.png from tools/prop-sheet.py) on the edges of a 1920x1080 transparent
picture, with soft shadows, so they overlap only a little into the window. usage: compose-props.py OUT.png [--preview BAND.png]"""
import argparse, math
from pathlib import Path
from PIL import Image, ImageFilter
SRC = Path(__file__).resolve().parent.parent / "assets" / "src" / "pasteup"
W, H = 1920, 1080
# name, centre x, centre y, size (longest side px), rotation deg, mirror
PLACE = [
    ("tape_3_0", 150, 26, 150, 0, False),   # placeholder replaced below
]
PLACE = [
    ("tape_0", 120, 22, 190, -8, False),
    ("note_pink_0", 150, 52, 112, 7, False),
    ("holo_1", 1650, 40, 88, -9, False),
    ("note_yellow_0", 1120, 30, 100, 5, False),
    ("tape_3", 560, 16, 120, 80, False),
    ("holo_3", 38, 560, 84, 12, False),
    ("tape_0", 36, 770, 170, 84, False),
    ("note_yellow_0", 1884, 300, 100, 80, True),
    ("holo_0", 1890, 880, 86, 10, True),
    ("note_yellow_0", 1560, 1050, 92, -6, True),
    ("holo_1", 230, 1050, 80, 8, False),
    ("tape_3", 960, 1066, 130, 100, False),
]
ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--preview")
a = ap.parse_args()
layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for name, cx, cy, size, rot, mir in PLACE:
    im = Image.open(SRC / f"{name}.png").convert("RGBA")
    im = im.crop(im.getbbox())
    k = size / max(im.size); im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    if mir: im = im.transpose(Image.FLIP_LEFT_RIGHT)
    im = im.rotate(-rot, expand=True, resample=Image.BICUBIC)
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0)); sh.putalpha(im.getchannel("A").point(lambda v: int(v * 0.55)))
    sh = sh.filter(ImageFilter.GaussianBlur(4))
    x, y = round(cx - im.width / 2), round(cy - im.height / 2)
    layer.alpha_composite(sh, (x + 3, y + 4)) if x >= 0 and y >= 0 else layer.paste(sh, (x + 3, y + 4), sh)
    layer.alpha_composite(im, (max(x, 0), max(y, 0))) if (x >= 0 and y >= 0 and x + im.width <= W and y + im.height <= H) else layer.paste(im, (x, y), im)
layer.save(a.out)
if a.preview:
    bg = Image.new("RGBA", (W, H), (10, 12, 22, 255))
    bg.alpha_composite(Image.open(a.preview).convert("RGBA")); bg.alpha_composite(layer)
    bg.convert("RGB").save(Path(a.out).with_name("pasteup_preview.png"))
