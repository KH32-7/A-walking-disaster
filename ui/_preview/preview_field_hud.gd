extends Control
## D-04 preview: field HUD over a flat field colour with animated fake state.
## Keys: R radio line, K kill reward, H hint card, N region card, 1/2/3 text size, C high contrast.
## Optional: -- --shot=user://hud.png  saves a screenshot after a moment and quits.

const Fake := preload("res://ui/_preview/fake_field_state.gd")

var _t := 0.0
var _hud: FieldHud


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("5a6b5c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var water := ColorRect.new()
	water.color = Color("2f6f74")
	water.anchor_top = 0.62
	water.anchor_right = 1.0
	water.anchor_bottom = 1.0
	add_child(water)
	UI.close_all()  # the title screen (D-19) opens on boot; this preview only wants the HUD
	UI.show_field_hud(true)
	_hud = UI.field_hud
	_hud.auto_bind = false
	EventBus.sortie_started.emit({"region_id": &"flooded_mall", "region_name": "침수 상가 광장"})
	_hud.push_reward("약품장 뒤짐", 25)
	_hud.push_reward("마물 처치", 40)
	_hud.show_hint("소리가 곧 위치입니다", "달리거나 쏘면 소음 링이 퍼집니다. 링 안의 마물은 소리 난 곳으로 옵니다.",
		"Shift", "떼고 걷기")
	EventBus.radio_message.emit(&"broadcaster", "들리나? 상가 3층 승강기 쪽에서 누가 문을 두드린다더군.", 1)


func _process(delta: float) -> void:
	_t += delta
	var st: Dictionary = Fake.make(_t + 6.5)
	if "--view=boss" in OS.get_cmdline_user_args():
		st["boss"] = {"name": "고목 거인", "hp": 2140.0, "hp_max": 4000.0, "phase": 2, "phase_count": 2}
	_hud.set_state(st)
	if _t > 1.2 and _t - delta <= 1.2:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shot="):
				get_viewport().get_texture().get_image().save_png(a.trim_prefix("--shot="))
				get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			EventBus.radio_message.emit(&"broadcaster", "총소리가 크게 울렸어. 근처 마물이 몰려올 거야.", 1)
		KEY_K:
			_hud.push_reward("마물 처치", 40)
		KEY_H:
			_hud.show_hint("해가 지고 있어요", "해질녘이 지나면 마물이 강해집니다. 탈출 지점으로 가세요.", "M", "지도", true)
		KEY_N:
			EventBus.sortie_started.emit({"region_name": "침수 상가 광장"})
		KEY_1, KEY_2, KEY_3:
			Settings.set_value(&"text_size", (event as InputEventKey).keycode - KEY_1)
		KEY_C:
			Settings.set_value(&"high_contrast", not bool(Settings.get_value(&"high_contrast")))
