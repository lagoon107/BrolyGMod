# Run: blender -b -P inspect_fbx.py -- <path to fbx>
import bpy, sys

fbx = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=fbx)

for ob in bpy.data.objects:
    print("OBJ", ob.name, ob.type, "scale", tuple(round(s, 3) for s in ob.scale),
          "rot", tuple(round(r, 3) for r in ob.rotation_euler), "dims", tuple(round(d, 3) for d in ob.dimensions))
    if ob.type == 'MESH':
        me = ob.data
        print("   verts", len(me.vertices), "faces", len(me.polygons), "groups", len(ob.vertex_groups),
              "shapekeys", len(me.shape_keys.key_blocks) if me.shape_keys else 0)
        for m in me.materials:
            tex = []
            if m and m.use_nodes:
                tex = [n.image.name for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
            print("   MAT", m.name if m else None, tex)

for ob in bpy.data.objects:
    if ob.type != 'ARMATURE':
        continue
    mw = ob.matrix_world
    for b in ob.data.bones:
        h = mw @ b.head_local
        t = mw @ b.tail_local
        print("BONE", b.name, "parent=", b.parent.name if b.parent else None,
              "head=", tuple(round(v, 3) for v in h), "tail=", tuple(round(v, 3) for v in t))
print("ACTIONS", [a.name for a in bpy.data.actions])
