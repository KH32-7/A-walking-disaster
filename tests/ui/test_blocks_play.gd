extends Node
## UI.blocks_play() (user report 2026-11-06): while a menu, a confirm dialog or a cinematic talk is up,
## clicks and Space belong to the UI, so the field player must not shoot or dodge. The field map stays
## playable. Also: a VisionShade whose camera never processes (the base map) stays hidden.


func run() -> bool:
	var ok := true
	UI.close_all()
	await get_tree().process_frame
	ok = _expect(not UI.blocks_play(), "nothing open: play goes on") and ok
	UI.open(&"bag")
	await get_tree().process_frame
	ok = _expect(UI.blocks_play(), "the bag (a screen that does not pause) blocks play") and ok
	UI.close_all()
	UI.open(&"map")
	await get_tree().process_frame
	ok = _expect(not UI.blocks_play(), "the field map does not block play") and ok
	UI.close_all()
	await get_tree().process_frame
	var dialog := ConfirmDialog.ask(UI.overlay, "테스트", "본문", "확인", func() -> void: pass)
	ok = _expect(UI.blocks_play(), "a confirm dialog blocks play") and ok
	dialog.queue_free()
	await get_tree().process_frame
	ok = _expect(not UI.blocks_play(), "and play comes back when it closes") and ok

	var shade := VisionShade.new()
	shade.process_mode = Node.PROCESS_MODE_DISABLED  # like the base map's switched-off FieldCamera
	add_child(shade)
	await get_tree().process_frame
	ok = _expect(not shade.visible, "a vision shade that never processes stays hidden") and ok
	shade.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr("test_blocks_play: " + message)
	return cond
