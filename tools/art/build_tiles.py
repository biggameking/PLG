# Assemble assets/tiles.png + tiles.json from posted tile cells
# (render/tile_<name>.png) plus the still-procedural wall/stair/marker
# cells — reuses gen_assets' painters for the non-ground rows so the
# manifest layout is identical to what world_drawer expects.
#
#   python3 build_tiles.py

import json
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
from PIL import Image
import gen_assets  # noqa: E402  (import runs module top-level only)

A = os.path.join(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))), "assets")
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

GROUND = ["grass_0", "grass_1", "grass_2", "grass_3",
          "tallgrass_0", "tallgrass_1", "flower_0", "flower_1",
          "sand_0", "sand_1", "water_0", "water_1",
          "stonefield_0", "stonefield_1", "dirt_0", "farmland_0"]
PROC = [("wall_sx", gen_assets.wall_img("sx")),
        ("wall_sy", gen_assets.wall_img("sy")),
        ("wall_corner", gen_assets.wall_img("corner")),
        ("stair_sx", gen_assets.wall_img("stair_sx")),
        ("stair_sy", gen_assets.wall_img("stair_sy")),
        ("stair_corner", gen_assets.wall_img("stair_corner")),
        ("marker", gen_assets.marker_img())]


def main():
    tiles = []
    for name in GROUND:
        p = os.path.join(R, "tile_%s.png" % name)
        if not os.path.exists(p):
            sys.exit("FAIL: missing posted tile %s" % p)
        tiles.append((name, Image.open(p).convert("RGBA")))
    tiles += PROC
    cols = 8
    rows = math.ceil(len(tiles) / cols)
    img = Image.new("RGBA", (cols * 64, rows * 64), (0, 0, 0, 0))
    manifest = {}
    for i, (name, t) in enumerate(tiles):
        c, r = i % cols, i // cols
        img.paste(t, (c * 64, r * 64), t)
        manifest[name] = [c, r]
    img.save(os.path.join(A, "tiles.png"))
    with open(os.path.join(A, "tiles.json"), "w") as f:
        json.dump({"cell": 64, "tw": gen_assets.TW, "th": gen_assets.TH,
                   "wall": gen_assets.WALL, "tiles": manifest}, f)
    print("atlas built: %d tiles -> %s" % (len(tiles), img.size))


if __name__ == "__main__":
    main()
