#!/usr/bin/env python3
"""Post-process a Blender kin render into a game sprite:
alpha-crop → cel-band luminance (posterize, keep hue) → warm pastel lift →
ink contour → halftone in the shade band → 80x64 output.

    python3 tools/art/post_kin.py fenjelly
reads tools/art/render/<sid>_f{0,1}.png, writes assets/kin/<sid>_f{0,1}.png
"""
from PIL import Image, ImageOps
import os, sys, math

A = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "kin")
INK = (28, 26, 46)
VIOLET = (91, 74, 138)
PW, PH = 80, 64
# cel levels — absolute posterized luminance, hue preserved. Five steps is
# the poster palette: ink-shade / shade / mid / lit / hot.
LEVELS = [46, 96, 152, 208, 245]
EDGES = [70, 130, 185, 232]  # lum thresholds between the five levels


def crop_alpha(img, pad=10):
    a = img.getchannel("A")
    bbox = a.getbbox()
    if not bbox:
        return img
    l, t, r, b = bbox
    return img.crop((max(0, l - pad), max(0, t - pad), min(img.width, r + pad), min(img.height, b + pad)))


def cel_band(img):
    """Posterize luminance to LEVELS at EDGES, preserving chroma."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < 1:
                continue
            i = 0
            while i < len(EDGES) and lum >= EDGES[i]:
                i += 1
            k = LEVELS[i] / lum
            px[x, y] = (min(255, int(r * k)), min(255, int(g * k)),
                        min(255, int(b * k)), a)
    return img


def warm_lift(img, warm=1.05, sat=1.12):
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            r2 = lum + (r - lum) * sat
            g2 = lum + (g - lum) * sat
            b2 = lum + (b - lum) * sat
            px[x, y] = (min(255, int(r2 * warm)),
                        min(255, int(g2)),
                        min(255, int(b2 * (2 - warm))), a)
    return img


def violet_shade(img):
    """Darkest band drifts toward lilac — poster shadow hue."""
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < 100:
                m = (100 - lum) / 100.0 * 0.4
                px[x, y] = (int(r * (1 - m) + VIOLET[0] * m),
                            int(g * (1 - m) + VIOLET[1] * m),
                            int(b * (1 - m) + VIOLET[2] * m), a)
    return img


def ink_outline(img):
    px = img.load()
    src = [p[:] for p in [list(px[x, y]) for y in range(img.height) for x in range(img.width)]]
    w, h = img.width, img.height
    def ap(xx, yy):
        return src[yy * w + xx][3] if 0 <= xx < w and 0 <= yy < h else 0
    for y in range(h):
        for x in range(w):
            if src[y * w + x][3] > 30:
                continue
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,-1),(1,-1),(-1,1)):
                if ap(x + dx, y + dy) > 100:
                    px[x, y] = INK + (255,)
                    break
    # thin existing edge pixels toward ink (anti-aliased rim becomes ink)
    for y in range(h):
        for x in range(w):
            a = src[y * w + x][3]
            if 30 < a < 100:
                c = src[y * w + x][:3]
                k = a / 255.0
                px[x, y] = (int(INK[0] * k + c[0] * (1 - k)),
                            int(INK[1] * k + c[1] * (1 - k)),
                            int(INK[2] * k + c[2] * (1 - k)), 255)
    # solidify: bright interior pixels touching transparency pull toward ink,
    # closing the contour where a lit edge would otherwise dissolve
    for y in range(h):
        for x in range(w):
            a = src[y * w + x][3]
            if a <= 100:
                continue
            near = False
            for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                if ap(x + dx, y + dy) <= 30:
                    near = True
                    break
            if near:
                c = src[y * w + x][:3]
                px[x, y] = (int(INK[0] * 0.6 + c[0] * 0.4),
                            int(INK[1] * 0.6 + c[1] * 0.4),
                            int(INK[2] * 0.6 + c[2] * 0.4), a)
    return img


def halftone(img, thresh=100, period=5, duty=2, strength=0.5):
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < thresh and (x + 2 * y) % period < duty:
                px[x, y] = (int(r * (1 - strength) + INK[0] * strength),
                            int(g * (1 - strength) + INK[1] * strength),
                            int(b * (1 - strength) + INK[2] * strength), a)
    return img


def fit(img):
    """Resize the cropped render into the 80x64 sprite box, feet near bottom."""
    img.thumbnail((PW - 8, PH - 8), Image.LANCZOS)
    out = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    x = (PW - img.width) // 2
    y = PH - img.height - 2  # feet 2px off the floor line
    out.paste(img, (x, y), img)
    return out


def process(sid):
    for f in (0, 1):
        img = Image.open(os.path.join(A, "%s_f%d.png" % (sid, f))).convert("RGBA")
        img = crop_alpha(img)
        # a fully/nearly transparent render (camera miss, hidden mesh, dead
        # action) must not pass as "ok" — bail so the batch tally stays true
        if sum(img.getchannel("A").histogram()[41:]) < 50:
            sys.exit("FAIL %s_f%d: blank render "
                     "(<50 opaque px)" % (sid, f))
        img = cel_band(img)
        img = warm_lift(img)
        img = fit(img)
        img = violet_shade(img)
        img = halftone(img)
        img = ink_outline(img)
        img.save(os.path.join(OUT, "%s_f%d.png" % (sid, f)))
        # 4x preview for review
        img.resize((PW * 4, PH * 4), Image.NEAREST).save(
            os.path.join(A, "%s_f%d_x4.png" % (sid, f)))
    print("posted", sid)


if __name__ == "__main__":
    process(sys.argv[1] if len(sys.argv) > 1 else "fenjelly")
