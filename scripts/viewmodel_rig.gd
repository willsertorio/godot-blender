class_name ViewmodelRig
extends Node
## Renders the weapon + arms with their own camera, drawn over the world and under the HUD:
##  - own FOV (no wide-angle stretch on things 30 cm from the eye) and a 1 cm near plane
##  - can never clip into walls (separate pass)
##  - a key + rim light that light only the viewmodel layer, so the gun reads in any room
## The world camera excludes VIEWMODEL_LAYER; viewmodel meshes are put on it by `adopt()`.

const VIEWMODEL_LAYER := 1 << 4  # render layer 5
const FOV := 54.0

var world_camera: Camera3D
var container: SubViewportContainer
var viewport: SubViewport
var camera: Camera3D
var canvas: CanvasLayer
## Capture tour: when false the viewmodel camera stays where it was put (inspection shots).
var follow := true


func setup(p_world_camera: Camera3D, world_env: Environment) -> void:
	world_camera = p_world_camera
	world_camera.cull_mask &= ~VIEWMODEL_LAYER

	canvas = CanvasLayer.new()
	canvas.layer = 5  # above the 3D view, below the HUD (GameUI is layer 10)
	add_child(canvas)
	container = SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(container)
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.01
	camera.far = 5.0
	camera.cull_mask = VIEWMODEL_LAYER
	# Same look as the world but no fog/glow (glow on a transparent pass leaves halos).
	var env := world_env.duplicate() as Environment if world_env else Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.fog_enabled = false
	env.glow_enabled = false
	camera.environment = env
	viewport.add_child(camera)
	camera.current = true

	# Hero lighting for the viewmodel only: warm key from upper left, cool rim from behind right.
	for spec in [[Vector3(-35, -30, 0), Color(1.0, 0.96, 0.9), 0.9], [Vector3(-10, 150, 0), Color(0.6, 0.8, 1.0), 0.9]]:
		var l := DirectionalLight3D.new()
		l.rotation_degrees = spec[0]
		l.light_color = spec[1]
		l.light_energy = spec[2]
		l.light_cull_mask = VIEWMODEL_LAYER
		l.shadow_enabled = false
		l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		camera.add_child(l)


## Put every mesh under `root` on the viewmodel layer (and keep it out of shadow maps).
static func adopt(root: Node) -> void:
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = VIEWMODEL_LAYER
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(_delta: float) -> void:
	if follow and camera and world_camera and is_instance_valid(world_camera):
		camera.global_transform = world_camera.global_transform
