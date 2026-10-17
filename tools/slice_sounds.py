"""Slice the source sounds in sound_src/ into game-ready clips in sound/broly/.

Every clip: mono 44.1 kHz 16-bit WAV (GMod only spatializes mono), short fades, peak-normalized.
Usage: python tools/slice_sounds.py
"""
import os, re, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "sound_src")
OUT = os.path.join(ROOT, "sound", "broly")
FFMPEG = os.path.expandvars(r"%LOCALAPPDATA%\universal-modder\ffmpeg\bin\ffmpeg.exe")

SCREAM = "dbs_broly_scream+windup.mp3"
YELL = "dbz_broly_lssj_transformation_yell.mp3"
CHARGE = "dbz_broly_ki_charge_sound_effect_repeated.mp3"
PACK = "z_broly_omega_blaster_sound_effect_pack.mp3"

# name: (source, start, end, fade_in, fade_out, peak_db)
CLIPS = {
	# voice
	"scream_full":  (SCREAM, 0.20, 10.25, 0.02, 0.40, -1),   # spawn / intro
	"roar_windup":  (SCREAM, 0.20, 5.00, 0.02, 0.25, -1),
	"roar":         (SCREAM, 5.00, 10.25, 0.03, 0.40, -1),
	"yell":         (YELL,   0.30, 3.30, 0.02, 0.30, -1),
	"grunt1":       (YELL,   0.55, 1.15, 0.02, 0.18, -2),
	"grunt2":       (YELL,   2.55, 3.10, 0.02, 0.18, -2),
	"grunt3":       (SCREAM, 3.60, 4.20, 0.01, 0.18, -2),
	"grunt4":       (SCREAM, 6.45, 7.05, 0.02, 0.18, -2),
	# ki
	"ki_charge":    (CHARGE, 1.22, 3.66, 0.01, 0.20, -2),
	"blast1":       (PACK,   0.45, 3.29, 0.005, 0.30, -1),
	"blast2":       (PACK,   4.40, 8.79, 0.005, 0.40, -1),
	"blast3":       (PACK,   9.57, 12.14, 0.005, 0.30, -1),
	"blast4":       (PACK,  12.92, 16.51, 0.005, 0.40, -1),
	"blast5":       (PACK,  17.08, 20.18, 0.005, 0.40, -1),
	"ki_shot1":     (PACK,   0.45, 0.95, 0.003, 0.20, -3),
	"ki_shot2":     (PACK,  12.92, 13.42, 0.003, 0.20, -3),
	"ki_hit":       (PACK,   9.57, 10.27, 0.003, 0.30, -3),
}


def peak_db(path):
	r = subprocess.run([FFMPEG, "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-"],
	                   capture_output=True, text=True)
	return float(re.search(r"max_volume: (-?[\d.]+) dB", r.stderr).group(1))


def main():
	os.makedirs(OUT, exist_ok=True)
	for name, (src, start, end, fin, fout, target) in CLIPS.items():
		dst = os.path.join(OUT, name + ".wav")
		dur = end - start
		af = "afade=t=in:d=%g,afade=t=out:st=%g:d=%g" % (fin, max(0, dur - fout), fout)
		cmd = [FFMPEG, "-v", "error", "-y", "-ss", str(start), "-t", str(dur), "-i", os.path.join(SRC, src),
		       "-af", af, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", dst]
		subprocess.run(cmd, check=True)
		gain = target - peak_db(dst)
		tmp = dst + ".tmp.wav"
		subprocess.run([FFMPEG, "-v", "error", "-y", "-i", dst, "-af", "volume=%gdB" % gain,
		                "-c:a", "pcm_s16le", tmp], check=True)
		os.replace(tmp, dst)
		print("%-12s %5.2fs  gain %+5.1f dB" % (name, dur, gain))


if __name__ == "__main__":
	main()
