extends Node
## D-06 재설계 preview: ②놓기 / ③짓기 on the real base map (instances base_school.tscn, saves nothing).
## Fake camp state, then starts placing a 벌목장 at the first valid spot near trees.
##   -- --step=2 (placing, cursor on a valid spot) | --step=3 (placed, site card) | --step=2bad (blocked spot)
##   --shot=<png path> saves a screenshot after 1.5 s and quits.

const BASE := "res://levels/base/base_school/base_school.tscn"

var _step := "2"
var _shot := ""
var _t := 0.0
var _base: Node
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			_step = a.trim_prefix("--step=")
		if a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
	if Colony.population() == 0:
		for p: Dictionary in DemoProfiles.PROFILES:
			Colony.add_resident(p)
	Economy.set_cap_bonus(300)
	Economy.apply({&"wood": 34, &"stone": 12, &"scrap": 8, &"food": 21, &"parts": 3, &"cloth": 5, &"seeds": 2})
	Colony.cleared_zones[&"playground"] = true
	GameState.set_flow_state(Enums.FlowState.BASE_MORNING)  # closes the title flow screen
	UI.close_all()
	_base = (load(BASE) as PackedScene).instantiate()
	add_child(_base)
	UI.show_base_hud(true)
	_go.call_deferred()


func _go() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var mode: BuildMode = _base.get(&"build_mode")
	var grid: BaseGrid = _base.get(&"grid")
	var spot := _find_spot(grid, &"lumber_yard", _step != "2bad")
	if spot.is_empty():
		push_warning("preview_build_flow: no spot found")
		return
	var player: Node3D = _base.get(&"player")
	var center := grid.footprint_center(spot["zone_id"], spot["cell"], Vector2i(2, 2))
	player.global_position = center + Vector3(-3, 0, 3)
	await get_tree().create_timer(0.4).timeout
	UI.build_requested.emit(&"lumber_yard")
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		Input.warp_mouse(cam.unproject_position(center))
	mode.preview_cell(spot["zone_id"], spot["cell"])
	if _step == "3":
		mode.confirm()


## First cell where the building fits (ok = true) or, for "2bad", one that overlaps a tree-less edge.
func _find_spot(grid: BaseGrid, def_id: StringName, want_ok: bool) -> Dictionary:
	var fallback := {}
	for zone_id: StringName in grid.areas:
		if not grid.is_zone_cleared(zone_id):
			continue
		var area: BuildArea = grid.areas[zone_id]
		for y in area.size_cells.y:
			for x in area.size_cells.x:
				var r := grid.check(def_id, zone_id, Vector2i(x, y))
				if r["ok"] == want_ok:
					if want_ok:
						return {"zone_id": zone_id, "cell": Vector2i(x, y)}
					if fallback.is_empty() and "나무" in ", ".join(PackedStringArray(r["reasons"])):
						fallback = {"zone_id": zone_id, "cell": Vector2i(x, y)}
	return fallback


func _process(delta: float) -> void:
	_t += delta
	if _shot != "" and not _done and _t > 1.6:
		_done = true
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
