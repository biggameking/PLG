# Item kind icons — 12 silhouettes (11 kinds + relic for the kindless
# specials), same light rig / 3-4 ortho cam as the structure renderer.
#
#   blender -b --python render_item.py -- <kind>
#
# Output: tools/art/render/item_<kind>_f0.png  (512x512 RGBA)

import bpy
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# palette — same family as structure/decor so the icons sit in the world
WOOD = (0.55, 0.38, 0.24)
WOOD_D = (0.35, 0.23, 0.14)
STONE = (0.52, 0.50, 0.55)
IRON = (0.42, 0.45, 0.52)
GOLD = (0.85, 0.62, 0.20)
GEM = (0.30, 0.75, 0.80)
LEAF = (0.35, 0.62, 0.30)
LEAF_D = (0.22, 0.42, 0.20)
MEAT = (0.75, 0.45, 0.35)
CRUST = (0.72, 0.52, 0.28)
PAPER = (0.85, 0.82, 0.72)
RED = (0.72, 0.28, 0.26)

CFG = {
    "material": {"ortho": 1.5, "tz": 0.42},
    "food": {"ortho": 1.5, "tz": 0.42},
    "seed": {"ortho": 1.4, "tz": 0.42},
    "orb": {"ortho": 1.5, "tz": 0.5},
    "weapon": {"ortho": 1.7, "tz": 0.55},
    "ammo": {"ortho": 1.7, "tz": 0.55},
    "medicine": {"ortho": 1.5, "tz": 0.45},
    "gear": {"ortho": 1.7, "tz": 0.55},
    "fruit": {"ortho": 1.4, "tz": 0.45},
    "armor": {"ortho": 1.6, "tz": 0.5},
    "accessory": {"ortho": 1.4, "tz": 0.45},
    "relic": {"ortho": 1.4, "tz": 0.45},
}


def mat(rgb, name, emit=0.0, rough=0.9, metal=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb[:3], 1.0)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb[:3], 1.0)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Specular IOR Level"].default_value = 0.15
    bs.inputs["Metallic"].default_value = metal
    if emit > 0:
        bs.inputs["Emission Color"].default_value = (*rgb[:3], 1.0)
        bs.inputs["Emission Strength"].default_value = emit
    return m


def cube(name, loc, scale, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    o.data.materials.append(material)
    # bake scale ONLY — applying location zeroes the origin and any later
    # rotation orbits the world origin (the batch-2 mill bug, audit-56)
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


def torus(name, loc, R, r, material):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r,
                                     major_segments=20, minor_segments=8,
                                     location=loc)
    bpy.context.active_object.data.materials.append(material)
    return bpy.context.active_object


def rot(o, x=0.0, y=0.0, z=0.0):
    o.rotation_euler = (x, y, z)
    return o


def build(kind):
    w = mat(WOOD, "wood"); wd = mat(WOOD_D, "wood_d")
    st = mat(STONE, "stone"); ir = mat(IRON, "iron", metal=0.6, rough=0.5)
    gd = mat(GOLD, "gold", metal=0.7, rough=0.35)
    gm = mat(GEM, "gem", emit=0.35, rough=0.3)
    lf = mat(LEAF, "leaf"); lfd = mat(LEAF_D, "leaf_d")
    mt = mat(MEAT, "meat"); cr = mat(CRUST, "crust")
    pp = mat(PAPER, "paper"); rd = mat(RED, "red")

    if kind == "material":  # stacked logs + a stone block — the raw pile
        rot(cyl("log1", (-0.12, 0, 0.22), 0.13, 0.72, w), y=1.5708)
        rot(cyl("log2", (0.05, 0, 0.44), 0.13, 0.72, w), y=1.5708)
        cube("block", (0.28, -0.05, 0.16), (0.14, 0.14, 0.14), st)
    elif kind == "food":  # bowl + dome loaf
        cyl("bowl", (0, 0, 0.2), 0.34, 0.18, wd, verts=12)
        ico("loaf", (0, 0, 0.34), 0.26, cr, sz=0.75)
        cyl("stem", (0.16, 0, 0.52), 0.03, 0.14, lf)
    elif kind == "seed":  # sprout — stem + two leaves
        rot(cyl("stem", (0, 0, 0.3), 0.04, 0.5, lf), x=0.12)
        rot(ico("leafA", (0.14, 0, 0.5), 0.16, lf, sz=0.45), z=-0.7)
        rot(ico("leafB", (-0.13, 0.02, 0.42), 0.13, lfd, sz=0.45), z=0.7)
        ico("dirt", (0, 0, 0.08), 0.22, wd, sz=0.5)
    elif kind == "orb":  # capture sphere — banded ball
        ico("ball", (0, 0, 0.42), 0.3, pp, sz=1.0)
        rot(torus("band", (0, 0, 0.42), 0.3, 0.045, wd), x=1.5708)
        ico("btn", (0, -0.28, 0.42), 0.07, gm)
    elif kind == "weapon":  # sword, upright — the 3/4 cam does the angling.
        # cube scale is FULL size (unit cube) — halves live in the scale arg
        cube("blade", (0, 0, 0.58), (0.1, 0.035, 0.5), ir)
        rot(cone("tip", (0, 0, 0.9), 0.1, 0.14, ir, verts=4), z=0.7854)
        cube("guard", (0, 0, 0.32), (0.2, 0.05, 0.04), gd)
        cyl("grip", (0, 0, 0.16), 0.05, 0.26, wd)
        ico("pommel", (0, 0, 0.01), 0.065, gd)
    elif kind == "ammo":  # arrow, upright — shaft / head / fanned fletch
        cyl("shaft", (0, 0, 0.42), 0.03, 0.8, w)
        cone("tip", (0, 0, 0.9), 0.055, 0.16, ir, verts=6)
        fa = cube("fletchA", (0.05, 0, 0.1), (0.11, 0.02, 0.16), rd)
        fa.rotation_euler = (0, 0.5, 0)
        fb = cube("fletchB", (-0.05, 0, 0.1), (0.11, 0.02, 0.16), rd)
        fb.rotation_euler = (0, -0.5, 0)
    elif kind == "medicine":  # flask — body / neck / liquid glow
        ico("body", (0, 0, 0.26), 0.26, pp, sz=1.0)
        cyl("neck", (0, 0, 0.52), 0.08, 0.2, pp)
        ico("liquid", (0, 0, 0.2), 0.17, rd, sz=0.8)
        cyl("cork", (0, 0, 0.64), 0.09, 0.08, w)
    elif kind == "gear":  # pickaxe — handle + two-point head
        rot(cyl("handle", (0, 0, 0.4), 0.045, 0.85, w), x=0.35)
        h1 = cone("headA", (0.2, -0.14, 0.72), 0.09, 0.42, ir, verts=6)
        h1.rotation_euler = (0, 1.5708 - 0.3, 0)
        h2 = cone("headB", (-0.2, -0.14, 0.72), 0.09, 0.42, ir, verts=6)
        h2.rotation_euler = (0, -1.5708 + 0.3, 0)
    elif kind == "fruit":  # berry cluster — three drupelets + leaf
        ico("b1", (0.1, 0, 0.3), 0.16, rd)
        ico("b2", (-0.1, 0.02, 0.26), 0.14, rd)
        ico("b3", (0.01, 0, 0.44), 0.13, rd)
        cyl("stem", (0.05, 0, 0.58), 0.025, 0.12, lfd)
        rot(ico("leaf", (0.16, 0, 0.62), 0.11, lf, sz=0.4), z=-0.8)
    elif kind == "armor":  # shield — oval plate + gold boss, -Y face
        pl = ico("plate", (0, 0, 0.42), 0.34, st, sz=1.0)
        pl.scale = (0.85, 0.25, 1.0)
        rot(ico("boss", (0, -0.12, 0.44), 0.11, gd, sz=0.7), x=1.5708)
    elif kind == "accessory":  # ring + gem
        rot(torus("ring", (0, 0, 0.36), 0.24, 0.07, gd), x=0.35)
        ico("gem", (0, -0.06, 0.62), 0.12, gm)
    elif kind == "relic":  # egg — the kindless specials all hatch or glow
        ico("egg", (0, 0, 0.36), 0.28, pp, sz=1.3)
        torus("crack", (0, 0, 0.36), 0.28, 0.02, wd).scale.z = 1.3
    else:
        raise SystemExit("unknown kind %s" % kind)


def main():
    kind = sys.argv[-1] if len(sys.argv) > 1 else ""
    cfg = CFG.get(kind)
    if cfg is None:
        raise SystemExit("usage: render_item.py -- <%s>" % "|".join(CFG))

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)

    build(kind)

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

    bpy.ops.object.camera_add(location=(3.6, -5.6, 2.9))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, cfg.get("tz", 0.45))
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = cfg.get("ortho", 1.5)
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
    s.render.filepath = os.path.join(OUT, "item_%s_f0.png" % kind)
    bpy.ops.render.render(write_still=True)
    print("rendered item", kind)


main()
