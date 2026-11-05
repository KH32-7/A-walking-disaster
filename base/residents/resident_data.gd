class_name ResidentData
## Builds and normalizes resident dictionaries (docs/design/07-residents.md "데이터 정의").
## Colony stores residents as plain Dictionaries so they are JSON-safe for SaveSystem.
## Only Colony should call create(); other lanes read residents through Colony.get_resident().
##
## Key convention: field names (top level, story, assignment) are String keys; maps keyed by ids
## (stats, job_skill, job_days, stat_days, class_aptitude, relations) use StringName keys.
##
## Resident fields:
##   id, name, nickname: StringName/String
##   age_stage: Enums.AgeStage, age_days: int
##   appearance: Dictionary (preset ids, colors; filled by the 입주 의식 C-13 / Lane D)
##   former_job: StringName (keys of FORMER_JOB_MAIN_STAT)
##   traits, likes, dislikes: Array[StringName]
##   access_needs: Array[int] (Enums.AccessNeed)
##   stats: {str, dex, sense, heart: 1..10}
##   job_skill: {job_id: 0..5}, job_days: {job_id: days worked}, stat_days: {stat: work days} (C-05)
##   class_aptitude: {gun, blade, blunt: Enums.Aptitude}
##   hunger, fatigue, morale, trust: int 0..100
##   low_morale_days: int (days in a row under 20), leave_crisis: bool (떠나려 한다, C-06)
##   health: Enums.HealthState, recover_days: int
##   relations: {resident_id: -100..100} (C-14)
##   assignment: {job: StringName, building_id: StringName}
##   bed_id: StringName (&"" = 임시 거처)
##   story: {background: String, fragments: Array[String], requests: Array}
##   status: Enums.ResidentStatus, joined_day: int
## Equipment is not stored here: Armory owns it (Armory.get_equipped(resident_id, slot)).

const STAT_KEYS: Array[StringName] = [&"str", &"dex", &"sense", &"heart"]
const CLASS_KEYS: Array[StringName] = [&"gun", &"blade", &"blunt"]
const STAT_MIN := 1
const STAT_MAX := 10
## Initial stats (07 "능력치"): main stat of the former job 5..7, the others 2..5.
const MAIN_STAT_RANGE := Vector2i(5, 7)
const OTHER_STAT_RANGE := Vector2i(2, 5)
## Chance of HIGH / LOW aptitude per class when a profile does not set it (가안).
const APTITUDE_HIGH_CHANCE := 0.25
const APTITUDE_LOW_CHANCE := 0.25
const TRAIT_COUNT := 2

## Starting needs when a resident joins (가안).
const START_HUNGER := 70
const START_FATIGUE := 20
const START_MORALE := 50
const START_TRUST := 0

## Former job -> main stat (07 "주민 데이터" 전직). &"" = random main stat.
const FORMER_JOB_MAIN_STAT := {
	&"carpenter": &"dex",
	&"nurse": &"heart",
	&"doctor": &"heart",
	&"mechanic": &"dex",
	&"electrician": &"dex",
	&"cook": &"heart",
	&"farmer": &"heart",
	&"teacher": &"heart",
	&"interpreter": &"heart",
	&"radio_pd": &"heart",
	&"police": &"sense",
	&"athlete": &"str",
	&"painter": &"dex",
	&"laborer": &"str",
	&"student": &"",
}


## Returns a complete resident dictionary. Fields present in `profile` win; missing ones are
## rolled with `rng` (stats, aptitude, traits) or take defaults.
static func create(profile: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var former_job := StringName(profile.get("former_job", &"laborer"))
	var r := {
		"id": StringName(profile.get("id", &"")),
		"name": str(profile.get("name", "이름 없는 생존자")),
		"nickname": str(profile.get("nickname", "")),
		"age_stage": Enums.AgeStage.ADULT,
		"age_days": 0,
		"appearance": {},
		"former_job": former_job,
		"traits": roll_traits(rng),
		"likes": [],
		"dislikes": [],
		"access_needs": [],
		"stats": roll_stats(former_job, rng),
		"job_skill": {},
		"job_days": {},
		"stat_days": {},
		"low_morale_days": 0,
		"leave_crisis": false,
		"class_aptitude": roll_aptitude(rng),
		"hunger": START_HUNGER,
		"fatigue": START_FATIGUE,
		"morale": START_MORALE,
		"trust": START_TRUST,
		"health": Enums.HealthState.OK,
		"recover_days": 0,
		"relations": {},
		"assignment": {"job": &"", "building_id": &""},
		"bed_id": &"",
		"story": {"background": "", "fragments": [], "requests": []},
		"status": Enums.ResidentStatus.ACTIVE,
		"joined_day": 0,
	}
	for key in profile:
		var k := str(key)
		if not r.has(k):
			continue
		if r[k] is Dictionary and profile[key] is Dictionary and k in ["stats", "class_aptitude", "story", "assignment"]:
			# Partial override, keep rolled values for the rest. String and StringName keys are
			# different Dictionary keys, so convert first.
			# stats/class_aptitude are id maps (StringName keys); story/assignment are records
			# (String keys, like the top level).
			var sub: Dictionary = r[k]
			var over: Dictionary = profile[key]
			sub.merge(_sn_keys(over) if k in ["stats", "class_aptitude"] else _str_keys(over), true)
		else:
			r[k] = profile[key]
	return normalize(r)


## Fixes types after JSON (keys -> StringName, numbers -> int) and clamps ranges.
## Safe to call on any resident dictionary; used by create() and Colony.load_data().
static func normalize(src: Dictionary) -> Dictionary:
	var r := src.duplicate(true)
	r["id"] = StringName(r.get("id", &""))
	r["name"] = str(r.get("name", ""))
	r["nickname"] = str(r.get("nickname", ""))
	r["age_stage"] = int(r.get("age_stage", Enums.AgeStage.ADULT))
	r["age_days"] = int(r.get("age_days", 0))
	r["appearance"] = r.get("appearance", {}) if r.get("appearance") is Dictionary else {}
	r["former_job"] = StringName(r.get("former_job", &""))
	r["traits"] = _names(r.get("traits", []))
	r["likes"] = _names(r.get("likes", []))
	r["dislikes"] = _names(r.get("dislikes", []))
	var needs: Array = []
	for n in r.get("access_needs", []):
		needs.append(int(n))
	r["access_needs"] = needs
	var stats := {}
	for key in STAT_KEYS:
		stats[key] = clampi(int(_read(r.get("stats", {}), key, STAT_MIN)), STAT_MIN, STAT_MAX)
	r["stats"] = stats
	r["job_skill"] = _int_map(r.get("job_skill", {}), 0, 5)
	r["job_days"] = _int_map(r.get("job_days", {}), 0, 1 << 30)
	r["stat_days"] = _int_map(r.get("stat_days", {}), 0, 1 << 30)
	r["low_morale_days"] = maxi(int(r.get("low_morale_days", 0)), 0)
	r["leave_crisis"] = bool(r.get("leave_crisis", false))
	var apt := {}
	for key in CLASS_KEYS:
		apt[key] = clampi(int(_read(r.get("class_aptitude", {}), key, Enums.Aptitude.MID)), 0, Enums.Aptitude.size() - 1)
	r["class_aptitude"] = apt
	for key in ["hunger", "fatigue", "morale", "trust"]:
		r[key] = clampi(int(r.get(key, 0)), 0, 100)
	r["health"] = int(r.get("health", Enums.HealthState.OK))
	r["recover_days"] = maxi(int(r.get("recover_days", 0)), 0)
	r["relations"] = _int_map(r.get("relations", {}), -100, 100)
	var assignment: Dictionary = r.get("assignment", {})
	r["assignment"] = {
		"job": StringName(assignment.get("job", &"")),
		"building_id": StringName(assignment.get("building_id", &"")),
	}
	r["bed_id"] = StringName(r.get("bed_id", &""))
	var story: Dictionary = r.get("story", {})
	r["story"] = {
		"background": str(story.get("background", "")),
		"fragments": Array(story.get("fragments", [])).map(func(f): return str(f)),
		"requests": Array(story.get("requests", [])),
	}
	r["status"] = int(r.get("status", Enums.ResidentStatus.ACTIVE))
	r["joined_day"] = int(r.get("joined_day", 0))
	return r


static func roll_stats(former_job: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var main: StringName = FORMER_JOB_MAIN_STAT.get(former_job, &"")
	if main == &"":
		main = STAT_KEYS[rng.randi_range(0, STAT_KEYS.size() - 1)]
	var stats := {}
	for key in STAT_KEYS:
		var range_ := MAIN_STAT_RANGE if key == main else OTHER_STAT_RANGE
		stats[key] = rng.randi_range(range_.x, range_.y)
	return stats


static func roll_aptitude(rng: RandomNumberGenerator) -> Dictionary:
	var apt := {}
	for key in CLASS_KEYS:
		var roll := rng.randf()
		if roll < APTITUDE_HIGH_CHANCE:
			apt[key] = Enums.Aptitude.HIGH
		elif roll < APTITUDE_HIGH_CHANCE + APTITUDE_LOW_CHANCE:
			apt[key] = Enums.Aptitude.LOW
		else:
			apt[key] = Enums.Aptitude.MID
	return apt


## TRAIT_COUNT random traits from data/traits, never two exclusive ones.
static func roll_traits(rng: RandomNumberGenerator) -> Array[StringName]:
	var pool: Array[StringName] = []
	for id: StringName in BaseDB.traits():
		if BaseDB.get_trait(id).randomizable:
			pool.append(id)
	pool.sort()  # deterministic order for a seeded rng
	var picked: Array[StringName] = []
	while picked.size() < TRAIT_COUNT and not pool.is_empty():
		var id: StringName = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var ok := true
		for other in picked:
			if traits_conflict(id, other):
				ok = false
				break
		if ok:
			picked.append(id)
	return picked


static func traits_conflict(a: StringName, b: StringName) -> bool:
	var da := BaseDB.get_trait(a)
	var db := BaseDB.get_trait(b)
	return (da != null and b in da.exclusive_with) or (db != null and a in db.exclusive_with)


static func _names(values: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if values is Array:
		for v in values:
			out.append(StringName(v))
	return out


static func _sn_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[StringName(k) if (k is String or k is StringName) else k] = d[k]
	return out


static func _str_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


static func _int_map(values: Variant, lo: int, hi: int) -> Dictionary:
	var out := {}
	if values is Dictionary:
		for k in values:
			out[StringName(k)] = clampi(int(values[k]), lo, hi)
	return out


## Dictionary read that works whether keys are StringName (fresh) or String (after JSON).
static func _read(d: Variant, key: StringName, default: Variant) -> Variant:
	if not d is Dictionary:
		return default
	if d.has(key):
		return d[key]
	return d.get(String(key), default)
