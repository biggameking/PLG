"""Source-asset kin renderer — upgrades a licensed .blend model into the
project's poster look, then renders animation frames at 512px for post.

    blender -b <model.blend> -P tools/art/render_src_asset.py -- <sid>

Per-species tuning lives in CFG below. Pipeline per species:
  1. split mesh by material (wool/skin) → independent subdivision & surface
  2. Subsurf×N + procedural displace on wool (real surface, not a blob)
  3. recolor to the species palette, add ink-bead eyes parented to a bone
  4. drive the source armature through its own action, render frames FRAMES
"""
import bpy, sys, os, math
import mathutils

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# ---------------------------------------------------------------- per-species
# mats: (wool_rgba, skin_rgba) as linear-ish rgb tuples · eye: two world-space
# offsets solved AFTER normalizing (script prints the head-bone position so
# tuning is one render round-trip) · subd/displace = surface complexity knobs
CFG = {
    "fenjelly": {
        "wool_mat_idx": 0,          # Quaternius 'White'
        "mats": [(0.93, 0.88, 0.78), (0.80, 0.66, 0.53)],
        "subd_wool": 3, "subd_skin": 2,
        "displace": {"scale": 0.22, "strength": 0.045, "detail": 4.0},
        "action": "Idle", "frames": (10, 85),
        "eyes": [(-0.10, -0.36, 1.02), (0.10, -0.36, 1.02)], "eye_r": 0.045,
        "target_h": 1.45,
    },
}

INK = (0.11, 0.10, 0.18)


def mat(col, name):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*col, 1.0)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Specular IOR Level"].default_value = 0.15
    return m


def split_by_material(src, keep_idx, name):
    """Duplicate the mesh keeping only faces of material `keep_idx`."""
    import bmesh
    ob = src.copy()
    ob.data = src.data.copy()
    ob.name = name
    src.users_collection[0].objects.link(ob)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for f in list(bm.faces):
        if f.material_index != keep_idx:
            bm.faces.remove(f)
    bm.to_mesh(ob.data)
    bm.free()
    return ob


def smooth(ob):
    for p in ob.data.polygons:
        p.use_smooth = True


def subdiv(ob, lv):
    m = ob.modifiers.new("subd", 'SUBSURF')
    m.subdivision_type = 'CATMULL_CLARK'
    m.levels = lv
    m.render_levels = lv


def displace(ob, scale, strength, detail):
    tex = bpy.data.textures.new("nap", type='CLOUDS')
    tex.noise_scale = scale
    tex.noise_depth = 2
    m = ob.modifiers.new("nap", 'DISPLACE')
    m.texture = tex
    m.strength = strength
    m.texture_coords = 'LOCAL'


def normalize(objs, target_h):
    """Uniform-scale the rig so the mesh stands target_h units, feet on z=0."""
    lo, hi = 1e9, -1e9
    for o in objs:
        for v in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(v)
            lo = min(lo, w.z); hi = max(hi, w.z)
    k = target_h / max(hi - lo, 0.001)
    for o in bpy.data.objects:
        if o.parent is None:
            o.scale = tuple(s * k for s in o.scale)
    bpy.context.view_layer.update()
    # drop feet to the floor
    lo2 = 1e9
    for o in objs:
        for v in o.bound_box:
            lo2 = min(lo2, (o.matrix_world @ mathutils.Vector(v)).z)
    for o in bpy.data.objects:
        if o.parent is None:
            o.location.z -= lo2
    bpy.context.view_layer.update()
    return k


def add_eyes(arm, bone_name, offsets, r, m):
    for i, off in enumerate(offsets):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12, radius=r)
        e = bpy.context.active_object
        e.data.materials.append(m)
        e.parent = arm
        e.parent_type = 'BONE'
        e.parent_bone = bone_name
        # matrix_parent_inverse trick: set world position, let parenting keep it
        e.matrix_world = mathutils.Matrix.Translation(mathutils.Vector(off))
        bpy.ops.object.shade_smooth()


def light_rig():
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


def camera():
    bpy.ops.object.camera_add(location=(3.6, -5.6, 2.9))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, 0.75)
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 2.4
    bpy.context.scene.camera = cam


def render(sid, fi):
    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = s.render.resolution_y = 512
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "%s_f%d.png" % (sid, fi))
    bpy.ops.render.render(write_still=True)
    print("rendered %s f%d" % (sid, fi))


def main():
    sid = sys.argv[-1]
    cfg = CFG[sid]
    s = bpy.context.scene

    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    src = next(o for o in bpy.data.objects if o.type == 'MESH')
    for o in bpy.data.objects:
        o.hide_render = False

    # report head-bone position for eye tuning
    hb = arm.data.bones.get("Head")
    if hb:
        wh = arm.matrix_world @ hb.head_local
        print("HEAD_BONE world", tuple(round(c, 3) for c in wh))

    # split wool/skin, upgrade surfaces
    wool_idx = cfg["wool_mat_idx"]
    wool = split_by_material(src, wool_idx, "wool")
    skin_idx = 1 - wool_idx if len(src.data.materials) > 1 else wool_idx
    skin = split_by_material(src, skin_idx, "skin")
    src.hide_render = True
    src.hide_viewport = True

    smooth(wool); smooth(skin)
    subdiv(wool, cfg["subd_wool"])
    subdiv(skin, cfg["subd_skin"])
    d = cfg["displace"]
    if d:
        displace(wool, d["scale"], d["strength"], d["detail"])

    # palette
    wm = mat(cfg["mats"][0], "wool")
    sm = mat(cfg["mats"][1], "skin")
    wool.data.materials.clear(); wool.data.materials.append(wm)
    skin.data.materials.clear(); skin.data.materials.append(sm)

    k = normalize([wool, skin], cfg["target_h"])
    print("scale k=%.4f faces: wool=%d skin=%d (pre-subd)" %
          (k, len(wool.data.polygons), len(skin.data.polygons)))

    em = mat(INK, "ink")
    if hb:
        add_eyes(arm, "Head", cfg["eyes"], cfg["eye_r"], em)

    # drive the source rig's own action
    if not arm.animation_data:
        arm.animation_data_create()
    act = bpy.data.actions.get(cfg["action"])
    if act:
        arm.animation_data.action = act
        print("action %s range %s" % (act.name, act.frame_range))

    light_rig()
    camera()
    for fi, fr in enumerate(cfg["frames"]):
        s.frame_set(int(fr))
        render(sid, fi)


main()
