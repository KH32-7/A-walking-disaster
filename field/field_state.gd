extends Node
## Autoload `FieldState`. Owner: Lane B.
## Persistent field-side state that survives between sorties: lost gear, region
## unlocks, boss respawn timers, the current sortie's runtime info.
## Also handles the player going down (B-11): bag loss, lost gear, stranded companions.
## Design reference: docs/design/02-field.md "고립과 유실물", 01-flow-time.md "실패 처리"

## [{"item_uid": StringName, "region_id": StringName, "position": Vector3, "offered": bool}]
## One entry per item. "offered" = its one recovery sortie has started (set by sortie_started).
var lost_gear: Array = []
## region_id -> day the boss respawns
var boss_respawn_day: Dictionary = {}
## region_id -> times the player went down there (A-14 radio: "같은 지역에서 3번 쓰러짐").
var downs_by_region: Dictionary = {}
## Current sortie, from EventBus.sortie_started. Saved so a suspended sortie keeps them.
var region_id: StringName = &""
## Companions still with the player this sortie (stranded ones are removed).
var companions: Array[StringName] = []

var _down_result: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_provider(&"field", self)
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.sortie_ended.connect(_on_sortie_ended)
	EventBus.player_downed.connect(_on_player_downed)


## True while the player is inside a field region.
func in_sortie() -> bool:
	return GameState.phase == Enums.Phase.SORTIE


## What the player lost when going down this sortie, {} if they did not go down.
## {"region_id", "position": Vector3, "gear": Array[StringName] (now lost gear),
##  "bag": {"resources": {id: n}, "items": [uid]} (Bag.lose_contents, empty when kept),
##  "bag_kept": bool (Settings keep_bag_on_down), "stranded": Array[StringName]}
## Lane A puts this into the sortie_ended result. Cleared when the next sortie starts.
func down_result() -> Dictionary:
	return _down_result


func down_count(region: StringName) -> int:
	return downs_by_region.get(region, 0)


## Lost gear the player can pick up in this sortie, one entry per drop spot:
## [{"position": Vector3, "item_uids": Array[StringName]}]. LostGearSpawner reads this.
func recoverable_gear() -> Array:
	var by_pos := {}
	for e: Dictionary in lost_gear:
		if e.get("offered", false) and e["region_id"] == region_id:
			if not by_pos.has(e["position"]):
				by_pos[e["position"]] = {"position": e["position"], "item_uids": [] as Array[StringName]}
			by_pos[e["position"]]["item_uids"].append(e["item_uid"])
	return by_pos.values()


## Picks lost gear back up: it goes into the field bag, or base storage if the bag is full.
## Returns false if the item is not lost gear.
func recover_gear(item_uid: StringName) -> bool:
	for i in lost_gear.size():
		if lost_gear[i]["item_uid"] == item_uid:
			lost_gear.remove_at(i)
			Armory.set_lost(item_uid, false)
			Bag.add_item(item_uid)
			return true
	return false


## A companion is left behind in the current region: the player went down, or B-09's
## "두고 갈까요?" / B-17's 30 s revive ran out. Lane C runs the strand timer.
func strand_companion(resident_id: StringName) -> void:
	companions.erase(resident_id)
	EventBus.companion_stranded.emit(resident_id, region_id)


func _on_sortie_started(loadout: Dictionary) -> void:
	region_id = loadout.get("region_id", &"")
	companions.assign(loadout.get("companions", []))
	_down_result = {}
	# Gear from another region is gone at once; gear from this region gets its one chance now.
	_drop_lost_gear(func(e: Dictionary) -> bool:
		return e.get("offered", false) or e["region_id"] != region_id)
	for e: Dictionary in lost_gear:
		e["offered"] = true


func _on_sortie_ended(_result: Dictionary) -> void:
	# Not recovered during its one sortie: gone.
	_drop_lost_gear(func(e: Dictionary) -> bool: return e.get("offered", false))


func _on_player_downed() -> void:
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	var pos := player.global_position if player else Vector3.ZERO
	var bag_kept: bool = Settings.get_value(&"keep_bag_on_down")
	var bag: Dictionary = {"resources": {}, "items": []} if bag_kept else Bag.lose_contents()
	var gear: Array[StringName] = []
	for uid: StringName in Armory.list_equipped(Armory.PLAYER_ID).values():
		Armory.set_lost(uid, true)
		lost_gear.append({"item_uid": uid, "region_id": region_id, "position": pos, "offered": false})
		gear.append(uid)
	downs_by_region[region_id] = down_count(region_id) + 1
	var stranded := companions.duplicate()
	for id in stranded:
		strand_companion(id)
	_down_result = {"region_id": region_id, "position": pos, "gear": gear, "bag": bag,
		"bag_kept": bag_kept, "stranded": stranded}


func _drop_lost_gear(should_drop: Callable) -> void:
	var kept := []
	for e: Dictionary in lost_gear:
		if should_drop.call(e):
			Armory.remove_item(e["item_uid"])
		else:
			kept.append(e)
	lost_gear = kept


func save_data() -> Dictionary:
	return {"lost_gear": lost_gear, "boss_respawn_day": boss_respawn_day,
		"downs_by_region": downs_by_region, "region_id": region_id, "companions": companions}


func load_data(data: Dictionary) -> void:
	lost_gear = data.get("lost_gear", [])
	boss_respawn_day = data.get("boss_respawn_day", {})
	downs_by_region = data.get("downs_by_region", {})
	region_id = data.get("region_id", &"")
	companions.assign(data.get("companions", []))
	_down_result = {}
