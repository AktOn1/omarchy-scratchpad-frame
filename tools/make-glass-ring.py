#!/usr/bin/env python3
"""Make assets/glass_ring.png for the STARGLASS style: the wallpaper, blurred into frosted glass, as a 22 px band
plus a faint glow that fades out ~40 px (at 1920x1080) into the window area (transparent beyond).
usage: make-glass-ring.py WALLPAPER OUT.png [W H]     Needs numpy and Pillow."""
import sys
import numpy as np
from PIL import Image, ImageFilter

wall, out = sys.argv[1], sys.argv[2]
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (960, 540)   # half size, the painter stretches it
K = W / 1920
BAND, R = 22 * K, 14 * K

img = Image.open(wall).convert("RGB").resize((W, H), Image.LANCZOS)
img = img.filter(ImageFilter.GaussianBlur(16 * K))
a = np.asarray(img, dtype=np.float32) / 255
gray = a.mean(2, keepdims=True)
a = np.clip(gray + (a - gray) * 1.7, 0, 1)        # saturate
a = np.clip(a * 2.2, 0, 1) ** 0.85                # lift the dark city into visible glass
navy = np.array([0.03, 0.04, 0.10], np.float32)
a = navy * 0.35 + a * 0.75
rng = np.random.default_rng(7)
a = np.clip(a + rng.normal(0, 0.008, (H, W, 1)), 0, 1)   # frost grain

y, x = np.mgrid[0:H, 0:W].astype(np.float32)
d = np.minimum(np.minimum(x, y), np.minimum(W - 1 - x, H - 1 - y))
# rounded outer corners
cx, cy = np.clip(x, R, W - 1 - R), np.clip(y, R, H - 1 - R)
inside = (np.hypot(x - cx, y - cy) <= R)
alpha = np.where(d < BAND, 1.0, 0.22 * np.exp(-(d - BAND) / (11.0 * K)))
alpha = np.where(d > BAND + 44 * K, 0, alpha) * inside
rgba = np.concatenate([a, alpha[..., None].astype(np.float32)], 2)
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
print(out, W, H)
