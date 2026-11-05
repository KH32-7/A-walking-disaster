extends RefCounted
## HudMinimap heading-up: map-space conversion, preview points turn with the heading, and in the
## real flooded mall the live marks (active exits) are collected around the player.

const TEST_SAVES := "user://test_hud_minimap_saves"


func run() -> bool:
	var ok := _check_math()
	ok = ok and await _check_live()
	return ok


func _check_math() -> bool:
	var r := HudMinimap.RANGE_M
	var ok := true
	# Facing north (bearing 0): a point ahead (-Z) is up, east (+X) is right.
	ok = ok and _near(HudMinimap.to_map(Vector3(0, 0, -r), 0.0), Vector2(0, -1), "ahead not up at bearing 0")
	ok = ok and _near(HudMinimap.to_map(Vector3(r, 0, 0), 0.0), Vector2(1, 0), "east not right at bearing 0")
	# Facing east (bearing 90): east is now up, north is left.
	ok = ok and _near(HudMinimap.to_map(Vector3(r, 0, 0), 90.0), Vector2(0, -1), "east not up at bearing 90")
	ok = ok and _near(HudMinimap.to_map(Vector3(0, 0, -r), 90.0), Vector2(-1, 0), "north not left at bearing 90")
	ok = ok and _expect(is_equal_approx(HudMinimap.bearing(Vector3(1, 0, 0)), 90.0), "bearing of +X is not 90")
	var mm := HudMinimap.new()
	mm.player_heading = 90.0
	mm.points = [{"pos": Vector2(1, 0), "kind": &"extract"}]
	var turned: Vector2 = mm._preview_points()[0].pos
	mm.free()
	return ok and _near(turned, Vector2(0, -1), "preview point east not turned to up")


func _check_live() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var backup := {}
	for key: StringName in SaveSystem._providers:
		backup[key] = SaveSystem._providers[key].save_data().duplicate(true)
	var old_dir := SaveSystem.save_dir
	var flow_before := GameState.flow_state
	SaveSystem.save_dir = TEST_SAVES
	GameState.flow_state = Enums.FlowState.TITLE
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	main.name = &"Main"
	tree.root.add_child(main)
	await tree.process_frame
	SceneRouter.start_new_game(0)
	SceneRouter.open_sortie_prep()
	SceneRouter.go_to_field({"region_id": &"flooded_mall", "companions": [], "gear": {}})
	# Wait for the loading screen (it hides the HUD) to go away.
	for i in 600:
		await tree.process_frame
		if i > 10 and UI.stack_ids().is_empty():
			break
	# The map turns after the player smoothly; give it time to settle.
	for i in 60:
		await tree.process_frame
	var mm: HudMinimap = UI.field_hud._minimap if UI.field_hud != null else null
	var ok := _expect(mm != null and mm._live, "minimap not live in the field")
	if ok:
		var exits: Array = mm._live_points.filter(func(p: Dictionary) -> bool: return p.kind == &"extract")
		ok = _expect(not exits.is_empty(), "no extraction marks on the minimap")
		var p := tree.get_first_node_in_group(&"player") as Node3D
		ok = ok and _expect(absf(angle_difference(deg_to_rad(mm.heading()),
			deg_to_rad(HudMinimap.bearing(p.call(&"facing"))))) < 0.2, "heading does not follow the player")
		# Next to the bus depot its landmark name shows on the minimap.
		p.global_position = Vector3(21.0, p.global_position.y, -80.0)
		for i in 5:
			await tree.process_frame
		var names: Array = mm._live_names.map(func(n: Dictionary) -> String: return n.text)
		ok = ok and _expect("버스 차고지" in names, "landmark name near the player not on the minimap: %s" % [names])

	UI.close_all()
	tree.root.remove_child(main)
	main.free()
	for key: StringName in backup:
		SaveSystem._providers[key].load_data(backup[key])
	GameState.flow_state = flow_before
	UI._on_flow_state_changed(flow_before)
	var dir := DirAccess.open(TEST_SAVES)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	SaveSystem.save_dir = old_dir
	return ok


func _near(a: Vector2, b: Vector2, message: String) -> bool:
	return _expect(a.distance_to(b) < 0.001, "%s (%s vs %s)" % [message, a, b])


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_hud_minimap: ", message)
	return cond
