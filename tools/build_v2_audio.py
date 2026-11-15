#!/usr/bin/env python3
"""V2 sounds: cut, level and name the CC0 recordings in assets_src/audio_v2/ -> assets/audio/v2/<key>_NN.ogg.

    python3 -I tools/build_v2_audio.py          # all keys (then: godot --headless --import)

Sources (all CC0, opengameart.org; one row each in licenses.csv; `tools/fetch_v2_audio.sh` downloads them):
  firearms/   The Free Firearm Sound Library (Still North Media): real guns, 24 bit / 96 kHz, several shots per file
  oga/        foley by rubberduck, Thimras, Fantozzi, BMacZero, zer0_sol, SpringySpringo, LFA, AntumDeluge, artisticdude,
              qubodup
What is done to a recording: a region or its loud events are cut out, faded at the ends, sometimes re-pitched
(resampled) or layered with another, brought to one peak level, written as Ogg Vorbis 44.1 kHz. The player's own
shots stay stereo; everything heard at a place in the room is mono. The mix between keys is `V2Sfx.SOUNDS`.
The choice of recordings for everything but the guns was made from their names, lengths and spectra, not by
ear (this machine has no sound): swap a recipe's source here if a sound is wrong.
"""
import os
import subprocess
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "assets_src", "audio_v2")
OUT = os.path.join(ROOT, "assets", "audio", "v2")
FF = os.path.join(SRC, "firearms", "Prepared SFX Library")
OG = os.path.join(SRC, "oga")
SR = 44100


def load(path, stereo=False):
    ch = 2 if stereo else 1
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
    assert len(a), "empty: " + path
    return a.reshape(-1, ch)


def mono(a):
    return a.mean(axis=1, keepdims=True)


def env(a, win=0.005):
    n = int(win * SR)
    return np.sqrt(np.convolve((a * a).mean(axis=1), np.ones(n) / n, "same"))


def onsets(a, quiet=0.3, thr_db=-18.0):
    """Starts of the loud events: where the envelope rises over thr (re the file's peak) after `quiet` s under it."""
    e = env(a)
    hot = np.flatnonzero(e > e.max() * 10 ** (thr_db / 20))
    out, last = [], -10 ** 9
    for i in hot:
        if i - last > quiet * SR:
            out.append(int(i))
        last = i
    return out


def fade(a, t_in=0.002, t_out=0.05):
    a = a.copy()
    n = min(int(t_in * SR), len(a) // 2)
    if n:
        a[:n] *= np.linspace(0, 1, n)[:, None]
    n = min(int(t_out * SR), len(a) // 2)
    if n:
        a[-n:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n)))[:, None]
    return a


def level(a, peak_db=-1.0):
    return a * (10 ** (peak_db / 20) / (np.abs(a).max() + 1e-12))


def cut(a, t0, t1, t_in=0.002, t_out=0.05):
    return fade(a[int(t0 * SR):int(t1 * SR)], t_in, t_out)


def shots(path, tail, stereo=False, pre=0.006, t_out=None, most=5):
    """Every shot of a firearm recording: from just before its crack for `tail` seconds, fading out."""
    a = load(path, stereo)
    out = []
    for o in onsets(a)[:most]:
        s = a[max(o - int(pre * SR), 0):o + int(tail * SR)]
        out.append(level(fade(s, 0.001, t_out if t_out else tail * 0.45)))
    return out


def pitch(a, ratio):
    """Resampled: `ratio` > 1 is higher and shorter."""
    n = int(len(a) / ratio)
    x = np.linspace(0, len(a) - 1, n)
    return np.stack([np.interp(x, np.arange(len(a)), a[:, c]) for c in range(a.shape[1])], axis=1)


def glide(a, r0, r1, dur):
    """Resampled at a rate that slides from r0 to r1 over `dur` seconds of output (a pitch that falls or rises)."""
    n = int(dur * SR)
    pos = np.cumsum(np.linspace(r0, r1, n)) % (len(a) - 1)
    return np.stack([np.interp(pos, np.arange(len(a)), a[:, c]) for c in range(a.shape[1])], axis=1)


def layer(*parts):
    """Mix [(sound, gain, delay seconds), ...]."""
    n = max(len(a) + int(d * SR) for a, g, d in parts)
    out = np.zeros((n, parts[0][0].shape[1]))
    for a, g, d in parts:
        i = int(d * SR)
        out[i:i + len(a)] += a * g
    return out


def loop(a, xfade=0.25):
    """Seamless: the end is faded out over the start faded in."""
    n = int(xfade * SR)
    body = a[n:].copy()
    k = np.linspace(0, 1, n)[:, None]
    body[-n:] = body[-n:] * (1 - k) + a[:n] * k
    return body


def whole(path, stereo=False, t_out=0.03):
    return fade(load(path, stereo), 0.001, t_out)


def events(path, quiet=0.12, thr_db=-22.0):
    a = load(path)
    on = onsets(a, quiet, thr_db) + [len(a)]
    return [fade(a[max(on[i] - 200, 0):on[i + 1]], 0.002, 0.03) for i in range(len(on) - 1)]


def o(name):
    return os.path.join(OG, name)


def recipes():
    r = {}
    # ---- the guns (The Free Firearm Sound Library)
    r["pistol_shot"] = shots(os.path.join(FF, "Walther PPQ", "X_39P.wav"), 1.1, stereo=True)             # 9 mm, near
    ar = os.path.join(FF, "AR-15", "D_32P.wav")                                                         # 5.56, near
    r["rifle_shot"] = shots(ar, 0.42, stereo=True, t_out=0.3)             # short: twelve of them a second
    a = load(ar, True)
    on = onsets(a)[-1]
    r["rifle_tail"] = [level(fade(a[on + int(0.11 * SR):on + int(1.7 * SR)], 0.05, 0.9), -9.0)]      # the last round dying away
    r["spider_shot"] = shots(os.path.join(FF, "Tikka", "W_24P.wav"), 1.2)                              # .30-06, a few metres off
    r["drone_shot"] = shots(os.path.join(FF, "Carl Gustav M45", "G_20P.wav"), 0.7)                     # 9 mm sub-machine gun
    r["turret_shot"] = shots(os.path.join(FF, "AK-47", "C_31P.wav"), 1.0)                              # 7.62x39
    # ---- handling the guns
    rl = load(o("reload.wav"))                                             # a real handgun: magazine out, in, slide racked
    r["pistol_mag_out"] = [level(cut(rl, 0.06, 0.40), -8.0)]
    r["pistol_mag_in"] = [level(cut(rl, 0.54, 0.90), -3.0)]
    r["slide"] = [level(cut(rl, 0.98, 1.50), -2.0)]
    ar_rl = load(o("assaultriflereload1_0.wav"))                           # airsoft rifle: magazine out ... in, charging handle
    r["rifle_mag_out"] = [level(cut(ar_rl, 0.08, 0.46), -6.0), level(whole(o("clipload2.wav")), -6.0)]
    r["rifle_mag_in"] = [level(cut(ar_rl, 1.00, 1.19, 0.002, 0.02), -3.0), level(whole(o("clipload1.wav")), -3.0)]
    r["bolt"] = [level(cut(ar_rl, 1.17, 1.56), -2.0)]
    ev = events(o("equipmentclicks.wav"))
    r["handling"] = [level(e[:int(0.5 * SR)] if len(e) > 0.5 * SR else e, -6.0) for e in (fade(x, 0.002, 0.08) for x in ev[:6])] \
        + [level(whole(o("rattle1.wav")), -6.0)]
    r["casing"] = [level(whole(o(n)), -3.0) for n in ("clink1_0.wav", "clink2.wav", "clink3.wav")]
    # ---- rounds landing
    bf = "sfx_breaking_and_falling/bfh1_"
    r["impact_concrete"] = [level(whole(o(n))) for n in (bf + "rock_hit_01.ogg", "sfx_100_v2/sfx100v2_stones_01.ogg",
                                                         "sfx_100_v2/sfx100v2_stones_02.ogg", "sfx_100_v2/sfx100v2_stones_03.ogg",
                                                         bf + "hit_05.ogg", bf + "hit_09.ogg")]
    r["impact_metal"] = [level(whole(o(n))) for n in (bf + "metal_hit_01.ogg", bf + "metal_hit_03.ogg", bf + "metal_hit_06.ogg",
                                                      "sfx_100_v2/sfx100v2_metal_hit_02.ogg")]
    r["robot_hit"] = [level(pitch(whole(o(n)), 0.8)) for n in (bf + "metal_hit_02.ogg", bf + "metal_hit_04.ogg", bf + "metal_hit_05.ogg")] \
        + [level(whole(o("sfx_100_v2/sfx100v2_metal_hit_01.ogg")))]
    r["flyby"] = [level(whole(o("swishes/swishes/swish-%d.wav" % i)), -4.0) for i in (1, 10, 11, 12, 13)]
    # ---- the player's body
    st = "Fantozzi-footsteps/Fantozzi-footsteps/flac/Fantozzi-Stone%s.flac"
    r["step"] = [level(whole(o(st % n)), -3.0) for n in ("L1", "L2", "L3", "R1", "R2", "R3")]
    r["jump"] = [level(pitch(whole(o(st % "L2")), 1.15), -3.0)]
    thud = whole(o(bf + "hit_02.ogg"))                                      # a low, dull blow
    r["land"] = [level(layer((pitch(whole(o(st % "R1")), 0.8), 1.0, 0.0), (thud, 0.9, 0.0)), -2.0)]
    r["crouch"] = [level(whole(o("rattle1.wav")), -6.0), level(whole(o("lightclunk2.wav")), -6.0)]
    r["hurt"] = [level(whole(o(bf + "hit_07.ogg"))), level(whole(o("sfx_100_v2/sfx100v2_hit_01.ogg")))]
    r["down"] = [level(pitch(thud, 0.7))]
    # ---- the robots
    r["spider_step"] = [level(whole(o("metal_steps_48k24b/metal_steps_%02d.wav" % i)), -3.0) for i in range(1, 11)]
    sq = whole(o("roboticsqueeze.flac"))                                    # a motor whine, far too high as recorded
    r["servo"] = [level(pitch(sq, 0.5), -3.0), level(pitch(sq, 0.62), -3.0)]
    r["drone_rotor"] = [level(loop(pitch(load(o("fan_interval.wav")), 1.5)), -3.0)]                 # loop
    mf = bf + "metal_falling_%02d.ogg"
    bang = "25-CC0-bang-sfx/"
    r["robot_break"] = [level(layer((whole(o(mf % 1)), 1.0, 0.03), (whole(o(bang + "bang_05.ogg")), 0.8, 0.0))),
                        level(layer((whole(o(mf % 2)), 1.0, 0.03), (whole(o(bang + "bang_08.ogg")), 0.8, 0.0)))]
    # a motor running down: the fan again, its pitch sliding from high to a third of it over two seconds
    # (a ready-made "machine shutting down" on OpenGameArt is cut from a freesound.org recording whose licence could
    # not be checked: not used)
    r["power_down"] = [level(fade(glide(load(o("fan_interval.wav")), 1.7, 0.3, 2.0), 0.01, 1.2), -2.0)]
    r["crash"] = [level(layer((pitch(whole(o(mf % 3)), 0.7), 1.0, 0.0), (thud, 1.0, 0.0))),
                  level(layer((pitch(whole(o(mf % 4)), 0.6), 1.0, 0.0), (thud, 1.0, 0.0)))]
    r["explosion"] = [level(layer((whole(o(bang + "bang_03.ogg"), t_out=0.3), 1.0, 0.0), (whole(o(bang + "cannon_02.ogg"), t_out=0.5), 0.8, 0.0))),
                      level(layer((whole(o(bang + "cannon_01.ogg"), t_out=0.4), 1.0, 0.0), (pitch(whole(o(bang + "bang_03.ogg")), 0.9), 0.9, 0.0)))]
    r["zap"] = [level(whole(o("spark.wav")), -3.0), level(whole(o("continuousspark.wav")), -3.0)]     # a small Tesla coil
    r["fire"] = [level(loop(load(o("fire-1.wav")), 0.4), -3.0)]                                       # loop
    return r


def write(key, i, a):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "%s_%02d.ogg" % (key, i + 1))
    a = np.clip(a, -1, 1).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(a.shape[1]), "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", path], input=a.tobytes(), check=True)
    return path


if __name__ == "__main__":
    for f in os.listdir(OUT) if os.path.isdir(OUT) else []:
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    total = 0
    for key, variants in recipes().items():
        for i, a in enumerate(variants):
            write(key, i, a)
        total += len(variants)
        print("%-16s %d  %s" % (key, len(variants), " ".join("%.2fs" % (len(a) / SR) for a in variants)))
    print("wrote", total, "files to", os.path.normpath(OUT))
    sys.exit(0)
