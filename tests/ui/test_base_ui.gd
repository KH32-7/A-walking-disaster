extends Node
## D-06: base HUD, threat zones, build panel and residents screens open and draw Colony data.


func run() -> bool:
	var ok := true
	ok = _expect(BaseHud.ThreatGauge.zone_name(10) == "안전" and BaseHud.ThreatGauge.zone_name(65) == "주의"
		and BaseHud.ThreatGauge.zone_name(90) == "위험", "threat zones follow RaidRules") and ok
	UI.show_base_hud(true)
	var hud := UI.base_hud
	hud.refresh()
	hud.push_note("@residents 테스트 알림", &"warn")
	ok = _expect(hud.note_count() >= 1, "notification card added") and ok
	for id in [&"build", &"residents"]:
		ok = _expect(UI.has_screen(id), "screen %s registered" % id) and ok
		UI.open(id)
		await get_tree().process_frame
		ok = _expect(UI.top() == id and UI.get_screen(id) is MenuScreen, "screen %s opens" % id) and ok
		UI.close(id)
	ok = _expect(get_tree().paused == false, "closing unpauses") and ok
	UI.show_base_hud(false)
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
