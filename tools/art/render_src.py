"""Raw-view renderer: open a .blend, light it with the poster rig, shoot the
iso camera, dump tools/art/render/src_<name>.png — for inspecting source assets.

    blender -b <model.blend> -P tools/art/render_src.py -- out_name
"""
import bpy, sys, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "render")


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


def camera(scale):
    bpy.ops.object.camera_add(location=(3.6, -5.6, 2.9))
    cam = bpy.context.active_object
    bpy.ops.object.constraint_add(type='TRACK_TO')
    tgt = bpy.data.objects.new("tgt", None)
    bpy.context.collection.objects.link(tgt)
    tgt.location = (0, 0, 0.5)
    cam.constraints[-1].target = tgt
    cam.constraints[-1].track_axis = 'TRACK_NEGATIVE_Z'
    cam.constraints[-1].up_axis = 'UP_Y'
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = scale
    bpy.context.scene.camera = cam


def main():
    name = sys.argv[-1] if len(sys.argv) > 1 and sys.argv[-1] != "--" else "src"
    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x = s.render.resolution_y = 512
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.view_settings.view_transform = 'Standard'
    s.view_settings.look = 'None'
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGBA'
    # normalize scale: source packs vary wildly in units
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if meshes:
        import mathutils
        hi = 0.0
        for o in meshes:
            for v in o.bound_box:
                hi = max(hi, (o.matrix_world @ mathutils.Vector(v)).z)
        if hi > 0:
            k = 1.6 / hi
            for o in bpy.data.objects:
                if o.parent is None:
                    o.scale = (o.scale[0] * k, o.scale[1] * k, o.scale[2] * k)
    light_rig()
    camera(2.4)
    os.makedirs(OUT, exist_ok=True)
    s.render.filepath = os.path.join(OUT, "src_%s.png" % name)
    bpy.ops.render.render(write_still=True)
    print("rendered src_%s" % name)


main()
