## Project Firewall UI palette and shared StyleBoxes (Godot 4).
## Global class: use UIPalette.CYAN, UIPalette.hud_panel() etc. No autoload needed.
class_name UIPalette
extends RefCounted

const FACILITY_WHITE := Color("F2F4F3")
const GRAPHITE := Color("111416")
const GRAPHITE_SECONDARY := Color("50585C")
const DIVIDER_ON_WHITE := Color("C9CFD1")

const CYAN := Color("3FD0E8")
const CYAN_LIGHT := Color("8BE6F5")
const ORANGE := Color("FF7A1A")
const ORANGE_LIGHT := Color("FFB27A")
const ORANGE_PALE := Color("FFD3B3")

const TEXT := Color("F4F7F8")
const TEXT_SECONDARY := Color("C9D2D6")
const LABEL := Color("9AA6AD")

const HUD_GLASS := Color(0.055, 0.071, 0.082, 0.70)
const HUD_GLASS_STRONG := Color(0.055, 0.071, 0.082, 0.78)
const HUD_GLASS_BORDER := Color(1, 1, 1, 0.12)
const SEGMENT_EMPTY := Color(1, 1, 1, 0.14)
const SEGMENT_LOST_GHOST := Color(1.0, 0.698, 0.478, 0.55)

const WEAPON_SCREEN_BG := Color("08161B")
const WEAPON_SCREEN_BG_LOW := Color("1B0F08")

const COMPLETE_BG := Color("33383B")
const FAILURE_BG := Color("070504")

const HEALTH_LOW_THRESHOLD := 40


## Translucent dark HUD panel (room, threat, health, weapon slots).
static func hud_panel(strong := false, border_color := HUD_GLASS_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = HUD_GLASS_STRONG if strong else HUD_GLASS
	sb.set_border_width_all(1)
	sb.border_color = border_color
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb


## Weapon slot background. The active slot also gets a 3 px CYAN ColorRect
## anchored to its bottom edge (StyleBoxFlat can't color one side differently).
static func weapon_slot(active: bool) -> StyleBoxFlat:
	var sb := hud_panel(active, HUD_GLASS_BORDER if active else Color(1, 1, 1, 0.08))
	if not active:
		sb.bg_color = Color(0.055, 0.071, 0.082, 0.5)
	return sb


## White facility sign (map board).
static func sign_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FACILITY_WHITE
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 30
	sb.shadow_offset = Vector2(0, 24)
	return sb


## Filled button (cyan on Mission complete, orange on Signal lost).
static func button_filled(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	return sb


## Outline button ("STOP HERE").
static func button_outline() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.957, 0.969, 0.973, 0.5)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	return sb


static func health_color(health: int) -> Color:
	return ORANGE if health <= HEALTH_LOW_THRESHOLD else CYAN
