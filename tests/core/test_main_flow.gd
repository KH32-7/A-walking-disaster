extends RefCounted
## main.tscn integration (A-05): the real base and field scenes load under World, the flow screens
## open, and the stand-in prompts (core/flow_prompts.gd) show on TITLE / BASE_STAY / NIGHT.
## Two sortie days and one stay day with the real scenes. Uses a throwaway save location.

const TEST_SAVES := "user://test_main_flow_saves"
const REGION := &"flooded_mall"

var _tree: SceneTree
var _main: Node


func run() -> bool:
	_tree = Engine.get_main_loop() as SceneTree
	var backup := {}
	for key: StringName in SaveSystem._providers:
		backup[key] = SaveSystem._providers[key].save_data().duplicate(true)
	var old_dir := SaveSystem.save_dir
	var old_slot := SaveSystem.current_slot
	var flow_before := GameState.flow_state
	SaveSystem.save_dir = TEST_SAVES
	_wipe()
	GameState.flow_state = Enums.FlowState.TITLE

	_main = (load("res://main.tscn") as PackedScene).instantiate()
	_main.name = &"Main"
	_tree.root.add_child(_main)
	await _frames(3)
	var ok := _expect(_prompt_count() > 0, "title prompt not shown")
	ok = ok and _expect(SceneRouter.start_new_game(0), "start_new_game refused")
	for day in 2:
		ok = ok and await _sortie_day()
	ok = ok and await _stay_day()

	UI.close_all()
	_tree.root.remove_child(_main)
	_main.free()
	_tree.paused = false
	for key: StringName in backup:
		SaveSystem._providers[key].load_data(backup[key])
	GameState.flow_state = flow_before
	UI._on_flow_state_changed(flow_before)
	_wipe()
	SaveSystem.save_dir = old_dir
	SaveSystem.current_slot = old_slot
	return ok


func _sortie_day() -> bool:
	await _frames(3)
	var ok := _expect(_world_name() == &"BaseSchool", "morning world is %s" % _world_name())
	ok = ok and _expect(SceneRouter.open_sortie_prep(), "open_sortie_prep refused")
	await _frames(2)
	ok = ok and _expect(UI.is_open(&"sortie_prep"), "sortie prep screen not open")
	ok = ok and _expect(SceneRouter.go_to_field({"region_id": REGION, "companions": [], "gear": {}}), "go_to_field refused")
	await _frames(10)
	ok = ok and _expect(_world_name() == &"FloodedMall", "field world is %s" % _world_name())
	ok = ok and _expect(_tree.get_nodes_in_group(&"player").size() == 1, "field should have one player")
	EventBus.extraction_completed.emit(&"test")
	await _frames(3)
	ok = ok and _expect(GameState.flow_state == Enums.FlowState.RESULT, "not in RESULT after extraction")
	ok = ok and _expect(UI.is_open(&"result"), "result screen not open")
	ok = ok and _expect(_world_name() == &"BaseSchool", "result world is %s" % _world_name())
	ok = ok and _expect(SceneRouter.finish_result(), "finish_result refused")
	await _frames(2)
	ok = ok and _expect(UI.is_open(&"evening"), "evening screen not open")
	ok = ok and _expect(SceneRouter.confirm_evening(), "confirm_evening refused")
	await _frames(2)
	ok = ok and _expect(GameState.flow_state == Enums.FlowState.NIGHT and _prompt_count() > 0, "night prompt not shown")
	var day := GameState.day
	ok = ok and _expect(SceneRouter.finish_night(), "finish_night refused")
	await _frames(2)
	return ok and _expect(GameState.day == day + 1 and _prompt_count() == 0, "next morning not reached cleanly")


func _stay_day() -> bool:
	var ok := _expect(SceneRouter.stay_at_base(), "stay_at_base refused")
	await _frames(3)
	# A stay day raid (Colony) may already have moved on to the evening.
	if GameState.flow_state == Enums.FlowState.BASE_STAY:
		ok = ok and _expect(_prompt_count() > 0, "stay prompt not shown")
		ok = ok and _expect(SceneRouter.end_stay(), "end_stay refused")
	await _frames(2)
	return ok and _expect(GameState.flow_state == Enums.FlowState.EVENING, "stay day did not reach the evening")


func _world_name() -> StringName:
	var world := _main.get_node(^"World")
	return world.get_child(0).name if world.get_child_count() > 0 else &""


func _prompt_count() -> int:
	var root := _main.get_node(^"FlowPrompts/Root")
	var n := 0
	for c in root.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame


func _wipe() -> void:
	var dir := DirAccess.open(TEST_SAVES)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_main_flow: ", message)
	return cond
