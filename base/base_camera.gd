class_name BaseCamera
extends Camera3D
## Base map camera (사용자 요청 2026-11-06): no player walking around the base. Looks straight north
## from 45° above (not the field's diagonal quarter view). WASD / arrow keys and middle-drag pan,
## the wheel zooms. Left click picks a resident or a building; `hover` tells the UI what is under
## the mouse so it can show "[클릭] 이야기하기". The pan stays inside the base's build areas.

const GROUP := &"base_camera"
const PITCH_DEG := 45.0
const FOV_DEG := 45.0
const ZOOM_DISTANCES := [18.0, 28.0, 40.0, 55.0]  # 55: one step further out (user feedback 2026-11-06)
const START_ZOOM := 1
const PAN_SPEED := 0.9  # × distance, m/s
const SHARPNESS := 10.0
const MARGIN_M := 12.0
const RAY_LENGTH := 300.0
## Hover outline (사용자 요청 2026-11-06): an inverted-hull overlay on the thing under the mouse.
const OUTLINE_COLOR := Color("f6c744")  # UiTokens.ACCENT
const OUTLINE_GROW := 0.18

var grid: BaseGrid
var build_mode: BuildMode
## Point on the ground the camera looks at.
var focus := Vector3.ZERO
## What is under the mouse: {"kind": &"resident"|&"building", "id", "text", "sub", "pos": Vector3} or {}.
## `sub` is a short second line (what the building does / site state), may be "".
var hover: Dictionary = {}

var _zoom := START_ZOOM
var _distance := 0.0
var _bounds := Rect2()
var _drag := false
var _outline: StandardMaterial3D
var _lit: Array = []  # GeometryInstance3D outlined, Label3D hidden (the tooltip says the same)
var _lit_key := ""


func _ready() -> void:
	add_to_group(GROUP)
	fov = FOV_DEG
	current = true
	_distance = ZOOM_DISTANCES[_zoom]
	_place(true)


## Frame the build areas (called by the base scene once the grid exists).
func setup(p_grid: BaseGrid, p_build_mode: BuildMode, start: Vector3) -> void:
	grid = p_grid
	build_mode = p_build_mode
	focus = Vector3(start.x, 0.0, start.z)
	var first := true
	for zone_id: StringName in grid.areas:
		var area: BuildArea = grid.areas[zone_id]
		var half := area.size_m() * 0.5
		for c in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, half.y)]:
			var w: Vector3 = area.to_global(c)
			var r := Rect2(Vector2(w.x, w.z), Vector2.ZERO)
			_bounds = r if first else _bounds.expand(Vector2(w.x, w.z))
			first = false
	_bounds = _bounds.grow(MARGIN_M)
	_place(true)


func _process(delta: float) -> void:
	if not current:
		hover = {}
		_update_outline()
		return
	var busy := not UI.stack_ids().is_empty()
	if not busy:
		var dir := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		dir += Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_up", &"ui_down"))
		if dir.length() > 1.0:
			dir = dir.normalized()
		focus += Vector3(dir.x, 0, dir.y) * PAN_SPEED * _distance * delta
	_distance = lerpf(_distance, ZOOM_DISTANCES[_zoom], 1.0 - exp(-SHARPNESS * delta))
	_place(false)
	hover = {} if busy or (build_mode != null and build_mode.active) else _pick(get_viewport().get_mouse_position())
	_update_outline()


func _place(_snap: bool) -> void:
	if _bounds.size != Vector2.ZERO:
		focus.x = clampf(focus.x, _bounds.position.x, _bounds.end.x)
		focus.z = clampf(focus.z, _bounds.position.y, _bounds.end.y)
	var back := Vector3(0, sin(deg_to_rad(PITCH_DEG)), cos(deg_to_rad(PITCH_DEG))) * _distance
	global_position = focus + back
	look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if not current or not UI.stack_ids().is_empty():
		return
	if build_mode != null and build_mode.active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxi(_zoom - 1, 0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = mini(_zoom + 1, ZOOM_DISTANCES.size() - 1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var h := _pick(mb.position)
			if not h.is_empty():
				_open(h)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag:
		var m := event as InputEventMouseMotion
		var k := _distance / get_viewport().get_visible_rect().size.y * 1.6
		focus -= Vector3(m.relative.x, 0, m.relative.y) * k


## Resident first (they stand in front of buildings), then the building on the cell under the mouse.
func _pick(screen: Vector2) -> Dictionary:
	var from := project_ray_origin(screen)
	var to := from + project_ray_normal(screen) * RAY_LENGTH
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 << (Enums.LAYER_INTERACTABLE - 1))
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.collider is ResidentAgent:
		var agent := hit.collider as ResidentAgent
		var r := Colony.get_resident(agent.resident_id)
		if not r.is_empty():
			return {"kind": &"resident", "id": agent.resident_id, "pos": agent.global_position,
				"text": "%s · 이야기하기" % String(r.get("name", "")), "sub": ""}
	if grid == null:
		return {}
	var ground = null
	var cell := {}
	for zone_id: StringName in grid.areas:  # each area at its own height (the ground is not y = 0)
		var area: BuildArea = grid.areas[zone_id]
		var at = Plane(Vector3.UP, area.global_position.y).intersects_ray(from, project_ray_normal(screen))
		if at == null:
			continue
		var c := area.world_to_cell(at)
		if area.has_cell(c):
			ground = at
			cell = {"zone_id": zone_id, "cell": c}
			break
	if cell.is_empty():
		return {}
	var uid: StringName = grid.occupied(cell["zone_id"]).get(cell["cell"], &"")
	if uid == &"":
		return {}
	var b := Colony.get_building(uid)
	var def := BaseDB.get_building(b.get("def_id", &""))
	if def == null:
		return {}
	var text := def.display_name
	var sub := def.description.get_slice("
", 0).strip_edges()
	if not b["completed"]:
		text += " · 건설 현장 %d/%d" % [int(b["progress"]), def.build_work_needed()]
		var workers := (b["workers"] as Array).size()
		sub = "일손 %d명이 짓는 중" % workers if workers > 0 else "일손을 보내야 지어져요"
	else:
		text += " Lv%d" % int(b["level"])
		if b.get("damaged", false):
			sub = "파손 · 클릭해서 수리"
	var view_pos := grid.footprint_center(cell["zone_id"], Vector2i(b["cell"][0], b["cell"][1]),
		BaseGrid.footprint(def, int(b["rotation"])))
	return {"kind": &"building", "id": uid, "pos": view_pos, "text": text, "sub": sub}


## Click: a resident opens 주민 (that person picked); a site opens its site card; a building opens
## 수리·레벨업 on it.
func _open(h: Dictionary) -> void:
	match h["kind"]:
		&"resident":
			UI.open(&"residents", {"id": h["id"]})
		&"building":
			var b := Colony.get_building(h["id"])
			UI.open(&"build", {"mode": &"site" if not b["completed"] else &"repair", "uid": h["id"]})


## Outline whatever `hover` points at; views are rebuilt on every Colony change, so the meshes are
## looked up again each frame and only re-lit when they changed.
func _update_outline() -> void:
	var node: Node = null
	if not hover.is_empty():
		match hover["kind"]:
			&"building":
				for v in get_tree().get_nodes_in_group(BuildingViews.VIEW_GROUP):
					if v.get_meta(&"building_uid", &"") == hover["id"] and not v.is_queued_for_deletion():
						node = v
						break
			&"resident":
				for a in get_tree().get_nodes_in_group(ResidentAgent.GROUP):
					if (a as ResidentAgent).resident_id == hover["id"]:
						node = a
						break
	var key := "" if node == null else str(node.get_instance_id())
	if key == _lit_key and _lit.all(func(g) -> bool: return is_instance_valid(g)):
		return
	for g in _lit:
		if not is_instance_valid(g):
			continue
		if g is Label3D:
			g.visible = true
		else:
			g.material_overlay = null
	_lit.clear()
	_lit_key = key
	if node == null:
		return
	if _outline == null:
		# Stencil outline (4.5+): an invisible overlay marks the mesh, its outline pass draws around it,
		# so boxes and models get one clean silhouette line instead of split, inflated faces.
		_outline = StandardMaterial3D.new()
		_outline.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline.albedo_color = Color(1, 1, 1, 0)
		_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
		_outline.stencil_color = OUTLINE_COLOR
		_outline.stencil_outline_thickness = OUTLINE_GROW
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		if g is Label3D:
			g.visible = false
		elif g is Sprite3D:
			continue
		else:
			(g as GeometryInstance3D).material_overlay = _outline
		_lit.append(g)
