#!/usr/bin/env python3
"""Blender headless kin renderer — builds a species rig from primitives,
lights it for the poster look (warm key / cool fill), renders two idle
frames to tools/art/render/<sid>_f{0,1}.png at 512px for post to shrink.

    blender -b -P tools/art/render_kin.py -- fenjelly

Add a species to RIGS below. Params are unit-space: the rig stands on the
ground plane around origin, ~1.5-2.0 units tall.
"""
import bpy, math, random, sys, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# ---------------------------------------------------------------- rigs
# A rig = list of parts. kind: 'sph' ellipsoid / 'ico' / 'cone' / 'cyl'
# (cx,cy,cz) center, r radius or (rx,ry,rz) scale, mat index into MATS,
# optional rot (rx,ry,rz) radians, seed jitter fields for fluff clusters.
RIGS = {
    "fenjelly": {
        "mats": [(0.93, 0.88, 0.78),      # 0 fleece #ede0c8
                 (0.80, 0.66, 0.53),      # 1 face/legs light fawn
                 (0.11, 0.10, 0.18)],     # 2 ink beads (eyes/nose)
        "parts": (
            # ---- fleece: a cloud of overlapping puffs ----
            {"kind": "fluff", "c": (0, 0.02, 0.86), "r": 0.62, "n": 26,
             "mat": 0, "sq": 0.82, "seed": 7, "jitter": 0.16},
            # crown puffs over the head
            {"kind": "fluff", "c": (0, -0.42, 1.28), "r": 0.34, "n": 10,
             "mat": 0, "sq": 0.85, "seed": 11, "jitter": 0.12},
            # ---- head + face ----
            {"kind": "sph", "c": (0, -0.58, 1.10), "r": (0.30, 0.26, 0.32), "mat": 1},
            # ears: flopped ellipsoids either side of the skull
            {"kind": "sph", "c": (-0.30, -0.50, 1.16), "r": (0.22, 0.10, 0.13),
             "rot": (0, 0, -0.5), "mat": 1},
            {"kind": "sph", "c": (0.30, -0.50, 1.16), "r": (0.22, 0.10, 0.13),
             "rot": (0, 0, 0.5), "mat": 1},
            # tiny legs under the fleece
            {"kind": "cyl", "c": (-0.26, -0.16, 0.16), "r": 0.075, "depth": 0.32, "mat": 1},
            {"kind": "cyl", "c": (0.26, -0.16, 0.16), "r": 0.075, "depth": 0.32, "mat": 1},
            {"kind": "cyl", "c": (-0.26, 0.22, 0.16), "r": 0.075, "depth": 0.32, "mat": 1},
            {"kind": "cyl", "c": (0.26, 0.22, 0.16), "r": 0.075, "depth": 0.32, "mat": 1},
            # eyes — ink beads slightly proud of the muzzle
            {"kind": "sph", "c": (-0.115, -0.795, 1.16), "r": 0.052, "mat": 2},
            {"kind": "sph", "c": (0.115, -0.795, 1.16), "r": 0.052, "mat": 2},
            # nose
            {"kind": "sph", "c": (0, -0.815, 1.02), "r": (0.055, 0.032, 0.04), "mat": 2},
        ),
        # f1 idle variation: fluff bobs up, ears lift a touch
        "f1": {"fluff_dy": 0.06, "ear_drop": 0.35, "head_dy": 0.03},
    },
}


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(col):
    m = bpy.data.materials.new("m")
    m.diffuse_color = (*col, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return m


def sph(c, r, m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=c)
    o = bpy.context.active_object
    sc = r if isinstance(r, (tuple, list)) else (r, r, r)
    o.scale = sc
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    o.data.materials.append(m)


def cyl(c, r, depth, m):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=c)
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    o.data.materials.append(m)


def fluff(c, r, n, sq, seed, jitter, m):
    """A mound of squashed spheres — the fleece look. Deterministic."""
    rng = random.Random(seed)
    cx, cy, cz = c
    for i in range(n):
        a = rng.uniform(0, math.tau)
        b = rng.uniform(-1, 1)
        rad = r * (0.34 + rng.uniform(0, 0.30))
        rr = r * (0.55 + rng.uniform(0, 0.45))
        x = cx + math.cos(a) * math.sqrt(1 - b * b) * rr * 0.9
        y = cy + math.sin(a) * math.sqrt(1 - b * b) * rr * 0.75
        z = cz + b * rr * 0.62
        sph((x, y, z + rng.uniform(-jitter, jitter) * 0.3), (rad, rad, rad * sq), m)


def build(sid, frame):
    rig = RIGS[sid]
    mats = [mat(c) for c in rig["mats"]]
    f1 = rig.get("f1", {}) if frame == 1 else {}
    fluff_dy = f1.get("fluff_dy", 0.0)
    for p in rig["parts"]:
        c = list(p["c"])
        if frame == 1:
            if p["kind"] == "fluff" and c[2] > 1.0:
                c[2] += fluff_dy
            elif p["kind"] == "sph" and p.get("rot"):
                c[2] += f1.get("ear_drop", 0) * 0.05
            elif p["mat"] == 1 and c[2] > 0.8:
                c[1] += f1.get("head_dy", 0)
        if p["kind"] == "fluff":
            fluff(tuple(c), p["r"], p["n"], p["sq"], p["seed"] + frame,
                  p["jitter"], mats[p["mat"]])
        elif p["kind"] == "sph":
            o_before = bpy.context.active_object
            bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, location=c)
            o = bpy.context.active_object
            sc = p["r"] if isinstance(p["r"], (tuple, list)) else (p["r"],) * 3
            o.scale = sc
            bpy.ops.object.transform_apply(scale=True)
            if p.get("rot"):
                o.rotation_euler = p["rot"]
            bpy.ops.object.shade_smooth()
            o.data.materials.append(mats[p["mat"]])
        elif p["kind"] == "cyl":
            cyl(tuple(c), p["r"], p["depth"], mats[p["mat"]])
    return mats


def light_rig():
    # warm key upper-left-front — the poster's single light source
    bpy.ops.object.light_add(type='AREA', location=(-3.4, -4.2, 5.5))
    key = bpy.context.active_object
    key.data.energy = 900
    key.data.size = 4.0
    key.data.color = (1.0, 0.93, 0.82)
    # cool fill right-back, much weaker — keeps shade alive, not gray
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


def camera():
    bpy.ops.object.camera_add(location=(3.6, -5.6, 2.9))
    cam = bpy.context.active_object
    # track to the sheep's center of mass
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, -0.05, 0.85)
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2.9
    cam.data.lens = 60
    bpy.context.scene.camera = cam


def render(sid, frame):
    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE' # 5.x names it EEVEE, not EEVEE_NEXT
    s.render.resolution_x = s.render.resolution_y = 512
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    # poster look wants flat saturated color, not AgX's filmic desaturation
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "%s_f%d.png" % (sid, frame))
    bpy.ops.render.render(write_still=True)


def main():
    sid = sys.argv[-1] if len(sys.argv) > 1 and sys.argv[-1] != "--" else "fenjelly"
    for frame in (0, 1):
        clean()
        build(sid, frame)
        light_rig()
        camera()
        render(sid, frame)
        print("rendered %s f%d" % (sid, frame))


main()
