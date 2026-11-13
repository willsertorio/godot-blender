"""Shared timing of the Firefight section of v2/scene.blend: the weapon views, the robots and the effects all read
it, so that a shot, its recoil, its flash, its tracer and its impact agree. Offsets are frames from FF_START."""
FF_START, FF_N = 1601, 72          # the section (3 s)
FF_HERO = 36                       # everybody fires on this frame: the one rendered as the still
FF_PISTOL = (6, 16, 26, 36, 46, 56, 66)                # frames the pistol's flash shows
FF_RIFLE = ((8, 7), (30, 8))                           # bursts: (first flash, rounds); a round every 2 frames
FF_SPIDER = (6, 21, 36, 51, 66)                        # twin shots
FF_DRONE = (12, 24, 36, 48, 60)
FF_TURRET = (8, 12, 16, 34, 36, 40, 44, 64, 68)        # barrels alternate
SHOOT_SPIDER = SHOOT_DRONE = (6, 12, 18)               # the robots' Shoot section (frames from its start)
SHOOT_TURRET = (6, 10, 14, 18)
