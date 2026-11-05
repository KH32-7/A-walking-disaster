class_name MapScreen
extends MenuScreen
## Field map (M, D-16). Owner: Lane D. Design 14 "지도: 탐색한 영역, 탈출 지점, 목표, 숨은 경로".
## UI_RULES §9 D-16 / D-07 map layout: goals on the left, map in the middle, legend on the right.
## Real time (does not pause): the player arrow and party move while it is open.
##
## Reads only (no game rules here):
##   field markers (field/markers/, groups) for the map bounds, ExtractPoint, Recording, HiddenRoute
##   ExtractionManager.active_point_ids() (B-09) — only the sortie's active exits are drawn
##   Quests.active_field_objectives(region_id) (A-13) — goal position = node named `marker`
##   FieldState.region_id, dusk_left_sec(), recoverable_gear() (B)
##   party: ExtractionManager.PARTY_GROUP nodes (display_name), player: group "player"
##   UI.explore (FieldExplore) for the explored fog. Recorders show once their spot was explored.
## Background: one top-down orthographic render of the running region (SubViewport sharing the
## world, render layer MAP_HIDDEN_LAYER excluded so B can keep monsters off the map).
## Hidden routes: drawn once revealed. B-20 has no getter yet; reads `revealed` on the HiddenRoute
## node when B adds it.
##
## open_with({"region_id", "revealed_routes": [route ids], "explore": FieldExplore}) — preview/tests.

## Render layer (1-based) the map camera skips. Ask Lane B to put monster meshes on it.
const MAP_HIDDEN_LAYER := 20
const RENDER_PX := 1024
const MARGIN_M := 14.0
const SIDE_W := 400.0
const LEGEND_W := 330.0
## Extraction type -> words (ExtractPoint.Type). Ids are not names; B has no display name yet.
const EXTRACT_TYPES := ["탈출", "탈출 · 발전기", "탈출 · 열쇠 필요", "탈출 · 배터리 필요"]
const LEGEND := [[&"player", "나"], [&"companion", "일행"], [&"extract", "탈출 지점"], [&"objective", "목표"],
	[&"route", "숨은 경로"], [&"recording", "녹음기"], [&"lost_gear", "유실물"]]
const REFRESH_SEC := 0.5

var region_id: StringName = &""
var _revealed_override: Array = []
var _explore: FieldExplore

var map: MapView
var _sub: SubViewport
var _goals: VBoxContainer
var _exits: VBoxContainer
var _dusk: Label
var _seen_label: Label
var _t := 0.0
## Last collected data, for tests: {"marks": [], "routes": [], "objectives": [], "exits": []}
var data: Dictionary = {}


func _init() -> void:
	title_text = "지도"
	footer_keys = [["M / Esc", "닫기"], ["J", "생존 일지"]]
	header_resources = []


func open_with(args: Dictionary) -> void:
	if args.has("region_id"):
		region_id = StringName(args.region_id)
	if args.has("revealed_routes"):
		_revealed_override = args.revealed_routes
	if args.has("explore"):
		_explore = args.explore
	if map != null:
		_collect()


func _build_body(b: Control) -> void:
	if region_id == &"":
		region_id = FieldState.region_id
	if _explore == null:
		_explore = UI.get(&"explore") as FieldExplore
	set_subtitle(region_name(region_id))

	_dusk = MenuScreen.label("", &"LabelNumber", 22)
	add_child(_dusk)
	_dusk.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_dusk.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dusk.position += Vector2(-52, 40)

	var lp := MenuScreen.panel("목표", "")
	var left: PanelContainer = lp[0]
	b.add_child(left)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = SIDE_W
	var lv: VBoxContainer = lp[1]
	_goals = VBoxContainer.new()
	_goals.add_theme_constant_override(&"separation", 12)
	lv.add_child(_goals)
	var sep := HSeparator.new()
	lv.add_child(sep)
	var eh := PanelContainer.new()
	eh.theme_type_variation = &"PanelBand"
	eh.add_child(MenuScreen.label("탈출 지점", &"LabelSection"))
	lv.add_child(eh)
	_exits = VBoxContainer.new()
	_exits.add_theme_constant_override(&"separation", 10)
	lv.add_child(_exits)

	var rp := MenuScreen.panel("범례", "")
	var right: PanelContainer = rp[0]
	b.add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -LEGEND_W
	var rv: VBoxContainer = rp[1]
	for l: Array in LEGEND:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 14)
		var icon := _Symbol.new()
		icon.kind = l[0]
		row.add_child(icon)
		row.add_child(MenuScreen.label(String(l[1]), &"Label", 17))
		rv.add_child(row)
	rv.add_child(HSeparator.new())
	_seen_label = MenuScreen.label("", &"LabelDim", 14)
	_seen_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_seen_label)

	map = MapView.new()
	b.add_child(map)
	map.set_anchors_preset(Control.PRESET_CENTER)
	var side := minf(1080.0 - 110.0 - 90.0, 1920.0 - 104.0 - SIDE_W - LEGEND_W - 48.0)
	map.custom_minimum_size = Vector2(side, side)
	map.size = Vector2(side, side)
	# centre the map between the two side panels
	var free_left := SIDE_W + 24.0
	var free_w := (1920.0 - 104.0) - SIDE_W - LEGEND_W - 48.0
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	map.position = Vector2(free_left + (free_w - side) * 0.5, 0)
	_collect()
	_capture()


## Region display name. Journal keeps the only Korean region names for now (TODO(B): RegionDef name).
static func region_name(id: StringName) -> String:
	if id == &"":
		return "필드"
	return String(Journal.REGION_NAMES.get(id, String(id)))


func _process(delta: float) -> void:
	_update_player()
	var left := FieldState.dusk_left_sec()
	_dusk.visible = left >= 0.0
	if left >= 0.0:
		_dusk.text = "해질녘까지  %02d:%02d" % [int(left) / 60, int(left) % 60]
		_dusk.add_theme_color_override(&"font_color", UiTokens.WARN if left < FieldHud.DUSK_WARN_SEC else UiTokens.TEXT)
	_t -= delta
	if _t <= 0.0:
		_t = REFRESH_SEC
		_collect()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or UI.top() != StringName(name) or not event.is_pressed() or event.is_echo():
		return
	if event.is_action(&"map"):
		close()
		get_viewport().set_input_as_handled()
	elif (event as InputEventKey).keycode == KEY_J:
		UI.open(&"journal")
		get_viewport().set_input_as_handled()


# ---------------- data ----------------

func _markers(group: StringName) -> Array:
	return get_tree().get_nodes_in_group(group).filter(func(n: Node) -> bool: return n is Node3D)


## Square x/z rectangle around every field marker, MARGIN_M on each side.
func _bounds() -> Rect2:
	var pts: Array = _markers(FieldMarker.GROUP_ALL)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if pts.is_empty():
		var c := Vector2(p.global_position.x, p.global_position.z) if p != null else Vector2.ZERO
		return Rect2(c - Vector2(60, 60), Vector2(120, 120))
	var r := Rect2(Vector2((pts[0] as Node3D).global_position.x, (pts[0] as Node3D).global_position.z), Vector2.ZERO)
	for n: Node3D in pts:
		r = r.expand(Vector2(n.global_position.x, n.global_position.z))
	r = r.grow(MARGIN_M)
	var s := maxf(r.size.x, r.size.y)
	return Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))


func _extraction() -> Node:
	return get_tree().get_first_node_in_group(ExtractionManager.GROUP)


func _collect() -> void:
	if map == null:
		return
	map.bounds = _bounds()
	var marks: Array = []
	var exits: Array = []
	var em := _extraction()
	var active: Array = em.call(&"active_point_ids") if em != null else []
	for p: ExtractPoint in _markers(ExtractPoint.GROUP):
		if em != null and not p.id in active:
			continue
		var label := String(EXTRACT_TYPES[clampi(int(p.type), 0, EXTRACT_TYPES.size() - 1)])
		marks.append({"pos": p.global_position, "kind": &"extract", "label": label})
		exits.append({"pos": p.global_position, "label": label, "wait": p.wait_sec, "noise": p.noise_radius, "id": p.id})
	var objectives: Array = []
	for o: Dictionary in Quests.active_field_objectives(region_id):
		var node := _find_marker(StringName(o.get("marker", &"")))
		var entry := o.duplicate()
		entry["found"] = node != null
		if node != null:
			entry["pos"] = node.global_position
			marks.append({"pos": node.global_position, "kind": &"objective", "label": _short(String(o.text))})
		objectives.append(entry)
	for r: Node3D in _markers(Recording.GROUP):
		if _explore != null and _explore.is_seen(r.global_position):
			marks.append({"pos": r.global_position, "kind": &"recording", "label": "녹음기"})
	for g: Dictionary in FieldState.recoverable_gear():
		marks.append({"pos": g.position, "kind": &"lost_gear", "label": "유실물"})
	for n: Node3D in _markers(ExtractionManager.PARTY_GROUP):
		marks.append({"pos": n.global_position, "kind": &"companion", "label": String(n.get(&"display_name"))
			if n.get(&"display_name") != null else ""})
	var routes: Array = []
	for r: HiddenRoute in _markers(HiddenRoute.GROUP):
		if route_revealed(r):
			routes.append({"from": r.from_point(), "to": r.to_point(), "label": "숨은 경로", "id": r.id})
	map.marks = marks
	map.routes = routes
	if _explore != null:
		map.set_explored(_explore.cells, FieldExplore.CELL)
	data = {"marks": marks, "routes": routes, "objectives": objectives, "exits": exits}
	_fill_side(objectives, exits, routes.size())


func route_revealed(r: HiddenRoute) -> bool:
	if r.id in _revealed_override:
		return true
	return bool(r.get(&"revealed")) if r.get(&"revealed") != null else false


func _find_marker(marker: StringName) -> Node3D:
	if marker == &"":
		return null
	for n: Node in get_tree().get_nodes_in_group(FieldMarker.GROUP_ALL):
		if n.name == marker and n is Node3D:
			return n
	var root := get_tree().current_scene
	return root.find_child(String(marker), true, false) as Node3D if root != null else null


static func _short(text: String) -> String:
	return text if text.length() <= 14 else text.left(13) + "…"


func _update_player() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if p != null and map != null:
		map.set_player(p.global_position, -p.global_basis.z)


func _fill_side(objectives: Array, exits: Array, routes: int) -> void:
	MenuScreen.clear(_goals)
	if objectives.is_empty():
		_goals.add_child(_wrap(MenuScreen.label("이 지역에서 할 퀘스트 목표가 없어요.", &"LabelDim", 15)))
	for o: Dictionary in objectives:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var icon := _Symbol.new()
		icon.kind = &"objective"
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override(&"separation", 2)
		var t := MenuScreen.label(String(o.text), &"Label", 17)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(t)
		var quest: QuestDef = Quests.get_def(StringName(o.quest_id))
		var sub := "%s · 남은 %d" % [quest.title if quest != null else "", int(o.remaining)]
		if not o.found:
			sub += " · 위치는 현장에서"
		v.add_child(MenuScreen.label(sub, &"LabelDim", 14))
		row.add_child(v)
		_goals.add_child(row)
	MenuScreen.clear(_exits)
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if exits.is_empty():
		_exits.add_child(MenuScreen.label("아직 열린 탈출 지점이 없어요.", &"LabelDim", 15))
	for e: Dictionary in exits:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var icon := _Symbol.new()
		icon.kind = &"extract"
		row.add_child(icon)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override(&"separation", 0)
		v.add_child(MenuScreen.label(String(e.label), &"Label", 17))
		var info := "대기 %d초" % int(e.wait)
		if float(e.noise) > 0.0:
			info += " · 소음 %dm" % int(e.noise)
		v.add_child(MenuScreen.label(info, &"LabelDim", 14))
		row.add_child(v)
		if p != null:
			var d := Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(e.pos.x, e.pos.z))
			row.add_child(MenuScreen.label("%dm" % roundi(d), &"LabelNumber", 20))
		_exits.add_child(row)
	var seen := _explore.cells.size() if _explore != null else 0
	_seen_label.text = "어두운 곳은 아직 가 보지 않은 곳이에요.\n밝힌 칸 %d · 숨은 경로 %d" % [seen, routes]


static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ---------------- background render ----------------

## One orthographic top-down frame of the running world. Kept while the screen is open.
func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_sub = SubViewport.new()
	_sub.size = Vector2i(RENDER_PX, RENDER_PX)
	_sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sub.world_3d = get_viewport().world_3d
	add_child(_sub)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = map.bounds.size.x
	cam.near = 0.5
	cam.far = 400.0
	cam.cull_mask = 0xFFFFF & ~(1 << (MAP_HIDDEN_LAYER - 1))
	var c := map.bounds.get_center()
	cam.position = Vector3(c.x, 150.0, c.y)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	_sub.add_child(cam)
	cam.current = true
	map.texture = _sub.get_texture()


class _Symbol extends Control:
	var kind: StringName = &""

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		MapView.draw_symbol(self, size * 0.5, kind)
