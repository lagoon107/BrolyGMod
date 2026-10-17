"""One-shot build: Broly.fbx -> models/broly/broly.mdl + materials/models/broly/*.vtf/vmt

Usage: python tools/build.py
Needs: Blender (path below), Garry's Mod bin tools (studiomdl, vtex).
"""
import glob, os, shutil, subprocess, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from vpk_extract import extract
from mdl_bones import read_bones

BLENDER = r"D:\SteamLibrary\steamapps\common\Blender\blender.exe"
GMOD = r"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
STUDIOMDL = os.path.join(GMOD, "bin", "studiomdl.exe")
VTEX = os.path.join(GMOD, "bin", "vtex.exe")

BUILD = os.path.join(ROOT, "build")
SRC = os.path.join(BUILD, "src")
SMD = os.path.join(BUILD, "smd")
GAME = os.path.join(BUILD, "game")

QC = r'''$modelname "broly/broly.mdl"
$cdmaterials "models/broly/"
$surfaceprop "flesh"
$eyeposition 0 0 {eye_z:.2f}

$body "body" "broly_ref.smd"

$includemodel "m_anm.mdl"

// proportions trick: keep Broly's skeleton under every ValveBiped animation
$sequence "reference" "anm_reference.smd" fps 1
$animation "a_proportions" "broly_proportions.smd" subtract "reference" 0
$sequence "proportions" "a_proportions" delta autoplay

// custom upper-body gestures (tools/anim_broly.py), played as layers over the fighting stance
{weightlist}
$sequence "broly_grab" "broly_grab.smd" fps 30 weightlist "broly_upper"
$sequence "broly_strike" "broly_strike.smd" fps 30 weightlist "broly_upper"
$sequence "broly_eraser" "broly_eraser.smd" fps 30 weightlist "broly_upper"
$sequence "broly_mouthblast" "broly_mouthblast.smd" fps 30 weightlist "broly_upper"
$sequence "broly_nova" "broly_nova.smd" fps 30 weightlist "broly_upper"
$sequence "broly_hammer" "broly_hammer.smd" fps 30 weightlist "broly_upper"

$attachment "eyes" "ValveBiped.Bip01_Head1" {eye_fwd:.2f} {eye_up:.2f} 0 rotate 0 -80 -90
$attachment "mouth" "ValveBiped.Bip01_Head1" {mouth_fwd:.2f} {mouth_up:.2f} 0 rotate 0 -80 -90
$attachment "chest" "ValveBiped.Bip01_Spine2" 5 4 0 rotate 0 95 90
$attachment "anim_attachment_RH" "ValveBiped.Anim_Attachment_RH" 0 0 0 rotate -90 -90 0
$attachment "anim_attachment_LH" "ValveBiped.Anim_Attachment_LH" 0 0 0 rotate -90 -90 0
$attachment "anim_attachment_head" "ValveBiped.Bip01_Head1" 0 0 0 rotate -90 -90 0

$collisionjoints "broly_phys.smd"
{{
	$mass 300
	$inertia 10
	$damping 0.01
	$rotdamping 1.5
	$rootbone "ValveBiped.Bip01_Pelvis"
}}
'''


def upper_weightlist(ref_json):
    """Every bone listed explicitly: legs/pelvis 0, spine ramps up, arms/head/fingers 1."""
    import json
    ramp = {"Pelvis": 0, "Spine": 0.25, "Spine1": 0.5, "Spine2": 0.85}
    lines = ['$weightlist "broly_upper" {']
    for b in json.load(open(ref_json)):
        if b["name"] == "ValveBiped.forward":  # unweighted helper bone; studiomdl drops it
            continue
        short = b["name"].replace("ValveBiped.Bip01_", "")
        if short in ramp:
            w = ramp[short]
        elif any(k in short for k in ("Thigh", "Calf", "Foot", "Toe")):
            w = 0
        else:
            w = 1
        lines.append('\t"%s" %g' % (b["name"], w))
    lines.append("}")
    return "\n".join(lines)


def run(cmd, **kw):
    print(">", " ".join('"%s"' % c if " " in c else c for c in cmd))
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    out = r.stdout + r.stderr
    if r.returncode != 0 or "ERROR" in out:
        print(out[-4000:])
        raise SystemExit("step failed: %s" % os.path.basename(cmd[0]))
    return out


def main():
    for d in (SRC, SMD, os.path.join(GAME, "models")):
        os.makedirs(d, exist_ok=True)
    with open(os.path.join(GAME, "gameinfo.txt"), "w") as f:
        f.write('"GameInfo"\n{\n game "broly_build"\n FileSystem\n {\n  SearchPaths\n  {\n   Game |gameinfo_path|.\n  }\n }\n}\n')

    # 1) unpack the source model (outer zip holds source/Broly.zip with the fbx + full-size pngs)
    with zipfile.ZipFile(os.path.join(ROOT, "models", "source", "broly.zip")) as z:
        inner = z.read("source/Broly.zip")
    inner_path = os.path.join(SRC, "Broly.zip")
    open(inner_path, "wb").write(inner)
    with zipfile.ZipFile(inner_path) as z:
        z.extractall(SRC)

    # 2) reference skeleton from the game's own m_anm.mdl
    extract(os.path.join(GMOD, "garrysmod", "garrysmod_dir.vpk"), BUILD, ["models/m_anm.mdl"])
    import json
    ref_json = os.path.join(BUILD, "m_anm_bones.json")
    json.dump(read_bones(os.path.join(BUILD, "models", "m_anm.mdl")), open(ref_json, "w"))

    # 3) blender conversion
    out = run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "build_broly.py"), "--",
               os.path.join(SRC, "Broly.fbx"), ref_json, SMD])
    if "BUILD OK" not in out:
        print(out[-4000:])
        raise SystemExit("blender step failed")
    report = json.load(open(os.path.join(SMD, "build_report.json")))
    print("blender:", {k: report[k] for k in ("scale", "materials_used", "phys_bones")})

    # 3b) custom animations
    out = run([sys.executable, "-I", os.path.join(HERE, "anim_broly.py"), ref_json, SMD])
    print(out.strip())

    # 4) QC + studiomdl
    head_z = report["head"][2]
    qc = QC.format(eye_z=head_z + 4.0 * report["k_scale"], eye_fwd=3.4 * report["k_scale"],
                   eye_up=-3.9 * report["k_scale"], mouth_fwd=0.8 * report["k_scale"],
                   mouth_up=-5.6 * report["k_scale"], weightlist=upper_weightlist(ref_json))
    qc_path = os.path.join(SMD, "broly.qc")
    open(qc_path, "w").write(qc)
    out = run([STUDIOMDL, "-nop4", "-game", GAME, qc_path])
    for line in out.splitlines():
        if "WARNING" in line:
            print("  studiomdl:", line.strip())

    dst_models = os.path.join(ROOT, "models", "broly")
    os.makedirs(dst_models, exist_ok=True)
    for f in glob.glob(os.path.join(GAME, "models", "broly", "broly.*")):
        shutil.copy2(f, dst_models)

    # 5) textures: tga -> vtf via vtex, plus the vmts
    dst_mats = os.path.join(ROOT, "materials", "models", "broly")
    os.makedirs(dst_mats, exist_ok=True)
    for tga in glob.glob(os.path.join(SMD, "*.tga")):
        base = os.path.splitext(tga)[0]
        open(base + ".txt", "w").write("")
        run([VTEX, "-nopause", "-quiet", "-game", GAME, "-outdir", dst_mats, tga])
        shutil.copy2(base + ".vmt", dst_mats)
    print("DONE ->", dst_models, dst_mats)


if __name__ == "__main__":
    main()
