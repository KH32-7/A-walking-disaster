extends Node
## B-28: hit marker kinds (kill > crit/weak point > hit, nothing for non-monsters), a kill marker is
## not replaced by the next pellet, the OS cursor comes back when the reticle hides.


func run() -> bool:
	var ok := true
	ok = _expect(AimReticle.hit_kind(Node.new(), {}) == &"", "non-monster hit gives no marker") and ok
	var reticle := AimReticle.new()
	add_child(reticle)
	reticle.show_hit(&"kill")
	reticle.show_hit(&"hit")
	ok = _expect(reticle._mark == &"kill", "kill marker is not cut short by a plain hit") and ok
	reticle._mark = &""
	reticle.show_hit(&"hit")
	reticle.show_hit(&"crit")
	ok = _expect(reticle._mark == &"crit", "crit replaces a plain hit") and ok
	reticle._set_cursor_hidden(true)
	reticle.visible = false
	ok = _expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cursor back when the reticle hides") and ok
	reticle.queue_free()
	return ok


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		push_error("test_aim_reticle: " + what)
	return cond
