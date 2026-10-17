"""Convert Broly.fbx (MMD-style rig) into ValveBiped SMDs + QC + TGA/VMT for studiomdl.

Run: blender -b --factory-startup -P build_broly.py -- <fbx> <ref_bones.json> <out_dir>

Approach ("proportions trick"):
  * Pose Broly's limbs so every segment points the same way as the m_anm.mdl reference pose.
  * Build a ValveBiped skeleton whose bone rotations equal the reference and whose joint
    positions are Broly's, and bind the posed mesh to it.
  * A delta "proportions" sequence (Broly skeleton minus reference) is autoplayed so all
    included ValveBiped animations keep Broly's proportions.
"""
import bpy, json, math, os, sys
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from smdlib import world_xforms, write_skeleton_smd, xform_mul, xform_inv, mat_vec, mat_t

argv = sys.argv[sys.argv.index("--") + 1:]
FBX, REF_JSON, OUT = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)

TARGET_HEIGHT = 96.0          # Source units (a stock player is ~72)
MAT_PREFIX = "models/broly/"
DOUBLE_SIDED = {"hair", "apron", "skirt", "eyebrows", "necklace_cloth", "pants"}

# ---------------------------------------------------------------- reference skeleton
ref = json.load(open(REF_JSON))
ref_names = [b["name"] for b in ref]
ref_parents = [b["parent"] for b in ref]
ref_world = world_xforms(ref)
RI = {n: i for i, n in enumerate(ref_names)}
VB = "ValveBiped.Bip01_"


def ref_pos(n):
    return Vector(ref_world[RI[VB + n]][1])


# ---------------------------------------------------------------- import
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
body = next(o for o in bpy.data.objects if o.type == 'MESH')

# The ValveBiped reference pose in m_anm.mdl faces -Y with left at +X, same as Blender,
# so SMD space = Blender space; only scale.
height = body.dimensions.z
SCALE = TARGET_HEIGHT / height
ROT = Matrix.Identity(3)
TO_SRC = Matrix.Diagonal((SCALE, SCALE, SCALE, 1)) @ ROT.to_4x4()
FROM_SRC_DIR = ROT.inverted()
arm_inv3 = arm.matrix_world.to_3x3().inverted()


def src_dir_to_arm(v):
    return (arm_inv3 @ (FROM_SRC_DIR @ v)).normalized()


# ---------------------------------------------------------------- 1) pose Broly into the reference pose
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='POSE')
PB = arm.pose.bones


def head(n):
    return PB[n].head.copy()


def rotate_about(pbname, R):
    pb = PB[pbname]
    h = pb.head.copy()
    pb.matrix = Matrix.Translation(h) @ R.to_4x4() @ Matrix.Translation(-h) @ pb.matrix
    bpy.context.view_layer.update()


def align(pbname, to_bone, ref_from, ref_to, sec=None):
    """Rotate pbname so head(pbname)->head(to_bone) points like ref_from->ref_to.
    sec = (broly_a, broly_b, ref_a, ref_b) secondary vector to fix roll."""
    cur = (head(to_bone) - head(pbname)).normalized()
    want = src_dir_to_arm(ref_pos(ref_to) - ref_pos(ref_from))
    if sec is None:
        R = cur.rotation_difference(want).to_matrix()
    else:
        cs = (head(sec[1]) - head(sec[0]))
        ws = src_dir_to_arm(ref_pos(sec[3]) - ref_pos(sec[2]))

        def frame(p, s):
            z = p.normalized()
            x = (s - z * s.dot(z)).normalized()
            return Matrix((x, z.cross(x), z)).transposed()
        R = frame(want, ws) @ frame(cur, cs).transposed()
    rotate_about(pbname, R)


FINGERS = [("Thumb", "0", ("0", "1", "2")), ("IndexFinger", "1", ("1", "2", "3")),
           ("MiddleFinger", "2", ("1", "2", "3")), ("RingFinger", "3", ("1", "2", "3")),
           ("LittleFinger", "4", ("1", "2", "3"))]

for side, s in (("Left", "L"), ("Right", "R")):
    align(f"{side} shoulder", f"{side} arm", f"{s}_Clavicle", f"{s}_UpperArm")
    align(f"{side} arm", f"{side} elbow", f"{s}_UpperArm", f"{s}_Forearm")
    align(f"{side} elbow", f"{side} wrist", f"{s}_Forearm", f"{s}_Hand")
    align(f"{side} wrist", f"MiddleFinger1_{s}", f"{s}_Hand", f"{s}_Finger2",
          sec=(f"LittleFinger1_{s}", f"IndexFinger1_{s}", f"{s}_Finger4", f"{s}_Finger1"))
    for fname, vi, segs in FINGERS:
        vb = [f"{s}_Finger{vi}", f"{s}_Finger{vi}1", f"{s}_Finger{vi}2"]
        bn = [f"{fname}{k}_{s}" for k in segs]
        align(bn[0], bn[1], vb[0], vb[1])
        align(bn[1], bn[2], vb[1], vb[2])
    align(f"{side} leg", f"{side} knee", f"{s}_Thigh", f"{s}_Calf")
    align(f"{side} knee", f"{side} ankle", f"{s}_Calf", f"{s}_Foot")
    align(f"{side} ankle", f"{side} toe", f"{s}_Foot", f"{s}_Toe0")

# ---------------------------------------------------------------- 2) ValveBiped skeleton at Broly's joints
def to_src(p_arm):
    return list(TO_SRC @ (arm.matrix_world @ p_arm))


JOINTS = {"Pelvis": "Hips", "Spine": "Spine", "Spine2": "Chest", "Neck1": "Neck", "Head1": "Head"}
for side, s in (("Left", "L"), ("Right", "R")):
    JOINTS.update({f"{s}_Clavicle": f"{side} shoulder", f"{s}_UpperArm": f"{side} arm",
                   f"{s}_Forearm": f"{side} elbow", f"{s}_Hand": f"{side} wrist",
                   f"{s}_Thigh": f"{side} leg", f"{s}_Calf": f"{side} knee",
                   f"{s}_Foot": f"{side} ankle", f"{s}_Toe0": f"{side} toe"})
    for fname, vi, segs in FINGERS:
        for vb_suffix, k in zip(("", "1", "2"), segs):
            JOINTS[f"{s}_Finger{vi}{vb_suffix}"] = f"{fname}{k}_{s}"

jpos = {VB + k: to_src(head(v)) for k, v in JOINTS.items()}
lerp = lambda a, b, t: [a[i] + (b[i] - a[i]) * t for i in range(3)]
jpos[VB + "Spine1"] = lerp(jpos[VB + "Spine"], jpos[VB + "Spine2"], 0.5)
jpos[VB + "Spine4"] = lerp(jpos[VB + "Spine2"], jpos[VB + "Neck1"], 0.73)

k_scale = jpos[VB + "Head1"][2] / ref_world[RI[VB + "Head1"]][1][2]
new_world = []
for i, b in enumerate(ref):
    R = ref_world[i][0]
    if b["name"] in jpos:
        new_world.append((R, jpos[b["name"]]))
    else:  # helper bones (forward, hand attachments): reference offset, scaled
        p = ref_parents[i]
        local = xform_mul(xform_inv(ref_world[p]), ref_world[i])
        new_world.append(xform_mul(new_world[p], (local[0], [v * k_scale for v in local[1]])))

# ---------------------------------------------------------------- 3) weights
BROLY_TO_VB = {v: VB + k for k, v in JOINTS.items()}


def vb_for(bname):
    b = arm.data.bones.get(bname)
    while b is not None:
        if b.name in BROLY_TO_VB:
            return RI[BROLY_TO_VB[b.name]]
        b = b.parent
    return RI[VB + "Pelvis"]


group_bone = {g.index: vb_for(g.name) for g in body.vertex_groups}

bpy.ops.object.mode_set(mode='OBJECT')
dg = bpy.context.evaluated_depsgraph_get()
me = body.evaluated_get(dg).to_mesh()
me.calc_loop_triangles()
orig = body.data
mw = body.matrix_world
nrm_m = (ROT @ mw.to_3x3()).inverted().transposed()
uv = me.uv_layers.active.data

vert_links = []
for v in orig.vertices:
    acc = {}
    for g in v.groups:
        if g.weight > 0.0 and g.group in group_bone:
            bi = group_bone[g.group]
            acc[bi] = acc.get(bi, 0.0) + g.weight
    links = sorted(acc.items(), key=lambda kv: -kv[1])[:3]
    tot = sum(w for _, w in links)
    vert_links.append([(bi, w / tot) for bi, w in links] if tot > 0 else None)

# Unweighted vertices (e.g. the earrings) copy the weights of the nearest weighted vertex,
# otherwise they'd stay pinned at the pelvis and stretch when animated.
from mathutils import kdtree
weighted = [i for i, l in enumerate(vert_links) if l]
kd = kdtree.KDTree(len(weighted))
for i in weighted:
    kd.insert(orig.vertices[i].co, i)
kd.balance()
unweighted = [i for i, l in enumerate(vert_links) if not l]
for i in unweighted:
    vert_links[i] = vert_links[kd.find(orig.vertices[i].co)[1]]
print("unweighted verts fixed:", len(unweighted))

# The necklace chain is partly skinned to the head; pin it to the neck so it doesn't stretch
# when the head tilts.
head_i, neck_i = RI[VB + "Head1"], RI[VB + "Neck1"]
neck_mats = {i for i, m in enumerate(orig.materials) if m and m.use_nodes and any(
    n.type == 'TEX_IMAGE' and n.image and "necklace" in n.image.name.lower() for n in m.node_tree.nodes)}
neck_verts = {v for p in orig.polygons if p.material_index in neck_mats for v in p.vertices}
for vi in neck_verts:
    merged = {}
    for bi, w in vert_links[vi]:
        bi = neck_i if bi == head_i else bi
        merged[bi] = merged.get(bi, 0.0) + w
    vert_links[vi] = sorted(merged.items(), key=lambda kv: -kv[1])

vert_pos = [list(TO_SRC @ (mw @ v.co)) for v in me.vertices]


# ---------------------------------------------------------------- 4) materials / textures
def tex_name(mat):
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and not n.image.name.lower().startswith("head.spa"):
                return n.image
    return None


images, slot_mat = {}, []
for mat in orig.materials:
    img = tex_name(mat)
    if img is None:
        slot_mat.append("missing")
        continue
    base = os.path.splitext(os.path.basename(img.filepath or img.name))[0]
    base = base.split(".")[0].lower().replace(" ", "_")
    images[base] = img
    slot_mat.append(base)

corner_n = me.corner_normals
tris = []
for lt in me.loop_triangles:
    verts = []
    for li, vi in zip(lt.loops, lt.vertices):
        n = (nrm_m @ Vector(corner_n[li].vector)).normalized()
        links = vert_links[vi]
        verts.append((links[0][0], vert_pos[vi], list(n), list(uv[li].uv), links))
    tris.append((slot_mat[lt.material_index], verts))

write_skeleton_smd(os.path.join(OUT, "broly_ref.smd"), ref_names, ref_parents, new_world, tris)
write_skeleton_smd(os.path.join(OUT, "broly_proportions.smd"), ref_names, ref_parents, new_world)
write_skeleton_smd(os.path.join(OUT, "anm_reference.smd"), ref_names, ref_parents, ref_world)


def pot(n):
    return min(2048, 1 << max(2, int(round(math.log2(max(n, 4))))))


tex_report = {}
for base, img in images.items():
    img.reload()
    w, h = img.size
    if w == 0:
        print("MISSING IMAGE", base, img.filepath)
        continue
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    alpha = px[3::4]
    has_alpha = bool((alpha < 0.5).mean() > 0.002)
    if (pot(w), pot(h)) != (w, h):
        img.scale(pot(w), pot(h))
    img.filepath_raw = os.path.join(OUT, base + ".tga")
    img.file_format = 'TARGA_RAW'
    img.save()
    tex_report[base] = {"size": [pot(w), pot(h)], "alpha": has_alpha}
    vmt = ['"VertexLitGeneric"', "{", f'\t"$basetexture" "{MAT_PREFIX}{base}"', '\t"$halflambert" "1"']
    if has_alpha:
        vmt.append('\t"$alphatest" "1"')
    if has_alpha or base in DOUBLE_SIDED:
        vmt.append('\t"$nocull" "1"')
    vmt.append("}")
    open(os.path.join(OUT, base + ".vmt"), "w").write("\n".join(vmt) + "\n")

# ---------------------------------------------------------------- 5) physics boxes (ragdoll)
PHYS = ["Pelvis", "Spine2", "Head1"] + [f"{s}_{p}" for s in "LR" for p in
                                        ("UpperArm", "Forearm", "Hand", "Thigh", "Calf", "Foot")]
phys_idx = {RI[VB + p] for p in PHYS}


def phys_owner(bi):
    while bi >= 0 and bi not in phys_idx:
        bi = ref_parents[bi]
    return bi if bi >= 0 else RI[VB + "Pelvis"]


pts = {bi: [] for bi in phys_idx}
for vi, links in enumerate(vert_links):
    if links[0][1] >= 0.6:
        pts[phys_owner(links[0][0])].append(vert_pos[vi])

phys_tris = []
CUBE_F = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
for bi, plist in pts.items():
    if len(plist) < 8:
        continue
    R, t = new_world[bi]
    Rt = mat_t(R)
    loc = np.array([mat_vec(Rt, [p[0] - t[0], p[1] - t[1], p[2] - t[2]]) for p in plist])
    lo, hi = np.percentile(loc, 2, axis=0), np.percentile(loc, 98, axis=0)
    c, half = (lo + hi) / 2, (hi - lo) / 2 * 0.9
    corners = []
    for ix in (-1, 1):
        for iy in (-1, 1):
            for iz in (-1, 1):
                lp = c + half * np.array([ix, iy, iz])
                corners.append([mat_vec(R, list(lp))[k] + t[k] for k in range(3)])
    for f in CUBE_F:
        for tri in ((f[0], f[1], f[2]), (f[0], f[2], f[3])):
            phys_tris.append(("phys", [(bi, corners[q], [0, 0, 1], [0, 0], [(bi, 1.0)]) for q in tri]))

write_skeleton_smd(os.path.join(OUT, "broly_phys.smd"), ref_names, ref_parents, new_world, phys_tris)

json.dump({"unweighted_fixed": len(unweighted), "scale": SCALE, "height": TARGET_HEIGHT, "k_scale": k_scale, "textures": tex_report,
           "materials_used": sorted(set(slot_mat)), "phys_bones": [ref_names[b] for b in pts if len(pts[b]) >= 8],
           "pelvis": jpos[VB + "Pelvis"], "head": jpos[VB + "Head1"]},
          open(os.path.join(OUT, "build_report.json"), "w"), indent=1)
print("BUILD OK", len(tris), "tris")
