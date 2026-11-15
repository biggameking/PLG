# Blender script: render a static nature-pack mesh into a 512px RGBA frame.
# Static decor variant of render_src_asset.py — no armature/action, so the
# normalize pass is a straight object-scale bake, not the conjugate loop.
#
#   blender -b <model.blend> -P render_decor.py -- <decor_id>
#
# Output: tools/art/render/<id>_f0.png (512x512, transparent) — post_decor.py
# turns it into the game's decor sprite.

import bpy
import math
import mathutils
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# id -> blend file under src/nature, mat_map {slot: rgb}, target world height,
# camera ortho scale + track-z, rot_z for a good 3/4 angle
CFG = {
    "tree_a": {     # PineTree_2 — tall conifer, matches the old teardrop slot
        "blend": "PineTree_2.blend",
        "mat_map": {"Wood": (0.42, 0.30, 0.20), "Green": (0.22, 0.55, 0.30),
                    "DarkGreen": (0.14, 0.40, 0.22)},
        "target_h": 2.6, "ortho": 3.0, "track_z": 1.2, "rot_z": 20.0,
    },
    "tree_b": {     # BirchTree_1 — rounder canopy for the second silhouette
        "blend": "BirchTree_1.blend",
        "mat_map": {"White": (0.82, 0.76, 0.68), "Black": (0.28, 0.24, 0.20),
                    "Green": (0.38, 0.62, 0.26), "DarkGreen": (0.26, 0.46, 0.20)},
        "target_h": 2.4, "ortho": 3.0, "track_z": 1.1, "rot_z": -15.0,
    },
    "rock": {       # Rock_2 — plain boulder
        "blend": "Rock_2.blend",
        "mat_map": {"Rock": (0.55, 0.55, 0.62)},
        "target_h": 0.9, "ortho": 1.6, "track_z": 0.4, "rot_z": 30.0,
    },
    "ore_coal": {   # Rock_2 dark seam
        "blend": "Rock_2.blend",
        "mat_map": {"Rock": (0.30, 0.28, 0.34)},
        "target_h": 0.9, "ortho": 1.6, "track_z": 0.4, "rot_z": 60.0,
    },
    "ore_gold": {   # Rock_2 warm seam
        "blend": "Rock_2.blend",
        "mat_map": {"Rock": (0.72, 0.58, 0.28)},
        "target_h": 0.9, "ortho": 1.6, "track_z": 0.4, "rot_z": 45.0,
    },
    "berry_bush": { # BushBerries_1 — leafy bush + berry dots
        "blend": "BushBerries_1.blend",
        "mat_map": {"Green": (0.26, 0.52, 0.28), "Berry": (0.85, 0.25, 0.30)},
        "target_h": 1.1, "ortho": 1.8, "track_z": 0.5, "rot_z": 15.0,
    },
    "stump": {      # TreeStump_Moss — cut trunk
        "blend": "TreeStump_Moss.blend",
        "mat_map": {"Wood": (0.45, 0.32, 0.22), "LightWood": (0.72, 0.55, 0.38),
                    "Green": (0.30, 0.50, 0.26)},
        "target_h": 0.8, "ortho": 1.5, "track_z": 0.35, "rot_z": 10.0,
    },
}


def mat(rgb, name):
    # Legacy Quaternius blends carry double-output node trees where the
    # render output is a DIFFUSE node — setting Principled inputs on the
    # existing material reaches nothing. Rebuild a clean Principled tree.
    m = bpy.data.materials.new("recol_%s" % name)
    m.diffuse_color = (*rgb[:3], 1.0)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = (*rgb[:3], 1.0)
    bs.inputs["Roughness"].default_value = 0.95
    bs.inputs["Specular IOR Level"].default_value = 0.12
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    return m


def main():
    sid = sys.argv[-1]
    cfg = CFG[sid]
    s = bpy.context.scene

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    # largest-volume mesh is the semantic main object (alphabetical-first
    # could be a sibling detail mesh)
    src = max(meshes, key=lambda o: mathutils.Vector(
        (o.bound_box[6][0] - o.bound_box[0][0],
         o.bound_box[6][1] - o.bound_box[0][1],
         o.bound_box[6][2] - o.bound_box[0][2])).length)
    if len(meshes) > 1:
        print("WARN %d mesh objects — only '%s' is processed" %
              (len(meshes), src.name))
    for o in bpy.data.objects:
        o.hide_render = o.hide_get()  # honor the source author's intent

    src.rotation_euler.z = math.radians(cfg.get("rot_z", 0.0))
    bpy.context.view_layer.update()

    # recolor named slots, warn on misses (same contract as mat_map kin path)
    pal = {name: mat(col, name) for name, col in cfg["mat_map"].items()}
    slots = []
    for i, m in enumerate(src.data.materials):
        nm = m.name if m else ""
        slots.append(nm)
        if nm in pal:
            src.data.materials[i] = pal[nm]
    dead = set(pal) - set(slots)
    bare = set(slots) - set(pal) - {""}
    if dead or bare:
        print("WARN mat_map: unused=%s uncolored=%s slots=%s" %
              (sorted(dead), sorted(bare), slots))

    for p in src.data.polygons:
        p.use_smooth = True

    # normalize: evaluated bbox -> scale to target_h, center XY, ground z=0
    dg = bpy.context.evaluated_depsgraph_get()
    ev = src.evaluated_get(dg)
    ws = [ev.matrix_world @ mathutils.Vector(c) for c in ev.bound_box]
    xlo = min(w.x for w in ws); xhi = max(w.x for w in ws)
    ylo = min(w.y for w in ws); yhi = max(w.y for w in ws)
    zlo = min(w.z for w in ws); zhi = max(w.z for w in ws)
    ext = max(zhi - zlo, 1e-6)
    k = cfg["target_h"] / ext
    # multiplicative scale + folded location — correct for sources that
    # arrive with a baked transform (world = raw*s + T; scaling the world
    # bounds by k means T must fold as (T - bound) * k)
    src.scale = src.scale * k
    src.location.z = (src.location.z - zlo) * k
    src.location.x = (src.location.x - (xlo + xhi) * 0.5) * k
    src.location.y = (src.location.y - (ylo + yhi) * 0.5) * k
    bpy.context.view_layer.update()
    print("scale k=%.3f ext=%.2f" % (k, ext))

    # light rig identical to render_src_asset.light_rig — the same warm key,
    # cool soft fill and grey world ambient keep decor on the kin look
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
    tgt.location = (0, 0, cfg.get("track_z", 0.75))
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = cfg.get("ortho", 2.4)
    s.camera = cam

    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = s.render.resolution_y = 512
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "%s_f0.png" % sid)
    bpy.ops.render.render(write_still=True)
    print("rendered %s" % sid)


main()
