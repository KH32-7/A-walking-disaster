extends Node
## Autoload `Colony`. Owner: Lane C.
## Residents, buildings, relationships, raids threat - everything that lives in the base.
## Other lanes read through the getters below; they never edit resident data directly.
## Design reference: docs/design/07-residents.md .. 10-raids-defense.md

const SAVE_VERSION := 1
## 본관 1층 침상 6자리 (docs/design/09-base-building.md "구역과 개간"). Buildings add more (C-04).
const START_BED_COUNT := 6
const START_BED_PREFIX := "main_hall_bed_"

## resident_id -> Dictionary (fields: base/residents/resident_data.gd, docs/design/07-residents.md)
var residents: Dictionary = {}
## bed_id -> resident_id (&"" = free). Ordered: beds are handed out in insertion order.
var beds: Dictionary = {}
var threat: int = 0
var tier: Enums.BaseTier = Enums.BaseTier.CAMP

var _next_resident_num := 1
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


## Base noise level that feeds the raid threat (docs/design/09-base-building.md).
func base_noise() -> float:
	# TODO(C-04)
	return 0.0


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
	threat = 0
	tier = Enums.BaseTier.CAMP
	_next_resident_num = 1
	_rng.randomize()


# --- Save provider -------------------------------------------------------------

func save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"residents": residents,
		"beds": beds,
		"next_resident_num": _next_resident_num,
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
	threat = int(data.get("threat", 0))
	tier = int(data.get("tier", Enums.BaseTier.CAMP)) as Enums.BaseTier


# --- Debug console (debug builds only) -----------------------------------------

func _register_debug_commands() -> void:
	DebugConsole.register(&"resident", _cmd_resident,
		"resident add [demo 1~3] | resident list - 주민 추가(무작위 또는 데모 구조자)·목록")


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
