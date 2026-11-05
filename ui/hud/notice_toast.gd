class_name NoticeToast
extends VBoxContainer
## EventBus.notification_posted while no HUD shows it (D-16). Owner: Lane D.
## The field HUD (reward feed / hint card, D-04) and the base HUD (note list, D-06) show
## notifications themselves; when a screen hides the HUD (map, bag, journal ...) or no HUD is up
## (sortie prep, result), this small stack (bottom right, above the footer row) shows them instead, so nothing that
## asks for action is lost. Severity is a word + shape tag, never colour only.

const MAX := 3
const SEC := 4.0
const TAGS := {&"info": ["알림", "●"], &"warn": ["주의", "▲"], &"danger": ["위험", "■"]}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override(&"separation", 8)
	EventBus.notification_posted.connect(_on_notification)


## True when the field or base HUD is on screen and will show the notification itself.
static func hud_shows_notices() -> bool:
	if not UI.hud.visible:
		return false
	return (UI.field_hud != null and UI.field_hud.visible) or (UI.base_hud != null and UI.base_hud.visible)


func _on_notification(text: String, severity: StringName) -> void:
	if not hud_shows_notices():
		push(text, severity)


func push(text: String, severity: StringName = &"info") -> void:
	if text.begins_with("@") and text.find(" ") > 0:  # "@screen_id text" (BaseHud click target)
		text = text.substr(text.find(" ") + 1)
	var tag: Array = TAGS.get(severity, TAGS[&"info"])
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardCream"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 12)
	card.add_child(h)
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTokens.DANGER if severity == &"danger" else (UiTokens.WARN if severity == &"warn" else UiTokens.GREY_BTN)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	chip.add_theme_stylebox_override(&"panel", sb)
	var tl := MenuScreen.label("%s %s" % [tag[1], tag[0]], &"Label", 14)
	tl.add_theme_color_override(&"font_color", UiTokens.TEXT if severity == &"danger" else UiTokens.ACCENT_TEXT)
	chip.add_child(tl)
	h.add_child(chip)
	h.add_child(MenuScreen.label(text, &"LabelOnCream"))
	add_child(card)
	while get_child_count() > MAX:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, ^"modulate:a", 1.0, 0.25)
	tw.tween_interval(SEC)
	tw.tween_property(card, ^"modulate:a", 0.0, 0.3)
	tw.tween_callback(card.queue_free)


func count() -> int:
	return get_child_count()
