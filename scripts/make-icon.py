#!/usr/bin/env python3
"""Draws the MemeFX app icon: a 2x2 sampler of colored pads on a near-black deck, so it reads
as a soundboard at a glance. Writes a 1024 PNG into the asset catalog.

    /usr/bin/python3 scripts/make-icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "App" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"
S = 1024
DECK = (14, 14, 16)
# the four pad faces and the darker lip under each (from Palette.swift)
PADS = [((255, 90, 54), (194, 58, 28)), ((255, 194, 26), (196, 143, 0)),
        ((63, 169, 255), (31, 114, 196)), ((46, 214, 154), (21, 160, 111))]

img = Image.new("RGB", (S, S), DECK)
d = ImageDraw.Draw(img)
margin, gap = 150, 54
cell = (S - 2 * margin - gap) / 2
radius, lip = 78, 30
for i, (face, lipcol) in enumerate(PADS):
    col, row = i % 2, i // 2
    x = margin + col * (cell + gap)
    y = margin + row * (cell + gap)
    d.rounded_rectangle([x, y + lip, x + cell, y + cell], radius=radius, fill=lipcol)
    d.rounded_rectangle([x, y, x + cell, y + cell - lip], radius=radius, fill=face)
img.save(OUT)
print(OUT.relative_to(ROOT))
