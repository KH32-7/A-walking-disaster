extends Node
## Live construction (사용자 요청 2026-11-06): a placed site gets every idle resident, its progress
## rises in base time, and the evening adds only the rest of the day's amount. Called by tests/run_tests.gd.


func run() -> bool:
	var ok := true
	var saved := Colony.save_data()
	var saved_econ := Economy.save_data().duplicate(true)
	var old_pace := WorkRules.pace
	WorkRules.pace = 1.0
	Colony._reset()
	Economy.apply({&"wood": 200, &"stone": 200, &"scrap": 200, &"plank": 200, &"medicine": 50})
	var a := Colony.add_resident({"traits": [], "former_job": &"laborer"})
	var b := Colony.add_resident({"traits": [], "former_job": &"laborer"})
	ok = _expect(a != &"" and b != &"", "two residents to staff with (%s, %s)" % [a, b]) and ok
	var busy := b
	Colony.assign_job(busy, WorkRules.REST_JOB)
	var uid := _place_site()
	ok = _expect(uid != &"", "a site was placed") and ok
	if uid != &"":
		var workers: Array = Colony.buildings[uid]["workers"]
		ok = _expect(a in workers, "an idle resident goes to the new site (%s)" % [workers]) and ok
		ok = _expect(not busy in workers, "a resident with a job keeps it") and ok
		var daily := Colony.build_per_day(a)
		for i in 30:
			Colony.advance_live_build(WorkRules.LIVE_BUILD_SEC / 60.0)  # half a day of base time
		var mid := int(Colony.buildings.get(uid, {}).get("progress", 0))
		ok = _expect(mid >= floori(daily * 0.5) - 1 and mid > 0, "progress rises live (%d after half a day, %.1f/day)" % [mid, daily]) and ok
		for i in 200:
			Colony.advance_live_build(WorkRules.LIVE_BUILD_SEC / 60.0)
		var full := int(Colony.buildings.get(uid, {}).get("progress", 0))
		ok = _expect(full <= floori(daily) + 1, "live work stops at one day's amount (%d, %.1f/day)" % [full, daily]) and ok
	Colony.load_data(saved)
	Economy.load_data(saved_econ)
	WorkRules.pace = old_pace
	return ok


func _place_site() -> StringName:
	for def_id: StringName in [&"lumber_yard", &"bed", &"palisade", &"quarry"]:
		var uid := Colony.place_building(def_id, Vector2i.ZERO, 0, &"", false)
		if uid != &"":
			Colony.auto_staff_site(uid)
			return uid
	return &""


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
