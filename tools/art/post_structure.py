# Post a structure render to its shipped sprite dims — same chain as
# post_decor.py (structures anchor bottom-center like decor).
#
#   python3 post_structure.py <struct_id>

import os
import sys
from PIL import Image
import post_kin

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")
OUT = os.path.join(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))), "assets", "structures")

DIMS = {
    "kinbox": (144, 136), "campfire": (80, 104), "workbench": (112, 120),
    "well": (80, 104), "torch": (80, 104), "waypoint": (80, 104),
    "chest": (80, 104), "feed_box": (80, 104), "kin_bed": (112, 120),
    "wooden_wall": (80, 104), "watch_tower": (80, 104),
    "notice_board": (80, 104),
    # batch 2 — production machines
    "furnace": (144, 136), "generator": (144, 136), "crusher": (144, 136),
    "mill": (144, 136), "incubator": (144, 136), "ore_mine": (144, 136),
    "logging_site": (144, 136), "stone_pit": (144, 136),
    "gathering_site": (144, 136), "spikes": (80, 104), "cooler": (80, 104),
    "kin_condenser": (112, 120),
}


def process(sid):
    dw, dh = DIMS[sid]
    img = Image.open(os.path.join(A, "struct_%s_f0.png" % sid)).convert("RGBA")
    img = post_kin.crop_alpha(img)
    if sum(img.getchannel("A").histogram()[41:]) < 50:
        sys.exit("FAIL %s: blank render (<50 opaque px)" % sid)
    img = post_kin.cel_band(img)
    img = post_kin.warm_lift(img)
    img.thumbnail((dw - 8, dh - 8), Image.LANCZOS)
    out = Image.new("RGBA", (dw, dh), (0, 0, 0, 0))
    out.paste(img, ((dw - img.width) // 2, dh - img.height - 2), img)
    out = post_kin.violet_shade(out)
    out = post_kin.halftone(out)
    out = post_kin.ink_outline(out)
    out.save(os.path.join(OUT, "%s.png" % sid))
    out.resize((dw * 3, dh * 3), Image.NEAREST).save(
        os.path.join(A, "struct_%s_x3.png" % sid))
    print("posted", sid, "%dx%d" % (dw, dh))


if __name__ == "__main__":
    process(sys.argv[1])
