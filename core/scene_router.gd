extends Node
## Autoload `SceneRouter`. Owner: Lane A (task A-05).
## Drives the day: every flow-state change goes through here (GameState.set_flow_state), and it swaps
## the world scene under main.tscn's `World` node. Lanes never call get_tree().change_scene_*().
## Design reference: docs/design/01-flow-time.md "하루 구조", "게임 상태", 10-raids-defense.md
##
## Day:  BASE_MORNING -> SORTIE_PREP -> FIELD -> RESULT -> EVENING -> NIGHT (-> NIGHT_RAID) -> next day
##       BASE_MORNING -> BASE_STAY (-> BASE_DAY_RAID) -> EVENING ...
## Who calls what:
##   Lane D (screens): start_new_game, load_game, load_suspended, open_sortie_prep, cancel_sortie_prep,
##                     go_to_field, stay_at_base, end_stay, finish_result, confirm_evening, finish_night
##   Lane B (field):   fills FieldState.last_sortie_result() (issue #27), then emits extraction_completed;
##                     on player_downed the router waits until the end of the frame so B's handlers
##                     (bag loss, lost gear, result) run first. rescue_completed / companion_stranded /
##                     emergency_return_requested are tracked too. The router emits sortie_ended.
##   Lane C (base):    start_day_raid / end_day_raid / start_night_event / end_night_event,
##                     and the Colony.settle_day / roll_raid / resolve_raid functions in contracts.md.
## Autosaves (design 01 "저장"): entering BASE_MORNING, right before the field loads (saved as
## SORTIE_PREP, so loading puts you back in prep) and on entering RESULT after the bag was unloaded.

const BASE_SCENE := "res://levels/base/base_school/base_school.tscn"
## Field region scenes follow levels/field/<region_id>/<region_id>.tscn (Lane B).
const REGION_SCENE_FMT := "res://levels/field/%s/%s.tscn"
const WORLD_PATH := ^"/root/Main/World"
## Fallback region id when no field map exists at all (tests, headless). advance() prefers
## default_region(), the first region that has a map.
const DEBUG_REGION := &"debug_region"
const FIELD_LEVELS_DIR := "res://levels/field"

const S := Enums.FlowState
## Allowed moves. Anything else is refused with an error.
const TRANSITIONS := {
	S.TITLE: [S.BASE_MORNING],
	S.BASE_MORNING: [S.SORTIE_PREP, S.BASE_STAY],
	S.SORTIE_PREP: [S.FIELD, S.BASE_MORNING],
	S.FIELD: [S.RESULT, S.BASE_DAY_RAID],
	S.BASE_STAY: [S.BASE_DAY_RAID, S.EVENING],
	S.BASE_DAY_RAID: [S.RESULT, S.EVENING],
	S.RESULT: [S.EVENING],
	S.EVENING: [S.NIGHT],
	S.NIGHT: [S.NIGHT_RAID, S.NIGHT_EVENT, S.BASE_MORNING],
	S.NIGHT_RAID: [S.NIGHT],
	S.NIGHT_EVENT: [S.NIGHT],
}

## True on days the player chose "기지에 머무르기" (Lane C: +20 % production, one extra talk).
var stayed_today := false
## The last evening report and sortie result, for screens opened late.
var last_evening_report: Dictionary = {}
var last_sortie_result: Dictionary = {}

var _loadout: Dictionary = {}
## rescue_completed profiles and companion_stranded ids seen during this sortie (fallback when Lane B
## has no result yet, and "rescued_profiles" in the result).
var _rescued: Array = []
var _stranded: Array = []
var _finish_pending := false
var _emergency_return := false
var _day_raid: Dictionary = {}
var _day_raid_from_field := false


func _ready() -> void:
	SaveSystem.register_provider(&"router", self)
	EventBus.extraction_completed.connect(_on_extraction_completed)
	EventBus.player_downed.connect(_on_player_downed)
	EventBus.rescue_completed.connect(func(rescued: Dictionary): _rescued.append(rescued))
	EventBus.companion_stranded.connect(
		func(resident_id: StringName, region_id: StringName):
			if not resident_id in _stranded:
				_stranded.append(resident_id))
	EventBus.emergency_return_requested.connect(func(): _emergency_return = true)


func state() -> Enums.FlowState:
	return GameState.flow_state


# --- Title ---

## New game in `slot` with a difficulty preset. Every save provider is reset to its defaults.
func start_new_game(slot: int = 0, difficulty: StringName = &"normal") -> bool:
	if state() != S.TITLE:
		return _refuse("start_new_game")
	SaveSystem.reset_all()
	SaveSystem.current_slot = slot
	Settings.apply_preset(difficulty, true)
	GameState.day = 1
	GameState.roll_weather()
	_begin_morning()
	return true


func load_game(slot: int) -> bool:
	if not SaveSystem.load_slot(slot):
		return false
	_resume_after_load()
	return true


## Continue a sortie the player quit mid-way (the suspend file is deleted by SaveSystem).
func load_suspended() -> bool:
	if not SaveSystem.load_suspend():
		return false
	_resume_after_load()
	return true


## Lane D's quit-to-title: in the field this writes the suspend save.
func quit_to_title() -> void:
	if state() == S.FIELD:
		SaveSystem.save_suspend()
	_clear_world()
	GameState.set_flow_state(S.TITLE)


# --- Morning ---

func open_sortie_prep() -> bool:
	return _go(S.SORTIE_PREP)


func cancel_sortie_prep() -> bool:
	return _go(S.BASE_MORNING)


## loadout: {"region_id": StringName, "companions": Array[StringName], "gear": Dictionary}
func go_to_field(loadout: Dictionary) -> bool:
	if state() != S.SORTIE_PREP:
		return _refuse("go_to_field")
	_loadout = loadout.duplicate(true)
	# Lane B picks the active extraction points from this seed; saved with the router so a
	# reload gets the same points (issue #27).
	if not _loadout.has("seed"):
		_loadout["seed"] = randi()
	_finish_pending = false
	_rescued.clear()
	_stranded.clear()
	_emergency_return = false
	stayed_today = false
	SaveSystem.autosave()  # "출격 직전": saved as SORTIE_PREP
	_go(S.FIELD)
	var region := StringName(_loadout.get("region_id", DEBUG_REGION))
	_load_world(REGION_SCENE_FMT % [region, region])
	EventBus.sortie_started.emit(_loadout)
	return true


func stay_at_base() -> bool:
	if not _go(S.BASE_STAY):
		return false
	stayed_today = true
	return true


func end_stay() -> bool:
	return _go(S.EVENING) and _settle_evening()


# --- Field end ---

func _on_extraction_completed(_point_id: StringName) -> void:
	if state() == S.FIELD:
		_finish_sortie(true)


## Deferred: Lane B's own player_downed handlers (FieldState bag loss and lost gear, the extraction
## manager's result) must run first, whatever order the signal connections have.
func _on_player_downed() -> void:
	if state() == S.FIELD and not _finish_pending:
		_finish_pending = true
		_finish_sortie.call_deferred(false)


## Builds the sortie_ended result (format: docs/dev/contracts.md "출격 결과"). Lane B's result from
## FieldState.last_sortie_result() is the base; the router adds what only it knows.
func _finish_sortie(extracted: bool) -> void:
	_finish_pending = false
	if state() != S.FIELD:
		return
	var b_result: Dictionary = {}
	if FieldState.has_method(&"last_sortie_result"):
		b_result = FieldState.call(&"last_sortie_result")
	var region := StringName(b_result.get("region_id", _loadout.get("region_id", &"")))
	# Lane B unloads at the moment of extraction; unloading again picks up anything left
	# (the safe pocket after going down) and merges it.
	var loot := _merge_loot(b_result.get("loot", {}), Bag.unload_to_base())
	var rescued_ids: Array = b_result.get("rescued", _rescued.map(func(p): return StringName(p.get("id", &""))))
	var result := {
		"extracted": extracted,
		"downed": not extracted,
		"region_id": region,
		"point_id": &"",
		"kills": 0,
		"kills_by_monster": {},
		"rescued": [],
		"companions": [],
		"stranded": _stranded.duplicate(),
		"duration_sec": 0.0,
	}
	result.merge(b_result, true)
	result["extracted"] = extracted
	result["downed"] = not extracted
	result["loot"] = loot
	result["rescued"] = rescued_ids
	result["rescued_profiles"] = _rescued.duplicate()
	result["down"] = FieldState.call(&"down_result") if not extracted and FieldState.has_method(&"down_result") else {}
	result["xp"] = Progression.finish_sortie(extracted, region, rescued_ids.size())
	last_sortie_result = result
	EventBus.sortie_ended.emit(last_sortie_result)
	if extracted and _emergency_return and not _day_raid.is_empty():
		_go(S.BASE_DAY_RAID)
		_load_world(BASE_SCENE)
		return
	_go(S.RESULT)
	_load_world(BASE_SCENE)
	SaveSystem.autosave()  # "탈출 직후"


func finish_result() -> bool:
	return _go(S.EVENING) and _settle_evening()


# --- Day raid (Lane C) ---

## Lane C: a day raid happens. While the player stays at base it starts the defence right away;
## during a sortie the router remembers it so an emergency return leads into the defence.
func start_day_raid(raid: Dictionary) -> bool:
	_day_raid = raid.duplicate(true)
	_day_raid_from_field = state() == S.FIELD
	if state() == S.BASE_STAY:
		return _go(S.BASE_DAY_RAID)
	return state() == S.FIELD


## Lane C: the day raid defence is over. From a stay day go to the evening, after an emergency
## return show the sortie result first.
func end_day_raid() -> bool:
	if state() != S.BASE_DAY_RAID:
		return _refuse("end_day_raid")
	var came_from_field := _day_raid_from_field
	_day_raid = {}
	_day_raid_from_field = false
	if came_from_field:
		_go(S.RESULT)
		SaveSystem.autosave()
		return true
	return _go(S.EVENING) and _settle_evening()


# --- Evening and night ---

func confirm_evening() -> bool:
	if not _go(S.NIGHT):
		return false
	_roll_night_raid()
	return true


## Lane C: a night event (bonfire, confession ...) is playing.
func start_night_event(event_id: StringName, participants: Array = []) -> bool:
	if not _go(S.NIGHT_EVENT):
		return false
	EventBus.night_event_started.emit(event_id, participants)
	return true


func end_night_event() -> bool:
	return _go(S.NIGHT)


## Night is over: next day's morning.
func finish_night() -> bool:
	if state() != S.NIGHT:
		return _refuse("finish_night")
	GameState.start_next_day()
	_begin_morning(false)
	return true


## First region (by folder name) under levels/field/ that has a map scene; DEBUG_REGION if none.
func default_region() -> StringName:
	var dir := DirAccess.open(FIELD_LEVELS_DIR)
	if dir == null:
		return DEBUG_REGION
	var names := Array(dir.get_directories())
	names.sort()
	for n: String in names:
		if ResourceLoader.exists(REGION_SCENE_FMT % [n, n]):
			return StringName(n)
	return DEBUG_REGION


## Debug / tests: take the default next step (sortie path, extract, no events).
## `region_id` picks the sortie region from SORTIE_PREP; empty means default_region().
func advance(region_id: StringName = &"") -> bool:
	match state():
		S.TITLE:
			return start_new_game()
		S.BASE_MORNING:
			return open_sortie_prep()
		S.SORTIE_PREP:
			var region := region_id if region_id != &"" else default_region()
			return go_to_field({"region_id": region, "companions": [], "gear": {}})
		S.FIELD:
			EventBus.extraction_completed.emit(&"debug")
			return true
		S.RESULT:
			return finish_result()
		S.BASE_STAY:
			return end_stay()
		S.BASE_DAY_RAID:
			return end_day_raid()
		S.EVENING:
			return confirm_evening()
		S.NIGHT_EVENT:
			return end_night_event()
		S.NIGHT:
			return finish_night()
	return false


## {"resources", "discarded", "items"} from two unloads added together.
func _merge_loot(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"resources": {}, "discarded": {}, "items": []}
	for part: Dictionary in [a, b]:
		for key in ["resources", "discarded"]:
			var dst: Dictionary = out[key]
			var src: Dictionary = part.get(key, {})
			for id in src:
				dst[id] = dst.get(id, 0) + int(src[id])
		for uid in part.get("items", []):
			if not uid in out["items"]:
				out["items"].append(uid)
	return out


# --- Save provider "router" ---

func save_data() -> Dictionary:
	return {"stayed_today": stayed_today, "loadout": _loadout, "rescued": _rescued, "stranded": _stranded,
		"emergency_return": _emergency_return, "day_raid": _day_raid, "day_raid_from_field": _day_raid_from_field}


func load_data(data: Dictionary) -> void:
	stayed_today = bool(data.get("stayed_today", false))
	_loadout = data.get("loadout", {})
	_rescued = data.get("rescued", [])
	_stranded = data.get("stranded", [])
	_emergency_return = bool(data.get("emergency_return", false))
	_day_raid = data.get("day_raid", {})
	_day_raid_from_field = bool(data.get("day_raid_from_field", false))


# --- Internals ---

func _begin_morning(first_day := true) -> void:
	stayed_today = false
	_day_raid = {}
	_go(S.BASE_MORNING)
	_load_world(BASE_SCENE)
	if first_day:
		# start_next_day() emits day_started for later days.
		EventBus.day_started.emit(GameState.day)
	SaveSystem.autosave()  # "아침 시작"


## Evening settlement order (contracts.md): Colony.settle_day -> Economy.apply_detailed -> report.
func _settle_evening() -> bool:
	var report: Dictionary = {"changes": {}, "produced": {}, "consumed": {}, "morale": {}, "events": []}
	if Colony.has_method(&"settle_day"):
		var settled: Dictionary = Colony.call(&"settle_day")
		report.merge(settled, true)
	var applied := Economy.apply_detailed(report.get("changes", {}))
	if not applied["ok"]:
		# Colony asked for more than storage holds; spend what exists instead of nothing.
		push_warning("SceneRouter: settle_day changes could not be applied as a whole: %s" % report["changes"])
	report["discarded"] = applied["discarded"]
	# A-09 auto repair (spends scrap itself; only runs when the player turned it on).
	report["repairs"] = {
		UpgradeRules.WEAPON_FACILITY: Armory.run_auto_repair(UpgradeRules.WEAPON_FACILITY),
		UpgradeRules.GEAR_FACILITY: Armory.run_auto_repair(UpgradeRules.GEAR_FACILITY),
	}
	last_evening_report = report
	EventBus.evening_settled.emit(report)
	return true


## Night raid is resolved automatically for now (direct defence is C-17).
func _roll_night_raid() -> void:
	if not Colony.has_method(&"roll_raid"):
		return
	var raid: Dictionary = Colony.call(&"roll_raid", Enums.RaidTime.NIGHT)
	if not raid.get("occurs", false):
		return
	_go(S.NIGHT_RAID)
	if Colony.has_method(&"resolve_raid"):
		Colony.call(&"resolve_raid", raid, Enums.RaidMode.AUTO)
	_go(S.NIGHT)


## The flow state came back with GameState; re-enter it so screens and the world match.
## Slot saves are made in BASE_MORNING, SORTIE_PREP or RESULT; only the suspend save is in FIELD.
func _resume_after_load() -> void:
	var target := state()
	if target == S.TITLE:
		target = S.BASE_MORNING
	GameState.flow_state = S.TITLE  # force a fresh flow_state_changed
	GameState.set_flow_state(target)
	if target == S.FIELD:
		var region := StringName(_loadout.get("region_id", DEBUG_REGION))
		_load_world(REGION_SCENE_FMT % [region, region])
	else:
		_load_world(BASE_SCENE)


func _go(next: Enums.FlowState) -> bool:
	var current := state()
	if not next in TRANSITIONS.get(current, []):
		return _refuse("%s -> %s" % [S.keys()[current], S.keys()[next]])
	GameState.set_flow_state(next)
	return true


func _refuse(what: String) -> bool:
	push_error("SceneRouter: not allowed from %s: %s" % [S.keys()[state()], what])
	return false


## Replaces the World node's child with `scene_path`. Missing World (tests, headless) or a scene that
## does not exist yet (levels still being built) just leaves the world empty.
func _load_world(scene_path: String) -> void:
	var world := get_node_or_null(WORLD_PATH)
	if world == null:
		return
	if world.get_child_count() == 1 and world.get_child(0).scene_file_path == scene_path:
		return
	_clear_world()
	if not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed != null:
		world.add_child(packed.instantiate())


func _clear_world() -> void:
	var world := get_node_or_null(WORLD_PATH)
	if world == null:
		return
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()
