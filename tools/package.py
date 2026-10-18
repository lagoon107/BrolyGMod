"""Release packager: zips the addon into dist/broly_<version>.zip with dev-only files stripped.

Usage: python tools/package.py [version]      (version defaults to the short git hash)
The zip holds a single broly/ folder -- extract it into garrysmod/addons/. Needs DrGBase.
"""
import fnmatch, json, os, subprocess, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DIST = os.path.join(ROOT, "dist")
ADDON_NAME = "broly"

# Only these top-level entries ship.
INCLUDE = ["addon.json", "lua", "models", "materials", "sound"]

# Dev-only paths (fnmatch against forward-slash paths relative to ROOT).
EXCLUDE = [
    "lua/autorun/server/broly_dev.lua",  # test concommands + file->RunString agent bridge
    "lua/broly_diag/*",                  # client FX diagnostics
    "models/source/*",                   # source FBX zip
    "models/textures/*",                 # source PNGs (compiled VTFs live in materials/)
]

# Extensions GMod's addon whitelist accepts in these folders; anything else is a stray file.
ALLOWED_EXT = {
    ".lua", ".json",
    ".mdl", ".vtx", ".vvd", ".phy", ".ani",
    ".vmt", ".vtf", ".png", ".jpg",
    ".wav", ".mp3", ".ogg",
}


def version():
    if len(sys.argv) > 1:
        return sys.argv[1]
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "dev"


def collect():
    files, skipped = [], []
    for entry in INCLUDE:
        path = os.path.join(ROOT, entry)
        if os.path.isfile(path):
            files.append(entry)
            continue
        for dirpath, dirnames, filenames in os.walk(path):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for name in filenames:
                rel = os.path.relpath(os.path.join(dirpath, name), ROOT).replace(os.sep, "/")
                if any(fnmatch.fnmatch(rel, pat) for pat in EXCLUDE):
                    skipped.append(rel)
                elif os.path.splitext(name)[1].lower() not in ALLOWED_EXT:
                    skipped.append(rel + "  (extension not whitelisted)")
                else:
                    files.append(rel)
    return sorted(files), skipped


def release_addon_json():
    # Drop the ignore list (meaningless once the files are already stripped).
    with open(os.path.join(ROOT, "addon.json"), encoding="utf-8") as f:
        meta = json.load(f)
    meta.pop("ignore", None)
    return json.dumps(meta, indent="\t") + "\n"


def main():
    files, skipped = collect()
    missing = [p for p in ("addon.json", "lua/entities/npc_broly.lua", "models/broly/broly.mdl") if p not in files]
    if missing:
        sys.exit("[package] missing required files: " + ", ".join(missing))

    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, f"{ADDON_NAME}_{version()}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in files:
            arc = f"{ADDON_NAME}/{rel}"
            if rel == "addon.json":
                zf.writestr(arc, release_addon_json())
            else:
                zf.write(os.path.join(ROOT, rel), arc)

    for rel in skipped:
        print("  skip", rel)
    print(f"[package] {len(files)} files -> {out} ({os.path.getsize(out) / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
