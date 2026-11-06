class_name ResidentPortrait
extends PanelContainer
## Resident portrait (D-13): the resident's own model — the same ResidentModel (City People assets) the
## base and the field show — rendered alone in a SubViewport with its own world (사용자 요청
## 2026-11-06: 화면마다 주민 모델이 아니라 다른 모델이 나옴). Without the assets/ submodule, or for
## set_look() previews (외형 꾸미기), the CharacterLook body is drawn instead. Owner: Lane D. Used by the dialog, gift, night event and
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
var _model: ResidentModel
## Height of the shown ResidentModel (m), 0 = the CharacterLook is shown.
var _model_h := 0.0


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
	if _show_model(r):
		return
	set_look(Colony.appearance_for_look(resident_id), int(r.get("age_stage", 3)))


## The resident's ResidentModel. False when there is no model for them (no assets): the look stays.
func _show_model(r: Dictionary) -> bool:
	if r.is_empty():
		return false
	if _model == null:
		_model = ResidentModel.new()
		_model.body_scale = 1.0  # the portrait camera frames the real size (ResidentModel.WORLD_SCALE is for the world)
		_model.fallback = NodePath("")
		# ResidentModel bodies face -Z; turn to the camera (+Z) and a little to the side.
		_model.rotation_degrees.y = 180.0 + 18.0
		_vp.add_child(_model)
	if not _model.show_resident(r):
		_model.visible = false
		return false
	_model.visible = true
	_look.visible = false
	_model_h = 1.75 * ResidentModel.scale_for(r)
	_frame()
	return true


func set_look(appearance: Dictionary, age_stage := 3) -> void:
	if _model != null:
		_model.visible = false
	_model_h = 0.0
	_look.visible = true
	_age = age_stage
	_look.age_stage = age_stage
	_look.apply(appearance)
	_frame()


func _frame() -> void:
	if _model_h > 0.0:
		var h := _model_h
		if framing == Framing.BUST:
			_cam.size = h * 0.6
			_cam.position = Vector3(0, h * 0.8, 3)
		else:
			_cam.size = h * 1.12
			_cam.position = Vector3(0, h * 0.5, 3)
		_cam.rotation = Vector3.ZERO
		return
	var k: float = CharacterLook.AGE_SCALE[clampi(_age, 0, 4)]
	if framing == Framing.BUST:
		_cam.size = 1.0 * k
		_cam.position = Vector3(0, 1.36 * k, 3)
	else:
		_cam.size = 1.95
		_cam.position = Vector3(0, 0.88, 3)
	_cam.rotation = Vector3.ZERO
