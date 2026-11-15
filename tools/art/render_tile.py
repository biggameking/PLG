# Blender script: render ONE ground-tile texture into a 256x128 RGBA frame.
# Scene is built procedurally (factory startup, no source blend): a 1x1 XY
# ground slab + per-kind geometry detail, shot with a dimetric ortho camera
# (azimuth 45, elevation 30 -> the top face projects as the game's 2:1
# diamond). post_tile.py then crops/masks into the atlas cell.
#
#   blender --factory-startup -b -P render_tile.py -- <tile_name>
#
# Output: tools/art/render/tile_<name>_f0.png

import bpy
import math
import mathutils
import os
import random
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# kind -> base color, detail recipe, deterministic seed
CFG = {
    "grass_0":     {"col": (0.238, 0.409, 0.165), "detail": "blades", "seed": 11},
    "grass_1":     {"col": (0.218, 0.376, 0.152), "detail": "blades", "seed": 22},
    "grass_2":     {"col": (0.264, 0.436, 0.185), "detail": "blades", "seed": 33},
    "grass_3":     {"col": (0.231, 0.396, 0.158), "detail": "blades", "seed": 44},
    "tallgrass_0": {"col": (0.224, 0.383, 0.145), "detail": "tall_blades", "seed": 55},
    "tallgrass_1": {"col": (0.211, 0.363, 0.139), "detail": "tall_blades", "seed": 66},
    "flower_0":    {"col": (0.244, 0.416, 0.172), "detail": "flowers", "seed": 77},
    "flower_1":    {"col": (0.251, 0.422, 0.178), "detail": "flowers", "seed": 88},
    "sand_0":      {"col": (0.541, 0.462, 0.310), "detail": "ripples", "seed": 99},
    "sand_1":      {"col": (0.528, 0.449, 0.297), "detail": "ripples", "seed": 110},
    "water_0":     {"col": (0.106, 0.277, 0.449), "detail": "waves", "seed": 121},
    "water_1":     {"col": (0.092, 0.264, 0.436), "detail": "waves", "seed": 132},
    "stonefield_0":{"col": (0.330, 0.330, 0.383), "detail": "stones", "seed": 143},
    "stonefield_1":{"col": (0.310, 0.317, 0.370), "detail": "stones", "seed": 154},
    "dirt_0":      {"col": (0.363, 0.264, 0.172), "detail": "clods", "seed": 165},
    "farmland_0":  {"col": (0.304, 0.218, 0.132), "detail": "ridges", "seed": 176},
}

HALF = 0.5  # ground slab covers XY in [-0.5, 0.5]


def mat(rgb, name, rough=0.95):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb[:3], 1.0)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb[:3], 1.0)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Specular IOR Level"].default_value = 0.12
    return m


def add_mesh(name, verts, faces, material):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(material)
    return ob


def ground(col):
    m = mat(col, "ground")
    # slab oversized ×1.3 (audit-56 HIGH): the output diamond mask must cut
    # through fully-opaque interior — a diamond rendered to fit exactly
    # leaves a semi-transparent rim that draws a dark seam grid on the map.
    # The excess projects outside the frame and is clipped harmlessly.
    H = HALF * 1.3
    verts = [(-H, -H, 0), (H, -H, 0), (H, H, 0), (-H, H, 0)]
    ob = add_mesh("slab", verts, [(0, 1, 2, 3)], m)
    # gentle height noise: subdivide FIRST (a 4-vert plane has nothing to
    # displace), then displace the subdivided grid with cloud noise
    sub = ob.modifiers.new("sub", 'SUBSURF')
    sub.subdivision_type = 'SIMPLE'
    sub.levels = 3
    tex = bpy.data.textures.new("gnoise", type='CLOUDS')
    tex.noise_scale = 0.28
    mod = ob.modifiers.new("disp", 'DISPLACE')
    mod.texture = tex
    mod.strength = 0.015
    return ob


def cone(name, loc, r, h, material, verts=5):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0,
                                    depth=h, location=loc)
    ob = bpy.context.active_object
    ob.data.materials.append(material)
    return ob


def ico(name, loc, r, material, subdivisions=1, squash_z=1.0):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=r,
                                          location=loc)
    ob = bpy.context.active_object
    ob.scale.z = squash_z
    ob.data.materials.append(material)
    return ob


def scatter_pts(rng, n, margin=0.42):
    """Points inside the slab's XY square, shrunk so blade tops still
    project inside the diamond (keep clear of the far/top corner)."""
    return [(rng.uniform(-margin, margin), rng.uniform(-margin, margin)) for _ in range(n)]


def detail(kind, rng):
    dark = mat((0.15, 0.28, 0.10), "blade_dark")
    lite = mat((0.30, 0.48, 0.20), "blade_lite")
    if kind == "blades":
        for x, y in scatter_pts(rng, 26):
            m = dark if rng.random() < 0.5 else lite
            h = rng.uniform(0.10, 0.20)
            cone("blade", (x, y, h * 0.5), rng.uniform(0.015, 0.03), h, m, 4)
    elif kind == "tall_blades":
        for x, y in scatter_pts(rng, 20):
            m = dark if rng.random() < 0.4 else lite
            h = rng.uniform(0.18, 0.30)
            cone("blade", (x, y, h * 0.5), rng.uniform(0.02, 0.035), h, m, 4)
    elif kind == "flowers":
        for x, y in scatter_pts(rng, 18):
            if rng.random() < 0.6:
                m = dark if rng.random() < 0.5 else lite
                h = rng.uniform(0.08, 0.16)
                cone("blade", (x, y, h * 0.5), 0.02, h, m, 4)
            else:
                fm = mat([(0.63, 0.30, 0.36), (0.63, 0.56, 0.23),
                          (0.56, 0.36, 0.63)][rng.randrange(3)], "petal")
                ico("bloom", (x, y, rng.uniform(0.10, 0.16)), 0.035, fm, 1, 0.7)
    elif kind == "ripples":
        rm = mat((0.580, 0.510, 0.360), "ripple")
        dm = mat((0.660, 0.550, 0.360), "dune")
        for x, y in scatter_pts(rng, 10, 0.38):
            if rng.random() < 0.45:
                # low dune lumps for coverage — thin rings alone read flat
                ico("dune", (x, y, 0.02), rng.uniform(0.05, 0.10), dm, 1, 0.35)
            else:
                bpy.ops.mesh.primitive_torus_add(major_radius=rng.uniform(0.07, 0.12),
                                                 minor_radius=0.018,
                                                 major_segments=10, minor_segments=4,
                                                 location=(x, y, 0.01))
                bpy.context.active_object.scale.z = 0.35
                bpy.context.active_object.data.materials.append(rm)
    elif kind == "waves":
        wm = mat((0.360, 0.500, 0.630), "crest")
        for x, y in scatter_pts(rng, 9, 0.36):
            bpy.ops.mesh.primitive_torus_add(major_radius=rng.uniform(0.06, 0.11),
                                             minor_radius=0.010,
                                             major_segments=10, minor_segments=4,
                                             location=(x, y, 0.012))
            o = bpy.context.active_object
            o.scale.z = 0.3
            o.data.materials.append(wm)
    elif kind == "stones":
        sm = mat((0.410, 0.410, 0.460), "stone")
        dm = mat((0.250, 0.250, 0.300), "stone_dark")
        for x, y in scatter_pts(rng, 14, 0.38):
            m = sm if rng.random() < 0.6 else dm
            ico("pebble", (x, y, 0.03), rng.uniform(0.04, 0.09), m, 1,
                rng.uniform(0.4, 0.7))
    elif kind == "clods":
        dm = mat((0.280, 0.190, 0.110), "clod")
        lm = mat((0.440, 0.330, 0.220), "clod_hi")
        for x, y in scatter_pts(rng, 16, 0.38):
            m = dm if rng.random() < 0.5 else lm
            ico("clod", (x, y, 0.025), rng.uniform(0.03, 0.06), m, 1, 0.5)
    elif kind == "ridges":
        rm = mat((0.240, 0.170, 0.100), "furrow")
        hm = mat((0.380, 0.290, 0.190), "ridge_hi")
        for i in range(5):
            y = -0.36 + i * 0.18
            bpy.ops.mesh.primitive_cube_add(size=1, location=(0, y, 0.03))
            o = bpy.context.active_object
            o.scale = (HALF, 0.035, 0.05)
            o.data.materials.append(hm if i % 2 else rm)


def main():
    name = sys.argv[-1]
    cfg = CFG[name]
    rng = random.Random(cfg["seed"])

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)

    ground(cfg["col"])
    detail(cfg["detail"], rng)

    # kin light rig (audit-55: decor uses the identical rig — tiles too)
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

    # dimetric: azimuth 45°, elevation 30° -> square top = 2:1 diamond
    az = math.radians(45)
    el = math.radians(30)
    dist = 4.0
    cx = dist * math.cos(el) * math.cos(az + math.pi)  # camera at -x,-y azimuth 225
    cy = dist * math.cos(el) * math.sin(az + math.pi)
    cz = dist * math.sin(el)
    bpy.ops.object.camera_add(location=(cx, cy, cz))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, 0.04)  # aim slightly above ground so detail centers
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 1.5  # diamond ~1.41 units wide + breathing room
    s = bpy.context.scene
    s.camera = cam

    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = 256
    s.render.resolution_y = 128
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "tile_%s_f0.png" % name)
    bpy.ops.render.render(write_still=True)
    print("rendered tile", name)


main()
