# Post a tile render into the atlas cell: crop to the diamond, downscale,
# keep it in the TOP half of the 64x64 cell (draw_texture_rect_region maps
# the cell rect; the diamond's top vertex is the cell's row 0).
# No ink_outline — a contour on the diamond edge would draw a dark grid
# across the whole map (neighboring cells share the edge).
#
#   python3 post_tile.py <tile_name>

import os
import sys
from PIL import Image
import post_kin

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")


def diamond_mask(w=64, h=32):
    """Pixel-exact match of the game's diamond: gen_assets.DIA covers rows
    0..32 with 16*|x-32|/32 <= y <= 32-16*|x-32|/32 — building the mask
    from the same inequality guarantees zero rim offset (audit-56)."""
    m = Image.new("L", (w, h), 0)
    px = m.load()
    for ty in range(33):
        for tx in range(w):
            dxa = abs(tx - 32) / 32.0
            if 16 * dxa <= ty <= 32 - 16 * dxa:
                px[tx, ty] = 255
    return m


def process(name):
    img = Image.open(os.path.join(A, "tile_%s_f0.png" % name)).convert("RGBA")
    if sum(img.getchannel("A").histogram()[41:]) < 50:
        sys.exit("FAIL %s: blank render (<50 opaque px)" % name)
    img = post_kin.cel_band(img)
    img = post_kin.warm_lift(img)
    # Fixed crop, NOT crop_alpha: the camera frames 1.5x0.75 units; the
    # 1x1 tile footprint projects as a 1.414x0.707 diamond = 94.27% of the
    # frame on both axes, centered -> fixed rect (7.34,3.67)-(248.7,124.3).
    # The slab is oversized ×1.3, so this rect sits inside fully-opaque
    # interior — no semi-transparent rim reaches the mask (audit-56 HIGH).
    img = img.crop((7, 4, 249, 124))
    # downscale to 64x33 and mask strictly to the game diamond — the
    # diamond's bottom vertex is row 32 of the cell (gen_assets fill_dia
    # loops rows 0..32), and anything outside bleeds into neighbor cells
    img = img.resize((64, 33), Image.LANCZOS)
    img.putalpha(Image.composite(img.getchannel("A"),
                                 Image.new("L", (64, 33), 0), diamond_mask(64, 33)))
    cell = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    cell.paste(img, (0, 0), img)
    cell.save(os.path.join(A, "tile_%s.png" % name))
    print("posted tile", name)


if __name__ == "__main__":
    process(sys.argv[1])
