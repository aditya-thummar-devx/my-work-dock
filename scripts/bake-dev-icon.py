#!/usr/bin/env python3
"""Bakes AppIcon-Dev (the Debug build's icon) from AppIcon: the same icon with a black DEV strip across its bottom.

    scripts/bake-dev-icon.py

Run again whenever AppIcon changes. Needs Pillow.
"""
import json, pathlib, shutil
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "MyWorkDock/Resources/Assets.xcassets"
SRC, OUT = ASSETS / "AppIcon.appiconset", ASSETS / "AppIcon-Dev.appiconset"
FONT = ROOT / "MyWorkDock/Resources/Fonts/Geist[wght].ttf"
STRIP = 0.24                      # of the icon body's height
BLACK, LIME = (12, 12, 14, 255), (212, 255, 58, 255)

def badge(path):
    icon = Image.open(path).convert("RGBA")
    alpha = icon.getchannel("A")
    # The body is the opaque part; the drop shadow around it stays as it is.
    left, top, right, bottom = alpha.point(lambda a: 255 if a > 200 else 0).getbbox()
    strip_top = round(bottom - (bottom - top) * STRIP)
    band = Image.new("L", icon.size, 0)
    ImageDraw.Draw(band).rectangle((left, strip_top, right, bottom), fill=255)
    icon.paste(Image.new("RGBA", icon.size, BLACK), mask=ImageChops.multiply(band, alpha.point(lambda a: 255 if a > 200 else a)))
    font = ImageFont.truetype(str(FONT), max(6, round((bottom - strip_top) * 0.62)))
    try: font.set_variation_by_axes([800])
    except OSError: pass
    ImageDraw.Draw(icon).text(((left + right) / 2, (strip_top + bottom) / 2), "DEV", font=font, fill=LIME, anchor="mm")
    return icon

OUT.mkdir(exist_ok=True)
shutil.copy(SRC / "Contents.json", OUT / "Contents.json")
for image in json.loads((SRC / "Contents.json").read_text())["images"]:
    badge(SRC / image["filename"]).save(OUT / image["filename"])
print(f"wrote {OUT.relative_to(ROOT)}")
