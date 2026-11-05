extends RefCounted
## ResidentPool (A-16): hand-written survivor data, validation, banned words, reviewed filter,
## draw / mark_used, save round trip, and handing a profile to Colony.add_resident().
## Restores ResidentPool and Colony afterwards and never writes a save file.

const CheckPool := preload("res://tools/check_resident_pool.gd")

var _saved_pool: Dictionary
var _saved_colony: String
var _saved_autosave: bool


func run() -> bool:
	_saved_pool = ResidentPool.save_data().duplicate(true)
	_saved_colony = JSON.stringify(JSON.from_native(Colony.save_data()))
	_saved_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	ResidentPool.load_data({})

	var ok := true
	ok = _check_data() and ok
	ok = _check_tool() and ok
	ok = _check_rejects() and ok
	ok = _check_reviewed_filter() and ok
	ok = _check_draw() and ok
	ok = _check_save() and ok
	ok = _check_colony() and ok

	ResidentPool.reload()
	ResidentPool.load_data(_saved_pool)
	Colony.load_data(JSON.to_native(JSON.parse_string(_saved_colony)))
	SaveSystem.autosave_enabled = _saved_autosave
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_resident_pool: " + message)
	return cond


## A valid entry that the tests then break in one place.
func _fake(id: StringName = &"test_fake", reviewed := true) -> ResidentTemplate:
	var t := ResidentTemplate.new()
	t.id = id
	t.name = "시험용"
	t.age_stage = Enums.AgeStage.ADULT
	t.former_job = &"electrician"
	t.traits = [&"diligent", &"brave"]
	t.likes = [&"tea", &"books"]
	t.dislikes = [&"cold", &"dust"]
	t.access_needs = [Enums.AccessNeed.HEARING]
	t.stats = {&"dex": 6}
	t.background = "배전반을 고치던 전기 기사. 정전된 지하 주차장에서 손전등 하나로 버텼다."
	t.fragments = ["전선 색만 보고도 어디로 이어지는지 안다.", "작업복 주머니에 늘 절연 테이프가 있다."]
	t.contribution = "발전기 배선을 맡는다."
	t.first_line = "불 좀 켜 볼까요."
	t.rescue_lines = ["저 배선, 살아 있어요.", "천천히요.", "여기 계단 조심해요."]
	t.reviewed = reviewed
	return t


func _check_data() -> bool:
	var banned := ResidentTemplate.load_banned_words()
	var ok := _expect(banned.size() >= 30, "banned word list has only %d entries" % banned.size())
	ok = _expect(ResidentPool.reviewed_ids().size() >= 3, "fewer than 3 reviewed survivors") and ok
	for id in [&"demo_carpenter", &"demo_mechanic", &"demo_child"]:
		var t: ResidentTemplate = ResidentPool.templates.get(id)
		ok = _expect(t != null and t.demo and t.reviewed, "demo survivor %s missing or not reviewed" % id) and ok
	# The three demo survivors of docs/design/13 "데모 구조자".
	var carpenter := ResidentPool.get_profile(&"demo_carpenter")
	ok = _expect(carpenter.get("age_stage") == Enums.AgeStage.ELDER and carpenter.get("former_job") == &"carpenter"
		and Enums.AccessNeed.MOBILITY in carpenter.get("access_needs", []), "demo_carpenter: elder carpenter, mobility") and ok
	var mechanic := ResidentPool.get_profile(&"demo_mechanic")
	ok = _expect(mechanic.get("former_job") == &"mechanic" and Enums.AccessNeed.MOBILITY in mechanic.get("access_needs", []),
		"demo_mechanic: mechanic, mobility") and ok
	var child := ResidentPool.get_profile(&"demo_child")
	ok = _expect(child.get("age_stage") == Enums.AgeStage.CHILD and &"monster_mark" in child.get("traits", [])
		and Enums.AccessNeed.LANGUAGE in child.get("access_needs", []), "demo_child: child, monster mark, language") and ok
	for id in ResidentPool.reviewed_ids():
		var errors: PackedStringArray = ResidentPool.templates[id].validate(banned)
		ok = _expect(errors.is_empty(), "%s invalid: %s" % [id, errors]) and ok
	return ok


func _check_tool() -> bool:
	var report: Dictionary = CheckPool.check_dir(ResidentPool.POOL_DIR, ResidentTemplate.load_banned_words())
	var ok := _expect(report["failed"] == 0, "check_resident_pool errors: %s" % report["errors"])
	ok = _expect(report["count"] == ResidentPool.templates.size() + ResidentPool.unreviewed.size(),
		"tool sees %d entries, pool %d" % [report["count"], ResidentPool.templates.size() + ResidentPool.unreviewed.size()]) and ok
	return _expect(report["reviewed"] == ResidentPool.templates.size(), "reviewed counts differ") and ok


func _check_rejects() -> bool:
	var banned := ResidentTemplate.load_banned_words()
	var ok := _expect(_fake().validate(banned).is_empty(), "fake entry should be valid: %s" % _fake().validate(banned))

	var pity := _fake(&"test_pity")
	pity.background = "다리를 다친 불쌍한 노인."
	ok = _expect(not pity.find_banned_words(banned).is_empty(), "pity wording not caught") and ok
	ok = _expect(not ResidentPool.add_template(pity, banned).is_empty() and not ResidentPool.templates.has(&"test_pity"),
		"pool accepted a banned word") and ok

	var hero := _fake(&"test_hero")
	hero.rescue_lines = ["장애를 극복한 사람이에요.", "가요.", "쉬어요."]
	ok = _expect(not hero.find_banned_words(banned).is_empty(), "heroizing wording not caught") and ok

	var mark := _fake(&"test_mark")
	mark.fragments = ["흔적이 있으면 마물이 될지도 모른다.", "조용하다."]
	ok = _expect(not mark.find_banned_words(banned).is_empty(), "monster-mark danger hint not caught") and ok
	# Spaces matter: "딱 한 번" is not "딱한".
	var plain := _fake(&"test_plain")
	plain.first_line = "딱 한 번만 쉬어요."
	ok = _expect(plain.find_banned_words(banned).is_empty(), "false positive on '딱 한 번'") and ok

	var cases := {
		"bad trait": func(t: ResidentTemplate): t.traits = [&"diligent", &"no_such_trait"],
		"exclusive traits": func(t: ResidentTemplate): t.traits = [&"brave", &"timid"],
		"one trait": func(t: ResidentTemplate): t.traits = [&"brave"],
		"bad job": func(t: ResidentTemplate): t.former_job = &"astronaut",
		"baby": func(t: ResidentTemplate): t.age_stage = Enums.AgeStage.BABY,
		"stat range": func(t: ResidentTemplate): t.stats = {&"str": 11},
		"stat key": func(t: ResidentTemplate): t.stats = {&"luck": 3},
		"access need": func(t: ResidentTemplate): t.access_needs = [99],
		"long line": func(t: ResidentTemplate): t.first_line = "가".repeat(41),
		"no background": func(t: ResidentTemplate): t.background = "",
		"fragments": func(t: ResidentTemplate): t.fragments = ["하나뿐"],
		"bad id": func(t: ResidentTemplate): t.id = &"Bad Id",
		"like twice": func(t: ResidentTemplate): t.dislikes = [&"tea", &"dust"],
	}
	for label: String in cases:
		var t := _fake(StringName("test_case"))
		cases[label].call(t)
		ok = _expect(not t.validate(banned).is_empty(), "validate() missed: %s" % label) and ok

	ok = _expect(not ResidentPool.add_template(_fake(&"demo_carpenter"), banned).is_empty(), "duplicate id accepted") and ok
	return ok


func _check_reviewed_filter() -> bool:
	var draft := _fake(&"test_draft", false)
	var errors := ResidentPool.add_template(draft)
	var ok := _expect(errors == PackedStringArray(["not reviewed"]), "unreviewed entry: %s" % errors)
	ok = _expect(ResidentPool.get_profile(&"test_draft").is_empty(), "unreviewed entry returned by get_profile") and ok
	ok = _expect(&"test_draft" not in ResidentPool.available_ids(), "unreviewed entry is drawable") and ok
	for i in 50:
		ok = _expect(ResidentPool.draw().get("id") != &"test_draft", "draw returned an unreviewed entry") and ok
	for id: StringName in ResidentPool.unreviewed:
		ok = _expect(ResidentPool.get_profile(id).is_empty(), "unreviewed %s visible" % id) and ok
	ResidentPool.unreviewed.erase(&"test_draft")
	return ok


func _check_draw() -> bool:
	ResidentPool.load_data({})
	var demos := ResidentPool.available_ids({"demo": true})
	var ok := _expect(demos.size() == 3, "demo filter gave %s" % [demos])
	var seen := {}
	for i in 3:
		var p := ResidentPool.draw({"demo": true})
		ok = _expect(not p.is_empty() and not seen.has(p["id"]), "draw %d gave %s" % [i, p.get("id")]) and ok
		seen[p.get("id")] = true
		ResidentPool.mark_used(p.get("id", &""))
	ok = _expect(ResidentPool.draw({"demo": true}).is_empty(), "draw after all demo used should be {}") and ok
	ok = _expect(not ResidentPool.get_profile(&"demo_child").is_empty(), "get_profile ignores used") and ok
	ok = _expect(ResidentPool.is_used(&"demo_child"), "demo_child marked used") and ok

	ResidentPool.load_data({})
	var language := ResidentPool.available_ids({"access_need": Enums.AccessNeed.LANGUAGE})
	ok = _expect(&"demo_child" in language and &"demo_carpenter" not in language, "access_need filter: %s" % [language]) and ok
	var elders := ResidentPool.available_ids({"age_stage": Enums.AgeStage.ELDER, "exclude": [&"demo_carpenter"]})
	ok = _expect(&"demo_carpenter" not in elders, "exclude filter") and ok
	for id in elders:
		ok = _expect(ResidentPool.templates[id].age_stage == Enums.AgeStage.ELDER, "age filter gave %s" % id) and ok
	# Profiles are copies: editing one must not change the pool.
	var p := ResidentPool.get_profile(&"demo_mechanic")
	p["traits"].append(&"loner")
	p["story"]["fragments"].clear()
	var again := ResidentPool.get_profile(&"demo_mechanic")
	ok = _expect(again["traits"].size() == 2 and again["story"]["fragments"].size() == 2, "profile is not a copy") and ok
	ResidentPool.mark_used(&"not_in_pool")
	ok = _expect(not ResidentPool.is_used(&"not_in_pool"), "unknown id marked used") and ok
	if OS.is_debug_build():
		var listing := DebugConsole.execute("pool list")
		ok = _expect(listing.contains("demo_child") and listing.contains("검수 대기"), "debug 'pool list': %s" % listing) and ok
	return ok


func _check_save() -> bool:
	ResidentPool.load_data({})
	ResidentPool.mark_used(&"demo_mechanic")
	var data: Dictionary = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(ResidentPool.save_data()))))
	ResidentPool.load_data({})
	var ok := _expect(not ResidentPool.is_used(&"demo_mechanic"), "load_data({}) resets")
	ResidentPool.load_data(data)
	ok = _expect(ResidentPool.is_used(&"demo_mechanic") and not ResidentPool.is_used(&"demo_child"), "used survives JSON round trip") and ok
	ResidentPool.load_data({})
	return ok


func _check_colony() -> bool:
	ResidentPool.load_data({})
	var before := Colony.population()
	var profile := ResidentPool.get_profile(&"demo_child")
	var id := Colony.add_resident(profile)
	var r := Colony.get_resident(id)
	var ok := _expect(id == &"demo_child", "resident id %s (expected the pool id)" % id)
	ok = _expect(Colony.population() == before + 1, "population did not grow") and ok
	ok = _expect(r.get("name") == profile["name"] and r.get("age_stage") == Enums.AgeStage.CHILD, "name / age copied") and ok
	ok = _expect(r.get("traits") == [&"monster_mark", &"timid"], "traits copied: %s" % [r.get("traits")]) and ok
	ok = _expect(r.get("access_needs") == [Enums.AccessNeed.LANGUAGE], "access_needs copied") and ok
	ok = _expect(r.get("story", {}).get("background") == profile["story"]["background"]
		and r["story"]["fragments"].size() == 2, "story copied") and ok
	ok = _expect(r.get("likes") == [&"drawing", &"sweet_food"], "likes copied") and ok
	for key in ResidentData.STAT_KEYS:
		var v: int = r["stats"][key]
		ok = _expect(v >= ResidentData.STAT_MIN and v <= ResidentData.STAT_MAX, "stat %s rolled out of range" % key) and ok
	ok = _expect(ResidentPool.is_used(&"demo_child"), "resident_joined did not mark the entry used") and ok
	ok = _expect(&"demo_child" not in ResidentPool.available_ids(), "joined survivor still drawable") and ok
	# Stats given in the template win over the roll.
	var carpenter_id := Colony.add_resident(ResidentPool.get_profile(&"demo_carpenter"))
	ok = _expect(Colony.get_resident(carpenter_id)["stats"][&"dex"] == 7, "template stats kept") and ok
	return ok
