class_name BuildingThumbs
extends Node
## Picture of each building made from its real model (Lane C BuildingModels, American Suburb pack).
## Owner: Lane D (D-06 재설계). One hidden SubViewport renders the queued buildings one at a time,
## quarter view like the base camera, and keeps the image. Cards show BuildingArt until the picture
## is ready, and keep it when there is no picture (no assets/ submodule, headless, no model).
##
##   BuildingThumbs.show_on(holder: Control, def_id, fallback_art)   card / detail picture

const Models := preload("res://base/building/building_models.gd")
const THUMB_SIZE := Vector2i(320, 240)
## Camera direction: from the front right and above, like the base map camera.
const VIEW_DIR := Vector3(1.0, 1.05, 1.0)

static var _cache := {}  # def_id -> ImageTexture (or null = tried, nothing)
static var _inst: BuildingThumbs

var _queue: Array[StringName] = []
var _waiting := {}  # def_id -> Array[Callable]
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _busy: StringName = &""
var _frames := 0


## Puts the model picture into `holder` (full rect) when it is ready; `fallback` is hidden then.
static func show_on(holder: Control, def_id: StringName, fallback: Control) -> void:
	if not can_render():
		return
	var tex: Variant = _cache.get(def_id, false)
	if tex is Texture2D:
		_attach(holder, tex, fallback)
		return
	if tex == null:
		return  # tried before: no model
	# Capture ids, not the nodes: the card may be freed (screen closed) before the picture is ready.
	var holder_id := holder.get_instance_id()
	var fallback_id := fallback.get_instance_id() if fallback != null else 0
	_instance().request(def_id, func(t: Texture2D) -> void:
		var h := instance_from_id(holder_id) as Control
		var f := instance_from_id(fallback_id) as Control if fallback_id != 0 else null
		if h != null and is_instance_valid(h) and not h.is_queued_for_deletion() and t != null:
			_attach(h, t, f if f != null and is_instance_valid(f) else null))


## Models exist and the renderer draws (not headless / dummy).
static func can_render() -> bool:
	return DisplayServer.get_name() != "headless" and Models.has_assets()


static func _attach(holder: Control, tex: Texture2D, fallback: Control) -> void:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if fallback != null:
		tr.offset_top = fallback.offset_top
		tr.offset_bottom = fallback.offset_bottom
		fallback.visible = false
		if fallback is BuildingArt and (fallback as BuildingArt).dim:
			tr.modulate = Color(0.55, 0.55, 0.55, 0.8)
		holder.add_child(tr)
		holder.move_child(tr, fallback.get_index())
	else:
		holder.add_child(tr)


static func _instance() -> BuildingThumbs:
	if not is_instance_valid(_inst):
		_inst = BuildingThumbs.new()
		_inst.name = &"BuildingThumbs"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_inst)
	return _inst


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus pause the tree
	_vp = SubViewport.new()
	_vp.size = THUMB_SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d9dccf")
	env.environment.ambient_light_energy = 0.75
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func request(def_id: StringName, cb: Callable) -> void:
	if not _waiting.has(def_id):
		_waiting[def_id] = []
		_queue.append(def_id)
	(_waiting[def_id] as Array).append(cb)


func _process(_delta: float) -> void:
	if _busy != &"":
		_frames += 1
		if _frames < 3:
			return
		var img := _vp.get_texture().get_image()
		var tex: Texture2D = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
		_cache[_busy] = tex
		for cb: Callable in _waiting.get(_busy, []):
			if cb.is_valid():
				cb.call(tex)
		_waiting.erase(_busy)
		_busy = &""
		for c in _stage.get_children():
			c.queue_free()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _queue.is_empty():
		return
	var id: StringName = _queue.pop_front()
	var def := BaseDB.get_building(id)
	if def == null or not Models.MODELS.has(id):
		_cache[id] = null
		_waiting.erase(id)
		return
	var size: Vector2i = Models.SIZE_OVERRIDE.get(id, def.size)
	size = Vector2i(maxi(size.x, 1), maxi(size.y, 1))
	var model := Models.build(id, size)
	_stage.add_child(model)
	var box := _aabb(model)
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 1.0)
	_cam.size = radius * 1.9
	_cam.position = center + VIEW_DIR.normalized() * (radius * 4.0)
	_cam.look_at(center, Vector3.UP)
	_busy = id
	_frames = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b := mi.global_transform * mi.mesh.get_aabb() if mi.is_inside_tree() else mi.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out if not first else AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
