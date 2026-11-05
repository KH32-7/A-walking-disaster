class_name ResidentPortrait
extends PanelContainer
## Resident portrait (D-13): the same CharacterLook body the base shows (D-09), rendered alone in a
## SubViewport with its own world. Owner: Lane D. Used by the dialog, gift, night event and
## welcome screens. BUST frames head and shoulders, FULL the whole body (외형 꾸미기).
##
##   var p := ResidentPortrait.new(Vector2(180, 210))
##   p.set_resident(id)               # Colony.appearance_for_look(id) + age stage
##   p.set_look(appearance, age)      # preview a look that is not saved yet

enum Framing { BUST, FULL }

var framing: Framing = Framing.BUST
var _vp: SubViewport
var _look: CharacterLook
var _cam: Camera3D
var _age := 3


func _init(px := Vector2(180, 210), frame := Framing.BUST) -> void:
	framing = frame
	custom_minimum_size = px
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.SLATE_2, 0.95)
	sb.border_color = UiTokens.LINE_STRONG
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(UiTokens.SLOT_RADIUS)
	add_theme_stylebox_override(&"panel", sb)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.size = Vector2i(px)
	holder.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d8dccf")
	env.environment.ambient_light_energy = 0.7
	_vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.1
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.5
	rim.light_color = Color("bfe3ff")
	_vp.add_child(rim)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_look = (load("res://art/characters/character.tscn") as PackedScene).instantiate() as CharacterLook
	_look.rotation_degrees.y = 18
	_vp.add_child(_look)
	_frame()


func set_resident(resident_id: StringName) -> void:
	var r := Colony.get_resident(resident_id)
	set_look(Colony.appearance_for_look(resident_id), int(r.get("age_stage", 3)))


func set_look(appearance: Dictionary, age_stage := 3) -> void:
	_age = age_stage
	_look.age_stage = age_stage
	_look.apply(appearance)
	_frame()


func _frame() -> void:
	var k: float = CharacterLook.AGE_SCALE[clampi(_age, 0, 4)]
	if framing == Framing.BUST:
		_cam.size = 1.0 * k
		_cam.position = Vector3(0, 1.36 * k, 3)
	else:
		_cam.size = 1.95
		_cam.position = Vector3(0, 0.88, 3)
	_cam.rotation = Vector3.ZERO
