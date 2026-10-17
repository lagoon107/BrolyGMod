"""Tiny math + SMD helpers shared by the build scripts (pure Python, works inside and outside Blender)."""
import math


# ---- quaternions (x, y, z, w) and 3x4 matrices as nested lists ----
def quat_to_mat(q):
    x, y, z, w = q
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def mat_t(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def vadd(a, b):
    return [a[i] + b[i] for i in range(3)]


def vsub(a, b):
    return [a[i] - b[i] for i in range(3)]


def xform_mul(a, b):
    """(R, t) composition: a * b."""
    return (mat_mul(a[0], b[0]), vadd(mat_vec(a[0], b[1]), a[1]))


def xform_inv(a):
    rt = mat_t(a[0])
    return (rt, [-v for v in mat_vec(rt, a[1])])


def rot_z(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def mat_to_euler(m):
    """Inverse of SMD's rotation convention: R = Rz(z) * Ry(y) * Rx(x)."""
    sy = -m[2][0]
    sy = max(-1.0, min(1.0, sy))
    y = math.asin(sy)
    if abs(math.cos(y)) > 1e-6:
        x = math.atan2(m[2][1], m[2][2])
        z = math.atan2(m[1][0], m[0][0])
    else:
        x = math.atan2(-m[1][2], m[1][1])
        z = 0.0
    return [x, y, z]


def world_xforms(bones):
    """bones: list of {name, parent, pos, quat}; returns list of world (R, t)."""
    out = []
    for b in bones:
        local = (quat_to_mat(b["quat"]), list(b["pos"]))
        out.append(xform_mul(out[b["parent"]], local) if b["parent"] >= 0 else local)
    return out


def write_skeleton_smd(path, names, parents, world, triangles=None):
    """world: list of (R, t) in SMD space. triangles: list of (mat, [(bone, pos, nrm, uv, [(bone, w)...])*3])."""
    lines = ["version 1", "nodes"]
    for i, n in enumerate(names):
        lines.append('%d "%s" %d' % (i, n, parents[i]))
    lines += ["end", "skeleton", "time 0"]
    for i in range(len(names)):
        local = world[i] if parents[i] < 0 else xform_mul(xform_inv(world[parents[i]]), world[i])
        e = mat_to_euler(local[0])
        lines.append("%d %.6f %.6f %.6f %.6f %.6f %.6f" % (i, *local[1], *e))
    lines.append("end")
    if triangles is not None:
        lines.append("triangles")
        for mat, verts in triangles:
            lines.append(mat)
            for (b, p, n, uv, links) in verts:
                s = "%d %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f" % (b, *p, *n, *uv)
                s += " %d" % len(links) + "".join(" %d %.6f" % lw for lw in links)
                lines.append(s)
        lines.append("end")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
