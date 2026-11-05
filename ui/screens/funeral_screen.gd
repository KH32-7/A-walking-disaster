extends Control
## Funeral (#125 part 3, C-20). Owner: Lane D. Screen id `funeral`. Design 08 "사망과 추모".
## A quiet scene the morning after a death: the base dims, one page per resident with the face first
## (ResidentPortrait), then the name, the
## day they joined, the memorial line and one line of their story, then who is grieving.
## Opened by UI on Colony.funeral_ready(resident_ids); the last page's button (or Esc) calls
## Colony.end_funeral() and closes. open_with({"resident_ids": [...]}) — default Colony.pending_funeral().

var ids: Array[StringName] = []
var index := 0

var _built := false
var _kicker: Label
var _name: Label
var _portrait: ResidentPortrait
var _when: Label
var _story: Label
var _stone: Label
var _mourners: Label
var _next: Button
var _count: Label
var _ended := false


func open_with(args: Dictionary) -> void:
	ids.clear()
	for id in args.get("resident_ids", Colony.pending_funeral()):
		ids.append(StringName(id))
	index = 0
	if _built:
		_show()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ids.is_empty():
		for id in Colony.pending_funeral():
			ids.append(id)
	var bg := ColorRect.new()
	bg.color = Color(UiTokens.INK, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 18)
	col.custom_minimum_size = Vector2(660, 0)
	center.add_child(col)
	_kicker = _centered(MenuScreen.label("", &"LabelHud", 18))
	_kicker.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	col.add_child(_kicker)
	# 그림 먼저 (UI 재설계): the face, then a candle on the line under it, then the words.
	var pc := CenterContainer.new()
	_portrait = ResidentPortrait.new(Vector2(210, 240))
	pc.add_child(_portrait)
	col.add_child(pc)
	col.add_child(Candle.new())
	_name = _centered(MenuScreen.label("", &"LabelTitle", 46))
	col.add_child(_name)
	_when = _centered(MenuScreen.label("", &"LabelDim", 16))
	col.add_child(_when)
	var cc := MenuScreen.cream_card(660)
	var cv: VBoxContainer = cc[1]
	cv.add_theme_constant_override(&"separation", 10)
	_story = MenuScreen.label("", &"LabelOnCream", 19)
	_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_story)
	cv.add_child(HSeparator.new())
	_stone = MenuScreen.label("", &"LabelOnCreamDim", 15)
	_stone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stone.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_stone)
	col.add_child(cc[0])
	_mourners = _centered(MenuScreen.label("", &"LabelHud", 16))
	_mourners.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_mourners)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	_count = MenuScreen.label("", &"LabelDim", 15)
	row.add_child(_count)
	_next = MenuScreen.button("", &"ButtonPrimary")
	_next.custom_minimum_size = Vector2(220, 52)
	_next.pressed.connect(_advance)
	row.add_child(_next)
	col.add_child(row)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override(&"separation", 10)
	foot.add_child(KeyChip.new("Enter", KeyChip.Style.OUTLINE))
	foot.add_child(MenuScreen.label("계속", &"LabelHud"))
	add_child(foot)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position += Vector2(52, -34)
	_built = true
	_show()
	_focus_next.call_deferred()


func _focus_next() -> void:
	if is_inside_tree() and is_instance_valid(_next):
		_next.grab_focus()


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _show() -> void:
	_kicker.text = "%d일차 아침 · 장례" % GameState.day
	if ids.is_empty():
		_portrait.visible = false
		_name.text = "보낼 사람이 없어요"
		_when.text = ""
		_story.text = ""
		_stone.text = ""
		_mourners.text = ""
		_count.text = ""
		_next.text = "닫기"
		return
	var id := ids[index]
	var r := Colony.get_resident(id)
	_portrait.set_resident(id)
	_name.text = LossText.display_name(id)
	var mem := _memorial_entry(id)
	_when.text = "%d일차에 합류%s" % [int(r.get("joined_day", 1)),
		" · %s 떠남" % LossText.memorial_line(mem) if not mem.is_empty() else ""]
	_story.text = "“%s”" % LossText.story_line(id)
	_stone.text = "추모비에 이름을 새겼어요." if not mem.is_empty() else ""
	_stone.visible = _stone.text != ""
	_mourners.text = _mourner_line()
	_count.text = "%d / %d" % [index + 1, ids.size()] if ids.size() > 1 else ""
	_next.text = "다음 사람" if index + 1 < ids.size() else "보내 주기"


func _memorial_entry(id: StringName) -> Dictionary:
	for m: Dictionary in Colony.memorial_names():
		if StringName(m.get("resident_id", &"")) == id:
			return m
	return {}


## "◇ 슬픔에 잠긴 사람  한지호 10일 · 문소라 5일" from the residents' grief_days.
func _mourner_line() -> String:
	var parts: PackedStringArray = []
	for id in Colony.active_resident_ids():
		var d := int(Colony.get_resident(id).get("grief_days", 0))
		if d > 0:
			parts.append("%s %d일" % [LossText.display_name(id), d])
	if parts.is_empty():
		return "모두 조용히 자리를 지켰어요."
	return "◇ 슬픔에 잠긴 사람   " + " · ".join(parts)


func _advance() -> void:
	if index + 1 < ids.size():
		index += 1
		_show()
	else:
		close()


## Esc and the last button: the scene is over.
func close() -> void:
	if not _ended:
		_ended = true
		Colony.end_funeral()
	UI.close(StringName(name))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") and not _next.has_focus():
		_advance()
		get_viewport().set_input_as_handled()


## A small flame over a short line: the only motion-free ornament of the scene.
class Candle extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, 0)
		draw_rect(Rect2(c + Vector2(-5, 20), Vector2(10, 20)), UiTokens.CREAM)
		draw_line(c + Vector2(0, 20), c + Vector2(0, 15), UiTokens.TEXT_DIM, 2.0)
		var flame := PackedVector2Array([c + Vector2(0, 0), c + Vector2(5, 10), c + Vector2(0, 17), c + Vector2(-5, 10)])
		draw_colored_polygon(flame, UiTokens.WARN)
		draw_line(c + Vector2(-140, 40), c + Vector2(140, 40), UiTokens.LINE, 1.0)
