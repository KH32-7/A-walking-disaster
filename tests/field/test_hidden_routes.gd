extends RefCounted
## B-20 경험이 여는 길. required_trait matches a trait, an access need, an age stage or an origin
## tag of anyone in the party (fake profiles), routes start behind a gate, open when the party
## changes, stay open after that person leaves, and the gate really blocks the mall loading ramp.
## Design reference: docs/design/02-field.md "경험이 여는 길".

const MALL_LAYOUT := "res://levels/field/flooded_mall/layout.tscn"


class FakeMember extends Node3D:
	var party_id: StringName = &""
	var display_name := ""
	var party_kind: StringName = &""
	## RescueTarget keeps `profile`, FieldCompanion keeps `resident`.
	var profile: Dictionary = {}
	var resident: Dictionary = {}

	func _ready() -> void:
		add_to_group(ExtractionManager.PARTY_GROUP)


var _ok := true
var _tree: SceneTree
var _opened: Array = []
var _notes: Array[String] = []


func run() -> bool:
	_ok = true
	_tree = Engine.get_main_loop() as SceneTree
	EventBus.notification_posted.connect(_on_note)
	_test_tags()
	await _test_party_changes()
	await _test_gate_blocks()
	await _test_mall_ramp()
	EventBus.notification_posted.disconnect(_on_note)
	return _ok


# --- Pure matching ---

func _test_tags() -> void:
	var M := HiddenRouteManager
	_expect(M.matches(&"quiet_step", {"traits": [&"quiet_step", &"brave"]}), "trait id matches")
	_expect(M.matches(&"mobility", {"access_needs": [Enums.AccessNeed.MOBILITY]}), "access need mobility")
	_expect(M.matches(&"language", {"access_needs": [Enums.AccessNeed.LANGUAGE]}), "access need language")
	_expect(M.matches(&"hearing", {"access_needs": [Enums.AccessNeed.HEARING]}), "access need hearing")
	_expect(M.matches(&"care", {"access_needs": [Enums.AccessNeed.CARE]}), "access need care")
	_expect(M.matches(&"elder", {"age_stage": Enums.AgeStage.ELDER}), "age stage elder")
	_expect(M.matches(&"child", {"age_stage": Enums.AgeStage.CHILD}), "age stage child")
	_expect(not M.matches(&"elder", {"age_stage": Enums.AgeStage.ADULT}), "adult is not elder")
	_expect(M.matches(&"migrant", {"origin_tags": [&"migrant"]}), "origin tag migrant")
	_expect(M.matches(&"MOBILITY", {"access_needs": [Enums.AccessNeed.MOBILITY]}), "case does not matter (mall marker)")
	_expect(not M.matches(&"mobility", {"access_needs": [Enums.AccessNeed.LANGUAGE]}), "other need does not match")
	_expect(not M.matches(&"", {"traits": [&"brave"]}), "empty required_trait never opens")
	_expect(not M.matches(&"migrant", {}), "empty profile matches nothing")


# --- Party changes ---

func _test_party_changes() -> void:
	var root := Node3D.new()
	_tree.root.add_child(root)
	var routes := {
		&"r_ramp": _add_route(root, &"r_ramp", &"mobility", Vector3(0, 0, 0)),
		&"r_tunnel": _add_route(root, &"r_tunnel", &"elder", Vector3(20, 0, 0)),
		&"r_marks": _add_route(root, &"r_marks", &"migrant", Vector3(40, 0, 0)),
	}
	var manager := HiddenRouteManager.new()
	manager.route_opened.connect(_on_opened)
	root.add_child(manager)
	await _frames(2)
	_opened.clear()
	_notes.clear()
	for id: StringName in routes:
		_expect(manager.gate_of(id) != null and not manager.is_open(id), "%s starts closed with a gate" % id)

	var wheel := _member(root, &"p_wheel", "서하은", {"access_needs": [Enums.AccessNeed.MOBILITY]}, true)
	await _frames(2)
	_expect(manager.is_open(&"r_ramp"), "mobility in the party opens the ramp")
	_expect(manager.gate_of(&"r_ramp") == null, "the ramp gate is gone")
	_expect(not manager.is_open(&"r_tunnel") and not manager.is_open(&"r_marks"), "other routes stay closed")
	_expect(_opened.size() == 1 and _opened[0][0] == &"r_ramp" and _opened[0][3] == &"p_wheel",
			"route_opened once with the opener id")
	_expect(_notes.size() == 1 and _notes[0].begins_with("서하은"), "one notification line names the person")

	_member(root, &"c_elder", "윤기철", {"age_stage": Enums.AgeStage.ELDER}, false)
	await _frames(2)
	_expect(manager.is_open(&"r_tunnel"), "an elder companion opens the old tunnel")

	# 고립: the person leaves the party, the way stays known.
	wheel.remove_from_group(ExtractionManager.PARTY_GROUP)
	await _frames(2)
	_expect(manager.is_open(&"r_ramp"), "ramp stays open after that person is stranded")
	_expect(not manager.is_open(&"r_marks"), "migrant marks still closed")

	_member(root, &"p_child", "린", {"origin_tags": [&"migrant"], "age_stage": Enums.AgeStage.CHILD}, true)
	await _frames(2)
	_expect(manager.is_open(&"r_marks"), "a migrant origin tag opens the marks route")
	_expect(_opened.size() == 3 and _notes.size() == 3, "each route announced once")
	_expect(manager.open_routes().size() == 3, "open_routes lists all three")
	root.queue_free()
	await _frames(1)


# --- Gate collision ---

func _test_gate_blocks() -> void:
	var root := Node3D.new()
	_tree.root.add_child(root)
	_add_route(root, &"r_gate", &"hearing", Vector3.ZERO) # To is 10 m along -Z (marker scene)
	var manager := HiddenRouteManager.new()
	root.add_child(manager)
	await _frames(3)
	var hit := _ray(Vector3(0, 1, -2), Vector3(0, 1, -8))
	_expect(hit.get("collider") == manager.gate_of(&"r_gate"), "closed gate blocks the route")
	_member(root, &"p_deaf", "", {"access_needs": [Enums.AccessNeed.HEARING]}, false)
	await _frames(3)
	_expect(_ray(Vector3(0, 1, -2), Vector3(0, 1, -8)).is_empty(), "open route lets you through")
	root.queue_free()
	await _frames(1)


## The real mall ramp (layout read only): a ray 1 m above the ramp from top to foot hits the gate.
func _test_mall_ramp() -> void:
	var layout := (load(MALL_LAYOUT) as PackedScene).instantiate() as Node3D
	_tree.root.add_child(layout)
	var manager := HiddenRouteManager.new()
	layout.add_child(manager)
	await _frames(4)
	var ramp := layout.get_node_or_null(^"Mall/LoadingRamp") as CSGPolygon3D
	var route := _tree.get_nodes_in_group(HiddenRoute.GROUP)[0] as HiddenRoute
	_expect(ramp != null, "mall layout has the loading ramp")
	if ramp != null:
		var t := ramp.global_transform
		var top := t.origin - t.basis.z * ramp.depth * 0.5 + Vector3.UP * (ramp.polygon[2].y + 1.0)
		var foot := t.origin - t.basis.z * ramp.depth * 0.5 + t.basis.x * ramp.polygon[1].x + Vector3.UP
		var gate := manager.gate_of(route.id)
		_expect(gate != null and _ray(top, foot).get("collider") == gate, "gate blocks the mall loading ramp")
		var chair := _member(layout, &"p_wheel", "", {"access_needs": [Enums.AccessNeed.MOBILITY]}, true)
		await _frames(3)
		_expect(manager.is_open(route.id), "wheelchair user opens the mall ramp")
		var after := _ray(top, foot)
		_expect(after.is_empty(), "ramp is clear once open (hit %s)" % after.get("collider"))
		chair.queue_free()
	layout.queue_free()
	await _frames(1)


# --- Helpers ---

func _add_route(parent: Node, id: StringName, required: StringName, at: Vector3) -> HiddenRoute:
	var route := (load("res://field/markers/hidden_route.tscn") as PackedScene).instantiate() as HiddenRoute
	route.id = id
	route.required_trait = required
	route.position = at
	parent.add_child(route)
	return route


func _member(parent: Node, id: StringName, person_name: String, data: Dictionary, rescued: bool) -> FakeMember:
	var m := FakeMember.new()
	m.party_id = id
	m.display_name = person_name
	m.party_kind = ExtractionManager.KIND_RESCUED if rescued else ExtractionManager.KIND_COMPANION
	if rescued:
		m.profile = data
	else:
		m.resident = data
	parent.add_child(m)
	return m


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 << (Enums.LAYER_WORLD - 1))
	return _tree.root.get_world_3d().direct_space_state.intersect_ray(query)


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame
		await _tree.physics_frame


func _on_opened(route_id: StringName, from: Vector3, to: Vector3, opener_id: StringName) -> void:
	_opened.append([route_id, from, to, opener_id])


func _on_note(text: String, _severity: StringName) -> void:
	_notes.append(text)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		_ok = false
		push_error("test_hidden_routes: " + label)
