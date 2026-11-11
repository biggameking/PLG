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
        "subd_wool": 4, "subd_skin": 2,
        "displace": {"scale": 0.14, "strength": 0.075, "detail": 4.0},
        "rot_z": 55.0,              # turn the rig until it faces the camera
        "action": "Idle", "frames": (10, 85),
        "eye_r": 0.04, "eye_gap": 0.065, "eye_fwd": -0.03, "eye_up": 0.17,
        # puff shell over the wool bbox — real fleece clumps on real anatomy
        "puffs": {"n": 30, "r": 0.16, "sq": 0.78, "shell": (0.9, 1.1),
                  "z_lo": 0.45, "seed": 5, "bone": "Body"},
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


def bone_attach(arm, bone_name, ob, world_m):
    """Parent `ob` to a bone so it lands at `world_m` right now and rides the
    bone afterward. Bone-parent children resolve against the bone TAIL in
    pose space — invert that chain or the offset gets applied twice."""
    pb = arm.pose.bones[bone_name]
    tail = mathutils.Matrix.Translation((0, -arm.data.bones[bone_name].length, 0))
    base = arm.matrix_world @ pb.matrix @ tail
    ob.parent = arm
    ob.parent_type = 'BONE'
    ob.parent_bone = bone_name
    ob.matrix_basis = base.inverted() @ world_m


def add_eyes(arm, bone_name, cfg, m):
    """Ink beads auto-placed from the head bone: muzzle dir (head→tail) +
    lateral cross gives both eye sockets — works on any quadruped rig.
    All targets use POSE-space coords (pb.head/tail) so they match the
    pose the file saved — never mix rest locals with pose matrices."""
    pb = arm.pose.bones[bone_name]
    h = arm.matrix_world @ pb.head
    t = arm.matrix_world @ pb.tail
    fwd = (t - h)
    fwd.z = 0
    if fwd.length < 1e-6:
        fwd = t - h
    fwd = fwd.normalized()
    lat = mathutils.Vector((-fwd.y, fwd.x, 0.0))
    center = t + fwd * cfg["eye_fwd"] + mathutils.Vector((0, 0, cfg["eye_up"]))
    for sgn in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12,
                                             radius=cfg["eye_r"])
        e = bpy.context.active_object
        e.data.materials.append(m)
        p = center + lat * (cfg["eye_gap"] * sgn)
        bone_attach(arm, bone_name, e, mathutils.Matrix.Translation(p))
        bpy.ops.object.shade_smooth()
    print("EYES at", tuple(round(c, 3) for c in center))


def fluff_shell(arm, wool, cfg, m):
    """Scatter squashed puff spheres on the wool's ellipsoid hull — the
    cauliflower fleece silhouette. Parented to the torso bone so they ride
    the animation."""
    import random
    bb = [wool.matrix_world @ mathutils.Vector(v) for v in wool.bound_box]
    lo = mathutils.Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = mathutils.Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    c = (lo + hi) / 2
    ext = (hi - lo) / 2
    z_min = lo.z + (hi.z - lo.z) * cfg["z_lo"]
    bone = cfg["bone"] if cfg["bone"] in arm.data.bones else arm.data.bones[0].name
    rng = random.Random(cfg["seed"])
    placed = 0
    tries = 0
    while placed < cfg["n"] and tries < cfg["n"] * 30:
        tries += 1
        d = mathutils.Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1)))
        if d.length < 1e-4:
            continue
        d.normalize()
        # point on the ellipsoid in direction d, jittered into the shell band
        denom = math.sqrt((d.x / ext.x) ** 2 + (d.y / ext.y) ** 2 + (d.z / ext.z) ** 2)
        band = rng.uniform(*cfg["shell"])
        p = c + mathutils.Vector((d.x / denom * band, d.y / denom * band, d.z / denom * band))
        if p.z < z_min or p.z > hi.z + 0.05:
            continue
        r = cfg["r"] * rng.uniform(0.75, 1.3)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12, radius=r)
        e = bpy.context.active_object
        e.data.materials.append(m)
        world_m = mathutils.Matrix.Translation(p) @ mathutils.Matrix.Diagonal(
            (1, 1, cfg["sq"], 1))
        bone_attach(arm, bone, e, world_m)
        bpy.ops.object.shade_smooth()
        placed += 1
    print("PUFFS placed", placed)


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

    # face the camera before anything else — eyes normalize against this pose
    arm.rotation_euler.z = math.radians(cfg.get("rot_z", 0.0))
    bpy.context.view_layer.update()

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

    # report head-bone world position POST-normalize — tune eye params off it
    hb = arm.pose.bones.get("Head")
    if hb:
        wh = arm.matrix_world @ hb.head
        wt = arm.matrix_world @ hb.tail
        print("HEAD_BONE world head=%s tail=%s" %
              (tuple(round(c, 3) for c in wh), tuple(round(c, 3) for c in wt)))

    em = mat(INK, "ink")
    if hb:
        add_eyes(arm, "Head", cfg, em)
    if cfg.get("puffs"):
        fluff_shell(arm, wool, cfg["puffs"], wm)

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
