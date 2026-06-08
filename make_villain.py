#!/usr/bin/env python3
"""Draws scattrd's villain glyph — a swept cat-eye domino mask — to Resources/villain.png."""
from PIL import Image, ImageDraw, ImageChops, ImageFilter
import os

SS = 4
S = 160 * SS
cx = S / 2
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources")
os.makedirs(OUT, exist_ok=True)

def P(fx, fy):
    return (cx + fx * S, fy * S)

# Symmetric cat-eye mask outline: center notch top & bottom, pointed swept corners.
pts = [P(0, 0.50), P(0.09, 0.555), P(0.29, 0.55), P(0.43, 0.385), P(0.30, 0.30),
       P(0.10, 0.30), P(0, 0.345),
       P(-0.10, 0.30), P(-0.30, 0.30), P(-0.43, 0.385), P(-0.29, 0.55), P(-0.09, 0.555)]
shape = Image.new("L", (S, S), 0)
ImageDraw.Draw(shape).polygon(pts, fill=255)
shape = shape.filter(ImageFilter.GaussianBlur(SS * 0.5))

# Slanted almond eye holes (angry).
def eye(sign):
    e = Image.new("L", (S, S), 0)
    ew, eh = S * 0.175, S * 0.082
    ex, ey = cx + sign * S * 0.155, 0.40 * S
    ImageDraw.Draw(e).ellipse([ex - ew / 2, ey - eh / 2, ex + ew / 2, ey + eh / 2], fill=255)
    return e.rotate(sign * 20, center=(ex, ey), resample=Image.BICUBIC)

holes = ImageChops.lighter(eye(1), eye(-1))
alpha = ImageChops.multiply(shape, ImageChops.invert(holes))

col = (251, 113, 133)
out = Image.new("RGBA", (S, S), (col[0], col[1], col[2], 0))
out.putalpha(alpha)
out = out.resize((160, 160), Image.LANCZOS)
out.save(os.path.join(OUT, "villain.png"))
print("wrote", os.path.join(OUT, "villain.png"))

# Embed the glyph as base64 in the villain card template (keeps the card self-contained).
import base64, re
b64 = base64.b64encode(open(os.path.join(OUT, "villain.png"), "rb").read()).decode()
swift = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Sources", "FocusTracker", "VillainAnalysis.swift")
src = open(swift).read()
src = re.sub(r'(data:image/png;base64,)[^"]*', r"\g<1>" + b64, src)
open(swift, "w").write(src)
print("injected", len(b64), "base64 chars into VillainAnalysis.swift")
