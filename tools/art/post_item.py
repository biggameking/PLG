# Post an item-kind render to a 24x24 HUD icon — same chain as
# post_structure.py but square, no bottom-anchor rule (icons center).
#
#   python3 post_item.py <kind>
#
# Output: assets/items/icons/<kind>.png

import os
import sys
from PIL import Image
import post_kin

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")
OUT = os.path.join(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))),
    "assets", "items", "icons")

DIM = 24


def process(kind):
    img = Image.open(os.path.join(A, "item_%s_f0.png" % kind)).convert("RGBA")
    img = post_kin.crop_alpha(img)
    if sum(img.getchannel("A").histogram()[41:]) < 50:
        sys.exit("FAIL %s: blank render (<50 opaque px)" % kind)
    w, h = img.size
    al = img.getchannel("A")
    px = al.load()
    def frac_opaque(x0, y0, x1, y1):
        n = 0
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                if px[xx, yy] > 40:
                    n += 1
        return n / max(1, (x1 - x0) * (y1 - y0))
    if frac_opaque(0, 0, w, 1) > 0.80:
        sys.exit("FAIL %s: top edge clipped" % kind)
    if frac_opaque(0, h - 1, w, h) > 0.95:
        sys.exit("FAIL %s: bottom edge clipped" % kind)
    if frac_opaque(0, 0, 1, h) > 0.80 or frac_opaque(w - 1, 0, w, h) > 0.80:
        sys.exit("FAIL %s: side edge clipped" % kind)
    img = post_kin.cel_band(img)
    img = post_kin.warm_lift(img)
    img.thumbnail((DIM - 4, DIM - 4), Image.LANCZOS)
    out = Image.new("RGBA", (DIM, DIM), (0, 0, 0, 0))
    out.paste(img, ((DIM - img.width) // 2, (DIM - img.height) // 2), img)
    out = post_kin.ink_outline(out)
    os.makedirs(OUT, exist_ok=True)
    out.save(os.path.join(OUT, "%s.png" % kind))
    out.resize((DIM * 4, DIM * 4), Image.NEAREST).save(
        os.path.join(A, "item_%s_x4.png" % kind))
    print("posted", kind, "%dx%d" % (DIM, DIM))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: post_item.py <kind>")
    process(sys.argv[1])
