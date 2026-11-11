import bpy
print("=== SCENE ===")
for o in bpy.data.objects:
    info = "%-24s type=%-10s" % (o.name, o.type)
    if o.type == 'MESH':
        info += " verts=%d faces=%d" % (len(o.data.vertices), len(o.data.polygons))
        info += " mats=%s" % [m.name if m else None for m in o.data.materials]
        vg = [g.name for g in o.vertex_groups]
        if vg:
            info += " vgroups=%d" % len(vg)
    if o.type == 'ARMATURE':
        info += " bones=%d" % len(o.data.bones)
        info += " bonenames=%s" % [b.name for b in o.data.bones][:20]
    print(info)
print("=== ACTIONS ===")
for a in bpy.data.actions:
    print("action %-24s frames %s" % (a.name, a.frame_range))
print("=== MODIFIERS ===")
for o in bpy.data.objects:
    for m in o.modifiers:
        print(o.name, m.type)
