extends Node3D
## B-11 sandbox: go down, lose the bag and gear, come back next sortie and pick it up.
## Run alone (F6). Keys:
##   K  go down here (take lethal damage)
##   N  next sortie, same region (lost gear point appears where you went down)
##   B  next sortie, another region (lost gear disappears)
##   P  toggle protect mode (Settings keep_bag_on_down)
##   F  pick up the lost gear point (normal interact)
## Autosave is off while this scene runs so it does not write save slots; protect mode is
## restored on exit.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const REGION := &"flooded_mall"
const OTHER_REGION := &"park"
const FAKE_COMPANIONS: Array[StringName] = [&"res_fake_companion"]
## Equipped into empty slots at every sortie start, so there is always something to lose.
const LOADOUT := {
	Enums.EquipSlot.MAIN: &"pistol",
	Enums.EquipSlot.HEAD: &"work_helmet",
	Enums.EquipSlot.BAG: &"school_bag",
}
const BAG_RESOURCES := {&"wood": 4, &"scrap": 6}

@onready var _camera: Camera3D = $FieldSandbox/Camera3D
@onready var _spawn: Marker3D = $SpawnPoint
@onready var _label: Label = $DebugLayer/DownedLabel

var _player: Player
var _camera_offset := Vector3.ZERO
var _log: PackedStringArray = []
var _autosave_before := true
var _keep_bag_before: Variant


func _ready() -> void:
	_autosave_before = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	_keep_bag_before = Settings.get_value(&"keep_bag_on_down")
	EventBus.companion_stranded.connect(_on_stranded)
	EventBus.player_downed.connect(_on_downed)
	_camera_offset = _camera.global_position - _spawn.global_position
	_start_sortie(REGION)


func _exit_tree() -> void:
	SaveSystem.autosave_enabled = _autosave_before
	Settings.set_value(&"keep_bag_on_down", _keep_bag_before)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_K:
			if not _player.is_downed:
				_player.take_damage(_player.health + 1.0)
		KEY_N:
			_next_sortie(REGION)
		KEY_B:
			_next_sortie(OTHER_REGION)
		KEY_P:
			Settings.set_value(&"keep_bag_on_down", not Settings.get_value(&"keep_bag_on_down"))


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + _camera_offset
	var lines := PackedStringArray([
		"K: 쓰러지기 / N: 같은 지역 다음 출격 / B: 다른 지역 출격 / P: 보호 모드 / F: 줍기",
		"지역: %s / 보호 모드(가방 유지): %s / 이 지역 쓰러짐: %d" % [
			FieldState.region_id, Settings.get_value(&"keep_bag_on_down"),
			FieldState.down_count(FieldState.region_id)],
		"장착: %s" % _defs(Armory.list_equipped(Armory.PLAYER_ID).values()),
		"가방: %s" % _bag_summary(),
		"유실물: %d개 / 이번 출격 회수 가능: %d곳" % [
			FieldState.lost_gear.size(), FieldState.recoverable_gear().size()],
	])
	lines.append_array(_log)
	_label.text = "\n".join(lines)


## Simulates A-05: end the sortie, then start a new one.
func _next_sortie(region: StringName) -> void:
	EventBus.sortie_ended.emit({})
	_start_sortie(region)


func _start_sortie(region: StringName) -> void:
	if _player:
		_player.free()
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = _spawn.global_position
	for slot: Enums.EquipSlot in LOADOUT:
		if Armory.get_equipped(Armory.PLAYER_ID, slot) == &"":
			Armory.equip(Armory.PLAYER_ID, slot, Armory.create_item(LOADOUT[slot]))
	for id: StringName in BAG_RESOURCES:
		Bag.add_resource(id, BAG_RESOURCES[id])
	EventBus.sortie_started.emit({"region_id": region, "companions": FAKE_COMPANIONS})
	for point in $LostGearSpawner.get_children():
		if point is LostGearPoint and not point.recovered.is_connected(_on_recovered):
			point.recovered.connect(_on_recovered)
	_add_log("출격 시작: %s" % region)


func _on_downed() -> void:
	var r := FieldState.down_result()
	_add_log("쓰러짐. 유실물 %s / 잃은 가방 %s / 가방 유지 %s" % [
		_defs(r["gear"]), r["bag"]["resources"], r["bag_kept"]])


func _on_stranded(resident_id: StringName, region_id: StringName) -> void:
	_add_log("고립: %s (%s)" % [resident_id, region_id])


func _on_recovered(item_uids: Array[StringName]) -> void:
	_add_log("회수: %s" % _defs(item_uids))


func _add_log(text: String) -> void:
	print("[B-11] ", text)
	_log.append(text)
	if _log.size() > 8:
		_log.remove_at(0)


func _defs(uids: Array) -> String:
	var names := PackedStringArray()
	for uid in uids:
		var item := Armory.get_item(uid)
		names.append(String(item.def_id) if item else String(uid))
	return ", ".join(names)


func _bag_summary() -> String:
	var parts := PackedStringArray()
	for e: Dictionary in Bag.entries():
		var area := "주머니" if e["area"] == Bag.AREA_POCKET else "가방"
		var label := String(Armory.get_item(e["ref"]).def_id) if e["kind"] == Bag.KIND_ITEM \
			else "%s x%d" % [e["ref"], e["amount"]]
		parts.append("%s(%s)" % [label, area])
	return ", ".join(parts)
