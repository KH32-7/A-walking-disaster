extends Node
## D-05: noise ring styles, monster marks, ring lifetime and the noise_rings setting.


func run() -> bool:
	var ok := true
	ok = _expect(WorldMarkers.ring_style(4.0)[1] == 2.0 and WorldMarkers.ring_style(8.0)[1] == 4.0
		and WorldMarkers.ring_style(22.0)[1] == 6.0, "ring width by radius 2/4/6") and ok
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.SUSPICIOUS) == &"suspicious"
		and WorldMarkers.mark_for(Enums.AIState.INVESTIGATE) == &"suspicious", "? for suspicious/investigate") and ok
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.CHASE) == &"alert"
		and WorldMarkers.mark_for(Enums.AIState.ATTACK) == &"alert", "! for chase/attack") and ok
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.WANDER) == &"", "no mark while wandering") and ok
	var wm := WorldMarkers.new()
	add_child(wm)
	var was: bool = Settings.get_value(&"noise_rings")
	Settings.values[&"noise_rings"] = true
	EventBus.noise_emitted.emit(Vector3.ZERO, 8.0, null)
	ok = _expect(wm.ring_count() == 1, "noise_emitted adds a ring") and ok
	for i in 50:
		wm._process(0.02)
	ok = _expect(wm.ring_count() == 0, "ring gone after 0.7 s") and ok
	Settings.values[&"noise_rings"] = false
	EventBus.noise_emitted.emit(Vector3.ZERO, 8.0, null)
	ok = _expect(wm.ring_count() == 0, "noise_rings off hides rings") and ok
	Settings.values[&"noise_rings"] = was
	wm.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
