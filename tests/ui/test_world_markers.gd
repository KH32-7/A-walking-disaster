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

	# Speech bubbles from rescue targets (B-10 called_out).
	var person := Node3D.new()
	person.add_user_signal(&"called_out", [{"name": "text", "type": TYPE_STRING}, {"name": "near", "type": TYPE_BOOL}])
	person.add_to_group(WorldMarkers.RESCUE_GROUP)
	add_child(person)
	wm._process(0.02)
	person.emit_signal(&"called_out", "어어... 사람 소리다...", false)
	ok = _expect(wm.bubble_texts() == ["어어... 사람 소리다..."], "called_out shows a bubble") and ok
	person.emit_signal(&"called_out", "으... 제발 살려주세요", true)
	ok = _expect(wm.bubble_texts() == ["으... 제발 살려주세요"], "one bubble per person, the newest") and ok
	for i in 200:
		wm._process(0.02)
	ok = _expect(wm.bubble_texts().is_empty(), "bubble gone after 3.5 s") and ok
	wm.add_bubble(person, "여기요")
	person.free()
	wm._process(0.02)
	ok = _expect(wm.bubble_texts().is_empty(), "bubble of a removed person goes too") and ok
	wm.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
