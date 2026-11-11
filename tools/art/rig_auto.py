#!/usr/bin/env python3
"""Parametric rig generator — derives a render_kin.py RIGS entry for every
species from its data (body archetype + palette), seeded by id so every kin
is distinct within its archetype. Writes tools/art/rigs_gen.py:

    python3 tools/art/rig_auto.py   # regenerates rigs_gen.py from species_dump.json
"""
import json, os, math, random

HERE = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HERE, "..", "species_dump.json")
OUT = os.path.join(HERE, "rigs_gen.py")

# Legendary accessories — the old procedural sprites stamped these; the rigs
# keep the same identity marks (see gen_assets.py ACCESSORY).
ACCESSORY = {
    "scalbeak": "crown", "snovstride": "halo", "nibhand": "mask",
    "shadekin": "horns", "wyrmhoof": "horns", "cindchew": "crest",
    "flarbeak": "crest", "tidscale": "fins", "scalcrest": "crown",
    "vermtrot": "wings",
}

INK = (0.11, 0.10, 0.18)


def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) / 255 for i in (0, 2, 4))


def shade(c, k):
    return tuple(min(1.0, max(0.0, v * k)) for v in c)


def shift(c, dh, ds, dv):
    """Small hue/sat/value nudge for accent derivation."""
    import colorsys
    h, s, v = colorsys.rgb_to_hsv(*c)
    return colorsys.hsv_to_rgb((h + dh) % 1.0, min(1, max(0, s * ds)), min(1, max(0, v * dv)))


def legs(x, y, z, h, r, mat):
    return [{"kind": "cyl", "c": (sx * x, sy * y, z + h / 2), "r": r, "depth": h, "mat": mat}
            for sx in (-1, 1) for sy in (-1, 1)]


def eyes(x, y, z, r, mat, dx=0.0):
    return [{"kind": "sph", "c": (-x + dx, y, z), "r": r, "mat": mat},
            {"kind": "sph", "c": (x + dx, y, z), "r": r, "mat": mat}]


def accessory(kind, top):
    """Extra parts stamped on the head anchor `top` = (x, y, z) approx."""
    x, y, z = top
    if kind == "crown":
        P = [{"kind": "cyl", "c": (x, y, z + 0.06), "r": 0.09, "depth": 0.12, "mat": 4}]
        P += [{"kind": "cyl", "c": (x + dx, y, z + 0.18), "r": 0.035, "depth": 0.12, "mat": 4}
              for dx in (-0.07, 0.0, 0.07)]
        return P
    if kind == "halo":
        return [{"kind": "sph", "c": (x + 0.16 * math.cos(a), y, z + 0.05 + 0.16 * math.sin(a)),
                 "r": 0.035, "mat": 4} for a in [i * 1.2566 for i in range(5)]]
    if kind == "horns":
        return [{"kind": "cyl", "c": (x + sx * 0.16, y, z + 0.1), "r": 0.04, "depth": 0.22,
                 "rot": (0, sx * 0.7, 0), "mat": 4} for sx in (-1, 1)]
    if kind == "crest":
        return [{"kind": "sph", "c": (x, y, z + 0.08), "r": (0.05, 0.14, 0.16), "mat": 4}]
    if kind == "fins":
        return [{"kind": "sph", "c": (x + sx * 0.24, y + 0.05, z + 0.02),
                 "r": (0.04, 0.16, 0.12), "rot": (0, 0, sx * 0.5), "mat": 4} for sx in (-1, 1)]
    if kind == "mask":
        return [{"kind": "sph", "c": (x, y - 0.05, z), "r": (0.26, 0.05, 0.09), "mat": 1}]
    if kind == "wings":  # back fan
        return [{"kind": "sph", "c": (x, y + 0.3, z), "r": (0.3, 0.05, 0.18),
                 "rot": (0.5, 0, 0), "mat": 4}]
    return []


def gen(sid, body, col, rng):
    """Return a rig dict: mats + parts (+ optional f1 bob)."""
    m0 = col                       # body
    m1 = shade(col, 0.72)          # accent = darker body
    m2 = INK                       # ink beads
    m3 = shift(col, 0.06, 1.1, 0.9)  # cheek/belly tint
    m4 = shift(col, 0.45, 1.4, 0.95)  # feature accent (beak/crest)
    s = rng.uniform(0.85, 1.15)    # size jitter
    P = []

    def blob():
        nonlocal P
        r = 0.62 * s
        P.append({"kind": "sph", "c": (0, 0, r * 0.9), "r": (r, r * 0.9, r * 0.95), "mat": 0})
        # crown blob
        if rng.random() < 0.7:
            P.append({"kind": "sph", "c": (rng.uniform(-0.08, 0.08), -0.02, r * 1.75),
                      "r": (r * 0.4, r * 0.36, r * 0.34), "mat": 1})
        # stubby feet
        for sx in (-1, 1):
            P.append({"kind": "cyl", "c": (sx * r * 0.42, -0.1, 0.08), "r": 0.09, "depth": 0.16, "mat": 1})
        P += eyes(r * 0.4, -r * 0.93, r * 1.12, 0.085, 2)
        P.append({"kind": "sph", "c": (0, -r * 0.72, r * 0.55), "r": (r * 0.55, r * 0.5, r * 0.45), "mat": 3})
        P.append({"kind": "sph", "c": (0, -r * 0.98, r * 0.8), "r": (0.1, 0.04, 0.05), "mat": 2})

    def quadruped(scale=1.0, head_z=1.0, horn=0.0, ear_r=0.14):
        nonlocal P
        bl = 0.62 * s * scale      # body length half-extent
        bh = 0.40 * s * scale      # body half-height
        bz = 0.62 * s * scale      # body center z
        hz = bz + bh * (0.55 + (head_z - 1.0) * 0.8)  # head_z raises the head
        P.append({"kind": "sph", "c": (0, 0.1, bz), "r": (bh * 0.9, bl, bh), "mat": 0})
        P.append({"kind": "sph", "c": (0, -bl - 0.12, hz), "r": (0.24, 0.26, 0.26), "mat": 1})
        P += legs(bh * 0.62, bl * 0.55, 0, bz - bh * 0.7 + 0.18, 0.085, 1)
        for sx in (-1, 1):  # ears / horns
            P.append({"kind": "sph", "c": (sx * 0.20, -bl - 0.06, hz + bh * 0.35),
                      "r": (ear_r, 0.07, ear_r + horn), "rot": (0, 0, sx * 0.45), "mat": 1})
        P.append({"kind": "sph", "c": (0, bl + 0.2, bz + bh * 0.3), "r": (0.07, 0.16, 0.07), "mat": 1})  # tail
        P += eyes(0.12, -bl - 0.38, hz + bh * 0.14, 0.065, 2)

    def bird():
        nonlocal P
        r = 0.5 * s
        P.append({"kind": "sph", "c": (0, 0, r + 0.25), "r": (r * 0.85, r, r * 1.05), "mat": 0})
        P.append({"kind": "sph", "c": (0, -r * 0.8, r * 1.9), "r": (r * 0.55, r * 0.55, r * 0.55), "mat": 0})
        P.append({"kind": "sph", "c": (0, -r * 1.35, r * 1.82), "r": (0.14, 0.26, 0.11), "mat": 4})  # beak
        for sx in (-1, 1):  # wings
            P.append({"kind": "sph", "c": (sx * r * 0.9, 0.05, r + 0.2),
                      "r": (0.1, r * 0.55, r * 0.42), "rot": (0.15, 0, sx * 0.2), "mat": 1})
        P.append({"kind": "sph", "c": (0, r * 0.85, r * 1.35), "r": (0.12, 0.3, 0.1), "mat": 1})  # tail
        for sx in (-1, 1):
            P.append({"kind": "cyl", "c": (sx * 0.14, -0.05, 0.12), "r": 0.05, "depth": 0.24, "mat": 1})
        P += eyes(0.17, -r * 1.34, r * 2.0, 0.065, 2)

    def ghost():
        nonlocal P
        r = 0.55 * s
        P.append({"kind": "sph", "c": (0, 0, r * 1.5), "r": (r, r * 0.9, r * 1.5), "mat": 0})
        # ragged hem — a row of fluff puffs
        P.append({"kind": "fluff", "c": (0, 0, r * 0.35), "r": r * 0.7, "n": 8,
                  "sq": 0.9, "seed": rng.randint(1, 999), "jitter": 0.1, "mat": 0})
        for sx in (-1, 1):  # stub arms
            P.append({"kind": "sph", "c": (sx * r * 1.0, -0.1, r * 1.2), "r": (0.16, 0.12, 0.2), "mat": 0})
        P += eyes(0.21, -r * 0.94, r * 1.95, 0.08, 2)

    def human():
        nonlocal P
        t = 0.34 * s
        P.append({"kind": "sph", "c": (0, 0, 0.95 * s), "r": (t, t * 0.75, t * 1.4), "mat": 0})  # torso
        P.append({"kind": "sph", "c": (0, -0.02, 1.55 * s), "r": (0.24, 0.22, 0.24), "mat": 3})  # head
        P.append({"kind": "sph", "c": (0, -0.02, 1.78 * s), "r": (0.2, 0.18, 0.12), "mat": 0})   # helm
        for sx in (-1, 1):
            P.append({"kind": "cyl", "c": (sx * (t + 0.1), -0.05, 0.95 * s), "r": 0.09, "depth": 0.55 * s,
                      "mat": 1})
            P.append({"kind": "cyl", "c": (sx * 0.14, 0, 0.28 * s), "r": 0.1, "depth": 0.56 * s, "mat": 1})
        P += eyes(0.1, -0.28, 1.58 * s, 0.06, 2)

    def serpent():
        nonlocal P
        n = 5
        r = 0.3 * s
        for i in range(n):  # body chain, tapering back
            k = i / (n - 1)
            P.append({"kind": "sph", "c": (math.sin(i * 1.1) * 0.16, i * r * 0.85 - r,
                                           r * (1.2 + 0.5 * math.sin(i * 0.9))),
                      "r": (r * (1 - k * 0.45),) * 3, "mat": 0 if i % 2 == 0 else 1})
        hx, hy, hz = 0.0, -r - 0.1, r * 1.2
        P.append({"kind": "sph", "c": (hx, hy, hz), "r": (r * 1.1, r * 1.15, r), "mat": 0})
        P += eyes(0.15, hy - r * 1.18, hz + 0.06, 0.065, 2)

    def small_quad(ear_big, tail_len):
        nonlocal P
        r = 0.4 * s
        P.append({"kind": "sph", "c": (0, 0.05, r + 0.15), "r": (r, r * 1.15, r), "mat": 0})
        P.append({"kind": "sph", "c": (0, -r * 1.2, r * 1.9), "r": (r * 0.62, r * 0.58, r * 0.6), "mat": 0})
        for sx in (-1, 1):
            P.append({"kind": "sph", "c": (sx * r * 0.55, -r * 1.1, r * 2.45),
                      "r": (ear_big, 0.05, ear_big), "rot": (0, 0, sx * 0.3), "mat": 1})
        P += legs(r * 0.55, r * 0.6, 0, r * 0.7, 0.06, 1)
        P.append({"kind": "cyl", "c": (0, r * 1.2, r + 0.2), "r": 0.04, "depth": tail_len, "mat": 1,
                  "rot": (0.7, 0, 0)})
        P += eyes(0.16, -r * 1.8, r * 1.95, 0.065, 2)

    def hedgehog():
        nonlocal P
        r = 0.5 * s
        # body mound first so the fluff sits on its back half, feet under body
        P.append({"kind": "sph", "c": (0, 0.05, r * 0.75), "r": (r * 0.8, r * 1.0, r * 0.75), "mat": 0})
        P.append({"kind": "fluff", "c": (0, 0.28, r * 1.05), "r": r * 0.95, "n": 20,
                  "sq": 0.8, "seed": rng.randint(1, 999), "jitter": 0.15, "mat": 1})
        # face out front, clear of the fluff
        P.append({"kind": "sph", "c": (0, -r * 1.05, r * 0.85), "r": (r * 0.5, r * 0.55, r * 0.45), "mat": 3})
        for sx in (-1, 1):
            P.append({"kind": "cyl", "c": (sx * r * 0.45, -r * 0.35, 0.08), "r": 0.07, "depth": 0.16, "mat": 1})
        P.append({"kind": "sph", "c": (0, -r * 1.62, r * 0.8), "r": (0.08, 0.05, 0.06), "mat": 2})  # nose
        P += eyes(0.17, -r * 1.58, r * 1.0, 0.065, 2)

    def monkey():
        nonlocal P
        t = 0.32 * s
        P.append({"kind": "sph", "c": (0, 0, 0.9 * s), "r": (t, t * 0.8, t * 1.3), "mat": 0})
        P.append({"kind": "sph", "c": (0, -0.02, 1.45 * s), "r": (0.26, 0.24, 0.26), "mat": 3})
        for sx in (-1, 1):
            P.append({"kind": "sph", "c": (sx * 0.3, -0.02, 1.5 * s), "r": (0.09, 0.06, 0.12), "mat": 3})
            P.append({"kind": "cyl", "c": (sx * (t + 0.12), -0.02, 0.75 * s), "r": 0.08, "depth": 0.7 * s, "mat": 1})
            P.append({"kind": "cyl", "c": (sx * 0.13, 0, 0.24 * s), "r": 0.09, "depth": 0.48 * s, "mat": 1})
        P.append({"kind": "sph", "c": (0, t * 1.6, 0.7 * s), "r": (0.06, 0.3, 0.06), "rot": (-0.6, 0, 0), "mat": 1})
        P += eyes(0.11, -0.29, 1.5 * s, 0.06, 2)

    archetypes = {
        "blob": blob, "quadruped": quadruped, "bird": bird, "ghost": ghost,
        "human": human, "serpent": serpent,
        "cow": lambda: quadruped(scale=1.25, horn=0.1),
        "deer": lambda: quadruped(scale=0.95, head_z=1.15, horn=0.28, ear_r=0.1),
        "kitty": lambda: small_quad(ear_big=0.12, tail_len=0.4),
        "mouse": lambda: small_quad(ear_big=0.22, tail_len=0.5),
        "monkey": monkey, "boar": lambda: quadruped(scale=1.1, horn=0.05),
        "hedgehog": hedgehog,
    }
    archetypes.get(body, blob)()
    acc = ACCESSORY.get(sid)
    if acc:  # head-top anchor per archetype (approx, in rig units)
        top = {
            "blob": (0, 0, 1.15 * s), "quadruped": (0, -0.62, 1.05 * s),
            "cow": (0, -0.72, 1.15 * s), "deer": (0, -0.62, 1.2 * s),
            "boar": (0, -0.66, 1.05 * s), "bird": (0, -0.42, 1.25 * s),
            "ghost": (0, 0, 1.6 * s), "human": (0, -0.02, 1.85 * s),
            "serpent": (0, -0.35, 0.7 * s), "kitty": (0, -0.5, 1.0 * s),
            "mouse": (0, -0.5, 1.0 * s), "hedgehog": (0, -0.1, 1.0 * s),
            "monkey": (0, -0.02, 1.75 * s),
        }.get(body, (0, 0, 1.2 * s))
        P += accessory(acc, top)
    return {"mats": [m0, m1, m2, m3, m4], "parts": tuple(P),
            "f1": {"fluff_dy": 0.06, "ear_drop": 0.3, "head_dy": 0.04}}


def fmt_col(c):
    return "(%.3f, %.3f, %.3f)" % c


def emit(species):
    lines = ["# Auto-generated by rig_auto.py — do not edit by hand", "RIGS_GEN = {"]
    for sp in species:
        sid, body, col = sp["id"], sp.get("body") or "blob", hx(sp["color"])
        rng = random.Random(sid)
        rig = gen(sid, body, col, rng)
        lines.append('    "%s": {' % sid)
        lines.append('        "mats": [%s],' % ", ".join(fmt_col(m) for m in rig["mats"]))
        lines.append('        "parts": (')
        for p in rig["parts"]:
            d = dict(p)
            c = d.pop("c"); kind = d.pop("kind"); mat = d.pop("mat")
            rest = ", ".join('%r: %r' % (k, v) for k, v in d.items())
            rest = (rest + ", ") if rest else ""
            lines.append('            {"kind": %r, "c": %r, %s"mat": %d},' % (kind, tuple(round(v,3) for v in c), rest, mat))
        lines.append('        ),')
        lines.append('        "f1": %r,' % rig["f1"])
        lines.append('    },')
    lines.append("}")
    open(OUT, "w").write("\n".join(lines) + "\n")


def main():
    species = [sp for sp in json.load(open(DUMP)) if sp["id"] != "fenjelly"]
    emit(species)
    print("rigs_gen.py: %d rigs" % len(species))


if __name__ == "__main__":
    main()
