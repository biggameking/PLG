"""Source-asset kin renderer — upgrades a licensed .blend model into the
project's poster look, then renders animation frames at 512px for post.

    blender -b <model.blend> -P tools/art/render_src_asset.py -- <sid>

Per-species tuning lives in CFG below. Pipeline per species:
  1. split mesh by material (wool/skin) → independent subdivision & surface
  2. Subsurf×N + procedural displace on wool (real surface, not a blob)
  3. recolor to the species palette, add ink-bead eyes parented to a bone
  4. drive the source armature through its own action, render frames FRAMES
"""
import bpy, sys, os, math, colorsys
import mathutils

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

# ---------------------------------------------------------------- per-species
# mats: (wool_rgba, skin_rgba) as linear-ish rgb tuples · eye: two world-space
# offsets solved AFTER normalizing (script prints the head-bone position so
# tuning is one render round-trip) · subd/displace = surface complexity knobs
CFG = {
    "player": {      # Alien_Tall.blend — the rancher (zone-matted outfit + hat)
        "zone_mats": [(0.0, 0.28, (0.30, 0.62, 0.88)),   # trousers #4d9de0
                      (0.28, 0.56, (0.82, 0.48, 0.24)),  # jacket #d17b3c
                      (0.56, 1.01, (0.91, 0.79, 0.63))], # skin #e8c9a0
        "strip_islands": True,  # strip the alien's 4 baked eyeball islands
        "strip_expect_faces": 528,
        "accessory": "hat", "acc_col": (0.16, 0.14, 0.18),
        "subd_wool": 2, "displace": None,
        "rot_z": 25.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Head3",  # dome driver (vgroup z 0.98-1.35) — 'Head'
                               # is jaw, 'Head2' mid-face; verified by the
                               # weight-vote remap, not by name
        "eye_r": 0.06, "eye_gap": 0.13, "eye_fwd": 0.50, "eye_up": -0.15,
        "eye_abs_z": 0.98,
        "nose_r": None,
        "target_h": 1.35,
    },
    "fenjelly": {
        "wool_mat_idx": 0,          # Quaternius 'White'
        "mats": [(0.93, 0.88, 0.78), (0.80, 0.66, 0.53)],
        "subd_wool": 4, "subd_skin": 2,
        "displace": {"scale": 0.14, "strength": 0.075, "detail": 4.0},
        "rot_z": 55.0,              # turn the rig until it faces the camera
        "action": "Idle", "frames": (10, 85),
        "eye_r": 0.04, "eye_gap": 0.065, "eye_fwd": -0.03, "eye_up": 0.17,
        "nose_r": 0.035, "nose_up": 0.055,
        # puff shell over the wool bbox — real fleece clumps on real anatomy
        "puffs": {"n": 48, "r": 0.15, "sq": 0.78, "shell": (0.7, 0.95),
                  "shrink": 0.85, "z_lo": 0.45, "seed": 5, "bone": "Body"},
        "target_h": 1.45,
    },
    # ---- audit-51: pack Vol.2 + farm leftovers — real anatomy per archetype.
    # head_bone: the neck→head bone whose TAIL is the snout/beak tip.
    # mat_map recolors named material slots; single-mat meshes get one key.
    "scalcrest": {   # Eagle.blend — royal bird
        "mat_map": {"Wings": (0.42, 0.52, 0.78), "Head": (0.60, 0.66, 0.86),
                    "Beak": (0.90, 0.72, 0.30), "Claws": (0.28, 0.24, 0.30)},
        "accessory": "crown",
        "subd_wool": 2, "displace": None,
        "rot_z": 285.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Bone.003",
        "eye_r": 0.05, "eye_gap": 0.09, "eye_fwd": -0.10, "eye_up": 0.10,
        "target_h": 1.35,
    },
    "scalfang": {    # Wolf.blend — fire-fang canine
        "mat_map": {"Wolf": (0.76, 0.44, 0.18)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Bone.003",
        "eye_r": 0.05, "eye_gap": 0.12, "eye_fwd": -0.12, "eye_up": 0.12,
        "nose_r": 0.045, "nose_up": 0.02,
        "target_h": 1.45,
    },
    "branpurr": {    # Cat.blend — ember cat
        "mat_map": {"Grey": (0.72, 0.20, 0.26), "White": (0.93, 0.88, 0.82), "Pink": (0.95, 0.62, 0.66)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Bone.003",
        "eye_r": 0.05, "eye_gap": 0.10, "eye_fwd": -0.10, "eye_up": 0.10,
        "nose_r": 0.04, "nose_up": 0.01,
        "target_h": 1.30,
    },
    "tidscale": {    # Piranha.blend — tide serpent reads as a fish-kin
        "mat_map": {"Brown": (0.20, 0.34, 0.52), "LightYellow": (0.55, 0.62, 0.72), "Black": (0.10, 0.12, 0.20), "White": (0.92, 0.92, 0.88)},
        "accessory": "fins",
        "subd_wool": 2, "displace": None,
        # a fish is long and low — height-normalization at 0.80 left it a
        # sliver of the frame; 1.35 fills it like the other kin (S122 probe)
        # rot -90 faced the camera head-on (audit-74 rot probe) — 0 = profile
        "rot_z": 0.0, "action": "Swimming", "frames": (10, 30),
        "head_bone": "Bone",
        "eye_r": 0.055, "eye_gap": 0.10, "eye_fwd": 0.05, "eye_up": 0.06,
        "target_h": 1.35,
    },
    "piplump": {     # Cow.blend — dairy kin
        "mat_map": {"White": (0.90, 0.84, 0.72), "Black": (0.24, 0.22, 0.28), "Pink": (0.95, 0.62, 0.66)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Head",
        "eye_r": 0.05, "eye_gap": 0.13, "eye_fwd": -0.12, "eye_up": 0.12,
        "nose_r": 0.05, "nose_up": 0.02,
        "target_h": 1.5,
    },
    "digsnout": {    # Pig.blend — boar digger
        "mat_map": {"Material.003": (0.50, 0.44, 0.38), "Material": (0.62, 0.52, 0.44)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Head",
        "eye_r": 0.05, "eye_gap": 0.12, "eye_fwd": -0.10, "eye_up": 0.10,
        "nose_r": 0.06, "nose_up": 0.01,
        "target_h": 1.35,
    },
    "dozantler": {   # Horse.blend — antlered draft kin
        "mat_map": {"Material.003": (0.78, 0.66, 0.38), "Material.006": (0.42, 0.32, 0.20)},
        # the fore-aft horn pair reads as antlers from the profile views a
        # quadruped poses in — the name's identity mark (S122)
        "accessory": "horns", "acc_col": (0.62, 0.50, 0.34),
        "subd_wool": 2, "displace": None,
        # rot 0 posed it rear-to-camera with the head low (a hump); 45 was
        # still a rear three-quarter — 90 shows the side profile the probe
        # grid found clean (S122)
        "rot_z": 90.0, "action": "Idle", "frames": (20, 80),
        "head_bone": "Head",
        "eye_r": 0.05, "eye_gap": 0.12, "eye_fwd": -0.14, "eye_up": 0.14,
        "nose_r": 0.05, "nose_up": 0.02,
        "target_h": 1.6,
    },
    "cindpaw": {     # Dog.blend — ember pup
        "mat_map": {"Dog": (0.74, 0.30, 0.16)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Bone.003",
        "eye_r": 0.05, "eye_gap": 0.11, "eye_fwd": -0.11, "eye_up": 0.11,
        "nose_r": 0.045, "nose_up": 0.02,
        "target_h": 1.4,
    },
    # ---- S108 den wardens: four previously-unused licensed meshes, one
    # silhouette each. Dragon/Bat keep their baked eye meshes (no_eyes);
    # Cyclops gets a single bead (gap=0 folds the pair onto the midline).
    "dreadwyrm": {   # Dragon.blend — ember elder wyrm
        "mat_map": {"Main": (0.55, 0.20, 0.14), "Wings": (0.36, 0.14, 0.10),
                    "Belly": (0.80, 0.62, 0.42), "Claws": (0.88, 0.82, 0.70)},
        # pose-dominated rig: data-bake diverges (ext grew every pass) —
        # scale the DragonArmature OBJECT; EyeArmature follows by constraint
        "norm_obj": True,
        "no_eyes": True,  # baked Eyes mesh is armature-driven and follows
        "subd_wool": 2, "displace": None,
        # frame 10 folds the wings over the body (a blob at 80px); 20/30
        # spread the wings and show the belly (S122 probe)
        "rot_z": 0.0, "action": "Dragon_Flying", "frames": (20, 30),
        "head_bone": "Head",
        "eye_r": 0.05, "eye_gap": 0.10, "eye_fwd": -0.10, "eye_up": 0.10,
        "target_h": 1.5,
    },
    "gloamwing": {   # Bat.blend — dusk sovereign bat
        "mat_map": {"Main": (0.30, 0.23, 0.38), "Black": (0.12, 0.10, 0.16),
                    "Belly": (0.66, 0.60, 0.72), "Nose": (0.80, 0.50, 0.58)},
        "no_eyes": True,
        "subd_wool": 2, "displace": None,
        # Bat_Flying range is 0–30; the 'Face' bone is the real head driver
        # an upright bat is narrow — 1.2 left it a speck; 1.5 fills the frame
        "rot_z": 0.0, "action": "Bat_Flying", "frames": (0, 15),
        "head_bone": "Face",
        "eye_r": 0.05, "eye_gap": 0.10, "eye_fwd": -0.10, "eye_up": 0.10,
        "target_h": 1.5,
    },
    "cragmaw": {     # Cyclops.blend — granite moss giant, ONE bead eye
        "mat_map": {"Texture": (0.38, 0.46, 0.30)},
        "subd_wool": 2, "displace": None,
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Head",
        # chibi rig: bone tail sits INSIDE the giant head — positive eye_fwd
        # pushes the bead out to the face surface at -Y (probed -0.79×k);
        # 0.72/0.13 buried it at 80px — 0.95/0.17 clears the brow (S122)
        "eye_r": 0.17, "eye_gap": 0.0, "eye_fwd": 0.95, "eye_up": 0.10,
        "target_h": 1.6,
    },
    "hexfiend": {    # Demon.blend — cinder fiend prince
        "mat_map": {"Texture": (0.32, 0.11, 0.19)},
        "subd_wool": 2, "displace": None,
        # rot 35 hid the horned face behind its own brow — dead-on reads
        # the maw and horns (S122 probe); beads pushed out + bigger
        "rot_z": 0.0, "action": "Idle", "frames": (5, 25),
        "head_bone": "Head",
        "eye_r": 0.10, "eye_gap": 0.22, "eye_fwd": 0.90, "eye_up": 0.10,
        "target_h": 1.5,
    },
}

# generated batch mapping (tools/art/mesh_map_gen.py → mesh_cfg_gen.py).
# Hand-tuned entries in CFG always win.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from mesh_cfg_gen import CFG_EXT
    for _k, _v in CFG_EXT.items():
        CFG.setdefault(_k, _v)
except ImportError:
    pass

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


def shift_hsv(c, dh, ds, dv):
    """Hue/sat/value nudge — mirrors rig_auto.shift so mesh accessories get
    the same feature accent the primitive rigs stamp."""
    h, s, v = colorsys.rgb_to_hsv(*c)
    return colorsys.hsv_to_rgb((h + dh) % 1.0,
                               min(1, max(0, s * ds)),
                               min(1, max(0, v * dv)))


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


def eval_verts(o):
    """World-space vertex positions AFTER modifiers (armature deform).

    bound_box only sees undeformed mesh data — rigs whose rendered shape
    differs from bind-space (Skeleton, Yeti) normalized wrong from it.
    """
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    try:
        me = ev.to_mesh()
        pts = [ev.matrix_world @ v.co for v in me.vertices]
    finally:
        ev.to_mesh_clear()
    if not pts:
        pts = [o.matrix_world @ mathutils.Vector(v) for v in o.bound_box]
    return pts


def _loc_fcurves(act):
    """Yield fcurves across Blender versions — 5.x nests them under
    layers->strips->channelbags, 4.x kept act.fcurves. Dedupe by pointer:
    4.4/4.5 expose the SAME fcurve through both APIs — scaling each key
    twice per pass makes pose-dominated rigs (Cat) diverge."""
    seen = set()
    for lay in getattr(act, "layers", []):
        for st in lay.strips:
            for cb in getattr(st, "channelbags", []):
                for fc in cb.fcurves:
                    if fc.as_pointer() not in seen:
                        seen.add(fc.as_pointer())
                        yield fc
    for fc in getattr(act, "fcurves", []):
        if fc.as_pointer() not in seen:
            seen.add(fc.as_pointer())
            yield fc


def normalize(objs, target_h, norm_obj=False):
    """Uniform-scale the rig so the mesh stands target_h units, feet on z=0.

    Iterates: armature rigs deform in bone-data space and the deform
    output is not linear in either input alone (Dog resisted 4x→1.4x
    for several passes; Skeleton diverged when child location was also
    scaled). Each pass measures EVALUATED bounds and bakes the residual
    factor into bone rest matrices AND mesh verts — both sides of the
    deform conjugation.

    norm_obj rigs (S108 Dragon): pose-dominated rigs whose deform output
    GROWS as rest data shrinks (the bake and the pose fight — ext rose
    every pass, 3.5→2.5 on 0.6× passes) are scaled through the armature
    OBJECT instead, which multiplies the whole deform output linearly —
    verified 3.495→1.500 in one shot. Sibling armatures bone-constrained
    to it (Dragon's EyeArmature) follow for free. The parent's object
    scale round-trip caveat only applies to bake-style uniform meshes.
    """
    k = 1.0
    owner = None
    if norm_obj:
        lo, hi = 1e9, -1e9
        for o in objs:
            for w in eval_verts(o):
                lo = min(lo, w.z); hi = max(hi, w.z)
        kk = target_h / max(hi - lo, 0.001)
        owner = objs[0].find_armature() or (
            objs[0].parent if objs[0].parent and
            objs[0].parent.type == 'ARMATURE' else None)
        if owner is None:
            print("WARN norm_obj: no armature owner — falling back to bake")
        else:
            owner.scale = owner.scale * kk
            bpy.context.view_layer.update()
            lo2, hi2 = 1e9, -1e9
            for o in objs:
                for w in eval_verts(o):
                    lo2 = min(lo2, w.z); hi2 = max(hi2, w.z)
            resid = target_h / max(hi2 - lo2, 0.001)
            print("PASS ext=%.2f kk=%.3f (object-scale on %s)" %
                  (hi - lo, kk, owner.name))
            if abs(resid - 1.0) > 0.03:
                print("WARN norm_obj residual %.3f — deform not linear" %
                      resid)
            k = kk
    if owner is None:
        for _ in range(10):
            lo, hi = 1e9, -1e9
            for o in objs:
                for w in eval_verts(o):
                    lo = min(lo, w.z); hi = max(hi, w.z)
            kk = target_h / max(hi - lo, 0.001)
            print("PASS ext=%.2f kk=%.3f" % (hi - lo, kk))
            if abs(kk - 1.0) < 0.02:
                break
            k *= kk
            S = mathutils.Matrix.Scale(kk, 4)
            for o in bpy.data.objects:
                if o.type == 'ARMATURE':
                    o.data.transform(S)
            for o in objs:
                o.data.transform(S)
            # audit-51: pose-bone location F-curves are stored in bone-local
            # units — they do NOT scale with the baked data, and for rigs
            # whose deform is pose-dominated (Cat converged to a 2.0
            # skeleton no matter how small the verts) the ACTION'S
            # positions ARE the output. Scale every location channel by
            # this pass's kk.
            for act in bpy.data.actions:
                for fc in _loc_fcurves(act):
                    if fc.data_path.endswith("location"):
                        for kp in fc.keyframe_points:
                            kp.co[1] *= kk
                            kp.handle_left[1] *= kk
                            kp.handle_right[1] *= kk
            bpy.context.view_layer.update()
        else:
            # 10 passes without converging — sprite ships at whatever
            # residual scale remains; make it loud instead of silently
            # mis-sized
            print("WARN normalize unconverged after 10 passes kk=%.3f" % kk)
    # drop feet to the floor
    lo2 = 1e9
    for o in objs:
        for w in eval_verts(o):
            lo2 = min(lo2, w.z)
    for o in bpy.data.objects:
        if o.parent is None:
            o.location.z -= lo2
    # audit-51: center X/Y too — off-origin rigs (Dog.blend) were cropping
    # out of frame; without this only in-origin meshes framed right
    cx2, cy2, n2 = 0.0, 0.0, 0
    for o in objs:
        for w in eval_verts(o):
            cx2 += w.x; cy2 += w.y; n2 += 1
    for o in bpy.data.objects:
        if o.parent is None:
            o.location.x -= cx2 / max(n2, 1)
            o.location.y -= cy2 / max(n2, 1)
    bpy.context.view_layer.update()
    return k


def bone_attach(arm, bone_name, ob, world_m):
    """Parent `ob` to a bone so it lands at `world_m` right now and rides the
    bone afterward. The matrix_world setter already carries Blender's own
    bone-parent correction — hand-solving matrix_basis double-applies it."""
    ob.parent = arm
    ob.parent_type = 'BONE'
    ob.parent_bone = bone_name
    ob.matrix_world = world_m


def _head_pts(arm, mesh_obj, bone_name):
    """Pose-space positions of raw verts weighted >0.5 to the head bone —
    the cluster that IS the head geometry, whatever the rig does to the
    bone itself. None when the vgroup is missing or unweighted."""
    try:
        gi = mesh_obj.vertex_groups.find(bone_name)
    except Exception:
        gi = -1
    if gi < 0:
        return None
    owned = [i for i, v in enumerate(mesh_obj.data.vertices)
             if any(g.group == gi and g.weight > 0.5 for g in v.groups)]
    if not owned:
        return None
    # evaluated (posed) positions — but only for verts the mesh still owns;
    # subdiv blows up topology, so evaluate the RAW bind verts instead and
    # transform them by the bone's pose delta
    pb = arm.pose.bones[bone_name]
    pose_m = arm.matrix_world @ pb.matrix  # bone pose in world
    # approximate: move the rest-space vert cluster by the bone's pose
    # translation only (head marks tolerate ~0.05 drift)
    mw = mesh_obj.matrix_world
    delta = pose_m.translation - (arm.matrix_world @
                                arm.data.bones[bone_name].head_local)
    return [mw @ mesh_obj.data.vertices[i].co + delta for i in owned]


def head_group_top(arm, mesh_obj, bone_name):
    """Skull-top anchor from the mesh itself: evaluated positions of verts
    weighted to the head bone's vgroup. Pose-independent — the anchor sits
    on the head GEOMETRY wherever the rig actually puts it, so throat/jaw
    bones can't drag a crown under the chin (wolf Bone.003 did exactly
    that). Returns (htop Vector) or None."""
    pts = _head_pts(arm, mesh_obj, bone_name)
    if not pts:
        return None
    hi = max(p.z for p in pts)
    top = [p for p in pts if p.z > hi - 0.06]
    return mathutils.Vector((
        sum(p.x for p in top) / len(top),
        sum(p.y for p in top) / len(top), hi))


def head_group_span(arm, mesh_obj, bone_name):
    """(lo_z, hi_z) of the head-weighted vert cluster in pose space — the
    band eyes/noses must stay inside even when the bone tail sits somewhere
    nonsensical (Wolf's Bone.003 tail reports z=-0.53 under Idle f0)."""
    pts = _head_pts(arm, mesh_obj, bone_name)
    if not pts:
        return None
    zs = [p.z for p in pts]
    return min(zs), max(zs)


def real_head_bone(arm, mesh_obj, cfg_bn):
    """The cfg head bone can be an unweighted control/IK bone. Verify it by
    vertex weights: tally the vgroups of raw verts in the TOP band near the
    bone's rest tail (the skull crown cluster, not the jaw-weighted muzzle
    tip). Bind space only — evaluated meshes have post-subdiv topology and
    their indices no longer map to vertex groups."""
    if cfg_bn not in arm.data.bones:
        return cfg_bn
    mw = mesh_obj.matrix_world
    ws = [mw @ v.co for v in mesh_obj.data.vertices]
    if not ws:
        return cfg_bn
    hi = max(w.z for w in ws)
    lo = min(w.z for w in ws)
    tip = arm.matrix_world @ arm.data.bones[cfg_bn].tail_local
    idx = [i for i, w in enumerate(ws)
           if w.z > hi - 0.35 * (hi - lo)
           and (w.xy - tip.xy).length < 0.35 * (hi - lo)]
    if not idx:
        return cfg_bn
    tally = {}
    for i in idx:
        # distance-weighted: a raised wingtip can land in the top band near
        # the beak's xy (Eagle) — verts right at the rest tail must dominate
        # or the vote remaps the head anchor onto a wing bone (audit-53)
        d = (ws[i].xy - tip.xy).length / max(0.1 * (hi - lo), 0.01)
        for g in mesh_obj.data.vertices[i].groups:
            nm = mesh_obj.vertex_groups[g.group].name
            tally[nm] = tally.get(nm, 0.0) + g.weight / (1.0 + d)
    if not tally:
        return cfg_bn
    best = max(tally, key=tally.get)
    # margin: only override the cfg when the winner clearly beats it —
    # near-ties mean the cfg bone is still a valid head driver
    if (best != cfg_bn and best in arm.pose.bones
            and tally[best] > 1.5 * tally.get(cfg_bn, 0.0)):
        print("WARN head_bone '%s' is not weighted at the head — "
              "real driver '%s'" % (cfg_bn, best))
        return best
    return cfg_bn


def head_anchor(arm, bone_name, cfg, zcap=None, head_span=None):
    """Face anchor shared by eyes/accessories: muzzle dir (head→tail) +
    lateral cross. POSE-space coords only. Returns (center, fwd, lat)."""
    pb = arm.pose.bones[bone_name]
    h = arm.matrix_world @ pb.head
    t = arm.matrix_world @ pb.tail
    fwd = (t - h)
    fwd.z = 0
    if fwd.length < 1e-6 or fwd.length < 0.3 * (t - h).length:
        # near-vertical head bone (humanoid rigs like Skeleton): there is no
        # muzzle direction — use the model's authored -Y facing carried
        # through the rig's own yaw (rot_z), else rotated humanoids get an
        # eye line skewed ~35° off the face (audit-53)
        fwd = arm.matrix_world.to_3x3() @ mathutils.Vector((0.0, -1.0, 0.0))
        fwd.z = 0.0
        if fwd.length < 1e-6:
            fwd = mathutils.Vector((0.0, -1.0, 0.0))
    fwd = fwd.normalized()
    lat = mathutils.Vector((-fwd.y, fwd.x, 0.0))
    center = t + fwd * cfg["eye_fwd"] + mathutils.Vector((0, 0, cfg["eye_up"]))
    if cfg.get("eye_abs_z") is not None:
        # explicit world-z override — rigs whose vgroup bands leave the
        # visual face center unreachable (Alien: Head≤0.94, Head3≥0.98)
        center.z = cfg["eye_abs_z"]
        if head_span is not None:
            lo_h, hi_h = head_span
            sp = max(hi_h - lo_h, 1e-6)
            if center.z < lo_h - 0.1 * sp or center.z > hi_h + 0.1 * sp:
                print("WARN eye_abs_z %.2f outside head span %.2f..%.2f" %
                      (center.z, lo_h, hi_h))
        elif zcap is not None and not (
                zcap[0] - 0.05 <= center.z <= zcap[1] + 0.05):
            print("WARN eye_abs_z %.2f outside mesh z %.2f..%.2f" %
                  (center.z, zcap[0], zcap[1]))
    elif head_span is not None:
        # the head cluster's own z-band is the honest clamp: a bone tail can
        # sit under the floor (Wolf Bone.003 → -0.53) or past the muzzle and
        # the eyes still land inside the head's upper half (audit-53)
        lo_h, hi_h = head_span
        center.z = min(max(center.z, hi_h - 0.55 * (hi_h - lo_h)),
                       hi_h - 0.10 * (hi_h - lo_h))
    elif zcap is not None:
        lo_z, hi_z = zcap
        center.z = min(max(center.z, lo_z + 0.35 * (hi_z - lo_z)),
                       hi_z + 0.05 * (hi_z - lo_z))
    if zcap is not None:
        s = (zcap[1] - zcap[0]) / 1.4
        dxy = mathutils.Vector((center.x - t.x, center.y - t.y))
        if dxy.length > 0.6 * s:
            dxy.normalize()
            center.x = t.x + dxy.x * 0.6 * s
            center.y = t.y + dxy.y * 0.6 * s
    return center, fwd, lat, t


def add_eyes(arm, bone_name, cfg, m, zcap=None, head_span=None):
    """Ink beads auto-placed from the head bone — works on any rig."""
    center, fwd, lat, t = head_anchor(arm, bone_name, cfg, zcap, head_span)
    for sgn in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12,
                                             radius=cfg["eye_r"])
        e = bpy.context.active_object
        e.data.materials.append(m)
        p = center + lat * (cfg["eye_gap"] * sgn)
        bone_attach(arm, bone_name, e, mathutils.Matrix.Translation(p))
        bpy.ops.object.shade_smooth()
    print("EYES at", tuple(round(c, 3) for c in center))
    if cfg.get("nose_r"):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12,
                                             radius=cfg["nose_r"])
        e = bpy.context.active_object
        e.data.materials.append(m)
        p = t + fwd * (cfg["eye_fwd"] + 0.04) + mathutils.Vector(
            (0, 0, cfg["nose_up"]))
        if cfg.get("eye_abs_z") is not None:
            # nose shares the eyes' explicit z-space, else eye and nose
            # anchors disagree (audit-54)
            p.z = cfg["eye_abs_z"] - 0.06 + cfg["nose_up"]
        elif head_span is not None:
            p.z = min(max(p.z, head_span[0]), head_span[1])
        elif zcap is not None:
            p.z = min(max(p.z, zcap[0]), zcap[1] + 0.05 * (zcap[1] - zcap[0]))
        bone_attach(arm, bone_name, e,
                    mathutils.Matrix.Translation(p) @ mathutils.Matrix.Diagonal(
                        (1.15, 1.0, 0.8, 1)))


def add_accessory(arm, bone_name, cfg, accent_m, zcap, objs):
    """Identity marks the source mesh lacks — the same marks the primitive
    rigs stamp (rig_auto.ACCESSORY): crown/halo/horns/crest/fins/mask/wings
    as primitive parts bone-parented to the head so they ride the action.
    Anchored at the skull top (silhouette hi_z, not the bone tail — muzzle
    bones would put a crown on the snout tip)."""
    kind_s = cfg.get("accessory")
    if not kind_s:
        return
    # space-separated composite — a body mark (fins) plus a per-sid mark
    # (halo) must stack, or the per-sid mark silently drops the body mark
    # (audit-75 LOW-1: the single-slot precedence trap)
    kinds = kind_s.split()
    head_span = head_group_span(arm, objs[0], bone_name)
    face, fwd, lat, tail = head_anchor(arm, bone_name, cfg, zcap, head_span)
    hi_z = zcap[1] if zcap else face.z + 0.2
    s = (zcap[1] - zcap[0]) / 1.4 if zcap else 1.0  # normalized-height scale
    # measure the head's real extents around the FACE anchor (where the eyes
    # landed) — the skull column is the verts near the face's xy, which
    # excludes wings/body that merely share the silhouette top. Fixed
    # offsets bury marks inside wide skulls; measuring keeps them outside.
    hw_lat = 0.1 * s
    hw_fwd = 0.1 * s
    htop_z = hi_z
    htop = mathutils.Vector((face.x, face.y, hi_z))
    head_col = [v for o in objs for v in eval_verts(o)]
    for w in head_col:
        lv = (w.x - face.x) * lat.x + (w.y - face.y) * lat.y
        fv = (w.x - face.x) * fwd.x + (w.y - face.y) * fwd.y
        # z-slab AND xy window around the face — otherwise torso tops and
        # wing spans inflate "head width" (halo sized off the chest on
        # Horse, audit-53)
        if (abs(w.z - face.z) < 0.35 * s and abs(lv) < 0.5 * s
                and -0.6 * s < fv < 0.6 * s):
            hw_lat = max(hw_lat, abs(lv))
            hw_fwd = max(hw_fwd, fv)
    # skull top from the head-bone's OWN weighted verts — the cranium rides
    # whatever the bone does (throat-bone rigs like Wolf keep the crown on
    # the skull even when the bone tail sits under the chin). Fall back to
    # the face column if the bone owns no verts.
    gt = head_group_top(arm, objs[0], bone_name)
    if gt is not None:
        htop = gt
        htop_z = gt.z
    else:
        skull = [w for w in head_col
                 if abs((w.x - face.x) * lat.x + (w.y - face.y) * lat.y)
                 < 0.35 * s
                 and -0.60 * s < ((w.x - face.x) * fwd.x +
                                  (w.y - face.y) * fwd.y) < 0.15 * s
                 and w.z <= face.z + 0.45 * s]
        if skull:
            htop_z = max(w.z for w in skull)
            top_v = [w for w in skull if w.z > htop_z - 0.08 * s]
            htop = mathutils.Vector((
                sum(w.x for w in top_v) / len(top_v),
                sum(w.y for w in top_v) / len(top_v), htop_z))
        else:
            # silhouette top on a raised-wing bird is a WINGTIP — a mark
            # anchored there floats off the head; warn so batch can see it
            print("WARN accessory anchor fell back to silhouette top")
    # marks that must sit ON the head mid-level anchor at the face column
    hpos = mathutils.Vector((face.x, face.y, max(face.z, tail.z)))
    print("HEAD_EXT lat=%.2f fwd=%.2f htz=%.2f" % (hw_lat, hw_fwd, htop_z))
    placed = 0

    # sphere dims are expressed in the (lat, fwd, z) basis — a crest's
    # long axis must run fore-aft even on yawed rigs; world-Y only lucks
    # out when rot_z=0 (flarbeak got a lateral blade at rot_z=90, audit-53)
    basis = mathutils.Matrix(
        (lat, fwd, mathutils.Vector((0.0, 0.0, 1.0)))).transposed().to_4x4()

    def put(shape, p, dims, rot=None):
        nonlocal placed
        if shape == "sph":
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=12,
                                                 radius=1.0)
        else:
            bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=dims[0],
                                                depth=dims[1])
        e = bpy.context.active_object
        e.data.materials.append(accent_m)
        if shape == "sph":
            m = mathutils.Matrix.Translation(p) @ basis @ \
                mathutils.Matrix.Diagonal((*dims, 1.0))
        else:
            # cylinders are axis-aligned already; radius/depth carry size
            m = mathutils.Matrix.Translation(p)
        if rot is not None:
            m = m @ rot
        bone_attach(arm, bone_name, e, m)
        bpy.ops.object.shade_smooth()
        placed += 1

    # head-column top anchor: crown/halo/horns sit ON the skull, not the
    # body mid (quadruped heads project forward of mid)
    for kind in kinds:
      if kind == "crown":
        put("cyl", htop + mathutils.Vector((0, 0, 0.04 * s)),
            (0.13 * s, 0.11 * s))
        for dx in (-0.10, 0.0, 0.10):
            put("cyl", htop + fwd * (dx * s) + mathutils.Vector(
                (0, 0, 0.17 * s)), (0.045 * s, 0.18 * s))
      elif kind == "halo":
        # ring in the fwd-z plane so it reads as a full arc in profile too
        hr = max(0.18 * s, hw_lat * 1.15)
        for i in range(5):
            a = i * 1.2566
            put("sph", htop + fwd * (hr * math.cos(a)) + mathutils.Vector(
                (0, 0, 0.10 * s + 0.05 * s * math.sin(a))), (0.045 * s,) * 3)
      elif kind == "horns":
        # splay in the fwd-z plane (fore-aft V): a lateral horn pair is
        # invisible from the profile views quadrupeds use (tips tilt along
        # the view axis); a fore-aft pair reads as horns from any angle.
        # Chunky + tall so the tips clear the skull silhouette at 80px.
        for sx in (-1, 1):
            put("cyl", htop + fwd * (0.12 * s * sx) + mathutils.Vector(
                (0, 0, 0.05 * s)), (0.07 * s, 0.40 * s),
                mathutils.Matrix.Rotation(sx * 0.5, 4, lat))
      elif kind == "crest":
        put("sph", htop + mathutils.Vector((0, 0, 0.05 * s)),
            (0.06 * s, 0.17 * s, 0.20 * s))
      elif kind == "fins":
        # pectoral fins hug the body sides just behind the head — the
        # skull-band lat can be inflated by fins already on the source
        # mesh (Piranha's own fins counted as "head width"), so cap it
        for sx in (-1, 1):
            put("sph", hpos + lat * (min(hw_lat, 0.2 * s) * sx +
                0.03 * s * sx) - mathutils.Vector((0, 0, 0.04 * s)),
                (0.05 * s, 0.16 * s, 0.13 * s),
                mathutils.Matrix.Rotation(sx * 0.5, 4, 'Z'))
      elif kind == "hat":
        # rancher hat: wide brim + crown on the skull top (player identity).
        # Anchor to the head-band top (vgroup/skull column), NOT the global
        # silhouette top — on rigs where an appendage rises past the head,
        # hi_z is the appendage tip and the hat floats off the face (audit-54)
        hat_z = htop_z
        if hi_z - hat_z > 0.1 * s:
            print("WARN hat anchor %.2f below silhouette top %.2f — "
                  "something rises past the head" % (hat_z, hi_z))
        hat_top = mathutils.Vector((face.x, face.y, hat_z))
        put("cyl", hat_top - mathutils.Vector((0, 0, 0.05 * s)),
            (0.42 * s, 0.06 * s))
        put("cyl", hat_top + mathutils.Vector((0, 0, 0.07 * s)),
            (0.20 * s, 0.16 * s))
        # the alien's sculpted mouth socket now sits BELOW the eyes — it
        # reads as the character's open mouth, no plug needed
      elif kind == "mask":
        put("sph", hpos + fwd * (hw_fwd + 0.03 * s) - mathutils.Vector(
            (0, 0, 0.14 * s)), (0.28 * s, 0.06 * s, 0.11 * s))
      elif kind == "wings":
        # tilt about local X (= world lat once the basis maps it) so the
        # wing sheet rakes back instead of spinning around an axis it no
        # longer owns in the lat/fwd frame (audit-53)
        put("sph", hpos - fwd * (0.45 * s) - mathutils.Vector(
            (0, 0, 0.02 * s)), (0.36 * s, 0.07 * s, 0.20 * s),
            mathutils.Matrix.Rotation(0.5, 4, 'X'))
      else:
        print("WARN accessory '%s' unknown — none placed" % kind)
    print("ACCESSORY %s placed %d parts" % (kind_s, placed))


def fluff_shell(arm, wool, cfg, m):
    """Scatter squashed puff spheres on the wool's ellipsoid hull — the
    cauliflower fleece silhouette. Parented to the torso bone so they ride
    the animation."""
    import random
    bb = [wool.matrix_world @ mathutils.Vector(v) for v in wool.bound_box]
    lo = mathutils.Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = mathutils.Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    c = (lo + hi) / 2
    ext = (hi - lo) / 2 * cfg.get("shrink", 1.0)
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
    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'  # Blender ≥4.2
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'       # older enum id
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

    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    src = meshes[0]
    # the processed mesh's OWN deformer, not whatever armature iterates
    # first — Dragon ships DragonArmature + constrained EyeArmature and
    # bpy.data order is not load-bearing (audit-61 L6)
    arm = src.find_armature() or next(
        (o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
    if arm is None:
        raise RuntimeError("no armature in scene")
    if len(meshes) > 1:
        # only the first mesh is recolored/normalized — siblings still render
        # at original scale and can poison the sprite (audit-52)
        print("WARN %d mesh objects — only '%s' is processed" %
              (len(meshes), src.name))
    for o in bpy.data.objects:
        # respect objects the source author hid (cutters/helpers) — only
        # unhide render-hidden ones we actually need (audit-53)
        if not o.hide_get():
            o.hide_render = False

    # face the camera before anything else — eyes normalize against this pose
    arm.rotation_euler.z = math.radians(cfg.get("rot_z", 0.0))
    bpy.context.view_layer.update()

    if cfg.get("zone_mats"):
        # single-material mesh recolored by height bands — faces get the
        # zone material matching their bind-space z fraction (player's
        # jacket/trousers/skin on Alien_Tall)
        objs = [src]
        if cfg.get("strip_islands"):
            # the source's baked eyeballs are disconnected islands floating
            # in front of the upper head — drop small islands that live
            # entirely in the upper-front zone. Thresholds are fractions of
            # the bind z-span (audit-54): Alien's eyeballs sit fz>0.45,
            # fy<-0.10; arms survive on fz_min≈0.30 (the y guard alone
            # would NOT protect them — their fy_max is only −0.07).
            import bmesh
            bm = bmesh.new()
            bm.from_mesh(src.data)
            zlo_i = min(v.co.z for v in src.data.vertices)
            zspan_i = max(max(v.co.z for v in src.data.vertices) - zlo_i,
                          1e-6)
            seen = set()
            doomed = []
            for f in bm.faces:
                if f.index in seen:
                    continue
                stack, isl = [f], []
                while stack:
                    g = stack.pop()
                    if g.index in seen:
                        continue
                    seen.add(g.index)
                    isl.append(g)
                    for e in g.edges:
                        for lf in e.link_faces:
                            if lf.index not in seen:
                                stack.append(lf)
                zs = [v.co.z for g in isl for v in g.verts]
                ys = [v.co.y for g in isl for v in g.verts]
                fz_min = (min(zs) - zlo_i) / zspan_i
                fy_max = max(ys) / zspan_i
                hit = (len(isl) < cfg.get("strip_max_faces", 200)
                       and fz_min > 0.42 and fy_max < -0.10)
                if hit:
                    doomed += isl
                print("ISLAND faces=%d fz=%.2f..%.2f fy=%.2f..%.2f %s" % (
                    len(isl), (min(zs) - zlo_i) / zspan_i,
                    (max(zs) - zlo_i) / zspan_i, min(ys) / zspan_i, fy_max,
                    "DROP" if hit else "keep"))
            bmesh.ops.delete(bm, geom=doomed, context='FACES')
            bm.to_mesh(src.data)
            bm.free()
            want = cfg.get("strip_expect_faces")
            if want is not None and len(doomed) != want:
                print("WARN strip_islands dropped %d faces, expected %d — "
                      "heuristics misfired" % (len(doomed), want))
        zmin = min(v.co.z for v in src.data.vertices)
        zmax = max(v.co.z for v in src.data.vertices)
        zspan = max(zmax - zmin, 1e-6)
        src.data.materials.clear()  # zone indices must own slots 0..n
        for zi, (z0, z1, col) in enumerate(cfg["zone_mats"]):
            src.data.materials.append(mat(col, "zone%d" % zi))
        zones = cfg["zone_mats"]
        stray = 0
        for p in src.data.polygons:
            zc = (sum(src.data.vertices[vi].co.z for vi in p.vertices)
                  / len(p.vertices) - zmin) / zspan
            hit = False
            for zi, (z0, z1, col) in enumerate(zones):
                if z0 <= zc < z1:
                    p.material_index = zi
                    hit = True
                    break
            if not hit:
                # a gap/overrun between bands must not keep a stale index
                # (audit-54) — snap to the nearest zone edge
                stray += 1
                p.material_index = min(range(len(zones)), key=lambda zi:
                    min(abs(zc - zones[zi][0]), abs(zc - zones[zi][1])))
        if stray:
            print("WARN zone_mats: %d faces fell outside every band" % stray)
        smooth(src)
        subdiv(src, cfg["subd_wool"])
        d = cfg["displace"]
        if d:
            displace(src, d["scale"], d["strength"], d["detail"])
        wm = sm = None
    elif cfg.get("mat_map"):
        # audit-51: multi-material meshes — recolor every named slot to a
        # palette color, keep the mesh whole (no wool/skin split)
        objs = [src]
        pal = {name: mat(col, name) for name, col in cfg["mat_map"].items()}
        slots = []
        for i, m in enumerate(src.data.materials):
            nm = m.name if m else ""
            slots.append(nm)
            if nm in pal:
                src.data.materials[i] = pal[nm]
        dead = set(pal) - set(slots); bare = set(slots) - set(pal) - {""}
        if dead or bare:
            print("WARN mat_map: unused=%s uncolored=%s slots=%s" %
                  (sorted(dead), sorted(bare), slots))
        smooth(src)
        subdiv(src, cfg["subd_wool"])
        d = cfg["displace"]
        if d:
            displace(src, d["scale"], d["strength"], d["detail"])
        wm = sm = None
    else:
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
        objs = [wool, skin]

    k = normalize(objs, cfg["target_h"], cfg.get("norm_obj", False))
    print("scale k=%.4f faces: %s" %
          (k, {o.name: len(o.data.polygons) for o in objs}))

    # report head-bone world position POST-normalize — tune eye params off it
    head_bn = real_head_bone(arm, objs[0], cfg.get("head_bone", "Head"))
    hb = arm.pose.bones.get(head_bn)
    if cfg.get("no_eyes"):
        hb = None
    if hb is None and not cfg.get("no_eyes"):
        print("WARN head_bone '%s' missing — sprite will render EYELESS" % head_bn)
    if hb:
        wh = arm.matrix_world @ hb.head
        wt = arm.matrix_world @ hb.tail
        print("HEAD_BONE world head=%s tail=%s" %
              (tuple(round(c, 3) for c in wh), tuple(round(c, 3) for c in wt)))

    em = mat(INK, "ink")
    # assign the action + settle on frame f0 BEFORE placing eyes/accessories:
    # bone-parented parts store an offset against the CURRENT pose — if the
    # action only starts driving the rig afterwards, the f0 pose delta
    # drags marks off the head (wolf horns landed past the muzzle)
    if not arm.animation_data:
        arm.animation_data_create()
    act = bpy.data.actions.get(cfg["action"])
    if act:
        arm.animation_data.action = act
        print("action %s range %s" % (act.name, act.frame_range))
        if cfg["frames"][0] < act.frame_range[0] or cfg["frames"][1] > act.frame_range[1]:
            print("WARN frames %s outside action range %s — f0==f1 possible"
                  % (cfg["frames"], tuple(act.frame_range)))
    else:
        print("WARN action '%s' missing — f0==f1 static frames" % cfg["action"])
    s.frame_set(int(cfg["frames"][0]))
    bpy.context.view_layer.update()

    zlo = zhi = None
    if hb:
        for o in objs:
            for w in eval_verts(o):
                zlo = w.z if zlo is None else min(zlo, w.z)
                zhi = w.z if zhi is None else max(zhi, w.z)
        hspan = head_group_span(arm, objs[0], head_bn)
        add_eyes(arm, head_bn, cfg, em,
                 (zlo, zhi) if zlo is not None else None, hspan)
    if cfg.get("accessory"):
        if hb is None:
            print("WARN accessory '%s' skipped — head bone missing" %
                  cfg["accessory"])
        else:
            # same hue-shift accent the primitive rigs use for feature marks,
            # with a value floor — dark-bodied species produce near-black
            # accents that vanish at 80px
            main_col = (next(iter(cfg["mat_map"].values()))
                        if cfg.get("mat_map")
                        else (cfg["zone_mats"][-1][2]
                              if cfg.get("zone_mats") else cfg["mats"][0]))
            acc = shift_hsv(main_col, 0.45, 1.4, 0.95)
            h_, s_, v_ = colorsys.rgb_to_hsv(*acc)
            if v_ < 0.6:
                acc = colorsys.hsv_to_rgb(h_, min(1.0, s_ * 1.3), 0.68)
            acc = cfg.get("acc_col", acc)
            add_accessory(arm, head_bn, cfg,
                          mat(acc, "accent"),
                          (zlo, zhi) if zlo is not None else None, objs)
    if cfg.get("puffs"):
        if wm is None:
            # zone_mats/mat_map entries have no wool material — a None
            # material crashes mid-render (audit-54); use the lowest zone
            # (trousers/fur-level) or the first mapped color
            wm = mat(cfg["zone_mats"][0][2] if cfg.get("zone_mats")
                     else next(iter(cfg["mat_map"].values())), "puff")
        fluff_shell(arm, objs[0], cfg["puffs"], wm)

    light_rig()
    camera()
    for fi, fr in enumerate(cfg["frames"]):
        s.frame_set(int(fr))
        render(sid, fi)


main()
