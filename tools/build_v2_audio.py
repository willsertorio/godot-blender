#!/usr/bin/env python3
"""V2 sounds: cut, design, level and name the CC0 recordings in assets_src/audio_v2/ -> assets/audio/v2/<key>_NN.ogg.

    python3 -I tools/build_v2_audio.py            # all keys (then: godot --headless --import)
    python3 -I tools/build_v2_audio.py --report   # the numbers of what is in assets/audio/v2 (nothing is written)

Sources (all CC0, opengameart.org; one row each in licenses.csv; `tools/fetch_v2_audio.sh` downloads them):
  firearms/   The Free Firearm Sound Library (Still North Media): real guns, 24 bit / 96 kHz, several shots per file
  oga/        foley by rubberduck, Thimras, BMacZero, zer0_sol, SpringySpringo, LFA, artisticdude, qubodup
  ../audio/impact-sounds/   Kenney Impact Sounds (the player's footsteps; V1's download, kenney.nl)

Foley: a region or its loud events are cut out, faded, sometimes re-pitched (resampled) or layered.

The guns are DESIGNED from the recordings (`gun()`), because a raw gunshot recorded in a field is not what a gun
sounds like to the person firing it in a room: measured, each shot of the library is a 15-25 ms crack with a
28 dB crest factor, nearly all of it between 500 and 1500 Hz and almost nothing under 200 Hz: a dry pop. Each
game shot is built from one real shot in layers:
  crack   the recording itself
  body    the same shot an octave down (resampled): its 500-1500 Hz weight lands at 250-750 Hz
  boom    the same shot two octaves down, low-passed: 125-375 Hz, four times as long
  sub     a 50 Hz thump (a decaying sine that falls in pitch): the only synthetic part, what a muzzle blast does to
          a room and no microphone a few metres off records
  action  the gun's mechanism (slide / bolt) from a real reload recording, 35 ms after the shot
then saturated (the crack is 20 dB over everything else: soft clipping brings the body up under it, as every
recording chain and the ear itself do), given the reflections and reverberation of a hard-walled room
(`room_ir`: early reflections of an 11 x 17 x 5 m room, a tail that dies faster in the treble), and equalised.
The player's guns are stereo with a wide tail; the robots' guns are mono (heard at a place in the room), built
from the takes recorded at a distance, with more room and less sub.

Levels: every file is brought to the same LOUDNESS (K-weighted, loudest 200 ms; `loud()`), not the same peak:
the mix between keys is then simply the dB column of `V2Sfx.SOUNDS`.

Nothing here was judged by ear (this machine has no sound). The guns were designed against numbers: crest
factor, decay time, energy per band (`--report`); the foley was chosen from names, lengths and spectra. Swap a
recipe's source or change a layer's gain here if a sound is wrong.
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


def channels(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels", "-of", "csv=p=0", path],
                         capture_output=True, check=True).stdout
    return int(out.decode().strip().split(",")[0])


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


def glide(a, rates, dur):
    """Resampled at a rate that slides through `rates` (evenly spaced) over `dur` seconds of output: a pitch that
    falls or rises."""
    n = int(dur * SR)
    r = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(rates)), rates)
    pos = np.cumsum(r) % (len(a) - 1)
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


# ---------------------------------------------------------------------------------------------- design tools

def _spec(a, gain, pad=0.06):
    """Zero-phase filter: every channel's spectrum times gain(frequencies)."""
    n0 = int(pad * SR)
    x = np.concatenate([np.zeros((n0, a.shape[1])), a, np.zeros((n0, a.shape[1]))])
    g = gain(np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 1.0))
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c]) * g, len(x)) for c in range(x.shape[1])], axis=1)
    return y[n0:n0 + len(a)]


def hp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (fc / f) ** (2 * order))


def lp(fc, order=2):
    return lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order))


def shelf_lo(fc, db):
    return lambda f: 10 ** (db / 20 / (1 + (f / fc) ** 2))


def shelf_hi(fc, db):
    return lambda f: 10 ** (db / 20 / (1 + (fc / f) ** 2))


def bell(fc, db, octaves=1.0):
    return lambda f: 10 ** (db / 20 * np.exp(-0.5 * (np.log2(f / fc) / (octaves / 2)) ** 2))


def eq(a, *stages):
    def gain(f):
        g = np.ones_like(f)
        for st in stages:
            g = g * st(f)
        return g
    return _spec(a, gain)


def stereo(a):
    return a if a.shape[1] == 2 else np.repeat(a, 2, axis=1)


def thump(f0, f1, dur, tau, glide_tau=0.03, ch=1):
    """A blow of air: a sine falling from f0 to f1 Hz, dying away with time constant `tau`."""
    t = np.arange(int(dur * SR)) / SR
    f = f1 + (f0 - f1) * np.exp(-t / glide_tau)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * (1 - np.exp(-t / 0.003)) * np.exp(-t / tau)
    return fade(np.repeat(y[:, None], ch, axis=1), 0.0, dur * 0.3)


def room_ir(rt, dur, seed, ch=2, early=((9, 0.55), (15, -0.4), (21, 0.42), (29, -0.34), (38, 0.3), (50, -0.24), (63, 0.2)),
            late=0.5, build=0.045):
    """The impulse response of a hard-walled room: discrete early reflections (ms, gain), then a diffuse tail that
    swells over `build` seconds and dies away, `rt` = (RT60 under 300 Hz, 300-3000 Hz, over 3000 Hz) seconds.
    Each channel has its own noise (a wide tail). Energy normalised to 1 per channel."""
    rng = np.random.default_rng(seed)
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros((n, ch))
    for c in range(ch):
        noise = rng.standard_normal((n, 1))
        tail = np.zeros((n, 1))
        for band, r in zip(((hp(20), lp(300, 3)), (hp(300, 3), lp(3000, 3)), (hp(3000, 3), lp(16000))), rt):
            tail += _spec(noise, lambda f, b=band: b[0](f) * b[1](f), 0.0) * np.exp(-6.91 * t / r)[:, None]
        tail *= (1 - np.exp(-t / build))[:, None]
        tail *= late / np.sqrt((tail ** 2).sum())
        ir = tail[:, 0]
        for k, (ms, g) in enumerate(early):
            i = int((ms + rng.uniform(-1.5, 1.5) + (1.3 * c if k % 2 else -1.3 * c)) * SR / 1000)
            ir[i] += g * (1.0 - late)
        out[:, c] = ir / np.sqrt((ir ** 2).sum())
    return out


def convolve(a, ir):
    n = len(a) + len(ir) - 1
    m = 1 << (n - 1).bit_length()
    out = np.zeros((n, max(a.shape[1], ir.shape[1])))
    for c in range(out.shape[1]):
        x = a[:, min(c, a.shape[1] - 1)]
        h = ir[:, min(c, ir.shape[1] - 1)]
        out[:, c] = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]
    return out


def sat(a, drive_db):
    """Soft clipping: the peak is driven `drive_db` into tanh. Output peak 1."""
    a = a / (np.abs(a).max() + 1e-12)
    d = 10 ** (drive_db / 20)
    return np.tanh(a * d) / np.tanh(d)


def squeeze(a, thr_db=-16.0, ratio=5.0, release=0.03, look=0.002):
    """A fast compressor with look-ahead: what is over `thr_db` (re the peak) is turned down by `ratio`, at once,
    and let up again over `release` seconds. It takes the crack down without adding harmonics, which is what
    brings everything after the first millisecond up. Output peak 1."""
    a = a / (np.abs(a).max() + 1e-12)
    mag = np.abs(a).max(axis=1)
    n = int(look * SR)
    pad = np.concatenate([mag, np.zeros(n)])
    ahead = np.max(np.stack([pad[k:k + len(mag)] for k in range(0, n + 1, 4)]), axis=0)      # the loudest sample just ahead
    over = np.maximum(20 * np.log10(ahead + 1e-9) - thr_db, 0.0)
    want = -over * (1.0 - 1.0 / ratio)                                                       # gain, dB
    g = np.empty_like(want)
    k = 1.0 - np.exp(-1.0 / (release * SR))
    cur = 0.0
    for i, w in enumerate(want):
        cur = w if w < cur else cur + (w - cur) * k
        g[i] = cur
    y = a * (10 ** (g / 20))[:, None]
    return y / (np.abs(y).max() + 1e-12)


def at_peak(a, i_peak):
    """`a` shifted so that its loudest sample sits at index i_peak (returns (sound, delay in seconds >= 0))."""
    i = int(np.argmax(np.abs(a).max(axis=1)))
    if i > i_peak:
        return a[i - i_peak:], 0.0
    return a, (i_peak - i) / SR


def loud(a, win=0.2):
    """Loudness, dB: K-weighted (as ITU-R BS.1770: treble shelf, bass roll-off), the loudest `win` seconds. A mono
    file counts as it is played: the same signal in both speakers."""
    k = eq(a, shelf_hi(1500, 4.0), hp(60, 2))
    p = (k ** 2).mean(axis=1) * 2.0
    n = int(win * SR)
    if len(p) <= n:
        ms = p.sum() / n
    else:
        c = np.cumsum(np.concatenate([[0.0], p]))
        ms = (c[n:] - c[:-n]).max() / n
    return -0.691 + 10 * np.log10(ms + 1e-20)


LOUD = -20.0          # every file's loudness
CEIL = -1.0           # and no sample over this, dBFS
_short = []           # (name, dB under LOUD): files that could not be made as loud without clipping


def finish(a, name=""):
    """To the common loudness. A sound too peaky to get there under the ceiling has its peaks rounded off (up to
    8 dB of soft clipping); past that it stays quieter and is listed."""
    a = a * 10 ** ((LOUD - loud(a)) / 20)
    c = 10 ** (CEIL / 20)
    pk = np.abs(a).max()
    if pk > c:
        over = 20 * np.log10(pk / c)
        if over > 8.0:
            a = a * 10 ** (-(over - 8.0) / 20)
            _short.append((name, over - 8.0))
        knee = c * 0.5                                     # (everything under half the ceiling is untouched)
        mag = np.abs(a)
        hot = mag > knee
        a = a.copy()
        a[hot] = np.sign(a[hot]) * (knee + (c - knee) * np.tanh((mag[hot] - knee) / (c - knee)))
    return a


def take(path, i, length, st=True, pre=0.006, quiet=0.3, thr_db=-18.0):
    """Shot number i of a firearm recording, raw: from `pre` s before its crack, `length` s."""
    a = load(path, st)
    on = onsets(a, quiet, thr_db)
    o = on[i % len(on)]
    return a[max(o - int(pre * SR), 0):o + int(length * SR)]


def gun(shot, *, ir, wet=-16.0, body=0.7, boom=0.5, sub=0.4, sub_hz=(150, 52), sub_tau=0.055, action=None, action_gain=0.2,
        squeeze_db=-16.0, warm=6.0, length=1.0, crack_hp=140, tone=(), out_fade=0.4, rng=None):
    """One game gunshot from one recorded shot (see the top of the file). `body`, `boom`, `sub`, `action_gain` are
    relative to the crack's peak once it is squeezed; `wet` is the room's energy against the dry shot's, dB;
    `warm` = how hard the low layers are driven into soft clipping, dB; `tone` = eq stages for the result."""
    rng = rng or np.random.default_rng(0)
    ch = shot.shape[1]
    pk = np.abs(shot).max()
    crack = squeeze(eq(shot / pk, hp(crack_hp)), squeeze_db)
    i0 = int(np.argmax(np.abs(crack).max(axis=1)))
    lows = []
    if body:
        b = eq(pitch(shot / pk, 0.5 * rng.uniform(0.96, 1.04)), hp(70), lp(900, 2))
        b, d = at_peak(squeeze(b, squeeze_db + 4.0), i0)
        lows.append((b, body, d))
    if boom:
        b = eq(pitch(shot / pk, 0.25 * rng.uniform(0.95, 1.05)), hp(45), lp(320, 3))
        b, d = at_peak(b / np.abs(b).max(), i0)
        lows.append((fade(b, 0.0, 0.2), boom, d))
    if sub:
        k = rng.uniform(0.94, 1.06)
        lows.append((thump(sub_hz[0] * k, sub_hz[1] * k, 0.45, sub_tau, ch=ch), sub, max(i0 / SR - 0.001, 0.0)))
    parts = [(crack, 1.0, 0.0)]
    if lows:
        low = layer(*lows)
        g = np.abs(low).max()
        parts.append((eq(sat(low, warm), lp(2500)) * g, 1.0, 0.0))        # (driven a little: weight, and overtones a small speaker can play)
    if action is not None:
        m = action if action.shape[1] == ch else (stereo(action) if ch == 2 else mono(action))
        parts.append((m / np.abs(m).max(), action_gain, i0 / SR + 0.035))
    dry = layer(*parts)
    send = eq(dry, hp(160), lp(7000))
    room = convolve(send, ir) * 10 ** (wet / 20) * np.sqrt((dry ** 2).sum() / ((send ** 2).sum() + 1e-12))
    y = layer((dry if dry.shape[1] == room.shape[1] else stereo(dry), 1.0, 0.0), (room, 1.0, 0.0))
    y = y[:int(length * SR)]
    y = eq(y, hp(32, 2), *tone)
    return fade(y, 0.0005, length * out_fade)


def o(name):
    return os.path.join(OG, name)


def recipes():
    r = {}
    # ---- the guns (The Free Firearm Sound Library), designed: see gun()
    rng = np.random.default_rng(7)
    rl = load(o("reload.wav"))                                             # a real handgun: magazine out, in, slide racked
    ar_rl = load(o("assaultriflereload1_0.wav"))                           # airsoft rifle: magazine out ... in, charging handle
    slide = fade(eq(cut(rl, 0.98, 1.30), hp(700))[:int(0.14 * SR)], 0.001, 0.06)          # the slide's clack
    bolt = fade(eq(cut(ar_rl, 1.17, 1.56), hp(600))[:int(0.09 * SR)], 0.001, 0.04)        # the bolt carrier's
    f = lambda gun_dir, name: os.path.join(FF, gun_dir, name)
    # Only the first tenth of a second of a recorded shot is used: after it come the echoes of the field it was
    # recorded in (the hills answer after 100-300 ms), which the squeeze would bring up into a second bang. The
    # room supplies the tail.
    dry_shot = lambda path, i, st=True: fade(take(path, i, 0.12, st), 0.0, 0.06)

    # pistol: Walther PPQ 9 mm, the three near shots, twice each with other dice (pitch of the layers, the room's noise)
    r["pistol_shot"] = [gun(dry_shot(f("Walther PPQ", "X_39P.wav"), i), ir=room_ir((0.9, 0.75, 0.4), 1.2, 10 + i), wet=-13.5,
                            body=0.6, boom=0.2, sub=0.12, action=slide, action_gain=0.16, length=1.15, rng=rng) for i in range(6)]

    # machine gun: AR-15 5.56, its two near shots, three times each with other dice. Twelve a second: each shot is
    # short and its room small; the long tail is a sound of its own, played when the trigger is let go.
    # (The recording is dull over 1.5 kHz, where a 5.56's crack lives: the treble is lifted, the 650 Hz box cut.)
    ar = [dry_shot(f("AR-15", "D_32P.wav"), 0), dry_shot(f("AR-15", "D_32P.wav"), 1)]
    r["rifle_shot"] = [gun(ar[i % 2], ir=room_ir((0.42, 0.36, 0.2), 0.5, 30 + i, late=0.4), wet=-16.0, body=0.6, boom=0.2, sub=0.13,
                           sub_hz=(135, 60), sub_tau=0.032, action=bolt, action_gain=0.13, length=0.5, out_fade=0.5,
                           tone=(shelf_hi(2500, 5.0), bell(650, -2.5, 1.5)), rng=rng) for i in range(6)]
    dry = gun(ar[0], ir=room_ir((0.4, 0.3, 0.2), 0.3, 1), wet=-60.0, body=0.6, boom=0.2, sub=0.13, length=0.4,
              tone=(shelf_hi(2500, 5.0), bell(650, -2.5, 1.5)), rng=rng)
    far = convolve(eq(dry, hp(140), lp(5500)), room_ir((1.5, 1.2, 0.6), 2.0, 44, early=(), late=1.0, build=0.08))
    r["rifle_tail"] = [fade(far[int(0.07 * SR):int(1.9 * SR)], 0.05, 1.2)]                 # the room ringing after the last round

    # the robots' guns: mono, single shots recorded at a distance (duller: the treble is lifted) and rounds out of
    # the long bursts recorded close by (the distant bursts are a tangle of shots and their echoes), a little more
    # room
    far_tone = (shelf_hi(2000, 5.0),)

    def robot_gun(paths, n, rt=(0.9, 0.7, 0.35), **kw):
        out = []
        for i in range(n):
            path, idx, burst = paths[i % len(paths)]
            shot = take(path, idx, 0.075 if burst else 0.1, st=False, quiet=0.035 if burst else 0.3, thr_db=-12.0 if burst else -18.0)
            shot = fade(shot, 0.0, 0.02 if burst else 0.04)
            out.append(gun(shot, ir=room_ir(rt, 1.4, 60 + i, ch=1), tone=far_tone, rng=rng, **kw))
        return out
    # spider: a cannon. Tikka .30-06
    r["spider_shot"] = robot_gun([(f("Tikka", "W_24P.wav"), 0, False), (f("Tikka", "W_24P.wav"), 1, False)], 4,
                                 wet=-15.0, body=0.65, boom=0.3, sub=0.18, sub_hz=(120, 46), sub_tau=0.07, length=1.3)
    # drone: a light, fast gun. Carl Gustav M45 9 mm: its three single shots, three rounds out of a long burst
    m45, m45b = f("Carl Gustav M45", "G_20P.wav"), f("Carl Gustav M45", "G_35P.wav")
    r["drone_shot"] = robot_gun([(m45, 0, False), (m45b, 2, True), (m45, 1, False), (m45b, 5, True), (m45, 2, False), (m45b, 8, True)], 6,
                                rt=(0.7, 0.6, 0.3), wet=-15.0, body=0.5, boom=0.12, sub=0.06, length=0.75)
    # turret: AK-47 7.62x39: two single shots, four rounds out of a long burst
    ak, akb = f("AK-47", "C_31P.wav"), f("AK-47", "C_27P.wav")
    r["turret_shot"] = robot_gun([(ak, 0, False), (akb, 3, True), (ak, 1, False), (akb, 11, True), (akb, 6, True), (akb, 19, True)], 6,
                                 wet=-15.0, body=0.6, boom=0.25, sub=0.14, sub_hz=(135, 50), length=1.05)
    # ---- handling the guns
    r["pistol_mag_out"] = [level(cut(rl, 0.06, 0.40), -8.0)]
    r["pistol_mag_in"] = [level(cut(rl, 0.54, 0.90), -3.0)]
    r["slide"] = [level(cut(rl, 0.98, 1.50), -2.0)]
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
    # a round glancing off: a metal hit with its pitch falling away (resampled at a sliding rate): the whine of a ricochet
    r["ricochet"] = [fade(eq(glide(whole(o(bf + "metal_hit_%02d.ogg" % i)), rates, 0.42), hp(600)), 0.001, 0.25)
                     for i, rates in ((1, (1.5, 1.25, 0.85, 0.6)), (3, (1.7, 1.3, 0.9, 0.7)), (6, (1.4, 1.1, 0.75, 0.5)))]
    r["robot_hit"] = [level(pitch(whole(o(n)), 0.8)) for n in (bf + "metal_hit_02.ogg", bf + "metal_hit_04.ogg", bf + "metal_hit_05.ogg")] \
        + [level(whole(o("sfx_100_v2/sfx100v2_metal_hit_01.ogg")))]
    # a round passing the head: short swishes, which as recorded are a low "fwip" (80-500 Hz); a bullet's pass is
    # a sharper thing: played 1.6 times as fast, the treble lifted
    r["flyby"] = [eq(pitch(whole(o("swishes/swishes/swish-%d.wav" % i)), 1.6), hp(180), shelf_hi(1500, 6.0)) for i in (1, 10, 11, 12, 13)]
    # ---- the player's body
    # Boots on a hard floor: Kenney's concrete footsteps (Impact Sounds, CC0; in assets_src/audio/, V1's download):
    # a short dull tap, nearly all of it under 500 Hz. (The first set, steps on stone from a "sand and stone" pack,
    # had a 0.15 s gritty scrape at 1.5-10 kHz in every step: the user heard sand, and tired of it.)
    ks = os.path.join(SRC, "..", "audio", "impact-sounds", "Audio", "footstep_concrete_%03d.ogg")
    r["step"] = [whole(ks % i) for i in range(5)] + [pitch(whole(ks % 1), 0.93), pitch(whole(ks % 2), 1.07)]
    r["jump"] = [pitch(whole(ks % 2), 1.15)]
    thud = whole(o(bf + "hit_02.ogg"))                                      # a low, dull blow
    r["land"] = [layer((level(pitch(whole(ks % 1), 0.8), -3.0), 1.0, 0.0), (level(thud, -3.0), 0.9, 0.0))]
    r["crouch"] = [level(whole(o("rattle1.wav")), -6.0), level(whole(o("lightclunk2.wav")), -6.0)]
    r["hurt"] = [level(whole(o(bf + "hit_07.ogg"))), level(whole(o("sfx_100_v2/sfx100v2_hit_01.ogg")))]
    # going down: the dull blow, with a harder hit in it (alone and pitched down it was all under 200 Hz: nothing on a laptop)
    r["down"] = [layer((pitch(thud, 0.85) / np.abs(thud).max(), 1.0, 0.0), (level(pitch(whole(o(bf + "hit_07.ogg")), 0.8), 0.0), 0.7, 0.0))]
    # ---- the robots
    r["spider_step"] = [level(whole(o("metal_steps_48k24b/metal_steps_%02d.wav" % i)), -3.0) for i in range(1, 11)]
    # a joint driven round: an electric motor run up and let go (the fan recording, three to four times as fast:
    # its 160 Hz hum becomes a 500-600 Hz whine that rises and falls) with a trace of gear squeal (a squeak that
    # sits at 16 kHz as recorded: eight times slower). The first version was that squeak alone at 8 kHz: piercing.
    fan = load(o("fan_interval.wav"))
    sq = whole(o("roboticsqueeze.flac"))

    def servo(rates, dur, squeal):
        m = eq(glide(fan, rates, dur), hp(260), lp(3800))
        g = eq(pitch(sq, squeal), lp(5000))[:len(m)]
        return fade(layer((m / np.abs(m).max(), 1.0, 0.0), (g / np.abs(g).max(), 0.16, 0.02)), 0.03, dur * 0.35)
    r["servo"] = [servo((2.6, 3.7, 3.4, 2.4), 0.5, 0.125), servo((3.0, 4.0, 3.2), 0.36, 0.14), servo((2.4, 3.3, 3.5, 2.2), 0.62, 0.11)]
    r["drone_rotor"] = [level(loop(pitch(load(o("fan_interval.wav")), 1.5)), -3.0)]                 # loop
    mf = bf + "metal_falling_%02d.ogg"
    bang = "25-CC0-bang-sfx/"
    r["robot_break"] = [level(layer((whole(o(mf % 1)), 1.0, 0.03), (whole(o(bang + "bang_05.ogg")), 0.8, 0.0))),
                        level(layer((whole(o(mf % 2)), 1.0, 0.03), (whole(o(bang + "bang_08.ogg")), 0.8, 0.0)))]
    # a motor running down: the fan again, its pitch sliding from high to a third of it over two seconds
    # (a ready-made "machine shutting down" on OpenGameArt is cut from a freesound.org recording whose licence could
    # not be checked: not used)
    r["power_down"] = [level(fade(glide(load(o("fan_interval.wav")), (1.7, 0.3), 2.0), 0.01, 1.2), -2.0)]
    r["crash"] = [level(layer((pitch(whole(o(mf % 3)), 0.7), 1.0, 0.0), (thud, 1.0, 0.0))),
                  level(layer((pitch(whole(o(mf % 4)), 0.6), 1.0, 0.0), (thud, 1.0, 0.0)))]
    # the drone blowing up: two recorded bangs laid over each other, a low blow under them (a 46 Hz thump: as for
    # the guns, what no microphone at a distance keeps; kept small, a laptop cannot play it), driven a little, in
    # the room
    def blast(a, seed):
        y = sat(layer((a / np.abs(a).max(), 1.0, 0.0), (thump(110, 46, 1.0, 0.2, 0.06), 0.35, 0.0)), 7.0)
        room = convolve(eq(y, hp(120), lp(5000)), room_ir((1.7, 1.3, 0.6), 2.2, seed, ch=1)) * 0.35
        return fade(layer((y, 1.0, 0.0), (room, 1.0, 0.0))[:int(2.4 * SR)], 0.0005, 1.2)
    r["explosion"] = [blast(layer((whole(o(bang + "bang_03.ogg"), t_out=0.3), 1.0, 0.0), (whole(o(bang + "cannon_02.ogg"), t_out=0.5), 0.8, 0.0)), 81),
                      blast(layer((whole(o(bang + "cannon_01.ogg"), t_out=0.4), 1.0, 0.0), (pitch(whole(o(bang + "bang_03.ogg")), 0.9), 0.9, 0.0)), 82)]
    # a robot coming back: the fan again, run up instead of down
    r["power_up"] = [fade(glide(load(o("fan_interval.wav")), (0.35, 1.5), 1.3), 0.15, 0.35)]
    # ---- the game: doors, crates, what is picked up, the exit (the 100 CC0 SFX #2 pack, and the motor loop again)
    sx = "sfx_100_v2/sfx100v2_"
    motor = eq(glide(fan, (1.2, 2.1, 2.0, 1.0), 0.75), hp(220), lp(3000))
    r["door"] = [layer((level(whole(o(sx + "door_05.ogg")), -6.0), 1.0, 0.0), (level(fade(motor, 0.03, 0.2), -9.0), 1.0, 0.05),
                       (level(whole(o(sx + "door_03.ogg")), -3.0), 1.0, 0.6))]            # latch, the leaves run on their motor, home with a thud
    r["crate"] = [layer((level(whole(o(sx + "lock_open_01.ogg")), -6.0), 1.0, 0.0), (level(whole(o(sx + "door_01.ogg")), -4.0), 1.0, 0.3))]
    r["pickup"] = [pitch(whole(o(sx + "items_01.ogg")), 0.8), pitch(whole(o(sx + "items_02.ogg")), 0.8)]
    r["dry"] = [fade(whole(o(sx + "switch_01.ogg"))[:int(0.14 * SR)], 0.001, 0.05)]      # an empty gun
    r["ui"] = [whole(o(sx + "switch_02.ogg"))]
    r["heal"] = [layer((level(whole(o(sx + "air_03.ogg")), -3.0), 1.0, 0.0), (level(fade(whole(o(sx + "air_02.ogg")), 0.05, 0.6), -12.0), 1.0, 0.2))]
    r["room_tone"] = [loop(eq(load(o(sx + "loop_ambient_04.ogg")), hp(70), lp(1800)), 1.0)]   # loop: the ventilation of the place, very low
    r["exit_hum"] = [loop(load(o(sx + "loop_machine_04.ogg")), 0.5)]                      # loop: the gate's field
    r["exit"] = [layer((level(fade(glide(fan, (0.5, 2.4), 1.6), 0.2, 0.5), -6.0), 1.0, 0.0),
                       (level(fade(whole(o(sx + "air_01.ogg")), 0.3, 1.2), -6.0), 1.0, 0.1))]   # through the gate
    r["zap"] = [level(whole(o("spark.wav")), -3.0), level(whole(o("continuousspark.wav")), -3.0)]     # a small Tesla coil
    return r


def write(key, i, a):
    os.makedirs(OUT, exist_ok=True)
    name = "%s_%02d.ogg" % (key, i + 1)
    a = np.clip(finish(a, name), -1, 1).astype(np.float32)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", str(a.shape[1]), "-ar", str(SR), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "6", os.path.join(OUT, name)], input=a.tobytes(), check=True)
    return a


BANDS = ((20, 80), (80, 200), (200, 500), (500, 1500), (1500, 4000), (4000, 10000), (10000, 20000))


def numbers(a):
    """(loudness, peak dBFS, seconds until the envelope is 20 dB under its top, energy per band in dB re the whole)."""
    e = env(a, 0.01)
    i0 = int(np.argmax(e))
    under = np.flatnonzero(e[i0:] < e[i0] * 0.1)
    m = a.mean(axis=1)
    sp = np.abs(np.fft.rfft(m)) ** 2
    fr = np.fft.rfftfreq(len(m), 1 / SR)
    return (loud(a), 20 * np.log10(np.abs(a).max() + 1e-12), (under[0] if len(under) else len(a)) / SR,
            [10 * np.log10(sp[(fr >= lo) & (fr < hi)].sum() / (sp.sum() + 1e-20) + 1e-12) for lo, hi in BANDS])


def report():
    print("%-22s %5s %6s %6s %6s   %s" % ("file", "s", "loud", "peak", "T-20", "energy per band, dB: " + " ".join("%d-%d" % b for b in BANDS)))
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".ogg"):
            a = load(os.path.join(OUT, f), channels(os.path.join(OUT, f)) == 2)
            L, pk, t20, bands = numbers(a)
            print("%-22s %5.2f %6.1f %6.1f %6.3f   %s" % (f, len(a) / SR, L, pk, t20, " ".join("%6.1f" % x for x in bands)))


if __name__ == "__main__":
    if "--report" in sys.argv:
        report()
        sys.exit(0)
    for f in os.listdir(OUT) if os.path.isdir(OUT) else []:
        if f.endswith(".ogg"):
            os.remove(os.path.join(OUT, f))
    total = 0
    for key, variants in recipes().items():
        done = [write(key, i, a) for i, a in enumerate(variants)]
        total += len(variants)
        print("%-16s %d  %s" % (key, len(variants), " ".join("%.2fs" % (len(a) / SR) for a in done)))
    print("wrote", total, "files to", os.path.normpath(OUT), "at %.0f dB loudness" % LOUD)
    for name, db in _short:
        print("  %s is %.1f dB quieter than the rest (too peaky to bring up)" % (name, db))
    sys.exit(0)
