# Blender script: render a 1x1xH cliff cube (top face at z=0) with the same
# dimetric camera as render_tile.py -> the two visible side faces project
# as the game's wall parallelograms. post_wall.py extracts them.
#
#   blender --factory-startup -b -P render_wall.py -- cliff
#
# Output: tools/art/render/wall_<id>_f0.png (256x256 RGBA)

import bpy
import math
import mathutils
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")

CFG = {
    "cliff": {"col_sx": (0.42, 0.36, 0.44),   # #6b5d70 — lit +x face
              "col_sy": (0.35, 0.29, 0.40),   # #584a66 — shaded +y face
              "h": 0.40, "seed": 7},
}

HALF = 0.5


def mat(rgb, name, rough=0.95):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb[:3], 1.0)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb[:3], 1.0)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Specular IOR Level"].default_value = 0.12
    return m


def main():
    cid = sys.argv[-1]
    cfg = CFG[cid]
    h = cfg["h"]

    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)

    # cube: top at z=0 (tile surface), sides dropping to z=-h
    msx = mat(cfg["col_sx"], "face_sx")
    msy = mat(cfg["col_sy"], "face_sy")
    mtop = mat((0.30, 0.50, 0.22), "top")  # only visible past the frame crop
    verts = [(-HALF, -HALF, 0), (HALF, -HALF, 0), (HALF, HALF, 0), (-HALF, HALF, 0),
             (-HALF, -HALF, -h), (HALF, -HALF, -h), (HALF, HALF, -h), (-HALF, HALF, -h)]
    # faces: 0=top,1=+x side,2=+y side (camera at -x,-y sees -x/-y — but the
    # game's walls are the +x/+y faces toward the low-screen viewer, so the
    # camera below is placed at +x,+y,-z? no — same azimuth as tiles, which
    # shows the -x/-y sides; whichever sides render, post labels them)
    # faces 3,4 (the -x/-y sides) are the only ones the camera sees —
    # they carry the game's lit/shaded pair (audit-57: indices must stay
    # inside the 3 appended slots; out-of-range silently falls back)
    faces = [(0, 1, 2, 3), (1, 5, 6, 2), (2, 6, 7, 3), (0, 4, 5, 1), (3, 7, 4, 0)]
    me = bpy.data.meshes.new("cliff")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("cliff", me)
    bpy.context.collection.objects.link(ob)
    for m in (mtop, msx, msy):
        ob.data.materials.append(m)
    for i, p in enumerate(me.polygons):
        p.material_index = (0, 1, 2, 1, 2)[i]
        p.use_smooth = False

    # strata texture on the side faces: subdivide FIRST (audit-56 lesson),
    # then displace — a 6-face cube has nothing to displace otherwise
    sub = ob.modifiers.new("sub", 'SUBSURF')
    sub.subdivision_type = 'SIMPLE'
    sub.levels = 3
    tex = bpy.data.textures.new("strata", type='CLOUDS')
    tex.noise_scale = 0.35
    tex.noise_depth = 1
    mod = ob.modifiers.new("disp", 'DISPLACE')
    mod.texture = tex
    mod.strength = 0.02

    # kin light rig
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

    # same dimetric camera, but tracked at mid-wall so the side faces land
    # in frame (256x256, ortho 1.5 -> 1.5 units on both axes)
    az = math.radians(45)
    el = math.radians(30)
    dist = 4.0
    cx = dist * math.cos(el) * math.cos(az + math.pi)
    cy = dist * math.cos(el) * math.sin(az + math.pi)
    cz = dist * math.sin(el) - h * 0.5
    bpy.ops.object.camera_add(location=(cx, cy, cz))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, -h * 0.5)
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 1.5
    s = bpy.context.scene
    s.camera = cam

    try:
        s.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = 256
    s.render.resolution_y = 256
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "wall_%s_f0.png" % cid)
    bpy.ops.render.render(write_still=True)
    print("rendered wall", cid)


main()
