# V2 sounds

All CC0. Built by `tools/build_v2_audio.py` from the raw downloads in `assets_src/audio_v2/`
(`tools/fetch_v2_audio.sh` gets them; sources and licences: `licenses.csv`, rows "V2 sounds").
Files are `<key>_NN.ogg`; a key plays one of its files at random with a little pitch scatter.

**The guns are designed, not just cut.** The source is The Free Firearm Sound Library (real firearms, recorded in
a field at 24 bit / 96 kHz). A raw shot from it, measured: a 15-25 ms crack, 28 dB of crest factor, nearly all of
its energy between 500 and 1500 Hz, almost nothing under 200 Hz. Played as it is, that is a dry pop, not what a gun
sounds like to the person firing it in a room. Each game shot is one real shot in layers: the crack itself; the
same shot an octave and two octaves down (weight at 125-750 Hz); a small 50 Hz thump (the one synthetic part: the
blast a microphone a few metres off does not record); the gun's mechanism from a real reload recording; the crack
squeezed by a fast compressor so that the body comes up under it; the reflections and reverberation of a
hard-walled room; equalised. The player's guns are stereo, the robots' mono with more room. Result, pistol: crest
16 dB, 20 dB down after 0.1 s, a tail of 0.8 s, energy spread evenly from 80 Hz to 4 kHz.

**Levels.** Every file is brought to the same loudness (-20 dB, K-weighted, loudest 200 ms), so the mix is simply
the dB column of `SOUNDS` in `scripts/v2/v2_sfx.gd`: how loud a sound is against the pistol (0). The first mix
was set on peak levels, and measured as loudness it was upside down in places: the pistol's slide 7 dB louder
than its shot, a robot's servo only 5 dB under it.

**Not judged by ear.** The build machine has no sound. The guns were designed against numbers
(`python3 -I tools/build_v2_audio.py --report`: loudness, peak, decay, energy per band of every file); the foley
was chosen from names, lengths and spectra. If a sound is wrong: a layer's gain or a source file is one line in
the build script; a volume is one number in `SOUNDS`.

| key | what it is | source recording |
|---|---|---|
| `pistol_shot` | one pistol round (stereo, in the head), 6 variants | Walther PPQ 9 mm, near: 3 real shots, designed; slide layer from the handgun reload |
| `rifle_shot` | one machine gun round, short (twelve a second), 6 variants | AR-15 5.56, near: 2 real shots, designed, treble lifted; bolt layer from the rifle reload |
| `rifle_tail` | the room ringing after the last round, when the trigger is let go | the designed shot through a long room (1.5 s) |
| `casing` | a brass case on the floor | small metal clinks |
| `pistol_mag_out` / `pistol_mag_in` / `slide` | the pistol's reload | a real handgun reload, cut in three |
| `rifle_mag_out` / `rifle_mag_in` / `bolt` | the machine gun's reload | an airsoft rifle reload, cut in three; magazine clicks |
| `handling` | the gun shifting in the hands: draw, aim, inspect | equipment clicks, a rattle |
| `impact_concrete` | a round into a wall or floor | stone and rock hits |
| `impact_metal` | a round on a wreck or on armour | metal hits |
| `flyby` | a robot's round passing the head | short swishes |
| `step` / `jump` / `land` | boots on a hard floor, quiet | Kenney's concrete footsteps (short dull taps); a low thud for the landing |
| `crouch` | gear as the player drops or rises | a rattle, a light clunk |
| `hurt` / `down` | the player is hit / goes down | dull blows |
| `spider_shot` / `drone_shot` / `turret_shot` | the robots' guns, at their muzzles (mono), 4 / 6 / 6 variants | Tikka .30-06 / Carl Gustav M45 9 mm / AK-47: single shots at mid distance and rounds out of the near bursts, designed |
| `spider_step` | a metal foot coming down | metal footsteps on concrete |
| `servo` | a joint driven round | a motor run up and let go (the motor loop, 3-4 times as fast, gliding) + a trace of gear squeal |
| `drone_rotor` | LOOP, pitch bent by the game | a motor loop, pitched up |
| `robot_hit` | a round that hurt a robot | heavier metal hits, pitched down |
| `robot_break` | a robot destroyed | metal falling + a bang |
| `power_down` / `power_up` | motors running down / a robot back in service | the motor loop with its pitch sliding down / up |
| `crash` | a heavy machine hitting the floor | metal falling, pitched down, + a low thud |
| `explosion` | the drone blowing up | firework bangs and cannon shots, layered, a low thump under them, in the room |
| `zap` | electric sparks | a small Tesla coil |
