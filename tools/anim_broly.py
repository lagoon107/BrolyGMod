"""Procedural keyframed animations for Broly, written as ValveBiped SMDs.

Poses are authored on the m_anm.mdl reference skeleton (same rotations as Broly's, reference
proportions); the model's autoplayed proportions delta then fits them to Broly like every other
ValveBiped animation.

Character space (SMD): forward = -Y, up = +Z, character's left = +X, right = -X.
Pose spec per bone:
  aim  = world-space direction the bone should point at its child
  rot  = (axis, degrees) world-space rotation about the bone's own origin
  curl = degrees about the bone's local Z (finger bend)

Usage: python anim_broly.py <m_anm_bones.json> <out_dir>
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from smdlib import quat_to_mat, mat_mul, mat_vec, xform_mul, xform_inv, mat_to_euler

VB = "ValveBiped.Bip01_"
FPS = 30
AIM_CHILD = {}
for s in "LR":
    AIM_CHILD[f"{s}_Clavicle"] = f"{s}_UpperArm"
    AIM_CHILD[f"{s}_UpperArm"] = f"{s}_Forearm"
    AIM_CHILD[f"{s}_Forearm"] = f"{s}_Hand"


# ------------------------------------------------------------------ math
def norm(v):
    l = math.sqrt(sum(c * c for c in v)) or 1.0
    return [c / l for c in v]


def axis_angle(axis, deg):
    x, y, z = norm(axis)
    a = math.radians(deg)
    c, s, t = math.cos(a), math.sin(a), 1 - math.cos(a)
    return [[t * x * x + c, t * x * y - s * z, t * x * z + s * y],
            [t * x * y + s * z, t * y * y + c, t * y * z - s * x],
            [t * x * z - s * y, t * y * z + s * x, t * z * z + c]]


def min_rot(v, d):
    v, d = norm(v), norm(d)
    cross = [v[1] * d[2] - v[2] * d[1], v[2] * d[0] - v[0] * d[2], v[0] * d[1] - v[1] * d[0]]
    dot = max(-1.0, min(1.0, sum(a * b for a, b in zip(v, d))))
    if math.sqrt(sum(c * c for c in cross)) < 1e-8:
        return [[1, 0, 0], [0, 1, 0], [0, 0, 1]] if dot > 0 else axis_angle([0, 0, 1], 180)
    return axis_angle(cross, math.degrees(math.acos(dot)))


def smooth(t):
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ skeleton
class Skeleton:
    def __init__(self, bones):
        self.names = [b["name"] for b in bones]
        self.parents = [b["parent"] for b in bones]
        self.local = [(quat_to_mat(b["quat"]), list(b["pos"])) for b in bones]
        self.index = {n: i for i, n in enumerate(self.names)}

    def short(self, i):
        return self.names[i].replace(VB, "")

    def pose(self, spec):
        world = []
        for i in range(len(self.names)):
            R, t = self.local[i]
            s = spec.get(self.short(i), {})
            if "curl" in s:
                R = mat_mul(R, axis_angle([0, 0, 1], s["curl"]))
            p = self.parents[i]
            W = xform_mul(world[p], (R, t)) if p >= 0 else (R, t)
            if "rot" in s:
                W = (mat_mul(axis_angle(*s["rot"]), W[0]), W[1])
            if "aim" in s:
                child = self.index[VB + AIM_CHILD[self.short(i)]]
                v = mat_vec(W[0], self.local[child][1])
                W = (mat_mul(min_rot(v, s["aim"]), W[0]), W[1])
            world.append(W)
        return world

    def write(self, path, frames):
        lines = ["version 1", "nodes"]
        lines += ['%d "%s" %d' % (i, n, self.parents[i]) for i, n in enumerate(self.names)]
        lines += ["end", "skeleton"]
        for f, world in enumerate(frames):
            lines.append("time %d" % f)
            for i in range(len(self.names)):
                p = self.parents[i]
                local = world[i] if p < 0 else xform_mul(xform_inv(world[p]), world[i])
                # keep reference bone lengths; only rotations are animated
                lines.append("%d %.6f %.6f %.6f %.6f %.6f %.6f" % (i, *self.local[i][1], *mat_to_euler(local[0])))
        lines.append("end")
        with open(path, "w", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")


# ------------------------------------------------------------------ keyframe interpolation
def lerp_spec(a, b, t):
    out = {}
    for bone in set(a) | set(b):
        sa, sb = a.get(bone, {}), b.get(bone, {})
        o = {}
        if "aim" in sa or "aim" in sb:
            va, vb = sa.get("aim", sb.get("aim")), sb.get("aim", sa.get("aim"))
            o["aim"] = norm([va[k] + (vb[k] - va[k]) * t for k in range(3)])
        if "rot" in sa or "rot" in sb:
            ra = sa["rot"] if "rot" in sa else (sb["rot"][0], 0)
            rb = sb["rot"] if "rot" in sb else (sa["rot"][0], 0)
            o["rot"] = (ra[0], ra[1] + (rb[1] - ra[1]) * t)  # axis taken from a; keys keep axes consistent
        if "curl" in sa or "curl" in sb:
            ca, cb = sa.get("curl", 0), sb.get("curl", 0)
            o["curl"] = ca + (cb - ca) * t
        out[bone] = o
    return out


def merge(*specs):
    out = {}
    for s in specs:
        for bone, v in s.items():
            out.setdefault(bone, {}).update(v)
    return out


def render(skel, keys, length, extra=None):
    """keys: [(time, spec)] sorted. extra(t) -> spec added on top (procedural shake etc)."""
    frames = []
    for f in range(int(round(length * FPS)) + 1):
        t = f / FPS
        k = 0
        while k < len(keys) - 2 and t > keys[k + 1][0]:
            k += 1
        (t0, s0), (t1, s1) = keys[k], keys[k + 1]
        u = smooth(max(0.0, min(1.0, (t - t0) / max(t1 - t0, 1e-6))))
        spec = lerp_spec(s0, s1, u)
        if extra:
            for bone, v in extra(t).items():
                if "rot" in v and "rot" in spec.get(bone, {}):
                    ax, deg = spec[bone]["rot"]
                    spec[bone]["rot"] = (ax, deg + v["rot"][1])
                else:
                    spec.setdefault(bone, {}).update(v)
        frames.append(skel.pose(spec))
    return frames


# ------------------------------------------------------------------ poses
X, Z = [1, 0, 0], [0, 0, 1]   # lean axis (character left), twist axis (up)
FINGERS = [f"{s}_Finger{a}{b}" for s in "LR" for a in "1234" for b in ("", "1", "2")]
THUMBS = [f"{s}_Finger0{b}" for s in "LR" for b in ("", "1", "2")]


def fingers(side, curl, thumb=None):
    out = {f: {"curl": curl} for f in FINGERS if f.startswith(side)}
    out.update({f: {"curl": curl * 0.4 if thumb is None else thumb} for f in THUMBS if f.startswith(side)})
    return out


GUARD = merge(
    {"R_UpperArm": {"aim": [-0.30, -0.35, -0.88]}, "R_Forearm": {"aim": [0.10, -0.75, 0.65]},
     "L_UpperArm": {"aim": [0.30, -0.35, -0.88]}, "L_Forearm": {"aim": [-0.10, -0.75, 0.65]},
     "Spine": {"rot": (Z, 0)}, "Spine2": {"rot": (X, 0)}},
    fingers("R", -70), fingers("L", -70))

REACH = merge(GUARD,
    {"R_UpperArm": {"aim": [-0.12, -0.97, 0.20]}, "R_Forearm": {"aim": [-0.02, -0.98, 0.18]},
     "Spine": {"rot": (Z, 15)}, "Spine2": {"rot": (X, 12)}},
    fingers("R", -5, 0))

CLENCH = merge(REACH, fingers("R", -55, -25))

OVERHEAD = merge(CLENCH,
    {"R_UpperArm": {"aim": [-0.12, -0.30, 0.95]}, "R_Forearm": {"aim": [-0.05, -0.12, 0.99]},
     "Spine": {"rot": (Z, 5)}, "Spine2": {"rot": (X, -8)}})

RELEASE = merge(OVERHEAD, fingers("R", -5, 0))

WINDUP = merge(RELEASE,
    {"R_UpperArm": {"aim": [-0.60, 0.70, 0.20]}, "R_Forearm": {"aim": [0.10, -0.30, 0.95]},
     "L_UpperArm": {"aim": [0.20, -0.90, 0.00]}, "L_Forearm": {"aim": [0.10, -0.95, 0.10]},
     "Spine": {"rot": (Z, -35)}, "Spine2": {"rot": (X, -5)}},
    fingers("R", -85))

STRIKE = merge(WINDUP,
    {"R_UpperArm": {"aim": [-0.05, -0.97, 0.22]}, "R_Forearm": {"aim": [0.00, -0.98, 0.20]},
     "L_UpperArm": {"aim": [0.35, 0.35, -0.85]}, "L_Forearm": {"aim": [0.10, -0.50, 0.85]},
     "Spine": {"rot": (Z, 30)}, "Spine2": {"rot": (X, 15)}})

FOLLOW = merge(STRIKE,
    {"R_UpperArm": {"aim": [0.35, -0.90, 0.15]}, "R_Forearm": {"aim": [0.60, -0.78, 0.10]},
     "Spine": {"rot": (Z, 45)}})


# Eraser Cannon: right arm drawn back low with the ball cupped in the palm, left hand aiming
CHARGE = merge(GUARD,
    {"R_UpperArm": {"aim": [-0.35, 0.55, -0.75]}, "R_Forearm": {"aim": [-0.15, -0.85, 0.10]},
     "L_UpperArm": {"aim": [0.25, -0.85, -0.20]}, "L_Forearm": {"aim": [0.05, -0.95, 0.20]},
     "Spine": {"rot": (Z, -25)}, "Spine2": {"rot": (X, -5)}},
    fingers("R", -20, -10), fingers("L", -10, 0))

THROW = merge(CHARGE,
    {"R_UpperArm": {"aim": [-0.05, -0.97, 0.20]}, "R_Forearm": {"aim": [0.00, -0.99, 0.10]},
     "L_UpperArm": {"aim": [0.35, 0.30, -0.85]}, "L_Forearm": {"aim": [0.10, -0.50, 0.85]},
     "Spine": {"rot": (Z, 25)}, "Spine2": {"rot": (X, 10)}},
    fingers("R", -5, 0))

THROW_FOLLOW = merge(THROW,
    {"R_UpperArm": {"aim": [0.25, -0.95, 0.10]}, "R_Forearm": {"aim": [0.35, -0.93, 0.05]},
     "Spine": {"rot": (Z, 35)}})


# Mouth blast: arch back gathering power, then thrust the head forward and unleash the wave
ROAR_PREP = merge(GUARD,
    {"R_UpperArm": {"aim": [-0.55, 0.35, -0.75]}, "R_Forearm": {"aim": [-0.40, -0.30, -0.85]},
     "L_UpperArm": {"aim": [0.55, 0.35, -0.75]}, "L_Forearm": {"aim": [0.40, -0.30, -0.85]},
     "Spine2": {"rot": (X, -14)}, "Head1": {"rot": (X, -18)}},
    fingers("R", -85), fingers("L", -85))

ROAR_FIRE = merge(ROAR_PREP,
    {"R_UpperArm": {"aim": [-0.75, 0.40, -0.50]}, "R_Forearm": {"aim": [-0.60, -0.10, -0.80]},
     "L_UpperArm": {"aim": [0.75, 0.40, -0.50]}, "L_Forearm": {"aim": [0.60, -0.10, -0.80]},
     "Spine2": {"rot": (X, 15)}, "Head1": {"rot": (X, 8)}})

# Nova: hunched double flex, roaring, then arms thrown wide as the dome detonates
FLEX = merge(GUARD,
    {"R_UpperArm": {"aim": [-0.85, 0.10, -0.50]}, "R_Forearm": {"aim": [0.30, -0.40, 0.85]},
     "L_UpperArm": {"aim": [0.85, 0.10, -0.50]}, "L_Forearm": {"aim": [-0.30, -0.40, 0.85]},
     "Spine2": {"rot": (X, 12)}, "Head1": {"rot": (X, -12)}},
    fingers("R", -90), fingers("L", -90))

BURST = merge(FLEX,
    {"R_UpperArm": {"aim": [-0.90, 0.10, 0.40]}, "R_Forearm": {"aim": [-0.95, 0.00, 0.30]},
     "L_UpperArm": {"aim": [0.90, 0.10, 0.40]}, "L_Forearm": {"aim": [0.95, 0.00, 0.30]},
     "Spine2": {"rot": (X, -12)}, "Head1": {"rot": (X, -22)}},
    fingers("R", -10, 0), fingers("L", -10, 0))

# Hammer: both fists raised overhead, then a double axe-handle smash straight down
RAISE = merge(GUARD,
    {"R_UpperArm": {"aim": [-0.15, -0.20, 0.97]}, "R_Forearm": {"aim": [0.15, 0.25, 0.95]},
     "L_UpperArm": {"aim": [0.15, -0.20, 0.97]}, "L_Forearm": {"aim": [-0.15, 0.25, 0.95]},
     "Spine2": {"rot": (X, -12)}, "Head1": {"rot": (X, 0)}},
    fingers("R", -90), fingers("L", -90))

SMASH = merge(RAISE,
    {"R_UpperArm": {"aim": [-0.10, -0.85, -0.50]}, "R_Forearm": {"aim": [0.15, -0.60, -0.78]},
     "L_UpperArm": {"aim": [0.10, -0.85, -0.50]}, "L_Forearm": {"aim": [-0.15, -0.60, -0.78]},
     "Spine2": {"rot": (X, 32)}, "Head1": {"rot": (X, 10)}})


GRAB_HIT = 0.40       # seconds into broly_grab when the hand closes
STRIKE_HIT = 0.34     # seconds into broly_strike when the fist connects
ERASER_RELEASE = 1.17 # seconds into broly_eraser when the ball leaves the hand
BEAM_START, BEAM_END = 0.70, 2.30   # broly_mouthblast firing window
NOVA_BURST = 1.85     # broly_nova: arms thrown wide as the dome explodes
HAMMER_HIT = 0.42     # broly_hammer: fists come down


def main():
    ref_json, out = sys.argv[1], sys.argv[2]
    skel = Skeleton(json.load(open(ref_json)))

    def rage_shake(t):  # trembling with rage while holding the victim up
        if t < 0.95:
            return {}
        a = min(1.0, (t - 0.95) / 0.15)
        return {"Spine2": {"rot": (X, a * 2.5 * math.sin(t * 55))},
                "Spine": {"rot": (Z, a * 3.0 * math.sin(t * 41 + 1.3))}}

    grab = render(skel, [(0.0, GUARD), (0.22, REACH), (GRAB_HIT, CLENCH), (0.95, OVERHEAD), (1.6, OVERHEAD)], 1.6, rage_shake)
    skel.write(os.path.join(out, "broly_grab.smd"), grab)

    strike = render(skel, [(0.0, OVERHEAD), (0.06, RELEASE), (0.24, WINDUP), (STRIKE_HIT, STRIKE),
                           (0.55, FOLLOW), (1.0, GUARD)], 1.0)
    skel.write(os.path.join(out, "broly_strike.smd"), strike)

    def charge_shake(t):  # straining as the ball grows
        if not 0.25 < t < 1.1:
            return {}
        a = min(1.0, (t - 0.25) / 0.3)
        return {"Spine2": {"rot": (X, a * 2.0 * math.sin(t * 60))},
                "Spine": {"rot": (Z, a * 2.5 * math.sin(t * 47 + 0.7))}}

    eraser = render(skel, [(0.0, GUARD), (0.25, CHARGE), (1.1, CHARGE), (ERASER_RELEASE + 0.03, THROW),
                           (1.4, THROW_FOLLOW), (1.8, GUARD)], 1.8, charge_shake)
    skel.write(os.path.join(out, "broly_eraser.smd"), eraser)

    def tremble(t0, t1, amp):
        def f(t):
            if not t0 < t < t1:
                return {}
            a = min(1.0, (t - t0) / 0.2) * amp
            return {"Spine2": {"rot": (X, a * math.sin(t * 63))}, "Head1": {"rot": (X, a * 1.5 * math.sin(t * 77 + 2))}}
        return f

    mouth = render(skel, [(0.0, GUARD), (0.45, ROAR_PREP), (BEAM_START - 0.1, ROAR_PREP), (BEAM_START + 0.08, ROAR_FIRE),
                          (BEAM_END, ROAR_FIRE), (2.8, GUARD)], 2.8, tremble(0.2, BEAM_END, 3.0))
    skel.write(os.path.join(out, "broly_mouthblast.smd"), mouth)

    nova = render(skel, [(0.0, GUARD), (0.35, FLEX), (NOVA_BURST - 0.08, FLEX), (NOVA_BURST + 0.08, BURST),
                         (2.3, BURST), (2.8, GUARD)], 2.8, tremble(0.3, NOVA_BURST, 4.0))
    skel.write(os.path.join(out, "broly_nova.smd"), nova)

    hammer = render(skel, [(0.0, GUARD), (0.15, RAISE), (HAMMER_HIT - 0.12, RAISE), (HAMMER_HIT, SMASH),
                           (0.75, SMASH), (1.1, GUARD)], 1.1)
    skel.write(os.path.join(out, "broly_hammer.smd"), hammer)
    print("ANIMS OK", len(grab), len(strike), len(eraser), len(mouth), len(nova), len(hammer))


if __name__ == "__main__":
    main()
