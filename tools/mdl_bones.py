"""Dump the bone table (name, parent, default local pos/quat) of a compiled Source .mdl as JSON.
Usage: python mdl_bones.py <model.mdl> [out.json]
"""
import json, struct, sys

BONE_SIZE = 216


def read_bones(path):
    with open(path, "rb") as f:
        d = f.read()
    assert d[:4] == b"IDST", "not an mdl"
    numbones, boneindex = struct.unpack_from("<ii", d, 156)
    bones = []
    for i in range(numbones):
        o = boneindex + i * BONE_SIZE
        nameoff, parent = struct.unpack_from("<ii", d, o)
        pos = struct.unpack_from("<3f", d, o + 32)
        quat = struct.unpack_from("<4f", d, o + 44)  # x y z w
        end = d.index(b"\x00", o + nameoff)
        name = d[o + nameoff:end].decode()
        bones.append({"name": name, "parent": parent, "pos": pos, "quat": quat})
    return bones


if __name__ == "__main__":
    bones = read_bones(sys.argv[1])
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as f:
            json.dump(bones, f, indent=1)
    for i, b in enumerate(bones):
        print(i, b["name"], b["parent"], [round(v, 3) for v in b["pos"]], [round(v, 4) for v in b["quat"]])
