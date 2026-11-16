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
    # batch 3 — farms / defense / misc
    "berry_farm": (176, 134), "wheat_farm": (176, 134), "ranch": (240, 166),
    "straw_bed": (112, 120), "hot_spring": (144, 136),
    "fish_trap": (80, 104), "snare_trap": (80, 104), "kin_cage": (80, 104),
    "guard_post": (80, 104), "training_hall": (144, 136),
    "sparring_ring": (144, 136), "training_dummy": (80, 104),
    "war_banner": (80, 104), "monitoring_stand": (80, 104),
    # batch 4 — remaining machines / POI misc
    "pharmacy": (112, 120), "oil_extractor": (144, 136),
    "sphere_factory": (112, 120), "sphere_factory_2": (112, 120),
    "compost_bin": (80, 104), "apiary": (80, 104),
    "weather_shrine": (80, 104), "kin_gacha": (80, 104),
    "fossil_bed": (80, 104), "spyglass": (80, 104),
    "lightning_rod": (80, 104), "expedition_post": (112, 120),
}


def process(sid):
    dw, dh = DIMS[sid]
    img = Image.open(os.path.join(A, "struct_%s_f0.png" % sid)).convert("RGBA")
    img = post_kin.crop_alpha(img)
    if sum(img.getchannel("A").histogram()[41:]) < 50:
        sys.exit("FAIL %s: blank render (<50 opaque px)" % sid)
    # audit-58: the shipped-sprite top-band smoke pin is unreachable for
    # small dims — clip detection belongs HERE on the tight crop. A
    # camera-clipped frame has a flat solid edge; a framed sprite tapers
    # to spire tips (top/sides, sparse) or a ground base (bottom, wide
    # but not solid). Thresholds tuned so real tips pass and any clip
    # (~100% edge) fails.
    w, h = img.size
    al = img.getchannel("A")
    px = al.load()
    def frac_opaque(x0, y0, x1, y1):
        n = 0; t = (x1 - x0) * (y1 - y0)
        for yy in range(y0, y1):
            for xx in range(x0, x1):
                if px[xx, yy] > 40:
                    n += 1
        return n / max(1, t)
    # measured on all 50 crops: legit max top=0.73 (guard_post's wide
    # roof), sides=0.37, bottom≈0. A camera clip leaves a flat ~1.00
    # frame edge — 0.80/0.95 thresholds separate them with margin.
    if frac_opaque(0, 0, w, 1) > 0.80:
        sys.exit("FAIL %s: top edge clipped (%.2f opaque)" % (sid, frac_opaque(0, 0, w, 1)))
    if frac_opaque(0, 0, 1, h) > 0.80 or frac_opaque(w - 1, 0, w, h) > 0.80:
        sys.exit("FAIL %s: side edge clipped" % sid)
    if frac_opaque(0, h - 1, w, h) > 0.95:
        sys.exit("FAIL %s: bottom edge clipped" % sid)
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
