"""Extract files from a Source VPK directory.
Usage: python vpk_extract.py <path/to/xxx_dir.vpk> <out_dir> <file_in_vpk> [more files...]
"""
import os, struct, sys


def read_cstr(f):
    out = bytearray()
    while True:
        c = f.read(1)
        if c in (b"\x00", b""):
            return out.decode("utf-8", "replace")
        out += c


def read_tree(dir_path):
    entries = {}
    with open(dir_path, "rb") as f:
        sig, ver, tree_size = struct.unpack("<III", f.read(12))
        assert sig == 0x55AA1234, "not a vpk"
        if ver == 2:
            f.read(16)
        header_len = f.tell()
        while True:
            ext = read_cstr(f)
            if not ext:
                break
            while True:
                path = read_cstr(f)
                if not path:
                    break
                while True:
                    name = read_cstr(f)
                    if not name:
                        break
                    crc, preload, arc, off, length, term = struct.unpack("<IHHIIH", f.read(18))
                    pre = f.read(preload)
                    full = (path + "/" if path.strip() else "") + name + "." + ext
                    entries[full.lower()] = (arc, off, length, pre)
        data_start = header_len + tree_size
    return entries, data_start


def extract(dir_path, out_dir, wanted):
    entries, data_start = read_tree(dir_path)
    base = dir_path[: -len("_dir.vpk")]
    for w in wanted:
        e = entries.get(w.lower().replace("\\", "/"))
        if not e:
            print("MISSING", w)
            continue
        arc, off, length, pre = e
        data = pre
        if length:
            src = dir_path if arc == 0x7FFF else "%s_%03d.vpk" % (base, arc)
            with open(src, "rb") as f:
                f.seek(off + (data_start if arc == 0x7FFF else 0))
                data += f.read(length)
        dst = os.path.join(out_dir, w)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(data)
        print("OK", w, len(data))


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2], sys.argv[3:])
