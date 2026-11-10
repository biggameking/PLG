#!/usr/bin/env python3
# Store capsule generator — PIL port of hud.gd's draw_title_sky + brand mark
# + a kin lineup. Procedural, same palette contract as the title scene.
# Outputs: store/capsule_460x215.png, store/capsule_616x353.png,
#          store/itch_banner_630x500.png, store/hero_1920x622.png
import math, os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "fonts", "PressStart2P-Regular.ttf")

SKY_TOP = (26, 46, 87)
SKY_BOT = (148, 102, 117)
SUN = (255, 222, 128)
SEA = (13, 41, 61)
RIDGE = (10, 26, 36)
TREE = (13, 36, 31)
GOLD = (232, 212, 77)
INK = (16, 20, 30)

LINEUP = ["fenjelly", "wyrmhoof", "snovstride", "scalbeak", "embpaw"]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def draw_scene(W, H):
    img = Image.new("RGB", (W, H), SKY_TOP)
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(24):  # 24-band vertical gradient
        c = lerp(SKY_TOP, SKY_BOT, i / 23.0)
        d.rectangle([0, int(H * i / 24), W, int(H * (i + 1) / 24)], fill=c)
    sun = (W * 0.70, H * 0.27)
    sun_r = H * 0.11
    for ring in range(4, 0, -1):  # halo, outside-in
        d.ellipse([sun[0] - sun_r - ring * sun_r * 0.45, sun[1] - sun_r - ring * sun_r * 0.45,
                   sun[0] + sun_r + ring * sun_r * 0.45, sun[1] + sun_r + ring * sun_r * 0.45],
                  fill=(255, 217, 115, 14))
    d.ellipse([sun[0] - sun_r, sun[1] - sun_r, sun[0] + sun_r, sun[1] + sun_r], fill=SUN)
    for c in range(6):  # cloud lanes, static frame (t=7 looks like the good screenshot)
        t = 7.0
        cxx = (W * (0.08 + c * 0.21) + t * (4.0 + c * 1.3)) % (W + W * 0.16) - W * 0.08
        cyy = H * (0.10 + c * 0.055)
        cr = H * 0.045
        for b in range(3):
            br = cr - abs(b - 1) * cr * 0.3
            d.ellipse([cxx + b * cr * 1.2 - br, cyy - abs(b - 1) * cr * 0.4 - br,
                       cxx + b * cr * 1.2 + br, cyy - abs(b - 1) * cr * 0.4 + br],
                      fill=(255, 255, 255, 26))
    sea_y = int(H * 0.68)
    d.rectangle([0, sea_y, W, H], fill=SEA)
    for g in range(9):  # sun path on the water
        gw = (W * 0.06) - g * (W * 0.006)
        yy = sea_y + g * (H - sea_y) / 9.0
        d.rectangle([sun[0] - gw / 2, yy, sun[0] + gw / 2, yy + max(2, H * 0.006)],
                    fill=(255, 217, 128, max(4, 26 - g * 2)))
    # island ridge — same polygon silhouette as the title scene
    d.polygon([(0, sea_y), (W * 0.18, sea_y - H * 0.11), (W * 0.34, sea_y - H * 0.05),
               (W * 0.52, sea_y - H * 0.15), (W * 0.7, sea_y - H * 0.07),
               (W, sea_y - H * 0.13), (W, sea_y)], fill=RIDGE)
    for tri in range(16):  # tree spikes
        tx = W * (0.04 + tri * 0.062)
        th = H * 0.035 + math.sin(tri * 7.0) * H * 0.02
        ty = sea_y - H * 0.02 - H * 0.07 * max(0.0, math.sin(tri * 1.7))
        d.polygon([(tx, ty - th), (tx - H * 0.017, ty), (tx + H * 0.017, ty)], fill=TREE)
    for m in range(18):  # motes
        mx = (m * 137.0 + 7.0 * 6.0) % W
        my = H * 0.15 + (m * 89.0 + 7.0 * 3.0) % (H * 0.5)
        d.ellipse([mx - 1.5, my - 1.5, mx + 1.5, my + 1.5], fill=(255, 242, 179, 90))
    return img, sea_y


def stamp_kin(img, sea_y, W, H):
    d = ImageDraw.Draw(img, "RGBA")
    n = len(LINEUP)
    scale = max(2, int(H / 64 * 0.55))  # kin are 80x64 — scale to scene height
    for i, sid in enumerate(LINEUP):
        path = os.path.join(ROOT, "assets", "kin", sid + "_f0.png")
        if not os.path.exists(path):
            continue
        spr = Image.open(path).convert("RGBA")
        w = int(spr.width * scale * 0.8)
        h = int(spr.height * scale * 0.8)
        spr = spr.resize((w, h), Image.NEAREST)
        # stand them on the ridge line, spread across the middle-left half
        x = int(W * (0.10 + i * (0.5 / max(1, n - 1))))
        y = int(sea_y - H * 0.09 - h * 0.75)
        # dark ground shadow keeps them planted
        d.ellipse([x + w * 0.1, y + h * 0.93, x + w * 0.9, y + h], fill=(0, 0, 0, 110))
        img.alpha_composite(spr, (x, y))


def wordmark(img, text="KINBOUND", size_frac=0.11, sub=None):
    W, H = img.size
    d = ImageDraw.Draw(img, "RGBA")
    fs = max(14, int(H * size_frac))
    f = ImageFont.truetype(FONT, fs)
    bbox = d.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x, y = (W - tw) / 2 - bbox[0], H * 0.16
    for ox, oy in [(-3, 0), (3, 0), (0, -3), (0, 3), (-2, -2), (2, 2), (-2, 2), (2, -2)]:
        d.text((x + ox, y + oy), text, font=f, fill=INK)
    d.text((x, y), text, font=f, fill=GOLD)
    d.rectangle([(W - tw) / 2, y + th + H * 0.02, (W + tw) / 2, y + th + H * 0.02 + max(2, H * 0.008)],
                fill=GOLD + (170,))
    if sub:
        f2 = ImageFont.truetype(FONT, max(9, int(fs * 0.28)))
        b2 = d.textbbox((0, 0), sub, font=f2)
        d.text(((W - (b2[2] - b2[0])) / 2 - b2[0], y + th + H * 0.05), sub, font=f2, fill=(230, 235, 240))


def vignette(img):
    # ImageDraw writes 4-tuples RAW onto an RGBA base — no blending. A full-
    # rect translucent fill would erase the scene; blend the whole frame
    # toward deep navy instead, then edge a hard dark frame.
    W, H = img.size
    dark = Image.new("RGBA", (W, H), (4, 8, 16, 255))
    img = Image.blend(img, dark, 0.10)
    d = ImageDraw.Draw(img)
    for i in range(6):  # edge falloff — soft frame like the title's wash
        a = int(30 - i * 4)
        d.rectangle([i * 3, i * 3, W - i * 3, H - i * 3], outline=(4, 6, 12, min(255, a * 6)), width=3)
    return img


def build(name, W, H, kin=True, size_frac=0.11, sub=None):
    img, sea_y = draw_scene(W, H)
    img = img.convert("RGBA")
    if kin:
        stamp_kin(img, sea_y, W, H)
    wordmark(img, "KINBOUND", size_frac, sub)
    img = vignette(img)
    out = os.path.join(ROOT, "store", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.convert("RGB").save(out)
    print("wrote", out, img.size)


if __name__ == "__main__":
    build("capsule_460x215.png", 460, 215, kin=False, size_frac=0.13)
    build("capsule_616x353.png", 616, 353)
    build("itch_banner_630x500.png", 630, 500, size_frac=0.09,
          sub="collect · craft · survive the Wildmere")
    build("hero_1920x622.png", 1920, 622, size_frac=0.14)
