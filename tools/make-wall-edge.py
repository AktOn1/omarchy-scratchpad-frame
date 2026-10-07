#!/usr/bin/env python3
"""Make assets/wall_edge.png for the CITYEDGE style: the wallpaper's own outer edge (a 22 px band, lifted so the dark
city shows) that fades out ~38 px (at 1920x1080) into the window area, so the frame continues the wallpaper behind it.
usage: make-wall-edge.py WALLPAPER OUT.png [W H]     Needs numpy and Pillow."""
import sys
import numpy as np
from PIL import Image, ImageFilter

wall, out = sys.argv[1], sys.argv[2]
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (1280, 720)
K = W / 1920
BAND, R = 22 * K, 14 * K

img = Image.open(wall).convert("RGB").resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.8 * K))
a = np.asarray(img, dtype=np.float32) / 255
a = np.clip(a * 1.5, 0, 1) ** 0.9                          # lift the dark city a little
a = 0.78 * np.tanh(a / 0.78)                                # soft-clip the bright billboards
gray = a.mean(2, keepdims=True)
a = np.clip(gray + (a - gray) * 1.35, 0, 1)                # a little more colour
a = np.clip(a + np.array([0.01, 0.015, 0.03], np.float32), 0, 1)

y, x = np.mgrid[0:H, 0:W].astype(np.float32)
d = np.minimum(np.minimum(x, y), np.minimum(W - 1 - x, H - 1 - y))
cx, cy = np.clip(x, R, W - 1 - R), np.clip(y, R, H - 1 - R)
inside = (np.hypot(x - cx, y - cy) <= R)
alpha = np.where(d < BAND, 1.0, 0.5 * np.exp(-(d - BAND) / (13.0 * K)))
alpha = np.where(d > BAND + 38 * K, 0, alpha) * inside
rgba = np.concatenate([a, alpha[..., None].astype(np.float32)], 2)
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(out, optimize=True)
print(out, W, H)
