#!/usr/bin/env python3
"""Generates scattrd's app icon: a gradient squircle with scattered dots
converging to a bright focal point (scatter → focus). Outputs Resources/icon_1024.png."""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, os

SS = 2
S = 1024 * SS
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources")
os.makedirs(OUT, exist_ok=True)

c0 = (91, 140, 255)   # blue
c1 = (159, 92, 255)   # violet

# Diagonal gradient body
base = Image.linear_gradient("L")
vramp = base.resize((S, S))
hramp = base.rotate(90, expand=False).resize((S, S))
diag = Image.blend(hramp, vramp, 0.5)
body = Image.composite(Image.new("RGB", (S, S), c1),
                       Image.new("RGB", (S, S), c0), diag).convert("RGBA")

# Rounded-rect (squircle-ish) mask
pad, rad = 192, 372
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([pad, pad, S - pad, S - pad], radius=rad, fill=255)
body.putalpha(mask)

cx = cy = S // 2

# Soft glow behind the focal point
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([cx - 260, cy - 260, cx + 260, cy + 260], fill=(255, 255, 255, 120))
glow = glow.filter(ImageFilter.GaussianBlur(90))

# Glyph: scattered dots (golden-angle spiral), a focus ring, a bright center
glyph = Image.new("RGBA", (S, S), (0, 0, 0, 0))
g = ImageDraw.Draw(glyph)
n = 10
for i in range(n):
    f = i / (n - 1)
    ang = i * 2.399963                       # golden angle → even scatter
    rp = (0.46 + 0.54 * f) * (S * 0.34)
    x = cx + math.cos(ang) * rp
    y = cy + math.sin(ang) * rp
    sz = 44 - 24 * f                          # outer dots smaller
    a = int(210 - 140 * f)                    # outer dots fainter
    g.ellipse([x - sz, y - sz, x + sz, y + sz], fill=(255, 255, 255, a))
g.ellipse([cx - 290, cy - 290, cx + 290, cy + 290], outline=(255, 255, 255, 140), width=18)
g.ellipse([cx - 132, cy - 132, cx + 132, cy + 132], fill=(255, 255, 255, 255))

# Clip glow+glyph to the rounded body, compose, downscale
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fg.alpha_composite(glow)
fg.alpha_composite(glyph)
fg.putalpha(ImageChops.multiply(fg.split()[3], mask))

out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
out.alpha_composite(body)
out.alpha_composite(fg)
out = out.resize((1024, 1024), Image.LANCZOS)
out.save(os.path.join(OUT, "icon_1024.png"))
print("wrote", os.path.join(OUT, "icon_1024.png"))
