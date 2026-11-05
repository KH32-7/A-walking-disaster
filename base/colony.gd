extends Node
## Emitted (by Colony itself) whenever buildings are placed, moved, completed, damaged or removed,
## and after loading. Building views (base/building) and Lane D screens redraw on it.
signal buildings_changed
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
## Day of the last raid (하루 최대 1번). 0 = none yet.
var last_raid_day := 0
## The raid between start_raid() and resolve_raid() ({} when none).
var active_raid: Dictionary = {}
## Zones cleared during play (C-10 adds clearing progress). Zones marked starts_cleared on the map
## need no entry. zone_id -> true.
var cleared_zones: Dictionary = {}

var _next_resident_num := 1
var _next_building_num := 1
var _power_supply := 0.0
var _power_demand := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SaveSystem.register_provider(&"colony", self)
	EventBus.rescue_completed.connect(_on_rescue_completed)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
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
		if b["completed"] and not b["damaged"]:
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


## Completed and not damaged by a raid (파손된 시설은 작동이 멈춤, 10 "수리").
func working_building_ids(def_id: StringName = &"") -> Array[StringName]:
	var ids: Array[StringName] = []
	for uid in building_ids(def_id):
		if not buildings[uid]["damaged"]:
			ids.append(uid)
	return ids


## Highest level among working (completed, not damaged) buildings of `def_id`; 0 when none.
## For Armory upgrade/craft caps (A-09, issue #45).
func facility_level(def_id: StringName) -> int:
	var level := 0
	for uid in working_building_ids(def_id):
		level = maxi(level, int(buildings[uid]["level"]))
	return level


## Active residents assigned to working buildings of `def_id` (A-09 reads their 손재주).
func facility_workers(def_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for uid in working_building_ids(def_id):
		for worker: StringName in buildings[uid]["workers"]:
			if residents.has(worker) and int(residents[worker]["status"]) == Enums.ResidentStatus.ACTIVE \
					and not worker in out:
				out.append(worker)
	return out


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
	buildings_changed.emit()
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
	buildings_changed.emit()


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
	buildings_changed.emit()
	return refund


## Moves a building (09 "건설 규칙": 이동은 무료, 진행도 유지). The grid (BaseGrid.check with
## ignore_uid) validates the new spot first. Workers and beds stay with the building.
func move_building(uid: StringName, cell: Vector2i, rotation: int, zone_id: StringName) -> bool:
	if not buildings.has(uid) or BaseDB.get_building(buildings[uid]["def_id"]).prebuilt:
		return false
	buildings[uid]["cell"] = [cell.x, cell.y]
	buildings[uid]["rotation"] = posmod(rotation, 4)
	buildings[uid]["zone_id"] = zone_id
	buildings_changed.emit()
	return true


## Zone clearing state (09 "구역과 개간"). C-10 adds progress, yields and the buried-box event;
## for now clear_zone() marks a zone usable (debug `zone clear <id>`, story).
func is_zone_cleared(zone_id: StringName) -> bool:
	return cleared_zones.has(zone_id)


func clear_zone(zone_id: StringName) -> void:
	cleared_zones[zone_id] = true
	buildings_changed.emit()


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
	for uid in working_building_ids():
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
## A generator that ran out of fuel in the last settlement gives no power ("fueled" = false).
func _refresh_power() -> void:
	var winter := GameState.season() == Enums.Season.WINTER
	_power_supply = 0.0
	_power_demand = 0
	var consumers: Array[StringName] = []
	for uid in building_ids():  # damaged ones are switched off below
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		var supply := building_effect(uid, &"power_supply")
		if winter and def.effects.has(&"power_supply_winter"):
			supply = building_effect(uid, &"power_supply_winter")
		if not buildings[uid]["fueled"] or buildings[uid]["damaged"]:
			supply = 0.0
		_power_supply += supply
		var use := def.power_use_at(int(buildings[uid]["level"]))
		_power_demand += use
		if buildings[uid]["damaged"]:
			buildings[uid]["powered"] = false
		elif use > 0:
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
		"fueled": true,
		"damaged": false,
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
	b["fueled"] = bool(b.get("fueled", true))
	b["damaged"] = bool(b.get("damaged", false))
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


# --- Jobs and the daily settlement (Lane C, C-05) ------------------------------

## Worker slots of a completed building: Lv1 정원, +1 per level above 1 (09 "건물 목록").
func building_capacity(uid: StringName) -> int:
	var b: Dictionary = buildings.get(uid, {})
	if b.is_empty():
		return 0
	var cap := BaseDB.get_building(b["def_id"]).capacity
	return cap + int(b["level"]) - 1 if cap > 0 else 0


## Why `resident_id` cannot take `job_id` at `building_uid` ("" = allowed). For the UI.
## building_uid &"" = pick a workplace automatically (see assign_job()).
func job_block_reason(resident_id: StringName, job_id: StringName, building_uid: StringName = &"") -> String:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return "주민 없음"
	var job := BaseDB.get_job(job_id)
	var reason := WorkRules.job_block_reason(r, job)
	if reason != "":
		return reason
	if job_id == WorkRules.CONSTRUCTION_JOB:
		var site: Dictionary = buildings.get(building_uid, {})
		return "" if not site.is_empty() and not site["completed"] else "건설 현장을 골라야 함"
	if job.workplace == &"":
		return ""
	if building_uid == &"":
		return "" if _free_workplace(job.workplace, resident_id) != &"" else "빈 %s 자리가 없음" % _def_name(job.workplace)
	var b: Dictionary = buildings.get(building_uid, {})
	if b.is_empty() or b["def_id"] != job.workplace or not b["completed"]:
		return "%s가 아님" % _def_name(job.workplace)
	if not resident_id in b["workers"] and b["workers"].size() >= building_capacity(building_uid):
		return "정원이 다 참"
	return ""


## Puts a resident on a job. Jobs with a workplace need a completed building of that type with a
## free slot; building_uid &"" picks the first one. 건설·개간 needs a construction site uid.
## TODO(C-11): 참여 조건 (이동 조건이면 경사로 없는 구역 작업장 배정 불가).
func assign_job(resident_id: StringName, job_id: StringName, building_uid: StringName = &"") -> bool:
	if job_block_reason(resident_id, job_id, building_uid) != "":
		return false
	var job := BaseDB.get_job(job_id)
	if building_uid == &"" and job.workplace != &"":
		building_uid = _free_workplace(job.workplace, resident_id)
	unassign_job(resident_id)
	residents[resident_id]["assignment"] = {"job": job_id, "building_id": building_uid}
	if buildings.has(building_uid):
		buildings[building_uid]["workers"].append(resident_id)
	return true


func unassign_job(resident_id: StringName) -> void:
	if not residents.has(resident_id):
		return
	var old: Dictionary = residents[resident_id]["assignment"]
	var uid: StringName = old.get("building_id", &"")
	if buildings.has(uid):
		buildings[uid]["workers"].erase(resident_id)
	residents[resident_id]["assignment"] = {"job": &"", "building_id": &""}


func job_of(resident_id: StringName) -> StringName:
	return residents.get(resident_id, {}).get("assignment", {}).get("job", &"")


## Expected output for one resident today, resource_id -> float (출격 준비·주민 상세 화면용).
## Ignores whether inputs (나무 → 목재판) are in stock.
func preview_output(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	var job := BaseDB.get_job(job_of(resident_id))
	if r.is_empty() or job == null or not WorkRules.can_work(r):
		return {}
	var f := WorkRules.efficiency(r, job, _works_alone(resident_id))
	var out := {}
	for res: StringName in job.base_output:
		out[res] = job.base_output[res] * f
	return out


## Evening settlement (A-05 calls this; docs/dev/contracts.md "하루 정산과 습격").
## Updates residents (hunger, fatigue, skills) and buildings (construction, generator fuel) and
## returns the report. Economy is NOT changed here: A applies report["changes"].
## Extra key "work": {resident_id: {"job": id, "output": {res: int}}} for the evening table (D-07).
## Stay day (SceneRouter.stayed_today, 기획 01·09): all work ×1.2 and the oldest construction site +20.
## Workshop / infirmary workers craft through Armory.craft_by_worker() (A-09, issue #45).
## TODO(C-06): morale factors, leave crisis. TODO(C-12): stay day deep talk +1.
func settle_day() -> Dictionary:
	var produced := {}
	var consumed := {}
	var events: Array = []
	var work := {}
	var ids := active_resident_ids()
	var stayed := SceneRouter.stayed_today
	var crafters: Array = []  # [resident_id, efficiency, workplace def id]

	# 1. Work: output, build progress, skill and stat growth.
	var worked := {}
	for id in ids:
		var r: Dictionary = residents[id]
		var job := BaseDB.get_job(job_of(id))
		if job == null or job.id == WorkRules.REST_JOB or not WorkRules.can_work(r):
			continue
		var uid: StringName = r["assignment"]["building_id"]
		if job.workplace != &"" and buildings.has(uid) and (not is_powered(uid) or buildings[uid]["damaged"]):
			continue  # workplace without power, or damaged by a raid, does not run
		var f := WorkRules.efficiency(r, job, _works_alone(id))
		if stayed:
			f *= WorkRules.STAY_OUTPUT_MULT
		var out := {}
		if job.workplace != &"" and not Armory.list_recipes(job.workplace, 1).is_empty():
			crafters.append([id, f, job.workplace])
		if job.id == WorkRules.CONSTRUCTION_JOB:
			if add_build_progress(uid, roundi(WorkRules.BUILD_PROGRESS_BASE * f)) and buildings.has(uid):
				events.append(_event(&"building_completed", id, "%s 완성" % _def_name(buildings[uid]["def_id"])))
			if buildings.has(uid) and buildings[uid]["completed"]:
				unassign_job(id)
		for res: StringName in job.base_output:
			out[res] = job.base_output[res] * f
		for res: StringName in job.base_input:
			consumed[res] = consumed.get(res, 0.0) + job.base_input[res] * f
		for res in out:
			produced[res] = produced.get(res, 0.0) + out[res]
		work[id] = {"job": job.id, "output": _rounded(out)}
		worked[id] = true
		_grow(id, job, events)

	# Stay day: the player builds too (09 "건설 규칙": 기지에 머무르면 +20) on the oldest site.
	if stayed:
		var site := _oldest_site()
		if site != &"" and add_build_progress(site, WorkRules.STAY_BUILD_PROGRESS):
			events.append(_event(&"building_completed", &"", "%s 완성" % _def_name(buildings[site]["def_id"])))

	# 2. Inputs that are not in stock reduce that job's output proportionally.
	_limit_inputs(produced, consumed)

	# 2b. Worker crafting (정비소: 탄약·소음 미끼, 의무실: 붕대·구급상자) via Armory.
	_craft(crafters, produced, consumed, work)

	# 3. Food: cooked meals if a cook worked today (식량 효율 ×1.5, 배고픔 +70).
	var cooked := false
	for id in work:
		if work[id]["job"] == &"cooking":
			cooked = true
	var food_left: float = float(Economy.get_amount(&"food")) + produced.get(&"food", 0.0)
	var eat_mult: float = BaseDB.get_job(&"cooking").effects.get(&"food_efficiency", 1.0) if cooked else 1.0
	var hungry: Array[StringName] = []
	for id in ids:
		var r: Dictionary = residents[id]
		var need: float = WorkRules.food_need(r) / eat_mult
		var ate: bool = food_left >= need
		if ate:
			food_left -= need
			consumed[&"food"] = consumed.get(&"food", 0.0) + need
		else:
			hungry.append(id)
		var gain: int = (WorkRules.COOKED_MEAL_HUNGER if cooked else WorkRules.MEAL_HUNGER) if ate else 0
		r["hunger"] = clampi(int(r["hunger"]) - WorkRules.HUNGER_PER_DAY + gain, 0, 100)
		var rested := job_of(id) == WorkRules.REST_JOB
		r["fatigue"] = clampi(int(r["fatigue"]) + WorkRules.fatigue_change(worked.has(id), rested, _sleep_recovery(id), r), 0, 100)
	if not hungry.is_empty():
		events.append(_event(&"food_short", &"", "식량이 모자라 %d명이 굶었다" % hungry.size()))

	# 4. Generator fuel (2/일, 겨울 3). No fuel → no power tomorrow.
	var fuel_left: float = float(Economy.get_amount(&"fuel")) + produced.get(&"fuel", 0.0)
	for uid in building_ids(&"generator"):
		var need: float = float(WorkRules.FUEL_PER_GENERATOR_WINTER) if GameState.season() == Enums.Season.WINTER \
			else BaseDB.get_building(&"generator").effect(&"fuel_per_day")
		buildings[uid]["fueled"] = fuel_left >= need
		if fuel_left >= need:
			fuel_left -= need
			consumed[&"fuel"] = consumed.get(&"fuel", 0.0) + need
		else:
			events.append(_event(&"no_fuel", &"", "연료가 없어 발전기가 멈췄다"))
	_refresh_power()

	# 5. Raid threat (10 "위협도"): T + 3 + 소음도 + 계절 − 2 × 전초기지 − 정찰.
	var before_threat := threat
	threat = clampi(roundi(threat + threat_delta()), 0, RaidRules.THREAT_MAX)

	var p := _rounded(produced)
	var c := _rounded(consumed)
	var changes := {}
	for res in p:
		changes[res] = p[res]
	for res in c:
		changes[res] = changes.get(res, 0) - c[res]
	for res in changes.keys():
		# Rounding must never ask Economy for more than it has: apply_detailed() refuses the whole
		# report if any amount would go below zero.
		var floor_change := -Economy.get_amount(res)
		if changes[res] < floor_change:
			c[res] = c.get(res, 0) - (floor_change - changes[res])
			changes[res] = floor_change
		if changes[res] == 0:
			changes.erase(res)
	return {
		## Extra keys besides the contract: "work" (주민별 산출), "threat" ({before, after}).
		"changes": changes,
		"produced": p,
		"consumed": c,
		"morale": {},
		"events": events,
		"work": work,
		"threat": {"before": before_threat, "after": threat},
	}


## Job skill +1 every 7 days on the same job (max 5), stat +1 every 10 work days (max 10).
func _grow(id: StringName, job: JobDef, events: Array) -> void:
	var r: Dictionary = residents[id]
	var days: int = r["job_days"].get(job.id, 0) + 1
	r["job_days"][job.id] = days
	if days % WorkRules.DAYS_PER_SKILL == 0 and int(r["job_skill"].get(job.id, 0)) < WorkRules.SKILL_MAX:
		r["job_skill"][job.id] = int(r["job_skill"].get(job.id, 0)) + 1
		events.append(_event(&"skill_up", id, "%s의 %s 숙련 %d" % [r["name"], job.display_name, r["job_skill"][job.id]]))
	var stat := job.main_stat_key()
	if stat == &"":
		return
	var stat_days: int = r["stat_days"].get(stat, 0) + 1
	r["stat_days"][stat] = stat_days
	if stat_days % WorkRules.DAYS_PER_STAT == 0 and int(r["stats"][stat]) < ResidentData.STAT_MAX:
		r["stats"][stat] = int(r["stats"][stat]) + 1
		events.append(_event(&"stat_up", id, "%s의 %s +1" % [r["name"], stat]))


## Each crafter makes roundi(efficiency × CRAFT_BATCHES_PER_DAY) batches (at least 1). Each batch
## takes the recipe (allowed at the facility's level) whose output is lowest in stock right now,
## so ammo types and supplies stay balanced (가안). Armory.craft_by_worker() limits by inputs.
func _craft(crafters: Array, produced: Dictionary, consumed: Dictionary, work: Dictionary) -> void:
	for entry in crafters:
		var id: StringName = entry[0]
		var facility: StringName = entry[2]
		var level := facility_level(facility)
		var recipes: Array[StringName] = []
		for recipe_id in Armory.list_recipes(facility, 1):
			if Armory.get_recipe(recipe_id).facility_level <= level:
				recipes.append(recipe_id)
		if recipes.is_empty():
			continue
		var made := {}
		for batch in maxi(roundi(float(entry[1]) * WorkRules.CRAFT_BATCHES_PER_DAY), 1):
			recipes.sort_custom(func(a: StringName, b: StringName) -> bool:
				return _stock(Armory.get_recipe(a).output_id, produced, consumed) \
					< _stock(Armory.get_recipe(b).output_id, produced, consumed))
			var done := false
			for recipe_id in recipes:
				var recipe := Armory.get_recipe(recipe_id)
				var stock := {}
				for res: StringName in recipe.inputs:
					stock[res] = floori(_stock(res, produced, consumed))
				var result := Armory.craft_by_worker(recipe_id, 1, stock)
				if int(result.get("count", 0)) <= 0:
					continue
				for res in result["produced"]:
					produced[res] = produced.get(res, 0.0) + result["produced"][res]
					made[res] = made.get(res, 0) + result["produced"][res]
				for res in result["consumed"]:
					consumed[res] = consumed.get(res, 0.0) + result["consumed"][res]
				done = true
				break
			if not done:
				break  # no inputs left for any recipe
		if work.has(id):
			work[id]["output"] = made


## Amount available right now during the settlement: storage + produced today − consumed today.
func _stock(res: StringName, produced: Dictionary, consumed: Dictionary) -> float:
	return Economy.get_amount(res) + float(produced.get(res, 0.0)) - float(consumed.get(res, 0.0))


func _oldest_site() -> StringName:
	for uid: StringName in buildings:  # insertion order = placement order
		if not buildings[uid]["completed"]:
			return uid
	return &""


## Scales down outputs of jobs whose inputs (목공: 나무) are short. Simple global ratio per input.
func _limit_inputs(produced: Dictionary, consumed: Dictionary) -> void:
	for res: StringName in consumed.keys():
		var have: float = float(Economy.get_amount(res)) + produced.get(res, 0.0)
		var want: float = consumed[res]
		if want <= have or want <= 0.0:
			continue
		var ratio: float = have / want
		consumed[res] = have
		for job_id: StringName in BaseDB.jobs():
			var job := BaseDB.get_job(job_id)
			if not job.base_input.has(res):
				continue
			for out_res: StringName in job.base_output:
				produced[out_res] = produced.get(out_res, 0.0) * ratio


func _sleep_recovery(id: StringName) -> int:
	var bed_id := String(residents[id]["bed_id"])
	if bed_id == "":
		return WorkRules.FATIGUE_NO_BED
	if bed_id.begins_with(START_BED_PREFIX):
		return WorkRules.FATIGUE_START_BED
	var uid := StringName(bed_id.get_slice("_bed_", 0))
	return roundi(building_effect(uid, &"fatigue_recovery", float(WorkRules.FATIGUE_START_BED)))


func _works_alone(id: StringName) -> bool:
	var uid: StringName = residents[id]["assignment"]["building_id"]
	return buildings.has(uid) and buildings[uid]["workers"].size() == 1


func _free_workplace(def_id: StringName, resident_id: StringName) -> StringName:
	for uid in building_ids(def_id):
		if resident_id in buildings[uid]["workers"] or buildings[uid]["workers"].size() < building_capacity(uid):
			return uid
	return &""


func _def_name(def_id: StringName) -> String:
	var def := BaseDB.get_building(def_id)
	return def.display_name if def else String(def_id)


static func _event(type: StringName, resident_id: StringName, text: String) -> Dictionary:
	return {"type": type, "resident_id": resident_id, "text": text}


static func _rounded(values: Dictionary) -> Dictionary:
	var out := {}
	for res in values:
		var n := roundi(values[res])
		if n != 0:
			out[res] = n
	return out


# --- Raids (Lane C, C-08) ------------------------------------------------------

## Today's threat change (10 "위협도"). Applied in settle_day().
func threat_delta() -> float:
	var season := GameState.season()
	var s := RaidRules.THREAT_SEASON if season == Enums.Season.SUMMER or season == Enums.Season.WINTER else 0.0
	var outposts := 0  # TODO(C-19): active outposts
	return RaidRules.THREAT_DAILY + base_noise() + s - RaidRules.THREAT_PER_OUTPOST * outposts - _scout_count()


## Rolls whether a raid comes now (A-05 at night, C-21 during the day). At most one raid a day,
## none before day 5. Emits raid_warning when one comes. Returns the contract Dictionary
## (docs/dev/contracts.md) plus "family" (Enums.Element) and "notice" (&"none" / &"morning" / &"day_before").
## `force` = debug (콘솔 raid now): skips the day/threat checks.
func roll_raid(time: Enums.RaidTime, force: bool = false) -> Dictionary:
	var day := GameState.day
	var raid := {"occurs": false, "raid_id": &"", "time": time, "type": &"", "directions": [],
		"strength": 0.0, "target": &"base", "warning_sec": 0.0, "family": Enums.Element.NONE, "notice": &"none"}
	var small := false
	if not force:
		if day < RaidRules.FIRST_RAID_DAY or last_raid_day == day:
			return raid
		var chance := RaidRules.raid_chance(time, threat)
		if _rng.randf() >= float(chance["chance"]):
			return raid
		small = chance["small"]
	var type := &"swarm" if small else RaidRules.pick_type(tier, _rng)
	var directions := RaidRules.pick_directions(type, _rng)
	var strength := RaidRules.strength(day, population(), tier,
		_rng.randf_range(RaidRules.STRENGTH_RANDOM_MIN, RaidRules.STRENGTH_RANDOM_MAX))
	strength *= float(Settings.get_value(&"raid_mult"))
	if small:
		strength *= RaidRules.SMALL_RAID_STRENGTH_MULT
	var has_post := not working_building_ids(&"guard_post").is_empty()
	raid["occurs"] = true
	raid["raid_id"] = StringName("raid_d%d_%s" % [day, "day" if time == Enums.RaidTime.DAY else "night"])
	raid["type"] = type
	raid["directions"] = directions
	raid["strength"] = snappedf(strength, 0.1)
	raid["family"] = RaidRules.TYPES[type]["family"]
	raid["small"] = small
	# TODO(C-19): 20% of raids target an outpost; outposts give a day-before notice.
	if time == Enums.RaidTime.DAY:
		raid["warning_sec"] = RaidRules.DAY_WARNING_SEC if has_post else 0.0
	elif has_post:
		raid["notice"] = &"day_before" if _keen_ear_guard() else &"morning"
	last_raid_day = day
	EventBus.raid_warning.emit(raid)
	return raid


## The raid begins (방어전 시작 or the auto judgment is about to run). Emits raid_started.
func start_raid(raid: Dictionary) -> void:
	active_raid = raid.duplicate(true)
	EventBus.raid_started.emit(raid)


## Total defense used by the automatic judgment, with its parts (for the raid screen D-14).
## Guards are residents on the 경비 job who can work; facilities count V_f × remaining durability.
func defense_breakdown() -> Dictionary:
	var guards := {}
	var total := 0.0
	for id in active_resident_ids():
		if job_of(id) != &"guard" or not WorkRules.can_work(residents[id]):
			continue
		var weapon := Armory.get_item_stats(Armory.get_equipped(id, Enums.EquipSlot.MAIN))
		var p := RaidRules.guard_power(residents[id], weapon, float(Armory.get_owner_summary(id)["defense"]))
		guards[id] = p
		total += p
	var facilities := {}
	for uid in working_building_ids():
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		if def.defense_value <= 0.0:
			continue
		var share := float(buildings[uid]["durability"]) / def.durability if def.durability > 0 else 1.0
		facilities[uid] = def.defense_value * clampf(share, 0.0, 1.0)
		total += facilities[uid]
	return {"total": total, "guards": guards, "facilities": facilities}


## Expected outcome band for the radio (A-14): R × [0.85, 1.15].
func predict_raid(raid: Dictionary) -> Dictionary:
	var strength := float(raid.get("strength", 0.0))
	if strength <= 0.0:
		strength = RaidRules.strength(GameState.day, population(), tier, 1.0)
	var ratio := float(defense_breakdown()["total"]) / strength
	return {
		"ratio_min": ratio * (1.0 - RaidRules.PREDICT_SPREAD),
		"ratio_max": ratio * (1.0 + RaidRules.PREDICT_SPREAD),
		"likely": RaidRules.outcome_for(ratio),
	}


## Automatic judgment (10 "자동 판정") and its damage. mode PLAYED = the player was at the base
## but chose 자동 판정으로 넘기기 (+20%). C-17's direct defense reports through the same format.
## Applies damage (buildings, residents, storage loss / loot via Economy.apply) and emits raid_resolved.
## Returns {"raid_id", "day", "time", "mode", "ratio", "outcome", "damage", "casualties", "loot", "summary"}.
func resolve_raid(raid: Dictionary, mode: Enums.RaidMode) -> Dictionary:
	var strength := maxf(float(raid.get("strength", 1.0)), 0.1)
	var defense := defense_breakdown()
	var ratio: float = defense["total"] / strength
	if mode == Enums.RaidMode.PLAYED:
		ratio *= RaidRules.PLAYED_BONUS
	var outcome := RaidRules.outcome_for(ratio)
	var guards: Array = defense["guards"].keys()
	var civilians: Array[StringName] = []
	var sheltered := has_completed(RaidRules.SHELTER) and RaidRules.ALARMS.any(func(a): return has_completed(a))
	if not sheltered:
		for id in active_resident_ids():
			if not id in guards:
				civilians.append(id)
	var damage := {"damaged": [], "durability_loss": {}, "resources_lost": {}}
	var casualties: Array = []
	var loot := {}
	var summary: Array[String] = []
	var where := _direction_text(raid.get("directions", []))
	summary.append("%s에서 마물이 몰려왔다 (강도 %.0f, 방어 %.1f)." % [where, strength, defense["total"]])

	match outcome:
		Enums.RaidOutcome.FLAWLESS:
			var material: StringName = RaidRules.FAMILY_MATERIAL.get(int(raid.get("family", Enums.Element.NONE)), &"")
			if material != &"":
				loot[material] = roundi(strength * RaidRules.FLAWLESS_LOOT_SHARE)
			# TODO(A-10): essences as loot too.
			summary.append("피해 없이 막아냈다.")
		Enums.RaidOutcome.WIN:
			for uid in working_building_ids():
				var def := BaseDB.get_building(buildings[uid]["def_id"])
				if def.durability > 0:
					var loss := roundi(def.durability * _rng.randf_range(RaidRules.WIN_DURABILITY_LOSS.x, RaidRules.WIN_DURABILITY_LOSS.y))
					buildings[uid]["durability"] = maxi(int(buildings[uid]["durability"]) - loss, 0)
					damage["durability_loss"][uid] = loss
			_hurt(guards, RaidRules.WIN_GUARD_INJURY, 0.0, 0.0, casualties)
			summary.append("벽과 시설이 조금 상했지만 막아냈다.")
		Enums.RaidOutcome.NARROW:
			_damage_buildings(RaidRules.NARROW_DAMAGED, damage)
			_hurt(guards, RaidRules.NARROW_GUARD_INJURY, 0.0, 0.0, casualties)
			_hurt(civilians, RaidRules.NARROW_CIVILIAN_INJURY, 0.0, 0.0, casualties)
			summary.append("간신히 버텼다. 시설 %d곳이 멈췄다." % damage["damaged"].size())
		Enums.RaidOutcome.LOSS:
			_damage_buildings(RaidRules.LOSS_DAMAGED, damage)
			for res: StringName in Economy.amounts:
				var n := floori(Economy.get_amount(res) * RaidRules.LOSS_STORAGE_SHARE)
				if Economy.uses_cap(res) and n > 0:
					damage["resources_lost"][res] = n
			_hurt(guards, 0.0, RaidRules.LOSS_GUARD_SERIOUS, RaidRules.LOSS_GUARD_DEATH, casualties)
			_hurt(civilians, 0.0, 0.0, RaidRules.LOSS_CIVILIAN_DEATH, casualties)
			for id in active_resident_ids():
				residents[id]["morale"] = clampi(int(residents[id]["morale"]) + RaidRules.LOSS_MORALE, 0, 100)
			summary.append("막지 못했다. 시설 %d곳이 부서지고 창고가 털렸다." % damage["damaged"].size())
	for c in casualties:
		summary.append("%s %s." % [residents[c["resident_id"]]["name"],
			{&"injured": "다침", &"serious": "크게 다침", &"dead": "목숨을 잃음"}[c["kind"]]])
	if summary.size() > 5:
		summary.resize(5)

	var economy_change := loot.duplicate()
	for res in damage["resources_lost"]:
		economy_change[res] = -int(damage["resources_lost"][res])
	if not economy_change.is_empty():
		Economy.apply(economy_change)
	threat = RaidRules.THREAT_AFTER_LOSS if outcome == Enums.RaidOutcome.LOSS else RaidRules.THREAT_AFTER_WIN
	_refresh_effects()
	var result := {
		"raid_id": raid.get("raid_id", &""), "day": GameState.day, "time": raid.get("time", Enums.RaidTime.NIGHT),
		"mode": mode, "ratio": snappedf(ratio, 0.01), "outcome": outcome, "damage": damage,
		"casualties": casualties, "loot": loot, "summary": summary,
	}
	active_raid = {}
	EventBus.raid_resolved.emit(result)
	return result


## Marks `count` random facilities as damaged (작동 정지). Beds, radio room, shelter are never hit.
func _damage_buildings(count: Vector2i, damage: Dictionary) -> void:
	var pool: Array[StringName] = []
	for uid in working_building_ids():
		if not buildings[uid]["def_id"] in RaidRules.INDESTRUCTIBLE:
			pool.append(uid)
	for i in mini(_rng.randi_range(count.x, count.y), pool.size()):
		var uid: StringName = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
		buildings[uid]["damaged"] = true
		damage["damaged"].append(uid)
		EventBus.building_damaged.emit(uid)
		buildings_changed.emit()


## Rolls injury / serious injury / death for each id. No permadeath (보호 모드) → serious injury.
func _hurt(ids: Array, injury: float, serious: float, death: float, casualties: Array) -> void:
	for id: StringName in ids:
		var roll := _rng.randf()
		var kind := &""
		if roll < death:
			kind = &"dead" if bool(Settings.get_value(&"permadeath")) else &"serious"
		elif roll < death + serious:
			kind = &"serious"
		elif roll < death + serious + injury:
			kind = &"injured"
		if kind == &"":
			continue
		casualties.append({"resident_id": id, "kind": kind})
		if kind == &"dead":
			_kill(id, &"raid")
		else:
			residents[id]["health"] = Enums.HealthState.INJURED
			residents[id]["recover_days"] = RaidRules.SERIOUS_INJURY_DAYS if kind == &"serious" else RaidRules.INJURY_DAYS
			unassign_job(id)


func _on_flow_state_changed(state: Enums.FlowState) -> void:
	if state == Enums.FlowState.BASE_STAY:
		# Deferred: SceneRouter is still inside its own transition when this signal fires.
		_roll_stay_day_raid.call_deferred()


## Stay day raid (10 "발생 규칙": 낮, 기지에 머무는 중, 위협도 70 이상 20%), issue #45.
## No direct defense yet (C-17), so the player-present automatic judgment (+20%) decides it.
## TODO(C-21): day raids during a sortie (60 s warning, emergency return, B-22).
func _roll_stay_day_raid() -> void:
	if SceneRouter.state() != Enums.FlowState.BASE_STAY:
		return
	var raid := roll_raid(Enums.RaidTime.DAY)
	if not raid["occurs"]:
		return
	if not SceneRouter.start_day_raid(raid):
		return
	start_raid(raid)
	resolve_raid(raid, Enums.RaidMode.PLAYED)
	SceneRouter.end_day_raid()


## TODO(C-20): funeral, grief, memorial, guardian succession.
func _kill(id: StringName, cause: StringName) -> void:
	unassign_job(id)
	release_bed(id)
	residents[id]["status"] = Enums.ResidentStatus.DEAD
	EventBus.resident_died.emit(id, cause)


func _scout_count() -> float:
	var g := 0.0
	for id in active_resident_ids():
		if job_of(id) == &"scouting" and WorkRules.can_work(residents[id]):
			var sense := int(residents[id]["stats"].get(&"sense", 0))
			g += RaidRules.SCOUT_BONUS_WEIGHT if sense >= RaidRules.SCOUT_SENSE_BONUS_AT else 1.0
	return g


func _keen_ear_guard() -> bool:
	for id in active_resident_ids():
		if job_of(id) == &"guard" and &"keen_ear" in residents[id]["traits"]:
			return true
	return false


static func _direction_text(directions: Array) -> String:
	var names := {&"north": "북쪽", &"east": "동쪽", &"south": "남쪽", &"west": "서쪽"}
	var parts := PackedStringArray()
	for d in directions:
		parts.append(names.get(StringName(d), String(d)))
	return "·".join(parts) if not parts.is_empty() else "어딘가"


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
	cleared_zones = {}
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
	last_raid_day = 0
	active_raid = {}
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
		"last_raid_day": last_raid_day,
		"cleared_zones": cleared_zones,
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
	last_raid_day = int(data.get("last_raid_day", 0))
	cleared_zones = {}
	for zone_id in data.get("cleared_zones", {}):
		cleared_zones[StringName(zone_id)] = true
	threat = int(data.get("threat", 0))
	tier = int(data.get("tier", Enums.BaseTier.CAMP)) as Enums.BaseTier
	_refresh_effects()
	buildings_changed.emit()


# --- Debug console (debug builds only) -----------------------------------------

func _register_debug_commands() -> void:
	DebugConsole.register(&"resident", _cmd_resident,
		"resident add [demo 1~3] | resident list - 주민 추가(무작위 또는 데모 구조자)·목록")
	DebugConsole.register(&"job", _cmd_job,
		"job <resident_id> <job_id> [building_uid] - 작업 배정 (job list: 직업 목록)")
	DebugConsole.register(&"settle", _cmd_settle,
		"settle - 하루 정산을 돌리고 Economy에 반영 (A-05 전 테스트용)")
	DebugConsole.register(&"zone", func(args: PackedStringArray) -> String:
		if args.size() >= 2 and args[0] == "clear":
			clear_zone(StringName(args[1]))
			return "개간 완료로 표시: %s" % args[1]
		return "zone clear <zone_id> - 구역을 개간된 것으로 (C-10 전 테스트용). 개간됨: %s" % [cleared_zones.keys()],
		"zone clear <zone_id> - 구역 개간 완료로 표시")
	DebugConsole.register(&"raid", _cmd_raid,
		"raid now [day|night] | raid threat <0~100> | raid info - 습격 강제·위협도 설정·방어력/예상")
	DebugConsole.register(&"build", _cmd_build,
		"build <building_id> | build list - 비용 없이 건물을 바로 완성 / 건물·전력·소음 목록")


func _cmd_job(args: PackedStringArray) -> String:
	if args.is_empty() or args[0] == "list":
		return "직업: " + ", ".join(PackedStringArray(BaseDB.jobs().keys()))
	if args.size() < 2:
		return "사용법: job <resident_id> <job_id> [building_uid]"
	var rid := StringName(args[0])
	var jid := StringName(args[1])
	var uid := StringName(args[2]) if args.size() > 2 else &""
	var reason := job_block_reason(rid, jid, uid)
	if reason != "":
		return "배정 불가: " + reason
	assign_job(rid, jid, uid)
	return "%s → %s (%s)" % [rid, jid, residents[rid]["assignment"]["building_id"]]


func _cmd_settle(_args: PackedStringArray) -> String:
	var report := settle_day()
	var applied := Economy.apply_detailed(report["changes"])
	var lines := PackedStringArray([
		"생산 %s" % report["produced"], "소비 %s" % report["consumed"],
		"변화 %s (반영 %s, 버림 %s)" % [report["changes"], applied["ok"], applied["discarded"]]])
	for e in report["events"]:
		lines.append("  · " + e["text"])
	return "\n".join(lines)


func _cmd_raid(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "info"
	match sub:
		"now":
			var time := Enums.RaidTime.DAY if args.size() > 1 and args[1] == "day" else Enums.RaidTime.NIGHT
			var raid := roll_raid(time, true)
			start_raid(raid)
			var result := resolve_raid(raid, Enums.RaidMode.AUTO)
			return "%s %s 강도 %.1f → %s (R %.2f)\n%s" % [raid["type"], raid["directions"], raid["strength"],
				Enums.RaidOutcome.keys()[result["outcome"]], result["ratio"], "\n".join(result["summary"])]
		"threat":
			if args.size() > 1:
				threat = clampi(int(args[1]), 0, RaidRules.THREAT_MAX)
			return "위협도 %d (내일 %+.1f)" % [threat, threat_delta()]
	var d := defense_breakdown()
	var p := predict_raid({})
	return "위협도 %d, 방어 %.1f (경비 %d명, 시설 %d), 예상 R %.2f~%.2f → %s" % [threat, d["total"],
		d["guards"].size(), d["facilities"].size(), p["ratio_min"], p["ratio_max"], Enums.RaidOutcome.keys()[p["likely"]]]


func _cmd_build(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "list"
	if sub == "list":
		var lines := PackedStringArray(["건물 %d개, 침상 %d, 전력 %.1f/%d, 소음도 %.1f, 창고 보너스 %d" % [
			buildings.size(), bed_count(), power_supply(), power_demand(), base_noise(), Economy.cap_bonus]])
		for uid: StringName in buildings:
			var b: Dictionary = buildings[uid]
			lines.append("  %s Lv%d %s%s" % [uid, b["level"], "완성" if b["completed"] else "건설 중 %d" % b["progress"],
				" (파손)" if b["damaged"] else ("" if b["powered"] else " (전력 없음)")])
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
