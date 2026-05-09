"""Build a padded adaptive-icon foreground from the transparent logo.

Android adaptive icons reserve the outer ~33% as a safe-zone for masking
(circle, squircle, etc). If we feed the raw 1024x1024 logo straight into
adaptive_icon_foreground, parts of the crescent + Thai wordmark get
cropped on most launchers. This script outputs a 1024x1024 transparent
canvas with the logo centered at 66% of the canvas — the standard inner
keep-zone — so launchers crop only the empty padding.

Reads:  assets/images/logo-chantra.png   (transparent background)
Writes: assets/images/logo-chantra-foreground.png
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "logo-chantra.png"
DST = ROOT / "assets" / "images" / "logo-chantra-foreground.png"

CANVAS = 1024
INNER = int(CANVAS * 0.66)  # keep-zone = inner 66%

def main() -> None:
    logo = Image.open(SRC).convert("RGBA")
    # Resize logo to inner zone, preserve aspect ratio.
    w, h = logo.size
    scale = INNER / max(w, h)
    nw, nh = int(round(w * scale)), int(round(h * scale))
    logo = logo.resize((nw, nh), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(logo, ((CANVAS - nw) // 2, (CANVAS - nh) // 2), logo)
    canvas.save(DST)
    print(f"wrote {DST} ({CANVAS}x{CANVAS}, logo {nw}x{nh})")


if __name__ == "__main__":
    main()
