"""Writes src/assets/stations/<part>.png, one alpha mask per vanilla station logo.

The rects come from radiostations_icons.inkatlas in the ink archive's database; the texture is
the atlas's 4K slot, uncooked to PNG with the wolvenkit MCP (`uncook_file` on
base\\gameplay\\gui\\common\\icons\\radiostations_icons.xbm).

    python scripts/station-icons.py <radiostations_icons.png> [path/to/ink.db]
"""
import json
import sqlite3
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
DEFAULT_DB = HERE.parents[3] / "cp2077-ink-archive" / "data" / "ink.db"
ATLAS = r"base\gameplay\gui\common\icons\radiostations_icons.inkatlas"
OUT = HERE.parent / "src" / "assets" / "stations"
SKIP = {"no_station"}


def main():
    texture = Image.open(sys.argv[1]).convert("RGBA")
    db = sqlite3.connect(sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DB)
    atlas = json.loads(db.execute("SELECT data FROM files WHERE path = ?", (ATLAS,)).fetchone()[0])
    slot = atlas["slots"]["Elements"][0]
    width, height = texture.size
    OUT.mkdir(parents=True, exist_ok=True)
    for part in slot["parts"]:
        name = part["partName"]
        if name in SKIP:
            continue
        uv = part["clippingRectInUVCoords"]
        box = (round(uv["Left"] * width), round(uv["Top"] * height),
               round(uv["Right"] * width), round(uv["Bottom"] * height))
        # Only the alpha is kept: the game tints the logo, so the page does too.
        alpha = texture.crop(box).getchannel("A")
        mask = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
        mask.putalpha(alpha)
        mask.save(OUT / f"{name}.png", optimize=True)
        print(name, box)


if __name__ == "__main__":
    main()
