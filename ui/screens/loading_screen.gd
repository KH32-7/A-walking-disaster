class_name LoadingScreen
extends Control
## Loading / scene transition card (D-19). Owner: Lane D. Screen id `loading` (overlay).
## UI_RULES §6 "장면 전환": black screen, one line in the middle, the Haesol stripe (teal + yellow)
## slides in from both sides in 0.4 s, one tip line at the bottom. Then it fades out by itself.
## UI opens it on sortie (출격), return (귀환), going down (쓰러짐) and when a game is loaded from the
## title (transition_for). Nothing here decides game flow; it only draws the change that happened.
##
## open_with(args):
##   kind      &"sortie" | &"return" | &"down" | &"load" | &"generic"
##   region_id field region for the line ("출격 — 침수 상가")
##   text      overrides the line
##   tip       overrides the tip ("" picks one from data/ui/loading_tips.tres)
##   duration  seconds before it fades out (default HOLD); auto_close false keeps it up

const TIPS_PATH := "res://data/ui/loading_tips.tres"
const PREP := preload("res://ui/screens/sortie_prep_screen.gd")
const HOLD := 1.4
const FADE_IN := 0.15
const FADE_OUT := 0.3
const S := Enums.FlowState

var kind: StringName = &"generic"
var region_id: StringName = &""
var line := ""
var tip := ""
var duration := HOLD
var auto_close := true

var _line_label: Label
var _tip_label: Label
var _bands: HaesolBands
var _center: VBoxContainer
var _closing := false
var _elapsed := 0.0


## Which transition card (if any) a flow change shows. {} = none.
static func transition_for(from: Enums.FlowState, to: Enums.FlowState) -> Dictionary:
	if from == to:
		return {}
	if to == S.FIELD:
		return {"kind": &"load" if from == S.TITLE else &"sortie"}
	if from == S.FIELD and to == S.RESULT:
		var downed := bool(SceneRouter.last_sortie_result.get("downed", false))
		return {"kind": &"down" if downed else &"return"}
	if from == S.FIELD and to == S.BASE_DAY_RAID:
		return {"kind": &"return"}
	if from == S.TITLE and to != S.TITLE:
		return {"kind": &"load"}
	return {}


static func region_name(id: StringName) -> String:
	for reg: Dictionary in PREP.REGIONS:
		if reg.id == id:
			return String(reg.name)
	return ""


## The one line for a kind (D copy, no game numbers except the day).
static func line_for(k: StringName, region: StringName = &"") -> String:
	var where := region_name(region)
	match k:
		&"sortie":
			return "출격: %s" % where if where != "" else "출격"
		&"return":
			return "귀환: 기지로"
		&"down":
			return "쓰러짐: 기지로 돌아간다"
		&"load":
			if GameState.flow_state == S.FIELD and where != "":
				return "%d일차: %s" % [GameState.day, where]
			return "%d일차: 해솔시" % GameState.day
	return "불러오는 중"


func open_with(args: Dictionary) -> void:
	kind = StringName(args.get("kind", kind))
	region_id = StringName(args.get("region_id", region_id))
	line = String(args.get("text", ""))
	if line == "":
		line = line_for(kind, region_id)
	if args.has("tip"):
		tip = String(args["tip"])
	if tip == "":
		var tips := load(TIPS_PATH) as LoadingTips
		tip = tips.pick(int(Time.get_ticks_msec() / 997) + GameState.day) if tips != null else ""
	duration = float(args.get("duration", duration))
	auto_close = bool(args.get("auto_close", auto_close))
	if is_inside_tree():
		_apply_text()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keeps animating over a pausing screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if line == "":
		open_with({})
	var bg := ColorRect.new()
	bg.color = UiTokens.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_center = VBoxContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override(&"separation", 26)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_line_label = MenuScreen.label("", &"LabelTitle", 38)
	_line_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_child(_line_label)
	_bands = HaesolBands.new()
	_bands.reach = 1.0
	_bands.teal_width = 8.0
	_bands.yellow_width = 4.0
	_center.add_child(_bands)

	var tip_row := HBoxContainer.new()
	tip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tip_row.add_theme_constant_override(&"separation", 14)
	tip_row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tip_row.offset_top = -150
	tip_row.offset_bottom = -110
	tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := MenuScreen.label("팁", &"LabelSection", 17)
	tag.add_theme_color_override(&"font_color", UiTokens.INFO)
	tip_row.add_child(tag)
	_tip_label = MenuScreen.label("", &"LabelHud", 18)
	_tip_label.add_theme_color_override(&"font_color", UiTokens.TEXT_DIM)
	tip_row.add_child(_tip_label)
	add_child(tip_row)
	_apply_text()

	_line_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_line_label, ^"modulate:a", 1.0, FADE_IN)
	_bands.play(HaesolBands.IN_TIME)


func _apply_text() -> void:
	if _line_label == null:
		return
	_line_label.text = line
	_tip_label.text = tip
	_tip_label.get_parent().visible = tip != ""


func _process(delta: float) -> void:
	_elapsed += delta
	if auto_close and not _closing and _elapsed >= duration:
		finish()


## Fades out and closes (also called when the next scene is ready, if auto_close is off).
func finish() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween()
	t.tween_property(self, ^"modulate:a", 0.0, FADE_OUT)
	t.tween_callback(func() -> void: UI.close(StringName(name)))
