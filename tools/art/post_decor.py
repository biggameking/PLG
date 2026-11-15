# Post a decor render into the game sprite: same cel/halftone/ink chain as
# post_kin.py, with per-decor output dims (the decor pool draws each texture
# bottom-anchored on its tile, so the sprite keeps the OLD file's dims).
#
#   python3 post_decor.py <decor_id>

import os
import sys
from PIL import Image
import post_kin

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")
OUT = os.path.join(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))), "assets", "decor")

# decor_id -> output (w, h) matching the shipped sprite dims
DIMS = {
    "tree_a": (64, 96), "tree_b": (64, 96),
    "rock": (64, 40), "ore_coal": (64, 40), "ore_gold": (64, 40),
    "berry_bush": (64, 56), "stump": (48, 30),
}


def process(did):
    dw, dh = DIMS[did]
    img = Image.open(os.path.join(A, "%s_f0.png" % did)).convert("RGBA")
    img = post_kin.crop_alpha(img)
    if sum(img.getchannel("A").histogram()[41:]) < 50:
        sys.exit("FAIL %s: blank render (<50 opaque px)" % did)
    img = post_kin.cel_band(img)
    img = post_kin.warm_lift(img)
    img.thumbnail((dw - 4, dh - 4), Image.LANCZOS)
    out = Image.new("RGBA", (dw, dh), (0, 0, 0, 0))
    out.paste(img, ((dw - img.width) // 2, dh - img.height - 2), img)
    out = post_kin.violet_shade(out)
    out = post_kin.halftone(out)
    out = post_kin.ink_outline(out)
    out.save(os.path.join(OUT, "%s.png" % did))
    out.resize((dw * 4, dh * 4), Image.NEAREST).save(
        os.path.join(A, "%s_x4.png" % did))
    print("posted", did, "%dx%d" % (dw, dh))


if __name__ == "__main__":
    process(sys.argv[1])
