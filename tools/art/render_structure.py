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
    bpy.ops.object.transform_apply(scale=True)
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
