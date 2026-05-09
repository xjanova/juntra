"""Strip near-black background from logo-chantra.png and save a transparent version.

Usage: python tools/strip_logo_bg.py

Reads:  assets/images/logo-chantra.png  (PNG with solid black background)
Writes: assets/images/logo-chantra.png  (PNG with alpha; black bg -> transparent)
        assets/images/logo-chantra-original.png  (backup of input, only on first run)

Algorithm:
  Per-pixel: alpha = max(R, G, B) scaled with a soft threshold so dark non-black
  pixels (e.g. shaded gold edges) keep some opacity. Pixels above the
  threshold stay fully opaque, pixels below fade to transparent — this avoids
  the harsh halo that a hard threshold creates around the gold strokes.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "logo-chantra.png"
BACKUP = ROOT / "assets" / "images" / "logo-chantra-original.png"

# Soft alpha threshold: pixels with luminance below LO are fully transparent,
# above HI fully opaque, in between linear ramp.
LO = 18    # near-black -> transparent
HI = 64    # mid-dark   -> fully opaque

def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"missing {SRC}")
    img = Image.open(SRC).convert("RGBA")
    if not BACKUP.exists():
        # Preserve the as-shipped pixels in case the user wants to revisit.
        Image.open(SRC).save(BACKUP)

    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            lum = max(r, g, b)
            if lum <= LO:
                a = 0
            elif lum >= HI:
                a = 255
            else:
                a = int(round((lum - LO) * 255 / (HI - LO)))
            px[x, y] = (r, g, b, a)

    img.save(SRC)
    print(f"wrote {SRC} ({w}x{h}) with alpha; backup at {BACKUP}")


if __name__ == "__main__":
    main()
