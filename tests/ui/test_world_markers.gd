extends Node
## D-05: monster marks, speech bubbles and edge arrows. Noise rings were removed (2026-11-06).


func run() -> bool:
	var ok := true
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.SUSPICIOUS) == &"suspicious"
		and WorldMarkers.mark_for(Enums.AIState.INVESTIGATE) == &"suspicious", "? for suspicious/investigate") and ok
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.CHASE) == &"alert"
		and WorldMarkers.mark_for(Enums.AIState.ATTACK) == &"alert", "! for chase/attack") and ok
	ok = _expect(WorldMarkers.mark_for(Enums.AIState.WANDER) == &"", "no mark while wandering") and ok
	var wm := WorldMarkers.new()
	add_child(wm)
	# No ground rings any more (user 2026-11-06); a noise must not leave anything drawn on the ground.
	ok = _expect(not wm.has_method(&"ring_count"), "no noise ring API left") and ok
	EventBus.noise_emitted.emit(Vector3.ZERO, 8.0, null)
	wm._process(0.02)

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
	# Two edge labels at one spot step apart along the edge instead of printing on top of each other
	# ("11m" under "?", QA 2026-11-06).
	wm._label_rects.clear()
	var a: Vector2 = wm._free_label_spot(Vector2(400, 140), "11m", 17, Vector2(1, 0))
	var b: Vector2 = wm._free_label_spot(Vector2(400, 140), "?", 17, Vector2(1, 0))
	ok = _expect(a == Vector2(400, 140) and b.y == a.y and absf(b.x - a.x) > 10.0, "second label moves along the edge (%s, %s)" % [a, b]) and ok
	ok = _expect(not wm._label_rects[0].intersects(wm._label_rects[1]), "the two label boxes do not overlap") and ok
	wm.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
