extends Node
## Emitted (by Colony itself) whenever buildings are placed, moved, completed, damaged or removed,
## and after loading. Building views (base/building) and Lane D screens redraw on it.
signal buildings_changed
## Emitted when a resident's trust changes (C-12). stage = TrustRules stage 0..4,
## reason = &"talk", &"gift", &"deep_talk", &"sortie_return", &"rescued" or the caller's tag.
signal trust_changed(resident_id: StringName, trust: int, stage: int, reason: StringName)
## Emitted when tonight's events are picked (C-14). Each: {event_id, participants, choices, night_day}.
## Lane D plays them with next_night_event() / resolve_night_event(choice).
signal night_events_ready(events: Array)
## 입주 의식 (C-13): a rescued survivor moved in and waits for the ceremony (D-13 opens it),
## and the ceremony ended (result = complete_arrival()'s Dictionary).
signal arrival_ready(resident_id: StringName)
signal arrival_completed(resident_id: StringName, result: Dictionary)
## Nickname or appearance changed (ResidentAgent redraws).
signal resident_profile_changed(resident_id: StringName)
## 아이 맞이 (C-15): a married couple wants a child (D asks "지금 / 나중에" and the method,
## then calls answer_child_wish), and a child joined a family (methods: Enums.ArrivalMethod).
signal child_wish(a: StringName, b: StringName, methods: Array)
signal child_arrived(child_id: StringName, method: int, parents: Array)
## 편견 이벤트 체인 (C-16): the rumor (D asks the player: PrejudiceRules.CHOICES), the incident
## (kind PrejudiceRules.INCIDENT_*), and one holder letting go of the prejudice.
signal prejudice_rumor(target_id: StringName, holder_ids: Array)
signal prejudice_incident(target_id: StringName, kind: StringName)
signal prejudice_resolved(holder_id: StringName, target_id: StringName)
## 고립·실종·사망·추모 (C-20): a stranded resident was not found in time, a funeral is shown this
## morning (D, then end_funeral()), and a child got a new guardian.
signal resident_missing(resident_id: StringName)
signal funeral_ready(resident_ids: Array)
signal guardian_changed(child_id: StringName, guardian_id: StringName)
## 전초기지 (C-19): built, garrison changed, damaged or repaired.
signal outposts_changed
## 직접 방어전 (C-17): the base scene should play this raid (DefenseBattle). first_wave 2 after an
## emergency return. It answers with finish_direct_defense() or skip_direct_defense().
signal defense_requested(raid: Dictionary, first_wave: int)
## The defence ends by a judgment instead (자동 판정으로 넘기기): the battle cleans up without a result.
signal defense_cancelled
## Autoload `Colony`. Owner: Lane C.
## Residents, buildings, relationships, raids threat - everything that lives in the base.
## Other lanes read through the getters below; they never edit resident data directly.
## Design reference: docs/design/07-residents.md .. 10-raids-defense.md

const SAVE_VERSION := 1
## 방송실 야영지 침낭 6자리 (docs/design/09-base-building.md "구역과 개간"). Buildings add more (C-04).
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
## Clearing progress (zone_id -> int) and zones whose one-time start cost is paid (C-10).
var clear_progress: Dictionary = {}
var clear_started: Dictionary = {}
## Day of the stay-day deep talk (하루 1번, C-12). 0 = none.
var deep_talk_day := 0
## Relation flags and days (C-14). RelationRules.pair_key(a, b) -> {a, b, flags: Array[int]
## (Enums.RelationFlag), since_day (연인이 된 날), last_day (마지막 교류), low_days (이별 카운트),
## engaged, wedding_ready, house_uid}.
var relation_meta: Dictionary = {}
## Day of the festival after a wedding (0 = none).
var festival_day := 0
## Night events: picked tonight, the one playing, and what happened (for the morning screen).
var night_queue: Array = []
var current_night_event: Dictionary = {}
var last_night_results: Array = []
var last_night_raid_day := 0
var _night_rolled_day := 0
## 편견 이벤트 체인 (C-16): target_id -> chain (see prejudice_chains()).
var prejudice_chains_data: Dictionary = {}
## 추모비에 새긴 이름 [{resident_id, name, day, cause}] and the funerals for tomorrow morning (C-20).
var memorials: Array = []
var funerals: Array = []
## 전초기지 (C-19): node_id -> outpost (see outpost_nodes()).
var outposts: Dictionary = {}
var _outpost_nodes_cache: Dictionary = {}
## 출격 중 낮 습격 (C-21): see field_day_raid().
var _field_raid: Dictionary = {}
var _emergency_requested := false
## The played defence in progress (C-17): {raid, first_wave, on_done}.
var _defense: Dictionary = {}
var _battle: Node = null

var _next_resident_num := 1
var _next_building_num := 1
var _power_supply := 0.0
var _power_demand := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SaveSystem.register_provider(&"colony", self)
	EventBus.rescue_completed.connect(_on_rescue_completed)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
	EventBus.sortie_ended.connect(_on_sortie_ended)
	EventBus.companion_stranded.connect(_on_companion_stranded)
	EventBus.emergency_return_requested.connect(_on_emergency_return)
	_reset()
	# DebugConsole loads after Colony and registers its placeholders in _ready; replace them after.
	_register_debug_commands.call_deferred()


## Field time for the day raid of this sortie (C-21). Pauses with the game.
func _process(delta: float) -> void:
	if GameState.flow_state == Enums.FlowState.FIELD:
		_advance_field_raid(delta)


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


## 인구 상한 = beds (야영지 6 + 침상·숙소 건물).
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

## Former job names for the "전직 … 주민 필요" reason (residents_screen has the full list).
const _JOB_REASON_NAMES := {&"doctor": "의사", &"nurse": "간호사", &"electrician": "전기기사", &"carpenter": "목수"}

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
	if def.story_only:
		reasons.append("이야기로만 생기는 건물")
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
		reasons.append("전직 %s 주민 필요" % _JOB_REASON_NAMES.get(def.requires_former_job, String(def.requires_former_job)))
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
	var zone := BaseDB.get_zone(zone_id)
	return cleared_zones.has(zone_id) or (zone != null and zone.starts_cleared)


## Can clearing of `zone_id` be worked on now? {"ok", "reasons"} (09 "구역과 개간", 해금 단계·비용).
func can_clear(zone_id: StringName) -> Dictionary:
	var zone := BaseDB.get_zone(zone_id)
	if zone == null:
		return {"ok": false, "reasons": ["알 수 없는 구역"]}
	var reasons: Array[String] = []
	if is_zone_cleared(zone_id):
		reasons.append("이미 개간됨")
	if tier < zone.unlock_tier:
		reasons.append("기지 단계 %s 필요" % Enums.BaseTier.keys()[zone.unlock_tier])
	if not clear_started.has(zone_id) and not zone.clear_cost.is_empty() and not Economy.can_afford(zone.clear_cost):
		reasons.append("시작 비용 부족: %s" % zone.clear_cost)
	return {"ok": reasons.is_empty(), "reasons": reasons}


## Pays the zone's one-time start cost (북쪽 숲: 비탈 계단) the first time someone is put on it.
func start_clearing(zone_id: StringName) -> bool:
	if not can_clear(zone_id)["ok"]:
		return false
	if not clear_started.has(zone_id):
		var zone := BaseDB.get_zone(zone_id)
		if not zone.clear_cost.is_empty() and not Economy.apply(_negated(zone.clear_cost)):
			return false
		clear_started[zone_id] = true
	return true


func clear_progress_of(zone_id: StringName) -> int:
	return int(clear_progress.get(zone_id, 0))


## One worker's clearing day: progress, 묻힌 상자 roll, and the yield when the zone is done.
func _clear_work(resident_id: StringName, zone_id: StringName, amount: int, produced: Dictionary, events: Array) -> void:
	var zone := BaseDB.get_zone(zone_id)
	if is_zone_cleared(zone_id):
		unassign_job(resident_id)
		return
	clear_progress[zone_id] = clear_progress_of(zone_id) + maxi(amount, 0)
	if _rng.randf() < TierRules.BURIED_BOX_CHANCE:
		var box := _buried_box()
		for res in box["resources"]:
			produced[res] = produced.get(res, 0.0) + box["resources"][res]
		if box["blueprint"] != &"":
			GameState.set_flag(box["blueprint"])
		events.append(_event(&"buried_box", resident_id, "%s에서 묻힌 상자를 찾았다: %s" % [zone.display_name, box["text"]]))
	if clear_progress_of(zone_id) >= zone.clear_work:
		cleared_zones[zone_id] = true
		for res: StringName in zone.clear_yield:
			produced[res] = produced.get(res, 0.0) + zone.clear_yield[res]
		events.append(_event(&"zone_cleared", resident_id, "%s 개간 완료" % zone.display_name))
		for id: StringName in residents:
			if residents[id]["assignment"]["building_id"] == zone_id:
				unassign_job(id)
		buildings_changed.emit()


func _buried_box() -> Dictionary:
	if _rng.randf() < TierRules.BURIED_BOX_BLUEPRINT_CHANCE:
		var pool: Array[StringName] = []
		for flag in TierRules.BURIED_BOX_BLUEPRINTS:
			if not GameState.has_flag(flag):
				pool.append(flag)
		if not pool.is_empty():
			var flag: StringName = pool[_rng.randi_range(0, pool.size() - 1)]
			return {"resources": {}, "blueprint": flag, "text": "설계도 (%s)" % flag}
	var n := _rng.randi_range(TierRules.BURIED_BOX_PARTS.x, TierRules.BURIED_BOX_PARTS.y)
	return {"resources": {&"parts": n}, "blueprint": &"", "text": "부품 %d" % n}


# --- Base tier and facility levels (C-10) -------------------------------------

## What the next tier still needs: {"tier": next or -1, "ok": bool, "missing": Array[String]}.
func next_tier_status() -> Dictionary:
	if tier >= Enums.BaseTier.FORTRESS:
		return {"tier": -1, "ok": false, "missing": []}
	var next := tier + 1
	var req: Dictionary = TierRules.REQUIREMENTS[next]
	var missing: Array[String] = []
	if population() < int(req["population"]):
		missing.append("인구 %d/%d" % [population(), req["population"]])
	for def_id: StringName in req["buildings"]:
		var have := working_building_ids(def_id).size()
		if have < int(req["buildings"][def_id]):
			missing.append("%s %d/%d" % [_def_name(def_id), have, req["buildings"][def_id]])
	for zone_id: StringName in req["zones"]:
		if not is_zone_cleared(zone_id):
			var zone := BaseDB.get_zone(zone_id)
			missing.append("%s 개간" % (zone.display_name if zone else String(zone_id)))
	if req["powered_generator"] and not _generator_running():
		missing.append("발전기 가동")
	return {"tier": next, "ok": missing.is_empty(), "missing": missing}


## Highest facility level allowed now (캐프 1, 정착지 2, 요새 3). A-09 caps upgrades with it.
func facility_level_cap() -> int:
	return TierRules.level_cap(tier)


## Can `uid` go up one level? {"ok", "reasons", "cost"} (09: Lv2 = ×2 + 부품 5, Lv3 = ×3 + 희귀 부품 3).
func can_upgrade(uid: StringName) -> Dictionary:
	var b := get_building(uid)
	if b.is_empty():
		return {"ok": false, "reasons": ["건물 없음"], "cost": {}}
	var def := BaseDB.get_building(b["def_id"])
	var next := int(b["level"]) + 1
	var cost := def.cost_for_level(next) if next <= BuildingDef.MAX_LEVEL else {}
	var reasons: Array[String] = []
	if not b["completed"] or b["damaged"]:
		reasons.append("완성되고 멀쩡한 건물만")
	if next > BuildingDef.MAX_LEVEL:
		reasons.append("최고 레벨")
	elif next > facility_level_cap():
		reasons.append("기지 단계가 오르면 Lv%d 가능" % next)
	elif not Economy.can_afford(cost):
		reasons.append("자원 부족")
	return {"ok": reasons.is_empty(), "reasons": reasons, "cost": cost}


func upgrade_building(uid: StringName) -> bool:
	var check := can_upgrade(uid)
	if not check["ok"] or not Economy.apply(_negated(check["cost"])):
		return false
	buildings[uid]["level"] = int(buildings[uid]["level"]) + 1
	var paid: Dictionary = buildings[uid]["paid"]
	for res in check["cost"]:
		paid[res] = int(paid.get(res, 0)) + int(check["cost"][res])
	_refresh_effects()
	buildings_changed.emit()
	return true


func _generator_running() -> bool:
	for uid in working_building_ids(&"generator"):
		if buildings[uid]["fueled"]:
			return true
	return false


## Raises the tier when the next one's conditions hold (checked every evening).
func _check_tier(events: Array) -> void:
	var status := next_tier_status()
	if not status["ok"]:
		return
	tier = int(status["tier"]) as Enums.BaseTier
	var names := ["캐프", "정착지", "요새"]
	events.append(_event(&"tier_up", &"", "기지가 %s(으)로 성장했다" % names[tier]))
	EventBus.notification_posted.emit("기지가 %s(으)로 성장했다" % names[tier], &"info")
	_refresh_effects()
	buildings_changed.emit()


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
		"repair_progress": -1,
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
	b["repair_progress"] = int(b.get("repair_progress", -1))
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
	if reason == "" and job != null and job.combat_role and is_pregnant(resident_id):
		reason = "출산을 기다리는 중 (경비 배정 불가)"
	if reason != "":
		return reason
	# 언어 조건: 무전·외교는 통역 무전기가 있어야 (07 "참여 조건", C-11).
	if job_id == &"radio" and Enums.AccessNeed.LANGUAGE in r["access_needs"] \
			and working_building_ids(&"interpreter_radio").is_empty():
		return "통역 무전기가 있어야 무전을 맡을 수 있음"
	if job_id == WorkRules.CONSTRUCTION_JOB:
		if BaseDB.get_zone(building_uid) != null:  # 개간 (C-10)
			var clear := can_clear(building_uid)
			if not clear["ok"]:
				return ", ".join(PackedStringArray(clear["reasons"]))
			return access_block_reason(resident_id, building_uid)
		var site: Dictionary = buildings.get(building_uid, {})
		if site.is_empty():
			return "건설 현장·수리할 건물·개간할 구역을 골라야 함"
		if site["completed"] and not _needs_maintenance(building_uid):
			return "할 일이 없는 건물 (파손되면 먼저 수리 시작, 벽은 내구도가 줄면)"
		return access_block_reason(resident_id, site["zone_id"])
	if job.workplace == &"":
		return ""
	if building_uid == &"":
		if _free_workplace(job.workplace, resident_id) != &"":
			return ""
		if _free_workplace(job.workplace, resident_id, false) != &"":
			return "갈 수 있는 %s 자리가 없음 (경사로·승강기 필요)" % _def_name(job.workplace)
		return "빈 %s 자리가 없음" % _def_name(job.workplace)
	var b: Dictionary = buildings.get(building_uid, {})
	if b.is_empty() or b["def_id"] != job.workplace or not b["completed"]:
		return "%s가 아님" % _def_name(job.workplace)
	if not resident_id in b["workers"] and b["workers"].size() >= building_capacity(building_uid):
		return "정원이 다 참"
	return access_block_reason(resident_id, b["zone_id"])


## Puts a resident on a job. Jobs with a workplace need a completed building of that type with a
## free slot; building_uid &"" picks the first one. 건설·개간 needs a construction site uid.
## TODO(C-11): 참여 조건 (이동 조건이면 경사로 없는 구역 작업장 배정 불가).
func assign_job(resident_id: StringName, job_id: StringName, building_uid: StringName = &"") -> bool:
	if job_block_reason(resident_id, job_id, building_uid) != "":
		return false
	var job := BaseDB.get_job(job_id)
	if building_uid == &"" and job.workplace != &"":
		building_uid = _free_workplace(job.workplace, resident_id)
	if job_id == WorkRules.CONSTRUCTION_JOB and BaseDB.get_zone(building_uid) != null:
		if not start_clearing(building_uid):
			return false
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
	var f := WorkRules.efficiency(r, job, _works_alone(resident_id)) * access_multiplier(resident_id)
	var out := {}
	for res: StringName in job.base_output:
		out[res] = job.base_output[res] * f * WorkRules.pace
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
	# 결혼식 다음 날 축제 (C-14): no work today, ×1.1 the day after.
	var festival := is_festival_today()
	var after_festival := festival_day > 0 and festival_day + 1 == GameState.day
	if festival:
		events.append(_event(&"festival", &"", "결혼 축제: 오늘은 모두 쉬며 즐겼다"))

	# 1. Work: output, build progress, skill and stat growth.
	var worked := {}
	for id in ids:
		if festival:
			break
		var r: Dictionary = residents[id]
		var job := BaseDB.get_job(job_of(id))
		if job == null or job.id == WorkRules.REST_JOB or not WorkRules.can_work(r):
			continue
		var uid: StringName = r["assignment"]["building_id"]
		if job.workplace != &"" and buildings.has(uid) and (not is_powered(uid) or buildings[uid]["damaged"]):
			continue  # workplace without power, or damaged by a raid, does not run
		if access_block_reason(id, _work_zone(id)) != "":
			continue  # 갈 수 없게 됨 (경사로가 부서지거나 철거됨)
		var f := WorkRules.efficiency(r, job, _works_alone(id)) * access_multiplier(id) * _best_friend_mult(id) * _pregnancy_mult(id, job) * _grief_mult(id)
		if stayed:
			f *= WorkRules.STAY_OUTPUT_MULT
		if after_festival:
			f *= RelationRules.FESTIVAL_NEXT_DAY_MULT
		var out := {}
		if job.workplace != &"" and not Armory.list_recipes(job.workplace, 1).is_empty():
			crafters.append([id, f, job.workplace])
		if job.id == WorkRules.CONSTRUCTION_JOB and BaseDB.get_zone(uid) != null:
			_clear_work(id, uid, roundi(TierRules.CLEAR_PROGRESS_BASE * f), produced, events)
		elif job.id == WorkRules.CONSTRUCTION_JOB and buildings.has(uid) and buildings[uid]["completed"]:
			_maintenance_work(id, uid, f, events)
		elif job.id == WorkRules.CONSTRUCTION_JOB:
			if add_build_progress(uid, roundi(WorkRules.build_progress() * f)) and buildings.has(uid):
				events.append(_event(&"building_completed", id, "%s 완성" % _def_name(buildings[uid]["def_id"])))
			if buildings.has(uid) and buildings[uid]["completed"]:
				unassign_job(id)
		for res: StringName in job.base_output:
			out[res] = job.base_output[res] * f * WorkRules.pace
		for res: StringName in job.base_input:
			consumed[res] = consumed.get(res, 0.0) + job.base_input[res] * f
		for res in out:
			produced[res] = produced.get(res, 0.0) + out[res]
		work[id] = {"job": job.id, "output": _rounded(out)}
		worked[id] = true
		_grow(id, job, events)

	# Stay day: the player builds too (09 "건설 규칙": 기지에 머무르면 +20) on the oldest site.
	if stayed and not festival:
		var site := _oldest_site()
		if site != &"" and add_build_progress(site, WorkRules.stay_build_progress()):
			events.append(_event(&"building_completed", &"", "%s 완성" % _def_name(buildings[site]["def_id"])))

	# 2. Inputs that are not in stock reduce that job's output proportionally.
	_limit_inputs(produced, consumed)

	# 2b. Worker crafting (정비소: 탄약·소음 미끼, 의무실: 붕대·구급상자) via Armory.
	_craft(crafters, produced, consumed, work)

	# 3. Food: cooked meals if a cook worked today (식량 효율 ×1.5, 배고픔 +70).
	var cooked := false
	var ate_cooked := {}
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
		if ate and cooked:
			ate_cooked[id] = true
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
	# 전초기지 유지비와 채집 (C-19).
	_settle_outposts(produced, consumed, events)

	# 3b. Health and morale (C-06): 07 "상태와 필요", 사기 요인 표, 떠날 위기.
	_settle_health(consumed, events)
	_settle_relations(worked)
	_settle_children(events)
	_settle_prejudice(events)
	_settle_loss(events)
	var morale := _settle_morale(ids, ate_cooked, events)

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

	# 4b. Base tier (09 "기지 단계").
	_check_tier(events)

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
		"morale": morale,
		"events": events,
		"work": work,
		"threat": {"before": before_threat, "after": threat},
	}


## Job skill +1 every 7 days on the same job (max 5), stat +1 every 10 work days (max 10).
func _grow(id: StringName, job: JobDef, events: Array) -> void:
	var r: Dictionary = residents[id]
	var days: int = r["job_days"].get(job.id, 0) + 1
	r["job_days"][job.id] = days
	if days % WorkRules.days_per_skill() == 0 and int(r["job_skill"].get(job.id, 0)) < WorkRules.SKILL_MAX:
		r["job_skill"][job.id] = int(r["job_skill"].get(job.id, 0)) + 1
		events.append(_event(&"skill_up", id, "%s의 %s 숙련 %d" % [r["name"], job.display_name, r["job_skill"][job.id]]))
	var stat := job.main_stat_key()
	if stat == &"":
		return
	var stat_days: int = r["stat_days"].get(stat, 0) + 1
	r["stat_days"][stat] = stat_days
	if stat_days % WorkRules.days_per_stat() == 0 and int(r["stats"][stat]) < ResidentData.STAT_MAX:
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


## First building of `def_id` with a free slot. check_access: only ones the resident can reach (C-11).
func _free_workplace(def_id: StringName, resident_id: StringName, check_access: bool = true) -> StringName:
	for uid in building_ids(def_id):
		if check_access and access_block_reason(resident_id, buildings[uid]["zone_id"]) != "":
			continue
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


# --- Repair and defense upkeep (Lane C, C-18) ---------------------------------------

## Repair cost of a damaged building: 30% of its current-level cost (10 "수리").
func repair_cost(uid: StringName) -> Dictionary:
	var b := get_building(uid)
	if b.is_empty():
		return {}
	var cost := {}
	var full := BaseDB.get_building(b["def_id"]).cost_for_level(int(b["level"]))
	for res in full:
		cost[res] = ceili(int(full[res]) * RaidRules.REPAIR_COST_SHARE)
	return cost


func can_repair(uid: StringName) -> Dictionary:
	var b := get_building(uid)
	var reasons: Array[String] = []
	if b.is_empty() or not b["damaged"]:
		reasons.append("파손된 건물이 아님")
	elif int(b["repair_progress"]) >= 0:
		reasons.append("이미 수리 중")
	elif not Economy.can_afford(repair_cost(uid)):
		reasons.append("자원 부족")
	return {"ok": reasons.is_empty(), "reasons": reasons, "cost": repair_cost(uid)}


## Pays the repair cost; then a 건설·개간 worker on this building does the work (건설 진행도 50%).
func start_repair(uid: StringName) -> bool:
	if not can_repair(uid)["ok"] or not Economy.apply(_negated(repair_cost(uid))):
		return false
	buildings[uid]["repair_progress"] = 0
	buildings_changed.emit()
	return true


## Work needed to finish a repair (09 진행도 × 50%).
func repair_work_needed(uid: StringName) -> int:
	return ceili(BaseDB.get_building(buildings[uid]["def_id"]).build_work_needed() * RaidRules.REPAIR_WORK_SHARE)


## A completed building a construction worker can work on: a started repair, or a defense
## structure that lost durability (벽 내구도는 저절로 회복되지 않음).
func _needs_maintenance(uid: StringName) -> bool:
	var b := get_building(uid)
	if b.is_empty() or not b["completed"]:
		return false
	if b["damaged"]:
		return int(b["repair_progress"]) >= 0
	var def := BaseDB.get_building(b["def_id"])
	return def.durability > 0 and int(b["durability"]) < def.durability


func _maintenance_work(resident_id: StringName, uid: StringName, f: float, events: Array) -> void:
	var b: Dictionary = buildings[uid]
	var def := BaseDB.get_building(b["def_id"])
	if b["damaged"] and int(b["repair_progress"]) >= 0:
		b["repair_progress"] = int(b["repair_progress"]) + roundi(WorkRules.build_progress() * f)
		if b["repair_progress"] >= repair_work_needed(uid):
			b["damaged"] = false
			b["repair_progress"] = -1
			b["durability"] = def.durability
			events.append(_event(&"repaired", resident_id, "%s 수리 완료" % def.display_name))
			unassign_job(resident_id)
			_refresh_effects()
			buildings_changed.emit()
	elif not b["damaged"] and def.durability > 0:
		b["durability"] = mini(int(b["durability"]) + roundi(RaidRules.WALL_REPAIR_PER_DAY * f), def.durability)
		if b["durability"] >= def.durability:
			unassign_job(resident_id)
		buildings_changed.emit()
	else:
		unassign_job(resident_id)


## Low essences in storage (정수 등불 연료).
func _low_essence_total() -> int:
	var n := 0
	for id in RaidRules.LOW_ESSENCES:
		n += Economy.get_amount(id)
	return n


## Takes `count` low essences, from the largest stack first. Returns what was taken.
func _take_low_essences(count: int) -> Dictionary:
	var taken := {}
	var ids := RaidRules.LOW_ESSENCES.duplicate()
	for i in count:
		ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			return Economy.get_amount(a) - int(taken.get(a, 0)) > Economy.get_amount(b) - int(taken.get(b, 0)))
		var best: StringName = ids[0]
		if Economy.get_amount(best) - int(taken.get(best, 0)) <= 0:
			break
		taken[best] = int(taken.get(best, 0)) + 1
	return taken


# --- Raids (Lane C, C-08) ------------------------------------------------------

## Today's threat change (10 "위협도"). Applied in settle_day().
func threat_delta() -> float:
	var season := GameState.season()
	var s := RaidRules.THREAT_SEASON if season == Enums.Season.SUMMER or season == Enums.Season.WINTER else 0.0
	var active := active_outposts().size()  # 가동 중인 전초기지 (C-19)
	return RaidRules.THREAT_DAILY + base_noise() + s - RaidRules.THREAT_PER_OUTPOST * active - _scout_count()


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
		if not RaidRules.RAIDS or day < RaidRules.FIRST_RAID_DAY or last_raid_day == day:
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
	# 전초기지 (C-19): 20% of raids go for an active outpost instead of the base.
	var active := active_outposts()
	if not active.is_empty() and _rng.randf() < OutpostRules.RAID_TARGET_CHANCE:
		var node_id: StringName = active[_rng.randi_range(0, active.size() - 1)]
		raid["target"] = node_id
		if outposts[node_id]["direction"] != &"":
			raid["directions"] = [outposts[node_id]["direction"]]
	# An outpost facing the raid warns a day ahead with size and family (10 "예고").
	var watched := false
	for d in raid["directions"]:
		if d in outpost_directions():
			watched = true
	raid["outpost_warned"] = watched
	if time == Enums.RaidTime.DAY:
		raid["warning_sec"] = RaidRules.DAY_WARNING_SEC if has_post or watched else 0.0
	elif watched:
		raid["notice"] = &"day_before"
	elif has_post:
		raid["notice"] = &"day_before" if _keen_ear_guard() else &"morning"
	last_raid_day = day
	if time == Enums.RaidTime.NIGHT:
		last_night_raid_day = day
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
	var lamp_fuel := _low_essence_total()
	for uid in working_building_ids():
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		if def.defense_value <= 0.0:
			continue
		if def.effects.has(&"essence_per_raid"):  # 정수 등불: only lamps that can be fed this raid
			var need := int(def.effect(&"essence_per_raid"))
			if lamp_fuel < need:
				continue
			lamp_fuel -= need
		if def.power_use_at(int(buildings[uid]["level"])) > 0 and not buildings[uid]["powered"]:
			continue  # 조명탑 without power
		var share := float(buildings[uid]["durability"]) / def.durability if def.durability > 0 else 1.0
		facilities[uid] = def.defense_value * clampf(share, 0.0, 1.0)
		total += facilities[uid]
	return {"total": total, "guards": guards, "facilities": facilities}


## Expected outcome band for the radio (A-14): R × [0.85, 1.15].
func predict_raid(raid: Dictionary) -> Dictionary:
	var strength := float(raid.get("strength", 0.0))
	if strength <= 0.0:
		strength = RaidRules.strength(GameState.day, population(), tier, 1.0)
	var ratio := float(defense_breakdown()["total"]) / (strength * raid_strength_mult(raid))
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
	if outposts.has(StringName(raid.get("target", &"base"))):
		return _resolve_outpost_raid(raid, mode)  # 전초기지 습격 (C-19)
	# 경보 카드의 "자동 판정으로 넘기기" (D-14 RaidFlow.choose) while this raid's defence is set up:
	# the battle steps down and this judgment ends the defence (its on_done runs after the result).
	var pending := {}
	if not _defense.is_empty() and StringName(_defense["raid"].get("raid_id", &"")) == StringName(raid.get("raid_id", &"")):
		pending = _defense
		_defense = {}
		defense_cancelled.emit()
	var strength := maxf(float(raid.get("strength", 1.0)), 0.1)
	strength *= raid_strength_mult(raid)
	var defense := defense_breakdown()
	var used := _use_defense_consumables()
	var ratio: float = defense["total"] / strength
	if mode == Enums.RaidMode.PLAYED:
		ratio *= RaidRules.PLAYED_BONUS
	var outcome := RaidRules.outcome_for(ratio)
	var guards: Array = defense["guards"].keys()
	var civilians: Array[StringName] = []
	var sheltered := has_completed(RaidRules.SHELTER) and RaidRules.ALARMS.any(func(a): return has_completed(a))
	# 청각 조건: without a visual alarm (경광등) they hear the warning late and miss the shelter (C-11).
	var visual_alarm := hearing_alarm()
	for id in active_resident_ids():
		if id in guards:
			continue
		var hears: bool = visual_alarm or not Enums.AccessNeed.HEARING in residents[id]["access_needs"]
		if not (sheltered and hears):
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
				if def.durability > 0 and not def.effects.has(&"trap_damage") and not def.effects.has(&"single_use"):  # traps count uses
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
		"mode": mode, "ratio": snappedf(ratio, 0.01), "outcome": outcome, "damage": damage, "used": used,
		"casualties": casualties, "loot": loot, "summary": summary,
	}
	active_raid = {}
	EventBus.raid_resolved.emit(result)
	if not pending.is_empty():
		pending["on_done"].call()
	return result


## Strength multiplier from defense facilities: 소음 미끼 −10% each (max −30%), and an unlit
## 안개 습격 (no working 조명탑) +20%.
func raid_strength_mult(raid: Dictionary) -> float:
	# 전초기지: −25% for the share of the raid's directions an active outpost faces (C-19).
	var dirs: Array = raid.get("directions", [])
	var covered := 0
	for d in dirs:
		if StringName(d) in outpost_directions():
			covered += 1
	var outpost_mult := 1.0 - OutpostRules.DIRECTION_CUT * (float(covered) / dirs.size()) if not dirs.is_empty() else 1.0
	return outpost_mult * _facility_strength_mult(raid)


## 소음 미끼 −10% each (max −30%), unlit 안개 습격 +20% (C-18).
func _facility_strength_mult(raid: Dictionary) -> float:
	var decoys := 0
	for uid in working_building_ids(&"noise_decoy"):
		decoys += 1
	var mult := 1.0 - minf(decoys * BaseDB.get_building(&"noise_decoy").effect(&"raid_strength_cut", 0.1), RaidRules.DECOY_CUT_MAX)
	if StringName(raid.get("type", &"")) == &"fog":
		var lit := false
		for uid in working_building_ids(&"light_tower"):
			if buildings[uid]["powered"]:
				lit = true
		if not lit:
			mult *= RaidRules.FOG_UNLIT_STRENGTH_MULT
	return mult


## After a raid: decoys are spent (removed), each trap loses one use (0 → damaged, needs repair),
## lamps burn their essence. Returns {"decoys": n, "traps": n, "essence": {id: n}}.
func _use_defense_consumables() -> Dictionary:
	var used := {"decoys": 0, "traps": 0, "essence": {}}
	for uid in working_building_ids(&"noise_decoy"):
		buildings.erase(uid)
		used["decoys"] += 1
	for uid in working_building_ids(&"spike_trap"):
		buildings[uid]["durability"] = maxi(int(buildings[uid]["durability"]) - 1, 0)
		used["traps"] += 1
		if buildings[uid]["durability"] <= 0:
			buildings[uid]["damaged"] = true
	for uid in working_building_ids(&"essence_lamp"):
		var need := int(BaseDB.get_building(&"essence_lamp").effect(&"essence_per_raid"))
		if _low_essence_total() < need:
			continue
		var taken := _take_low_essences(need)
		Economy.apply(_negated(taken))
		for id in taken:
			used["essence"][id] = int(used["essence"].get(id, 0)) + int(taken[id])
	if used["decoys"] > 0 or used["traps"] > 0:
		_refresh_effects()
		buildings_changed.emit()
	return used


## Marks `count` random facilities as damaged (작동 정지). Beds, radio room, shelter are never hit.
## Buildings in an indoor zone with raid_damage_mult < 1 (실내 구역 −50%, 지금 지도에는 없음) are skipped that often.
func _damage_buildings(count: Vector2i, damage: Dictionary) -> void:
	var pool: Array[StringName] = []
	for uid in working_building_ids():
		var zone := BaseDB.get_zone(buildings[uid]["zone_id"])
		if zone != null and zone.raid_damage_mult < 1.0 and _rng.randf() >= zone.raid_damage_mult:
			continue
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
	elif state == Enums.FlowState.NIGHT:
		# Deferred: the router rolls the night raid right after entering NIGHT.
		_roll_tonight.call_deferred()
	elif state == Enums.FlowState.FIELD:
		_roll_field_day_raid.call_deferred()  # C-21
	elif state == Enums.FlowState.BASE_DAY_RAID:
		_play_field_day_raid.call_deferred()  # C-21: back by the emergency return
	elif state == Enums.FlowState.BASE_MORNING:
		_field_raid = {}
		_finish_night()
		if not funerals.is_empty():
			funeral_ready.emit(pending_funeral())


## Stay day raid (10 "발생 규칙": 낮, 기지에 머무는 중, 위협도 70 이상 20%), issue #45.
## No direct defense yet (C-17), so the player-present automatic judgment (+20%) decides it.
## Day raids during a sortie are C-21 (_roll_field_day_raid, _advance_field_raid).
func _roll_stay_day_raid() -> void:
	if SceneRouter.state() != Enums.FlowState.BASE_STAY:
		return
	var raid := roll_raid(Enums.RaidTime.DAY)
	if not raid["occurs"]:
		return
	if not SceneRouter.start_day_raid(raid):
		return
	start_raid(raid)
	# Played on the base map from wave 1 (C-17); falls back to the +20% judgment without a base scene.
	begin_direct_defense(raid, 1, SceneRouter.end_day_raid)


# --- 직접 방어전 (C-17, 10 "직접 방어전") -----------------------------------------------------
## Colony asks the base scene for a played defence (defense_requested). The base scene (C-17
## DefenseBattle) runs the waves with Lane B's combat parts and reports back with
## finish_direct_defense() or skip_direct_defense() (자동 판정으로 넘기기, +20%). Without a base scene
## listening (headless, tests) the player-present judgment decides at once.

## The defence being played: {} = none, else {"raid", "first_wave"}.
func direct_defense() -> Dictionary:
	return {"raid": _defense["raid"], "first_wave": _defense["first_wave"]} if not _defense.is_empty() else {}


## Starts a played defence of `raid` (already started with start_raid). `on_done` runs after the result.
## A (night raids, SceneRouter) can call this instead of resolve_raid(AUTO) to let the player fight.
func begin_direct_defense(raid: Dictionary, first_wave: int, on_done: Callable) -> void:
	if not RaidRules.DIRECT_DEFENSE:
		resolve_raid(raid, Enums.RaidMode.AUTO)  # 방어전 꺼짐: 자동 판정
		on_done.call()
		return
	if defense_requested.get_connections().is_empty():
		resolve_raid(raid, Enums.RaidMode.PLAYED)
		on_done.call()
		return
	_defense = {"raid": raid, "first_wave": first_wave, "on_done": on_done}
	defense_requested.emit(raid, first_wave)


## D-14 경보 카드의 "직접 방어" (RaidFlow.choose). The battle is already set up for a raid Colony
## began (its prep waits while the card is open); otherwise this starts one. Returns true.
func start_defense(raid: Dictionary) -> bool:
	if not RaidRules.DIRECT_DEFENSE:
		return false
	if not _defense.is_empty() and StringName(_defense["raid"].get("raid_id", &"")) == StringName(raid.get("raid_id", &"")):
		return true
	if active_raid.is_empty():
		start_raid(raid)
	begin_direct_defense(raid, 1, func() -> void: pass)
	return true


## D-14 방어전 HUD (RaidDefenseHud pulls it every frame): {} without a battle, else
## {wave, waves, phase (&"prep" / &"fight" / &"done"), time_left, prep_sec, hold_left, monsters_left,
##  shelter_door {hp, max}, traps {ready, total}, guards [{id, name, power, spot, down}],
##  spots [{id, name, kind (&"post" / &"gate" / &"shelter"), cap}]}.
func defense_state() -> Dictionary:
	return _battle.call(&"hud_state") if is_instance_valid(_battle) else {}


## D-14: move a guard to another spot between waves (spot id from defense_state()["spots"]).
## Without a battle (the HUD's preview) there is nothing to refuse: true, the move stays local.
func assign_defense_spot(resident_id: StringName, spot_id: StringName) -> bool:
	if not is_instance_valid(_battle):
		return true
	return bool(_battle.call(&"move_guard", resident_id, spot_id))


## D-14 "준비 끝내고 바로 시작": the next wave comes now.
func skip_defense_prep() -> bool:
	return is_instance_valid(_battle) and bool(_battle.call(&"skip_prep"))


## DefenseBattle registers itself while it runs (for the D-14 calls above).
func _attach_battle(battle: Node) -> void:
	_battle = battle


func _detach_battle(battle: Node) -> void:
	if _battle == battle:
		_battle = null


## 자동 판정으로 넘기기: the same formula with the player bonus (+20%).
func skip_direct_defense() -> Dictionary:
	if _defense.is_empty():
		return {}
	var d := _defense
	_defense = {}
	defense_cancelled.emit()
	var result := resolve_raid(d["raid"], Enums.RaidMode.PLAYED)
	d["on_done"].call()
	return result


## The played defence ended. report = {"won": bool, "broken": Array (building uids),
## "guards_down": Array (resident ids still down at the end), "hurt": Array (residents hit)}.
## Facilities already lost their durability during the fight (damage_building). Returns the
## same result format as resolve_raid() with "direct": true.
func finish_direct_defense(report: Dictionary) -> Dictionary:
	if _defense.is_empty():
		return {}
	var d := _defense
	_defense = {}
	var raid: Dictionary = d["raid"]
	var broken: Array = report.get("broken", [])
	var guards_down: Array = report.get("guards_down", [])
	var hurt: Array = report.get("hurt", [])
	var harm := broken.size() + guards_down.size() + hurt.size()
	var outcome := DefenseRules.outcome(bool(report.get("won", false)), harm)
	var used := _use_defense_consumables()
	var casualties: Array = []
	var loot := {}
	var damage := {"damaged": broken.duplicate(), "durability_loss": {}, "resources_lost": {}}
	var summary: Array[String] = ["%s에서 마물이 몰려왔다. 직접 막아섰다." % _direction_text(raid.get("directions", []))]
	match outcome:
		Enums.RaidOutcome.FLAWLESS:
			var material: StringName = RaidRules.FAMILY_MATERIAL.get(int(raid.get("family", Enums.Element.NONE)), &"")
			if material != &"":
				loot[material] = roundi(float(raid.get("strength", 0.0)) * RaidRules.FLAWLESS_LOOT_SHARE)
			summary.append("피해 없이 막아냈다.")
		Enums.RaidOutcome.WIN, Enums.RaidOutcome.NARROW:
			_hurt(guards_down, 1.0, 0.0, 0.0, casualties)
			_hurt(hurt, 1.0, 0.0, 0.0, casualties)
			summary.append("막아냈다. 시설 %d곳이 부서졌다." % broken.size() if outcome == Enums.RaidOutcome.WIN else "간신히 버텼다.")
		Enums.RaidOutcome.LOSS:
			for res: StringName in Economy.amounts:
				var n := floori(Economy.get_amount(res) * RaidRules.LOSS_STORAGE_SHARE)
				if Economy.uses_cap(res) and n > 0:
					damage["resources_lost"][res] = n
			_hurt(guards_down, 1.0 - RaidRules.LOSS_GUARD_SERIOUS - RaidRules.LOSS_GUARD_DEATH, RaidRules.LOSS_GUARD_SERIOUS, RaidRules.LOSS_GUARD_DEATH, casualties)
			_hurt(hurt, 1.0 - RaidRules.LOSS_CIVILIAN_DEATH, 0.0, RaidRules.LOSS_CIVILIAN_DEATH, casualties)
			for id in active_resident_ids():
				residents[id]["morale"] = clampi(int(residents[id]["morale"]) + RaidRules.LOSS_MORALE, 0, 100)
			summary.append("막지 못했다. 창고가 털렸다.")
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
		"mode": Enums.RaidMode.PLAYED, "ratio": -1.0, "outcome": outcome, "damage": damage, "used": used,
		"casualties": casualties, "loot": loot, "summary": summary, "direct": true,
	}
	active_raid = {}
	EventBus.raid_resolved.emit(result)
	d["on_done"].call()
	return result


## A raider hit a facility (RaidStructure). Returns the durability left; at 0 the building is damaged.
func damage_building(uid: StringName, amount: int) -> int:
	if not buildings.has(uid) or amount <= 0:
		return int(buildings.get(uid, {}).get("durability", 0))
	var b: Dictionary = buildings[uid]
	b["durability"] = maxi(int(b["durability"]) - amount, 0)
	if int(b["durability"]) == 0 and not b["damaged"]:
		b["damaged"] = true
		EventBus.building_damaged.emit(uid)
		_refresh_effects()
		buildings_changed.emit()
	return int(b["durability"])


## 함정 재설치 between waves: a used-up or damaged trap is set again for the repair cost (C-18).
func reinstall_trap(uid: StringName) -> bool:
	var b: Dictionary = buildings.get(uid, {})
	var def := BaseDB.get_building(b.get("def_id", &""))
	if b.is_empty() or def == null or not def.effects.has(&"trap_damage"):
		return false
	if not b["damaged"] and int(b["durability"]) >= def.durability:
		return false
	var cost := repair_cost(uid)
	if not Economy.can_afford(cost):
		return false
	Economy.apply(_negated(cost))
	b["damaged"] = false
	b["durability"] = def.durability
	_refresh_effects()
	buildings_changed.emit()
	return true


# --- 출격 중 낮 습격 (C-21, 10 "출격 중 습격과 긴급 귀환") -------------------------------------
## When a sortie starts (FIELD) the day raid is decided (낮, 위협도 70 이상 20%, 5일차부터, 하루 1번).
## Some time into the sortie the warning comes (raid_warning: 60 s with a guard post or an outpost
## facing it, otherwise at once with raid_started). B-22 asks the player:
##   keep exploring → the raid is judged automatically when it hits;
##   emergency return → it waits for the player; after extraction the router enters BASE_DAY_RAID
##   and the defence is played (C-17: the player joins from wave 2, wave 1 is automatic).
## If the player goes down instead, the raid is judged automatically at the sortie's end.

## The day raid of this sortie: {} = none, else {"phase", "due_in", "hit_in", "raid", "result"}.
## phase: &"waiting" (경보 전), &"warned" (경보, 습격 전), &"hold" (긴급 귀환, 플레이어 기다림), &"done".
func field_day_raid() -> Dictionary:
	return _field_raid.duplicate(true)


func _roll_field_day_raid() -> void:
	_field_raid = {}
	_emergency_requested = false
	var day := GameState.day
	if not RaidRules.RAIDS or day < RaidRules.FIRST_RAID_DAY or last_raid_day == day:
		return
	if _rng.randf() >= float(RaidRules.raid_chance(Enums.RaidTime.DAY, threat)["chance"]):
		return
	_field_raid = {"phase": &"waiting", "due_in": _rng.randf_range(RaidRules.FIELD_RAID_AFTER_SEC.x, RaidRules.FIELD_RAID_AFTER_SEC.y),
		"hit_in": 0.0, "raid": {}, "result": {}}


## Sortie clock (seconds of field time). Called from _process while in FIELD; tests call it directly.
func _advance_field_raid(delta: float) -> void:
	if _field_raid.is_empty():
		return
	match _field_raid["phase"]:
		&"waiting":
			_field_raid["due_in"] = float(_field_raid["due_in"]) - delta
			if float(_field_raid["due_in"]) <= 0.0:
				var raid := roll_raid(Enums.RaidTime.DAY, true)  # emits raid_warning (B-22, Radio A-14)
				SceneRouter.start_day_raid(raid)
				_field_raid["raid"] = raid
				_field_raid["hit_in"] = float(raid["warning_sec"])
				_field_raid["phase"] = &"warned"
				if float(raid["warning_sec"]) <= 0.0:
					_field_raid_hits()
		&"warned":
			_field_raid["hit_in"] = float(_field_raid["hit_in"]) - delta
			if float(_field_raid["hit_in"]) <= 0.0:
				_field_raid_hits()


## The raid reaches the base: auto judgment, unless the player is on the way back.
func _field_raid_hits() -> void:
	start_raid(_field_raid["raid"])
	if _emergency_requested:
		_field_raid["phase"] = &"hold"
	else:
		_field_raid["result"] = resolve_raid(_field_raid["raid"], Enums.RaidMode.AUTO)
		_field_raid["phase"] = &"done"


## B-22: the player chose to go back. A raid that hits after this waits for them (phase hold).
func _on_emergency_return() -> void:
	_emergency_requested = true


## Sortie over. Downed, or extracted without the emergency return: judge it now if it is still open.
func _finish_field_raid(result: Dictionary) -> void:
	if _field_raid.is_empty() or _field_raid["phase"] == &"done":
		return
	if _field_raid["phase"] == &"waiting":
		_field_raid = {}  # back before it came: no day raid today
		return
	if bool(result.get("extracted", false)) and _emergency_requested:
		return  # the router goes to BASE_DAY_RAID; the defence is played there
	if _field_raid["phase"] == &"warned":
		start_raid(_field_raid["raid"])
	_field_raid["result"] = resolve_raid(_field_raid["raid"], Enums.RaidMode.AUTO)
	_field_raid["phase"] = &"done"


## Back at the base after the emergency return (BASE_DAY_RAID). Until C-17 the player-present
## judgment (+20%) decides it; then the router shows the sortie result.
func _play_field_day_raid() -> void:
	if SceneRouter.state() != Enums.FlowState.BASE_DAY_RAID or _field_raid.is_empty() or _field_raid["phase"] == &"done":
		return
	if _field_raid["phase"] == &"warned":
		start_raid(_field_raid["raid"])
	_field_raid["phase"] = &"done"
	# 긴급 귀환: the player joins from wave 2 (wave 1 counts as judged), C-17.
	begin_direct_defense(_field_raid["raid"], DefenseRules.EMERGENCY_FIRST_WAVE, SceneRouter.end_day_raid)


func _resolve_returned_field_raid() -> Dictionary:
	if _field_raid["phase"] == &"warned":
		start_raid(_field_raid["raid"])
	_field_raid["result"] = resolve_raid(_field_raid["raid"], Enums.RaidMode.PLAYED)
	_field_raid["phase"] = &"done"
	return _field_raid["result"]


## Death: coworkers' morale, grief, the memorial, guardianship and tomorrow's funeral (C-20).
func _kill(id: StringName, cause: StringName) -> void:
	unassign_job(id)
	release_bed(id)
	residents[id]["status"] = Enums.ResidentStatus.DEAD
	_after_death(id, cause)
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


# --- 참여 조건 and inclusion facilities (Lane C, C-11) --------------------------------

## Which conditions a zone meets now: {"mobility": bool, "language": bool, "missing": Array[String]}.
## 이동: by ZoneDef.mobility_access (open / ramp in ramp_zone / working elevator anywhere).
## 언어: a working 그림 표지판 in the zone. Unknown zones (prebuilt rooms with no zone) count as met.
func zone_access(zone_id: StringName) -> Dictionary:
	var zone := BaseDB.get_zone(zone_id)
	if zone == null:
		return {"mobility": true, "language": true, "missing": []}
	var missing: Array[String] = []
	var mobility := true
	match zone.mobility_access:
		"ramp":
			var ramp_zone := zone.ramp_zone if zone.ramp_zone != &"" else zone_id
			mobility = _has_effect_in_zone(&"access_mobility", ramp_zone)
			if not mobility:
				missing.append("경사로 (%s)" % BaseDB.get_zone(ramp_zone).display_name if BaseDB.get_zone(ramp_zone) else "경사로")
		"elevator":
			mobility = _has_effect_in_zone(&"access_mobility_floors", &"", true)
			if not mobility:
				missing.append("승강기 (전력 필요)")
	var language := _has_effect_in_zone(&"access_language", zone_id)
	if not language:
		missing.append("그림 표지판")
	return {"mobility": mobility, "language": language, "missing": missing}


## 청각: a working, powered 경광등 somewhere gives the visual raid alarm.
func hearing_alarm() -> bool:
	return _has_effect_in_zone(&"access_hearing", &"", true)


## 돌봄: child places at working 돌봄방 / 교실 that have someone on the job (돌봄 / 교육).
func care_slots() -> int:
	var slots := 0
	for uid in working_building_ids():
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		var staffed: bool = not buildings[uid]["workers"].is_empty()
		if staffed and def.effects.has(&"care_children"):
			slots += roundi(building_effect(uid, &"care_children"))
		elif staffed and def.effects.has(&"students"):
			slots += roundi(building_effect(uid, &"students"))
	return slots


## Guardians whose child is looked after (돌봄 조건 충족), in a stable order.
func care_covered() -> Array[StringName]:
	var guardians: Array[StringName] = []
	for id in active_resident_ids():
		if _needs_care(id):
			guardians.append(id)
	guardians.sort()
	return guardians.slice(0, care_slots())


## For the 접근성 보기 overlay and resident screens (D): per zone and base-wide.
## {"zones": {zone_id: {"mobility", "language", "missing"}}, "hearing_alarm": bool,
##  "care": {"slots": int, "guardians": int, "covered": Array}, "interpreter_radio": bool}
func access_map() -> Dictionary:
	var zones := {}
	for zone_id: StringName in BaseDB.zones():
		zones[zone_id] = zone_access(zone_id)
	var guardians := 0
	for id in active_resident_ids():
		if _needs_care(id):
			guardians += 1
	return {
		"zones": zones,
		"hearing_alarm": hearing_alarm(),
		"care": {"slots": care_slots(), "guardians": guardians, "covered": care_covered()},
		"interpreter_radio": not working_building_ids(&"interpreter_radio").is_empty(),
	}


## "" when `resident_id` can reach work in `zone_id` (이동 조건), else why not.
func access_block_reason(resident_id: StringName, zone_id: StringName) -> String:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or not Enums.AccessNeed.MOBILITY in r["access_needs"]:
		return ""
	var access := zone_access(zone_id)
	if access["mobility"]:
		return ""
	var zone := BaseDB.get_zone(zone_id)
	return "%s에 갈 수 없음: %s 필요" % [zone.display_name if zone else String(zone_id), access["missing"][0]]


## F_access in the work formula: 언어 조건 without a picture sign ×0.7, 돌봄 조건 without care ×0.5.
func access_multiplier(resident_id: StringName) -> float:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return 1.0
	var mult := 1.0
	var needs: Array = r["access_needs"]
	if Enums.AccessNeed.LANGUAGE in needs and not zone_access(_work_zone(resident_id))["language"]:
		mult *= NeedsRules.LANGUAGE_UNMET_MULT
	if _needs_care(resident_id) and not resident_id in care_covered():
		mult *= NeedsRules.CARE_UNMET_MULT
	return mult


## Zone of a resident's current workplace (building, construction site or zone being cleared).
func _work_zone(resident_id: StringName) -> StringName:
	var uid: StringName = residents[resident_id]["assignment"]["building_id"]
	if BaseDB.get_zone(uid) != null:
		return uid
	return buildings.get(uid, {}).get("zone_id", &"")


## A working building with `effect` in `zone_id` (&"" = anywhere). needs_power: must be powered.
func _has_effect_in_zone(effect: StringName, zone_id: StringName, needs_power: bool = false) -> bool:
	for uid in working_building_ids():
		var b: Dictionary = buildings[uid]
		if zone_id != &"" and b["zone_id"] != zone_id:
			continue
		if not BaseDB.get_building(b["def_id"]).effects.has(effect):
			continue
		if needs_power and not b["powered"]:
			continue
		return true
	return false


# --- Health, morale, leaving (Lane C, C-06) -----------------------------------------

## Residents who want to leave (떠나려 한다). They leave at the next evening unless persuaded.
func residents_in_crisis() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		if residents[id]["leave_crisis"]:
			out.append(id)
	return out


## 대화로 붙잡기 (07: 신뢰도 40 이상이면 성공). Returns {"ok": bool, "reason": String}.
## TODO(C-13): "원하는 것을 들어주기" (personal request, A-13) as the other way to keep them.
func persuade_to_stay(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or not r["leave_crisis"]:
		return {"ok": false, "reason": "떠나려는 사람이 아님"}
	if int(r["trust"]) < NeedsRules.PERSUADE_TRUST:
		return {"ok": false, "reason": "신뢰도 %d 필요 (지금 %d)" % [NeedsRules.PERSUADE_TRUST, r["trust"]]}
	r["leave_crisis"] = false
	r["low_morale_days"] = 0
	r["morale"] = maxi(int(r["morale"]), NeedsRules.PERSUADE_MORALE)
	return {"ok": true, "reason": ""}


# --- Relations and night events (C-14, 08 "관계 수치", "밤 이벤트") ---------------------
## Values live in residents[id]["relations"] (kept the same on both sides). Flags and days live in
## relation_meta. Night events: rolled when the night starts (no raid tonight), played one by one by
## Lane D (next_night_event → scene → resolve_night_event), and any left over are resolved with
## their first choice in the morning, so the rules also run without a screen.

func relation(a: StringName, b: StringName) -> int:
	if not residents.has(a):
		return 0
	return int(residents[a]["relations"].get(b, 0))


## Enums.RelationFlag values for the pair.
func relation_flags(a: StringName, b: StringName) -> Array:
	return relation_meta.get(RelationRules.pair_key(a, b), {}).get("flags", [])


## &"rival", &"awkward", &"acquainted", &"friend", &"best_friend", &"lover", &"married".
## relationship_changed also sends &"separated" once when lovers or a couple break up.
## (names: RelationRules.STAGE_NAMES).
func relation_stage(a: StringName, b: StringName) -> StringName:
	return RelationRules.stage_of(relation(a, b), relation_flags(a, b))


## other_id -> {"value": int, "stage": StringName} for residents still in the base.
func relations_of(resident_id: StringName) -> Dictionary:
	var out := {}
	if not residents.has(resident_id):
		return out
	for other: StringName in residents[resident_id]["relations"]:
		if residents.has(other):
			out[other] = {"value": relation(resident_id, other), "stage": relation_stage(resident_id, other)}
	return out


## The lover or spouse of `resident_id` (&"" = none).
func partner_of(resident_id: StringName) -> StringName:
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		var flags: Array = m["flags"]
		if not (Enums.RelationFlag.LOVERS in flags or Enums.RelationFlag.MARRIED in flags):
			continue
		if m["a"] == resident_id and _present(m["b"]):
			return m["b"]
		if m["b"] == resident_id and _present(m["a"]):
			return m["a"]
	return &""


## Married couples [[a, b], ...] (아이 맞이 C-15 reads this).
func couples() -> Array:
	var out := []
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if Enums.RelationFlag.MARRIED in m["flags"] and _present(m["a"]) and _present(m["b"]):
			out.append([m["a"], m["b"]])
	return out


## Changes the relation between two residents and returns the new value. Positive changes get the
## trait multipliers (혼자가 편함, 편견, 연애에 관심 없음). Counts as an interaction (감소가 멈춤).
## Emits relationship_changed when the stage changes. B / C-17 call this for 상대를 구해줌 (+15).
func add_relation(a: StringName, b: StringName, amount: int, _reason: StringName = &"") -> int:
	if a == b or not residents.has(a) or not residents.has(b):
		return 0
	var before := relation_stage(a, b)
	var d := float(amount)
	if d > 0.0:
		var flags := relation_flags(a, b)
		var romantic := Enums.RelationFlag.LOVERS in flags or Enums.RelationFlag.MARRIED in flags
		d *= RelationRules.gain_mult(residents[a], residents[b], romantic)
	var value := clampi(relation(a, b) + roundi(d), RelationRules.MIN, RelationRules.MAX)
	residents[a]["relations"][b] = value
	residents[b]["relations"][a] = value
	_relation_meta(a, b)["last_day"] = GameState.day
	_emit_stage(a, b, before)
	return value


## 결혼식 준비 (청혼 뒤): {"ok", "missing": Array[String], "cost", "house_uid"}.
func wedding_status(a: StringName, b: StringName) -> Dictionary:
	var m: Dictionary = relation_meta.get(RelationRules.pair_key(a, b), {})
	var missing: Array[String] = []
	if not m.get("engaged", false):
		missing.append("청혼 전")
	elif m.get("wedding_ready", false):
		missing.append("이미 준비됨")
	var cost: Dictionary = RelationRules.WEDDING_COST.duplicate()
	for res: StringName in cost:
		if Economy.get_amount(res) < int(cost[res]):
			missing.append("%s %d 필요" % [res, cost[res]])
	var house := _free_family_house()
	if house == &"":
		missing.append("빈 가족 숙소 필요")
	return {"ok": missing.is_empty(), "missing": missing, "cost": cost, "house_uid": house}


## Pays the wedding cost and keeps a family house for the pair. The wedding is the next night.
func prepare_wedding(a: StringName, b: StringName) -> bool:
	var status := wedding_status(a, b)
	if not status["ok"]:
		return false
	var pay := {}
	for res: StringName in status["cost"]:
		pay[res] = -int(status["cost"][res])
	Economy.apply(pay)
	var m := _relation_meta(a, b)
	m["wedding_ready"] = true
	m["house_uid"] = status["house_uid"]
	return true


## Festival day after a wedding: no production, everyone +15 morale; the day after, work ×1.1.
func is_festival_today() -> bool:
	return festival_day > 0 and festival_day == GameState.day


## Tonight's events still waiting to be played ([{event_id, participants, choices, night_day}]).
func pending_night_events() -> Array:
	return night_queue.duplicate(true)


## Lane D: start the next event's scene. Returns the event ({} = none). The router goes to NIGHT_EVENT
## and emits night_event_started(event_id, participants).
func next_night_event() -> Dictionary:
	if night_queue.is_empty() or not current_night_event.is_empty():
		return {}
	current_night_event = night_queue.pop_front()
	if GameState.flow_state == Enums.FlowState.NIGHT:
		SceneRouter.start_night_event(current_night_event["event_id"], current_night_event["participants"])
	return current_night_event.duplicate(true)


## Lane D: the scene ended with `choice` (one of the event's choices; &"" = the first).
## Applies the outcome, returns {event_id, participants, choice, text, ...} and goes back to NIGHT.
func resolve_night_event(choice: StringName = &"") -> Dictionary:
	if current_night_event.is_empty():
		return {}
	var ev := current_night_event
	current_night_event = {}
	var result := _apply_night_event(ev, choice)
	if GameState.flow_state == Enums.FlowState.NIGHT_EVENT:
		SceneRouter.end_night_event()
	return result


## Picks tonight's events (priority ones, then 1~2 by weight). Used by the night hook and tests.
func roll_night_events() -> Array:
	var picked: Array = []
	var weighted: Array = []
	for event_id: StringName in BaseDB.night_events():
		var def := BaseDB.get_night_event(event_id)
		var groups := _night_candidates(event_id)
		if groups.is_empty():
			continue
		if def.priority:
			for g in groups:
				picked.append(_night_event(def, g))
		else:
			weighted.append([def, groups])
	var want := 1 + (1 if _rng.randf() < RelationRules.NIGHT_SECOND_EVENT_CHANCE else 0)
	while picked.size() < want and not weighted.is_empty():
		var total := 0
		for w: Array in weighted:
			total += (w[0] as NightEventDef).weight
		var roll := _rng.randi_range(1, maxi(total, 1))
		for i in weighted.size():
			roll -= (weighted[i][0] as NightEventDef).weight
			if roll <= 0:
				var groups: Array = weighted[i][1]
				picked.append(_night_event(weighted[i][0], groups[_rng.randi_range(0, groups.size() - 1)]))
				weighted.remove_at(i)
				break
	return picked


func _night_event(def: NightEventDef, participants: Array) -> Dictionary:
	var ids: Array[StringName] = []
	for p in participants:
		ids.append(StringName(p))
	return {"event_id": def.id, "participants": ids, "choices": def.choices.duplicate(), "night_day": GameState.day}


## Participant groups that meet `event_id`'s condition tonight.
func _night_candidates(event_id: StringName) -> Array:
	var ids := _adults_and_teens()
	var out: Array = []
	match event_id:
		&"prejudice_talk":
			for target: StringName in prejudice_chains_data:
				var c: Dictionary = prejudice_chains_data[target]
				if c["step"] == PrejudiceRules.STEP_INCIDENT and target in ids:
					for h in c["holders"]:
						if h in ids:
							out.append([h, target])
		&"bonfire":
			if ids.size() >= RelationRules.BONFIRE_PARTICIPANTS.x:
				var pool := ids.duplicate()
				var group: Array = []
				for i in mini(_rng.randi_range(RelationRules.BONFIRE_PARTICIPANTS.x, RelationRules.BONFIRE_PARTICIPANTS.y), pool.size()):
					group.append(pool.pop_at(_rng.randi_range(0, pool.size() - 1)))
				out.append(group)
		&"quarrel":
			for pair in _pairs(ids):
				var a: Dictionary = residents[pair[0]]
				var b: Dictionary = residents[pair[1]]
				var tired := int(a["fatigue"]) >= RelationRules.QUARREL_FATIGUE_AT or int(b["fatigue"]) >= RelationRules.QUARREL_FATIGUE_AT
				var prejudice := RelationRules.prejudiced_against(a, b) or RelationRules.prejudiced_against(b, a)
				if relation(pair[0], pair[1]) <= RelationRules.QUARREL_BELOW and (tired or prejudice):
					out.append(pair)
		&"confession":
			for pair in _pairs(ids):
				if RelationRules.romance_ok(residents[pair[0]]) and RelationRules.romance_ok(residents[pair[1]]) \
						and partner_of(pair[0]) == &"" and partner_of(pair[1]) == &"" \
						and relation(pair[0], pair[1]) >= RelationRules.CONFESS_AT:
					out.append(pair)
		_:
			for key: String in relation_meta:
				var m: Dictionary = relation_meta[key]
				var pair := [m["a"], m["b"]]
				if not (pair[0] in ids and pair[1] in ids):
					continue
				var flags: Array = m["flags"]
				var lovers := Enums.RelationFlag.LOVERS in flags
				var value := relation(pair[0], pair[1])
				match event_id:
					&"date":
						if lovers:
							out.append(pair)
					&"proposal":
						if lovers and not m["engaged"] and value >= RelationRules.PROPOSE_AT \
								and GameState.day - int(m["since_day"]) >= RelationRules.PROPOSE_LOVERS_DAYS \
								and int(residents[pair[0]]["morale"]) >= RelationRules.PROPOSE_MORALE_AT \
								and int(residents[pair[1]]["morale"]) >= RelationRules.PROPOSE_MORALE_AT:
							out.append(pair)
					&"wedding":
						if m["wedding_ready"]:
							out.append(pair)
					&"breakup":
						if (lovers or Enums.RelationFlag.MARRIED in flags) and int(m["low_days"]) >= RelationRules.BREAKUP_DAYS:
							out.append(pair)
	return out


func _apply_night_event(ev: Dictionary, choice: StringName) -> Dictionary:
	var choices: Array = ev.get("choices", [])
	if not choice in choices:
		choice = StringName(choices[0]) if not choices.is_empty() else &"watch"
	var who: Array = ev["participants"]
	for id in who:
		if not residents.has(id):
			return {"event_id": ev["event_id"], "participants": who, "choice": choice, "text": "", "skipped": true}
	var a: StringName = who[0]
	var b: StringName = who[1] if who.size() > 1 else &""
	var names := ", ".join(who.map(func(id): return String(residents[id]["name"])))
	var result := {"event_id": ev["event_id"], "participants": who, "choice": choice, "text": ""}
	match ev["event_id"]:
		&"prejudice_talk":
			result["fragments"] = _resolve_prejudice(a, b)
			result["text"] = "%s이(가) 이야기를 나눴다. 소문은 근거가 없었다" % names
		&"bonfire":
			for pair in _pairs(who):
				var ra: Dictionary = residents[pair[0]]
				var rb: Dictionary = residents[pair[1]]
				var amount := roundi(_rng.randi_range(RelationRules.BONFIRE.x, RelationRules.BONFIRE.y) * RelationRules.bonfire_mult(ra, rb))
				if RelationRules.shared_like(ra, rb):
					amount += RelationRules.SHARED_LIKE_BONUS
				add_relation(pair[0], pair[1], amount, &"bonfire")
			for id in who:
				var story := unlocked_story(id)
				if not story.is_empty():
					result["fragment"] = {"resident_id": id, "text": story[_rng.randi_range(0, story.size() - 1)]}
					break
			result["text"] = "%s이(가) 모닥불가에서 이야기했다" % names
		&"quarrel":
			var trust_avg := (int(residents[a]["trust"]) + int(residents[b]["trust"])) / 2.0
			if choice == &"mediate" and _rng.randf() * 100.0 < trust_avg:
				add_relation(a, b, RelationRules.MEDIATE_SUCCESS_GAIN, &"mediated")
				result["mediated"] = true
				result["text"] = "%s의 다툼을 말려 화해시켰다" % names
			else:
				add_relation(a, b, _rng.randi_range(RelationRules.QUARREL.x, RelationRules.QUARREL.y), &"quarrel")
				result["mediated"] = false
				result["text"] = "%s이(가) 다퉜다" % names
		&"confession":
			_set_lovers(a, b, int(ev["night_day"]))
			if choice == &"cheer":
				for id in who:
					residents[id]["morale"] = NeedsRules.apply_morale(residents[id], RelationRules.CHEER_MORALE)
			result["text"] = "%s이(가) 연인이 되었다" % names
		&"date":
			add_relation(a, b, RelationRules.DATE_RELATION, &"date")
			for id in who:
				residents[id]["morale"] = NeedsRules.apply_morale(residents[id], RelationRules.DATE_MORALE)
			result["text"] = "%s이(가) 데이트를 했다" % names
		&"proposal":
			_relation_meta(a, b)["engaged"] = true
			result["text"] = "%s이(가) 결혼을 약속했다. 결혼식 준비: 식량 %d, 천 %d, 빈 가족 숙소" % [names,
				RelationRules.WEDDING_COST[&"food"], RelationRules.WEDDING_COST[&"cloth"]]
		&"wedding":
			var before := relation_stage(a, b)
			var m := _relation_meta(a, b)
			m["flags"] = [Enums.RelationFlag.MARRIED]
			m["engaged"] = false
			m["wedding_ready"] = false
			_move_into_house(who, m["house_uid"])
			festival_day = int(ev["night_day"]) + 1
			_emit_stage(a, b, before)
			result["text"] = "%s이(가) 결혼했다. 내일은 축제" % names
		&"breakup":
			var m := _relation_meta(a, b)
			m["flags"] = []
			m["engaged"] = false
			m["wedding_ready"] = false
			m["house_uid"] = &""
			m["low_days"] = 0
			for id in who:
				residents[id]["morale"] = NeedsRules.apply_morale(residents[id], RelationRules.BREAKUP_MORALE)
			# Journal (A-17) reads &"separated" for 이별; the pair's value stage is unchanged.
			EventBus.relationship_changed.emit(a, b, RelationRules.SEPARATED)
			result["text"] = "%s이(가) 헤어졌다" % names
	last_night_results.append(result)
	if ev["event_id"] in [&"confession", &"proposal", &"wedding", &"breakup"]:
		EventBus.notification_posted.emit(result["text"], &"info")
	return result


func _set_lovers(a: StringName, b: StringName, day: int) -> void:
	var before := relation_stage(a, b)
	var m := _relation_meta(a, b)
	m["flags"] = [Enums.RelationFlag.LOVERS]
	m["since_day"] = day
	m["low_days"] = 0
	_emit_stage(a, b, before)


## Daily part of the settlement: 같은 작업장 +1, 10일 교류 없으면 감소, 이별 카운트.
func _settle_relations(worked: Dictionary) -> void:
	var done := {}
	for id: StringName in worked:
		for other in _coworker_ids(id):
			var key := RelationRules.pair_key(id, other)
			if worked.has(other) and not done.has(key):
				done[key] = true
				add_relation(id, other, RelationRules.SAME_WORKPLACE, &"workplace")
	var today := GameState.day
	for id: StringName in residents:
		for other: StringName in residents[id]["relations"]:
			if String(id) > String(other) or not residents.has(other):
				continue
			var value := relation(id, other)
			var m: Dictionary = relation_meta.get(RelationRules.pair_key(id, other), {})
			var last := int(m.get("last_day", 0))
			if value > RelationRules.DECAY_FROM and today - last >= RelationRules.DECAY_AFTER_DAYS:
				var before := relation_stage(id, other)
				value = maxi(value - RelationRules.DECAY_PER_DAY, RelationRules.DECAY_FROM)
				residents[id]["relations"][other] = value
				residents[other]["relations"][id] = value
				_emit_stage(id, other, before)
			if not m.is_empty():
				var flags: Array = m["flags"]
				if (Enums.RelationFlag.LOVERS in flags or Enums.RelationFlag.MARRIED in flags) and value < RelationRules.BREAKUP_BELOW:
					m["low_days"] = int(m["low_days"]) + 1
				else:
					m["low_days"] = 0


## Residents at the same workplace: the same building / zone / node, or the same job with no place.
func _coworker_ids(resident_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return out
	var job := job_of(resident_id)
	var place: StringName = r["assignment"]["building_id"]
	if job == &"" or job == WorkRules.REST_JOB:
		return out
	for other in active_resident_ids():
		if other == resident_id:
			continue
		var o: Dictionary = residents[other]
		if job_of(other) == job and StringName(o["assignment"]["building_id"]) == place:
			out.append(other)
		elif place != &"" and StringName(o["assignment"]["building_id"]) == place:
			out.append(other)
	return out


## 절친과 같은 작업장 효율 +10%.
func _best_friend_mult(resident_id: StringName) -> float:
	for other in _coworker_ids(resident_id):
		if relation(resident_id, other) >= RelationRules.BEST_FRIEND_AT:
			return RelationRules.BEST_FRIEND_WORK_MULT
	return 1.0


func _relation_meta(a: StringName, b: StringName) -> Dictionary:
	var key := RelationRules.pair_key(a, b)
	if not relation_meta.has(key):
		var first := a if String(a) < String(b) else b
		relation_meta[key] = {"a": first, "b": b if first == a else a, "flags": [], "since_day": 0,
			"last_day": GameState.day, "low_days": 0, "engaged": false, "wedding_ready": false, "house_uid": &""}
	return relation_meta[key]


func _emit_stage(a: StringName, b: StringName, before: StringName) -> void:
	var stage := relation_stage(a, b)
	if stage != before:
		EventBus.relationship_changed.emit(a, b, stage)


func _adults_and_teens() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		if int(residents[id]["age_stage"]) >= Enums.AgeStage.TEEN:
			out.append(id)
	return out


func _pairs(ids: Array) -> Array:
	var out: Array = []
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			out.append([ids[i], ids[j]])
	return out


func _free_family_house() -> StringName:
	var taken := {}
	for key: String in relation_meta:
		var uid: StringName = relation_meta[key].get("house_uid", &"")
		if uid != &"":
			taken[uid] = true
	for uid in building_ids(RelationRules.FAMILY_HOUSE):
		if not taken.has(uid):
			return uid
	return &""


## The couple moves into their family house beds (when free).
func _move_into_house(who: Array, house_uid: StringName) -> void:
	if house_uid == &"" or not buildings.has(house_uid):
		return
	var house_beds: Array[StringName] = []
	for bed_id: StringName in beds:
		if String(bed_id).begins_with(String(house_uid) + "_bed_") and beds[bed_id] == &"":
			house_beds.append(bed_id)
	for id in who:
		if house_beds.is_empty():
			return
		release_bed(id)
		assign_bed(id, house_beds.pop_front())


func _roll_tonight() -> void:
	var day := GameState.day
	if GameState.flow_state != Enums.FlowState.NIGHT or _night_rolled_day == day:
		return
	_night_rolled_day = day
	last_night_results = []
	if last_night_raid_day == day:
		return  # 습격이 있는 밤에는 이벤트가 없다
	night_queue = roll_night_events()
	if not night_queue.is_empty():
		night_events_ready.emit(pending_night_events())


## Morning: events nobody played are resolved with their first choice.
func _finish_night() -> void:
	if not current_night_event.is_empty():
		var ev := current_night_event
		current_night_event = {}
		_apply_night_event(ev, &"")
	while not night_queue.is_empty():
		_apply_night_event(night_queue.pop_front(), &"")


## 함께 출격해 살아 돌아옴: relation +5 between the companions who came back.
func _sortie_relations(back: Array[StringName]) -> void:
	for pair in _pairs(back):
		add_relation(pair[0], pair[1], RelationRules.SORTIE_TOGETHER, &"sortie")


# --- 아이 맞이 + 성장 (C-15, 08 "아이 맞이", "성장") ----------------------------------------
## Family data lives on the married couple's relation_meta entry: children, last_child_day,
## wish_day (아이를 맞고 싶다 is waiting for an answer), carrier / due_day (출산), adoption_waiting.
## Guardian links are relation_meta entries with the GUARDIAN flag (parent ↔ child).

## Why a married couple cannot welcome a child now: {"ok", "missing": Array[String]}.
func child_arrival_status(a: StringName, b: StringName) -> Dictionary:
	var m: Dictionary = relation_meta.get(RelationRules.pair_key(a, b), {})
	var missing: Array[String] = []
	if m.is_empty() or not Enums.RelationFlag.MARRIED in m["flags"]:
		missing.append("결혼한 두 사람이 아님")
		return {"ok": false, "missing": missing}
	if _family_free_bed(m) == &"":
		missing.append("가족 숙소에 빈 침상 필요")
	if not has_completed(ChildRules.INFIRMARY):
		missing.append("의무실 필요")
	if Economy.get_amount(&"food") < population() * ChildRules.FOOD_PER_RESIDENT:
		missing.append("식량 %d 이상 필요" % (population() * ChildRules.FOOD_PER_RESIDENT))
	for id in [a, b]:
		if int(residents[id]["morale"]) < ChildRules.MORALE_AT:
			missing.append("%s 사기 %d 이상 필요" % [residents[id]["name"], ChildRules.MORALE_AT])
	var last := int(m.get("last_child_day", 0))
	if last > 0 and GameState.day - last < ChildRules.FAMILY_INTERVAL_DAYS:
		missing.append("지난 아이 맞이에서 %d일 필요" % ChildRules.FAMILY_INTERVAL_DAYS)
	if int(m.get("due_day", 0)) > 0 or m.get("adoption_waiting", false):
		missing.append("이미 아이를 기다리는 중")
	return {"ok": missing.is_empty(), "missing": missing}


## Ways this family can welcome a child: 출산 when one of them is a woman (ChildRules.can_give_birth),
## 입양 for every family.
func child_methods(a: StringName, b: StringName) -> Array:
	var methods: Array = [Enums.ArrivalMethod.ADOPTION]
	if residents.has(a) and residents.has(b) and (ChildRules.can_give_birth(residents[a]) or ChildRules.can_give_birth(residents[b])):
		methods.push_front(Enums.ArrivalMethod.BIRTH)
	return methods


## "아이를 맞고 싶다" waiting for the family's answer: [{a, b, methods}].
func child_wishes() -> Array:
	var out: Array = []
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if int(m.get("wish_day", 0)) > 0 and residents.has(m["a"]) and residents.has(m["b"]):
			out.append({"a": m["a"], "b": m["b"], "methods": child_methods(m["a"], m["b"])})
	return out


## The family answers: choice &"now" (with a method) or &"later".
## Returns {"ok", "reason", "child_id", "due_day", "waiting"}.
func answer_child_wish(a: StringName, b: StringName, choice: StringName, method: int = Enums.ArrivalMethod.ADOPTION) -> Dictionary:
	var out := {"ok": false, "reason": "", "child_id": &"", "due_day": 0, "waiting": false}
	var m: Dictionary = relation_meta.get(RelationRules.pair_key(a, b), {})
	if m.is_empty() or int(m.get("wish_day", 0)) == 0:
		out["reason"] = "기다리는 대화가 없음"
		return out
	m["wish_day"] = 0
	if choice != &"now":
		out["ok"] = true
		return out
	if not method in child_methods(a, b):
		out["reason"] = "이 가족은 고를 수 없는 방식"
		return out
	m["last_child_day"] = GameState.day
	out["ok"] = true
	if method == Enums.ArrivalMethod.BIRTH:
		m["carrier"] = a if ChildRules.can_give_birth(residents[a]) else b
		m["due_day"] = GameState.day + ChildRules.BIRTH_DAYS
		out["due_day"] = m["due_day"]
		EventBus.notification_posted.emit("%s 가족에게 %d일 뒤 아기가 온다" % [_display_name(residents[a]), ChildRules.BIRTH_DAYS], &"info")
		return out
	var waiting := orphans()
	if not waiting.is_empty():
		out["child_id"] = waiting[0]
		_adopt(m, waiting[0])
		return out
	# No child without a guardian in the base: the radio hears a rumor and a rescue target appears.
	m["adoption_waiting"] = true
	out["waiting"] = true
	if Quests.get_def(ChildRules.LOST_CHILD_QUEST) != null:
		Quests.start(ChildRules.LOST_CHILD_QUEST, a)
	EventBus.notification_posted.emit("방송실: 보호자를 잊은 아이가 있다는 소문을 기다린다", &"info")
	return out


## Children in the base with no guardian (입양 대상).
func orphans() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		if ChildRules.is_minor(residents[id]) and guardians_of(id).is_empty():
			out.append(id)
	return out


func guardians_of(child_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if not Enums.RelationFlag.GUARDIAN in m["flags"]:
			continue
		var other: StringName = m["b"] if m["a"] == child_id else (m["a"] if m["b"] == child_id else &"")
		if other != &"" and _present(other) and not ChildRules.is_minor(residents[other]):
			out.append(other)
	return out


## Children of a married couple (born or adopted here).
func children_of(a: StringName, b: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for c in relation_meta.get(RelationRules.pair_key(a, b), {}).get("children", []):
		if residents.has(c):
			out.append(StringName(c))
	return out


func is_pregnant(resident_id: StringName) -> bool:
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if int(m.get("due_day", 0)) > 0 and m.get("carrier", &"") == resident_id:
			return true
	return false


## Why a resident cannot go on a sortie ("" = can). 출산을 기다리는 주민은 출격 불가.
func sortie_block_reason(resident_id: StringName) -> String:
	if not residents.has(resident_id):
		return "없는 주민"
	if is_pregnant(resident_id):
		return "출산을 기다리는 중"
	return ""


## 이름 짓기 (입주 의식의 아이 판): a child still in the ceremony gets a name. {"ok", "reason"}.
func name_child(child_id: StringName, child_name: String) -> Dictionary:
	var r: Dictionary = residents.get(child_id, {})
	if r.is_empty() or not ChildRules.is_minor(r) or not r["arrival_pending"]:
		return {"ok": false, "reason": "이름을 지을 아이가 아님"}
	var text := child_name.strip_edges()
	if text == "" or text.length() > ChildRules.NAME_MAX:
		return {"ok": false, "reason": "이름은 1~%d자" % ChildRules.NAME_MAX}
	for word in ResidentTemplate.load_banned_words():
		if word != "" and text.to_lower().contains(word.to_lower()):
			return {"ok": false, "reason": "쓸 수 없는 말이 들어 있다"}
	r["name"] = text
	resident_profile_changed.emit(child_id)
	return {"ok": true, "reason": ""}


## Daily part of the settlement: growth, births, the 5% wish, classroom study.
func _settle_children(events: Array) -> void:
	for id in active_resident_ids():
		_age_one_day(id, events)
	var today := GameState.day
	for key: String in relation_meta.keys():
		var m: Dictionary = relation_meta[key]
		if not Enums.RelationFlag.MARRIED in m["flags"]:
			continue
		if int(m.get("due_day", 0)) > 0 and today >= int(m["due_day"]):
			var child := _birth(m)
			events.append(_event(&"child_born", child, "%s 가족에게 아기가 태어났다" % _display_name(residents[m["a"]])))
		elif int(m.get("wish_day", 0)) == 0 and child_arrival_status(m["a"], m["b"])["ok"] \
				and _rng.randf() < ChildRules.WISH_CHANCE:
			m["wish_day"] = today
			events.append(_event(&"child_wish", m["a"], "%s 가족이 아이를 맞고 싶어 한다" % _display_name(residents[m["a"]])))
			child_wish.emit(m["a"], m["b"], child_methods(m["a"], m["b"]))
	_study(events)


func _age_one_day(id: StringName, events: Array) -> void:
	var r: Dictionary = residents[id]
	var stage := int(r["age_stage"])
	if stage >= Enums.AgeStage.ADULT:
		return
	# Rescued children start at the beginning of their stage (구조 당시 나이대에서 시작).
	r["age_days"] = maxi(int(r["age_days"]), int(ChildRules.STAGE_START[stage])) + 1
	var next := int(ChildRules.stage_for_days(int(r["age_days"])))
	if next > stage:
		r["age_stage"] = next
		events.append(_event(&"grew_up", id, "%s이(가) %s" % [_display_name(r),
			["아기가 되었다", "아이가 되었다", "청소년이 되었다", "어른이 되었다", ""][next]]))
		resident_profile_changed.emit(id)


func _birth(m: Dictionary) -> StringName:
	var a: Dictionary = residents[m["a"]]
	var b: Dictionary = residents[m["b"]]
	var parents := [a, b]
	var stats := {}
	for key in ResidentData.STAT_KEYS:
		stats[key] = _rng.randi_range(ChildRules.CHILD_STAT_RANGE.x, ChildRules.CHILD_STAT_RANGE.y)
	var inherited: Array = []
	var pool: Array = a["traits"] + b["traits"]
	if not pool.is_empty():
		inherited.append(pool[_rng.randi_range(0, pool.size() - 1)])
	# 외형 혼합: each colour comes from one of the parents.
	var look := {}
	for key in ArrivalRules.COLOR_KEYS:
		var p: Dictionary = parents[_rng.randi_range(0, 1)]
		if p["appearance"].has(key):
			look[key] = p["appearance"][key]
	var id := add_resident({"name": ChildRules.CHILD_NAME, "age_stage": Enums.AgeStage.BABY, "age_days": 0,
		"former_job": &"", "traits": inherited, "stats": stats, "appearance": look, "arrival_pending": true})
	m["due_day"] = 0
	m["carrier"] = &""
	_adopt(m, id)
	child_arrived.emit(id, Enums.ArrivalMethod.BIRTH, [m["a"], m["b"]])
	return id


## Makes the couple the child's guardians and moves the child into the family house.
func _adopt(m: Dictionary, child_id: StringName) -> void:
	m["adoption_waiting"] = false
	if not m.has("children"):
		m["children"] = []
	if not child_id in m["children"]:
		m["children"].append(child_id)
	for parent in [m["a"], m["b"]]:
		var g := _relation_meta(parent, child_id)
		if not Enums.RelationFlag.GUARDIAN in g["flags"]:
			g["flags"].append(Enums.RelationFlag.GUARDIAN)
		if relation(parent, child_id) < ChildRules.START_RELATION:
			add_relation(parent, child_id, ChildRules.START_RELATION - relation(parent, child_id), &"family")
	var bed := _family_free_bed(m)
	if bed != &"":
		release_bed(child_id)
		assign_bed(child_id, bed)
	EventBus.notification_posted.emit("%s 가족이 %s을(를) 맞이했다" % [_display_name(residents[m["a"]]), _display_name(residents[child_id])], &"info")


## A free bed in the couple's family house (&"" = none).
func _family_free_bed(m: Dictionary) -> StringName:
	var house: StringName = m.get("house_uid", &"")
	if house == &"":
		return &""
	for bed_id: StringName in beds:
		if String(bed_id).begins_with(String(house) + "_bed_") and beds[bed_id] == &"":
			return bed_id
	return &""


## A rescued child joins while a family waits to adopt: they become that family's child.
func _adopt_rescued(child_id: StringName) -> void:
	if not ChildRules.is_minor(residents[child_id]):
		return
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if m.get("adoption_waiting", false) and residents.has(m["a"]) and residents.has(m["b"]):
			_adopt(m, child_id)
			child_arrived.emit(child_id, Enums.ArrivalMethod.ADOPTION, [m["a"], m["b"]])
			return


## 교실: each staffed classroom teaches up to its student count (아이·청소년). Stats grow ×2 and
## after 20 days a child gets the teacher's former-job work at skill 1 (세대 간 전수).
func _study(events: Array) -> void:
	var students: Array[StringName] = []
	for id in active_resident_ids():
		if int(residents[id]["age_stage"]) in [Enums.AgeStage.CHILD, Enums.AgeStage.TEEN]:
			students.append(id)
	students.sort()
	for uid in working_building_ids(ChildRules.CLASSROOM):
		var workers: Array = buildings[uid]["workers"]
		if workers.is_empty() or students.is_empty():
			continue
		var teacher: Dictionary = residents[workers[0]]
		var work: StringName = ChildRules.FORMER_JOB_WORK.get(teacher["former_job"], &"")
		var job := BaseDB.get_job(work)
		var seats := roundi(building_effect(uid, &"students"))
		var mult := roundi(building_effect(uid, &"study_speed_mult", 1.0))
		for i in mini(seats, students.size()):
			var id: StringName = students.pop_front()
			var r: Dictionary = residents[id]
			if job == null:
				continue
			var days := int(r["study_days"].get(work, 0)) + 1
			r["study_days"][work] = days
			var stat := job.main_stat_key()
			if stat != &"":
				var sd := int(r["stat_days"].get(stat, 0)) + mult
				r["stat_days"][stat] = sd
				if sd / WorkRules.days_per_stat() > (sd - mult) / WorkRules.days_per_stat() and int(r["stats"][stat]) < ResidentData.STAT_MAX:
					r["stats"][stat] = int(r["stats"][stat]) + 1
			if days == ChildRules.STUDY_DAYS and int(r["job_skill"].get(work, 0)) < ChildRules.TEACH_SKILL:
				r["job_skill"][work] = ChildRules.TEACH_SKILL
				events.append(_event(&"taught", id, "%s이(가) %s에게서 %s을(를) 배웠다" % [_display_name(r), _display_name(teacher), job.display_name]))


## Guardians of a baby need care like the 돌봄 condition (돌봄방이 없으면 효율 0.5).
func _needs_care(resident_id: StringName) -> bool:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return false
	if Enums.AccessNeed.CARE in r["access_needs"]:
		return true
	for key: String in relation_meta:
		var m: Dictionary = relation_meta[key]
		if not Enums.RelationFlag.GUARDIAN in m["flags"]:
			continue
		var other: StringName = m["b"] if m["a"] == resident_id else (m["a"] if m["b"] == resident_id else &"")
		if other != &"" and residents.has(other) and int(residents[other]["age_stage"]) == Enums.AgeStage.BABY \
				and int(residents[other]["status"]) == Enums.ResidentStatus.ACTIVE and not ChildRules.is_minor(r):
			return true
	return false


## 출산을 기다리는 주민: 힘 작업 효율 ×0.7.
func _pregnancy_mult(resident_id: StringName, job: JobDef) -> float:
	return ChildRules.PREGNANT_STR_MULT if job.main_stat_key() == &"str" and is_pregnant(resident_id) else 1.0


# --- 전초기지 (C-19, 10 "전초기지") -----------------------------------------------------------
## outposts[node_id] = {node_id, direction, region_id, ready_day, damaged, durability}. Garrison
## residents have assignment {job: &"garrison", building_id: node_id}. 가동 = 완성 + 부서지지 않음 +
## 주둔 2명. Active outposts lower the threat (−2 each), cut raids from their direction by 25%, warn a
## day ahead with size and family, gather wood and scrap, and cost food. 20% of raids hit one.

## Every node an outpost can stand on: [{node_id, direction, region_id, built, ready, active,
## damaged, garrison, ready_day}] (4 directions + one per field region).
func outpost_nodes() -> Array:
	var out: Array = []
	for node_id: StringName in _outpost_node_defs():
		var def: Dictionary = _outpost_node_defs()[node_id]
		var o: Dictionary = outposts.get(node_id, {})
		out.append({"node_id": node_id, "direction": def["direction"], "region_id": def["region_id"],
			"built": not o.is_empty(), "ready": _outpost_ready(node_id), "active": is_outpost_active(node_id),
			"damaged": o.get("damaged", false), "garrison": garrison_of(node_id), "ready_day": o.get("ready_day", 0)})
	return out


## Active outposts (가동 중), in node order.
func active_outposts() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id: StringName in _outpost_node_defs():
		if is_outpost_active(node_id):
			out.append(node_id)
	return out


func is_outpost_active(node_id: StringName) -> bool:
	return _outpost_ready(node_id) and not outposts[node_id]["damaged"] and garrison_of(node_id).size() >= OutpostRules.GARRISON_SIZE


## Residents posted at an outpost.
func garrison_of(node_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		var a: Dictionary = residents[id]["assignment"]
		if a["job"] == OutpostRules.GARRISON_JOB and a["building_id"] == node_id:
			out.append(id)
	return out


## {"ok", "reasons": Array[String], "cost"} for building an outpost on `node_id`.
func can_build_outpost(node_id: StringName) -> Dictionary:
	var reasons: Array[String] = []
	if not _outpost_node_defs().has(node_id):
		reasons.append("없는 노드: %s" % node_id)
	elif outposts.has(node_id):
		reasons.append("이미 전초기지가 있음")
	if not Economy.can_afford(OutpostRules.COST):
		reasons.append("자원 부족 (나무 %d, 돌 %d, 고철 %d)" % [OutpostRules.COST[&"wood"], OutpostRules.COST[&"stone"], OutpostRules.COST[&"scrap"]])
	return {"ok": reasons.is_empty(), "reasons": reasons, "cost": OutpostRules.COST.duplicate()}


## Pays and starts the outpost; it is ready after OutpostRules.BUILD_DAYS evenings.
func build_outpost(node_id: StringName) -> bool:
	if not can_build_outpost(node_id)["ok"]:
		return false
	Economy.apply(_negated(OutpostRules.COST))
	var def: Dictionary = _outpost_node_defs()[node_id]
	outposts[node_id] = {"node_id": node_id, "direction": def["direction"], "region_id": def["region_id"],
		"ready_day": GameState.day + OutpostRules.BUILD_DAYS, "damaged": false, "durability": OutpostRules.DURABILITY}
	outposts_changed.emit()
	return true


## Posts a resident at a ready outpost (주둔 2명까지). Same limits as other combat roles.
func assign_garrison(node_id: StringName, resident_id: StringName) -> bool:
	if not _outpost_ready(node_id) or not residents.has(resident_id):
		return false
	if garrison_of(node_id).size() >= OutpostRules.GARRISON_SIZE and not resident_id in garrison_of(node_id):
		return false
	if job_block_reason(resident_id, OutpostRules.GARRISON_JOB) != "":
		return false
	unassign_job(resident_id)
	residents[resident_id]["assignment"] = {"job": OutpostRules.GARRISON_JOB, "building_id": node_id}
	outposts_changed.emit()
	return true


## Repair cost (30% of the build cost, rounded up) for a damaged outpost.
func outpost_repair_cost(node_id: StringName) -> Dictionary:
	var cost := {}
	for res: StringName in OutpostRules.COST:
		cost[res] = ceili(OutpostRules.COST[res] * OutpostRules.REPAIR_SHARE)
	return cost


func repair_outpost(node_id: StringName) -> bool:
	if not outposts.has(node_id) or not outposts[node_id]["damaged"] or not Economy.can_afford(outpost_repair_cost(node_id)):
		return false
	Economy.apply(_negated(outpost_repair_cost(node_id)))
	outposts[node_id]["damaged"] = false
	outposts[node_id]["durability"] = OutpostRules.DURABILITY
	outposts_changed.emit()
	return true


## Directions covered by active outposts.
func outpost_directions() -> Array[StringName]:
	var out: Array[StringName] = []
	for node_id in active_outposts():
		var d: StringName = outposts[node_id]["direction"]
		if d != &"" and not d in out:
			out.append(d)
	return out


## Evening: finished outposts, upkeep (식량 2/곳) and gathering (나무·고철 +5/곳).
func _settle_outposts(produced: Dictionary, consumed: Dictionary, events: Array) -> void:
	for node_id: StringName in outposts:
		var o: Dictionary = outposts[node_id]
		if int(o["ready_day"]) == GameState.day:
			events.append(_event(&"outpost_ready", &"", "전초기지 완성 (%s)" % _outpost_label(node_id)))
		if not is_outpost_active(node_id):
			continue
		for res: StringName in OutpostRules.UPKEEP:
			consumed[res] = consumed.get(res, 0.0) + OutpostRules.UPKEEP[res]
		for res: StringName in OutpostRules.GATHER:
			produced[res] = produced.get(res, 0.0) + OutpostRules.GATHER[res]


## A raid aimed at an outpost: its garrison and walls against the raid. Lost → damaged (멈춤) and the
## garrison is hurt. The base takes no damage. Same result format as resolve_raid().
func _resolve_outpost_raid(raid: Dictionary, mode: Enums.RaidMode) -> Dictionary:
	var node_id := StringName(raid["target"])
	var strength := maxf(float(raid.get("strength", 1.0)), 0.1)
	var garrison := garrison_of(node_id)
	var defense := OutpostRules.BASE_DEFENSE if not outposts[node_id]["damaged"] else 0.0
	for id in garrison:
		var weapon := Armory.get_item_stats(Armory.get_equipped(id, Enums.EquipSlot.MAIN))
		defense += RaidRules.guard_power(residents[id], weapon, float(Armory.get_owner_summary(id)["defense"]))
	var ratio := defense / strength
	if mode == Enums.RaidMode.PLAYED:
		ratio *= RaidRules.PLAYED_BONUS
	var outcome := RaidRules.outcome_for(ratio)
	var casualties: Array = []
	var summary: Array[String] = ["마물이 %s을(를) 덮쳤다 (강도 %.0f, 방어 %.1f)." % [_outpost_label(node_id), strength, defense]]
	var damage := {"damaged": [], "durability_loss": {}, "resources_lost": {}}
	if outcome == Enums.RaidOutcome.LOSS or outcome == Enums.RaidOutcome.NARROW:
		outposts[node_id]["damaged"] = true
		outposts[node_id]["durability"] = 0
		damage["damaged"].append(node_id)
		_hurt(garrison, OutpostRules.LOST_INJURY_CHANCE, 0.0, 0.0, casualties)
		summary.append("전초기지가 무너졌다. 주둔 주민이 다쳤다.")
	else:
		summary.append("전초기지가 버텼다.")
	threat = RaidRules.THREAT_AFTER_LOSS if outcome == Enums.RaidOutcome.LOSS else RaidRules.THREAT_AFTER_WIN
	var result := {
		"raid_id": raid.get("raid_id", &""), "day": GameState.day, "time": raid.get("time", Enums.RaidTime.NIGHT),
		"mode": mode, "ratio": snappedf(ratio, 0.01), "outcome": outcome, "damage": damage, "used": {},
		"casualties": casualties, "loot": {}, "summary": summary, "target": node_id,
	}
	active_raid = {}
	outposts_changed.emit()
	EventBus.raid_resolved.emit(result)
	return result


func _outpost_ready(node_id: StringName) -> bool:
	return outposts.has(node_id) and GameState.day >= int(outposts[node_id]["ready_day"])


func _outpost_label(node_id: StringName) -> String:
	var o: Dictionary = outposts.get(node_id, _outpost_node_defs().get(node_id, {}))
	if o.get("direction", &"") != &"":
		return "%s 전초기지" % _direction_text([o["direction"]])
	return "%s 입구 전초기지" % o.get("region_id", node_id)


## node_id -> {direction, region_id}: the 4 direction nodes and one per data/regions entry.
func _outpost_node_defs() -> Dictionary:
	if _outpost_nodes_cache.is_empty():
		for node_id: StringName in OutpostRules.DIRECTION_NODES:
			_outpost_nodes_cache[node_id] = {"direction": OutpostRules.DIRECTION_NODES[node_id], "region_id": &""}
		# Regions are data/regions/<id>.tres (RegionDef) and/or data/regions/<id>/ folders (rescues).
		var regions: Array[String] = []
		var dir := DirAccess.open(OutpostRules.REGIONS_DIR)
		if dir != null:
			for f in dir.get_files():
				var file := f.trim_suffix(".remap")
				if file.ends_with(".tres") and not file.get_basename() in regions:
					regions.append(file.get_basename())
			for d in dir.get_directories():
				if not d in regions:
					regions.append(d)
		regions.sort()
		for region in regions:
			_outpost_nodes_cache[StringName(OutpostRules.REGION_NODE_PREFIX + region)] = {"direction": &"", "region_id": StringName(region)}
	return _outpost_nodes_cache


# --- 고립·실종·사망·추모 (C-20) ------------------------------------------------------------
## 고립: companion_stranded → status STRANDED with strand_days_left (Settings strand_days, -1 = 기한
## 없음). Each evening one day passes; at 0 the resident goes missing (MISSING, 장비 유실).
## A stranded resident rescued in the field comes home through rescue_completed (resident dict).
## 사망: _kill() → 동료 사기, 슬픔, 추모비 기록, 보호자 승계, next morning's funeral.

## Stranded residents: [{"resident_id", "region_id", "days_left" (-1 = no limit)}] for B's rescue
## spawns, the radio and the residents screen.
func stranded_residents() -> Array:
	var out: Array = []
	for id: StringName in residents:
		var r: Dictionary = residents[id]
		if int(r["status"]) == Enums.ResidentStatus.STRANDED:
			out.append({"resident_id": id, "region_id": r["stranded_region"], "days_left": r["strand_days_left"]})
	return out


## Stranded residents in one region (B-10/B-11 spawn them as fixed rescue targets).
func stranded_in(region_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for s in stranded_residents():
		if s["region_id"] == region_id:
			out.append(s["resident_id"])
	return out


## Memorial stone names: [{"resident_id", "name", "day", "cause"}], oldest first.
func memorial_names() -> Array:
	return memorials.duplicate(true)


## Residents whose funeral is shown this morning (D plays the scene, then calls end_funeral()).
func pending_funeral() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in funerals:
		out.append(StringName(id))
	return out


func end_funeral() -> void:
	funerals = []


## 추모비 방문 (밤, 하루 한 번): 슬픔 −1일 (추모비 효과), 사기 +3. Returns {"ok", "reason"}.
func visit_memorial(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or int(r["status"]) != Enums.ResidentStatus.ACTIVE:
		return {"ok": false, "reason": "없는 주민"}
	var stones := working_building_ids(LossRules.MEMORIAL)
	if stones.is_empty():
		return {"ok": false, "reason": "추모비가 없음"}
	if int(r["memorial_day"]) == GameState.day:
		return {"ok": false, "reason": "오늘은 이미 다녀왔다"}
	r["memorial_day"] = GameState.day
	r["grief_days"] = maxi(int(r["grief_days"]) - roundi(building_effect(stones[0], &"grief_recovery", 1.0)), 0)
	r["morale"] = NeedsRules.apply_morale(r, LossRules.MEMORIAL_VISIT_MORALE)
	return {"ok": true, "reason": ""}


## Still part of the base (active, or stranded and coming back): not dead or missing.
func _present(resident_id: StringName) -> bool:
	return residents.has(resident_id) and int(residents[resident_id]["status"]) in [Enums.ResidentStatus.ACTIVE, Enums.ResidentStatus.STRANDED]


## 슬픔 중이면 작업 효율 −20%.
func _grief_mult(resident_id: StringName) -> float:
	return LossRules.GRIEF_WORK_MULT if int(residents[resident_id]["grief_days"]) > 0 else 1.0


func _on_companion_stranded(resident_id: StringName, region_id: StringName) -> void:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or int(r["status"]) != Enums.ResidentStatus.ACTIVE:
		return
	unassign_job(resident_id)
	r["status"] = Enums.ResidentStatus.STRANDED
	r["stranded_region"] = region_id
	var days := int(Settings.get_value(LossRules.STRAND_SETTING))
	r["strand_days_left"] = days if days > 0 else -1


## Evening: one day passes for stranded residents, grief eases.
func _settle_loss(events: Array) -> void:
	for id: StringName in residents.keys():
		var r: Dictionary = residents[id]
		match int(r["status"]):
			Enums.ResidentStatus.STRANDED:
				if int(r["strand_days_left"]) < 0:
					continue
				r["strand_days_left"] = int(r["strand_days_left"]) - 1
				if int(r["strand_days_left"]) <= 0:
					_go_missing(id, events)
			Enums.ResidentStatus.ACTIVE:
				if int(r["grief_days"]) > 0:
					r["grief_days"] = int(r["grief_days"]) - 1


## 실종: permanent, the equipment is lost with them, children get another guardian.
func _go_missing(id: StringName, events: Array) -> void:
	var r: Dictionary = residents[id]
	r["status"] = Enums.ResidentStatus.MISSING
	r["strand_days_left"] = 0
	release_bed(id)
	for slot in Armory.list_equipped(id):
		var item: StringName = Armory.list_equipped(id)[slot]
		if item != &"":
			Armory.remove_item(item)
	_end_partnership(id)
	_pass_guardianship(id, events)
	events.append(_event(&"missing", id, "%s을(를) 끝내 찾지 못했다" % _display_name(r)))
	resident_missing.emit(id)


## After a death: coworkers' morale, grief, the memorial, guardianship, tomorrow's funeral.
func _after_death(id: StringName, cause: StringName) -> void:
	var dead: Dictionary = residents[id]
	var spouse := partner_of(id)
	var married := spouse != &"" and Enums.RelationFlag.MARRIED in relation_flags(id, spouse)
	for other in active_resident_ids():
		var r: Dictionary = residents[other]
		var closeness := clampf(relation(id, other) / 100.0, 0.0, 1.0)
		r["morale"] = NeedsRules.apply_morale(r, roundi(lerpf(LossRules.DEATH_MORALE_MIN, LossRules.DEATH_MORALE_MAX, closeness)))
		var grief := 0
		if other == spouse and married:
			grief = LossRules.GRIEF_SPOUSE_DAYS
		elif other == spouse or relation(id, other) >= LossRules.GRIEF_CLOSE_AT \
				or Enums.RelationFlag.GUARDIAN in relation_flags(id, other):
			grief = LossRules.GRIEF_DAYS
		r["grief_days"] = maxi(int(r["grief_days"]), grief)
	memorials.append({"resident_id": id, "name": _display_name(dead), "day": GameState.day, "cause": cause})
	GameState.set_flag(LossRules.FIRST_DEATH_FLAG)
	if not id in funerals:
		funerals.append(id)
	_end_partnership(id)
	_pass_guardianship(id, [])


## The lovers / married flags end when one of them dies or goes missing (the other is not re-matched).
func _end_partnership(id: StringName) -> void:
	var partner := partner_of(id)
	if partner == &"":
		return
	var m := _relation_meta(id, partner)
	m["flags"] = m["flags"].filter(func(f): return f != Enums.RelationFlag.LOVERS and f != Enums.RelationFlag.MARRIED)
	m["engaged"] = false
	m["wedding_ready"] = false


## 보호자 승계: a child who lost every guardian gets the adult they are closest to.
func _pass_guardianship(gone: StringName, events: Array) -> void:
	for key: String in relation_meta.keys():
		var m: Dictionary = relation_meta[key]
		if not Enums.RelationFlag.GUARDIAN in m["flags"] or not gone in [m["a"], m["b"]]:
			continue
		var child: StringName = m["b"] if m["a"] == gone else m["a"]
		if not residents.has(child) or not ChildRules.is_minor(residents[child]) or not guardians_of(child).is_empty():
			continue
		var best := &""
		var best_value := -1000
		for other in active_resident_ids():
			if other == child or ChildRules.is_minor(residents[other]):
				continue
			if relation(child, other) > best_value:
				best = other
				best_value = relation(child, other)
		if best == &"":
			continue
		var g := _relation_meta(best, child)
		if not Enums.RelationFlag.GUARDIAN in g["flags"]:
			g["flags"].append(Enums.RelationFlag.GUARDIAN)
		events.append(_event(&"guardian", child, "%s이(가) %s을(를) 맡아 돌보기로 했다" % [_display_name(residents[best]), _display_name(residents[child])]))
		guardian_changed.emit(child, best)


# --- 편견 이벤트 체인 (C-16, 08 "편견과 갈등") ---------------------------------------------
## One chain per resident with 마물 흔적: prejudice_chains[target_id] = {target, holders: Array,
## step (PrejudiceRules.STEP_*), choice, started_day, incident_day, incident}. Lane D shows the
## rumor choice (prejudice_rumor → choose_prejudice_response) and the incident; the resolution is
## the night event "prejudice_talk" (C-14 pool), one per holder.

## All chains (copies), for screens and the journal.
func prejudice_chains() -> Dictionary:
	return prejudice_chains_data.duplicate(true)


## The chain about `target_id` ({} = none).
func prejudice_chain(target_id: StringName) -> Dictionary:
	return prejudice_chains_data.get(target_id, {}).duplicate(true)


## The player's answer to the rumor: PrejudiceRules.CHOICE_DEFEND / WATCH / SEPARATE.
## Returns {"ok", "reason", "incident_day"}.
func choose_prejudice_response(target_id: StringName, choice: StringName) -> Dictionary:
	var c: Dictionary = prejudice_chains_data.get(target_id, {})
	if c.is_empty() or c["step"] != PrejudiceRules.STEP_RUMOR:
		return {"ok": false, "reason": "선택을 기다리는 소문이 없음", "incident_day": 0}
	if not choice in PrejudiceRules.CHOICES:
		return {"ok": false, "reason": "없는 선택: %s" % choice, "incident_day": 0}
	var r: Dictionary = residents[target_id]
	var delay := _rng.randi_range(PrejudiceRules.INCIDENT_DAYS.x, PrejudiceRules.INCIDENT_DAYS.y)
	match choice:
		PrejudiceRules.CHOICE_DEFEND:
			add_trust(target_id, PrejudiceRules.DEFEND_TRUST, &"defended")
			r["morale"] = NeedsRules.apply_morale(r, PrejudiceRules.DEFEND_MORALE)
		PrejudiceRules.CHOICE_SEPARATE:
			r["morale"] = NeedsRules.apply_morale(r, PrejudiceRules.SEPARATE_MORALE)
			release_bed(target_id)  # 따로 지낸다: 임시 거처
			delay += PrejudiceRules.SEPARATE_EXTRA_DAYS
	c["choice"] = choice
	c["step"] = PrejudiceRules.STEP_WAITING
	c["incident_day"] = GameState.day + delay
	return {"ok": true, "reason": "", "incident_day": c["incident_day"]}


## Daily part of the settlement: start a rumor, or bring a waiting chain to its incident.
func _settle_prejudice(events: Array) -> void:
	var today := GameState.day
	var holders := _prejudice_holders()
	for id in active_resident_ids():
		var r: Dictionary = residents[id]
		if not _has_trait(r, PrejudiceRules.TARGET_TRAIT):
			continue
		var c: Dictionary = prejudice_chains_data.get(id, {})
		if c.is_empty():
			if not holders.is_empty() and today - int(r["joined_day"]) >= PrejudiceRules.RUMOR_AFTER_DAYS \
					and _rng.randf() < PrejudiceRules.RUMOR_CHANCE:
				_start_rumor(id, holders, events)
		elif c["step"] == PrejudiceRules.STEP_WAITING and today >= int(c["incident_day"]):
			_prejudice_incident(c, events)


func _start_rumor(target_id: StringName, holders: Array[StringName], events: Array) -> void:
	prejudice_chains_data[target_id] = {"target": target_id, "holders": holders.duplicate(), "step": PrejudiceRules.STEP_RUMOR,
		"choice": &"", "started_day": GameState.day, "incident_day": 0, "incident": &""}
	for id in active_resident_ids():
		residents[id]["morale"] = NeedsRules.apply_morale(residents[id], PrejudiceRules.RUMOR_MORALE)
	var text := "\"%s이(가) 언젠가 마물이 된다\"는 말이 돈다" % _display_name(residents[target_id])
	events.append(_event(&"prejudice_rumor", target_id, text))
	EventBus.notification_posted.emit(text, &"warning")
	prejudice_rumor.emit(target_id, holders.duplicate())


## 사건: the marked resident saves someone, or solves a crisis at the essence workshop.
func _prejudice_incident(c: Dictionary, events: Array) -> void:
	var target: StringName = c["target"]
	var who := _display_name(residents[target])
	c["step"] = PrejudiceRules.STEP_INCIDENT
	if target in facility_workers(PrejudiceRules.WORKSHOP):
		c["incident"] = PrejudiceRules.INCIDENT_WORKSHOP
		for id in active_resident_ids():
			residents[id]["morale"] = NeedsRules.apply_morale(residents[id], PrejudiceRules.WORKSHOP_MORALE)
		events.append(_event(&"prejudice_incident", target, "%s이(가) 정수 공방에서 기지의 위기를 막았다" % who))
	else:
		c["incident"] = PrejudiceRules.INCIDENT_RESCUE
		var saved: StringName = &""
		for h in c["holders"]:
			if residents.has(h):
				saved = h
				break
		if saved != &"":
			add_relation(target, saved, PrejudiceRules.RESCUE_RELATION, &"saved")
		events.append(_event(&"prejudice_incident", target, "%s이(가) %s을(를) 구했다" % [who,
			_display_name(residents[saved]) if saved != &"" else "동료"]))
	prejudice_incident.emit(target, c["incident"])


## 해소 대화 (night event prejudice_talk): the holder's prejudice goes away, relation +20, the
## target's story is shown. Returns the target's fragments now revealed.
func _resolve_prejudice(holder: StringName, target: StringName) -> Array[String]:
	var c: Dictionary = prejudice_chains_data.get(target, {})
	var revealed: Array[String] = []
	if c.is_empty() or not residents.has(holder) or not residents.has(target):
		return revealed
	var h: Dictionary = residents[holder]
	var def := BaseDB.get_trait(PrejudiceRules.HOLDER_TRAIT)
	if def != null and def.removable:
		h["traits"].erase(PrejudiceRules.HOLDER_TRAIT)
	add_relation(holder, target, PrejudiceRules.RESOLVE_RELATION, &"reconciled")
	c["holders"].erase(holder)
	residents[target]["story_revealed"] = true
	for f in residents[target]["story"]["fragments"]:
		revealed.append(String(f))
	if c["holders"].filter(func(x): return residents.has(x)).is_empty():
		c["step"] = PrejudiceRules.STEP_RESOLVED
	Journal.record(&"prejudice_resolved", {"resident_id": holder, "other_id": target})
	prejudice_resolved.emit(holder, target)
	return revealed


func _prejudice_holders() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		if _has_trait(residents[id], PrejudiceRules.HOLDER_TRAIT):
			out.append(id)
	return out


func _has_trait(r: Dictionary, trait_id: StringName) -> bool:
	for t in r["traits"]:
		if StringName(t) == trait_id:
			return true
	return false


# --- 입주 의식 (C-13, 07 "입주 의식") ---------------------------------------------------
## A rescued survivor joins with arrival_pending = true. Lane D's ceremony screen (D-13) walks the
## steps (ArrivalRules.STEPS) with these calls and ends with complete_arrival(). Residents gather at
## the base to greet them meanwhile (ResidentCrowd, activity &"welcome").

## Residents waiting for their 입주 의식, oldest first.
func pending_arrivals() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in active_resident_ids():
		if residents[id]["arrival_pending"]:
			out.append(id)
	return out


## Everything the ceremony screen needs for one resident:
## {resident_id, name, nickname, age_stage, appearance (CharacterLook form), steps, hair_styles,
##  bed_id, beds: [{bed_id, building_uid, building_name}], nickname_max}.
func arrival_info(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return {}
	var choices: Array = []
	for bed_id in free_beds():
		var uid := _bed_building(bed_id)
		choices.append({"bed_id": bed_id, "building_uid": uid,
			"building_name": _def_name(buildings[uid]["def_id"]) if buildings.has(uid) else "방송실 야영지"})
	return {
		"resident_id": resident_id, "name": r["name"], "nickname": r["nickname"], "age_stage": r["age_stage"],
		"appearance": appearance_for_look(resident_id), "steps": ArrivalRules.STEPS.duplicate(),
		"hair_styles": ArrivalRules.HAIR_STYLES.duplicate(), "bed_id": r["bed_id"], "beds": choices,
		"nickname_max": ArrivalRules.NICKNAME_MAX,
	}


## 별명 짓기 (empty = no nickname). Returns {"ok", "reason"}.
func set_nickname(resident_id: StringName, nickname: String) -> Dictionary:
	if not residents.has(resident_id):
		return {"ok": false, "reason": "없는 주민"}
	var check := ArrivalRules.check_nickname(nickname, ResidentTemplate.load_banned_words())
	if check["ok"]:
		residents[resident_id]["nickname"] = check["nickname"]
		resident_profile_changed.emit(resident_id)
	return {"ok": check["ok"], "reason": check["reason"]}


## 외형 꾸미기: keys preset, hair, hair_color, outfit_color, outfit_accent, skin (Color or "#rrggbb").
## Merged into what the resident has. Returns {"ok", "reason"}.
func set_appearance(resident_id: StringName, appearance: Dictionary) -> Dictionary:
	if not residents.has(resident_id):
		return {"ok": false, "reason": "없는 주민"}
	var clean := ArrivalRules.clean_appearance(appearance)
	if clean["ok"]:
		residents[resident_id]["appearance"].merge(clean["appearance"], true)
		resident_profile_changed.emit(resident_id)
	return {"ok": clean["ok"], "reason": clean["reason"]}


## The resident's look for CharacterLook.apply(): colours as Color, a default preset when none was
## picked yet (by age, ResidentAgent.default_preset).
func appearance_for_look(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return {}
	var look := ArrivalRules.to_look(r["appearance"])
	if not look.has("preset"):
		look["preset"] = ResidentAgent.default_preset(r)
	return look


## 침상 배정: a free bed, or &"" for 임시 거처 (사기 −10/일). Returns false if the bed is taken.
func choose_bed(resident_id: StringName, bed_id: StringName) -> bool:
	if not residents.has(resident_id):
		return false
	if bed_id == residents[resident_id]["bed_id"]:
		return true
	if bed_id != &"" and (not beds.has(bed_id) or beds[bed_id] != &""):
		return false
	release_bed(resident_id)
	return bed_id == &"" or assign_bed(resident_id, bed_id)


## 첫 대화 and the end of the ceremony: tells the story's first piece (background) and one like,
## counts as today's talk (+3 trust when not talked yet). Returns {"ok", "first_line", "background", "like"}.
func complete_arrival(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty() or not r["arrival_pending"]:
		return {"ok": false, "first_line": "", "background": "", "like": &""}
	r["arrival_pending"] = false
	var like: StringName = r["likes"][0] if not r["likes"].is_empty() else &""
	if like != &"" and not like in r["known_likes"]:
		r["known_likes"].append(like)
	if trust_actions(resident_id).get("talk", false):
		talk(resident_id)
	var result := {"ok": true, "first_line": r["story"]["first_line"], "background": r["story"]["background"], "like": like}
	arrival_completed.emit(resident_id, result)
	EventBus.notification_posted.emit("%s이(가) 기지 식구가 되었다" % _display_name(r), &"info")
	return result


## Likes the player knows about (첫 대화, liked gifts). Screens show only these.
func known_likes(resident_id: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for like in residents.get(resident_id, {}).get("known_likes", []):
		out.append(StringName(like))
	return out


## A liked gift tells the player which like it matched (the tag, or the resource id itself).
func _learn_like(resident_id: StringName, resource_id: StringName) -> void:
	var r: Dictionary = residents[resident_id]
	for like: StringName in r["likes"]:
		if (like == resource_id or resource_id in TrustRules.GIFT_TAGS.get(like, [])) and not like in r["known_likes"]:
			r["known_likes"].append(like)
			return


func _display_name(r: Dictionary) -> String:
	return String(r["nickname"]) if String(r["nickname"]) != "" else String(r["name"])


func _bed_building(bed_id: StringName) -> StringName:
	var s := String(bed_id)
	return &"" if s.begins_with(START_BED_PREFIX) else StringName(s.get_slice("_bed_", 0))


# --- Trust, talk, gifts (C-12, 07 "신뢰도") ---------------------------------------
## Lines come from Lane A (Radio / AI 대화); the resident screen is D-13. Colony only keeps the numbers.

## Adds trust (clamped 0..100) and returns the new value (-1 = no such resident).
## A-13 calls this for 개인 요청 완료 (+20). `reason` tags the change for trust_changed listeners.
## Emits trust_changed, and a notification when a new stage opens.
func add_trust(resident_id: StringName, amount: int, reason: StringName = &"") -> int:
	if not residents.has(resident_id):
		return -1
	var r: Dictionary = residents[resident_id]
	var before := int(r["trust"])
	var after := clampi(before + amount, 0, 100)
	r["trust"] = after
	var stage := TrustRules.stage_of(after)
	if after != before:
		trust_changed.emit(resident_id, after, stage, reason)
	if stage > TrustRules.stage_of(before):
		EventBus.notification_posted.emit("%s와(과) %s 사이가 되었다 (%s)" % [r["name"], TrustRules.STAGE_NAMES[stage],
			TrustRules.STAGE_UNLOCKS[stage]], &"info")
	return after


## 0 낯섬 .. 4 가족 같은 (TrustRules.STAGE_NAMES).
func trust_stage(resident_id: StringName) -> int:
	return TrustRules.stage_of(int(residents.get(resident_id, {}).get("trust", 0)))


## Story fragments the player has opened so far (사연 1 at 경계 풀림, 사연 2 at 가까움).
func unlocked_story(resident_id: StringName) -> Array[String]:
	var out: Array[String] = []
	var r: Dictionary = residents.get(resident_id, {})
	if r.is_empty():
		return out
	if r.get("story_revealed", false):  # 편견 해소 (C-16): 사연 공개
		for f in r["story"]["fragments"]:
			out.append(String(f))
		return out
	var stage := trust_stage(resident_id)
	var fragments: Array = r["story"]["fragments"]
	for i in mini(fragments.size(), TrustRules.FRAGMENT_STAGES.size()):
		if stage >= TrustRules.FRAGMENT_STAGES[i]:
			out.append(String(fragments[i]))
	return out


## What the player may still do with this resident today: {"talk", "gift", "deep_talk": bool}.
func trust_actions(resident_id: StringName) -> Dictionary:
	var r: Dictionary = residents.get(resident_id, {})
	var here := not r.is_empty() and int(r["status"]) == Enums.ResidentStatus.ACTIVE
	var today := GameState.day
	return {
		"talk": here and int(r["talked_day"]) != today,
		"gift": here and int(r["gift_day"]) != today,
		"deep_talk": here and SceneRouter.stayed_today and deep_talk_day != today,
	}


## 하루 대화 1회 (+3). Returns {"ok", "reason", "trust"}.
func talk(resident_id: StringName) -> Dictionary:
	if not trust_actions(resident_id).get("talk", false):
		return {"ok": false, "reason": "오늘은 이미 이야기했다" if residents.has(resident_id) else "없는 주민", "trust": -1}
	residents[resident_id]["talked_day"] = GameState.day
	return {"ok": true, "reason": "", "trust": add_trust(resident_id, TrustRules.TALK, &"talk")}


## 머무르기 날 깊은 대화 (기획 01: 주민 1명과 1회 추가, 하루 1번). Also uses up that day's talk.
func deep_talk(resident_id: StringName) -> Dictionary:
	if not trust_actions(resident_id).get("deep_talk", false):
		var why := "없는 주민"
		if residents.has(resident_id):
			why = "머무르는 날만" if not SceneRouter.stayed_today else "오늘 깊은 대화는 이미 했다"
		return {"ok": false, "reason": why, "trust": -1}
	deep_talk_day = GameState.day
	residents[resident_id]["talked_day"] = GameState.day
	return {"ok": true, "reason": "", "trust": add_trust(resident_id, TrustRules.DEEP_TALK, &"deep_talk")}


## &"liked" / &"normal" / &"disliked" for giving `resource_id` (TrustRules.gift_reaction).
func gift_reaction(resident_id: StringName, resource_id: StringName) -> StringName:
	return TrustRules.gift_reaction(residents.get(resident_id, {}), resource_id)


## 선물 (하루 1번): takes 1 from Economy. Returns {"ok", "reason", "reaction", "trust"}.
func give_gift(resident_id: StringName, resource_id: StringName) -> Dictionary:
	if not trust_actions(resident_id).get("gift", false):
		return {"ok": false, "reason": "오늘은 이미 선물했다" if residents.has(resident_id) else "없는 주민", "reaction": &"", "trust": -1}
	if Economy.get_amount(resource_id) < 1:
		return {"ok": false, "reason": "%s이(가) 없다" % resource_id, "reaction": &"", "trust": -1}
	Economy.apply({resource_id: -1})
	residents[resident_id]["gift_day"] = GameState.day
	var reaction := gift_reaction(resident_id, resource_id)
	if reaction == &"liked":
		_learn_like(resident_id, resource_id)
	var amount: int = TrustRules.GIFT_AMOUNT[reaction]
	return {"ok": true, "reason": "", "reaction": reaction, "trust": add_trust(resident_id, amount, &"gift")}


## 함께 출격해 살아 돌아옴 +5 (companions who are not stranded).
func _on_sortie_ended(result: Dictionary) -> void:
	var stranded: Array = result.get("stranded", [])
	var back: Array[StringName] = []
	for c in result.get("companions", []):
		var id := StringName(c)
		if not id in stranded and residents.has(id) and int(residents[id]["status"]) == Enums.ResidentStatus.ACTIVE:
			add_trust(id, TrustRules.SORTIE_RETURN, &"sortie_return")
			back.append(id)
	_sortie_relations(back)
	_finish_field_raid(result)  # 출격 중 낮 습격 (C-21)


## Injury countdown (의무실이 있으면 1일), sickness (겨울·배고픔), contagion, medicine cures.
func _settle_health(consumed: Dictionary, events: Array) -> void:
	var heal_slots := 0
	for medic in facility_workers(&"infirmary"):
		if WorkRules.can_work(residents[medic]):
			heal_slots += int(BaseDB.get_job(&"medical").effects.get(&"heal_per_day", 2.0))
	var medicine_left: float = Economy.get_amount(&"medicine") - float(consumed.get(&"medicine", 0.0))
	var winter := GameState.season() == Enums.Season.WINTER
	var sick_now := 0
	for id in active_resident_ids():
		if int(residents[id]["health"]) == Enums.HealthState.SICK:
			sick_now += 1
	for id in active_resident_ids():
		var r: Dictionary = residents[id]
		match int(r["health"]):
			Enums.HealthState.INJURED:
				if heal_slots > 0:
					heal_slots -= 1
					r["recover_days"] = mini(int(r["recover_days"]), NeedsRules.INFIRMARY_RECOVER_DAYS)
				r["recover_days"] = int(r["recover_days"]) - 1
				if r["recover_days"] <= 0:
					_recover(id, events)
			Enums.HealthState.SICK:
				if heal_slots > 0 and medicine_left >= NeedsRules.MEDICINE_PER_CURE:
					heal_slots -= 1
					medicine_left -= NeedsRules.MEDICINE_PER_CURE
					consumed[&"medicine"] = consumed.get(&"medicine", 0.0) + NeedsRules.MEDICINE_PER_CURE
					_recover(id, events)
				else:
					r["recover_days"] = int(r["recover_days"]) - 1
					if r["recover_days"] <= 0:
						# 질병 방치 (C-20): untreated and starving → may not make it (영구 사망일 때).
						if int(r["hunger"]) < WorkRules.HUNGRY_BELOW and bool(Settings.get_value(&"permadeath")) \
								and _rng.randf() < LossRules.NEGLECT_DEATH_CHANCE:
							events.append(_event(&"died", id, "%s이(가) 병을 이기지 못했다" % r["name"]))
							_kill(id, &"sickness")
						else:
							_recover(id, events)
			_:
				var chance := 0.0
				if winter or int(r["hunger"]) < WorkRules.HUNGRY_BELOW:
					chance = NeedsRules.SICK_CHANCE
				chance = 1.0 - (1.0 - chance) * pow(1.0 - NeedsRules.CONTAGION_CHANCE, sick_now)
				if chance > 0.0 and _rng.randf() < chance:
					r["health"] = Enums.HealthState.SICK
					r["recover_days"] = NeedsRules.SICK_DAYS
					events.append(_event(&"fell_sick", id, "%s이(가) 앓아누웠다" % r["name"]))


func _recover(id: StringName, events: Array) -> void:
	residents[id]["health"] = Enums.HealthState.OK
	residents[id]["recover_days"] = 0
	events.append(_event(&"recovered", id, "%s이(가) 회복했다" % residents[id]["name"]))


## Applies today's morale factors and handles 떠날 위기. Returns {resident_id: morale delta}.
func _settle_morale(ids: Array[StringName], ate_cooked: Dictionary, events: Array) -> Dictionary:
	var stranded := 0
	for id: StringName in residents:
		if int(residents[id]["status"]) == Enums.ResidentStatus.STRANDED:
			stranded += 1
	# 모닥불·식당: the best building of each kind counts once for everyone.
	var shared := {}
	for uid in working_building_ids():
		var def := BaseDB.get_building(buildings[uid]["def_id"])
		if def.category != BuildingDef.Category.HOUSING and def.effects.has(&"morale_daily"):
			shared[def.id] = maxf(shared.get(def.id, 0.0), building_effect(uid, &"morale_daily"))
	var shared_bonus := 0
	for v in shared.values():
		shared_bonus += roundi(v)
	for id in ids:
		if residents.has(id) and int(residents[id]["age_stage"]) == Enums.AgeStage.CHILD:
			shared_bonus += ChildRules.PLAY_MORALE  # 아이 놀이 (08 "성장")
			break
	if is_festival_today():
		shared_bonus += RelationRules.FESTIVAL_MORALE
	var deltas := {}
	for id in ids:
		if not residents.has(id) or int(residents[id]["status"]) != Enums.ResidentStatus.ACTIVE:
			continue
		var r: Dictionary = residents[id]
		var coworkers: Array = []
		for w in _coworker_ids(id):
			coworkers.append(residents[w])
		var bed := String(r["bed_id"])
		var home_bonus := 0
		if bed != "" and not bed.begins_with(START_BED_PREFIX):
			home_bonus = roundi(building_effect(StringName(bed.get_slice("_bed_", 0)), &"morale_daily"))
		var ctx := {
			"job_id": job_of(id), "coworkers": coworkers, "ate_cooked": ate_cooked.has(id),
			"has_bed": bed != "", "living_bonus": shared_bonus + home_bonus, "stranded_count": stranded,
		}
		var before := int(r["morale"])
		r["morale"] = NeedsRules.apply_morale(r, NeedsRules.daily_morale(r, ctx))
		deltas[id] = int(r["morale"]) - before
		# 떠날 위기: yesterday's crisis not resolved → leaves; 3 low days in a row → crisis.
		if int(r["morale"]) >= NeedsRules.CRISIS_MORALE:
			r["low_morale_days"] = 0
			r["leave_crisis"] = false
			continue
		r["low_morale_days"] = int(r["low_morale_days"]) + 1
		if r["leave_crisis"]:
			events.append(_event(&"resident_left", id, "%s이(가) 기지를 떠났다" % r["name"]))
			_leave(id, &"low_morale")
		elif r["low_morale_days"] >= NeedsRules.CRISIS_DAYS:
			r["leave_crisis"] = true
			events.append(_event(&"leave_crisis", id, "%s이(가) 떠나려 한다 (신뢰 %d)" % [r["name"], r["trust"]]))
	return deltas


func _leave(id: StringName, reason: StringName) -> void:
	unassign_job(id)
	release_bed(id)
	residents.erase(id)
	EventBus.resident_left.emit(id, reason)


## A rescued profile that is already a stranded/missing resident comes home instead of becoming a
## second copy (B-10 sends the resident's own dictionary when rescuing a stranded companion).
func _on_rescue_completed(rescued: Dictionary) -> void:
	var id := StringName(rescued.get("id", &""))
	if residents.has(id) and int(residents[id]["status"]) in [Enums.ResidentStatus.STRANDED, Enums.ResidentStatus.MISSING]:
		residents[id]["status"] = Enums.ResidentStatus.ACTIVE
		residents[id]["stranded_region"] = &""
		residents[id]["strand_days_left"] = 0
		add_trust(id, TrustRules.RESCUED_FROM_STRAND, &"rescued")
		var free := free_beds()
		if residents[id]["bed_id"] == &"" and not free.is_empty():
			assign_bed(id, free[0])
		EventBus.resident_joined.emit(id)
		return
	# A new survivor: 입주 의식 (C-13) is still to come.
	var new_id := add_resident(rescued.merged({"arrival_pending": true}, true))
	if new_id != &"":
		arrival_ready.emit(new_id)
		_adopt_rescued(new_id)


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
	clear_progress = {}
	clear_started = {}
	beds = {}
	var start: Array[StringName] = []
	for i in START_BED_COUNT:
		start.append(StringName("%s%d" % [START_BED_PREFIX, i + 1]))
	add_beds(start)
	buildings = {}
	power_priority_override = {}
	_next_building_num = 1
	# Rooms that exist from the start (방송실, 공터 남쪽 야영지). uid = def id.
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
	deep_talk_day = 0
	relation_meta = {}
	festival_day = 0
	night_queue = []
	current_night_event = {}
	last_night_results = []
	last_night_raid_day = 0
	_night_rolled_day = 0
	prejudice_chains_data = {}
	memorials = []
	funerals = []
	outposts = {}
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
		"deep_talk_day": deep_talk_day,
		"relation_meta": relation_meta,
		"festival_day": festival_day,
		"prejudice_chains": prejudice_chains_data,
		"memorials": memorials,
		"funerals": funerals,
		"outposts": outposts,
		"cleared_zones": cleared_zones,
		"clear_progress": clear_progress,
		"clear_started": clear_started,
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
	deep_talk_day = int(data.get("deep_talk_day", 0))
	festival_day = int(data.get("festival_day", 0))
	prejudice_chains_data = {}
	memorials = Array(data.get("memorials", [])).map(func(m): return {"resident_id": StringName(m.get("resident_id", "")),
		"name": str(m.get("name", "")), "day": int(m.get("day", 0)), "cause": StringName(m.get("cause", ""))})
	funerals = Array(data.get("funerals", [])).map(func(x): return StringName(x))
	outposts = {}
	var saved_outposts: Dictionary = data.get("outposts", {})
	for key in saved_outposts:
		var o: Dictionary = saved_outposts[key]
		outposts[StringName(key)] = {"node_id": StringName(key), "direction": StringName(o.get("direction", "")),
			"region_id": StringName(o.get("region_id", "")), "ready_day": int(o.get("ready_day", 0)),
			"damaged": bool(o.get("damaged", false)), "durability": int(o.get("durability", OutpostRules.DURABILITY))}
	var saved_chains: Dictionary = data.get("prejudice_chains", {})
	for key in saved_chains:
		var c: Dictionary = saved_chains[key]
		prejudice_chains_data[StringName(key)] = {"target": StringName(c.get("target", key)),
			"holders": Array(c.get("holders", [])).map(func(h): return StringName(h)), "step": StringName(c.get("step", "")),
			"choice": StringName(c.get("choice", "")), "started_day": int(c.get("started_day", 0)),
			"incident_day": int(c.get("incident_day", 0)), "incident": StringName(c.get("incident", ""))}
	relation_meta = {}
	var saved_meta: Dictionary = data.get("relation_meta", {})
	for key in saved_meta:
		var m: Dictionary = saved_meta[key]
		var flags: Array = []
		for f in m.get("flags", []):
			flags.append(int(f))
		relation_meta[String(key)] = {"a": StringName(m.get("a", "")), "b": StringName(m.get("b", "")), "flags": flags,
			"since_day": int(m.get("since_day", 0)), "last_day": int(m.get("last_day", 0)), "low_days": int(m.get("low_days", 0)),
			"engaged": bool(m.get("engaged", false)), "wedding_ready": bool(m.get("wedding_ready", false)),
			"house_uid": StringName(m.get("house_uid", "")),
			# 아이 맞이 (C-15)
			"children": Array(m.get("children", [])).map(func(c): return StringName(c)),
			"last_child_day": int(m.get("last_child_day", 0)), "wish_day": int(m.get("wish_day", 0)),
			"carrier": StringName(m.get("carrier", "")), "due_day": int(m.get("due_day", 0)),
			"adoption_waiting": bool(m.get("adoption_waiting", false))}
	cleared_zones = {}
	for zone_id in data.get("cleared_zones", {}):
		cleared_zones[StringName(zone_id)] = true
	clear_progress = {}
	var saved_progress: Dictionary = data.get("clear_progress", {})
	for zone_id in saved_progress:
		clear_progress[StringName(zone_id)] = int(saved_progress[zone_id])
	clear_started = {}
	for zone_id in data.get("clear_started", {}):
		clear_started[StringName(zone_id)] = true
	threat = int(data.get("threat", 0))
	tier = int(data.get("tier", Enums.BaseTier.CAMP)) as Enums.BaseTier
	_refresh_effects()
	buildings_changed.emit()


# --- Debug console (debug builds only) -----------------------------------------

func _register_debug_commands() -> void:
	DebugConsole.register(&"resident", _cmd_resident,
		"resident add [demo 1~3] | list | persuade <id> | set <id> <morale|trust|hunger|fatigue> <n> - 주민 추가·목록·붙잡기·값 설정")
	DebugConsole.register(&"job", _cmd_job,
		"job <resident_id> <job_id> [building_uid] - 작업 배정 (job list: 직업 목록)")
	DebugConsole.register(&"settle", _cmd_settle,
		"settle - 하루 정산을 돌리고 Economy에 반영 (A-05 전 테스트용)")
	DebugConsole.register(&"trust", _cmd_trust,
		"trust <id> | trust talk|deep|add <id> [n] | trust gift <id> <resource_id> - 신뢰도·대화·선물")
	DebugConsole.register(&"outpost", _cmd_outpost,
		"outpost | outpost build <node> | post <node> <id> | repair <node> | raid <node> - 전초기지")
	DebugConsole.register(&"loss", _cmd_loss,
		"loss | loss strand <id> [region] | loss day | loss kill <id> | loss visit <id> - 고립·실종·사망·추모")
	DebugConsole.register(&"prejudice", _cmd_prejudice,
		"prejudice | prejudice rumor <id> | choose <id> defend|watch|separate | incident <id> - 편견 이벤트 체인")
	DebugConsole.register(&"child", _cmd_child,
		"child | child wish <a> <b> | child now <a> <b> birth|adopt | child later <a> <b> - 아이 맞이 (조건·대화·답)")
	DebugConsole.register(&"arrival", _cmd_arrival,
		"arrival | arrival <id> nick <별명> | preset <id> | bed <bed_id|none> | done - 입주 의식 (목록·별명·외형·침상·첫 대화)")
	DebugConsole.register(&"rel", _cmd_rel,
		"rel <id> | rel add <a> <b> <n> | rel night (오늘 밤 이벤트 뽑고 모두 진행) | rel wedding <a> <b> (결혼식 준비)")
	DebugConsole.register(&"zone", _cmd_zone,
		"zone list | zone clear <id> (즉시 개간) | job <주민> construction <zone_id> 로 개간 배정")
	DebugConsole.register(&"tier", func(_args: PackedStringArray) -> String:
		var s := next_tier_status()
		return "기지 단계 %s, 시설 상한 Lv%d. 다음: %s" % [Enums.BaseTier.keys()[tier], facility_level_cap(),
			"없음" if s["tier"] < 0 else ("조건 충족" if s["ok"] else ", ".join(PackedStringArray(s["missing"])))],
		"tier - 기지 단계와 다음 단계 조건")
	DebugConsole.register(&"repair", func(args: PackedStringArray) -> String:
		if args.is_empty():
			return "사용법: repair <building_uid> (비용을 내고 수리 시작 → job <주민> construction <uid>)"
		var check := can_repair(StringName(args[0]))
		if not check["ok"]:
			return "수리 불가: " + ", ".join(PackedStringArray(check["reasons"]))
		start_repair(StringName(args[0]))
		return "수리 시작: %s (비용 %s, 작업 %d)" % [args[0], check["cost"], repair_work_needed(StringName(args[0]))],
		"repair <building_uid> - 파손된 건물 수리 시작")
	DebugConsole.register(&"upgrade", func(args: PackedStringArray) -> String:
		if args.is_empty():
			return "사용법: upgrade <building_uid>"
		var check := can_upgrade(StringName(args[0]))
		if not check["ok"]:
			return "레벨업 불가: " + ", ".join(PackedStringArray(check["reasons"]))
		upgrade_building(StringName(args[0]))
		return "%s → Lv%d (비용 %s)" % [args[0], get_building(StringName(args[0]))["level"], check["cost"]],
		"upgrade <building_uid> - 시설 레벨업")
	DebugConsole.register(&"raid", _cmd_raid,
		"raid now [day|night] | raid threat <0~100> | raid info - 습격 강제·위협도 설정·방어력/예상")
	DebugConsole.register(&"build", _cmd_build,
		"build <building_id> | build list - 비용 없이 건물을 바로 완성 / 건물·전력·소음 목록")


func _cmd_outpost(args: PackedStringArray) -> String:
	var usage := "사용법: outpost | outpost build <node> | outpost post <node> <id> | outpost repair <node> | outpost raid <node>"
	if args.is_empty():
		var lines := PackedStringArray()
		for n in outpost_nodes():
			lines.append("  %s %s%s · 주둔 %s" % [n["node_id"], "가동" if n["active"] else ("부서짐" if n["damaged"] else ("완성" if n["ready"] else ("건설 중(%d일)" % n["ready_day"] if n["built"] else "빈 노드"))),
				"", n["garrison"]])
		return "\n".join(lines)
	if args.size() < 2:
		return usage
	var node_id := StringName(args[1])
	match args[0]:
		"build":
			var check := can_build_outpost(node_id)
			return "건설 시작 (%d일 뒤 완성)" % OutpostRules.BUILD_DAYS if build_outpost(node_id) else "실패: " + ", ".join(check["reasons"])
		"post":
			return "주둔: %s" % [garrison_of(node_id)] if args.size() > 2 and assign_garrison(node_id, StringName(args[2])) else "주둔시킬 수 없음"
		"repair":
			return "수리함" if repair_outpost(node_id) else "수리할 수 없음 (비용 %s)" % outpost_repair_cost(node_id)
		"raid":
			if not outposts.has(node_id):
				return "전초기지가 없음"
			var raid := roll_raid(Enums.RaidTime.NIGHT, true)
			raid["target"] = node_id
			return "\n".join(resolve_raid(raid, Enums.RaidMode.AUTO)["summary"])
	return usage


func _cmd_loss(args: PackedStringArray) -> String:
	var usage := "사용법: loss | loss strand <id> [region] | loss day | loss kill <id> | loss visit <id>"
	if args.is_empty():
		return "고립 %s · 추모비 %s · 장례 대기 %s" % [stranded_residents(), memorial_names(), pending_funeral()]
	var events: Array = []
	match args[0]:
		"day":
			_settle_loss(events)
			return "\n".join(PackedStringArray(events.map(func(e): return String(e["text"])))) if not events.is_empty() else "고립 하루 지남: %s" % [stranded_residents()]
	if args.size() < 2 or not residents.has(StringName(args[1])):
		return usage
	var id := StringName(args[1])
	match args[0]:
		"strand":
			_on_companion_stranded(id, StringName(args[2]) if args.size() > 2 else &"flooded_mall")
			return "%s 고립 (남은 날 %d)" % [id, residents[id]["strand_days_left"]]
		"kill":
			_kill(id, &"debug")
			return "%s 사망. 추모비 %s, 장례 대기 %s" % [id, memorial_names().size(), pending_funeral()]
		"visit":
			var res := visit_memorial(id)
			return "추모비 방문: 슬픔 %d일 남음" % residents[id]["grief_days"] if res["ok"] else "실패: " + String(res["reason"])
	return usage


func _cmd_prejudice(args: PackedStringArray) -> String:
	var usage := "사용법: prejudice | prejudice rumor <흔적 주민> | prejudice choose <흔적 주민> defend|watch|separate | prejudice incident <흔적 주민>"
	if args.is_empty():
		return "편견 체인: %s · 편견 가진 주민 %s" % [prejudice_chains_data if not prejudice_chains_data.is_empty() else "없음", _prejudice_holders()]
	if args.size() < 2 or not residents.has(StringName(args[1])):
		return usage
	var target := StringName(args[1])
	var events: Array = []
	match args[0]:
		"rumor":
			if prejudice_chains_data.has(target) or _prejudice_holders().is_empty():
				return "이미 체인이 있거나 편견을 가진 주민이 없음"
			_start_rumor(target, _prejudice_holders(), events)
			return events[0]["text"]
		"choose":
			var res := choose_prejudice_response(target, StringName(args[2]) if args.size() > 2 else &"")
			return "사건 예정일 %d일" % res["incident_day"] if res["ok"] else "실패: " + String(res["reason"])
		"incident":
			var c: Dictionary = prejudice_chains_data.get(target, {})
			if c.is_empty() or c["step"] != PrejudiceRules.STEP_WAITING:
				return "사건을 기다리는 체인이 아님"
			_prejudice_incident(c, events)
			return "%s (오늘 밤 해소 대화)" % events[0]["text"]
	return usage


func _cmd_child(args: PackedStringArray) -> String:
	var usage := "사용법: child | child wish <a> <b> | child now <a> <b> birth|adopt | child later <a> <b>"
	if args.is_empty():
		var lines := PackedStringArray()
		for pair in couples():
			var status := child_arrival_status(pair[0], pair[1])
			lines.append("%s+%s: %s · 아이 %s" % [pair[0], pair[1], "조건 충족" if status["ok"] else ", ".join(status["missing"]),
				children_of(pair[0], pair[1])])
		lines.append("대화 대기 %s · 보호자 없는 아이 %s" % [child_wishes(), orphans()])
		return "\n".join(lines)
	if args.size() < 3 or not residents.has(StringName(args[1])) or not residents.has(StringName(args[2])):
		return usage
	var a := StringName(args[1])
	var b := StringName(args[2])
	var m: Dictionary = relation_meta.get(RelationRules.pair_key(a, b), {})
	match args[0]:
		"wish":
			if m.is_empty() or not Enums.RelationFlag.MARRIED in m["flags"]:
				return "결혼한 두 사람이 아님"
			m["wish_day"] = GameState.day
			child_wish.emit(a, b, child_methods(a, b))
			return "아이를 맞고 싶다는 대화를 띄움 (방식 %s)" % [child_methods(a, b)]
		"now", "later":
			var method := Enums.ArrivalMethod.BIRTH if args.size() > 3 and args[3] == "birth" else Enums.ArrivalMethod.ADOPTION
			var res := answer_child_wish(a, b, StringName(args[0]), method)
			return "%s" % res if res["ok"] else "실패: " + String(res["reason"])
	return usage


func _cmd_arrival(args: PackedStringArray) -> String:
	var usage := "사용법: arrival | arrival <id> nick <별명> | preset <id> | bed <bed_id|none> | done"
	if args.is_empty():
		var waiting := pending_arrivals()
		return "입주 의식 대기: %s · 빈 침상 %s" % [waiting if not waiting.is_empty() else "없음", free_beds()]
	var id := StringName(args[0])
	if not residents.has(id):
		return "없는 주민: %s" % id
	if args.size() < 2:
		return "%s" % arrival_info(id)
	var value := " ".join(args.slice(2)) if args.size() > 2 else ""
	match args[1]:
		"nick":
			var res := set_nickname(id, value)
			return "별명: %s" % residents[id]["nickname"] if res["ok"] else "실패: " + String(res["reason"])
		"preset":
			var res := set_appearance(id, {"preset": StringName(value)})
			return "외형: %s" % appearance_for_look(id) if res["ok"] else "실패: " + String(res["reason"])
		"bed":
			return "침상: %s" % residents[id]["bed_id"] if choose_bed(id, &"" if value == "none" else StringName(value)) else "그 침상은 쓸 수 없다"
		"done":
			var res := complete_arrival(id)
			return "첫 대화 — %s / 좋아하는 것: %s" % [res["background"], res["like"]] if res["ok"] else "입주 의식 대기 중이 아님"
	return usage


func _cmd_rel(args: PackedStringArray) -> String:
	var usage := "사용법: rel <id> | rel add <a> <b> <n> | rel night | rel wedding <a> <b>"
	if args.is_empty():
		return usage
	match args[0]:
		"add":
			if args.size() < 4 or not residents.has(StringName(args[1])) or not residents.has(StringName(args[2])):
				return usage
			var v := add_relation(StringName(args[1]), StringName(args[2]), int(args[3]), &"debug")
			return "%s↔%s %d (%s)" % [args[1], args[2], v, RelationRules.STAGE_NAMES[relation_stage(StringName(args[1]), StringName(args[2]))]]
		"night":
			if night_queue.is_empty():
				night_queue = roll_night_events()
			var lines := PackedStringArray()
			while not night_queue.is_empty():
				lines.append(String(_apply_night_event(night_queue.pop_front(), &"")["text"]))
			return "\n".join(lines) if not lines.is_empty() else "오늘 밤 일어날 이벤트가 없다"
		"wedding":
			if args.size() < 3:
				return usage
			var status := wedding_status(StringName(args[1]), StringName(args[2]))
			if not prepare_wedding(StringName(args[1]), StringName(args[2])):
				return "준비 못 함: %s" % ", ".join(status["missing"])
			return "결혼식 준비 완료 (가족 숙소 %s). 다음 밤 결혼식" % status["house_uid"]
	var id := StringName(args[0])
	if not residents.has(id):
		return "없는 주민: %s" % id
	var lines := PackedStringArray(["%s %s의 관계" % [id, residents[id]["name"]]])
	var rels := relations_of(id)
	for other: StringName in rels:
		lines.append("  %s %s %d %s" % [other, residents[other]["name"], rels[other]["value"], RelationRules.STAGE_NAMES[rels[other]["stage"]]])
	return "\n".join(lines)


func _cmd_trust(args: PackedStringArray) -> String:
	var usage := "사용법: trust <id> | trust talk|deep|add <id> [n] | trust gift <id> <resource_id>"
	if args.is_empty():
		return usage
	var sub := args[0]
	var id := StringName(args[1]) if args.size() > 1 else &""
	if args.size() == 1:
		id = StringName(sub)
		sub = "show"
	if not residents.has(id):
		return "없는 주민: %s" % id
	var res := {}
	match sub:
		"show":
			return "%s 신뢰 %d · %s · 열린 사연 %s · 오늘 가능 %s" % [id, residents[id]["trust"],
				TrustRules.STAGE_NAMES[trust_stage(id)], unlocked_story(id), trust_actions(id)]
		"talk":
			res = talk(id)
		"deep":
			res = deep_talk(id)
		"add":
			return "%s 신뢰 %d" % [id, add_trust(id, int(args[2]) if args.size() > 2 else TrustRules.TALK, &"debug")]
		"gift":
			if args.size() < 3:
				return usage
			res = give_gift(id, StringName(args[2]))
		_:
			return usage
	if not res["ok"]:
		return "실패: " + String(res["reason"])
	var extra: String = (" (%s)" % res["reaction"]) if res.has("reaction") else ""
	return "%s 신뢰 %d%s" % [id, res["trust"], extra]


func _cmd_zone(args: PackedStringArray) -> String:
	if args.size() >= 2 and args[0] == "clear":
		clear_zone(StringName(args[1]))
		return "개간 완료로 표시: %s" % args[1]
	var lines := PackedStringArray()
	for zone_id: StringName in BaseDB.zones():
		var z := BaseDB.get_zone(zone_id)
		var state := "개간됨" if is_zone_cleared(zone_id) else "%d/%d" % [clear_progress_of(zone_id), z.clear_work]
		var can := can_clear(zone_id)
		lines.append("  %s %s: %s%s" % [zone_id, z.display_name, state,
			"" if can["ok"] or is_zone_cleared(zone_id) else " (" + ", ".join(PackedStringArray(can["reasons"])) + ")"])
	return "\n".join(lines)


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
				lines.append("  %s %s (%s) 특성 %s 능력치 %s · 사기 %d 신뢰 %d 배고픔 %d 피로 %d %s%s" % [id, r["name"],
					"여성" if r["gender"] == ResidentData.GENDER_FEMALE else "남성",
					r["traits"], r["stats"], r["morale"], r["trust"], r["hunger"], r["fatigue"],
					Enums.HealthState.keys()[r["health"]], " · 떠나려 함" if r["leave_crisis"] else ""])
			return "\n".join(lines)
		"persuade":
			if args.size() < 2:
				return "사용법: resident persuade <id>"
			var res := persuade_to_stay(StringName(args[1]))
			return "붙잡았다" if res["ok"] else "실패: " + res["reason"]
		"set":
			# resident set <id> <morale|trust|hunger|fatigue> <n>
			if args.size() < 4 or not residents.has(StringName(args[1])) or not args[2] in ["morale", "trust", "hunger", "fatigue"]:
				return "사용법: resident set <id> <morale|trust|hunger|fatigue> <0~100>"
			residents[StringName(args[1])][args[2]] = clampi(int(args[3]), 0, 100)
			return "%s %s = %s" % [args[1], args[2], args[3]]
	return "사용법: resident add [demo 1~3] | resident list | resident persuade <id> | resident set <id> <morale|trust|hunger|fatigue> <n>"
