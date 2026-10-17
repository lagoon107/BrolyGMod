# Debug render of an SMD's triangles (bind pose), front + side, workbench.
# Run: blender -b --factory-startup -P render_smd.py -- <file.smd> <out_prefix>
import bpy, sys, math
from mathutils import Vector

smd, out = sys.argv[sys.argv.index("--") + 1:][:2]
verts, faces = [], []
with open(smd) as f:
    lines = f.read().splitlines()
i = lines.index("triangles") + 1
while lines[i] != "end":
    tri = []
    for k in range(3):
        p = lines[i + 1 + k].split()
        tri.append(len(verts))
        verts.append((float(p[1]), float(p[2]), float(p[3])))
    faces.append(tri)
    i += 4

bpy.ops.wm.read_factory_settings(use_empty=True)
me = bpy.data.meshes.new("m")
me.from_pydata(verts, [], faces)
ob = bpy.data.objects.new("m", me)
bpy.context.scene.collection.objects.link(ob)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_WORKBENCH'
sc.render.resolution_x, sc.render.resolution_y = 600, 800
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 110
sc.collection.objects.link(cam)
sc.camera = cam
for name, pos in (("front", (200, 0, 50)), ("side", (0, -200, 50))):
    cam.location = pos
    d = Vector((0, 0, 50)) - Vector(pos)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = out + "_" + name + ".png"
    bpy.ops.render.render(write_still=True)
