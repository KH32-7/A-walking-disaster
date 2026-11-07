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
##   FieldState.ping / set_ping / clear_ping (B): right click on the map sets or clears it.
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
const EXTRACT_TYPES := ["탈출", "탈출 / 발전기", "탈출 / 열쇠 필요", "탈출 / 배터리 필요"]
const LEGEND := [[&"player", "나"], [&"companion", "일행"], [&"extract", "탈출 지점"], [&"objective", "목표"],
	[&"route", "숨은 경로"], [&"recording", "녹음기"], [&"lost_gear", "유실물"], [&"ping", "핑"], [&"danger", "마물 둥지, 보스"]]
const REFRESH_SEC := 0.5
## Right click within this many pixels of the ping clears it instead of moving it.
const PING_CLEAR_PX := 22.0
## Painted region maps (art/maps/README.md): region id -> [picture, world x/z rectangle it covers].
## The flooded mall art covers the 150 m map file, which the layout builds at x1.5
## (levels/field/flooded_mall/build/build_layout.gd MAP_SCALE), so 225 m centred on the origin.
## Regions without art keep the top-down render with the explored fog.
const OVERVIEWS := {
	&"flooded_mall": ["res://art/maps/flooded_mall_overview_2k.webp", Rect2(-112.5, -112.5, 225.0, 225.0)],
}

var region_id: StringName = &""
var _revealed_override: Array = []
var _explore: FieldExplore

var map: MapView
var _sub: SubViewport
var _goals: VBoxContainer
var _exits: VBoxContainer
## RegionDef.map_labels of this region (place names on the map, names for the exits).
var _place_labels: Array = []
var _dusk: Label
var _seen_label: Label
var _t := 0.0
## Last collected data, for tests: {"marks": [], "routes": [], "objectives": [], "exits": []}
var data: Dictionary = {}


func _init() -> void:
	title_text = "지도"
	footer_keys = [["M / Esc", "닫기"], ["J", "생존 일지"], ["우클릭", "핑 찍기"]]
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
	map.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	b.resized.connect(_fit_map.bind(b))
	_fit_map(b)
	var def := RegionDef.load_def(region_id)
	_place_labels = def.map_labels if def != null else []
	map.place_labels = _place_labels
	var art: Array = OVERVIEWS.get(region_id, [])
	if not art.is_empty() and ResourceLoader.exists(art[0]):
		map.set_art(load(art[0]) as Texture2D, art[1])
	_collect()
	if not map.art_mode:
		_capture()


## Largest square that fits between the two side panels, centred (any window size).
func _fit_map(b: Control) -> void:
	var free_left := SIDE_W + 24.0
	var free_w := b.size.x - SIDE_W - LEGEND_W - 48.0
	var side := maxf(120.0, minf(free_w, b.size.y))
	map.custom_minimum_size = Vector2.ZERO
	map.size = Vector2(side, side)
	map.position = Vector2(free_left + (free_w - side) * 0.5, (b.size.y - side) * 0.5)
	map.queue_redraw_all()


## Region display name. Journal keeps the only Korean region names for now (TODO(B): RegionDef name).
static func region_name(id: StringName) -> String:
	if id == &"":
		return "필드"
	var def := RegionDef.load_def(id)
	if def != null and def.name != "":
		return def.name
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
		# Mark handled first: close() removes this node, so get_viewport() is null afterwards (#86).
		get_viewport().set_input_as_handled()
		close()
	elif (event as InputEventKey).keycode == KEY_J:
		UI.open(&"journal")
		get_viewport().set_input_as_handled()


## Right click on the map sets the ping there (FieldState), or clears it when clicking on it.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed or map == null:
		return
	if not visible or UI.top() != StringName(name):
		return
	var local := map.get_global_transform_with_canvas().affine_inverse() * mb.position
	if not Rect2(Vector2.ZERO, map.size).has_point(local):
		return
	get_viewport().set_input_as_handled()
	if FieldState.has_ping and map.to_map(FieldState.ping).distance_to(local) <= PING_CLEAR_PX:
		FieldState.clear_ping()
	else:
		var p := get_tree().get_first_node_in_group(&"player") as Node3D
		var at := map.from_map(local)
		# The map has no heights: the ping sits at the player's height.
		at.y = p.global_position.y if p != null else 0.0
		FieldState.set_ping(at)
	_collect()


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


## "하역장 탈출", "주유소 탈출 · 발전기"; just the type words when no place is near.
static func exit_label(type: int, place: String) -> String:
	var kind := String(EXTRACT_TYPES[clampi(type, 0, EXTRACT_TYPES.size() - 1)])
	return kind if place.is_empty() else "%s %s" % [place, kind]


## Name of the closest landmark or road (then any place) within `max_m` metres, "" if none.
static func place_near(labels: Array, pos: Vector3, max_m := 30.0) -> String:
	var best := ""
	var best_score := INF
	for l: Dictionary in labels:
		var p: Vector2 = l.get("pos", Vector2.ZERO)
		var d := p.distance_to(Vector2(pos.x, pos.z))
		if d > max_m:
			continue
		# Landmarks and roads name a spot best; areas, water and small spots only when nothing else.
		var score := d if StringName(l.get("kind", &"")) in [&"landmark", &"road"] else d + max_m
		if score < best_score:
			best_score = score
			best = String(l.get("text", ""))
	return best


func _extraction() -> Node:
	return get_tree().get_first_node_in_group(ExtractionManager.GROUP)


func _collect() -> void:
	if map == null:
		return
	if not map.art_mode:
		map.bounds = _bounds()
	var marks: Array = []
	var exits: Array = []
	var em := _extraction()
	var active: Array = em.call(&"active_point_ids") if em != null else []
	for p: ExtractPoint in _markers(ExtractPoint.GROUP):
		if em != null and not p.id in active:
			continue
		var label := exit_label(int(p.type), place_near(_place_labels, p.global_position))
		marks.append({"pos": p.global_position, "kind": &"extract", "label": label})
		exits.append({"pos": p.global_position, "label": label, "wait": p.wait_sec, "noise": p.noise_radius, "id": p.id})
	for n in _markers(MonsterNest.GROUP):
		marks.append({"pos": n.global_position, "kind": &"danger", "label": "마물 둥지"})
	for a in _markers(BossArena.GROUP):
		marks.append({"pos": a.global_position, "kind": &"danger", "label": "보스 구역"})
	map.title = region_name(region_id)
	var objectives: Array = []
	for o: Dictionary in Quests.active_field_objectives(region_id):
		var escort := RescueTarget.escort_goal(get_tree(), o)
		var node := escort if escort != null else _find_marker(StringName(o.get("marker", &"")))
		if node == null:
			node = RescueTarget.auto_goal(get_tree(), o)
		var entry := o.duplicate()
		entry["found"] = node != null
		if node != null:
			entry["pos"] = node.global_position
			var where := "탈출 지점" if escort != null or node is ExtractPoint else String(o.get("marker_label", ""))
			marks.append({"pos": node.global_position, "kind": &"objective", "label": where if where != "" else _short(String(o.text))})
		objectives.append(entry)
	for r: Node3D in _markers(Recording.GROUP):
		if _explore != null and _explore.is_seen(r.global_position):
			marks.append({"pos": r.global_position, "kind": &"recording", "label": "녹음기"})
	for g: Dictionary in FieldState.recoverable_gear():
		marks.append({"pos": g.position, "kind": &"lost_gear", "label": "유실물"})
	if FieldState.has_ping:
		var me := get_tree().get_first_node_in_group(&"player") as Node3D
		var label := ""
		if me != null:
			label = "%dm" % roundi(Vector2(me.global_position.x, me.global_position.z).distance_to(
				Vector2(FieldState.ping.x, FieldState.ping.z)))
		marks.append({"pos": FieldState.ping, "kind": &"ping", "label": label})
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
	return text if text.length() <= 14 else text.left(13) + "..."


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
		var sub := "%s / 남은 %d" % [quest.title if quest != null else "", int(o.remaining)]
		if not o.found:
			sub += " / 위치는 현장에서"
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
			info += " / 소음 %dm" % int(e.noise)
		v.add_child(MenuScreen.label(info, &"LabelDim", 14))
		row.add_child(v)
		if p != null:
			var d := Vector2(p.global_position.x, p.global_position.z).distance_to(Vector2(e.pos.x, e.pos.z))
			row.add_child(MenuScreen.label("%dm" % roundi(d), &"LabelNumber", 20))
		_exits.add_child(row)
	var seen := _explore.cells.size() if _explore != null else 0
	if map.art_mode:
		_seen_label.text = "지역 전체 지도예요.\n숨은 경로 %d" % routes
	else:
		_seen_label.text = "어두운 곳은 아직 가 보지 않은 곳이에요.\n밝힌 칸 %d / 숨은 경로 %d" % [seen, routes]


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
