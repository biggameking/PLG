#!/usr/bin/env python3
# PLG asset generator — all art is procedural. Run: python tools/gen_assets.py
# Writes into assets/: tiles.png + tiles.json (atlas), pals/<id>_f{0,1}.png,
# decor/*.png, structures/<id>.png, shadow.png, ui/element_orbs.png
import json, math, os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
for d in ["", "pals", "decor", "structures", "ui"]:
    os.makedirs(os.path.join(A, d), exist_ok=True)

# ---------- deterministic hash (same as engine) ----------
def hash2(x, y, seed):
    h = seed & 0xFFFFFFFF
    h ^= (x | 0) & 0xFFFFFFFF
    h = (h * 0x27d4eb2d) & 0xFFFFFFFF
    h ^= (y | 0) & 0xFFFFFFFF
    h = (h * 0x165667b1) & 0xFFFFFFFF
    h ^= h >> 15
    h = (h * 0x85ebca6b) & 0xFFFFFFFF
    h ^= h >> 13
    return (h & 0xFFFFFFFF) / 4294967296.0

# ---------- color helpers ----------
def hxc(hx):
    return tuple(int(hx[i:i+2], 16) for i in (1, 3, 5))

def hsl(hx):
    r, g, b = [c / 255 for c in hxc(hx)]
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return (0.0, 0.0, l)
    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        h = ((g - b) / d + 6) % 6
    elif mx == g:
        h = (b - r) / d + 2
    else:
        h = (r - g) / d + 4
    return (h * 60, s, l)

def rgb(h, s, l):
    h = (h % 360 + 360) % 360
    s = max(0, min(1, s)); l = max(0, min(1, l))
    c = (1 - abs(2 * l - 1)) * s
    x = c * (1 - abs((h / 60) % 2 - 1))
    m = l - c / 2
    if h < 60: r, g, b = c, x, 0
    elif h < 120: r, g, b = x, c, 0
    elif h < 180: r, g, b = 0, c, x
    elif h < 240: r, g, b = 0, x, c
    elif h < 300: r, g, b = x, 0, c
    else: r, g, b = c, 0, x
    return (round((r + m) * 255), round((g + m) * 255), round((b + m) * 255))

def ramp(hx):
    h, s, l = hsl(hx)
    return {
        "out": rgb(h + 25, min(1, s * 1.1), l * 0.22),
        "shade": rgb(h + 14, min(1, s * 1.15), l * 0.55),
        "base": rgb(h, s, l),
        "light": rgb(h - 12, min(1, s * 1.05), min(0.88, l * 1.3)),
        "spec": rgb(h - 25, s * 0.45, 0.93),
    }

DARK = {"out": rgb(230, 0.15, 0.06), "shade": rgb(230, 0.15, 0.1),
        "base": rgb(25, 0.12, 0.14), "light": rgb(25, 0.1, 0.22), "spec": rgb(30, 0.1, 0.4)}
WHITE = {"out": rgb(220, 0.25, 0.3), "shade": rgb(215, 0.2, 0.72),
         "base": rgb(0, 0, 1), "light": rgb(0, 0, 1), "spec": rgb(0, 0, 1)}

# =========================================================================
# PAL SPRITES — port of prototype/src/game/sprite.ts, coords x2 → 80x64
# =========================================================================
PW, PH = 80, 64

def newbuf():
    return [[0] * PW for _ in range(PH)]

def S(b, x, y, c):
    x, y = int(x) * 2, int(y) * 2
    if 0 <= x < PW - 1 and 0 <= y < PH - 1:
        b[y][x] = b[y][x + 1] = b[y + 1][x] = b[y + 1][x + 1] = c

def R(b, x0, y0, x1, y1, c):
    for y in range(int(y0) * 2, int(y1) * 2 + 2):
        for x in range(int(x0) * 2, int(x1) * 2 + 2):
            if 0 <= x < PW and 0 <= y < PH:
                b[y][x] = c

def E(b, cx, cy, rx, ry, c):
    cx, cy, rx, ry = cx * 2, cy * 2, rx * 2, ry * 2
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            dx, dy = (x - cx) / rx, (y - cy) / ry
            if dx * dx + dy * dy <= 1 and 0 <= x < PW and 0 <= y < PH:
                b[y][x] = c

def D(b, cx, cy, r, c):
    E(b, cx, cy, r, r, c)

def quadruped(b, f):
    s = 1 if f else 0
    R(b, 8, 24+s, 10, 30+s, 1); R(b, 14, 24+(1-s), 16, 30+(1-s), 1)
    R(b, 22, 24+(1-s), 24, 30+(1-s), 1); R(b, 28, 24+s, 30, 30+s, 1)
    R(b, 8, 30+s, 10, 31+s, 3); R(b, 14, 30+(1-s), 16, 31+(1-s), 3)
    R(b, 22, 30+(1-s), 24, 31+(1-s), 3); R(b, 28, 30+s, 30, 31+s, 3)
    E(b, 18, 19, 12, 7, 1); E(b, 17, 22, 8, 4, 2)
    D(b, 29, 11, 6, 1)
    R(b, 24, 3, 26, 8, 3); S(b, 25, 5, 4); S(b, 25, 6, 4); S(b, 25, 7, 4)
    R(b, 32, 3, 34, 8, 3); S(b, 33, 5, 4); S(b, 33, 6, 4); S(b, 33, 7, 4)
    S(b, 29, 9, 4); S(b, 30, 8, 5); S(b, 30, 10, 4)
    S(b, 34, 13, 4); S(b, 34, 14, 4)
    R(b, 5, 15, 7, 19, 3); S(b, 4, 17, 5)
    S(b, 12, 15, 2); S(b, 15, 17, 2); S(b, 10, 20, 2)

def kitty(b, f):
    s = 1 if f else 0
    R(b, 12, 24+s, 14, 30+s, 1); R(b, 24, 24+(1-s), 26, 30+(1-s), 1)
    R(b, 12, 30+s, 14, 31+s, 3); R(b, 24, 30+(1-s), 26, 31+(1-s), 3)
    E(b, 17, 20, 10, 6, 1); E(b, 17, 22, 7, 3, 2)
    D(b, 28, 11, 5, 1)
    R(b, 23, 4, 25, 8, 3); S(b, 24, 6, 4)
    R(b, 31, 4, 33, 8, 3); S(b, 32, 6, 4)
    R(b, 5, 6, 7, 15, 3); S(b, 5, 4, 5); S(b, 6, 4, 3)
    S(b, 28, 10, 4); S(b, 29, 9, 5); S(b, 29, 11, 4)
    S(b, 32, 13, 4); S(b, 33, 13, 4); S(b, 33, 15, 4)
    S(b, 13, 16, 3); S(b, 16, 15, 3); S(b, 19, 16, 3)

def bird(b, f):
    s = 1 if f else 0
    R(b, 16, 26+s, 17, 29+s, 4); R(b, 15, 30+s, 18, 30+s, 4)
    R(b, 21, 26+(1-s), 22, 29+(1-s), 4); R(b, 20, 30+(1-s), 23, 30+(1-s), 4)
    E(b, 19, 18, 9, 9, 1); E(b, 19, 21, 6, 5, 2)
    E(b, 14, 17, 4, 6, 2)
    S(b, 13, 21, 3); S(b, 13, 22, 3); S(b, 15, 23, 3)
    D(b, 21, 7, 5, 1)
    R(b, 26, 6, 30, 9, 3); S(b, 31, 7, 3)
    S(b, 21, 6, 4); S(b, 22, 5, 5); S(b, 22, 7, 4)
    S(b, 19, 1, 3); S(b, 21, 0, 3); S(b, 23, 1, 3)
    R(b, 8, 15, 10, 21, 3); S(b, 8, 22, 3)

def mouse(b, f):
    s = 1 if f else 0
    R(b, 14, 26+s, 16, 29+s, 1); R(b, 20, 26+(1-s), 22, 29+(1-s), 1)
    R(b, 14, 29+s, 16, 30+s, 3); R(b, 20, 29+(1-s), 22, 30+(1-s), 3)
    D(b, 18, 20, 8, 1); D(b, 18, 23, 5, 2)
    D(b, 26, 14, 5, 1)
    D(b, 22, 7, 4, 3); D(b, 22, 7, 2, 4)
    D(b, 30, 7, 4, 3); D(b, 30, 7, 2, 4)
    R(b, 8, 22, 11, 24, 3); S(b, 7, 21, 3); S(b, 6, 20, 3)
    S(b, 26, 13, 4); S(b, 27, 12, 5)
    S(b, 30, 15, 4); S(b, 29, 17, 5)
    S(b, 15, 14, 2); S(b, 18, 12, 2)

def hedgehog(b, f):
    s = 1 if f else 0
    R(b, 11, 27+s, 13, 30+s, 2); R(b, 22, 27+(1-s), 24, 30+(1-s), 2)
    E(b, 19, 21, 13, 7, 1); E(b, 19, 24, 9, 3, 2)
    for x in range(8, 31):
        S(b, x, 15 - (x % 3), 3); S(b, x, 14 - (x % 3), 3)
    for x in range(11, 28):
        S(b, x, 11 - (x % 3), 3)
    D(b, 31, 19, 5, 1)
    S(b, 31, 17, 4); S(b, 32, 16, 5)
    S(b, 35, 20, 4); S(b, 35, 21, 4); S(b, 33, 23, 4)

def deer(b, f):
    s = 1 if f else 0
    R(b, 8, 24+s, 10, 30+s, 1); R(b, 14, 24+(1-s), 16, 30+(1-s), 1)
    R(b, 23, 24+(1-s), 25, 30+(1-s), 1); R(b, 29, 24+s, 31, 30+s, 1)
    R(b, 8, 30+s, 10, 31+s, 4); R(b, 14, 30+(1-s), 16, 31+(1-s), 4)
    R(b, 23, 30+(1-s), 25, 31+(1-s), 4); R(b, 29, 30+s, 31, 31+s, 4)
    E(b, 18, 19, 11, 7, 1); E(b, 17, 22, 8, 4, 2)
    D(b, 29, 11, 5, 1)
    R(b, 32, 12, 34, 14, 2); S(b, 34, 13, 4)
    R(b, 25, 2, 26, 6, 3); S(b, 24, 1, 3); S(b, 23, 2, 3); S(b, 27, 2, 3); S(b, 28, 1, 3)
    R(b, 31, 2, 32, 6, 3); S(b, 30, 1, 3); S(b, 33, 2, 3); S(b, 34, 1, 3)
    S(b, 29, 9, 4); S(b, 30, 8, 5)
    S(b, 5, 16, 3); S(b, 4, 15, 3)
    S(b, 11, 15, 2); S(b, 15, 13, 2); S(b, 19, 15, 2); S(b, 13, 18, 2)

def boar(b, f):
    s = 1 if f else 0
    R(b, 8, 24+s, 10, 30+s, 1); R(b, 14, 24+(1-s), 16, 30+(1-s), 1)
    R(b, 23, 24+(1-s), 25, 30+(1-s), 1); R(b, 30, 24+s, 32, 30+s, 1)
    R(b, 8, 30+s, 10, 31+s, 4); R(b, 14, 30+(1-s), 16, 31+(1-s), 4)
    R(b, 23, 30+(1-s), 25, 31+(1-s), 4); R(b, 30, 30+s, 32, 31+s, 4)
    E(b, 18, 20, 12, 7, 1); E(b, 17, 23, 9, 4, 2)
    R(b, 10, 11, 25, 14, 3)
    for x in range(10, 26, 2): S(b, x, 10, 3)
    R(b, 27, 13, 34, 20, 1)
    R(b, 33, 16, 36, 19, 2); S(b, 35, 17, 4)
    S(b, 30, 20, 5); S(b, 31, 20, 5); S(b, 30, 21, 5)
    S(b, 30, 14, 4); S(b, 31, 13, 5); S(b, 28, 12, 3)
    S(b, 5, 16, 3); S(b, 4, 15, 3); S(b, 5, 14, 3)

def cow(b, f):
    s = 1 if f else 0
    R(b, 8, 24+s, 10, 30+s, 1); R(b, 14, 24+(1-s), 16, 30+(1-s), 1)
    R(b, 23, 24+(1-s), 25, 30+(1-s), 1); R(b, 29, 24+s, 31, 30+s, 1)
    R(b, 8, 30+s, 10, 31+s, 4); R(b, 14, 30+(1-s), 16, 31+(1-s), 4)
    R(b, 23, 30+(1-s), 25, 31+(1-s), 4); R(b, 29, 30+s, 31, 31+s, 4)
    E(b, 18, 20, 12, 7, 1); E(b, 17, 23, 9, 4, 2)
    D(b, 30, 10, 5, 1)
    R(b, 25, 3, 27, 6, 3); R(b, 33, 3, 35, 6, 3)
    S(b, 24, 9, 2); S(b, 35, 9, 2)
    R(b, 31, 13, 34, 16, 2); S(b, 33, 14, 4); S(b, 34, 14, 4)
    S(b, 30, 9, 4); S(b, 31, 8, 5)
    D(b, 12, 16, 3, 2); D(b, 20, 21, 2, 2); D(b, 9, 21, 2, 2)
    R(b, 5, 15, 6, 22, 3); S(b, 5, 23, 3); S(b, 6, 23, 3)
    S(b, 19, 27, 3); S(b, 21, 27, 3)

def monkey(b, f):
    s = 1 if f else 0
    R(b, 15, 26+s, 17, 30+s, 1); R(b, 19, 26+(1-s), 21, 30+(1-s), 1)
    R(b, 15, 30+s, 17, 31+s, 3); R(b, 19, 30+(1-s), 21, 31+(1-s), 3)
    E(b, 18, 18, 8, 8, 1); D(b, 18, 20, 4, 2)
    R(b, 10, 15+s, 12, 21+s, 1); S(b, 11, 22+s, 3)
    R(b, 25, 15+(1-s), 27, 21+(1-s), 1); S(b, 26, 22+(1-s), 3)
    D(b, 18, 7, 5, 1); D(b, 18, 8, 3, 2)
    D(b, 13, 6, 2, 3); D(b, 23, 6, 2, 3)
    S(b, 17, 6, 4); S(b, 18, 5, 5); S(b, 20, 6, 4); S(b, 18, 10, 4)
    S(b, 9, 22, 3); S(b, 8, 21, 3); S(b, 8, 19, 3); S(b, 9, 18, 3); S(b, 11, 19, 3); S(b, 10, 20, 3)

def blob(b, f):
    s = 1 if f else 0
    E(b, 19, 22, 12, 8, 1); E(b, 19, 15+s, 9, 7, 1); E(b, 19, 24, 8, 4, 2)
    S(b, 15, 14+s, 4); S(b, 16, 13+s, 5); S(b, 23, 14+s, 4); S(b, 24, 13+s, 5)
    R(b, 17, 18+s, 21, 19+s, 4)
    S(b, 18, 7+s, 3); S(b, 19, 8+s, 3); S(b, 19, 6+s, 3)
    S(b, 8, 20, 1); S(b, 7, 19, 1); S(b, 30, 20, 1); S(b, 31, 19, 1)
    S(b, 13, 30, 1); S(b, 19, 30, 1); S(b, 25, 30, 1)

def serpent(b, f):
    pts = [(6, 26, 4), (11, 23+f, 5), (17, 19, 5), (24, 15-f, 5), (30, 10, 6)]
    for x, y, r in pts: D(b, x, y, r, 1)
    D(b, 30, 9, 6, 1)
    R(b, 25, 1, 27, 5, 3); S(b, 31, 0, 3); S(b, 32, 1, 3)
    S(b, 30, 7, 4); S(b, 31, 6, 5); S(b, 34, 10, 4); S(b, 34, 12, 5)
    S(b, 2, 26, 3); S(b, 1, 25, 3)
    E(b, 17, 21, 10, 4, 2)
    S(b, 13, 20, 3); S(b, 26, 13, 3); S(b, 10, 24, 2); S(b, 21, 17, 2)

def human(b, f):
    s = 1 if f else 0
    R(b, 15, 25+s, 17, 30+s, 2); R(b, 21, 25+(1-s), 23, 30+(1-s), 2)
    R(b, 15, 30+s, 17, 31+s, 4); R(b, 21, 30+(1-s), 23, 31+(1-s), 4)
    E(b, 19, 17, 7, 7, 1); E(b, 19, 22, 6, 4, 1)
    R(b, 14, 23, 24, 24, 4)
    R(b, 11, 14+s, 13, 20+s, 1); S(b, 12, 21+s, 3)
    R(b, 25, 14+(1-s), 27, 20+(1-s), 1); S(b, 26, 21+(1-s), 3)
    D(b, 19, 6, 5, 3)
    R(b, 14, 0, 24, 4, 4); S(b, 15, 5, 4); S(b, 14, 6, 4)
    S(b, 21, 5, 4); S(b, 22, 5, 5); S(b, 22, 8, 4)

def ghost(b, f):
    s = 1 if f else 0
    E(b, 19, 14+s, 11, 9, 1)
    for x in range(9, 30): S(b, x, 22 + s + (1 if x % 2 else 0), 1)
    for x in range(10, 29, 2): S(b, x, 23 + s + (1 if x % 4 else 0), 1)
    S(b, 11, 25+s, 1); S(b, 19, 25+s, 1); S(b, 26, 25+s, 1)
    D(b, 15, 13+s, 2, 4); S(b, 16, 12+s, 5)
    D(b, 23, 13+s, 2, 4); S(b, 24, 12+s, 5)
    S(b, 19, 17+s, 4); S(b, 20, 17+s, 4)
    S(b, 13, 16+s, 2); S(b, 25, 16+s, 2)
    S(b, 7, 15+s, 3); S(b, 6, 14+s, 3); S(b, 31, 15+s, 3); S(b, 32, 14+s, 3)

PLANS = {"quadruped": quadruped, "kitty": kitty, "bird": bird, "mouse": mouse,
         "hedgehog": hedgehog, "deer": deer, "boar": boar, "cow": cow,
         "monkey": monkey, "blob": blob, "serpent": serpent, "human": human, "ghost": ghost}

SPRITES = {
    "lamball":     ("quadruped", ["#ede0c8", "#d8c9ab", "#f2a0b5"], 0.55),
    "cattiva":     ("kitty",     ["#f2a0b5", "#e085a0", "#ffffff"], 0.3),
    "chikipi":     ("bird",      ["#f5f2ea", "#e8e0cc", "#e64533"], 0.25),
    "foxparks":    ("kitty",     ["#e8963c", "#c97e2a", "#ffd54f"], 0.3),
    "pengullet":   ("bird",      ["#4d9de0", "#2b5d8a", "#e8d44d"], 0),
    "penking":     ("bird",      ["#3f94c8", "#2b5d8a", "#ffd54f"], 0.15),
    "eikthyrdeer": ("deer",      ["#d4b96e", "#b8945a", "#8a6d4d"], 0),
    "lifmunk":     ("mouse",     ["#4caf50", "#3d9143", "#9acd32"], 0),
    "tanzee":      ("monkey",    ["#9acd32", "#7a9d2a", "#d4b96e"], 0.2),
    "sparkit":     ("mouse",     ["#e8d44d", "#c9b23a", "#ff9a3c"], 0.2),
    "jolthog":     ("hedgehog",  ["#e8e05c", "#c9bf45", "#8a6d4d"], 0.4),
    "dumud":       ("serpent",   ["#b8935f", "#96794d", "#8fd1a0"], 0),
    "depresso":    ("blob",      ["#6fa8d1", "#5a8db0", "#4d6f8a"], 0),
    "daedream":    ("ghost",     ["#c678dd", "#a45ec0", "#e08ee8"], 0.25),
    "mau":         ("kitty",     ["#a8b5c4", "#8a98a8", "#e8d44d"], 0),
    "rushoar":     ("boar",      ["#d1813c", "#a96a2f", "#f5eee0"], 0.3),
    "cremis":      ("kitty",     ["#f5eee0", "#d8d0be", "#e8963c"], 0.45),
    "mozzarina":   ("cow",       ["#ede0c8", "#c9b89e", "#e8d44d"], 0.2),
    "fuack":       ("bird",      ["#4dd0e1", "#35a8b8", "#e8d44d"], 0.2),
    "player":      ("human",     ["#d17b3c", "#4d9de0", "#e8c9a0"], 0),
    "syndicate_grunt":   ("human", ["#3a3a4a", "#2a2a35", "#e8c9a0"], 0),
    "syndicate_sweeper": ("human", ["#5a2e4a", "#3d1f33", "#e8c9a0"], 0),
}

def render_pal(spec_id):
    plan, colors, fluff = SPRITES[spec_id]
    ramps = [ramp(colors[0]), ramp(colors[1]), ramp(colors[2]), DARK, WHITE]
    for f in (0, 1):
        b = newbuf()
        PLANS[plan](b, f)
        img = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
        px = img.load()
        def at(x, y):
            return b[y][x] if 0 <= x < PW and 0 <= y < PH else 0
        for y in range(PH):
            for x in range(PW):
                c = at(x, y)
                if not c:
                    continue
                h = hash2(x * 7 + 3, y * 7 + 1, 31)
                op = not (at(x-1, y) and at(x+1, y) and at(x, y-1) and at(x, y+1))
                rp = ramps[c - 1]
                lf = (1 - y / PH) * 0.62 + (1 - x / PW) * 0.14 + (h - 0.5) * 0.16
                if op:
                    col = rp["out"]
                elif lf > 0.8:
                    col = rp["spec"]
                elif lf > 0.62:
                    col = rp["light"]
                elif lf < 0.26:
                    col = rp["shade"]
                else:
                    nearHi = 0.62 - lf < 0.09
                    nearLo = lf - 0.26 < 0.09
                    dither = ((x + y) % 2 == 0) and (nearHi or nearLo or h < fluff)
                    col = rp["light"] if (dither and nearHi) else (rp["shade"] if dither else rp["base"])
                px[x, y] = col + (255,)
        img.save(os.path.join(A, "pals", f"{spec_id}_f{f}.png"))

# =========================================================================
# TERRAIN ATLAS — 64x64 slots; ground diamond 64x32 in top half
# =========================================================================
TW, TH, WALL = 64, 32, 16
DIA = [(32, 0), (64, 16), (32, 32), (0, 16)]

def tile_img():
    return Image.new("RGBA", (TW, 64), (0, 0, 0, 0))

def dia_clip(img):
    mask = Image.new("L", (TW, 64), 0)
    ImageDraw.Draw(mask).polygon(DIA, fill=255)
    return mask

def fill_dia(img, base, vary, seed, dark_bottom=0.0):
    """Fill diamond with base color + per-pixel hash speckle."""
    px = img.load()
    b = hxc(base)
    for y in range(33):
        for x in range(TW):
            # point-in-diamond test
            dx = abs(x - 32) / 32.0
            top, bot = 16 * dx, 32 - 16 * dx
            if top <= y <= bot:
                h = hash2(x + seed * 13, y + seed * 7, seed)
                f = 1 + (h - 0.5) * vary
                # darken slightly toward bottom vertex (fake depth)
                dd = 1 - dark_bottom * (y / 32.0)
                px[x, y] = (int(b[0] * f * dd), int(b[1] * f * dd), int(b[2] * f * dd), 255)

def in_dia(x, y):
    dx = abs(x - 32) / 32.0
    return 16 * dx <= y <= 32 - 16 * dx

def speckle(img, colors, n, seed, size=1):
    px = img.load()
    for i in range(n):
        x = int(hash2(i, seed, 7) * 62) + 1
        y = int(hash2(seed, i, 13) * 30) + 1
        if in_dia(x, y):
            px[x, y] = hxc(colors[int(hash2(i, seed, 29) * len(colors))]) + (255,)
            if size > 1 and in_dia(x + 1, y):
                px[x + 1, y] = px[x, y]

def blades(img, n, seed, cols):
    px = img.load()
    for i in range(n):
        x = int(hash2(i, seed, 41) * 60) + 2
        y = int(hash2(seed, i, 43) * 28) + 2
        if in_dia(x, y):
            c = hxc(cols[int(hash2(i, 1, seed) * len(cols))])
            h = 1 + int(hash2(i, 3, seed) * 3)
            for k in range(h):
                if in_dia(x, y - k):
                    px[x, y - k] = c + (255,)

def make_grass(v):
    img = tile_img()
    bases = ["#69ad4a", "#5f9f44", "#74b857", "#66a848"]
    fill_dia(img, bases[v % 4], 0.12, 100 + v)
    blades(img, 14 + v * 3, 200 + v, ["#4e8a38", "#7fc463", "#589a3f"])
    speckle(img, ["#8ad06b", "#4a8034"], 8 + v * 2, 300 + v)
    return img

def make_tallgrass(v):
    img = make_grass(v % 4)
    blades(img, 30, 400 + v, ["#3f7a30", "#8fd070", "#68b054"])
    return img

def make_flower(v):
    img = make_grass(1)
    px = img.load()
    cols = ["#e08ee8", "#ff7d6e", "#ffd54f", "#ffffff", "#ff9ad5"]
    for i in range(7):
        x = int(hash2(i, v, 61) * 56) + 4
        y = int(hash2(v, i, 67) * 24) + 4
        if in_dia(x, y):
            c = hxc(cols[(i + v) % len(cols)])
            for dx, dy in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
                if in_dia(x + dx, y + dy):
                    px[x + dx, y + dy] = c + (255,)
            px[x, y] = (255, 240, 160, 255)
    return img

def make_sand(v):
    img = tile_img()
    fill_dia(img, ["#e8d193", "#e0c887"][v % 2], 0.07, 500 + v)
    speckle(img, ["#c9a86a", "#f4e6b4", "#b8946a"], 16, 600 + v)
    px = img.load()
    for i in range(3):  # ripples
        y0 = 8 + i * 8 + int(hash2(i, v, 71) * 3)
        for x in range(8, 56):
            yy = y0 + int(math.sin((x + i * 9) / 7.0) * 2)
            if in_dia(x, yy):
                px[x, yy] = hxc("#d4ba7e") + (255,)
    return img

def make_water(v):
    img = tile_img()
    px = img.load()
    for y in range(33):
        for x in range(TW):
            if in_dia(x, y):
                t = y / 32.0
                base = (61, 144, 205)
                deep = (33, 96, 150)
                c = tuple(int(base[i] * (1 - t) + deep[i] * t) for i in range(3))
                px[x, y] = c + (255,)
    speckle(img, ["#7fc4ee", "#a8dcf6"], 8, 700 + v)
    for i in range(2):  # wave strokes
        y0 = 8 + i * 10 + int(hash2(i, v, 73) * 4)
        for x in range(10, 54, 2):
            yy = y0 + int(math.sin((x + i * 11) / 9.0) * 2)
            if in_dia(x, yy) and in_dia(x + 1, yy):
                px[x, yy] = px[x + 1, yy] = hxc("#8fd0f0") + (220,)
    return img

def make_stonefield(v):
    img = tile_img()
    fill_dia(img, "#8a9096", 0.14, 800 + v)
    px = img.load()
    for i in range(5):  # slabs
        x = int(hash2(i, v, 81) * 52) + 6
        y = int(hash2(v, i, 83) * 22) + 5
        if in_dia(x, y):
            w = 3 + int(hash2(i, v, 87) * 5)
            for dx in range(w):
                if in_dia(x + dx, y):
                    px[x + dx, y] = hxc("#6e767e") + (255,)
                if in_dia(x + dx, y + 1):
                    px[x + dx, y + 1] = hxc("#9aa2aa") + (255,)
    return img

def make_dirt(v):
    img = tile_img()
    fill_dia(img, "#a98a5e", 0.12, 900 + v)
    speckle(img, ["#8a6d4d", "#c4a678", "#6e5238"], 14, 950 + v)
    return img

def make_farmland(v):
    img = tile_img()
    fill_dia(img, "#7a5c3e", 0.08, 1000 + v)
    px = img.load()
    for i in range(4):  # tilled rows along x axis
        y0 = 7 + i * 6
        for x in range(6, 58):
            yy = y0 + (x - 6) // 4 * 0  # straight rows
            if in_dia(x, yy):
                px[x, yy] = hxc("#5e462e") + (255,)
            if in_dia(x, yy + 1):
                px[x, yy + 1] = hxc("#8a6c4c") + (255,)
    return img

def wall_img(kind):
    """kind: 'sx' right-down face, 'sy' left-down, 'corner' both, 'stair_*' variants."""
    img = tile_img()
    px = img.load()
    faces = {"sx": [(64, 16), (32, 32)], "sy": [(0, 16), (32, 32)]}
    draw_faces = []
    if kind in ("sx", "corner", "stair_sx", "stair_corner"):
        draw_faces.append("sx")
    if kind in ("sy", "corner", "stair_sy", "stair_corner"):
        draw_faces.append("sy")
    stair = kind.startswith("stair")
    for f in draw_faces:
        (x1, y1), (x2, y2) = faces[f]
        for t in range(WALL):
            for k in range(33):
                x = x1 + (x2 - x1) * k / 32
                y = y1 + (y2 - y1) * k / 32 + t
                xi = int(x)
                if 0 <= xi < TW and 0 <= int(y) < 64:
                    h = hash2(xi + t * 3, int(y) * 5, 1200)
                    if stair:
                        # steps: horizontal treads every 3px
                        step = t // 3
                        inset = step * 4 if f == "sx" else step * -4
                        if f == "sx" and xi < 64 - step * 3 or f == "sy" and xi > step * 3 - 32:
                            base = hxc("#a08460")
                            cc = base if t % 3 else hxc("#c4a678")
                        else:
                            cc = hxc("#5a4c3c")
                    else:
                        v = 1 + (h - 0.5) * 0.18
                        base = hxc("#6e6250")
                        cc = tuple(min(255, int(c * v)) for c in base)
                        if t == 0:
                            cc = hxc("#94866c")  # top rim light
                        elif t in (5, 10) and h < 0.8:
                            cc = hxc("#57503f")  # strata lines
                    px[xi, int(y)] = cc + (255,)
    if kind == "corner" or kind == "stair_corner":
        for t in range(WALL):
            for dy in range(2):
                if 0 <= 32 + dy < 64 and 0 <= 30 + t < 64:
                    px[31 + dy, 32 + t] = hxc("#3c352b") + (255,)
    return img

def marker_img():
    img = tile_img()
    d = ImageDraw.Draw(img)
    d.line(DIA + [DIA[0]], fill=(255, 255, 255, 200), width=2)
    return img

# =========================================================================
# DECOR — y-sorted sprites, anchor bottom-center
# =========================================================================
def decor_img(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def tree_a():
    img = decor_img(64, 96)
    d = ImageDraw.Draw(img)
    d.rectangle([28, 62, 35, 90], fill=hxc("#6e5238") + (255,))
    d.rectangle([28, 62, 30, 90], fill=hxc("#8a6d4d") + (255,))
    layers = [(32, 18, 26, "#4faa50"), (32, 34, 30, "#3f9140"), (32, 50, 24, "#357a35")]
    for cx, cy, r, col in layers:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=hxc(col) + (255,))
    px = img.load()
    for i in range(140):  # leaf dither
        cx, cy, r, col = layers[int(hash2(i, 1, 1500) * 3)]
        x = int(cx - r + hash2(i, 2, 1501) * r * 2)
        y = int(cy - r + hash2(i, 3, 1502) * r * 2)
        if (x - cx) ** 2 + (y - cy) ** 2 <= r * r * 0.9 and 0 <= x < 64 and 0 <= y < 96:
            lt = hash2(i, 4, 1503)
            px[x, y] = hxc("#68c060" if lt > 0.75 else ("#2e6e2e" if lt < 0.25 else col)) + (255,)
    return img

def tree_b():
    img = decor_img(64, 96)
    d = ImageDraw.Draw(img)
    d.rectangle([29, 78, 34, 94], fill=hxc("#5e462e") + (255,))
    for i, (top, half, col) in enumerate([(6, 20, "#3f9140"), (28, 26, "#357a35"), (50, 30, "#2e6e2e")]):
        d.polygon([(32, top), (32 - half, top + 34), (32 + half, top + 34)], fill=hxc(col) + (255,))
    px = img.load()
    for i in range(80):
        top = [6, 28, 50][int(hash2(i, 1, 1600) * 3)]
        half = [20, 26, 30][int(hash2(i, 2, 1601) * 3)]
        x = int(32 - half + hash2(i, 3, 1602) * half * 2)
        y = int(top + hash2(i, 4, 1603) * 32)
        if 0 <= x < 64 and 0 <= y < 96 and px[x, y][3]:
            px[x, y] = hxc("#55aa55" if hash2(i, 5, 1604) > 0.6 else "#256428") + (255,)
    return img

def boulder(veins=None):
    img = decor_img(64, 40)
    d = ImageDraw.Draw(img)
    pts = [(10, 34), (8, 22), (18, 10), (34, 6), (50, 12), (56, 24), (54, 34)]
    d.polygon(pts, fill=hxc("#8a9096") + (255,))
    px = img.load()
    for i in range(90):
        x = int(8 + hash2(i, 1, 1700) * 48)
        y = int(6 + hash2(i, 2, 1701) * 28)
        if 0 <= x < 64 and 0 <= y < 40 and px[x, y][3]:
            lt = hash2(i, 3, 1702)
            if lt > 0.8:
                px[x, y] = hxc("#9aa2aa") + (255,)
            elif lt < 0.3:
                px[x, y] = hxc("#6e767e") + (255,)
    if veins:
        for i in range(9):
            x = int(12 + hash2(i, 1, 1710) * 40)
            y = int(10 + hash2(i, 2, 1711) * 24)
            if 0 <= x < 64 and 0 <= y < 40 and px[x, y][3]:
                px[x, y] = hxc(veins) + (255,)
                if x + 1 < 64 and px[x + 1, y][3]:
                    px[x + 1, y] = hxc(veins) + (255,)
    return img

def berry_bush():
    img = decor_img(64, 56)
    d = ImageDraw.Draw(img)
    d.ellipse([10, 14, 54, 48], fill=hxc("#3f9140") + (255,))
    px = img.load()
    for i in range(70):
        x = int(10 + hash2(i, 1, 1800) * 44)
        y = int(14 + hash2(i, 2, 1801) * 34)
        if (x - 32) ** 2 / 484 + (y - 31) ** 2 / 289 <= 1:
            px[x, y] = hxc("#55aa55" if hash2(i, 3, 1802) > 0.5 else "#357a35") + (255,)
    for i in range(12):
        x = int(14 + hash2(i, 1, 1810) * 36)
        y = int(18 + hash2(i, 2, 1811) * 26)
        if (x - 32) ** 2 / 484 + (y - 31) ** 2 / 289 <= 1:
            px[x, y] = hxc("#e64533") + (255,)
            px[x + 1, y] = hxc("#f47a6e") + (255,)
    return img

def stump():
    img = decor_img(48, 30)
    d = ImageDraw.Draw(img)
    d.rectangle([16, 10, 32, 24], fill=hxc("#6e5238") + (255,))
    d.ellipse([14, 4, 34, 14], fill=hxc("#a98a5e") + (255,))
    d.ellipse([17, 6, 31, 12], fill=hxc("#8a6d4d") + (255,))
    return img

# =========================================================================
# STRUCTURES — iso boxes with per-structure accents
# =========================================================================
def iso_box(img, ox, oy, w_tiles, h_tiles, hpx, top, side_l, side_r):
    """Draw an iso box: top diamond of w×h tiles + two faces. (ox,oy)=top vertex."""
    d = ImageDraw.Draw(img)
    ax, ay = ox + w_tiles * 32, oy + w_tiles * 16          # +x corner (right)
    bx, by = ox + (w_tiles - h_tiles) * 32, oy + (w_tiles + h_tiles) * 16  # bottom
    cx2, cy2 = ox - h_tiles * 32, oy + h_tiles * 16        # +y corner (left)
    c = lambda v: (hxc(v) if isinstance(v, str) else v) + (255,)
    d.polygon([(ox, oy), (ax, ay), (bx, by), (cx2, cy2)], fill=c(top))
    d.polygon([(cx2, cy2), (bx, by), (bx, by + hpx), (cx2, cy2 + hpx)], fill=c(side_l))
    d.polygon([(ax, ay), (bx, by), (bx, by + hpx), (ax, ay + hpx)], fill=c(side_r))

def struct_img(w_tiles, h_tiles, hpx, top, sl, sr, pad=8):
    wpx = (w_tiles + h_tiles) * 32 + pad * 2
    hpx_total = (w_tiles + h_tiles) * 16 + hpx + pad * 2 + 30
    img = Image.new("RGBA", (wpx, hpx_total), (0, 0, 0, 0))
    ox = h_tiles * 32 + pad
    oy = pad + 30
    iso_box(img, ox, oy, w_tiles, h_tiles, hpx, top, sl, sr)
    return img, d_corner(img, wpx)

def d_corner(img, w):
    return ImageDraw.Draw(img)

def shade3(hexcol):
    h, s, l = hsl(hexcol)
    return (rgb(h, s, min(1, l * 1.15)), rgb(h - 8, s, l * 0.72), rgb(h - 16, s, l * 0.55))

def make_structure(sid, color, w, h):
    top, sl, sr = shade3(color)
    hpx = 26 if sid not in ("ranch", "berry_farm", "wheat_farm") else 8
    img, d = struct_img(w, h, hpx, top, sl, sr)
    W, H = img.size
    if sid == "palbox":
        d.ellipse([W//2 - 13, 8, W//2 + 13, 34], fill=hxc("#4dd0e1") + (255,))
        d.ellipse([W//2 - 9, 12, W//2 + 3, 22], fill=hxc("#aef0fa") + (255,))
        d.rectangle([W//2 - 8, 34, W//2 + 8, 44], fill=hxc("#2b5d8a") + (255,))
    elif sid == "campfire":
        d.polygon([(W//2 - 14, 44), (W//2 + 14, 44), (W//2, 18)], fill=hxc("#e8963c") + (255,))
        d.polygon([(W//2 - 8, 42), (W//2 + 8, 42), (W//2, 26)], fill=hxc("#ffd54f") + (255,))
        for dx in (-12, -4, 4, 12):
            d.ellipse([W//2 + dx - 4, 44, W//2 + dx + 4, 50], fill=hxc("#8a9096") + (255,))
    elif sid == "furnace":
        d.rectangle([W//2 - 10, 40, W//2 + 10, 52], fill=hxc("#3c352b") + (255,))
        d.rectangle([W//2 - 7, 43, W//2 + 7, 50], fill=hxc("#e86c3c") + (255,))
    elif sid == "generator":
        d.polygon([(W//2 + 2, 14), (W//2 - 8, 30), (W//2, 30), (W//2 - 2, 44),
                   (W//2 + 10, 26), (W//2 + 2, 26)], fill=hxc("#ffe98a") + (255,))
    elif sid == "chest":
        d.line([(W//2 - 20, 34), (W//2 + 20, 34)], fill=hxc("#3c2f22") + (255,), width=3)
        d.rectangle([W//2 - 3, 30, W//2 + 3, 38], fill=hxc("#e8d44d") + (255,))
    elif sid == "pal_bed" or sid == "straw_bed":
        d.polygon([(W//2 - 30, 30), (W//2 + 26, 30), (W//2 + 32, 40), (W//2 - 24, 40)],
                  fill=hxc("#f2e6ae") + (255,))
        d.line([(W//2 - 28, 36), (W//2 + 28, 36)], fill=hxc("#c4a678") + (255,), width=2)
    elif sid in ("berry_farm", "wheat_farm"):
        crop = "#e64533" if sid == "berry_farm" else "#d8c96e"
        for i in range(4):
            y = 34 + i * 6
            for x in range(W//2 - 38, W//2 + 38, 8):
                d.line([(x, y + 4), (x, y - 2)], fill=hxc("#4faa50") + (255,), width=2)
                d.ellipse([x - 2, y - 4, x + 2, y], fill=hxc(crop) + (255,))
    elif sid == "ranch":
        for i in range(10):
            x = 12 + i * (W - 24) / 9
            d.rectangle([int(x) - 1, 20, int(x) + 1, 46], fill=hxc("#8a6d4d") + (255,))
        d.line([(10, 28), (W - 10, 28)], fill=hxc("#a98a5e") + (255,), width=2)
        d.line([(10, 40), (W - 10, 40)], fill=hxc("#a98a5e") + (255,), width=2)
    elif sid == "logging_site":
        for i in range(3):
            d.rectangle([W//2 - 24, 28 + i * 8, W//2 + 24, 34 + i * 8], fill=hxc("#8a6d4d") + (255,))
            d.ellipse([W//2 - 28, 27 + i * 8, W//2 - 20, 35 + i * 8], fill=hxc("#a98a5e") + (255,))
    elif sid in ("stone_pit", "ore_mine"):
        d.ellipse([W//2 - 26, 26, W//2 + 26, 46], fill=hxc("#3c352b") + (255,))
        vein = "#e8d44d" if sid == "ore_mine" else "#9aa2aa"
        for i in range(6):
            x = W//2 - 20 + i * 7
            d.ellipse([x - 2, 32 + (i % 2) * 3, x + 3, 38 + (i % 2) * 3], fill=hxc(vein) + (255,))
    elif sid == "crusher" or sid == "mill":
        d.ellipse([W//2 - 12, 14, W//2 + 12, 38], fill=hxc("#4d9de0") + (255,))
        d.ellipse([W//2 - 5, 21, W//2 + 5, 31], fill=hxc("#aef0fa") + (255,))
    elif sid == "torch":
        d.rectangle([W//2 - 2, 20, W//2 + 2, 46], fill=hxc("#6e5238") + (255,))
        d.polygon([(W//2 - 7, 20), (W//2 + 7, 20), (W//2, 6)], fill=hxc("#e8963c") + (255,))
        d.polygon([(W//2 - 4, 18), (W//2 + 4, 18), (W//2, 10)], fill=hxc("#ffd54f") + (255,))
    elif sid == "feed_box":
        d.polygon([(W//2 - 18, 32), (W//2 + 18, 32), (W//2 + 14, 42), (W//2 - 14, 42)],
                  fill=hxc("#5e462e") + (255,))
        d.ellipse([W//2 - 12, 30, W//2 + 12, 36], fill=hxc("#e64533") + (255,))
    elif sid == "gathering_site":
        for i in range(5):
            x = W//2 - 24 + i * 12
            d.ellipse([x - 4, 26, x + 4, 34], fill=hxc("#8a6d4d") + (255,))
            d.ellipse([x - 5, 20, x + 5, 28], fill=hxc("#c46a52") + (255,))
    elif sid == "pharmacy":
        d.rectangle([W//2 - 4, 12, W//2 + 4, 34], fill=hxc("#e8f0f2") + (255,))
        d.rectangle([W//2 - 11, 19, W//2 + 11, 27], fill=hxc("#e8f0f2") + (255,))
    elif sid == "cooler":
        d.rectangle([W//2 - 14, 16, W//2 + 14, 40], fill=hxc("#e8f4fa") + (255,))
        d.line([(W//2 - 14, 24), (W//2 + 14, 24)], fill=hxc("#4d9de0") + (255,), width=2)
        for (dx, dy) in ((-6, 30), (2, 33), (8, 29)):
            d.ellipse([W//2 + dx - 2, dy, W//2 + dx + 2, dy + 4], fill=hxc("#aef0fa") + (255,))
    elif sid == "pal_condenser":
        # two joining cylinders + star spark between them
        d.rectangle([8, 16, 26, 44], fill=hxc("#5a448f") + (255,))
        d.rectangle([W - 26, 16, W - 8, 44], fill=hxc("#5a448f") + (255,))
        d.rectangle([W//2 - 3, 14, W//2 + 3, 44], fill=hxc("#b09ae0") + (255,))
        for dx, dy in [(0, -6), (0, 6), (-6, 0), (6, 0)]:
            d.rectangle([W//2 + dx - 1, 10 + dy - 1, W//2 + dx + 1, 10 + dy + 1],
                        fill=hxc("#ffe89a") + (255,))
    elif sid == "oil_extractor":
        d.rectangle([W//2 - 4, 12, W//2 + 4, 40], fill=hxc("#3c352b") + (255,))
        d.polygon([(W//2 - 14, 20), (W//2 + 12, 12), (W//2 + 16, 18), (W//2 - 10, 26)],
                  fill=hxc("#2f2a24") + (255,))
        d.ellipse([W//2 + 12, 16, W//2 + 20, 24], fill=hxc("#a45ec0") + (255,))
    elif sid == "incubator":
        # glass dome over a glowing egg on a padded base
        d.rectangle([W//2 - 20, 40, W//2 + 20, 48], fill=hxc("#5e462e") + (255,))
        d.ellipse([W//2 - 10, 26, W//2 + 10, 44], fill=hxc("#f5e6c8") + (255,))
        d.ellipse([W//2 - 14, 14, W//2 + 14, 42], outline=hxc("#aef0fa") + (255,), width=3)
        d.ellipse([W//2 - 4, 30, W//2 + 4, 40], fill=hxc("#ffd76e") + (255,))
    elif sid == "wooden_wall":
        # vertical planks + cross brace
        for i in range(5):
            x = W//2 - 20 + i * 9
            d.rectangle([x, 14, x + 7, 46], fill=hxc("#8a6d4d") + (255,))
            d.line([(x, 14), (x, 46)], fill=hxc("#5e462e") + (255,))
        d.line([(W//2 - 22, 24), (W//2 + 22, 24)], fill=hxc("#a98a5e") + (255,), width=3)
        d.line([(W//2 - 22, 38), (W//2 + 22, 38)], fill=hxc("#a98a5e") + (255,), width=3)
    elif sid == "spikes":
        # flat board bristling with sharpened stakes
        d.rectangle([W//2 - 22, 42, W//2 + 22, 48], fill=hxc("#5e462e") + (255,))
        for i in range(4):
            x = W//2 - 16 + i * 11
            d.polygon([(x - 4, 44), (x + 4, 44), (x, 24)], fill=hxc("#c4a678") + (255,))
            d.line([(x, 30), (x, 24)], fill=hxc("#ede0c8") + (255,))
    elif sid == "hot_spring":
        # stone-rimmed pool with steam wisps
        d.ellipse([W//2 - 22, 30, W//2 + 22, 48], fill=hxc("#6b6f72") + (255,))
        d.ellipse([W//2 - 18, 32, W//2 + 18, 46], fill=hxc("#7ec8e3") + (255,))
        d.ellipse([W//2 - 8, 34, W//2 + 8, 44], fill=hxc("#a8dff0") + (255,))
        for i, x in enumerate((-10, 0, 10)):
            d.arc([W//2 + x - 5, 10 + i * 2, W//2 + x + 5, 26 + i * 2], 200, 340,
                  fill=hxc("#d8f4fa") + (255,), width=2)
    elif sid == "monitoring_stand":
        # watchtower post with a stern flag
        d.rectangle([W//2 - 3, 16, W//2 + 3, 48], fill=hxc("#5e462e") + (255,))
        d.polygon([(W//2 + 3, 16), (W//2 + 18, 20), (W//2 + 3, 26)], fill=hxc("#d06a6a") + (255,))
        d.rectangle([W//2 - 10, 44, W//2 + 10, 50], fill=hxc("#8a6d4d") + (255,))
        d.ellipse([W//2 - 4, 30, W//2 + 4, 38], fill=hxc("#ede0c8") + (255,))
    elif sid == "watch_tower":
        # stilted perch topped by a bolt thrower
        for dx in (-12, 8):
            d.line([(W//2 + dx, 48), (W//2 + dx + 4, 30)], fill=hxc("#5e462e") + (255,), width=2)
        d.rectangle([W//2 - 14, 24, W//2 + 14, 30], fill=hxc("#8a6d4d") + (255,))
        d.polygon([(W//2 - 16, 24), (W//2, 12), (W//2 + 16, 24)], fill=hxc("#a0622d") + (255,))
        d.line([(W//2 - 8, 21), (W//2 + 8, 21)], fill=hxc("#ede0c8") + (255,), width=2)
        d.line([(W//2, 21), (W//2, 27)], fill=hxc("#ede0c8") + (255,), width=2)
    elif sid == "sphere_factory":
        # conveyor bench rolling a fresh sphere — Palworld's assembly line
        d.rectangle([W//2 - 22, 30, W//2 + 22, 40], fill=hxc("#5e462e") + (255,))
        for i in range(4):
            x = W//2 - 18 + i * 11
            d.ellipse([x, 32, x + 7, 38], outline=hxc("#8a6d4d") + (255,), width=2)
        d.ellipse([W//2 - 8, 14, W//2 + 8, 30], fill=hxc("#e05050") + (255,))
        d.rectangle([W//2 - 8, 21, W//2 + 8, 24], fill=hxc("#ede0c8") + (255,))
        d.ellipse([W//2 - 4, 15, W//2 - 1, 18], fill=hxc("#f8f4f0") + (255,))
    elif sid == "sphere_factory_2":
        # the bigger belt — a twin-lane line rolling a giga sphere
        d.rectangle([W//2 - 22, 30, W//2 + 22, 40], fill=hxc("#5e462e") + (255,))
        for i in range(4):
            x = W//2 - 18 + i * 11
            d.ellipse([x, 32, x + 7, 38], outline=hxc("#8a6d4d") + (255,), width=2)
        d.ellipse([W//2 - 11, 11, W//2 + 11, 31], fill=hxc("#3f7fd8") + (255,))
        d.rectangle([W//2 - 11, 20, W//2 + 11, 24], fill=hxc("#ede0c8") + (255,))
        d.ellipse([W//2 - 6, 13, W//2 - 2, 17], fill=hxc("#f8f4f0") + (255,))
    elif sid == "compost_bin":
        # a squat lidded barrel with a sprout poking through the mulch
        d.rectangle([W//2 - 14, 26, W//2 + 14, 44], fill=hxc("#8a6d4d") + (255,))
        d.rectangle([W//2 - 16, 22, W//2 + 16, 27], fill=hxc("#5e462e") + (255,))
        d.ellipse([W//2 - 10, 24, W//2 + 10, 30], fill=hxc("#6a5a3a") + (255,))
        d.line([(W//2, 26), (W//2, 16)], fill=hxc("#7a9a4a") + (255,), width=2)
        d.ellipse([W//2 - 5, 14, W//2 - 1, 18], fill=hxc("#9acd32") + (255,))
        d.ellipse([W//2 + 1, 13, W//2 + 6, 17], fill=hxc("#9acd32") + (255,))
    elif sid == "training_dummy":
        # straw man on a post — crossbar arms, battered head, wood base
        d.rectangle([W//2 - 8, 40, W//2 + 8, 44], fill=hxc("#5e462e") + (255,))
        d.line([(W//2, 14), (W//2, 40)], fill=hxc("#8a6d4d") + (255,), width=3)
        d.line([(W//2 - 10, 24), (W//2 + 10, 24)], fill=hxc("#8a6d4d") + (255,), width=3)
        d.ellipse([W//2 - 6, 12, W//2 + 6, 24], fill=hxc("#d8b84a") + (255,))
        d.rectangle([W//2 - 7, 20, W//2 + 7, 23], fill=hxc("#a08050") + (255,))
        d.line([(W//2 - 3, 15), (W//2 + 3, 19)], fill=hxc("#8a6d4d") + (255,), width=1)
    elif sid == "guard_post":
        # a raised watch platform — posts, slats, a little pennant
        for px2 in (-10, 10):
            d.line([(W//2 + px2, 26), (W//2 + px2, 44)], fill=hxc("#5e462e") + (255,), width=3)
        d.rectangle([W//2 - 14, 24, W//2 + 14, 30], fill=hxc("#8a6d4d") + (255,))
        d.rectangle([W//2 - 14, 30, W//2 + 14, 32], fill=hxc("#5e462e") + (255,))
        d.line([(W//2 + 12, 8), (W//2 + 12, 26)], fill=hxc("#5e462e") + (255,), width=2)
        d.polygon([(W//2 + 12, 8), (W//2 + 22, 11), (W//2 + 12, 15)], fill=hxc("#b06a50") + (255,))
    elif sid == "training_hall":
        # a sparring dojo — wooden deck, corner posts, crossed practice blades
        d.rectangle([W//2 - 26, 34, W//2 + 26, 46], fill=hxc("#8a6a4a") + (255,))
        for px3 in range(-26, 30, 8):
            d.line([(W//2 + px3, 34), (W//2 + px3, 46)], fill=hxc("#6b4f36") + (255,), width=1)
        for px4 in (-24, 24):
            d.line([(W//2 + px4, 16), (W//2 + px4, 34)], fill=hxc("#5e462e") + (255,), width=3)
        d.line([(W//2 - 24, 16), (W//2 + 24, 16)], fill=hxc("#5e462e") + (255,), width=3)
        d.line([(W//2 - 8, 20), (W//2 + 8, 32)], fill=hxc("#c9cdd2") + (255,), width=2)
        d.line([(W//2 + 8, 20), (W//2 - 8, 32)], fill=hxc("#c9cdd2") + (255,), width=2)
        d.ellipse([W//2 - 3, 24, W//2 + 3, 30], outline=hxc("#d8b84a") + (255,), width=2)
    elif sid == "sparring_ring":
        # a roped-off pit — corner posts, two rope lines, scuffed sand
        d.rectangle([W//2 - 24, 26, W//2 + 24, 44], fill=hxc("#c9b08a") + (255,))
        for px5 in (-24, 24):
            for py5 in (26, 44):
                d.ellipse([W//2 + px5 - 3, py5 - 3, W//2 + px5 + 3, py5 + 3], fill=hxc("#5e462e") + (255,))
        for ry in (30, 40):
            d.line([(W//2 - 24, ry), (W//2 + 24, ry)], fill=hxc("#a87848") + (255,), width=2)
        d.line([(W//2 - 6, 34), (W//2 + 6, 38)], fill=hxc("#8a6d4d") + (255,), width=2)
        d.line([(W//2 + 6, 34), (W//2 - 6, 38)], fill=hxc("#8a6d4d") + (255,), width=2)
    elif sid == "notice_board":
        # a pitch board on a post — pinned slips at odd angles
        d.line([(W//2, 30), (W//2, 44)], fill=hxc("#5e462e") + (255,), width=3)
        d.rectangle([W//2 - 13, 14, W//2 + 13, 30], fill=hxc("#8a6d4d") + (255,))
        d.rectangle([W//2 - 13, 14, W//2 + 13, 16], fill=hxc("#5e462e") + (255,))
        for sx in (-8, -1, 6):
            d.rectangle([W//2 + sx - 2, 19 + (sx % 3), W//2 + sx + 2, 26 + (sx % 3)], fill=hxc("#e8dcc0") + (255,))
        d.rectangle([W//2 - 13, 28, W//2 + 13, 30], fill=hxc("#5e462e") + (255,))
    elif sid == "fossil_bed":
        # old bones heaped in the dirt — a skull and scattered ribs
        d.ellipse([W//2 - 13, 30, W//2 + 13, 44], fill=hxc("#7a6a4e") + (255,))
        d.ellipse([W//2 - 7, 16, W//2 + 7, 30], fill=hxc("#d8ccb0") + (255,))
        d.rectangle([W//2 - 3, 20, W//2 - 1, 23], fill=hxc("#4a3c28") + (255,))
        d.rectangle([W//2 + 1, 20, W//2 + 3, 23], fill=hxc("#4a3c28") + (255,))
        for rx2 in (-9, -3, 4, 9):
            d.line([(W//2 + rx2, 34), (W//2 + rx2 + 3, 30)], fill=hxc("#d8ccb0") + (255,), width=2)
    elif sid == "pal_gacha":
        # brass capsule machine — glass dome of eggs over a coin slot
        d.rectangle([W//2 - 10, 28, W//2 + 10, 44], fill=hxc("#a87830") + (255,))
        d.rectangle([W//2 - 10, 28, W//2 + 10, 30], fill=hxc("#e8b830") + (255,))
        d.rectangle([W//2 - 2, 34, W//2 + 2, 38], fill=hxc("#3a2a18") + (255,))
        d.ellipse([W//2 - 9, 12, W//2 + 9, 28], fill=hxc("#cfe8f0") + (255,))
        for ex, ey in ((-4, 20), (3, 18), (0, 24)):
            d.ellipse([W//2 + ex - 2, ey - 2, W//2 + ex + 2, ey + 2], fill=hxc("#e8f0f2") + (255,))
        d.rectangle([W//2 - 10, 42, W//2 + 10, 44], fill=hxc("#8a6a30") + (255,))
    elif sid == "snare_trap":
        # leaf litter over steel jaws — the trap hides until it bites
        d.ellipse([W//2 - 14, 30, W//2 + 14, 42], fill=hxc("#7a8a4a") + (255,))
        d.polygon([(W//2 - 10, 36), (W//2 - 3, 30), (W//2 - 1, 36)], fill=hxc("#8a7a5a") + (255,))
        d.polygon([(W//2 + 10, 36), (W//2 + 3, 30), (W//2 + 1, 36)], fill=hxc("#8a7a5a") + (255,))
        for tx6 in range(-8, 9, 4):
            d.polygon([(W//2 + tx6, 40), (W//2 + tx6 + 2, 44), (W//2 + tx6 + 4, 40)], fill=hxc("#c9cdd2") + (255,))
    elif sid == "war_banner":
        # a tall pole with a dyed war banner and a spear-tip crown
        d.line([(W//2, 6), (W//2, 44)], fill=hxc("#5e462e") + (255,), width=3)
        d.polygon([(W//2, 2), (W//2 + 4, 8), (W//2, 12), (W//2 - 4, 8)], fill=hxc("#c9cdd2") + (255,))
        d.polygon([(W//2 + 2, 10), (W//2 + 20, 13), (W//2 + 20, 24), (W//2 + 2, 21)], fill=hxc("#b84a3a") + (255,))
        d.line([(W//2 + 6, 12), (W//2 + 6, 21)], fill=hxc("#d8b84a") + (255,), width=2)
        d.rectangle([W//2 - 5, 44, W//2 + 5, 47], fill=hxc("#6b6f72") + (255,))
    elif sid == "spyglass":
        # a lookout platform — timber legs, a deck, a brass spyglass on a post
        for px6 in (-9, 9):
            d.line([(W//2 + px6, 24), (W//2 + px6, 44)], fill=hxc("#5e462e") + (255,), width=3)
        d.rectangle([W//2 - 13, 22, W//2 + 13, 27], fill=hxc("#8a6d4d") + (255,))
        d.line([(W//2, 10), (W//2, 22)], fill=hxc("#5e462e") + (255,), width=2)
        d.ellipse([W//2 - 7, 5, W//2 + 7, 13], outline=hxc("#d8b84a") + (255,), width=2)
        d.ellipse([W//2 - 4, 7, W//2 + 4, 11], fill=hxc("#7a9ab8") + (255,))
    elif sid == "well":
        # a stone ring over a dark shaft, timber A-frame and a little bucket
        d.ellipse([W//2 - 13, 26, W//2 + 13, 44], fill=hxc("#6b6f72") + (255,))
        d.ellipse([W//2 - 9, 29, W//2 + 9, 41], fill=hxc("#20262e") + (255,))
        for px7 in (-10, 10):
            d.line([(W//2 + px7, 8), (W//2 + px7, 30)], fill=hxc("#5e462e") + (255,), width=2)
        d.line([(W//2 - 12, 8), (W//2 + 12, 8)], fill=hxc("#5e462e") + (255,), width=3)
        d.line([(W//2, 8), (W//2, 22)], fill=hxc("#8a6d4d") + (255,), width=1)
        d.rectangle([W//2 - 3, 22, W//2 + 3, 27], fill=hxc("#8a6d4d") + (255,))
    elif sid == "lightning_rod":
        # a copper finger on a stone foot, forked tip catching the sky
        d.polygon([(W//2 - 10, 44), (W//2 + 10, 44), (W//2 + 6, 38), (W//2 - 6, 38)], fill=hxc("#6b6f72") + (255,))
        d.line([(W//2, 38), (W//2, 12)], fill=hxc("#c07a3a") + (255,), width=3)
        d.line([(W//2, 12), (W//2 - 5, 6)], fill=hxc("#f0e060") + (255,), width=2)
        d.line([(W//2, 12), (W//2 + 5, 6)], fill=hxc("#f0e060") + (255,), width=2)
        d.line([(W//2, 12), (W//2, 4)], fill=hxc("#f0e060") + (255,), width=2)
    elif sid == "pal_cage":
        # iron-bar cage with a lockplate — grey bars on a dark frame
        d.rectangle([W//2 - 12, 10, W//2 + 12, 44], outline=hxc("#3a4450") + (255,), width=2)
        for bx9 in (-8, -4, 0, 4, 8):
            d.line([(W//2 + bx9, 11), (W//2 + bx9, 43)], fill=hxc("#6a7a8a") + (255,), width=2)
        d.rectangle([W//2 - 3, 24, W//2 + 3, 30], fill=hxc("#d8b84a") + (255,))
    elif sid == "weather_shrine":
        # stone altar with a floating paldium crystal and swirling wind lines
        d.rectangle([W//2 - 12, 36, W//2 + 12, 44], fill=hxc("#6b6f72") + (255,))
        d.rectangle([W//2 - 8, 30, W//2 + 8, 36], fill=hxc("#8b8f92") + (255,))
        d.polygon([(W//2, 12), (W//2 + 7, 22), (W//2, 30), (W//2 - 7, 22)], fill=hxc("#4dd0e1") + (255,))
        d.arc([W//2 - 14, 8, W//2 - 6, 16], 0, 270, fill=hxc("#7fb8d8") + (255,), width=1)
        d.arc([W//2 + 6, 14, W//2 + 15, 22], 0, 270, fill=hxc("#7fb8d8") + (255,), width=1)
    elif sid == "apiary":
        # a domed bee skep — straw rings, little door, drifting bees
        d.ellipse([W//2 - 13, 22, W//2 + 13, 44], fill=hxc("#d8b830") + (255,))
        for ry in (28, 33, 38):
            d.arc([W//2 - 13, ry - 6, W//2 + 13, ry + 6], 0, 180, fill=hxc("#a08030") + (255,), width=2)
        d.ellipse([W//2 - 4, 36, W//2 + 4, 42], fill=hxc("#4a3a20") + (255,))
        d.ellipse([W//2 + 12, 16, W//2 + 15, 19], fill=hxc("#3a3a3a") + (255,))
        d.ellipse([W//2 - 16, 12, W//2 - 13, 15], fill=hxc("#3a3a3a") + (255,))
    elif sid == "fish_trap":
        # woven weir box over lapping water — stakes, net, a silver catch
        d.rectangle([W//2 - 16, 30, W//2 + 16, 44], fill=hxc("#3a6ea8") + (255,))
        for i in range(3):
            d.arc([W//2 - 18 + i * 8, 34, W//2 - 10 + i * 8, 42], 0, 180, fill=hxc("#7fc8f8") + (255,), width=1)
        for sx in range(3):
            d.line([(W//2 - 12 + sx * 12, 14), (W//2 - 12 + sx * 12, 32)], fill=hxc("#8a6d4d") + (255,), width=2)
        d.line([(W//2 - 14, 20), (W//2 + 14, 20)], fill=hxc("#5e462e") + (255,), width=2)
        d.line([(W//2 - 14, 27), (W//2 + 14, 27)], fill=hxc("#5e462e") + (255,), width=2)
        d.ellipse([W//2 - 5, 28, W//2 + 5, 33], fill=hxc("#9ac8e8") + (255,))
    elif sid == "expedition_post":
        # rally flag over a supply crate — Palworld's dispatch camp
        d.rectangle([W//2 - 20, 34, W//2 - 6, 44], fill=hxc("#8a6d4d") + (255,))
        d.rectangle([W//2 - 20, 38, W//2 - 6, 40], fill=hxc("#5e462e") + (255,))
        d.line([(W//2 + 6, 46), (W//2 + 6, 12)], fill=hxc("#5e462e") + (255,), width=3)
        d.polygon([(W//2 + 6, 12), (W//2 + 6, 24), (W//2 + 24, 18)],
                  fill=hxc("#e05050") + (255,))
        d.ellipse([W//2 + 4, 10, W//2 + 8, 14], fill=hxc("#ede0c8") + (255,))
    elif sid == "waypoint":
        # standing stone with a glowing paldium core
        d.polygon([(W//2 - 10, 48), (W//2 + 10, 48), (W//2 + 7, 16), (W//2 - 7, 16)],
                  fill=hxc("#6b6f72") + (255,))
        d.polygon([(W//2 - 4, 44), (W//2 + 4, 44), (W//2 + 3, 20), (W//2 - 3, 20)],
                  fill=hxc("#7fc8f8") + (255,))
        d.ellipse([W//2 - 3, 26, W//2 + 3, 34], fill=hxc("#d8f4fa") + (255,))
        for i in range(3):
            d.arc([W//2 - 14 + i * 4, 20 + i * 3, W//2 + 14 - i * 4, 40 - i * 2],
                  300, 240, fill=hxc("#7fc8f8") + (180,), width=1)
    elif sid == "workbench":
        for dx in (-20, 16):
            d.rectangle([W//2 + dx, 38, W//2 + dx + 5, 52], fill=hxc("#5e462e") + (255,))
        d.rectangle([W//2 - 12, 18, W//2 - 4, 28], fill=hxc("#7f8c8d") + (255,))
        d.rectangle([W//2 + 2, 16, W//2 + 10, 26], fill=hxc("#a98a5e") + (255,))
    img.save(os.path.join(A, "structures", f"{sid}.png"))
    return img

STRUCT_DEFS = {  # id: (color, w, h) — mirrors STRUCTURES in structures.gd
    "palbox": ("#4dd0e1", 2, 2), "pal_bed": ("#ede0c8", 2, 1),
    "feed_box": ("#b8a468", 1, 1), "campfire": ("#e8963c", 1, 1),
    "workbench": ("#7f8c8d", 2, 1), "logging_site": ("#4d7d47", 2, 2),
    "stone_pit": ("#6b6f72", 2, 2), "ore_mine": ("#a0622d", 2, 2),
    "crusher": ("#4d9de0", 2, 2), "furnace": ("#e8963c", 2, 2),
    "mill": ("#7f8c8d", 2, 2), "berry_farm": ("#e64533", 3, 2),
    "wheat_farm": ("#b8a468", 3, 2), "ranch": ("#8a6d4d", 4, 3),
    "chest": ("#8a6d4d", 1, 1), "generator": ("#e8d44d", 2, 2),
    "torch": ("#e8963c", 1, 1), "straw_bed": ("#b8a468", 2, 1),
    "gathering_site": ("#7d9a4a", 2, 2), "pharmacy": ("#8fd0a0", 2, 1),
    "cooler": ("#a8dff0", 1, 1), "oil_extractor": ("#4d565c", 2, 2),
    "pal_condenser": ("#7a5ac9", 2, 1), "incubator": ("#f2a0b5", 2, 2),
    "wooden_wall": ("#8a6d4d", 1, 1), "spikes": ("#a98a5e", 1, 1),
    "hot_spring": ("#7ec8e3", 2, 2),
    "monitoring_stand": ("#d06a6a", 1, 1),
    "waypoint": ("#7fc8f8", 1, 1), "watch_tower": ("#c9a86a", 1, 1),
    "sphere_factory": ("#4dd0e1", 2, 1),
    "sphere_factory_2": ("#4dd0e1", 2, 1),
    "compost_bin": ("#7a9a4a", 1, 1),
    "fish_trap": ("#5a8ac0", 1, 1),
    "apiary": ("#d8b830", 1, 1),
    "weather_shrine": ("#7fb8d8", 1, 1),
    "guard_post": ("#b06a50", 1, 1),
    "training_hall": ("#8a6a4a", 2, 2),
    "sparring_ring": ("#a87848", 2, 2),
    "notice_board": ("#c9a15a", 1, 1),
    "snare_trap": ("#8a7a5a", 1, 1),
    "pal_gacha": ("#e8b830", 1, 1),
    "fossil_bed": ("#c8b890", 1, 1),
    "war_banner": ("#b84a3a", 1, 1),
    "spyglass": ("#7a9ab8", 1, 1),
    "well": ("#6a8ab0", 1, 1),
    "lightning_rod": ("#d8c04a", 1, 1),
    "pal_cage": ("#6a7a8a", 1, 1),
    "training_dummy": ("#a08050", 1, 1),
    "expedition_post": ("#c9a15a", 2, 1),
}

# =========================================================================
# MISC
# =========================================================================
def shadow():
    img = Image.new("RGBA", (56, 20), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([2, 3, 54, 17], fill=(0, 0, 0, 90))
    img.save(os.path.join(A, "shadow.png"))

def element_orbs():
    cols = {"neutral": "#c8d3d5", "fire": "#e8963c", "water": "#4d9de0",
            "grass": "#4caf50", "electric": "#e8d44d", "ice": "#a8dff0",
            "ground": "#b8935f", "dark": "#a45ec0", "dragon": "#4d6fd1"}
    img = Image.new("RGBA", (9 * 16, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i, (el, col) in enumerate(cols.items()):
        cx = i * 16 + 8
        d.ellipse([cx - 5, 3, cx + 5, 13], fill=hxc(col) + (255,))
        d.ellipse([cx - 5, 11, cx + 5, 13], fill=rgb(hsl(col)[0], hsl(col)[1], hsl(col)[2] * 0.6) + (255,))
        d.ellipse([cx - 2, 4, cx + 1, 8], fill=(255, 255, 255, 170))
    img.save(os.path.join(A, "ui", "element_orbs.png"))

def atlas():
    tiles = [
        ("grass_0", make_grass(0)), ("grass_1", make_grass(1)),
        ("grass_2", make_grass(2)), ("grass_3", make_grass(3)),
        ("tallgrass_0", make_tallgrass(0)), ("tallgrass_1", make_tallgrass(1)),
        ("flower_0", make_flower(0)), ("flower_1", make_flower(1)),
        ("sand_0", make_sand(0)), ("sand_1", make_sand(1)),
        ("water_0", make_water(0)), ("water_1", make_water(1)),
        ("stonefield_0", make_stonefield(0)), ("stonefield_1", make_stonefield(1)),
        ("dirt_0", make_dirt(0)), ("farmland_0", make_farmland(0)),
        ("wall_sx", wall_img("sx")), ("wall_sy", wall_img("sy")),
        ("wall_corner", wall_img("corner")),
        ("stair_sx", wall_img("stair_sx")), ("stair_sy", wall_img("stair_sy")),
        ("stair_corner", wall_img("stair_corner")),
        ("marker", marker_img()),
    ]
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
        json.dump({"cell": 64, "tw": TW, "th": TH, "wall": WALL, "tiles": manifest}, f)

def decor():
    for name, fn in {"tree_a": tree_a, "tree_b": tree_b,
                     "rock": lambda: boulder(), "ore_gold": lambda: boulder("#e8d44d"),
                     "ore_coal": lambda: boulder("#3c3c3c"), "berry_bush": berry_bush,
                     "stump": stump}.items():
        fn().save(os.path.join(A, "decor", f"{name}.png"))


SPRITES.update({
    "flambelle": ("blob", ["#e8734a", "#c9552f", "#ffd54f"], 0.25),
    "rooby": ("kitty", ["#c93a4d", "#a32c3d", "#f5eee0"], 0.3),
    "arsox": ("quadruped", ["#d1813c", "#a96a2f", "#ffd54f"], 0.2),
    "incineram": ("human", ["#8a3d5c", "#6d2e48", "#e8734a"], 0.1),
    "blazehowl": ("quadruped", ["#c9552f", "#9e3f22", "#ffd76e"], 0.15),
    "bushi": ("human", ["#a83232", "#7d2525", "#e8c9a0"], 0.1),
    "ragnahawk": ("bird", ["#e8734a", "#c9552f", "#3a3a4a"], 0.15),
    "suzaku": ("bird", ["#e8452f", "#c93522", "#ffd76e"], 0.2),
    "blazamut": ("cow", ["#8a4a4a", "#6d3838", "#e8734a"], 0.1),
    "kelpsea": ("serpent", ["#5ab8d1", "#4296b0", "#9be8d8"], 0.2),
    "chillet": ("quadruped", ["#8fd1e8", "#68b0d1", "#f5eee0"], 0.3),
    "celaray": ("ghost", ["#7ec8e3", "#5aa8c4", "#c8e8f5"], 0.15),
    "teafant": ("blob", ["#a8d8c8", "#85bfae", "#f5eee0"], 0.35),
    "relaxaurus": ("cow", ["#6d9dc5", "#5480a8", "#8fd1a0"], 0.15),
    "azurobe": ("serpent", ["#4d7db8", "#3a6196", "#9be8d8"], 0.1),
    "jormuntide": ("serpent", ["#3a5a8a", "#2d4770", "#8fd1e8"], 0.1),
    "gobfin": ("blob", ["#5a8db0", "#47708c", "#8fd1e8"], 0.2),
    "surfdog": ("quadruped", ["#e8c46a", "#c9a34d", "#4dd0e1"], 0.3),
    "ribbuny": ("mouse", ["#f2b8d1", "#d193ad", "#f5eee0"], 0.4),
    "flopie": ("blob", ["#b8d77c", "#96ba5e", "#f5eee0"], 0.35),
    "sweety": ("blob", ["#e8d44d", "#c9b23a", "#f5eee0"], 0.4),
    "beegarde": ("human", ["#e8d44d", "#b89a2f", "#3a3a4a"], 0.1),
    "bristla": ("quadruped", ["#7cb86a", "#5e9a4e", "#e8d44d"], 0.25),
    "caprity": ("deer", ["#a8c97a", "#88a85c", "#f2b8d1"], 0.25),
    "broncherry": ("quadruped", ["#c9b8d1", "#a89ab8", "#9be8d8"], 0.2),
    "dinossom": ("quadruped", ["#8fc46a", "#6da350", "#e8734a"], 0.2),
    "verdash": ("monkey", ["#6dc48a", "#4ea36a", "#e8d44d"], 0.2),
    "mossanda": ("monkey", ["#7cb86a", "#5e9a4e", "#b8935f"], 0.15),
    "grintale": ("kitty", ["#e8b8d1", "#c998b8", "#f5eee0"], 0.3),
    "elizabee": ("ghost", ["#e8d44d", "#c9a82f", "#3a3a4a"], 0.15),
    "vaelet": ("ghost", ["#c9a8e8", "#a885c9", "#f5eee0"], 0.25),
    "cinnamoth": ("ghost", ["#e8c98a", "#c9a85e", "#f5eee0"], 0.3),
    "lullu": ("ghost", ["#d8c8e8", "#b8a8c9", "#f5eee0"], 0.35),
    "petallia": ("ghost", ["#f2b8d1", "#d193ad", "#9be8a0"], 0.3),
    "univolt": ("deer", ["#e8d44d", "#c9a82f", "#4dd0e1"], 0.15),
    "beakon": ("bird", ["#e8d44d", "#c9b23a", "#3a3a4a"], 0.15),
    "rayhound": ("quadruped", ["#7ac9e8", "#5aa8c9", "#e8d44d"], 0.15),
    "dazzi": ("mouse", ["#e8e0a8", "#c9be85", "#e8d44d"], 0.3),
    "tocotoco": ("bird", ["#e8a83c", "#c9852a", "#3a3a4a"], 0.25),
    "grizzbolt": ("cow", ["#8a7a5a", "#6d5e45", "#e8d44d"], 0.1),
    "sweepa": ("quadruped", ["#b8d8e8", "#96b8c9", "#f5eee0"], 0.3),
    "swee": ("blob", ["#c8e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "wumpo": ("cow", ["#a8b8c9", "#8899aa", "#f5eee0"], 0.15),
    "sibelyx": ("quadruped", ["#d8d8e8", "#b8b8d1", "#8fd1e8"], 0.25),
    "reindrix": ("deer", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.2),
    "frostallion": ("deer", ["#8fc9e8", "#6aa8c9", "#f5eee0"], 0.1),
    "mau_cryst": ("kitty", ["#a8d8e8", "#85b8c9", "#e8f5fa"], 0.25),
    "hangyu": ("ghost", ["#8fb8a8", "#6d9685", "#f5eee0"], 0.3),
    "fuddler": ("mouse", ["#8a7a6a", "#6d5f52", "#d8b8a8"], 0.3),
    "digtoise": ("hedgehog", ["#a8885a", "#8a6d45", "#d8c9a0"], 0.15),
    "anubis": ("human", ["#5a5a8a", "#44446d", "#e8c9a0"], 0.1),
    "reptyro": ("quadruped", ["#8a6d5a", "#6d5443", "#d89a5a"], 0.15),
    "direhowl": ("quadruped", ["#8a8a9a", "#6d6d7d", "#f5eee0"], 0.15),
    "galeclaw": ("bird", ["#7a9db8", "#5d82a0", "#e8d44d"], 0.15),
    "cawgnito": ("bird", ["#5a5a6a", "#44445a", "#e8c98a"], 0.2),
    "robinquill": ("human", ["#7ab86a", "#5d9a4e", "#e8c9a0"], 0.15),
    "gorirat": ("monkey", ["#7a6a5a", "#5d5243", "#d8c9a0"], 0.2),
    "woolipop": ("hedgehog", ["#f5d8e8", "#d8b8c9", "#f5eee0"], 0.45),
    "melpaca": ("quadruped", ["#e8b8c9", "#c998ad", "#f5eee0"], 0.3),
    "vixy": ("kitty", ["#e8c9a8", "#c9a888", "#f5eee0"], 0.35),
    "lovander": ("human", ["#d88aa8", "#b86a8a", "#f5eee0"], 0.2),
    "loupmoon": ("quadruped", ["#5a5a7a", "#43435e", "#c9d8e8"], 0.15),
    "hoocrates": ("human", ["#7a6a8a", "#5d526d", "#e8d44d"], 0.2),
    "killamari": ("ghost", ["#8a7ad1", "#6d5eb0", "#f5eee0"], 0.25),
    "lunaris": ("human", ["#8aa8d1", "#6a85b0", "#f5eee0"], 0.2),
    "nox": ("ghost", ["#8a6a9a", "#6d517d", "#f5eee0"], 0.3),
    "maraith": ("ghost", ["#6a8a7a", "#526d5e", "#c9e8d8"], 0.25),
    "catress": ("kitty", ["#9a7ab8", "#7d5e9a", "#e8d44d"], 0.25),
    "wixen": ("human", ["#b87a9a", "#96587d", "#f5eee0"], 0.2),
    "menasting": ("human", ["#4a3a5a", "#3a2d47", "#e8d44d"], 0.1),
    "shadowbeak": ("bird", ["#5a4a7a", "#443761", "#e8452f"], 0.1),
    "necromus": ("human", ["#6a5a7a", "#53455e", "#e8452f"], 0.1),
    "helzephyr": ("bird", ["#6a5a8a", "#53456d", "#a8d8e8"], 0.15),
    "tombat": ("blob", ["#8a7a9a", "#6d5f7d", "#d8c9a0"], 0.25),
    "jetragon": ("bird", ["#5a8ad1", "#4370b0", "#e8d44d"], 0.1),
    "paladius": ("human", ["#d8d8e8", "#b8b8d1", "#e8c9a0"], 0.1),
    "quivern": ("bird", ["#8a9ad1", "#6a7cb0", "#f5eee0"], 0.15),
    "astegon": ("quadruped", ["#4a4a6a", "#383853", "#e8452f"], 0.1),
    "elphidran": ("quadruped", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.15),
    "blazequil": ("hedgehog", ["#e88a4a", "#c96d2f", "#ffd76e"], 0.3),
    "hydrostar": ("blob", ["#5ac9d1", "#42a8b0", "#f5eee0"], 0.3),
    "stormpuff": ("ghost", ["#8ad1e8", "#68b0c9", "#e8d44d"], 0.3),
    "emberwing": ("bird", ["#e8a85a", "#c98542", "#3a3a4a"], 0.2),
    "mirelurk": ("hedgehog", ["#6a8a5a", "#526d45", "#d8c9a0"], 0.2),
    "frostbun": ("mouse", ["#c9e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "thornite": ("hedgehog", ["#7a8a6a", "#5e6d52", "#c9b88a"], 0.2),
    "dreadmaw": ("serpent", ["#5a4a6a", "#453a53", "#e8452f"], 0.1),
    "glimmora": ("ghost", ["#c9d8a8", "#a8b885", "#e8d44d"], 0.3),
    "cragboar": ("boar", ["#8a7a6a", "#6d5f52", "#d8c9a0"], 0.15),
    "vapori": ("ghost", ["#a8e8d8", "#85c9b8", "#f5eee0"], 0.35),
    "bombird": ("bird", ["#9a6a4a", "#7d523a", "#e8734a"], 0.15),
})


SPRITES.update({
    "flambelle": ("blob", ["#e8734a", "#c9552f", "#ffd54f"], 0.25),
    "rooby": ("kitty", ["#c93a4d", "#a32c3d", "#f5eee0"], 0.3),
    "arsox": ("quadruped", ["#d1813c", "#a96a2f", "#ffd54f"], 0.2),
    "incineram": ("human", ["#8a3d5c", "#6d2e48", "#e8734a"], 0.1),
    "blazehowl": ("quadruped", ["#c9552f", "#9e3f22", "#ffd76e"], 0.15),
    "bushi": ("human", ["#a83232", "#7d2525", "#e8c9a0"], 0.1),
    "ragnahawk": ("bird", ["#e8734a", "#c9552f", "#3a3a4a"], 0.15),
    "suzaku": ("bird", ["#e8452f", "#c93522", "#ffd76e"], 0.2),
    "blazamut": ("cow", ["#8a4a4a", "#6d3838", "#e8734a"], 0.1),
    "kelpsea": ("serpent", ["#5ab8d1", "#4296b0", "#9be8d8"], 0.2),
    "chillet": ("quadruped", ["#8fd1e8", "#68b0d1", "#f5eee0"], 0.3),
    "celaray": ("ghost", ["#7ec8e3", "#5aa8c4", "#c8e8f5"], 0.15),
    "teafant": ("blob", ["#a8d8c8", "#85bfae", "#f5eee0"], 0.35),
    "relaxaurus": ("cow", ["#6d9dc5", "#5480a8", "#8fd1a0"], 0.15),
    "azurobe": ("serpent", ["#4d7db8", "#3a6196", "#9be8d8"], 0.1),
    "jormuntide": ("serpent", ["#3a5a8a", "#2d4770", "#8fd1e8"], 0.1),
    "gobfin": ("blob", ["#5a8db0", "#47708c", "#8fd1e8"], 0.2),
    "surfdog": ("quadruped", ["#e8c46a", "#c9a34d", "#4dd0e1"], 0.3),
    "ribbuny": ("mouse", ["#f2b8d1", "#d193ad", "#f5eee0"], 0.4),
    "flopie": ("blob", ["#b8d77c", "#96ba5e", "#f5eee0"], 0.35),
    "sweety": ("blob", ["#e8d44d", "#c9b23a", "#f5eee0"], 0.4),
    "beegarde": ("human", ["#e8d44d", "#b89a2f", "#3a3a4a"], 0.1),
    "bristla": ("quadruped", ["#7cb86a", "#5e9a4e", "#e8d44d"], 0.25),
    "caprity": ("deer", ["#a8c97a", "#88a85c", "#f2b8d1"], 0.25),
    "broncherry": ("quadruped", ["#c9b8d1", "#a89ab8", "#9be8d8"], 0.2),
    "dinossom": ("quadruped", ["#8fc46a", "#6da350", "#e8734a"], 0.2),
    "verdash": ("monkey", ["#6dc48a", "#4ea36a", "#e8d44d"], 0.2),
    "mossanda": ("monkey", ["#7cb86a", "#5e9a4e", "#b8935f"], 0.15),
    "grintale": ("kitty", ["#e8b8d1", "#c998b8", "#f5eee0"], 0.3),
    "elizabee": ("ghost", ["#e8d44d", "#c9a82f", "#3a3a4a"], 0.15),
    "vaelet": ("ghost", ["#c9a8e8", "#a885c9", "#f5eee0"], 0.25),
    "cinnamoth": ("ghost", ["#e8c98a", "#c9a85e", "#f5eee0"], 0.3),
    "lullu": ("ghost", ["#d8c8e8", "#b8a8c9", "#f5eee0"], 0.35),
    "petallia": ("ghost", ["#f2b8d1", "#d193ad", "#9be8a0"], 0.3),
    "univolt": ("deer", ["#e8d44d", "#c9a82f", "#4dd0e1"], 0.15),
    "beakon": ("bird", ["#e8d44d", "#c9b23a", "#3a3a4a"], 0.15),
    "rayhound": ("quadruped", ["#7ac9e8", "#5aa8c9", "#e8d44d"], 0.15),
    "dazzi": ("mouse", ["#e8e0a8", "#c9be85", "#e8d44d"], 0.3),
    "tocotoco": ("bird", ["#e8a83c", "#c9852a", "#3a3a4a"], 0.25),
    "grizzbolt": ("cow", ["#8a7a5a", "#6d5e45", "#e8d44d"], 0.1),
    "sweepa": ("quadruped", ["#b8d8e8", "#96b8c9", "#f5eee0"], 0.3),
    "swee": ("blob", ["#c8e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "wumpo": ("cow", ["#a8b8c9", "#8899aa", "#f5eee0"], 0.15),
    "sibelyx": ("quadruped", ["#d8d8e8", "#b8b8d1", "#8fd1e8"], 0.25),
    "reindrix": ("deer", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.2),
    "frostallion": ("deer", ["#8fc9e8", "#6aa8c9", "#f5eee0"], 0.1),
    "mau_cryst": ("kitty", ["#a8d8e8", "#85b8c9", "#e8f5fa"], 0.25),
    "hangyu": ("ghost", ["#8fb8a8", "#6d9685", "#f5eee0"], 0.3),
    "fuddler": ("mouse", ["#8a7a6a", "#6d5f52", "#d8b8a8"], 0.3),
    "digtoise": ("hedgehog", ["#a8885a", "#8a6d45", "#d8c9a0"], 0.15),
    "anubis": ("human", ["#5a5a8a", "#44446d", "#e8c9a0"], 0.1),
    "reptyro": ("quadruped", ["#8a6d5a", "#6d5443", "#d89a5a"], 0.15),
    "direhowl": ("quadruped", ["#8a8a9a", "#6d6d7d", "#f5eee0"], 0.15),
    "galeclaw": ("bird", ["#7a9db8", "#5d82a0", "#e8d44d"], 0.15),
    "cawgnito": ("bird", ["#5a5a6a", "#44445a", "#e8c98a"], 0.2),
    "robinquill": ("human", ["#7ab86a", "#5d9a4e", "#e8c9a0"], 0.15),
    "gorirat": ("monkey", ["#7a6a5a", "#5d5243", "#d8c9a0"], 0.2),
    "woolipop": ("hedgehog", ["#f5d8e8", "#d8b8c9", "#f5eee0"], 0.45),
    "melpaca": ("quadruped", ["#e8b8c9", "#c998ad", "#f5eee0"], 0.3),
    "vixy": ("kitty", ["#e8c9a8", "#c9a888", "#f5eee0"], 0.35),
    "lovander": ("human", ["#d88aa8", "#b86a8a", "#f5eee0"], 0.2),
    "loupmoon": ("quadruped", ["#5a5a7a", "#43435e", "#c9d8e8"], 0.15),
    "hoocrates": ("human", ["#7a6a8a", "#5d526d", "#e8d44d"], 0.2),
    "killamari": ("ghost", ["#8a7ad1", "#6d5eb0", "#f5eee0"], 0.25),
    "lunaris": ("human", ["#8aa8d1", "#6a85b0", "#f5eee0"], 0.2),
    "nox": ("ghost", ["#8a6a9a", "#6d517d", "#f5eee0"], 0.3),
    "maraith": ("ghost", ["#6a8a7a", "#526d5e", "#c9e8d8"], 0.25),
    "catress": ("kitty", ["#9a7ab8", "#7d5e9a", "#e8d44d"], 0.25),
    "wixen": ("human", ["#b87a9a", "#96587d", "#f5eee0"], 0.2),
    "menasting": ("human", ["#4a3a5a", "#3a2d47", "#e8d44d"], 0.1),
    "shadowbeak": ("bird", ["#5a4a7a", "#443761", "#e8452f"], 0.1),
    "necromus": ("human", ["#6a5a7a", "#53455e", "#e8452f"], 0.1),
    "helzephyr": ("bird", ["#6a5a8a", "#53456d", "#a8d8e8"], 0.15),
    "tombat": ("blob", ["#8a7a9a", "#6d5f7d", "#d8c9a0"], 0.25),
    "jetragon": ("bird", ["#5a8ad1", "#4370b0", "#e8d44d"], 0.1),
    "paladius": ("human", ["#d8d8e8", "#b8b8d1", "#e8c9a0"], 0.1),
    "quivern": ("bird", ["#8a9ad1", "#6a7cb0", "#f5eee0"], 0.15),
    "astegon": ("quadruped", ["#4a4a6a", "#383853", "#e8452f"], 0.1),
    "elphidran": ("quadruped", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.15),
    "blazequil": ("hedgehog", ["#e88a4a", "#c96d2f", "#ffd76e"], 0.3),
    "hydrostar": ("blob", ["#5ac9d1", "#42a8b0", "#f5eee0"], 0.3),
    "stormpuff": ("ghost", ["#8ad1e8", "#68b0c9", "#e8d44d"], 0.3),
    "emberwing": ("bird", ["#e8a85a", "#c98542", "#3a3a4a"], 0.2),
    "mirelurk": ("hedgehog", ["#6a8a5a", "#526d45", "#d8c9a0"], 0.2),
    "frostbun": ("mouse", ["#c9e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "thornite": ("hedgehog", ["#7a8a6a", "#5e6d52", "#c9b88a"], 0.2),
    "dreadmaw": ("serpent", ["#5a4a6a", "#453a53", "#e8452f"], 0.1),
    "glimmora": ("ghost", ["#c9d8a8", "#a8b885", "#e8d44d"], 0.3),
    "cragboar": ("boar", ["#8a7a6a", "#6d5f52", "#d8c9a0"], 0.15),
    "vapori": ("ghost", ["#a8e8d8", "#85c9b8", "#f5eee0"], 0.35),
    "bombird": ("bird", ["#9a6a4a", "#7d523a", "#e8734a"], 0.15),
})


SPRITES.update({
    "flambelle": ("blob", ["#e8734a", "#c9552f", "#ffd54f"], 0.25),
    "rooby": ("kitty", ["#c93a4d", "#a32c3d", "#f5eee0"], 0.3),
    "arsox": ("quadruped", ["#d1813c", "#a96a2f", "#ffd54f"], 0.2),
    "incineram": ("human", ["#8a3d5c", "#6d2e48", "#e8734a"], 0.1),
    "blazehowl": ("quadruped", ["#c9552f", "#9e3f22", "#ffd76e"], 0.15),
    "bushi": ("human", ["#a83232", "#7d2525", "#e8c9a0"], 0.1),
    "ragnahawk": ("bird", ["#e8734a", "#c9552f", "#3a3a4a"], 0.15),
    "suzaku": ("bird", ["#e8452f", "#c93522", "#ffd76e"], 0.2),
    "blazamut": ("cow", ["#8a4a4a", "#6d3838", "#e8734a"], 0.1),
    "kelpsea": ("serpent", ["#5ab8d1", "#4296b0", "#9be8d8"], 0.2),
    "chillet": ("quadruped", ["#8fd1e8", "#68b0d1", "#f5eee0"], 0.3),
    "celaray": ("ghost", ["#7ec8e3", "#5aa8c4", "#c8e8f5"], 0.15),
    "teafant": ("blob", ["#a8d8c8", "#85bfae", "#f5eee0"], 0.35),
    "relaxaurus": ("cow", ["#6d9dc5", "#5480a8", "#8fd1a0"], 0.15),
    "azurobe": ("serpent", ["#4d7db8", "#3a6196", "#9be8d8"], 0.1),
    "jormuntide": ("serpent", ["#3a5a8a", "#2d4770", "#8fd1e8"], 0.1),
    "gobfin": ("blob", ["#5a8db0", "#47708c", "#8fd1e8"], 0.2),
    "surfdog": ("quadruped", ["#e8c46a", "#c9a34d", "#4dd0e1"], 0.3),
    "ribbuny": ("mouse", ["#f2b8d1", "#d193ad", "#f5eee0"], 0.4),
    "flopie": ("blob", ["#b8d77c", "#96ba5e", "#f5eee0"], 0.35),
    "sweety": ("blob", ["#e8d44d", "#c9b23a", "#f5eee0"], 0.4),
    "beegarde": ("human", ["#e8d44d", "#b89a2f", "#3a3a4a"], 0.1),
    "bristla": ("quadruped", ["#7cb86a", "#5e9a4e", "#e8d44d"], 0.25),
    "caprity": ("deer", ["#a8c97a", "#88a85c", "#f2b8d1"], 0.25),
    "broncherry": ("quadruped", ["#c9b8d1", "#a89ab8", "#9be8d8"], 0.2),
    "dinossom": ("quadruped", ["#8fc46a", "#6da350", "#e8734a"], 0.2),
    "verdash": ("monkey", ["#6dc48a", "#4ea36a", "#e8d44d"], 0.2),
    "mossanda": ("monkey", ["#7cb86a", "#5e9a4e", "#b8935f"], 0.15),
    "grintale": ("kitty", ["#e8b8d1", "#c998b8", "#f5eee0"], 0.3),
    "elizabee": ("ghost", ["#e8d44d", "#c9a82f", "#3a3a4a"], 0.15),
    "vaelet": ("ghost", ["#c9a8e8", "#a885c9", "#f5eee0"], 0.25),
    "cinnamoth": ("ghost", ["#e8c98a", "#c9a85e", "#f5eee0"], 0.3),
    "lullu": ("ghost", ["#d8c8e8", "#b8a8c9", "#f5eee0"], 0.35),
    "petallia": ("ghost", ["#f2b8d1", "#d193ad", "#9be8a0"], 0.3),
    "univolt": ("deer", ["#e8d44d", "#c9a82f", "#4dd0e1"], 0.15),
    "beakon": ("bird", ["#e8d44d", "#c9b23a", "#3a3a4a"], 0.15),
    "rayhound": ("quadruped", ["#7ac9e8", "#5aa8c9", "#e8d44d"], 0.15),
    "dazzi": ("mouse", ["#e8e0a8", "#c9be85", "#e8d44d"], 0.3),
    "tocotoco": ("bird", ["#e8a83c", "#c9852a", "#3a3a4a"], 0.25),
    "grizzbolt": ("cow", ["#8a7a5a", "#6d5e45", "#e8d44d"], 0.1),
    "sweepa": ("quadruped", ["#b8d8e8", "#96b8c9", "#f5eee0"], 0.3),
    "swee": ("blob", ["#c8e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "wumpo": ("cow", ["#a8b8c9", "#8899aa", "#f5eee0"], 0.15),
    "sibelyx": ("quadruped", ["#d8d8e8", "#b8b8d1", "#8fd1e8"], 0.25),
    "reindrix": ("deer", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.2),
    "frostallion": ("deer", ["#8fc9e8", "#6aa8c9", "#f5eee0"], 0.1),
    "mau_cryst": ("kitty", ["#a8d8e8", "#85b8c9", "#e8f5fa"], 0.25),
    "hangyu": ("ghost", ["#8fb8a8", "#6d9685", "#f5eee0"], 0.3),
    "fuddler": ("mouse", ["#8a7a6a", "#6d5f52", "#d8b8a8"], 0.3),
    "digtoise": ("hedgehog", ["#a8885a", "#8a6d45", "#d8c9a0"], 0.15),
    "anubis": ("human", ["#5a5a8a", "#44446d", "#e8c9a0"], 0.1),
    "reptyro": ("quadruped", ["#8a6d5a", "#6d5443", "#d89a5a"], 0.15),
    "direhowl": ("quadruped", ["#8a8a9a", "#6d6d7d", "#f5eee0"], 0.15),
    "galeclaw": ("bird", ["#7a9db8", "#5d82a0", "#e8d44d"], 0.15),
    "cawgnito": ("bird", ["#5a5a6a", "#44445a", "#e8c98a"], 0.2),
    "robinquill": ("human", ["#7ab86a", "#5d9a4e", "#e8c9a0"], 0.15),
    "gorirat": ("monkey", ["#7a6a5a", "#5d5243", "#d8c9a0"], 0.2),
    "woolipop": ("hedgehog", ["#f5d8e8", "#d8b8c9", "#f5eee0"], 0.45),
    "melpaca": ("quadruped", ["#e8b8c9", "#c998ad", "#f5eee0"], 0.3),
    "vixy": ("kitty", ["#e8c9a8", "#c9a888", "#f5eee0"], 0.35),
    "lovander": ("human", ["#d88aa8", "#b86a8a", "#f5eee0"], 0.2),
    "loupmoon": ("quadruped", ["#5a5a7a", "#43435e", "#c9d8e8"], 0.15),
    "hoocrates": ("human", ["#7a6a8a", "#5d526d", "#e8d44d"], 0.2),
    "killamari": ("ghost", ["#8a7ad1", "#6d5eb0", "#f5eee0"], 0.25),
    "lunaris": ("human", ["#8aa8d1", "#6a85b0", "#f5eee0"], 0.2),
    "nox": ("ghost", ["#8a6a9a", "#6d517d", "#f5eee0"], 0.3),
    "maraith": ("ghost", ["#6a8a7a", "#526d5e", "#c9e8d8"], 0.25),
    "catress": ("kitty", ["#9a7ab8", "#7d5e9a", "#e8d44d"], 0.25),
    "wixen": ("human", ["#b87a9a", "#96587d", "#f5eee0"], 0.2),
    "menasting": ("human", ["#4a3a5a", "#3a2d47", "#e8d44d"], 0.1),
    "shadowbeak": ("bird", ["#5a4a7a", "#443761", "#e8452f"], 0.1),
    "necromus": ("human", ["#6a5a7a", "#53455e", "#e8452f"], 0.1),
    "helzephyr": ("bird", ["#6a5a8a", "#53456d", "#a8d8e8"], 0.15),
    "tombat": ("blob", ["#8a7a9a", "#6d5f7d", "#d8c9a0"], 0.25),
    "jetragon": ("bird", ["#5a8ad1", "#4370b0", "#e8d44d"], 0.1),
    "paladius": ("human", ["#d8d8e8", "#b8b8d1", "#e8c9a0"], 0.1),
    "quivern": ("bird", ["#8a9ad1", "#6a7cb0", "#f5eee0"], 0.15),
    "astegon": ("quadruped", ["#4a4a6a", "#383853", "#e8452f"], 0.1),
    "elphidran": ("quadruped", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.15),
    "blazequil": ("hedgehog", ["#e88a4a", "#c96d2f", "#ffd76e"], 0.3),
    "hydrostar": ("blob", ["#5ac9d1", "#42a8b0", "#f5eee0"], 0.3),
    "stormpuff": ("ghost", ["#8ad1e8", "#68b0c9", "#e8d44d"], 0.3),
    "emberwing": ("bird", ["#e8a85a", "#c98542", "#3a3a4a"], 0.2),
    "mirelurk": ("hedgehog", ["#6a8a5a", "#526d45", "#d8c9a0"], 0.2),
    "frostbun": ("mouse", ["#c9e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "thornite": ("hedgehog", ["#7a8a6a", "#5e6d52", "#c9b88a"], 0.2),
    "dreadmaw": ("serpent", ["#5a4a6a", "#453a53", "#e8452f"], 0.1),
    "glimmora": ("ghost", ["#c9d8a8", "#a8b885", "#e8d44d"], 0.3),
    "cragboar": ("boar", ["#8a7a6a", "#6d5f52", "#d8c9a0"], 0.15),
    "vapori": ("ghost", ["#a8e8d8", "#85c9b8", "#f5eee0"], 0.35),
    "bombird": ("bird", ["#9a6a4a", "#7d523a", "#e8734a"], 0.15),
})


SPRITES.update({
    "flambelle": ("blob", ["#e8734a", "#c9552f", "#ffd54f"], 0.25),
    "rooby": ("kitty", ["#c93a4d", "#a32c3d", "#f5eee0"], 0.3),
    "arsox": ("quadruped", ["#d1813c", "#a96a2f", "#ffd54f"], 0.2),
    "incineram": ("human", ["#8a3d5c", "#6d2e48", "#e8734a"], 0.1),
    "blazehowl": ("quadruped", ["#c9552f", "#9e3f22", "#ffd76e"], 0.15),
    "bushi": ("human", ["#a83232", "#7d2525", "#e8c9a0"], 0.1),
    "ragnahawk": ("bird", ["#e8734a", "#c9552f", "#3a3a4a"], 0.15),
    "suzaku": ("bird", ["#e8452f", "#c93522", "#ffd76e"], 0.2),
    "blazamut": ("cow", ["#8a4a4a", "#6d3838", "#e8734a"], 0.1),
    "kelpsea": ("serpent", ["#5ab8d1", "#4296b0", "#9be8d8"], 0.2),
    "chillet": ("quadruped", ["#8fd1e8", "#68b0d1", "#f5eee0"], 0.3),
    "celaray": ("ghost", ["#7ec8e3", "#5aa8c4", "#c8e8f5"], 0.15),
    "teafant": ("blob", ["#a8d8c8", "#85bfae", "#f5eee0"], 0.35),
    "relaxaurus": ("cow", ["#6d9dc5", "#5480a8", "#8fd1a0"], 0.15),
    "azurobe": ("serpent", ["#4d7db8", "#3a6196", "#9be8d8"], 0.1),
    "jormuntide": ("serpent", ["#3a5a8a", "#2d4770", "#8fd1e8"], 0.1),
    "gobfin": ("blob", ["#5a8db0", "#47708c", "#8fd1e8"], 0.2),
    "surfdog": ("quadruped", ["#e8c46a", "#c9a34d", "#4dd0e1"], 0.3),
    "ribbuny": ("mouse", ["#f2b8d1", "#d193ad", "#f5eee0"], 0.4),
    "flopie": ("blob", ["#b8d77c", "#96ba5e", "#f5eee0"], 0.35),
    "sweety": ("blob", ["#e8d44d", "#c9b23a", "#f5eee0"], 0.4),
    "beegarde": ("human", ["#e8d44d", "#b89a2f", "#3a3a4a"], 0.1),
    "bristla": ("quadruped", ["#7cb86a", "#5e9a4e", "#e8d44d"], 0.25),
    "caprity": ("deer", ["#a8c97a", "#88a85c", "#f2b8d1"], 0.25),
    "broncherry": ("quadruped", ["#c9b8d1", "#a89ab8", "#9be8d8"], 0.2),
    "dinossom": ("quadruped", ["#8fc46a", "#6da350", "#e8734a"], 0.2),
    "verdash": ("monkey", ["#6dc48a", "#4ea36a", "#e8d44d"], 0.2),
    "mossanda": ("monkey", ["#7cb86a", "#5e9a4e", "#b8935f"], 0.15),
    "grintale": ("kitty", ["#e8b8d1", "#c998b8", "#f5eee0"], 0.3),
    "elizabee": ("ghost", ["#e8d44d", "#c9a82f", "#3a3a4a"], 0.15),
    "vaelet": ("ghost", ["#c9a8e8", "#a885c9", "#f5eee0"], 0.25),
    "cinnamoth": ("ghost", ["#e8c98a", "#c9a85e", "#f5eee0"], 0.3),
    "lullu": ("ghost", ["#d8c8e8", "#b8a8c9", "#f5eee0"], 0.35),
    "petallia": ("ghost", ["#f2b8d1", "#d193ad", "#9be8a0"], 0.3),
    "univolt": ("deer", ["#e8d44d", "#c9a82f", "#4dd0e1"], 0.15),
    "beakon": ("bird", ["#e8d44d", "#c9b23a", "#3a3a4a"], 0.15),
    "rayhound": ("quadruped", ["#7ac9e8", "#5aa8c9", "#e8d44d"], 0.15),
    "dazzi": ("mouse", ["#e8e0a8", "#c9be85", "#e8d44d"], 0.3),
    "tocotoco": ("bird", ["#e8a83c", "#c9852a", "#3a3a4a"], 0.25),
    "grizzbolt": ("cow", ["#8a7a5a", "#6d5e45", "#e8d44d"], 0.1),
    "sweepa": ("quadruped", ["#b8d8e8", "#96b8c9", "#f5eee0"], 0.3),
    "swee": ("blob", ["#c8e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "wumpo": ("cow", ["#a8b8c9", "#8899aa", "#f5eee0"], 0.15),
    "sibelyx": ("quadruped", ["#d8d8e8", "#b8b8d1", "#8fd1e8"], 0.25),
    "reindrix": ("deer", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.2),
    "frostallion": ("deer", ["#8fc9e8", "#6aa8c9", "#f5eee0"], 0.1),
    "mau_cryst": ("kitty", ["#a8d8e8", "#85b8c9", "#e8f5fa"], 0.25),
    "hangyu": ("ghost", ["#8fb8a8", "#6d9685", "#f5eee0"], 0.3),
    "fuddler": ("mouse", ["#8a7a6a", "#6d5f52", "#d8b8a8"], 0.3),
    "digtoise": ("hedgehog", ["#a8885a", "#8a6d45", "#d8c9a0"], 0.15),
    "anubis": ("human", ["#5a5a8a", "#44446d", "#e8c9a0"], 0.1),
    "reptyro": ("quadruped", ["#8a6d5a", "#6d5443", "#d89a5a"], 0.15),
    "direhowl": ("quadruped", ["#8a8a9a", "#6d6d7d", "#f5eee0"], 0.15),
    "galeclaw": ("bird", ["#7a9db8", "#5d82a0", "#e8d44d"], 0.15),
    "cawgnito": ("bird", ["#5a5a6a", "#44445a", "#e8c98a"], 0.2),
    "robinquill": ("human", ["#7ab86a", "#5d9a4e", "#e8c9a0"], 0.15),
    "gorirat": ("monkey", ["#7a6a5a", "#5d5243", "#d8c9a0"], 0.2),
    "woolipop": ("hedgehog", ["#f5d8e8", "#d8b8c9", "#f5eee0"], 0.45),
    "melpaca": ("quadruped", ["#e8b8c9", "#c998ad", "#f5eee0"], 0.3),
    "vixy": ("kitty", ["#e8c9a8", "#c9a888", "#f5eee0"], 0.35),
    "lovander": ("human", ["#d88aa8", "#b86a8a", "#f5eee0"], 0.2),
    "loupmoon": ("quadruped", ["#5a5a7a", "#43435e", "#c9d8e8"], 0.15),
    "hoocrates": ("human", ["#7a6a8a", "#5d526d", "#e8d44d"], 0.2),
    "killamari": ("ghost", ["#8a7ad1", "#6d5eb0", "#f5eee0"], 0.25),
    "lunaris": ("human", ["#8aa8d1", "#6a85b0", "#f5eee0"], 0.2),
    "nox": ("ghost", ["#8a6a9a", "#6d517d", "#f5eee0"], 0.3),
    "maraith": ("ghost", ["#6a8a7a", "#526d5e", "#c9e8d8"], 0.25),
    "catress": ("kitty", ["#9a7ab8", "#7d5e9a", "#e8d44d"], 0.25),
    "wixen": ("human", ["#b87a9a", "#96587d", "#f5eee0"], 0.2),
    "menasting": ("human", ["#4a3a5a", "#3a2d47", "#e8d44d"], 0.1),
    "shadowbeak": ("bird", ["#5a4a7a", "#443761", "#e8452f"], 0.1),
    "necromus": ("human", ["#6a5a7a", "#53455e", "#e8452f"], 0.1),
    "helzephyr": ("bird", ["#6a5a8a", "#53456d", "#a8d8e8"], 0.15),
    "tombat": ("blob", ["#8a7a9a", "#6d5f7d", "#d8c9a0"], 0.25),
    "jetragon": ("bird", ["#5a8ad1", "#4370b0", "#e8d44d"], 0.1),
    "paladius": ("human", ["#d8d8e8", "#b8b8d1", "#e8c9a0"], 0.1),
    "quivern": ("bird", ["#8a9ad1", "#6a7cb0", "#f5eee0"], 0.15),
    "astegon": ("quadruped", ["#4a4a6a", "#383853", "#e8452f"], 0.1),
    "elphidran": ("quadruped", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.15),
    "blazequil": ("hedgehog", ["#e88a4a", "#c96d2f", "#ffd76e"], 0.3),
    "hydrostar": ("blob", ["#5ac9d1", "#42a8b0", "#f5eee0"], 0.3),
    "stormpuff": ("ghost", ["#8ad1e8", "#68b0c9", "#e8d44d"], 0.3),
    "emberwing": ("bird", ["#e8a85a", "#c98542", "#3a3a4a"], 0.2),
    "mirelurk": ("hedgehog", ["#6a8a5a", "#526d45", "#d8c9a0"], 0.2),
    "frostbun": ("mouse", ["#c9e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "thornite": ("hedgehog", ["#7a8a6a", "#5e6d52", "#c9b88a"], 0.2),
    "dreadmaw": ("serpent", ["#5a4a6a", "#453a53", "#e8452f"], 0.1),
    "glimmora": ("ghost", ["#c9d8a8", "#a8b885", "#e8d44d"], 0.3),
    "cragboar": ("boar", ["#8a7a6a", "#6d5f52", "#d8c9a0"], 0.15),
    "vapori": ("ghost", ["#a8e8d8", "#85c9b8", "#f5eee0"], 0.35),
    "bombird": ("bird", ["#9a6a4a", "#7d523a", "#e8734a"], 0.15),
})


SPRITES.update({
    "flambelle": ("blob", ["#e8734a", "#c9552f", "#ffd54f"], 0.25),
    "rooby": ("kitty", ["#c93a4d", "#a32c3d", "#f5eee0"], 0.3),
    "arsox": ("quadruped", ["#d1813c", "#a96a2f", "#ffd54f"], 0.2),
    "incineram": ("human", ["#8a3d5c", "#6d2e48", "#e8734a"], 0.1),
    "blazehowl": ("quadruped", ["#c9552f", "#9e3f22", "#ffd76e"], 0.15),
    "bushi": ("human", ["#a83232", "#7d2525", "#e8c9a0"], 0.1),
    "ragnahawk": ("bird", ["#e8734a", "#c9552f", "#3a3a4a"], 0.15),
    "suzaku": ("bird", ["#e8452f", "#c93522", "#ffd76e"], 0.2),
    "blazamut": ("cow", ["#8a4a4a", "#6d3838", "#e8734a"], 0.1),
    "kelpsea": ("serpent", ["#5ab8d1", "#4296b0", "#9be8d8"], 0.2),
    "chillet": ("quadruped", ["#8fd1e8", "#68b0d1", "#f5eee0"], 0.3),
    "celaray": ("ghost", ["#7ec8e3", "#5aa8c4", "#c8e8f5"], 0.15),
    "teafant": ("blob", ["#a8d8c8", "#85bfae", "#f5eee0"], 0.35),
    "relaxaurus": ("cow", ["#6d9dc5", "#5480a8", "#8fd1a0"], 0.15),
    "azurobe": ("serpent", ["#4d7db8", "#3a6196", "#9be8d8"], 0.1),
    "jormuntide": ("serpent", ["#3a5a8a", "#2d4770", "#8fd1e8"], 0.1),
    "gobfin": ("blob", ["#5a8db0", "#47708c", "#8fd1e8"], 0.2),
    "surfdog": ("quadruped", ["#e8c46a", "#c9a34d", "#4dd0e1"], 0.3),
    "ribbuny": ("mouse", ["#f2b8d1", "#d193ad", "#f5eee0"], 0.4),
    "flopie": ("blob", ["#b8d77c", "#96ba5e", "#f5eee0"], 0.35),
    "sweety": ("blob", ["#e8d44d", "#c9b23a", "#f5eee0"], 0.4),
    "beegarde": ("human", ["#e8d44d", "#b89a2f", "#3a3a4a"], 0.1),
    "bristla": ("quadruped", ["#7cb86a", "#5e9a4e", "#e8d44d"], 0.25),
    "caprity": ("deer", ["#a8c97a", "#88a85c", "#f2b8d1"], 0.25),
    "broncherry": ("quadruped", ["#c9b8d1", "#a89ab8", "#9be8d8"], 0.2),
    "dinossom": ("quadruped", ["#8fc46a", "#6da350", "#e8734a"], 0.2),
    "verdash": ("monkey", ["#6dc48a", "#4ea36a", "#e8d44d"], 0.2),
    "mossanda": ("monkey", ["#7cb86a", "#5e9a4e", "#b8935f"], 0.15),
    "grintale": ("kitty", ["#e8b8d1", "#c998b8", "#f5eee0"], 0.3),
    "elizabee": ("ghost", ["#e8d44d", "#c9a82f", "#3a3a4a"], 0.15),
    "vaelet": ("ghost", ["#c9a8e8", "#a885c9", "#f5eee0"], 0.25),
    "cinnamoth": ("ghost", ["#e8c98a", "#c9a85e", "#f5eee0"], 0.3),
    "lullu": ("ghost", ["#d8c8e8", "#b8a8c9", "#f5eee0"], 0.35),
    "petallia": ("ghost", ["#f2b8d1", "#d193ad", "#9be8a0"], 0.3),
    "univolt": ("deer", ["#e8d44d", "#c9a82f", "#4dd0e1"], 0.15),
    "beakon": ("bird", ["#e8d44d", "#c9b23a", "#3a3a4a"], 0.15),
    "rayhound": ("quadruped", ["#7ac9e8", "#5aa8c9", "#e8d44d"], 0.15),
    "dazzi": ("mouse", ["#e8e0a8", "#c9be85", "#e8d44d"], 0.3),
    "tocotoco": ("bird", ["#e8a83c", "#c9852a", "#3a3a4a"], 0.25),
    "grizzbolt": ("cow", ["#8a7a5a", "#6d5e45", "#e8d44d"], 0.1),
    "sweepa": ("quadruped", ["#b8d8e8", "#96b8c9", "#f5eee0"], 0.3),
    "swee": ("blob", ["#c8e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "wumpo": ("cow", ["#a8b8c9", "#8899aa", "#f5eee0"], 0.15),
    "sibelyx": ("quadruped", ["#d8d8e8", "#b8b8d1", "#8fd1e8"], 0.25),
    "reindrix": ("deer", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.2),
    "frostallion": ("deer", ["#8fc9e8", "#6aa8c9", "#f5eee0"], 0.1),
    "mau_cryst": ("kitty", ["#a8d8e8", "#85b8c9", "#e8f5fa"], 0.25),
    "hangyu": ("ghost", ["#8fb8a8", "#6d9685", "#f5eee0"], 0.3),
    "fuddler": ("mouse", ["#8a7a6a", "#6d5f52", "#d8b8a8"], 0.3),
    "digtoise": ("hedgehog", ["#a8885a", "#8a6d45", "#d8c9a0"], 0.15),
    "anubis": ("human", ["#5a5a8a", "#44446d", "#e8c9a0"], 0.1),
    "reptyro": ("quadruped", ["#8a6d5a", "#6d5443", "#d89a5a"], 0.15),
    "direhowl": ("quadruped", ["#8a8a9a", "#6d6d7d", "#f5eee0"], 0.15),
    "galeclaw": ("bird", ["#7a9db8", "#5d82a0", "#e8d44d"], 0.15),
    "cawgnito": ("bird", ["#5a5a6a", "#44445a", "#e8c98a"], 0.2),
    "robinquill": ("human", ["#7ab86a", "#5d9a4e", "#e8c9a0"], 0.15),
    "gorirat": ("monkey", ["#7a6a5a", "#5d5243", "#d8c9a0"], 0.2),
    "woolipop": ("hedgehog", ["#f5d8e8", "#d8b8c9", "#f5eee0"], 0.45),
    "melpaca": ("quadruped", ["#e8b8c9", "#c998ad", "#f5eee0"], 0.3),
    "vixy": ("kitty", ["#e8c9a8", "#c9a888", "#f5eee0"], 0.35),
    "lovander": ("human", ["#d88aa8", "#b86a8a", "#f5eee0"], 0.2),
    "loupmoon": ("quadruped", ["#5a5a7a", "#43435e", "#c9d8e8"], 0.15),
    "hoocrates": ("human", ["#7a6a8a", "#5d526d", "#e8d44d"], 0.2),
    "killamari": ("ghost", ["#8a7ad1", "#6d5eb0", "#f5eee0"], 0.25),
    "lunaris": ("human", ["#8aa8d1", "#6a85b0", "#f5eee0"], 0.2),
    "nox": ("ghost", ["#8a6a9a", "#6d517d", "#f5eee0"], 0.3),
    "maraith": ("ghost", ["#6a8a7a", "#526d5e", "#c9e8d8"], 0.25),
    "catress": ("kitty", ["#9a7ab8", "#7d5e9a", "#e8d44d"], 0.25),
    "wixen": ("human", ["#b87a9a", "#96587d", "#f5eee0"], 0.2),
    "menasting": ("human", ["#4a3a5a", "#3a2d47", "#e8d44d"], 0.1),
    "shadowbeak": ("bird", ["#5a4a7a", "#443761", "#e8452f"], 0.1),
    "necromus": ("human", ["#6a5a7a", "#53455e", "#e8452f"], 0.1),
    "helzephyr": ("bird", ["#6a5a8a", "#53456d", "#a8d8e8"], 0.15),
    "tombat": ("blob", ["#8a7a9a", "#6d5f7d", "#d8c9a0"], 0.25),
    "jetragon": ("bird", ["#5a8ad1", "#4370b0", "#e8d44d"], 0.1),
    "paladius": ("human", ["#d8d8e8", "#b8b8d1", "#e8c9a0"], 0.1),
    "quivern": ("bird", ["#8a9ad1", "#6a7cb0", "#f5eee0"], 0.15),
    "astegon": ("quadruped", ["#4a4a6a", "#383853", "#e8452f"], 0.1),
    "elphidran": ("quadruped", ["#a8c9e8", "#85a8c9", "#f5eee0"], 0.15),
    "blazequil": ("hedgehog", ["#e88a4a", "#c96d2f", "#ffd76e"], 0.3),
    "hydrostar": ("blob", ["#5ac9d1", "#42a8b0", "#f5eee0"], 0.3),
    "stormpuff": ("ghost", ["#8ad1e8", "#68b0c9", "#e8d44d"], 0.3),
    "emberwing": ("bird", ["#e8a85a", "#c98542", "#3a3a4a"], 0.2),
    "mirelurk": ("hedgehog", ["#6a8a5a", "#526d45", "#d8c9a0"], 0.2),
    "frostbun": ("mouse", ["#c9e8f5", "#a5c9d8", "#f5eee0"], 0.4),
    "thornite": ("hedgehog", ["#7a8a6a", "#5e6d52", "#c9b88a"], 0.2),
    "dreadmaw": ("serpent", ["#5a4a6a", "#453a53", "#e8452f"], 0.1),
    "glimmora": ("ghost", ["#c9d8a8", "#a8b885", "#e8d44d"], 0.3),
    "cragboar": ("boar", ["#8a7a6a", "#6d5f52", "#d8c9a0"], 0.15),
    "vapori": ("ghost", ["#a8e8d8", "#85c9b8", "#f5eee0"], 0.35),
    "bombird": ("bird", ["#9a6a4a", "#7d523a", "#e8734a"], 0.15),
})

if __name__ == "__main__":
    print("generating pals…")
    for sid in SPRITES:
        render_pal(sid)
    print("generating atlas…")
    atlas()
    print("generating decor…")
    decor()
    print("generating structures…")
    for sid, (col, w, h) in STRUCT_DEFS.items():
        make_structure(sid, col, w, h)
    shadow()
    element_orbs()
    print("done")
