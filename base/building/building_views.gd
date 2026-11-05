class_name BuildingViews
extends Node3D
## Greybox look of every Colony building placed on this base map (C-03). Redraws on
## Colony.buildings_changed. Construction sites are low, see-through boxes with their progress;
## damaged buildings get a "(파손)" label. Real models are Lane D's: a view node is in group
## VIEW_GROUP with metadata building_uid / def_id so D can put a model on top or replace it.

const VIEW_GROUP := &"base_building_view"
const HEIGHT_BY_CATEGORY := {
	BuildingDef.Category.HOUSING: 2.4, BuildingDef.Category.PRODUCTION: 2.0,
	BuildingDef.Category.INCLUSION: 0.6, BuildingDef.Category.DEFENSE: 1.6,
}
const DEFAULT_HEIGHT := 2.6
const SITE_HEIGHT := 0.4
const LABEL_FONT := 40

var grid: BaseGrid

var _materials := {}


func _ready() -> void:
	Colony.buildings_changed.connect(refresh)
	refresh.call_deferred()


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
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	# A little smaller than the footprint so neighbours read as separate buildings.
	mesh.size = Vector3(footprint_m.x - 0.2, height, footprint_m.z - 0.2)
	box.mesh = mesh
	box.position.y = height * 0.5
	box.material_override = _material(def.category, done)
	root.add_child(box)
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = LABEL_FONT
	label.outline_size = 10
	label.pixel_size = 0.01
	label.position.y = height + 0.8
	var state := ""
	if not done:
		state = "\n건설 중 %d/%d" % [int(b["progress"]), def.build_work_needed()]
	elif b.get("damaged", false):
		state = "\n(파손)"
	label.text = def.display_name + state
	root.add_child(label)
	return root


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
