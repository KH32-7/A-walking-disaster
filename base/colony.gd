extends Node
## Autoload `Colony`. Owner: Lane C.
## Residents, buildings, relationships, raids threat - everything that lives in the base.
## Other lanes read through the getters below; they never edit resident data directly.
## Design reference: docs/design/07-residents.md .. 10-raids-defense.md

const SAVE_VERSION := 1
## 본관 1층 침상 6자리 (docs/design/09-base-building.md "구역과 개간"). Buildings add more (C-04).
const START_BED_COUNT := 6
const START_BED_PREFIX := "main_hall_bed_"
## 기지 소음도 = 시설 소음 합 + 인구 × 0.3 (docs/design/09-base-building.md "기지 소음도").
const NOISE_PER_RESIDENT := 0.3
## Building effects grow +50% per level above 1 (09 "건물 목록").
const EFFECT_PER_LEVEL := 0.5
## Demolishing returns this share of what was paid (09 "건설 규칙").
const DEMOLISH_REFUND := 0.5

## resident_id -> Dictionary (fields: base/residents/resident_data.gd, docs/design/07-residents.md)
var residents: Dictionary = {}
## bed_id -> resident_id (&"" = free). Ordered: beds are handed out in insertion order.
var beds: Dictionary = {}
## building uid -> instance Dictionary (fields: see _new_building()).
var buildings: Dictionary = {}
## building uid -> power priority set by the player (lower = kept on longer). Missing = def default.
var power_priority_override: Dictionary = {}
var threat: int = 0
var tier: Enums.BaseTier = Enums.BaseTier.CAMP

var _next_resident_num := 1
var _next_building_num := 1
var _power_supply := 0.0
var _power_demand := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SaveSystem.register_provider(&"colony", self)
	EventBus.rescue_completed.connect(_on_rescue_completed)
	_reset()
	# DebugConsole loads after Colony and registers its placeholders in _ready; replace them after.
	_register_debug_commands.call_deferred()


# --- Read API (any lane) -------------------------------------------------------

func get_resident(resident_id: StringName) -> Dictionary:
	return residents.get(resident_id, {})


func active_resident_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in residents:
		if residents[id].get("status", Enums.ResidentStatus.ACTIVE) == Enums.ResidentStatus.ACTIVE:
			ids.append(id)
	return ids


## Population shown in the base HUD (인구). Active residents only.
func population() -> int:
	return active_resident_ids().size()


func bed_count() -> int:
	return beds.size()


func free_beds() -> Array[StringName]:
	var free: Array[StringName] = []
	for bed_id: StringName in beds:
		if beds[bed_id] == &"":
			free.append(bed_id)
	return free


## Base noise level that feeds the raid threat (docs/design/09-base-building.md "기지 소음도").
## TODO(C-14): +5 on a wedding day.
func base_noise() -> float:
	var total := population() * NOISE_PER_RESIDENT
	for uid: StringName in buildings:
		var b: Dictionary = buildings[uid]
		if b["completed"]:
			total += BaseDB.get_building(b["def_id"]).noise
	return total


## 인구 상한 = beds (본관 6 + 침상·숙소 건물).
func population_cap() -> int:
	return bed_count()


func get_building(uid: StringName) -> Dictionary:
	return buildings.get(uid, {})


## Building uids, optionally of one def. completed_only = skip construction sites.
func building_ids(def_id: StringName = &"", completed_only: bool = true) -> Array[StringName]:
	var ids: Array[StringName] = []
	for uid: StringName in buildings:
		var b: Dictionary = buildings[uid]
		if (def_id == &"" or b["def_id"] == def_id) and (b["completed"] or not completed_only):
			ids.append(uid)
	return ids


func has_completed(def_id: StringName) -> bool:
	return not building_ids(def_id).is_empty()


## Total power produced today (발전기 10, 태양광 3 / 겨울 1.5).
func power_supply() -> float:
	return _power_supply


## Total power wanted by completed buildings, powered or not.
func power_demand() -> int:
	return _power_demand


func is_powered(uid: StringName) -> bool:
	return bool(buildings.get(uid, {}).get("powered", false))


# --- Residents (Lane C) --------------------------------------------------------

## Turns a profile (rescue data, pool entry, debug) into a resident. Returns the new id.
## Gives a free bed when there is one, otherwise the resident sleeps in 임시 거처 (bed_id &"").
func add_resident(profile: Dictionary) -> StringName:
	var data := ResidentData.create(profile, _rng)
	var id: StringName = data["id"]
	if id == &"" or residents.has(id):
		id = _new_resident_id()
	data["id"] = id
	data["joined_day"] = GameState.day
	data["bed_id"] = &""
	residents[id] = data
	var free := free_beds()
	if not free.is_empty():
		assign_bed(id, free[0])
	EventBus.resident_joined.emit(id)
	return id


## Puts a resident in a bed (입주 의식 C-13 lets the player choose). The bed must exist and be
## free. Moves the resident out of their previous bed.
func assign_bed(resident_id: StringName, bed_id: StringName) -> bool:
	if not residents.has(resident_id) or not beds.has(bed_id):
		return false
	if beds[bed_id] != &"" and beds[bed_id] != resident_id:
		return false
	release_bed(resident_id)
	beds[bed_id] = resident_id
	residents[resident_id]["bed_id"] = bed_id
	return true


func release_bed(resident_id: StringName) -> void:
	if not residents.has(resident_id):
		return
	var old: StringName = residents[resident_id]["bed_id"]
	if beds.get(old, &"") == resident_id:
		beds[old] = &""
	residents[resident_id]["bed_id"] = &""


## Adds beds (C-04: when a bed building completes). Existing ids are ignored.
func add_beds(bed_ids: Array[StringName]) -> void:
	for bed_id in bed_ids:
		if not beds.has(bed_id):
			beds[bed_id] = &""


## Removes beds (a bed building was demolished). Their sleepers go to 임시 거처.
func remove_beds(bed_ids: Array[StringName]) -> void:
	for bed_id in bed_ids:
		var sleeper: StringName = beds.get(bed_id, &"")
		if sleeper != &"" and residents.has(sleeper):
			residents[sleeper]["bed_id"] = &""
		beds.erase(bed_id)


# --- Buildings (Lane C) --------------------------------------------------------

## Can `def_id` be built now? Checks tier, required buildings, flags (blueprints, first death),
## a resident with the required former job, and the Lv1 cost. Placement (cells, zone, paths)
## is checked by the grid (C-03). Returns {"ok": bool, "reasons": Array[String]} for the UI.
func can_build(def_id: StringName) -> Dictionary:
	var reasons: Array[String] = []
	var def := BaseDB.get_building(def_id)
	if def == null:
		return {"ok": false, "reasons": ["알 수 없는 건물: %s" % def_id]}
	if def.prebuilt:
		reasons.append("처음부터 있는 시설")
	if tier < def.tier_min:
		reasons.append("기지 단계 %s 필요" % Enums.BaseTier.keys()[def.tier_min])
	for req in def.requires:
		if not has_completed(req):
			var req_def := BaseDB.get_building(req)
			reasons.append("%s 필요" % (req_def.display_name if req_def else String(req)))
	for flag in def.requires_flags:
		if not GameState.has_flag(flag):
			reasons.append("조건 필요: %s" % flag)
	if def.requires_former_job != &"" and not _has_former_job(def.requires_former_job):
		reasons.append("전직 %s 주민 필요" % def.requires_former_job)
	if not Economy.can_afford(def.cost_for_level(1)):
		reasons.append("자원 부족")
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Places a construction site (건설 현장) and pays the Lv1 cost. Returns its uid, or &"" when
## can_build() fails (or the cost cannot be paid). `pay = false` for debug/sandbox/story builds.
## Cells/rotation are stored as given; the grid (C-03) validates them before calling this.
func place_building(def_id: StringName, cell: Vector2i = Vector2i.ZERO, rotation: int = 0,
		zone_id: StringName = &"", pay: bool = true) -> StringName:
	var def := BaseDB.get_building(def_id)
	if def == null:
		return &""
	if pay:
		if not can_build(def_id)["ok"] or not Economy.apply(_negated(def.cost_for_level(1))):
			return &""
	var uid := _new_building_uid(def_id)
	buildings[uid] = _new_building(uid, def, cell, rotation, zone_id, def.cost_for_level(1) if pay else {})
	return uid


## Adds build progress (건설 담당 주민 C-05, 플레이어 머무르기 +20). Completes the building when
## the needed work is reached. Returns true when this call completed it.
func add_build_progress(uid: StringName, amount: int) -> bool:
	var b: Dictionary = buildings.get(uid, {})
	if b.is_empty() or b["completed"]:
		return false
	b["progress"] = int(b["progress"]) + maxi(amount, 0)
	if b["progress"] >= BaseDB.get_building(b["def_id"]).build_work_needed():
		complete_building(uid)
		return true
	return false


## Finishes a building right away (debug, story, prebuilt). Applies its effects.
func complete_building(uid: StringName) -> void:
	var b: Dictionary = buildings.get(uid, {})
	if b.is_empty() or b["completed"]:
		return
	var def := BaseDB.get_building(b["def_id"])
	b["completed"] = true
	b["progress"] = def.build_work_needed()
	b["durability"] = def.durability
	_refresh_effects()
	EventBus.building_completed.emit(uid)


## Removes a building and returns 50% of what was paid. Prebuilt rooms cannot be removed.
## Returns the refund (resource_id -> amount), or {} if nothing was removed.
func demolish_building(uid: StringName) -> Dictionary:
	var b: Dictionary = buildings.get(uid, {})
	if b.is_empty() or BaseDB.get_building(b["def_id"]).prebuilt:
		return {}
	var refund := {}
	var paid: Dictionary = b["paid"]
	for res in paid:
		var n := floori(int(paid[res]) * DEMOLISH_REFUND)
		if n > 0:
			refund[StringName(res)] = n
	for worker in b["workers"]:
		if residents.has(worker):
			residents[worker]["assignment"] = {"job": &"", "building_id": &""}
	buildings.erase(uid)
	power_priority_override.erase(uid)
	_refresh_effects()
	if not refund.is_empty():
		Economy.apply(refund)
	return refund


## Effect value of a completed building at its level (+50% per level above 1).
func building_effect(uid: StringName, key: StringName, default: float = 0.0) -> float:
	var b: Dictionary = buildings.get(uid, {})
	if b.is_empty():
		return default
	var base := BaseDB.get_building(b["def_id"]).effect(key, default)
	return base * (1.0 + EFFECT_PER_LEVEL * (int(b["level"]) - 1))


## Player-set power priority (전력 우선순위 화면, Lane D). Lower = stays on longer.
func set_power_priority(uid: StringName, priority: int) -> void:
	if buildings.has(uid):
		power_priority_override[uid] = priority
		_refresh_effects()


## Recomputes everything derived from completed buildings: beds, storage cap, power.
## Called after any building change and after loading.
func _refresh_effects() -> void:
	_refresh_beds()
	var storage := 0.0
	for uid in building_ids():
		storage += building_effect(uid, &"storage")
	Economy.set_cap_bonus(roundi(storage))
	_refresh_power()


func _refresh_beds() -> void:
	var wanted: Array[StringName] = []
	for uid in building_ids():
		var n := BaseDB.get_building(buildings[uid]["def_id"]).bed_count()
		for i in n:
			wanted.append(StringName("%s_bed_%d" % [uid, i + 1]))
	var stale: Array[StringName] = []
	for bed_id: StringName in beds:
		if not String(bed_id).begins_with(START_BED_PREFIX) and not bed_id in wanted:
			stale.append(bed_id)
	remove_beds(stale)
	add_beds(wanted)


## Supplies power to consumers in priority order (09 "전력"): inclusion → infirmary → radio → rest.
## TODO(C-05): a generator without fuel for the day gives no power.
func _refresh_power() -> void:
	var winter := GameState.season() == Enums.Season.WINTER
	_power_supply = 0.0
	_power_demand = 0
	var consumers: Array[StringName] = []
	for uid in building_ids():
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		var supply := building_effect(uid, &"power_supply")
		if winter and def.effects.has(&"power_supply_winter"):
			supply = building_effect(uid, &"power_supply_winter")
		_power_supply += supply
		var use := def.power_use_at(int(buildings[uid]["level"]))
		_power_demand += use
		if use > 0:
			consumers.append(uid)
		else:
			buildings[uid]["powered"] = true
	consumers.sort_custom(func(a: StringName, b: StringName) -> bool:
		var pa := _power_priority_of(a)
		var pb := _power_priority_of(b)
		return pa < pb if pa != pb else String(a) < String(b))
	var left := _power_supply
	for uid in consumers:
		var use := BaseDB.get_building(buildings[uid]["def_id"]).power_use_at(int(buildings[uid]["level"]))
		buildings[uid]["powered"] = left >= use
		if left >= use:
			left -= use


func _power_priority_of(uid: StringName) -> int:
	if power_priority_override.has(uid):
		return int(power_priority_override[uid])
	return BaseDB.get_building(buildings[uid]["def_id"]).power_priority


func _new_building(uid: StringName, def: BuildingDef, cell: Vector2i, rotation: int,
		zone_id: StringName, paid: Dictionary) -> Dictionary:
	# Same types as _normalize_building() so a save → load round trip compares equal.
	var workers: Array[StringName] = []
	return {
		"uid": uid,
		"def_id": def.id,
		"level": 1,
		"cell": [cell.x, cell.y],
		"rotation": posmod(rotation, 4),
		"zone_id": zone_id,
		"durability": 0,
		"workers": workers,
		"progress": 0,
		"completed": false,
		"powered": false,
		"paid": paid.duplicate(),
	}


## Fixes types after a JSON round trip.
func _normalize_building(src: Dictionary) -> Dictionary:
	var b := src.duplicate(true)
	b["uid"] = StringName(b.get("uid", &""))
	b["def_id"] = StringName(b.get("def_id", &""))
	b["level"] = clampi(int(b.get("level", 1)), 1, BuildingDef.MAX_LEVEL)
	var cell: Array = b.get("cell", [0, 0])
	b["cell"] = [int(cell[0]), int(cell[1])] if cell.size() >= 2 else [0, 0]
	b["rotation"] = posmod(int(b.get("rotation", 0)), 4)
	b["zone_id"] = StringName(b.get("zone_id", &""))
	b["durability"] = int(b.get("durability", 0))
	var workers: Array[StringName] = []
	for w in b.get("workers", []):
		workers.append(StringName(w))
	b["workers"] = workers
	b["progress"] = int(b.get("progress", 0))
	b["completed"] = bool(b.get("completed", false))
	b["powered"] = bool(b.get("powered", false))
	var paid := {}
	var src_paid: Dictionary = b.get("paid", {})
	for res in src_paid:
		paid[StringName(res)] = int(src_paid[res])
	b["paid"] = paid
	return b


func _new_building_uid(def_id: StringName) -> StringName:
	while true:
		var uid := StringName("%s_%03d" % [def_id, _next_building_num])
		_next_building_num += 1
		if not buildings.has(uid):
			return uid
	return &""


func _has_former_job(former_job: StringName) -> bool:
	for id in active_resident_ids():
		if residents[id]["former_job"] == former_job:
			return true
	return false


static func _negated(cost: Dictionary) -> Dictionary:
	var out := {}
	for res in cost:
		out[res] = -int(cost[res])
	return out


func _on_rescue_completed(rescued: Dictionary) -> void:
	add_resident(rescued)


func _new_resident_id() -> StringName:
	while true:
		var id := StringName("resident_%03d" % _next_resident_num)
		_next_resident_num += 1
		if not residents.has(id):
			return id
	return &""


func _reset() -> void:
	residents = {}
	beds = {}
	var start: Array[StringName] = []
	for i in START_BED_COUNT:
		start.append(StringName("%s%d" % [START_BED_PREFIX, i + 1]))
	add_beds(start)
	buildings = {}
	power_priority_override = {}
	_next_building_num = 1
	# Rooms that exist from the start (무전실 = 본관 방송실). uid = def id.
	for def_id: StringName in BaseDB.buildings():
		var def := BaseDB.get_building(def_id)
		if def.prebuilt:
			var b := _new_building(def_id, def, Vector2i.ZERO, 0, &"main_hall", {})
			b["completed"] = true
			b["durability"] = def.durability
			buildings[def_id] = b
	threat = 0
	tier = Enums.BaseTier.CAMP
	_next_resident_num = 1
	_rng.randomize()
	_refresh_effects()


# --- Save provider -------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"residents": residents,
		"beds": beds,
		"buildings": buildings,
		"power_priority_override": power_priority_override,
		"next_resident_num": _next_resident_num,
		"next_building_num": _next_building_num,
		"threat": threat,
		"tier": tier,
	}


## Accepts data straight from save_data() or after a JSON round trip (String keys, float numbers).
func load_data(data: Dictionary) -> void:
	_reset()
	residents = {}
	for key in data.get("residents", {}):
		var r := ResidentData.normalize(data["residents"][key])
		if r["id"] == &"":
			r["id"] = StringName(key)
		residents[r["id"]] = r
	var saved_beds: Dictionary = data.get("beds", {})
	if not saved_beds.is_empty():
		beds = {}
		for bed_id in saved_beds:
			beds[StringName(bed_id)] = StringName(saved_beds[bed_id])
	_next_resident_num = maxi(int(data.get("next_resident_num", 1)), 1)
	if data.has("buildings"):
		buildings = {}
		for key in data["buildings"]:
			var b := _normalize_building(data["buildings"][key])
			if BaseDB.get_building(b["def_id"]) == null:
				push_warning("Colony: dropping building with unknown def %s" % b["def_id"])
				continue
			buildings[b["uid"]] = b
	power_priority_override = {}
	var saved_prio: Dictionary = data.get("power_priority_override", {})
	for uid in saved_prio:
		power_priority_override[StringName(uid)] = int(saved_prio[uid])
	_next_building_num = maxi(int(data.get("next_building_num", 1)), 1)
	threat = int(data.get("threat", 0))
	tier = int(data.get("tier", Enums.BaseTier.CAMP)) as Enums.BaseTier
	_refresh_effects()


# --- Debug console (debug builds only) -----------------------------------------

func _register_debug_commands() -> void:
	DebugConsole.register(&"resident", _cmd_resident,
		"resident add [demo 1~3] | resident list - 주민 추가(무작위 또는 데모 구조자)·목록")
	DebugConsole.register(&"build", _cmd_build,
		"build <building_id> | build list - 비용 없이 건물을 바로 완성 / 건물·전력·소음 목록")


func _cmd_build(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "list"
	if sub == "list":
		var lines := PackedStringArray(["건물 %d개, 침상 %d, 전력 %.1f/%d, 소음도 %.1f, 창고 보너스 %d" % [
			buildings.size(), bed_count(), power_supply(), power_demand(), base_noise(), Economy.cap_bonus]])
		for uid: StringName in buildings:
			var b: Dictionary = buildings[uid]
			lines.append("  %s Lv%d %s%s" % [uid, b["level"], "완성" if b["completed"] else "건설 중 %d" % b["progress"],
				"" if b["powered"] else " (전력 없음)"])
		return "\n".join(lines)
	var def_id := StringName(sub)
	if BaseDB.get_building(def_id) == null:
		return "알 수 없는 건물: %s (data/buildings)" % sub
	var uid := place_building(def_id, Vector2i.ZERO, 0, &"", false)
	complete_building(uid)
	return "건설 완료: %s" % uid


func _cmd_resident(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "list"
	match sub:
		"add":
			var profile := {}
			if args.size() >= 3 and args[1] == "demo":
				var i := int(args[2]) - 1
				if i < 0 or i >= DemoProfiles.PROFILES.size():
					return "데모 번호는 1~%d" % DemoProfiles.PROFILES.size()
				profile = DemoProfiles.PROFILES[i]
			var id := add_resident(profile)
			var r := get_resident(id)
			return "주민 추가: %s %s (침상 %s)" % [id, r["name"], r["bed_id"] if r["bed_id"] != &"" else "없음 - 임시 거처"]
		"list":
			var lines := PackedStringArray(["주민 %d명, 침상 %d/%d" % [population(), bed_count() - free_beds().size(), bed_count()]])
			for id: StringName in residents:
				var r: Dictionary = residents[id]
				lines.append("  %s %s 특성 %s 능력치 %s" % [id, r["name"], r["traits"], r["stats"]])
			return "\n".join(lines)
	return "사용법: resident add [demo 1~3] | resident list"
