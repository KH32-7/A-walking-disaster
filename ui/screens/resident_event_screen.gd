class_name ResidentEventScreen
extends ResidentSceneScreen
## Shared layout of the resident event screens (#125: prejudice_choice, child_wish, wedding_prep).
## Owner: Lane D. Same as the D-13 talk screen (UI_RULES §4 "장면형 화면"): the base on the left,
## the cream card column on the right, the conversation strip with up to three cream pill choices
## along the bottom. Adds the people in the event as portrait cards on the left, with the relation
## line between neighbours (shape = stage, RelationGraph) and small note chips under each name.

var people: HBoxContainer


func _build_body(b: Control) -> void:
	people = HBoxContainer.new()
	people.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	people.anchor_right = ResidentSceneScreen.RIGHT
	people.offset_left = 52
	people.offset_right = -20
	people.offset_top = 150
	people.offset_bottom = -340
	people.alignment = BoxContainer.ALIGNMENT_CENTER
	people.add_theme_constant_override(&"separation", 18)
	people.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(people)
	super._build_body(b)
	move_child(people, dialog.get_index())


## Portrait cards for `ids` with the relation line between neighbours.
## chips: resident id -> [[text, colour], ...] under the name.
func draw_people(ids: Array, chips: Dictionary = {}, portrait := Vector2(230, 270)) -> void:
	MenuScreen.clear(people)
	for i in ids.size():
		var id := StringName(ids[i])
		if i > 0:
			people.add_child(link(StringName(ids[i - 1]), id))
		var card := VBoxContainer.new()
		card.add_theme_constant_override(&"separation", 8)
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		var p := ResidentPortrait.new(portrait)
		card.add_child(p)
		p.set_resident(id)
		var nm := MenuScreen.label(ResidentText.call_name(Colony.get_resident(id)), &"LabelSection", 20)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override(&"separation", 6)
		for c: Array in chips.get(id, []):
			row.add_child(DialogBox.note_chip(String(c[0]), c[1] if c.size() > 1 else UiTokens.TEXT))
		card.add_child(row)
		people.add_child(card)


## The relation line between two people: its shape tells the stage, the stage name under it.
func link(a: StringName, b: StringName) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override(&"separation", 4)
	v.custom_minimum_size = Vector2(120, 270)
	var stage := Colony.relation_stage(a, b)
	var s := RelationGraph.LineSample.new(stage)
	s.custom_minimum_size = Vector2(120, 26)
	v.add_child(s)
	var l := MenuScreen.label(RelationGraph.stage_name(stage), &"LabelHud", 15)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


# ---------------- cream card builders ----------------

## A cream card in the right column. Returns its content VBox.
func card() -> VBoxContainer:
	var cc := MenuScreen.cream_card(0)
	column.add_child(cc[0])
	var v: VBoxContainer = cc[1]
	v.add_theme_constant_override(&"separation", 10)
	return v


static func card_title(t: String) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCream", 26)
	l.add_theme_font_override(&"font", UiThemeBuilder.font_kr(700))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func card_text(t: String, dim := false, size_px := 16) -> Label:
	var l := MenuScreen.label(t, &"LabelOnCreamDim" if dim else &"LabelOnCream", size_px)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## One row with a shape mark in front (✓ ● ○ ✕ …), so state never reads by colour alone.
static func mark_row(mark: String, text: String, strong := true, mark_color := UiTokens.TEXT_ON_CREAM) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override(&"separation", 10)
	var m := MenuScreen.label(mark, &"LabelOnCream", 16)
	m.custom_minimum_size = Vector2(22, 0)
	m.add_theme_color_override(&"font_color", mark_color)
	h.add_child(m)
	var l := card_text(text, not strong, 16)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h
