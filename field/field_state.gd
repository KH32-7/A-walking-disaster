extends Node
## Autoload `FieldState`. Owner: Lane B.
## Persistent field-side state that survives between sorties: lost gear, region
## unlocks, boss respawn timers, the current sortie's runtime info.
## Also handles the player going down (B-11): bag loss, lost gear, stranded companions.
## Design reference: docs/design/02-field.md "고립과 유실물", 01-flow-time.md "실패 처리"
## Also runs the sortie clock (B-21): dusk at GameState.SORTIE_DUSK_SEC, night from
## GameState.SORTIE_NIGHT_SEC. Night rules are in `night` (field/night_tuning.tres).
## Design reference: docs/design/01-flow-time.md "필드의 밤"

## Sortie clock reached dusk (12 min). Also says the Radio "dusk" line.
signal dusk_started
## Sortie clock reached night (15 min). MonsterSpawner applies the night rules.
signal night_started

## Night rules. Tests may swap in their own NightTuning.
var night: NightTuning = preload("res://field/night_tuning.tres")

## [{"item_uid": StringName, "region_id": StringName, "position": Vector3, "offered": bool}]
## One entry per item. "offered" = its one recovery sortie has started (set by sortie_started).
var lost_gear: Array = []
## boss monster id -> day it respawns. One region can hold several bosses (the flooded mall holds four),
## so each boss keeps its own day. Old saves keyed by region are moved to that region's boss on load.
var boss_respawn_day: Dictionary = {}
## boss monster id -> times killed (B-19). The first kill gives the BossDef first-kill reward.
var boss_kills: Dictionary = {}
## region_id -> times the player went down there (A-14 radio: "같은 지역에서 3번 쓰러짐").
var downs_by_region: Dictionary = {}
## Current sortie, from EventBus.sortie_started. Saved so a suspended sortie keeps them.
## Days from the start on which going down keeps the bag (early_bag_kept).
const EARLY_KEEP_BAG_DAYS := 3
var region_id: StringName = &""
## EarlyZone: the open part of today's map is z >= this (world, m). -INF = all of it.
var open_min_z := -INF
## Companions still with the player this sortie (stranded ones are removed).
var companions: Array[StringName] = []
## Garage uid of the vehicle brought on this sortie (loadout "vehicle"), &"" for none.
var vehicle_uid: StringName = &""
## loadout["seed"] of the current sortie (SceneRouter sets it), -1 when the scene runs without
## the router. ExtractionManager picks the active extraction points from it (issue #44).
var sortie_seed := -1
## Map ping (M map, right click). One at a time. Cleared when the sortie starts or ends,
## or once the player is within PING_REACH_M of it. Not saved.
const PING_REACH_M := 3.0
var has_ping := false
var ping := Vector3.ZERO

## Back at base with no weapon in hand and none in storage (everything lost on going down):
## the player gets this one (user playtest 2026-11-06: "기본 무기 칼 같은 거").
const STARTER_WEAPON := &"dagger"
const STARTER_WEAPON_TEXT := "맨손으로 돌아왔다. 기지에 남아 있던 단검을 챙겼다."

var _down_result: Dictionary = {}
var _sortie_result: Dictionary = {}
## Seconds since sortie_started. Runs from sortie_started until extraction, downing or sortie_ended.
var _sortie_time := 0.0
var _clock_running := false
var _dusk_sent := false
var _night_sent := false


func _ready() -> void:
	SaveSystem.register_provider(&"field", self)
	EventBus.sortie_started.connect(_on_sortie_started)
	EventBus.sortie_ended.connect(_on_sortie_ended)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.extraction_completed.connect(func(_id: StringName) -> void: _clock_running = false)


func _process(delta: float) -> void:
	if _clock_running:
		advance_sortie_time(delta)
	if has_ping:
		var p := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
		if p != null and Vector2(p.global_position.x - ping.x, p.global_position.z - ping.z).length() <= PING_REACH_M:
			clear_ping()


## Sets the one map ping (replaces the old one).
func set_ping(pos: Vector3) -> void:
	ping = pos
	has_ping = true


func clear_ping() -> void:
	has_ping = false


## True while the player is inside a field region.
func in_sortie() -> bool:
	return GameState.phase == Enums.Phase.SORTIE


## Seconds since this sortie started.
func sortie_time() -> float:
	return _sortie_time


## False in the demo build: no dusk, no night.
func night_enabled() -> bool:
	return night != null and night.enabled


## Between the dusk signal and night.
func is_dusk() -> bool:
	return _dusk_sent and not _night_sent


## Night rules apply (spawn, elites, sight, drops).
func is_night() -> bool:
	return _night_sent


## Seconds until dusk (HUD timer), 0 after it, -1 when night is off.
func dusk_left_sec() -> float:
	if not night_enabled():
		return -1.0
	return maxf(0.0, GameState.SORTIE_DUSK_SEC - _sortie_time)


## Moves the sortie clock forward. _process calls this; tests call it with big steps.
## Crossing both thresholds in one step sends dusk_started, then night_started.
func advance_sortie_time(sec: float) -> void:
	_sortie_time += maxf(sec, 0.0)
	if not night_enabled():
		return
	if not _dusk_sent and _sortie_time >= GameState.SORTIE_DUSK_SEC:
		_dusk_sent = true
		var minutes := roundi((GameState.SORTIE_NIGHT_SEC - GameState.SORTIE_DUSK_SEC) / 60.0)
		Radio.say(&"dusk", {"minutes": minutes})
		dusk_started.emit()
	if not _night_sent and _sortie_time >= GameState.SORTIE_NIGHT_SEC:
		_night_sent = true
		night_started.emit()


## What the player lost when going down this sortie, {} if they did not go down.
## {"region_id", "position": Vector3, "gear": Array[StringName] (now lost gear),
##  "bag": {"resources": {id: n}, "items": [uid]} (Bag.lose_contents, empty when kept),
##  "bag_kept": bool (Settings keep_bag_on_down), "stranded": Array[StringName]}
## Lane A puts this into the sortie_ended result. Cleared when the next sortie starts.
func down_result() -> Dictionary:
	return _down_result


## Result of the finished sortie for SceneRouter's sortie_ended ({} until extraction or downing).
## Format: docs/dev/contracts.md "출격 결과" (issue #27, #44).
func last_sortie_result() -> Dictionary:
	return _sortie_result


## ExtractionManager stores its result here: before extraction_completed, and on player_downed.
func set_sortie_result(result: Dictionary) -> void:
	_sortie_result = result.duplicate(true)


## The boss is up: never killed, or GameState.day reached its respawn day (B-19).
func boss_ready(boss_id: StringName) -> bool:
	return GameState.day >= int(boss_respawn_day.get(boss_id, 0))


func boss_kill_count(boss_id: StringName) -> int:
	return int(boss_kills.get(boss_id, 0))


## BossMonster calls this on death. An empty region keeps no respawn day (sandbox scenes).
func record_boss_kill(region: StringName, boss_id: StringName, respawn_day: int) -> void:
	boss_kills[boss_id] = boss_kill_count(boss_id) + 1
	if region != &"":
		boss_respawn_day[boss_id] = respawn_day


## Saves before the flooded mall bosses kept one day per region: move it to the region's boss.
static func _respawn_by_boss(days: Dictionary) -> Dictionary:
	var out := {}
	for key in days:
		var id := StringName(key)
		var path := RegionDef.DIR + String(id) + ".tres"
		var region := load(path) as RegionDef if ResourceLoader.exists(path) else null
		if region and region.boss_id != &"":
			id = region.boss_id
		out[id] = maxi(int(days[key]), int(out.get(id, 0)))
	return out


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
	vehicle_uid = StringName(loadout.get("vehicle", &""))
	sortie_seed = int(loadout.get("seed", -1))
	_down_result = {}
	# A stale result would leak into this sortie's sortie_ended (issue #44).
	_sortie_result = {}
	clear_ping()
	_reset_clock()
	_clock_running = true
	# Gear from another region is gone at once; gear from this region gets its one chance now.
	_drop_lost_gear(func(e: Dictionary) -> bool:
		return e.get("offered", false) or e["region_id"] != region_id)
	for e: Dictionary in lost_gear:
		e["offered"] = true


func _on_sortie_ended(_result: Dictionary) -> void:
	# Back at base: no field night left over for anything that reads is_night().
	_reset_clock()
	open_min_z = -INF
	clear_ping()
	# Not recovered during its one sortie: gone.
	_drop_lost_gear(func(e: Dictionary) -> bool: return e.get("offered", false))
	ensure_starter_weapon()


## Gives the player STARTER_WEAPON (equipped) when they hold no weapon and storage has none.
## Returns the new item uid, or &"" when nothing was needed.
func ensure_starter_weapon() -> StringName:
	if Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) != &"" \
			or Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.SUB) != &"":
		return &""
	for uid in Armory.list_storage(Enums.EquipSlot.MAIN):
		if Armory.get_def(Armory.get_item(uid).def_id).is_weapon():
			return &""
	var uid := Armory.create_item(STARTER_WEAPON, 0)
	if uid == &"" or not Armory.equip(Armory.PLAYER_ID, Enums.EquipSlot.MAIN, uid):
		return &""
	EventBus.notification_posted.emit(STARTER_WEAPON_TEXT, &"info")
	return uid


## 12 "난이도" 초반 보호 (사용자 요청 2026-11-07, 가안): going down on days 1..EARLY_KEEP_BAG_DAYS
## keeps the bag on every difficulty but hardcore. Equipped gear still drops as lost gear.
func early_bag_kept(day: int) -> bool:
	return day <= EARLY_KEEP_BAG_DAYS and not Settings.get_value(&"hardcore")


func _on_player_downed() -> void:
	_clock_running = false
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	var pos := player.global_position if player else Vector3.ZERO
	var bag_kept: bool = Settings.get_value(&"keep_bag_on_down") or early_bag_kept(GameState.day)
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


func _reset_clock() -> void:
	_sortie_time = 0.0
	_clock_running = false
	_dusk_sent = false
	_night_sent = false


func _drop_lost_gear(should_drop: Callable) -> void:
	var kept := []
	for e: Dictionary in lost_gear:
		if should_drop.call(e):
			Armory.remove_item(e["item_uid"])
		else:
			kept.append(e)
	lost_gear = kept


func save_data() -> Dictionary:
	return {"lost_gear": lost_gear, "boss_respawn_day": boss_respawn_day, "boss_kills": boss_kills,
		"downs_by_region": downs_by_region, "region_id": region_id, "companions": companions,
		"vehicle_uid": String(vehicle_uid), "sortie_time": _sortie_time, "clock_running": _clock_running}


func load_data(data: Dictionary) -> void:
	lost_gear = data.get("lost_gear", [])
	boss_respawn_day = _respawn_by_boss(data.get("boss_respawn_day", {}))
	boss_kills = data.get("boss_kills", {})
	downs_by_region = data.get("downs_by_region", {})
	region_id = data.get("region_id", &"")
	companions.assign(data.get("companions", []))
	vehicle_uid = StringName(data.get("vehicle_uid", ""))
	_down_result = {}
	# A suspended sortie resumes on the same clock. Thresholds already passed are not re-sent;
	# MonsterSpawner checks is_night() itself when the region scene loads.
	_sortie_time = float(data.get("sortie_time", 0.0))
	_clock_running = bool(data.get("clock_running", false))
	_dusk_sent = night_enabled() and _sortie_time >= GameState.SORTIE_DUSK_SEC
	_night_sent = night_enabled() and _sortie_time >= GameState.SORTIE_NIGHT_SEC
