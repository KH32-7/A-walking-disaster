extends RefCounted
## GameState flow/phase contract (A-01) and season math.


func run() -> bool:
	var saved := GameState.save_data()
	var saved_flow := GameState.flow_state
	var ok := _check_phase_map() and _check_flow_signals() and _check_season() and _check_weather()
	GameState.load_data(saved)
	GameState.flow_state = saved_flow
	return ok


func _check_phase_map() -> bool:
	for state in Enums.FlowState.values():
		if state == Enums.FlowState.TITLE:
			if GameState.PHASE_OF_FLOW.has(state):
				printerr("TITLE must not map to a phase")
				return false
		elif not GameState.PHASE_OF_FLOW.has(state):
			printerr("FlowState %s has no phase" % Enums.FlowState.keys()[state])
			return false
	return true


func _check_flow_signals() -> bool:
	var flows: Array = []
	var phases: Array = []
	var on_flow := func(s): flows.append(s)
	var on_phase := func(p): phases.append(p)
	EventBus.flow_state_changed.connect(on_flow)
	EventBus.phase_changed.connect(on_phase)

	GameState.flow_state = Enums.FlowState.TITLE
	GameState.phase = Enums.Phase.NIGHT
	GameState.set_flow_state(Enums.FlowState.BASE_MORNING)  # flow + phase
	GameState.set_flow_state(Enums.FlowState.SORTIE_PREP)  # flow only (still MORNING)
	GameState.set_flow_state(Enums.FlowState.SORTIE_PREP)  # nothing

	EventBus.flow_state_changed.disconnect(on_flow)
	EventBus.phase_changed.disconnect(on_phase)
	var ok := flows == [Enums.FlowState.BASE_MORNING, Enums.FlowState.SORTIE_PREP] \
		and phases == [Enums.Phase.MORNING]
	if not ok:
		printerr("flow signals %s, phase signals %s" % [flows, phases])
	return ok


func _check_weather() -> bool:
	var seen: Array = []
	var on_weather := func(w): seen.append(w)
	EventBus.weather_changed.connect(on_weather)
	GameState.weather = Enums.Weather.CLEAR
	GameState.set_weather(Enums.Weather.RAIN)
	GameState.set_weather(Enums.Weather.RAIN)  # no second signal
	var signals_ok := seen == [Enums.Weather.RAIN] and GameState.is_raining()
	var saved := GameState.save_data()
	GameState.set_weather(Enums.Weather.CLEAR)
	GameState.load_data(saved)
	var restored := GameState.weather == Enums.Weather.RAIN
	EventBus.weather_changed.disconnect(on_weather)
	# Summer rains more often than spring over many rolls.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var rain := {Enums.Season.SPRING: 0, Enums.Season.SUMMER: 0}
	for d in [1, 16]:
		GameState.day = d
		for i in 400:
			GameState.roll_weather(rng)
			rain[GameState.season()] += int(GameState.is_raining())
	var ok: bool = signals_ok and restored and rain[Enums.Season.SUMMER] > rain[Enums.Season.SPRING] \
		and rain[Enums.Season.SPRING] > 0
	if not ok:
		printerr("weather: signals %s restored %s rain %s" % [seen, restored, rain])
	return ok


func _check_season() -> bool:
	var cases := {1: Enums.Season.SPRING, 15: Enums.Season.SPRING, 16: Enums.Season.SUMMER,
		46: Enums.Season.WINTER, 61: Enums.Season.SPRING}
	for d in cases:
		GameState.day = d
		if GameState.season() != cases[d]:
			printerr("day %d -> season %d, expected %d" % [d, GameState.season(), cases[d]])
			return false
	return true
