# Extract the two rendered side faces of the cliff cube into the game's
# wall cells (wall_sx / wall_sy / wall_corner). The render's top diamond
# is at the same scale as ground tiles (242x120), so cell px (x,y) maps
# linearly to render px; the face coverage masks reuse the game's own
# edge+drop geometry. Stair cells stay procedural (stepped reads better
# flat). The INK top line + lilac rim are re-applied in post — the crisp
# edge is how the wall reads as elevation.
#
#   python3 post_wall.py cliff

import os
import sys
from PIL import Image
import post_kin

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# measured on render/wall_cliff_f0.png: top diamond x[8,247] y[39,158]
RX0, RY0 = 8.0, 39.0
SX, SY = (247 - 8) / 64.0, (158 - 39) / 32.0   # cell -> render scale
INK = (28, 26, 46)
LILAC = (154, 134, 184)


def face_mask(kind):
    """Set of (x,y) cell pixels the face owns — same geometry as
    gen_assets.wall_img: sx edge (64,16)->(32,32), sy edge (0,16)->(32,32),
    each dropping WALL=16px; corner adds the center column below."""
    cov = set()
    if kind in ("sx", "corner"):
        for x in range(32, 65):
            k = 64 - x
            for t in range(16):
                if 0 <= 16 + k / 2 + t < 64:
                    cov.add((x, int(16 + k / 2 + t)))
    if kind in ("sy", "corner"):
        for x in range(0, 33):
            for t in range(16):
                if 0 <= 16 + x / 2 + t < 64:
                    cov.add((x, int(16 + x / 2 + t)))
    if kind == "corner":
        for dy in range(2):
            for t in range(16):
                cov.add((31 + dy, 32 + t))
    return cov


def top_edge_px(kind):
    """The face's top-edge pixels (t==0) -> ink line; t==1 -> lilac rim."""
    ink, rim = set(), set()
    if kind in ("sx", "corner"):
        for x in range(32, 65):
            k = 64 - x
            ink.add((x, int(16 + k / 2)))
            rim.add((x, int(16 + k / 2 + 1)))
    if kind in ("sy", "corner"):
        for x in range(0, 33):
            ink.add((x, int(16 + x / 2)))
            rim.add((x, int(16 + x / 2 + 1)))
    return ink, rim


def process(cid):
    img = Image.open(os.path.join(A, "wall_%s_f0.png" % cid)).convert("RGBA")
    img = post_kin.cel_band(img)
    img = post_kin.warm_lift(img)
    for kind in ("sx", "sy", "corner"):
        cell = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        cov = face_mask(kind)
        ink, rim = top_edge_px(kind)
        src = img.load()
        for x, y in cov:
            if not (0 <= x < 64 and 0 <= y < 64):
                continue
            rx = int(RX0 + x * SX)
            ry = int(RY0 + y * SY)
            p = src[rx, ry]
            # strata lines at drop-depths 5/10 (same bands as the old
            # procedural walls) — deterministic jitter, darken ~18%
            edge_y = int(16 + (64 - x) / 2) if x > 32 else int(16 + x / 2)
            if kind == "corner" and x in (31, 32) and y >= 32:
                edge_y = 32
            rel_y = y - edge_y
            if rel_y in (5, 10) and ((x * 7 + y * 13) % 5) < 3:
                p = (int(p[0] * 0.82), int(p[1] * 0.82), int(p[2] * 0.85), p[3])
            cell.putpixel((x, y), p)
        for x, y in rim:
            if 0 <= x < 64 and 0 <= y < 64:
                cell.putpixel((x, y), LILAC + (255,))
        for x, y in ink:
            if 0 <= x < 64 and 0 <= y < 64:
                cell.putpixel((x, y), INK + (255,))
        cell.save(os.path.join(A, "wall_%s.png" % kind))
        print("posted wall_%s" % kind)


if __name__ == "__main__":
    process(sys.argv[1] if len(sys.argv) > 1 else "cliff")
