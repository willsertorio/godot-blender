#!/usr/bin/env python3
"""Listen to the V2 sounds without starting the game: a short scene mixed the way the game mixes it.

    python3 -I tools/audition_v2_audio.py                       # -> captures/v2/audition.ogg
    python3 -I tools/audition_v2_audio.py --dir DIR --sfx FILE --out FILE --gain DB    # another set of files / table / bus gain

What is in it, in order (a second of silence between the parts):
  1  pistol: four shots, a casing after each, then a reload (magazine out, in, slide)
  2  machine gun: 1.5 s held (twelve rounds a second), the tail on release, a reload (magazine out, in, bolt)
  3  the spider, 8 m away: steps, a servo, three shots, two rounds landing on concrete
  4  the drone, 8 m away: its rotors, two bursts, a round passing the head
  5  the turret, 8 m away: a servo, four shots
  6  hits: three of the player's rounds on a robot, the robot breaks, runs down, a wreck's sparks, a crash
  7  the drone's explosion at 6 m, then the robot coming back
  8  the player: steps, a jump and a landing, hit twice, down
Volumes come from `SOUNDS` in scripts/v2/v2_sfx.gd; a sound "at a place" is turned down for its distance as the
game does (6 dB per doubling past 4 m); files are picked at random with the table's pitch scatter. Not in it: the
game's room reverb and stereo placement. The sum goes through a soft limiter, as the game's bus does.
"""
import os
import re
import subprocess
import sys

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SR = 44100


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


DIR = arg("--dir", os.path.join(ROOT, "assets", "audio", "v2"))
SFX = arg("--sfx", os.path.join(ROOT, "scripts", "v2", "v2_sfx.gd"))
OUT = arg("--out", os.path.join(ROOT, "captures", "v2", "audition.ogg"))
GAIN = float(arg("--gain", "3.0"))                       # the bus gain of V2Sfx (GAIN there)

table = {}
for m in re.finditer(r'^\t"(\w+)": \[\[.*?\], [\d.]+, (-?[\d.]+), ([\d.]+), ([\d.]+)\]', open(SFX).read(), re.M):
    table[m.group(1)] = (float(m.group(2)), float(m.group(3)))
files = {}
for f in sorted(os.listdir(DIR)):
    if f.endswith(".ogg"):
        files.setdefault(f.rsplit("_", 1)[0], []).append(os.path.join(DIR, f))
rng = np.random.default_rng(3)
cache = {}


def load(path):
    if path not in cache:
        ch = int(subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
                                capture_output=True, check=True).stdout.decode().strip().split(",")[0])
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", str(ch), "-ar", str(SR), "-"],
                             capture_output=True, check=True).stdout
        a = np.frombuffer(raw, dtype=np.float32).astype(np.float64).reshape(-1, ch)
        cache[path] = a if ch == 2 else np.repeat(a, 2, axis=1)
    return cache[path]


mix = np.zeros((SR * 90, 2))
missing = set()


def play(key, t, dist=0.0, db=0.0, pitch=1.0, length=None, pan=0.0):
    """`key` at time t (s); dist > 0 = at a place that far away."""
    if key not in files or key not in table:
        missing.add(key)
        return
    vol, scatter = table[key]
    a = load(files[key][rng.integers(len(files[key]))])
    r = pitch * rng.uniform(1 - scatter, 1 + scatter)
    x = np.linspace(0, len(a) - 1, int(len(a) / r))
    a = np.stack([np.interp(x, np.arange(len(a)), a[:, c]) for c in range(2)], axis=1)
    if length:                                             # (a loop: repeated to length, faded)
        n = int(length * SR)
        a = np.tile(a, (n // len(a) + 1, 1))[:n]
        k = int(0.15 * SR)
        a[:k] *= np.linspace(0, 1, k)[:, None]
        a[-k:] *= np.linspace(1, 0, k)[:, None]
    g = vol + db + GAIN
    if dist > 0:
        g += min(-20 * np.log10(dist / 4.0), 3.0)
        a = a * np.array([[1 - max(pan, 0) * 0.6, 1 + min(pan, 0) * 0.6]])
    i = int(t * SR)
    mix[i:i + len(a)] += a[:len(mix) - i] * 10 ** (g / 20)


t = 0.5
# 1 pistol
for k in range(4):
    play("pistol_shot", t)
    play("casing", t + 0.5)
    t += 0.55
t += 0.5
play("handling", t)
play("pistol_mag_out", t + 0.3)
play("pistol_mag_in", t + 1.1)
play("slide", t + 1.6)
t += 3.2
# 2 machine gun
for k in range(18):
    play("rifle_shot", t + k / 12.0)
    if k % 3 == 0:
        play("casing", t + k / 12.0 + 0.5)
play("rifle_tail", t + 18 / 12.0)
t += 3.6
play("rifle_mag_out", t)
play("rifle_mag_in", t + 0.9)
play("bolt", t + 1.5)
t += 3.2
# 3 spider
for k in range(6):
    play("spider_step", t + k * 0.25, 8.0, pan=-0.5)
play("servo", t + 1.6, 8.0, pan=-0.5)
for k in range(3):
    play("spider_shot", t + 2.4 + k * 0.7, 8.0, pan=-0.5)
    play("impact_concrete", t + 2.45 + k * 0.7, 3.0, pan=0.4)
t += 5.6
# 4 drone
play("drone_rotor", t, 8.0, length=4.0, pan=0.5)
for b in range(2):
    for k in range(5):
        play("drone_shot", t + 1.0 + b * 1.3 + k * 0.1, 8.0, pan=0.5)
play("flyby", t + 1.25)
play("flyby", t + 2.55)
t += 5.0
# 5 turret
play("servo", t, 8.0)
for k in range(4):
    play("turret_shot", t + 0.8 + k * 0.3, 8.0)
    play("impact_concrete", t + 0.85 + k * 0.3, 2.5, pan=-0.4)
t += 3.6
# 6 hits on a robot, it breaks
for k in range(3):
    play("pistol_shot", t + k * 0.5)
    play("impact_metal", t + k * 0.5 + 0.03, 7.0)
    play("robot_hit", t + k * 0.5 + 0.03, 7.0)
play("robot_break", t + 1.05, 7.0)
play("power_down", t + 1.1, 7.0)
play("zap", t + 1.6, 7.0, -2.0)
play("crash", t + 2.5, 7.0)
play("zap", t + 3.1, 7.0, -4.0)
play("zap", t + 3.3, 7.0, -5.0)
t += 5.0
# 7 explosion, the robot comes back
play("explosion", t, 6.0)
play("power_up", t + 3.0, 7.0)
t += 5.2
# 8 the player
for k in range(6):
    play("step", t + k * 0.42)
play("jump", t + 2.7)
play("land", t + 3.3)
play("hurt", t + 4.2)
play("hurt", t + 4.9)
play("down", t + 5.5)
t += 7.5

mix = mix[:int(t * SR)]
peak = np.abs(mix).max()
c = 10 ** (-0.5 / 20)                                       # the bus limiter, roughly: soft over half the ceiling
knee = c * 0.5
mag = np.abs(mix)
hot = mag > knee
mix[hot] = np.sign(mix[hot]) * (knee + (c - knee) * np.tanh((mag[hot] - knee) / (c - knee)))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(SR), "-i", "-", "-c:a", "libvorbis", "-q:a", "6", OUT],
               input=mix.astype(np.float32).tobytes(), check=True)
print("%s  %.0f s, peak before the limiter %.1f dBFS" % (os.path.normpath(OUT), t, 20 * np.log10(peak)))
if missing:
    print("  keys without files or table rows:", " ".join(sorted(missing)))
