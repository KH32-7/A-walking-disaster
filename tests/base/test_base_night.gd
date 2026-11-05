extends Node
## Base night (user request 2026-11-06): by day the base keeps its look and building lights are off;
## at GameState NIGHT the base goes darker and lamps, fires and light towers
## (BuildingModels.NIGHT_LIGHTS) light a circle around them. Buildings without a light give none.

const BASE := "res://levels/base/base_school/base_school.tscn"
const Models := preload("res://base/building/building_models.gd")


func run() -> bool:
	var snap := {"economy": JSON.from_native(Economy.save_data()), "colony": JSON.from_native(Colony.save_data())}
	var phase_before := GameState.phase
	GameState.set_phase(Enums.Phase.MORNING)
	Economy.load_data({})
	Colony.load_data({})
	var base := (load(BASE) as PackedScene).instantiate()
	add_child(base)
	await _frames(3)
	var fire := Colony.place_building(&"bonfire", Vector2i(2, 1), 0, &"front_yard", false)
	Colony.complete_building(fire)
	var bed := Colony.place_building(&"bed", Vector2i(8, 1), 0, &"front_yard", false)
	Colony.complete_building(bed)
	base.building_views.refresh()
	await _frames(2)
	var ok := true
	var fire_view := _view(base.building_views, fire)
	var bed_view := _view(base.building_views, bed)
	ok = _expect(fire_view != null and bed_view != null, "both buildings are drawn") and ok
	var light := fire_view.get_node_or_null(^"NightLight") as OmniLight3D if fire_view != null else null
	ok = _expect(light != null, "a bonfire carries a night light") and ok
	ok = _expect(bed_view == null or bed_view.get_node_or_null(^"NightLight") == null, "a bed gives no light") and ok
	ok = _expect(light == null or not light.visible, "by day the light is off") and ok
	var dressing := base.find_child("Dressing", false, false)
	var sun := dressing.get_node_or_null(^"Sun") as DirectionalLight3D if dressing != null else null
	var day_sun := sun.light_energy if sun != null else 0.0
	dressing.set(&"night_fade_sec", 0.0)
	GameState.set_phase(Enums.Phase.NIGHT)
	await _frames(3)
	ok = _expect(light == null or light.visible, "at night the bonfire lights up") and ok
	if sun != null:
		ok = _expect(sun.light_energy < day_sun and sun.light_energy > 0.2, "the base is darker at night, not black") and ok
	GameState.set_phase(Enums.Phase.MORNING)
	await _frames(3)
	ok = _expect(light == null or not light.visible, "the light goes off again in the morning") and ok
	if sun != null:
		ok = _expect(is_equal_approx(sun.light_energy, day_sun), "the day look comes back") and ok
	base.queue_free()
	await _frames(2)
	GameState.set_phase(phase_before)
	Economy.load_data(JSON.to_native(snap.economy))
	Colony.load_data(JSON.to_native(snap.colony))
	return ok


## The live view of building `uid` (refresh() frees the old ones at the end of the frame).
func _view(views: Node, uid: StringName) -> Node3D:
	for child in views.get_children():
		if not child.is_queued_for_deletion() and child.get_meta(&"building_uid", &"") == uid:
			return child as Node3D
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_base_night: " + message)
	return cond
