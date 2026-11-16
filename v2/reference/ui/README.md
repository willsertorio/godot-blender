# Project Firewall: UI and HUD handoff

This package holds the UI concept for **Project Firewall**, a first-person procedural dungeon shooter, so it can be built in **Godot 4**.

## How to use this package (for Claude Code)

1. Copy `fonts/`, `icons/` and `godot/` into the Godot project, for example under `res://ui/`.
2. Read `screens/*.png` first. They are the visual target, rendered at **1440×810**. `Kit.png` collects every state of every component.
3. Build each screen from the **Screens** section below. Every pixel value is at 1440×810.
4. Hook the HUD to existing game state using **Data bindings**. Find the real variable and signal names in the codebase; don't invent new systems.
5. Keep gameplay code unchanged. This is a UI pass.

Suggested prompt: *"Implement the UI in `firewall-ui/README.md` in this Godot project. Start with the HUD, then the end screens, then the title screen. Match `screens/*.png`."*

---

## Project setup

- **Viewport:** set *Project Settings → Display → Window → Size* to 1440×810. Set *Stretch Mode* to `canvas_items` and *Aspect* to `expand`, so the spec's px values map 1:1 and scale cleanly to 1080p and 4K.
- **Fonts:** Barlow and Barlow Condensed are in `fonts/` (SIL Open Font License, see `fonts/OFL.txt`).
  - Make a `Theme` whose default font is `Barlow-Regular.ttf` at size 16.
  - Use `FontVariation` resources or separate fonts per weight:
    - Light 300 for big numbers
    - SemiBold 600 for objective text
    - Bold 700 for labels and buttons
    - Condensed ExtraBold 800 for titles
  - For letter spacing, set `FontVariation.spacing_glyph` to `tracking_em × font_size`. For example, 0.24em at 11px is about 2.6px.
- **Icons:** `icons/*.svg` are drawn in white. Import them as textures and tint with `modulate` or `self_modulate`.
- **Colors and styles:** `godot/ui_palette.gd` (global class `UIPalette`) holds every color and the shared `StyleBoxFlat` builders. The full token list is in `design/tokens.json`.
- **Shaders:** `godot/shaders/`
  - `screen_blur.gdshader`: blurs the 3D view behind the HUD.
  - `damage_vignette.gdshader`: orange edge glow, stronger on the side the hit came from.
  - `scanlines.gdshader`: scanlines for the Signal lost screen.

### Layer order (CanvasLayers above the 3D view)

| layer | contents |
|---|---|
| 1 | `BlurRect`: full-screen ColorRect with `screen_blur`. Hidden by default. |
| 2 | `DamageVignette`: full-screen ColorRect with `damage_vignette`, intensity 0 by default. |
| 3 | `HUD` (all in-play panels and the crosshair) |
| 4 | `MapOverlay` (Tab) |
| 5 | `EndScreen` (Mission complete / Signal lost) |

Set `mouse_filter = IGNORE` on every HUD Control so nothing steals clicks.

---

## Visual language

- **Look:** a sterile, white, Portal-like facility. Menus look like wall signage: white boards, graphite ink, big thin numbers.
- **In play:** the HUD uses dark translucent glass panels so it reads against the bright white rooms.
- **Two signal colors only:**
  - **Cyan `#3FD0E8`** means you, the system, focus and "good".
  - **Orange `#FF7A1A`** means danger, damage, low and hostiles.
- **Corruption** (RGB split, jitter, blur, scanlines) appears **only at story moments**: the end screens. Normal play stays clean.
- **Numbers** use Barlow Light with tabular figures and zero-padding where shown (`02 / 08`, `THREAT 00`).

---

## Screens

### 1. Title (`screens/Main.png`)
- Full-screen solid `FACILITY_WHITE #F2F4F3`. Nothing else on screen.
- Centered logo stack, 22px gap between items:
  - "PROJECT": Barlow SemiBold 18px, tracking 0.6em, graphite.
  - "FIREWALL": Barlow Condensed ExtraBold 168px, graphite, line height 0.88.
  - A 120×6 bar in CYAN.
- "PRESS ENTER": Barlow Bold 16px, tracking 0.5em, `#50585C`, centered, 112px from the bottom. Its alpha pulses 1.0 → 0.25 → 1.0 over 1.8s (ease in-out, looping).
- **Input:** Enter (or any key/click, your call) starts a run. There is **no** menu, no Lab and no Quit on this screen.

### 2. HUD: explore (`screens/HudExplore.png`)
Panels sit 32px from the left/right edges and 28px from the top/bottom.

**Top-left: room panel.** `hud_panel()` glass at 70%, split in two by a 1px divider (`HUD_GLASS_BORDER`).
- Left cell (padding 10/16):
  - Label "ROOM": 11px Bold caps, tracking 0.24em, `#9AA6AD`.
  - Number "01": Light 40px. Followed by " / 08" in Medium 18px, `#9AA6AD`.
- Right cell (padding 10/18, two lines, 6px gap):
  - Objective line: SemiBold 16px with a 14px icon. When the room is clear the icon is a CYAN check and the text is "Room clear. Find the exit portal." When hostiles are present the icon is an ORANGE `enemy_*` icon and the text is "N hostile(s) in this room".
  - Exit line: 13px `#C9D2D6` with a small portal outline. Shows "Exit portal not located", or "Exit portal: N rooms away" once the exit room is known.

**Top-right**, two small glass chips with an 8px gap:
- `THREAT 00`: label Bold 12px tracking 0.22em, value Medium 18px. THREAT is the number of missions completed.
- `[TAB] MAP`: the key cap is a 1px white-50% outlined box, 11px Bold.

**Center: crosshair.** A 26px ring (2px, `TEXT` at 85% alpha, with a 1px black-35% outer line) and a 4px center dot.

**Interact prompt.** A glass chip with a CYAN 1px border, placed 32px right of the crosshair and vertically centered on it. It holds a 26×26 CYAN key cap with a graphite "E" (ExtraBold 15px), then "OPEN DOOR" in Bold 14px tracking 0.18em. Use "OPEN CRATE" for containers.
- **Show it only while the player is inside interact range of a closed door or container.** This also teaches the range, which the GDD says is currently invisible.

**Bottom-left: health panel.** 360px wide, glass at 70%, padding 14/16, 10px gap.
- Top row, left side: a 22px `health_cross` icon tinted with the health color, then the health number in Light 44px.
- Top row, right side: 3 kit slots (30×30, 6px gap), then a `Q` key cap.
  - Filled slot: CYAN 1px border, CYAN at 18% fill, `health_kit` icon in CYAN.
  - Empty slot: 1px dashed white-30% border, no fill. Approximate the dash with a plain 1px white-20% border if needed.
- Bar: **20 segments**, each 8px tall with a 3px gap, filling the panel width. Segments on = `round(health / 5)`. Segment color is CYAN, or ORANGE when health ≤ 40. Empty segments are white at 14%.

**Bottom-right: weapon slots.** Two icon tiles side by side with a 6px gap. No text names.
- Pistol tile is 72×52. Rifle tile is 104×52.
- Slot number ("1" / "2") in the top-left corner: 11px Bold, `#9AA6AD`.
- Icons: `weapon_pistol.svg` at 34px, `weapon_rifle.svg` at 70×30.
- Active tile: strong glass at 78%, icon in `TEXT` white, plus a **3px CYAN bar along the bottom edge**.
- Inactive tile: glass at 50%, icon in `#9AA6AD`.

**Ammo lives on the weapon, not the HUD.** Add a small emissive screen to each viewmodel, using a `SubViewport` → `ViewportTexture` on a quad, or a `Label3D`:
- **Rifle:** background `#08161B`. Shows `24` in SemiBold, CYAN with glow, plus `/ 60` reserve in `#8BE6F5`, with a thin magazine bar underneath. When the magazine is ≤ 25% of its size, switch to background `#1B0F08` with ORANGE text. While reloading, show "RELOAD" and a filling bar. When both the magazine and reserve are empty, show "1 · PISTOL" in orange.
- **Pistol:** a CYAN `∞`. The pistol never runs out.
- If the viewmodel screen is too much work for now, fall back to a small readout above the rifle tile. Keep the same styling.

### 3. HUD: combat, hit taken (`screens/HudCombat.png`)
Same layout as explore. These states change:
- **On each hit:**
  - Show `BlurRect` with `amount` tweened 3.0 → 0 over 0.5s.
  - Set `DamageVignette.intensity` to 1, then tween to 0 over 0.6s. Set `hit_dir` from the attacker's screen-space direction.
- **Hit direction indicator:** a 120px ring around the crosshair. Draw only a ~90° arc, 5px thick, ORANGE with a soft glow, pointing toward the attacker. It fades out with the vignette. Use `draw_arc()` in a custom Control.
- **Low health (≤ 40):**
  - The panel border becomes ORANGE at 55%.
  - The number turns `#FFB27A`.
  - The cross icon blinks (alpha 1 → 0.35, 0.9s loop).
  - A third line appears: "LOW · BREAK LINE OF SIGHT", 12px SemiBold, tracking 0.14em, `#FFB27A`.
- **Damage ghost:** when health drops, the lost segments show briefly as `SEGMENT_LOST_GHOST` (orange at 55%) before they empty, about 0.4s.
- **Healing with Q:** the new segments fill white, then settle to the bar color.
- **"Hostile lined up" crosshair** (when the center ray hits a hostile with clear line of sight): ORANGE ring at 30px, side brackets at 46px, orange dot. See `Kit.png`.
- **Aiming down sights:** shrink the ring, fade the HUD panels to 40% opacity. This quietly signals the slower movement.

### 4. Tab map (`screens/Map.png`)
- 3D view behind is darkened to about 45% brightness and desaturated (a black ColorRect at 55%).
- **Map board:** white sign panel (`sign_panel()`) at x48 y44, 920×722, padding 26/32.
  - Header: "MAP" in Condensed ExtraBold 44px on the left, "3 OF 8 ROOMS SEEN" in SemiBold 14px tracking 0.12em on the right, then a 2px graphite rule.
  - Floor plan area: 840×560 with a faint 20px grid (graphite at 6%). Draw it from real dungeon data:
    - **Explored room:** solid graphite rect, radius 3, room number in Light 22px white at top-left (padding 10/12).
    - **Current room:** CYAN rect, number SemiBold, graphite `player_arrow` icon (36px) rotated to the player's facing.
    - **Unexplored room:** 2px dashed `#8A9499` outline, "?" in `#6B757A`.
    - **Corridors:** solid 6px graphite line between explored rooms. 3px dashed `#8A9499` when either end is unexplored.
    - **Closed door:** 8×26 graphite bar across the corridor.
    - **Hostiles seen** in a room: ORANGE pill badge with the count (ExtraBold 12–13px).
    - **Exit portal:** `exit_portal` icon in the room once found.
- **Right column** (x = right 48, width 380, 14px gap), glass at 82%:
  - **ROUTE** card: portal icon plus "Exit portal not located", then a 14px helper line, e.g. "The exit waits in the final room. Five rooms are still unseen."
  - **KEY** card: legend for you are here, explored, unexplored, hostiles seen, closed door, exit portal.
  - Footer: `[TAB] CLOSE · the run keeps going`.
- The game keeps running while the map is open, matching the GDD's no-pause rule.

### 5. Mission complete (`screens/Complete.png`)
- **Solid background `#33383B`.** No scene, no effects.
- Content column at x72 y92, 600px wide, 22px gap:
  - Kicker: portal outline icon plus "EXIT PORTAL REACHED", 13px Bold, tracking 0.3em, `#8BE6F5`.
  - Title: "MISSION / COMPLETE" on two lines, Condensed ExtraBold 104px, line height 0.86, white.
    - **RGB split:** two copies behind it, ORANGE at 85% offset −4px x and CYAN at 85% offset +4px x.
    - **Jitter:** every ~3.2s, quick x offsets −14 → +10 → −4 → 0px, in steps rather than tweens.
  - Stats: 3 columns, 16px gap. Each column has a 2px white top rule, an 11px label (`#B4BEC3`) and a Light 44px value:
    - SCORE (thousands separator)
    - HOSTILES (enemies killed)
    - ROOMS (explored / total)
  - THREAT change bar: orange 12% fill, orange 60% border. Shows "THREAT 00 → 01" (new value in SemiBold `#FF9A4D`) and "Tougher, more numerous hostiles. Fewer kits."
  - Buttons:
    - **ENTER DATASPACE 02**: CYAN fill, graphite ExtraBold 17px, tracking 0.2em, chevron, height 56. Starts the next, harder run.
    - **STOP HERE**: outline. Returns to the title screen.

### 6. Signal lost, failure (`screens/Failure.png`)
- **Everything behind the text is heavily blurred:** `BlurRect` with `amount` ≈ 4.5, desaturated, with an orange tint (`tint = #FF5A0A`, alpha 0.12).
- Add a radial darkening (edges about 92% `#070504`) and `scanlines.gdshader` at 0.25 on top.
- Centered column, top at 150px, 28px gap. **Only these elements:**
  - "SIGNAL LOST": Condensed ExtraBold 128px, with an RGB split of ORANGE −5px and CYAN at 60% +5px, and jitter every ~2.6s.
  - The same 3 stats (SCORE / HOSTILES / ROOMS) in a 600px-wide row.
  - Buttons:
    - **RE-ASSEMBLE**: ORANGE fill, graphite text, `retry` icon. Starts a new run at the **same** THREAT; only completing a mission raises it.
    - **STOP HERE**: outline, back to title.
- No other text.

---

## Data bindings (GDD → UI)

| UI element | Game data |
|---|---|
| ROOM `NN / TT` | rooms entered (count of distinct rooms visited) / total rooms in this dungeon (8–12) |
| Objective line | hostiles alive in the current room (0 → "Room clear. Find the exit portal.") |
| Exit line | exit room discovered? → distance in rooms along the room graph |
| THREAT | missions completed this session (resets on reload, nothing is saved) |
| Health number + bar | player health 0–100 |
| Kit slots | carried health kits, 0–3 (Q spends one) |
| Weapon tiles | active weapon (1 = pistol, 2 = rifle) |
| Rifle screen | magazine / reserve, reloading flag |
| Interact prompt | nearest closed door or container within interact distance |
| Hit indicator + vignette | damage event + attacker world position |
| Map | dungeon room graph, visited flags, door states, hostiles seen per room, exit room once seen |
| End screens | success/failure, score (kill total), enemies killed, rooms explored / total |

## Files

```
README.md                     this spec
screens/                      PNG targets at 1440×810 (Kit at 1440×1240)
design/tokens.json            colors, type scale, spacing
fonts/                        Barlow + Barlow Condensed TTFs, OFL.txt
icons/                        white SVG icons, tint in Godot
godot/ui_palette.gd           class_name UIPalette: colors + StyleBoxFlat builders
godot/shaders/                screen_blur, damage_vignette, scanlines
mockups/                      static HTML sources of each screen (exact CSS values, if needed)
```
