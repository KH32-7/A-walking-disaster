class_name BuildingViews
extends Node3D
## Look of every Colony building placed on this base map (C-03). Redraws on Colony.buildings_changed.
## Completed buildings are made of American Suburb models (BuildingModels table); without the private
## assets/ submodule they stay grey boxes. Construction sites are low, see-through boxes with their
## progress; damaged buildings get a "(파손)" label. A view node is in group VIEW_GROUP with metadata
## building_uid / def_id (DefenseBattle and Lane D find buildings by these).

const Models := preload("res://base/building/building_models.gd")
const VIEW_GROUP := &"base_building_view"
const HEIGHT_BY_CATEGORY := {
	BuildingDef.Category.HOUSING: 2.4, BuildingDef.Category.PRODUCTION: 2.0,
	BuildingDef.Category.INCLUSION: 0.6, BuildingDef.Category.DEFENSE: 1.6,
}
const DEFAULT_HEIGHT := 2.6
const SITE_HEIGHT := 0.4
const MODEL_LABEL_HEIGHT := 4.5
const LABEL_FONT := 40

var grid: BaseGrid

var _materials := {}


func _ready() -> void:
	Colony.buildings_changed.connect(refresh)
	Colony.build_progress_changed.connect(_on_build_progress)
	refresh.call_deferred()


## Live construction: only the site's label changes.
func _on_build_progress(uid: StringName) -> void:
	var root := get_node_or_null(NodePath(String(uid)))
	var b: Dictionary = Colony.buildings.get(uid, {})
	if root == null or b.is_empty():
		return
	var label := root.get_node_or_null(^"Label") as Label3D
	if label != null:
		label.text = _label_text(BaseDB.get_building(b["def_id"]), b, b["completed"])


func refresh() -> void:
	if grid == null or not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
	for uid: StringName in Colony.buildings:
		var b: Dictionary = Colony.buildings[uid]
		if not grid.areas.has(b["zone_id"]):
			continue  # prebuilt rooms, attachments, or other maps
		var def := BaseDB.get_building(b["def_id"])
		if def == null or def.size == Vector2i.ZERO:
			continue
		add_child(_make_view(uid, b, def))


func view_count() -> int:
	var n := 0
	for child in get_children():
		if not child.is_queued_for_deletion():
			n += 1
	return n


## The circle of light a lamp, fire or light tower gives at night (BuildingModels.NIGHT_LIGHTS).
## On only while it is night at the base; ForestDressing switches the whole group.
func _night_light(def_id: StringName) -> OmniLight3D:
	var spec: Dictionary = Models.NIGHT_LIGHTS[def_id]
	var light := OmniLight3D.new()
	light.name = "NightLight"
	light.light_color = spec["color"]
	light.light_energy = spec["energy"]
	light.omni_range = spec["range"]
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.position.y = spec["height"]
	light.set_meta(&"energy", spec["energy"])
	light.set_meta(&"flicker", spec.get("flicker", false))
	light.add_to_group(Models.NIGHT_LIGHT_GROUP)
	light.visible = GameState.phase == Enums.Phase.NIGHT
	return light


func _make_view(uid: StringName, b: Dictionary, def: BuildingDef) -> Node3D:
	var size := BaseGrid.footprint(def, int(b["rotation"]))
	var origin := Vector2i(b["cell"][0], b["cell"][1])
	var center := grid.footprint_center(b["zone_id"], origin, size)
	var done: bool = b["completed"]
	var height: float = HEIGHT_BY_CATEGORY.get(def.category, DEFAULT_HEIGHT) if done else SITE_HEIGHT
	var footprint_m := Vector3(size.x, 0.0, size.y) * ColonyMarker.CELL_SIZE
	var root := Node3D.new()
	root.name = String(uid)
	root.add_to_group(VIEW_GROUP)
	root.set_meta(&"building_uid", uid)
	root.set_meta(&"def_id", def.id)
	root.position = center - global_position
	if done and Models.NIGHT_LIGHTS.has(def.id):
		root.add_child(_night_light(def.id))
	if done and Models.has_assets() and Models.MODELS.has(def.id):
		var model := Models.build(def.id, size)
		model.name = "Model"
		model.position.y = 0.05
		if b.get("damaged", false):
			model.rotation_degrees.z = 3.0  # a slight lean reads as damage until D adds a damaged look
		root.add_child(model)
		root.add_child(_label(def, b, done, MODEL_LABEL_HEIGHT))
		return root
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	# A little smaller than the footprint so neighbours read as separate buildings.
	mesh.size = Vector3(footprint_m.x - 0.2, height, footprint_m.z - 0.2)
	box.mesh = mesh
	box.position.y = height * 0.5
	box.material_override = _material(def.category, done)
	root.add_child(box)
	root.add_child(_label(def, b, done, height + 0.8))
	return root


func _label(def: BuildingDef, b: Dictionary, done: bool, y: float) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = LABEL_FONT
	label.outline_size = 10
	label.pixel_size = 0.01
	label.position.y = y
	label.name = "Label"
	label.text = _label_text(def, b, done)
	return label


func _label_text(def: BuildingDef, b: Dictionary, done: bool) -> String:
	var state := ""
	if not done:
		# D-06 재설계 ③짓기: 현장은 진행과 일손을 함께 보여 준다 (일손 0이면 아무도 짓지 않음).
		var workers := (b["workers"] as Array).size()
		state = "\n건설 현장 %d/%d / %s" % [int(b["progress"]), def.build_work_needed(),
			"일손 %d명" % workers if workers > 0 else "일손을 보내야 지어져요"]
	elif b.get("damaged", false):
		state = "\n(파손)"
	return def.display_name + state


func _material(category: int, done: bool) -> StandardMaterial3D:
	var key := "%d_%s" % [category, done]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	var hue := fmod(category * 0.13, 1.0)
	m.albedo_color = Color.from_hsv(hue, 0.25, 0.85)
	if not done:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 0.45
	_materials[key] = m
	return m
