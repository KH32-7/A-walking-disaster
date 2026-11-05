extends RefCounted
## Journal (A-17): template data + review rules, particles and placeholders, one entry per signal,
## rescue vs. join, the daily cap, day / resident queries, the epilogue and the save round trip.
## No LLM anywhere. Colony, GameState, Progression, FieldState and the router's sortie lists are
## restored afterwards; autosave is off so nothing touches the real save slots.

## Words the review rules (15 "검수 규칙") keep out of every line: pity, heroizing, belittling,
## graphic violence.
const BANNED := ["불쌍", "가엾", "가여", "딱한", "극복", "장애를", "장애인", "병신", "늙은이", "노인네",
	"벙어리", "귀머거리", "절름발이", "앉은뱅이", "외국인 노동자", "피투성이", "처참", "끔찍", "참혹", "시체",
	"내장", "잔인"]

var _heard: Array = []
var _saved: Dictionary = {}
var _saved_autosave: bool
var _saved_router_rescued: Array
var _saved_router_stranded: Array


func run() -> bool:
	_saved = {
		"journal": Journal.save_data(), "colony": Colony.save_data().duplicate(true),
		"game": GameState.save_data(), "progression": Progression.save_data(), "field": FieldState.save_data(),
	}
	_saved_router_rescued = SceneRouter._rescued.duplicate(true)
	_saved_router_stranded = SceneRouter._stranded.duplicate(true)
	_saved_autosave = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	var on_entry := func(day: int, text: String): _heard.append({"day": day, "text": text})
	EventBus.journal_entry_added.connect(on_entry)

	var ok := _check_data()
	ok = _check_fill() and ok
	ok = await _check_arrivals() and ok
	ok = _check_signals() and ok
	ok = _check_cap() and ok
	ok = _check_quiet_day() and ok
	ok = _check_queries() and ok
	ok = await _check_epilogue() and ok
	ok = _check_save_round_trip() and ok

	EventBus.journal_entry_added.disconnect(on_entry)
	SaveSystem.autosave_enabled = _saved_autosave
	SceneRouter._rescued = _saved_router_rescued
	SceneRouter._stranded = _saved_router_stranded
	Colony.load_data(_saved["colony"])
	GameState.load_data(_saved["game"])
	Progression.load_data(_saved["progression"])
	FieldState.load_data(_saved["field"])
	Journal.load_data(_saved["journal"])
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _reset(day := 5) -> void:
	Colony.load_data({})
	Journal.load_data({})
	GameState.day = day
	_heard.clear()


func _texts() -> Array:
	return _heard.map(func(h): return h["text"])


func _kinds(day: int) -> Array:
	return Journal.entries_for_day(day).map(func(e): return e["kind"])


func _check_data() -> bool:
	var ok := _expect(Journal.templates.size() >= 30, "only %d journal templates" % Journal.templates.size())
	for kind in [&"rescued", &"joined", &"returned", &"left", &"died", &"stranded", &"wedding", &"lover",
			&"friend", &"separated", &"prejudice_resolved", &"request_completed", &"raid_flawless", &"raid_win",
			&"raid_narrow", &"raid_loss", &"building_completed", &"sortie_extracted", &"sortie_downed",
			&"night_campfire", &"quiet_day", &"epilogue_stay", &"epilogue_leave", &"epilogue_active",
			&"epilogue_dead", &"epilogue_left", &"epilogue_missing", &"epilogue_quiet"]:
		ok = _expect(Journal.templates.has(kind), "missing journal template %s" % kind) and ok
	for kind in Journal.HIGHLIGHTS:
		ok = _expect(Journal.templates.has(Journal.HIGHLIGHTS[kind]), "missing %s" % Journal.HIGHLIGHTS[kind]) and ok
	var placeholder := RegEx.create_from_string("\\{(\\w+)(?:\\|([^}]+))?\\}")
	# "{region}은" would print "침수 상가은"; particles that change with the word go inside the braces.
	var raw_particle := RegEx.create_from_string("\\}(이랑|랑|으로|로|이|가|을|를|은|는|과|와|아|야)(\\s|[.,!?]|$)")
	for id: StringName in Journal.templates:
		var template: JournalTemplate = Journal.templates[id]
		var minimum := 2 if String(id).begins_with("epilogue_") else 3
		ok = _expect(template.lines.size() >= minimum, "%s has %d lines" % [id, template.lines.size()]) and ok
		for line in template.lines:
			for word in BANNED:
				ok = _expect(not line.contains(word), "%s line uses banned word '%s': %s" % [id, word, line]) and ok
			ok = _expect(not line.contains("일차. "), "%s line has its own day prefix: %s" % [id, line]) and ok
			ok = _expect(raw_particle.search(line) == null, "%s particle outside the braces: %s" % [id, line]) and ok
			for m in placeholder.search_all(line):
				var josa := m.get_string(2)
				ok = _expect(josa == "" or Journal.PARTICLES.has(josa), "%s unknown particle |%s" % [id, josa]) and ok
	return ok


func _check_fill() -> bool:
	var ok := _expect(Journal.particle("지은", "이") == "이" and Journal.particle("민수", "이") == "가",
		"이/가 %s %s" % [Journal.particle("지은", "이"), Journal.particle("민수", "이")])
	ok = _expect(Journal.particle("지은", "를") == "을" and Journal.particle("민수", "을") == "를", "을/를") and ok
	ok = _expect(Journal.particle("지은", "와") == "과" and Journal.particle("민수", "과") == "와", "과/와") and ok
	ok = _expect(Journal.particle("서울", "으로") == "로" and Journal.particle("학교", "으로") == "로"
		and Journal.particle("지은", "로") == "으로", "(으)로") and ok
	ok = _expect(Journal.particle("3", "이") == "이" and Journal.particle("2", "이") == "가", "digits") and ok
	var line := Journal.fill("{name|이} {other|과} {region}에서 {day}일 {missing}.", {"name": "지은", "day": 12})
	ok = _expect(line == "지은이 누군가와 바깥에서 12일 .", "fill: %s" % line) and ok

	_reset(12)
	var added := Journal.record(&"request_completed", {"resident_id": &"nobody", "name": "지은"})
	var text: String = _heard[0]["text"] if not _heard.is_empty() else ""
	ok = _expect(added and _heard.size() == 1 and _heard[0]["day"] == 12, "record did not emit once") and ok
	ok = _expect(text.begins_with("12일차. ") and text.contains("지은") and not text.contains("{"),
		"placeholder not filled: %s" % text) and ok
	ok = _expect(not Journal.record(&"no_such_kind"), "unknown kind recorded") and ok
	return ok


## rescue_completed and resident_joined arrive in the same frame (Colony turns the rescue into a
## resident first); the journal writes one "rescued" entry, not two.
func _check_arrivals() -> bool:
	_reset(3)
	EventBus.rescue_completed.emit({"name": "지은", "former_job": &"teacher"})
	await Engine.get_main_loop().process_frame
	var ids := Colony.active_resident_ids()
	var ok := _expect(ids.size() == 1, "rescue did not add a resident: %s" % [ids])
	ok = _expect(_kinds(3) == [&"rescued"], "rescue entries %s" % [_kinds(3)]) and ok
	ok = _expect(_texts().size() == 1 and _texts()[0].contains("지은"), "rescue text %s" % [_texts()]) and ok

	var walk_in := Colony.add_resident({"name": "민수"})
	await Engine.get_main_loop().process_frame
	ok = _expect(_kinds(3) == [&"rescued", &"joined"], "join entries %s" % [_kinds(3)]) and ok

	# Stranded in the field, then brought home: "returned".
	GameState.day = 4
	EventBus.companion_stranded.emit(walk_in, &"flooded_mall")
	ok = _expect(_kinds(4) == [&"stranded"], "stranded %s" % [_kinds(4)]) and ok
	ok = _expect(Journal.entries_for_day(4)[0]["text"].contains("침수 상가"), "region name") and ok
	GameState.day = 5
	EventBus.resident_joined.emit(walk_in)
	await Engine.get_main_loop().process_frame
	ok = _expect(_kinds(5) == [&"returned"], "returned %s" % [_kinds(5)]) and ok
	return ok


func _check_signals() -> bool:
	_reset(7)
	var a := Colony.add_resident({"name": "지은"})
	var b := Colony.add_resident({"name": "민수"})
	Journal._flush_arrivals()
	_heard.clear()
	var ok := true
	var cases := [
		[func(): EventBus.relationship_changed.emit(a, b, &"friend"), &"friend"],
		[func(): EventBus.relationship_changed.emit(a, b, &"lover"), &"lover"],
		[func(): EventBus.relationship_changed.emit(a, b, &"spouse"), &"wedding"],
		[func(): EventBus.relationship_changed.emit(a, b, &"separated"), &"separated"],
		[func(): EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.FLAWLESS}), &"raid_flawless"],
		[func(): EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.WIN}), &"raid_win"],
		[func(): EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.NARROW}), &"raid_narrow"],
		[func(): EventBus.raid_resolved.emit({"outcome": Enums.RaidOutcome.LOSS}), &"raid_loss"],
		[func(): EventBus.sortie_ended.emit({"extracted": true, "region_id": &"flooded_mall", "rescued": []}), &"sortie_extracted"],
		[func(): EventBus.sortie_ended.emit({"extracted": false, "downed": true, "region_id": &"flooded_mall"}), &"sortie_downed"],
		[func(): EventBus.building_completed.emit(&"no_such_building"), &"building_completed"],
		[func(): EventBus.night_event_started.emit(&"campfire", [a, b]), &"night_campfire"],
		[func(): EventBus.resident_died.emit(a, &"raid"), &"died"],
		[func(): Colony._leave(b, &"low_morale"), &"left"],
	]
	for i in cases.size():
		GameState.day = 100 + i  # one day each so the daily cap never interferes
		_heard.clear()
		cases[i][0].call()
		var kinds := _kinds(GameState.day)
		ok = _expect(kinds == [cases[i][1]], "case %d: expected %s, got %s" % [i, cases[i][1], kinds]) and ok
		ok = _expect(_heard.size() == 1 and not _heard[0]["text"].contains("{"), "case %d text %s" % [i, _texts()]) and ok
	# Pair entries name both residents; the leaver's name survives Colony forgetting them.
	var wedding: Dictionary = Journal.entries_for_day(102)[0]
	ok = _expect(wedding["text"].contains("지은") and wedding["text"].contains("민수")
		and wedding["residents"] == [a, b], "wedding entry %s" % wedding) and ok
	var left: Dictionary = Journal.entries_for_day(113)[0]
	ok = _expect(Colony.get_resident(b).is_empty() and left["text"].contains("민수"), "left entry %s" % left) and ok
	ok = _expect(Journal.entries_for_day(110)[0]["text"].contains("새 시설"), "building fallback name") and ok
	# Ignored: unknown stages, night events without a template, a sortie that rescued someone.
	GameState.day = 200
	EventBus.relationship_changed.emit(a, b, &"acquaintance")
	EventBus.night_event_started.emit(&"no_template_event", [])
	EventBus.sortie_ended.emit({"extracted": true, "region_id": &"flooded_mall", "rescued": [&"x"]})
	ok = _expect(_kinds(200).is_empty(), "ignored events wrote %s" % [_kinds(200)]) and ok
	return ok


func _check_cap() -> bool:
	_reset(9)
	var max_per_day: int = Journal.MAX_ENTRIES_PER_DAY
	for i in max_per_day:
		Journal.record(&"building_completed", {"building": "벌목장"})
	var full := Journal.entries_for_day(9).size() == max_per_day
	var low := Journal.record(&"sortie_extracted")  # lower priority than building_completed: dropped
	var high := Journal.record(&"died", {"name": "지은"})  # replaces one building line
	var kinds := _kinds(9)
	var ok := _expect(full and not low and high, "cap %s %s %s" % [full, low, high])
	ok = _expect(kinds.size() == max_per_day and kinds.has(&"died") and not kinds.has(&"sortie_extracted"),
		"capped day %s" % [kinds]) and ok
	ok = _expect(_heard.size() == max_per_day + 1, "emitted %d" % _heard.size()) and ok
	return ok


func _check_quiet_day() -> bool:
	_reset(1)
	EventBus.day_started.emit(1)  # new game: nothing before day 1
	var first_day := Journal.days().is_empty()
	GameState.day = 2
	EventBus.day_started.emit(2)  # day 1 ended with no entries
	var quiet := _kinds(1) == [Journal.QUIET_DAY]
	GameState.day = 3
	EventBus.day_started.emit(3)  # day 2 was quiet too
	Journal.record(&"joined", {"name": "지은"})
	GameState.day = 4
	EventBus.day_started.emit(4)  # day 3 had an entry: no quiet line
	var busy := _kinds(3) == [&"joined"] and _kinds(2) == [Journal.QUIET_DAY]
	# A day loaded from a save (day_started for the same day) does not get a quiet line for yesterday.
	Journal.load_data({"last_day": 7})
	EventBus.day_started.emit(7)
	var loaded := Journal.entries_for_day(6).is_empty()
	return _expect(first_day and quiet and busy and loaded,
		"quiet day %s %s %s %s" % [first_day, quiet, busy, loaded])


func _check_queries() -> bool:
	_reset(10)
	Journal.record(&"rescued", {"resident_id": &"r_a", "name": "지은"})
	GameState.day = 11
	Journal.record(&"friend", {"resident_id": &"r_a", "other_id": &"r_b", "name": "지은", "other": "민수"})
	Journal.record(&"raid_win")
	GameState.day = 13
	Journal.record(&"request_completed", {"resident_id": &"r_b", "name": "민수"})
	var ok := _expect(Journal.days() == [10, 11, 13], "days %s" % [Journal.days()])
	ok = _expect(_kinds(11) == [&"friend", &"raid_win"], "day 11 %s" % [_kinds(11)]) and ok
	var for_a := Journal.entries_for_resident(&"r_a").map(func(e): return e["kind"])
	var for_b := Journal.entries_for_resident(&"r_b").map(func(e): return e["kind"])
	ok = _expect(for_a == [&"rescued", &"friend"], "resident a %s" % [for_a]) and ok
	ok = _expect(for_b == [&"friend", &"request_completed"], "resident b %s" % [for_b]) and ok
	ok = _expect(Journal.people() == [&"r_a", &"r_b"], "people %s" % [Journal.people()]) and ok
	ok = _expect(Journal.resident_name(&"r_b") == "민수", "name cache") and ok
	# Copies: changing a returned entry does not change the journal.
	Journal.entries_for_day(10)[0]["text"] = "changed"
	ok = _expect(Journal.entries_for_day(10)[0]["text"] != "changed", "entries_for_day returned the original") and ok
	return ok


func _check_epilogue() -> bool:
	_reset(20)
	var a := Colony.add_resident({"name": "지은"})
	var b := Colony.add_resident({"name": "민수"})
	var c := Colony.add_resident({"name": "하나"})
	var d := Colony.add_resident({"name": "도윤"})
	await Engine.get_main_loop().process_frame
	EventBus.relationship_changed.emit(a, b, &"spouse")
	GameState.day = 21
	Colony._kill(c, &"raid")  # the real path: status DEAD, then resident_died
	Colony._leave(d, &"low_morale")
	var cards := Journal.epilogue(Enums.EndingChoice.STAY)
	var by_id := {}
	for card: Dictionary in cards:
		by_id[card["resident_id"]] = card
	var ok := _expect(cards.size() == 4, "epilogue has %d cards" % cards.size())
	ok = _expect(by_id.has(a) and by_id[a]["status"] == &"active" and by_id[a]["lines"].size() == 2,
		"a card %s" % by_id.get(a)) and ok
	var a_text := " ".join(by_id.get(a, {"lines": []})["lines"])
	ok = _expect(a_text.contains("지은") and a_text.contains("민수"), "family highlight missing: %s" % a_text) and ok
	ok = _expect(Journal.templates[&"epilogue_stay"].lines.any(func(l): return Journal.fill(l, {"name": "지은", "joined": 20}) == by_id[a]["lines"][0]),
		"stay ending line not used: %s" % by_id[a]["lines"][0]) and ok
	ok = _expect(by_id.get(c, {}).get("status") == &"dead", "dead card %s" % by_id.get(c)) and ok
	ok = _expect(by_id.get(d, {}).get("status") == &"left" and " ".join(by_id[d]["lines"]).contains("도윤"),
		"left card %s" % by_id.get(d)) and ok
	for card: Dictionary in cards:
		for line: String in card["lines"]:
			ok = _expect(line != "" and not line.contains("{"), "epilogue line %s" % line) and ok
	# Stable: the same journal gives the same epilogue; LEAVE changes the active residents' first line.
	var again := Journal.epilogue(Enums.EndingChoice.STAY)
	ok = _expect(str(again) == str(cards), "epilogue not stable") and ok
	var leave := Journal.epilogue(Enums.EndingChoice.LEAVE)
	ok = _expect(Journal.templates[&"epilogue_leave"].lines.any(func(l): return Journal.fill(l, {"name": "지은", "joined": 20}) == leave[0]["lines"][0]),
		"leave ending line not used: %s" % leave[0]["lines"][0]) and ok
	return ok


func _check_save_round_trip() -> bool:
	_reset(30)
	Journal.record(&"rescued", {"resident_id": &"r_a", "name": "지은"})
	Journal.record(&"friend", {"resident_id": &"r_a", "other_id": &"r_b", "name": "지은", "other": "민수"})
	EventBus.day_started.emit(30)
	var before := Journal.save_data()
	var epilogue_before := str(Journal.epilogue())
	# Same path as SaveSystem: Godot-typed JSON text and back.
	var parsed: Variant = JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(before))))
	Journal.load_data({})
	var cleared := Journal.days().is_empty() and Journal.people().is_empty()
	Journal.load_data(parsed)
	var ok := _expect(cleared, "load_data({}) did not clear the journal")
	ok = _expect(str(Journal.save_data()) == str(before), "round trip changed data:\n%s\n%s" % [Journal.save_data(), before]) and ok
	ok = _expect(Journal.entries_for_resident(&"r_a").size() == 2 and Journal.entries_for_day(30)[1]["residents"].get_typed_builtin() == TYPE_STRING_NAME,
		"entries after load") and ok
	ok = _expect(str(Journal.epilogue()) == epilogue_before, "epilogue changed after load") and ok
	return ok
