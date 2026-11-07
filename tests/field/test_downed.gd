extends Node
## B-11: going down empties the bag (not in protect mode), equipped gear becomes lost gear,
## the next sortie to the same region can recover it once, another region drops it,
## companions are stranded.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const REGION := &"flooded_mall"
const OTHER_REGION := &"park"
const DOWN_POS := Vector3(3.0, 0.0, 4.0)

var _ok := true
var _stranded: Array = []
var _autosave_before := true
var _keep_bag_before: Variant


func run() -> bool:
	# Past the onboarding days (MonsterRules.EARLY_DENSITY, EarlyZone, FieldState.early_bag_kept).
	var day_before := GameState.day
	GameState.day = 9
	_ok = true
	_autosave_before = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	_keep_bag_before = Settings.get_value(&"keep_bag_on_down")
	EventBus.companion_stranded.connect(_on_stranded)

	_test_down_loses_bag_and_gear()
	_test_protect_mode_keeps_bag()
	await _test_recover_next_sortie_same_region()
	_test_not_recovered_is_gone()
	_test_other_region_is_gone()
	_test_strand_companion_direct()
	_test_save_round_trip()

	EventBus.companion_stranded.disconnect(_on_stranded)
	Settings.set_value(&"keep_bag_on_down", _keep_bag_before)
	SaveSystem.autosave_enabled = _autosave_before
	_reset()
	GameState.day = day_before
	return _ok


func _test_down_loses_bag_and_gear() -> void:
	var gear := _setup_sortie([&"res_fake_1", &"res_fake_2"])
	Settings.set_value(&"keep_bag_on_down", false)
	Bag.add_resource(&"scrap", 5)
	var pocket_id: int = Bag.entries(Bag.AREA_BAG)[0]["id"]
	Bag.add_resource(&"wood", 3)
	_expect(Bag.move(pocket_id, Vector2i.ZERO, false, Bag.AREA_POCKET), "scrap moved to the safe pocket")
	_stranded.clear()
	var p := _down_player()

	_expect(p.is_downed, "player is downed")
	_expect(Bag.count(&"scrap") == 5, "safe pocket kept")
	_expect(Bag.count(&"wood") == 0, "bag contents lost")
	_expect(Armory.list_equipped(Armory.PLAYER_ID).is_empty(), "nothing equipped after going down")
	for uid in gear:
		_expect(Armory.get_item(uid).owner == Armory.LOST_ID, "%s is lost gear" % uid)
	_expect(FieldState.lost_gear.size() == gear.size(), "one lost_gear entry per item")
	var e: Dictionary = FieldState.lost_gear[0]
	_expect(e["region_id"] == REGION and e["position"].is_equal_approx(DOWN_POS),
		"lost gear records region and down position")
	_expect(FieldState.down_count(REGION) == 1, "down counted for the region")
	_expect(_stranded == [[&"res_fake_1", REGION], [&"res_fake_2", REGION]], "both companions stranded")
	_expect(FieldState.companions.is_empty(), "no companions left after going down")
	var r := FieldState.down_result()
	_expect(r["gear"].size() == gear.size() and not r["bag_kept"], "down_result lists lost gear")
	_expect(r["bag"]["resources"].get(&"wood", 0) == 3, "down_result lists lost bag contents")
	_expect(r["stranded"] == [&"res_fake_1", &"res_fake_2"], "down_result lists stranded companions")
	p.free()


func _test_protect_mode_keeps_bag() -> void:
	var gear := _setup_sortie([])
	Settings.set_value(&"keep_bag_on_down", true)
	Bag.add_resource(&"wood", 3)
	var p := _down_player()
	_expect(Bag.count(&"wood") == 3, "protect mode keeps the bag")
	_expect(FieldState.lost_gear.size() == gear.size(), "protect mode still loses equipped gear")
	_expect(FieldState.down_result()["bag_kept"], "down_result says the bag was kept")
	Settings.set_value(&"keep_bag_on_down", false)
	p.free()


func _test_recover_next_sortie_same_region() -> void:
	var gear := _setup_sortie([])
	var p := _down_player()
	p.free()
	EventBus.sortie_ended.emit({})
	_expect(FieldState.lost_gear.size() == gear.size(), "lost gear survives the sortie it was dropped in")
	_expect(FieldState.recoverable_gear().is_empty(), "not recoverable before the next sortie")

	EventBus.sortie_started.emit({"region_id": REGION, "companions": []})
	var drops := FieldState.recoverable_gear()
	_expect(drops.size() == 1 and drops[0]["item_uids"].size() == gear.size(), "one drop with all the gear")
	_expect(FieldState.down_result().is_empty(), "down_result cleared on a new sortie")

	var spawner := LostGearSpawner.new()
	add_child(spawner)
	var points := spawner.get_children()
	_expect(points.size() == 1 and points[0].global_position.is_equal_approx(DOWN_POS),
		"spawner placed a recovery point at the down position")
	_expect(spawner.spawn_points().is_empty(), "spawner does not spawn the same drop twice")
	EventBus.sortie_started.emit({"region_id": REGION, "companions": []})
	_expect(points[0].is_queued_for_deletion(), "a new sortie removes the old recovery point")
	_expect(FieldState.recoverable_gear().is_empty(), "gear had its one chance and is gone")
	# Same spot again: going down where the last gear lay must still get a point.
	gear = _setup_sortie([])
	_down_player().free()
	EventBus.sortie_ended.emit({})
	EventBus.sortie_started.emit({"region_id": REGION, "companions": []})
	var fresh := spawner.get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_expect(fresh.size() == 1, "a second drop at the same spot gets its own point")

	var picker: Player = PLAYER_SCENE.instantiate()
	add_child(picker)
	picker.global_position = DOWN_POS + Vector3(0.5, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(picker.interact(), "player interact picks up the lost gear")
	for uid in gear:
		_expect(Armory.get_item(uid).owner == Armory.BAG_ID, "%s went into the bag" % uid)
	_expect(FieldState.lost_gear.is_empty(), "lost_gear empty after recovery")
	EventBus.sortie_ended.emit({})
	for uid in gear:
		_expect(Armory.has_item(uid), "%s still exists after the sortie" % uid)
	picker.free()
	spawner.free()


func _test_not_recovered_is_gone() -> void:
	var gear := _setup_sortie([])
	_down_player().free()
	EventBus.sortie_ended.emit({})
	EventBus.sortie_started.emit({"region_id": REGION, "companions": []})
	_expect(FieldState.recoverable_gear().size() == 1, "recoverable during the next sortie")
	EventBus.sortie_ended.emit({})
	_expect(FieldState.lost_gear.is_empty(), "not recovered in its one sortie: gone")
	for uid in gear:
		_expect(not Armory.has_item(uid), "%s deleted" % uid)


func _test_other_region_is_gone() -> void:
	var gear := _setup_sortie([])
	_down_player().free()
	EventBus.sortie_ended.emit({})
	EventBus.sortie_started.emit({"region_id": OTHER_REGION, "companions": []})
	_expect(FieldState.lost_gear.is_empty() and FieldState.recoverable_gear().is_empty(),
		"sortie to another region drops lost gear at once")
	for uid in gear:
		_expect(not Armory.has_item(uid), "%s deleted" % uid)


func _test_strand_companion_direct() -> void:
	_setup_sortie([&"res_fake_1"])
	_stranded.clear()
	FieldState.strand_companion(&"res_fake_1")
	_expect(_stranded == [[&"res_fake_1", REGION]], "strand_companion emits companion_stranded")
	_expect(FieldState.companions.is_empty(), "stranded companion leaves the party")


func _test_save_round_trip() -> void:
	_setup_sortie([&"res_fake_1"])
	_down_player().free()
	var saved := FieldState.save_data()
	var text := JSON.stringify(JSON.from_native(saved))
	FieldState.load_data({})
	_expect(FieldState.lost_gear.is_empty() and FieldState.down_count(REGION) == 0, "load_data({}) resets")
	FieldState.load_data(JSON.to_native(JSON.parse_string(text)))
	_expect(FieldState.save_data() == saved, "field save data survives JSON")
	_expect(FieldState.lost_gear[0]["position"] is Vector3, "position comes back as Vector3")


# --- Helpers ---

## Fresh state, a sortie to REGION, the player wearing a weapon, a helmet and a bag.
func _setup_sortie(companions: Array[StringName]) -> Array[StringName]:
	_reset()
	EventBus.sortie_started.emit({"region_id": REGION, "companions": companions})
	var gear: Array[StringName] = []
	for pair in [[&"pistol", Enums.EquipSlot.MAIN], [&"work_helmet", Enums.EquipSlot.HEAD],
			[&"school_bag", Enums.EquipSlot.BAG]]:
		var uid := Armory.create_item(pair[0])
		Armory.equip(Armory.PLAYER_ID, pair[1], uid)
		gear.append(uid)
	return gear


func _down_player() -> Player:
	var p: Player = PLAYER_SCENE.instantiate()
	add_child(p)
	p.global_position = DOWN_POS
	p.take_damage(p.health + 1.0)
	return p


func _reset() -> void:
	Armory.load_data({})
	Bag.load_data({})
	FieldState.load_data({})


func _on_stranded(resident_id: StringName, region_id: StringName) -> void:
	_stranded.append([resident_id, region_id])


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_downed: " + label)
