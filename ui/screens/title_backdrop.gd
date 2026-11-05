class_name TitleBackdrop
extends Control
## Live in-game backdrop behind the title screen: the flooded-mall shore (water about a third of the
## view) seen through the field camera, which drifts slowly down the screen, fades to black and
## starts over. No player, monsters, loot or managers: only the map.
## The level loads on a thread; until it is ready (and in headless runs, where it is skipped) the
## title's own flat background shows. Its own World3D, so nothing leaks into the game world.

const LEVEL_PATH := "res://levels/field/flooded_mall/flooded_mall.tscn"
## Level children that run gameplay; removed before the level enters the tree.
const STRIP := [^"MonsterSpawner", ^"RoamingSpawner", ^"BossSpawner", ^"LootSpawner", ^"ExtractionManager",
	^"LostGearSpawner", ^"RescueManager", ^"CompanionManager", ^"HiddenRouteManager"]
## Camera focus path (world, metres). Screen-down for the field camera's start yaw is +x +z.
const PAN_FROM := Vector3(66.0, 0.0, 6.0)
const PAN_TO := Vector3(74.0, 0.0, 14.0)
const PAN_SEC := 24.0
const FADE_SEC := 1.6
const ZOOM_STEPS := 1  ## from the field camera's start zoom: +1 = farthest
## Left side darkened for the menu: alpha at the left edge, fully clear at this share of the width.
const SHADE_ALPHA := 0.85
const SHADE_END := 0.6

var _view: SubViewportContainer
var _pivot: Node3D
var _camera: FieldCamera
var _loading := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not will_show():
		return
	# Black from the first frame; the map fades in over it once loaded (no flash of another background).
	var base := ColorRect.new()
	base.color = Color.BLACK
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	_loading = ResourceLoader.load_threaded_request(LEVEL_PATH) == OK


## False in headless runs (tests, CI) or without the level: the title then keeps its flat background.
static func will_show() -> bool:
	return DisplayServer.get_name() != "headless" and ResourceLoader.exists(LEVEL_PATH)


func _process(_delta: float) -> void:
	if not _loading:
		return
	match ResourceLoader.load_threaded_get_status(LEVEL_PATH):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return
		ResourceLoader.THREAD_LOAD_LOADED:
			_loading = false
			_build(ResourceLoader.load_threaded_get(LEVEL_PATH) as PackedScene)
		_:
			_loading = false


func _build(packed: PackedScene) -> void:
	if packed == null:
		return
	var level := packed.instantiate() as Node3D
	if "spawn_player" in level:
		level.spawn_player = false
	for path: NodePath in STRIP:
		var n := level.get_node_or_null(path)
		if n != null:
			level.remove_child(n)
			n.free()

	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.modulate.a = 0.0
	add_child(_view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.gui_disable_input = true
	vp.audio_listener_enable_3d = false
	_view.add_child(vp)

	_pivot = Node3D.new()
	_pivot.position = PAN_FROM
	level.add_child(_pivot)
	_camera = level.get_node_or_null(^"FieldCamera") as FieldCamera
	vp.add_child(level)
	if _camera != null:
		_camera.set_process_input(false)
		_camera.set_process_unhandled_input(false)
		_camera.target = _pivot
		_camera.zoom_step(ZOOM_STEPS)
		_camera.snap()

	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, SHADE_ALPHA))
	grad.set_color(1, Color(0, 0, 0, 0))
	grad.set_offset(1, SHADE_END)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 4
	shade.texture = tex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_loop()


func _loop() -> void:
	var tw := create_tween().set_loops()
	tw.tween_callback(_restart)
	tw.set_parallel(true)
	tw.tween_property(_view, ^"modulate:a", 1.0, FADE_SEC)
	tw.tween_property(_pivot, ^"position", PAN_TO, PAN_SEC).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_view, ^"modulate:a", 0.0, FADE_SEC).set_delay(PAN_SEC - FADE_SEC)
	tw.set_parallel(false)


func _restart() -> void:
	_pivot.position = PAN_FROM
	if _camera != null:
		_camera.snap()
