# Blender script: build a structure procedurally and render it into a
# 512x512 RGBA frame — same upright 3/4 camera and light rig as
# render_decor.py. post_structure.py posts it to the shipped dims.
#
#   blender --factory-startup -b -P render_structure.py -- <struct_id>
#
# Output: tools/art/render/struct_<id>_f0.png

import bpy
import math
import mathutils
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# id -> builder kind, world height, camera ortho/track, rot_z
CFG = {
    "kinbox":       {"build": "kinbox",      "h": 2.2, "ortho": 2.8, "tz": 1.0},
    "campfire":     {"build": "campfire",    "h": 0.9, "ortho": 1.5, "tz": 0.4},
    "workbench":    {"build": "workbench",   "h": 1.1, "ortho": 1.7, "tz": 0.5},
    "well":         {"build": "well",        "h": 1.4, "ortho": 1.9, "tz": 0.6},
    "torch":        {"build": "torch",       "h": 1.3, "ortho": 1.8, "tz": 0.6},
    "waypoint":     {"build": "waypoint",    "h": 1.5, "ortho": 2.0, "tz": 0.7},
    "chest":        {"build": "chest",       "h": 0.7, "ortho": 1.3, "tz": 0.3},
    "feed_box":     {"build": "feed_box",    "h": 0.7, "ortho": 1.4, "tz": 0.3},
    "kin_bed":      {"build": "bed",         "h": 0.6, "ortho": 1.5, "tz": 0.3},
    "wooden_wall":  {"build": "log_wall",    "h": 1.2, "ortho": 1.7, "tz": 0.5},
    "watch_tower":  {"build": "watch_tower", "h": 2.4, "ortho": 3.0, "tz": 1.1},
    "notice_board": {"build": "notice_board","h": 1.4, "ortho": 1.9, "tz": 0.6},
    # batch 2 — production machines
    "furnace":      {"build": "furnace",     "h": 1.5, "ortho": 2.2, "tz": 0.7},
    "generator":    {"build": "generator",   "h": 1.4, "ortho": 2.1, "tz": 0.6},
    "crusher":      {"build": "crusher",     "h": 1.5, "ortho": 2.2, "tz": 0.7},
    "mill":         {"build": "mill",        "h": 1.8, "ortho": 2.5, "tz": 0.8},
    "incubator":    {"build": "incubator",   "h": 1.3, "ortho": 2.0, "tz": 0.6},
    "ore_mine":     {"build": "ore_mine",    "h": 1.3, "ortho": 2.0, "tz": 0.6},
    "logging_site": {"build": "logging_site","h": 0.9, "ortho": 1.8, "tz": 0.4},
    "stone_pit":    {"build": "stone_pit",   "h": 0.9, "ortho": 1.8, "tz": 0.4},
    "gathering_site":{"build": "gathering",  "h": 1.0, "ortho": 1.8, "tz": 0.5},
    "spikes":       {"build": "spikes",      "h": 0.6, "ortho": 1.3, "tz": 0.3},
    "cooler":       {"build": "cooler",      "h": 0.9, "ortho": 1.5, "tz": 0.4},
    "kin_condenser":{"build": "kin_condenser","h": 1.5, "ortho": 2.1, "tz": 0.7},
    # batch 3 — farms / defense / misc
    "berry_farm":   {"build": "berry_farm",  "h": 0.7, "ortho": 2.4, "tz": 0.35},
    "wheat_farm":   {"build": "wheat_farm",  "h": 0.7, "ortho": 2.4, "tz": 0.35},
    "ranch":        {"build": "ranch",       "h": 1.1, "ortho": 3.4, "tz": 0.5},
    "straw_bed":    {"build": "straw_bed",   "h": 0.5, "ortho": 1.4, "tz": 0.25},
    "hot_spring":   {"build": "hot_spring",  "h": 0.8, "ortho": 2.2, "tz": 0.4},
    "fish_trap":    {"build": "fish_trap",   "h": 0.7, "ortho": 1.4, "tz": 0.35},
    "snare_trap":   {"build": "snare_trap",  "h": 0.5, "ortho": 1.3, "tz": 0.25},
    "kin_cage":     {"build": "kin_cage",    "h": 1.3, "ortho": 1.9, "tz": 0.6},
    "guard_post":   {"build": "guard_post",  "h": 1.6, "ortho": 2.1, "tz": 0.7},
    "training_hall":{"build": "training_hall","h": 1.5, "ortho": 2.6, "tz": 0.7},
    "sparring_ring":{"build": "sparring",    "h": 1.0, "ortho": 2.4, "tz": 0.5},
    "training_dummy":{"build": "dummy",      "h": 1.4, "ortho": 1.9, "tz": 0.65},
    "war_banner":   {"build": "war_banner",  "h": 1.7, "ortho": 2.2, "tz": 0.8},
    "monitoring_stand":{"build": "monitor",  "h": 1.5, "ortho": 2.0, "tz": 0.7},
}

WOOD = (0.45, 0.32, 0.20)
WOOD_D = (0.32, 0.22, 0.13)
STONE = (0.55, 0.55, 0.62)
IRON = (0.35, 0.38, 0.44)


def mat(rgb, name, emit=0.0, rough=0.9):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb[:3], 1.0)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb[:3], 1.0)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Specular IOR Level"].default_value = 0.12
    if emit > 0:
        bs.inputs["Emission Color"].default_value = (*rgb[:3], 1.0)
        bs.inputs["Emission Strength"].default_value = emit
    return m


def cube(name, loc, scale, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(material)
    # bake scale ONLY — the default applies location too, zeroing the
    # object origin so any later rotation_euler orbits the world origin
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth_by_angle()
    return o


def cyl(name, loc, r, h, material, verts=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h, location=loc)
    bpy.context.active_object.data.materials.append(material)
    return bpy.context.active_object


def cone(name, loc, r, h, material, verts=8):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0,
                                    depth=h, location=loc)
    bpy.context.active_object.data.materials.append(material)
    return bpy.context.active_object


def ico(name, loc, r, material, sub=2, sz=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=r, location=loc)
    o = bpy.context.active_object
    o.scale.z = sz
    o.data.materials.append(material)
    return o


def roof_prism(name, loc, w, d, h, material):
    """Triangular prism roof: ridge along x."""
    x0, y0, z = loc
    v = [(x0 - w / 2, y0 - d / 2, z), (x0 + w / 2, y0 - d / 2, z),
         (x0 + w / 2, y0 + d / 2, z), (x0 - w / 2, y0 + d / 2, z),
         (x0 - w / 2, y0, z + h), (x0 + w / 2, y0, z + h)]
    f = [(0, 1, 5, 4), (3, 2, 5, 4), (0, 3, 4), (1, 2, 5), (0, 1, 2, 3)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(v, [], f)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob


def build(kind, cfg):
    w = mat(WOOD, "wood"); wd = mat(WOOD_D, "wood_d")
    st = mat(STONE, "stone"); ir = mat(IRON, "iron")
    if kind == "kinbox":
        cyl("plinth", (0, 0, 0.5), 0.55, 1.0, st, 12)
        cyl("cap", (0, 0, 1.02), 0.62, 0.08, ir, 12)
        orb = mat((0.30, 0.82, 0.88), "orb", emit=1.8)
        ico("orb", (0, 0, 1.45), 0.34, orb, 3)
        cyl("ring", (0, 0, 1.18), 0.20, 0.10, ir, 10)
    elif kind == "campfire":
        for i in range(8):
            a = i * math.tau / 8
            ico("stone", (math.cos(a) * 0.30, math.sin(a) * 0.30, 0.05), 0.07, st, 1, 0.7)
        for i, a in enumerate((0.4, 1.9, 3.4)):
            o = cyl("log", (math.cos(a) * 0.05, math.sin(a) * 0.05, 0.16), 0.035, 0.4, wd, 6)
            o.rotation_euler = (math.radians(35), 0, a)
        fl = mat((0.95, 0.50, 0.12), "flame", emit=2.5)
        cone("flame", (0, 0, 0.30), 0.12, 0.42, fl, 8)
        fl2 = mat((1.0, 0.80, 0.30), "flame_hi", emit=3.0)
        cone("flame2", (0, 0, 0.30), 0.07, 0.30, fl2, 6)
    elif kind == "workbench":
        cube("top", (0, 0, 0.55), (0.85, 0.45, 0.08), w)
        for sx, sy in ((-0.75, -0.35), (0.75, -0.35), (-0.75, 0.35), (0.75, 0.35)):
            cube("leg", (sx / 2, sy / 2, 0.28), (0.09, 0.09, 0.55), wd)
        cube("vise", (0.28, -0.18, 0.65), (0.16, 0.10, 0.12), ir)
        cyl("saw", (-0.15, 0.05, 0.66), 0.10, 0.02, ir, 12)
    elif kind == "well":
        cyl("wall", (0, 0, 0.30), 0.42, 0.60, st, 12)
        cyl("inner", (0, 0, 0.58), 0.34, 0.10, mat((0.10, 0.12, 0.18), "water_hole"), 12)
        for sx in (-0.4, 0.4):
            cube("post", (sx, 0, 0.95), (0.06, 0.06, 0.8), wd)
        roof_prism("roof", (0, 0, 1.30), 1.15, 0.9, 0.32, w)
        cyl("bar", (0, 0, 1.10), 0.04, 0.75, wd, 6).rotation_euler.y = math.radians(90)
        cyl("rope", (0, 0, 0.85), 0.015, 0.45, mat((0.55, 0.48, 0.38), "rope"), 6)
        cube("bucket", (0, 0, 0.62), (0.14, 0.14, 0.16), wd)
    elif kind == "torch":
        cyl("pole", (0, 0, 0.55), 0.05, 1.10, wd, 6)
        cyl("cup", (0, 0, 1.12), 0.10, 0.14, ir, 8)
        fl = mat((0.95, 0.50, 0.12), "flame", emit=2.5)
        cone("flame", (0, 0, 1.32), 0.10, 0.30, fl, 8)
        fl2 = mat((1.0, 0.80, 0.30), "flame_hi", emit=3.0)
        cone("flame2", (0, 0, 1.30), 0.06, 0.20, fl2, 6)
    elif kind == "waypoint":
        cyl("base", (0, 0, 0.12), 0.35, 0.24, st, 8)
        cyl("plinth", (0, 0, 0.42), 0.16, 0.40, st, 8)
        cry = mat((0.45, 0.75, 0.98), "crystal", emit=2.0)
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.16, radius2=0.0,
                                        depth=0.65, location=(0, 0, 0.95))
        bpy.context.active_object.data.materials.append(cry)
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.16, radius2=0.0,
                                        depth=0.30, location=(0, 0, 0.75))
        bpy.context.active_object.rotation_euler.x = math.pi
        bpy.context.active_object.data.materials.append(cry)
    elif kind == "chest":
        cube("box", (0, 0, 0.24), (0.70, 0.45, 0.45), w)
        cube("lid", (0, 0, 0.50), (0.72, 0.47, 0.14), wd)
        cube("strap", (0, -0.01, 0.30), (0.74, 0.05, 0.50), ir)
        cube("clasp", (0, -0.24, 0.44), (0.10, 0.04, 0.14), mat((0.85, 0.75, 0.30), "brass"))
    elif kind == "feed_box":
        cube("front", (0, -0.28, 0.18), (0.75, 0.06, 0.36), w)
        cube("back", (0, 0.28, 0.18), (0.75, 0.06, 0.36), w)
        for sx in (-0.36, 0.36):
            cube("side", (sx, 0, 0.18), (0.06, 0.50, 0.36), w)
        cube("feed", (0, 0, 0.28), (0.68, 0.48, 0.14), mat((0.75, 0.62, 0.30), "feed"))
    elif kind == "bed":
        cube("frame", (0, 0, 0.18), (1.0, 0.55, 0.16), wd)
        cube("mat", (0, 0, 0.30), (0.94, 0.50, 0.12), mat((0.90, 0.82, 0.60), "straw"))
        cube("pillow", (-0.35, 0, 0.36), (0.22, 0.40, 0.09), mat((0.95, 0.92, 0.80), "pillow"))
    elif kind == "log_wall":
        for sx in (-0.42, 0.42):
            cyl("post", (sx, 0, 0.60), 0.07, 1.20, wd, 8)
        for i in range(3):
            o = cyl("log", (0, 0, 0.25 + i * 0.33), 0.10, 0.95, w, 8)
            o.rotation_euler.y = math.radians(90)
    elif kind == "watch_tower":
        for sx, sy in ((-0.35, -0.35), (0.35, -0.35), (-0.35, 0.35), (0.35, 0.35)):
            o = cyl("leg", (sx, sy, 0.9), 0.06, 1.8, wd, 6)
            o.rotation_euler.x = math.radians(4 * (-1 if sy < 0 else 1))
        cube("deck", (0, 0, 1.85), (0.95, 0.95, 0.08), w)
        for sx in (-0.42, 0.42):
            cube("rail", (sx, 0, 2.0), (0.05, 0.9, 0.20), w)
        for sy in (-0.42, 0.42):
            cube("rail", (0, sy, 2.0), (0.9, 0.05, 0.20), w)
        roof_prism("roof", (0, 0, 2.15), 1.15, 1.15, 0.35, wd)
        for sx, sy in ((-0.42, -0.42), (0.42, -0.42), (-0.42, 0.42), (0.42, 0.42)):
            cube("rpost", (sx, sy, 2.12), (0.05, 0.05, 0.30), wd)
    elif kind == "notice_board":
        for sx in (-0.42, 0.42):
            cyl("post", (sx, 0, 0.70), 0.05, 1.40, wd, 8)
        cube("board", (0, 0, 0.95), (0.95, 0.06, 0.55), w)
        cube("note", (-0.18, -0.035, 0.98), (0.22, 0.015, 0.26), mat((0.93, 0.89, 0.75), "paper"))
        cube("note2", (0.20, -0.035, 0.92), (0.18, 0.015, 0.20), mat((0.88, 0.85, 0.70), "paper2"))
    elif kind == "furnace":
        cyl("body", (0, 0, 0.65), 0.55, 1.30, st, 10)
        cyl("chimney", (0.15, 0.15, 1.35), 0.18, 0.35, ir, 8)
        cube("mouth", (0, -0.52, 0.35), (0.34, 0.10, 0.34), mat((0.08, 0.08, 0.10), "dark"))
        fire = mat((0.95, 0.45, 0.10), "fire", emit=2.2)
        cube("fire", (0, -0.50, 0.35), (0.24, 0.06, 0.24), fire)
        cyl("rim", (0, 0, 1.32), 0.58, 0.10, ir, 10)
    elif kind == "generator":
        cube("base", (0, 0, 0.30), (0.9, 0.7, 0.55), ir)
        cyl("coil", (0, 0, 0.85), 0.28, 0.45, mat((0.75, 0.65, 0.20), "copper"), 10)
        bolt = mat((0.95, 0.85, 0.20), "spark", emit=2.0)
        for i, a in enumerate((0.0, 2.1, 4.2)):
            o = cone("rod", (math.cos(a) * 0.35, math.sin(a) * 0.35, 1.05),
                     0.04, 0.5, ir, 6)
        ico("orb", (0, 0, 1.35), 0.18, bolt, 2)
    elif kind == "crusher":
        cube("frame_l", (-0.45, 0, 0.6), (0.10, 0.6, 1.2), ir)
        cube("frame_r", (0.45, 0, 0.6), (0.10, 0.6, 1.2), ir)
        cyl("roller", (0, 0, 0.75), 0.30, 0.75, st, 10).rotation_euler.x = math.radians(90)
        for i in range(6):
            a = i * math.tau / 6
            ico("tooth", (math.cos(a) * 0.30, -0.01, 0.75 + math.sin(a) * 0.30), 0.05, ir, 1)
        cube("hopper", (0, 0, 1.12), (0.55, 0.55, 0.30), w)
    elif kind == "mill":
        cyl("tower", (0, 0, 0.55), 0.35, 1.10, st, 8)
        roof_prism("cap", (0, 0, 1.10), 0.85, 0.85, 0.30, wd)
        cyl("hub", (0, -0.44, 0.98), 0.09, 0.16, ir, 8).rotation_euler.x = math.radians(90)
        for i in range(4):
            a = i * math.tau / 4 + math.radians(45)
            o = cube("sail", (math.sin(a) * 0.26, -0.50, 0.98 + math.cos(a) * 0.26),
                     (0.12, 0.02, 0.55), mat((0.88, 0.82, 0.65), "sail"))
            o.rotation_euler.y = a
    elif kind == "incubator":
        cube("base", (0, 0, 0.25), (0.85, 0.65, 0.45), w)
        egg = mat((0.95, 0.80, 0.85), "egg")
        ico("egg", (0, 0, 0.75), 0.32, egg, 2, 1.25)
        glow = mat((0.95, 0.60, 0.65), "glow", emit=1.5)
        for sx in (-0.30, 0.30):
            cyl("lamp", (sx, 0.15, 0.90), 0.05, 0.35, glow, 6)
    elif kind == "ore_mine":
        for sx in (-0.5, 0.5):
            cube("post", (sx, 0, 0.55), (0.09, 0.09, 1.1), wd)
        cube("beam", (0, 0, 1.05), (1.15, 0.10, 0.12), wd)
        ico("ore1", (-0.2, -0.2, 0.18), 0.22, mat((0.72, 0.55, 0.30), "ore"), 1)
        ico("ore2", (0.25, -0.1, 0.14), 0.16, mat((0.80, 0.68, 0.38), "ore2"), 1)
        ico("rock", (0, 0.2, 0.20), 0.28, st, 1, 0.8)
        o = cyl("pick", (0.35, -0.3, 0.45), 0.03, 0.7, wd, 6)
        o.rotation_euler = (math.radians(30), 0, math.radians(-30))
    elif kind == "logging_site":
        for i in range(3):
            o = cyl("log", (-0.2 + i * 0.2, -0.1, 0.12 + i * 0.13), 0.12, 0.8, w, 8)
            o.rotation_euler.y = math.radians(90)
        ico("stump", (0.3, 0.25, 0.18), 0.20, wd, 1, 0.9)
        o = cube("axe", (0.3, 0.25, 0.5), (0.03, 0.03, 0.5), wd)
        o.rotation_euler.x = math.radians(25)
        cube("axehead", (0.3, 0.35, 0.68), (0.16, 0.03, 0.12), ir)
    elif kind == "stone_pit":
        for i, (x, y, r) in enumerate(((-0.25, -0.15, 0.25), (0.2, -0.2, 0.18),
                                       (0.0, 0.25, 0.30), (0.35, 0.15, 0.15))):
            ico("rock", (x, y, r * 0.7), r, st, 1, 0.75)
        cyl("post", (-0.45, 0.3, 0.4), 0.05, 0.8, wd, 6)
        o = cyl("pick", (-0.45, 0.25, 0.75), 0.025, 0.5, ir, 6)
        o.rotation_euler.x = math.radians(60)
    elif kind == "gathering":
        for i in range(5):
            a = i * math.tau / 5 + 0.3
            ico("bush", (math.cos(a) * 0.35, math.sin(a) * 0.35, 0.22),
                0.18, mat((0.35, 0.55, 0.25), "bush"), 1)
        for i in range(4):
            a = i * math.tau / 4 + 0.9
            ico("berry", (math.cos(a) * 0.38, math.sin(a) * 0.38, 0.32),
                0.05, mat((0.85, 0.25, 0.25), "berry"), 1)
        cyl("basket", (0, 0, 0.18), 0.16, 0.30, w, 8)
    elif kind == "spikes":
        cube("plate", (0, 0, 0.06), (0.85, 0.85, 0.10), wd)
        for x, y in ((-0.25, -0.25), (0.25, -0.25), (-0.25, 0.25), (0.25, 0.25), (0, 0)):
            cone("spike", (x, y, 0.30), 0.09, 0.45, mat((0.75, 0.72, 0.65), "spike"), 6)
    elif kind == "cooler":
        cube("box", (0, 0, 0.32), (0.65, 0.5, 0.60), mat((0.55, 0.80, 0.92), "cooler"))
        cube("lid", (0, 0, 0.65), (0.68, 0.53, 0.12), mat((0.85, 0.90, 0.95), "lid"))
        cube("latch", (0, -0.27, 0.55), (0.10, 0.04, 0.12), ir)
        for i in range(3):
            ico("frost", (-0.15 + i * 0.15, -0.20, 0.45), 0.05,
                mat((0.85, 0.95, 1.0), "frost"), 1)
    elif kind == "kin_condenser":
        cyl("tank", (0, 0, 0.65), 0.40, 1.20, ir, 10)
        ico("core", (0, -0.05, 0.65), 0.28, mat((0.55, 0.40, 0.90), "core", emit=1.6), 2)
        cyl("cap", (0, 0, 1.28), 0.42, 0.10, w, 10)
        cyl("cap2", (0, 0, 0.08), 0.44, 0.16, w, 10)
        for sx in (-0.35, 0.35):
            cyl("pipe", (sx, 0.25, 0.9), 0.05, 0.6, ir, 6).rotation_euler.x = math.radians(20)
    elif kind == "berry_farm":
        cube("soil", (0, 0, 0.08), (1.7, 1.1, 0.14), mat((0.30, 0.20, 0.12), "soil"))
        for i in range(6):
            x = -0.6 + (i % 3) * 0.6; y = -0.3 + (i // 3) * 0.6
            ico("bush", (x, y, 0.30), 0.22, mat((0.32, 0.52, 0.24), "bush"), 1)
            for j in range(3):
                a = j * 2.1 + i
                ico("berry", (x + math.cos(a) * 0.16, y + math.sin(a) * 0.10, 0.38),
                    0.05, mat((0.85, 0.25, 0.25), "berry"), 1)
    elif kind == "wheat_farm":
        cube("soil", (0, 0, 0.08), (1.7, 1.1, 0.14), mat((0.32, 0.24, 0.14), "soil"))
        wheat = mat((0.85, 0.70, 0.30), "wheat")
        for i in range(12):
            x = -0.65 + (i % 4) * 0.43; y = -0.35 + (i // 4) * 0.35
            cone("wheat", (x, y, 0.35), 0.07, 0.55, wheat, 5)
    elif kind == "ranch":
        for x, y in ((-1.4, -0.9), (0, -0.9), (1.4, -0.9), (-1.4, 0.9),
                     (0, 0.9), (1.4, 0.9), (-1.4, 0), (1.4, 0)):
            cyl("post", (x, y, 0.35), 0.06, 0.70, wd, 6)
        for y in (-0.9, 0.9):
            for z in (0.30, 0.55):
                o = cyl("rail", (0, y, z), 0.04, 2.9, w, 6)
                o.rotation_euler.y = math.radians(90)
        for x in (-1.4, 1.4):
            for z in (0.30, 0.55):
                o = cyl("rail", (x, 0, z), 0.04, 1.9, w, 6)
                o.rotation_euler.x = math.radians(90)
        ico("hay", (0.6, 0.3, 0.25), 0.28, mat((0.85, 0.72, 0.35), "hay"), 1)
    elif kind == "straw_bed":
        cube("mat", (0, 0, 0.14), (0.95, 0.55, 0.22), mat((0.82, 0.70, 0.40), "straw"))
        for i in range(6):
            a = i * 1.1
            ico("tuft", (math.cos(a) * 0.35, math.sin(a) * 0.2, 0.28), 0.07,
                mat((0.88, 0.78, 0.45), "tuft"), 1)
    elif kind == "hot_spring":
        cyl("rim", (0, 0, 0.28), 0.75, 0.55, st, 12)
        cyl("water", (0, 0, 0.52), 0.62, 0.10, mat((0.45, 0.75, 0.90), "water"), 12)
        steam = mat((0.9, 0.9, 0.95), "steam", emit=0.6)
        for x in (-0.25, 0.1, 0.3):
            ico("steam", (x, 0, 0.85), 0.12, steam, 1, 1.6)
    elif kind == "fish_trap":
        cone("basket", (0, 0, 0.35), 0.35, 0.65, w, 10)
        bpy.context.active_object.rotation_euler.x = math.pi
        cyl("hoop", (0, 0, 0.06), 0.38, 0.06, wd, 10)
        for i in range(6):
            a = i * math.tau / 6
            o = cyl("rib", (math.cos(a) * 0.19, math.sin(a) * 0.19, 0.33), 0.02, 0.6, wd, 5)
            o.rotation_euler = (math.cos(a) * 0.5, math.sin(a) * 0.5, 0)
    elif kind == "snare_trap":
        cube("plate", (0, 0, 0.04), (0.7, 0.7, 0.07), wd)
        bpy.ops.mesh.primitive_torus_add(major_radius=0.22, minor_radius=0.03,
                                         major_segments=10, minor_segments=6,
                                         location=(0, 0, 0.12))
        bpy.context.active_object.data.materials.append(ir)
        for i in range(4):
            a = i * math.tau / 4 + 0.4
            o = cyl("stick", (math.cos(a) * 0.25, math.sin(a) * 0.25, 0.16),
                    0.02, 0.3, w, 5)
            o.rotation_euler = (math.cos(a) * 0.6, math.sin(a) * 0.6, 0)
    elif kind == "kin_cage":
        cube("floor", (0, 0, 0.06), (0.9, 0.9, 0.10), wd)
        for sx in (-0.42, 0.42):
            for sy in (-0.42, 0.42):
                cyl("corner", (sx, sy, 0.65), 0.04, 1.25, ir, 6)
        for i in range(4):
            a = i * math.tau / 4 + math.tau / 8
            for sx in (-0.2, 0.0, 0.2):
                x = math.cos(a) * 0.42 - math.sin(a) * sx
                y = math.sin(a) * 0.42 + math.cos(a) * sx
                cyl("bar", (x, y, 0.65), 0.02, 1.15, ir, 5)
        cube("top", (0, 0, 1.30), (0.9, 0.9, 0.08), wd)
    elif kind == "guard_post":
        cyl("pole", (0, 0, 0.7), 0.07, 1.4, wd, 8)
        cube("deck", (0, 0, 1.35), (0.5, 0.5, 0.08), w)
        cube("hut", (0, 0, 1.55), (0.4, 0.35, 0.32), w)
        roof_prism("roof", (0, 0, 1.72), 0.55, 0.5, 0.18, wd)
        spear = cyl("spear", (0.28, -0.1, 0.9), 0.025, 1.4, ir, 6)
        spear.rotation_euler.x = math.radians(8)
    elif kind == "training_hall":
        for sx in (-0.8, 0.8):
            for sy in (-0.5, 0.5):
                cyl("post", (sx, sy, 0.75), 0.07, 1.5, wd, 8)
        roof_prism("roof", (0, 0, 1.55), 1.9, 1.3, 0.35, w)
        cube("mat", (0, 0, 0.05), (1.6, 1.0, 0.08), mat((0.72, 0.55, 0.35), "mat"))
        cyl("dummy", (0.4, 0.1, 0.45), 0.14, 0.8, mat((0.75, 0.60, 0.35), "dum"), 8)
        ico("dhead", (0.4, 0.1, 0.95), 0.16, mat((0.75, 0.60, 0.35), "dum2"), 1)
    elif kind == "sparring":
        cyl("ring", (0, 0, 0.06), 0.85, 0.10, mat((0.72, 0.55, 0.35), "ring"), 14)
        for i in range(8):
            a = i * math.tau / 8
            cyl("post", (math.cos(a) * 0.85, math.sin(a) * 0.85, 0.30), 0.04, 0.5, wd, 6)
        for z in (0.35, 0.5):
            bpy.ops.mesh.primitive_torus_add(major_radius=0.85, minor_radius=0.02,
                                             major_segments=14, minor_segments=5,
                                             location=(0, 0, z))
            bpy.context.active_object.data.materials.append(
                mat((0.75, 0.30, 0.25), "rope"))
    elif kind == "dummy":
        cyl("post", (0, 0, 0.45), 0.07, 0.9, wd, 8)
        cyl("body", (0, 0, 0.85), 0.22, 0.7, mat((0.78, 0.62, 0.38), "straw_d"), 8)
        ico("head", (0, 0, 1.30), 0.20, mat((0.78, 0.62, 0.38), "straw_h"), 1)
        o = cyl("arm", (0, 0, 1.0), 0.04, 0.9, wd, 6)
        o.rotation_euler.y = math.radians(90)
        cube("target", (0, -0.23, 0.85), (0.20, 0.02, 0.20),
             mat((0.85, 0.30, 0.25), "target"))
    elif kind == "war_banner":
        cyl("pole", (0, 0, 0.85), 0.05, 1.7, wd, 8)
        ico("finial", (0, 0, 1.75), 0.08, mat((0.85, 0.72, 0.30), "brass"), 1)
        cube("banner", (0.28, 0, 1.35), (0.5, 0.02, 0.6),
             mat((0.72, 0.22, 0.20), "banner"))
        cube("sigil", (0.28, -0.015, 1.35), (0.20, 0.01, 0.20),
             mat((0.92, 0.85, 0.60), "sigil"))
    elif kind == "monitor":
        cube("deck", (0, 0, 0.9), (0.6, 0.5, 0.07), w)
        for sx, sy in ((-0.25, -0.2), (0.25, -0.2), (-0.25, 0.2), (0.25, 0.2)):
            cyl("leg", (sx, sy, 0.45), 0.045, 0.9, wd, 6)
        cyl("scope", (0, -0.15, 1.1), 0.07, 0.4, ir, 8).rotation_euler.x = math.radians(75)
        cube("board", (0.2, 0.1, 1.05), (0.25, 0.02, 0.2), mat((0.93, 0.89, 0.75), "note"))


def main():
    sid = sys.argv[-1]
    cfg = CFG[sid]

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)

    build(cfg["build"], cfg)

    # kin light rig (identical across all art pipelines)
    bpy.ops.object.light_add(type='AREA', location=(-3.4, -4.2, 5.5))
    key = bpy.context.active_object
    key.data.energy = 900
    key.data.size = 4.0
    key.data.color = (1.0, 0.93, 0.82)
    bpy.ops.object.light_add(type='AREA', location=(3.5, 1.5, 3.0))
    fill = bpy.context.active_object
    fill.data.energy = 260
    fill.data.size = 5.0
    fill.data.color = (0.62, 0.68, 1.0)
    world = bpy.context.scene.world or bpy.data.worlds.new("W")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.55, 0.62, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.35

    # same upright 3/4 camera as decor
    bpy.ops.object.camera_add(location=(3.6, -5.6, 2.9))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, cfg.get("tz", 0.5))
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = cfg.get("ortho", 2.0)
    s = bpy.context.scene
    s.camera = cam

    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = 512
    s.render.resolution_y = 512
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "struct_%s_f0.png" % sid)
    bpy.ops.render.render(write_still=True)
    print("rendered struct", sid)


main()
