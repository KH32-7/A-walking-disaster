class_name HiddenRouteManager
extends Node
## 경험이 여는 길 (B-20). Put one in each region assembly scene (next to RescueManager).
##
## - Every HiddenRoute marker (HiddenRoute.GROUP) starts closed: a gate (StaticBody3D, world layer)
##   stands across the route. At the marker's child "Gate" (Node3D) if it has one, else halfway
##   between From and To, turned across the From -> To direction.
## - Whenever the party (group ExtractionManager.PARTY_GROUP: rescued people following, companions)
##   changes, every closed route is checked again. A route opens when anyone in the party matches
##   its required_trait (see profile_tags()). Opened routes stay open for the rest of the sortie,
##   even if that person is later stranded (the way is known, and nobody gets shut in on it).
## - Opening: the gate is freed, route_opened is emitted, and one notification line is posted.
## Lane D: find this node in GROUP. route_opened / open_routes() for the map and world marks.
## Design reference: docs/design/02-field.md "경험이 여는 길", 07-residents.md "참여 조건".

## from / to = HiddenRoute.from_point() / to_point(). opener_id = party_id of the person.
signal route_opened(route_id: StringName, from: Vector3, to: Vector3, opener_id: StringName)

const GROUP := &"field_hidden_route_manager"
## One line when a route opens (02: 지도에 나타납니다). %s = the person's name.
const OPENED_TEXT := "%s 덕분에 숨은 길이 지도에 표시됐다"

@export_group("Gate (가안)")
## Across the route (m). Mall loading ramp is 3.5 m wide with a 4 m gap in the deck parapet.
@export var gate_width := 4.5
@export var gate_thickness := 0.4
@export var gate_height := 4.0
## How far the gate reaches below the gate point (a ramp's surface can sit above or below it).
@export var gate_below := 1.5

## route id -> gate StaticBody3D, while closed.
var _gates := {}
## route id -> HiddenRoute, opened this sortie.
var _open := {}
var _party_key := ""


func _ready() -> void:
	add_to_group(GROUP)
	# Deferred: the layout (and its markers) may come after this node in the assembly scene.
	_build_gates.call_deferred()


func _physics_process(_delta: float) -> void:
	var key := _current_party_key()
	if key != _party_key:
		_party_key = key
		refresh()


## Checks every closed route against the party now. Returns the ids opened by this call.
func refresh() -> Array[StringName]:
	var opened: Array[StringName] = []
	var party := _party()
	for route in _routes():
		if _open.has(route.id):
			continue
		for person in party:
			if matches(route.required_trait, _profile_of(person)):
				_open_route(route, person)
				opened.append(route.id)
				break
	return opened


func is_open(route_id: StringName) -> bool:
	return _open.has(route_id)


## Opened routes for the map: [{id, required_trait, from, to}].
func open_routes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _open:
		var route: HiddenRoute = _open[id]
		if is_instance_valid(route):
			out.append({"id": id, "required_trait": route.required_trait,
					"from": route.from_point(), "to": route.to_point()})
	return out


## The gate blocking this route, or null once open (tests, D dressing).
func gate_of(route_id: StringName) -> StaticBody3D:
	return _gates.get(route_id) as StaticBody3D


## Lowercase tags a person brings to hidden routes:
## traits as their TraitDef id, access_needs / age_stage as the lowercase Enums key,
## origin_tags as written (not in the profile yet, Lane A / C).
static func profile_tags(profile: Dictionary) -> Array[StringName]:
	var tags: Array[StringName] = []
	for id in profile.get("traits", []):
		tags.append(StringName(str(id).to_lower()))
	for need in profile.get("access_needs", []):
		var key = Enums.AccessNeed.find_key(int(need))
		if key != null:
			tags.append(StringName(str(key).to_lower()))
	if profile.has("age_stage"):
		var key = Enums.AgeStage.find_key(int(profile["age_stage"]))
		if key != null:
			tags.append(StringName(str(key).to_lower()))
	for tag in profile.get("origin_tags", []):
		tags.append(StringName(str(tag).to_lower()))
	return tags


## True when the person's profile has the route's required_trait (case does not matter).
static func matches(required_trait: StringName, profile: Dictionary) -> bool:
	if required_trait == &"":
		return false
	return StringName(str(required_trait).to_lower()) in profile_tags(profile)


func _open_route(route: HiddenRoute, person: Node) -> void:
	_open[route.id] = route
	var gate := gate_of(route.id)
	if gate != null:
		gate.queue_free()
	_gates.erase(route.id)
	var opener_id: StringName = person.get(&"party_id")
	route_opened.emit(route.id, route.from_point(), route.to_point(), opener_id)
	var who := str(person.get(&"display_name"))
	EventBus.notification_posted.emit(OPENED_TEXT % (who if who != "" else str(opener_id)), &"info")


func _build_gates() -> void:
	for route in _routes():
		if _open.has(route.id) or _gates.has(route.id):
			continue
		var gate := _make_gate(route)
		add_child(gate)
		gate.global_transform = _gate_transform(route)
		_gates[route.id] = gate
	# A party that was already there (companions spawn deferred too) is checked next physics frame.
	_party_key = ""


func _make_gate(route: HiddenRoute) -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.name = "Gate_%s" % route.id
	gate.collision_layer = 0
	gate.collision_mask = 0
	gate.set_collision_layer_value(Enums.LAYER_WORLD, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(gate_width, gate_height, gate_thickness)
	shape.shape = box
	shape.position = Vector3(0.0, gate_height * 0.5 - gate_below, 0.0)
	gate.add_child(shape)
	return gate


## Local Z along the route (From -> To, flat), so the box's width (X) lies across it.
func _gate_transform(route: HiddenRoute) -> Transform3D:
	var custom := route.get_node_or_null(^"Gate") as Node3D
	if custom != null:
		return custom.global_transform
	var from := route.from_point()
	var to := route.to_point()
	var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var point := (from + to) * 0.5
	if along.length() < 0.01:
		return Transform3D(Basis.IDENTITY, point)
	var z := along.normalized()
	return Transform3D(Basis(Vector3.UP.cross(z), Vector3.UP, z), point)


func _routes() -> Array[HiddenRoute]:
	var out: Array[HiddenRoute] = []
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(HiddenRoute.GROUP):
		if node is HiddenRoute and node.id != &"":
			out.append(node)
	return out


func _party() -> Array[Node]:
	return get_tree().get_nodes_in_group(ExtractionManager.PARTY_GROUP) if is_inside_tree() else []


## Rescued people keep `profile`, companions keep `resident` (Colony.get_resident copy).
static func _profile_of(person: Node) -> Dictionary:
	for key: StringName in [&"profile", &"resident"]:
		var value = person.get(key)
		if value is Dictionary and not value.is_empty():
			return value
	return {}


func _current_party_key() -> String:
	var ids := PackedStringArray()
	for person in _party():
		ids.append(str(person.get(&"party_id")))
	ids.sort()
	return ",".join(ids)
