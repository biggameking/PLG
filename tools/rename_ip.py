#!/usr/bin/env python3
# S1 IP de-risk: rename every Palworld-derived species id + display name,
# replace the "pal" product lexicon (palbox/paldeck/pal sphere/paldium/pal egg),
# scrub "Palworld"/"Palapagos" from comments+strings, rename asset files,
# and emit src/data/migrate.gd so old saves load under the new ids.
import re, os, json, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---------- 1. species metadata ----------
def load_meta():
    out = {}
    for f in ['src/data/species_gen.gd', 'src/data/species.gd']:
        src = open(os.path.join(ROOT, f)).read()
        m = re.search(r'const SPECIES = \{(.*?)\nconst |const SPECIES = \{(.*?)\Z', src, re.S)
        seg = m.group(1) or m.group(2)
        for mm in re.finditer(r'"([a-z_0-9]+)":\s*\{(.*?)\n \}', seg, re.S):
            sid, body = mm.group(1), mm.group(2)
            el = re.search(r'"elements":\s*\[\s*"([a-z]+)"', body)
            bd = re.search(r'"body":\s*"([a-z]+)"', body)
            nm = re.search(r'"name":\s*"([^"]+)"', body)
            out[sid] = {"el": el.group(1) if el else "neutral",
                        "bd": bd.group(1) if bd else "blob",
                        "name": nm.group(1) if nm else sid}
    return out

PRE = {"neutral": ["Puff", "Nib", "Taw", "Mim", "Doz", "Pip", "Tam", "Fen", "Bram", "Hush"],
       "fire": ["Pyre", "Emb", "Cind", "Flar", "Soot", "Bran", "Sol", "Scal"],
       "water": ["Mar", "Bub", "Corl", "Tid", "Rip", "Laz", "Dew", "Brin"],
       "grass": ["Fern", "Moss", "Petal", "Thorn", "Leaf", "Briar", "Sprig", "Wort"],
       "electric": ["Volt", "Spark", "Zap", "Thun", "Jolt", "Stat", "Farad"],
       "ice": ["Frost", "Glac", "Snow", "Chil", "Rime", "Brr", "Snov"],
       "ground": ["Terr", "Dig", "Crag", "Dust", "Loam", "Flint", "Grit"],
       "dark": ["Noct", "Umbr", "Shade", "Murk", "Dusk", "Grim", "Veil"],
       "dragon": ["Drak", "Wyrm", "Scal", "Verm", "Glaed", "Ryuj"]}
SUF = {"quadruped": ["paw", "hoof", "trot", "mane", "fang"],
       "bird": ["wing", "beak", "plume", "talon", "crest"],
       "blob": ["melt", "lump", "jelly", "mite", "puff", "goo"],
       "serpent": ["coil", "fang", "scale", "writh"],
       "human": ["kin", "ling", "hand", "smith"],
       "mouse": ["squeak", "whisk", "nib"],
       "kitty": ["purr", "whisk", "tail"],
       "deer": ["antler", "fawn", "stride"],
       "boar": ["tusk", "snout", "brist"],
       "cow": ["mool", "chew", "bell"],
       "monkey": ["tail", "palm", "chim"],
       "hedgehog": ["spike", "quill", "burr"],
       "ghost": ["wisp", "veil", "haunt", "gloom"]}

def h(s):
    v = 0
    for c in s:
        v = (v * 131 + ord(c)) & 0xFFFFFFFF
    return v

def new_id(sid, meta, used):
    if sid.startswith("syndicate_"):
        return "ironpact_" + sid.split("_", 1)[1]
    pre = PRE.get(meta["el"], PRE["neutral"])
    suf = SUF.get(meta["bd"], SUF["blob"])
    n = pre[h(sid) % len(pre)] + suf[(h(sid) >> 8) % len(suf)]
    cand = n.lower()
    salt = 2
    while cand in used or cand == sid:
        cand = (n + str(salt)).lower()
        salt += 1
    used.add(cand)
    return cand

meta = load_meta()
used = set()
RENAME_IDS = {}
for sid in sorted(meta):
    # skip ids that are already non-infringing internal species we keep? No — uniform rename.
    if sid in ("farm", "work"):
        continue
    RENAME_IDS[sid] = new_id(sid, meta[sid], used)

# ---------- 2. term ids (items / structures) ----------
TERM_IDS = {
    "palbox": "kinbox", "pal_bed": "kin_bed", "pal_cage": "kin_cage",
    "pal_condenser": "kin_condenser", "pal_gacha": "kin_gacha",
    "pal_egg": "kin_egg", "huge_pal_egg": "huge_kin_egg",
    "paldium": "lumenite",
    "pal_sphere": "kin_orb", "mega_sphere": "mega_orb", "giga_sphere": "giga_orb",
    "ultra_sphere": "ultra_orb", "legendary_sphere": "legendary_orb",
    "sphere_launcher": "orb_launcher",
}
# item/gear ids that embed a species id (lifmunk_effigy, foxparks_harness, ...)
for sid, nid in RENAME_IDS.items():
    for tail in ["_effigy", "_harness", "_smg", "_rifle", "_launcher"]:
        TERM_IDS[sid + tail] = RENAME_IDS[sid] + tail

IDS = dict(TERM_IDS); IDS.update(RENAME_IDS)  # species wins on overlap
# longer ids first so mau_cryst beats mau
ORDER = sorted(IDS, key=len, reverse=True)

# ---------- 3. display-name map ----------
NAMES = {}
for sid, m in meta.items():
    if sid in RENAME_IDS:
        NAMES[m["name"]] = RENAME_IDS[sid].replace("_", " ").title().replace(" ", "")
NAMES.update({
    "Palbox": "Kinbox", "Pal Box": "Kinbox", "Pal Bed": "Kin Bed",
    "Pal Cage": "Kin Cage", "Pal Condenser": "Kin Condenser", "Pal Gacha": "Kin Gacha",
    "Pal Sphere": "Kin Orb", "Mega Sphere": "Mega Orb", "Giga Sphere": "Giga Orb",
    "Ultra Sphere": "Ultra Orb", "Legendary Sphere": "Legendary Orb",
    "Sphere Launcher": "Orb Launcher",
    "Paldium": "Lumenite", "Paldium Fragment": "Lumenite Shard",
    "Pal Egg": "Kin Egg", "Huge Pal Egg": "Huge Kin Egg",
    "PALDECK": "KINDEX", "Paldeck": "Kindex", "paldeck": "kindex",
    "Palapagos": "the Wildmere",
    "Syndicate": "Iron Pact", "syndicate": "Iron Pact",
    "Rayne": "Iron Pact",
})
NAME_ORDER = sorted(NAMES, key=len, reverse=True)

# generic in-string lexicon: whole words only, inside string literals
LEX = [(r'\bpals\b', 'kin'), (r'\bPals\b', 'Kin'), (r'\bpal\b', 'kin'), (r'\bPal\b', 'Kin')]

# ---------- 4. text pass ----------
EXT = (".gd", ".ts", ".py", ".json", ".godot", ".cfg", ".import", ".md")
files = []
for dp, dn, fn in os.walk(ROOT):
    if ".git" in dp.split(os.sep) or ".godot" in dp.split(os.sep):
        continue
    for f in fn:
        if f.endswith(EXT) and f != "rename_ip.py":
            files.append(os.path.join(dp, f))

lit_re = re.compile(r'"([^"\n]*)"')
def lit_sub(s):
    # replace display names + lexicon inside "..." literals only
    def repl(m):
        t = m.group(1)
        for o in NAME_ORDER:
            if o in t:
                t = t.replace(o, NAMES[o])
        for pat, rep in LEX:
            t = re.sub(pat, rep, t)
        return '"' + t + '"'
    return lit_re.sub(repl, s)

changed = 0
for fp in files:
    src = open(fp, encoding="utf-8").read()
    out = src
    for o in ORDER:
        out = re.sub(r'\b' + re.escape(o) + r'\b', IDS[o], out)
    out = lit_sub(out)
    out = out.replace("Palworld's ", "").replace("Palworlds ", "")
    out = re.sub(r'\bPalworld\b', 'the island', out)
    if out != src:
        open(fp, "w", encoding="utf-8").write(out)
        changed += 1
print("text files changed:", changed, "of", len(files))

# ---------- 5. asset renames ----------
renamed = 0
for old, new in IDS.items():
    for pat in ["assets/pals/%s_f0.png", "assets/pals/%s_f1.png",
                "assets/pals/%s_f0.png.import", "assets/pals/%s_f1.png.import",
                "assets/structures/%s.png", "assets/structures/%s.png.import"]:
        op = os.path.join(ROOT, pat % old)
        np_ = os.path.join(ROOT, pat % new)
        if os.path.exists(op):
            subprocess.run(["git", "mv", op, np_], cwd=ROOT, check=False)
            if os.path.exists(op):  # git mv failed (untracked) — plain move
                os.rename(op, np_)
            renamed += 1
print("asset files renamed:", renamed)

# ---------- 6. save migration ----------
lines = ["class_name Migrate", "# S1 legacy save ids -> renamed ids (species/items/structures).",
         "const ID := {"]
for o in sorted(IDS):
    lines.append(' "%s": "%s",' % (o, IDS[o]))
lines += ["}", "", "static func rid(x) -> Variant:", "\treturn ID.get(str(x), x)", ""]
open(os.path.join(ROOT, "src/data/migrate.gd"), "w").write("\n".join(lines))
print("migrate.gd written:", len(IDS), "id mappings")

# ---------- 7. leftover report ----------
rest = []
for fp in files:
    src = open(fp, encoding="utf-8").read()
    for m in lit_re.finditer(src):
        t = m.group(1)
        if re.search(r'\b[Pp]al(s)?\b|\bpaldium\b|\bpaldeck\b|Palapagos', t):
            rest.append((fp.replace(ROOT + "/", ""), t[:80]))
print("leftover pal-strings:", len(rest))
for f, t in rest[:40]:
    print("  %s: %s" % (f, t))
