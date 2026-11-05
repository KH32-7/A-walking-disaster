extends RefCounted
## DebugConsole (A-03): register/execute, built-in commands. Tests run in debug builds.


func run() -> bool:
	var saved_game := GameState.save_data()
	var saved_flow := GameState.flow_state
	var saved_economy := Economy.save_data()
	var saved_godmode := DebugConsole.godmode
	var ok := _check_register() and _check_res() and _check_phase_flow() and _check_godmode() \
		and _check_unknown()
	GameState.load_data(saved_game)
	GameState.flow_state = saved_flow
	Economy.load_data(saved_economy)
	DebugConsole.godmode = saved_godmode
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond


func _check_register() -> bool:
	DebugConsole.register(&"zz_echo", func(args: PackedStringArray): return "|".join(args))
	var out := DebugConsole.execute("zz_echo a b")
	DebugConsole.register(&"zz_echo", func(_args: PackedStringArray): return "replaced")
	var replaced := DebugConsole.execute("ZZ_ECHO")
	return _expect(out == "a|b", "echo -> %s" % out) \
		and _expect(replaced == "replaced", "re-register -> %s" % replaced)


func _check_res() -> bool:
	Economy.amounts = {}
	DebugConsole.execute("res wood 30")
	var after_add := Economy.get_amount(&"wood")
	var fail := DebugConsole.execute("res wood -100")
	return _expect(after_add == 30, "res add -> %d" % after_add) \
		and _expect(Economy.get_amount(&"wood") == 30, "negative res changed amount") \
		and _expect(fail.begins_with("실패"), "res below zero -> %s" % fail) \
		and _expect(DebugConsole.execute("res wood").begins_with("사용법"), "res usage")


func _check_phase_flow() -> bool:
	DebugConsole.execute("phase night")
	var phase_ok := GameState.phase == Enums.Phase.NIGHT
	DebugConsole.execute("flow sortie_prep")
	return _expect(phase_ok, "phase night") \
		and _expect(GameState.flow_state == Enums.FlowState.SORTIE_PREP, "flow sortie_prep") \
		and _expect(GameState.phase == Enums.Phase.MORNING, "flow did not move phase")


func _check_godmode() -> bool:
	DebugConsole.execute("godmode on")
	var on := DebugConsole.godmode
	DebugConsole.execute("godmode")
	return _expect(on and not DebugConsole.godmode, "godmode toggle")


func _check_unknown() -> bool:
	return _expect(DebugConsole.execute("nope").begins_with("알 수 없는"), "unknown command") \
		and _expect(DebugConsole.execute("   ") == "", "blank line")
