extends Node3D
## B-23 sandbox: B's field combat parts on Lane C's base layout (instanced, never saved here).
## Player with field_rules = false, FieldCamera, a guard companion at a post, two base residents,
## fake raid structures (a gate in the south opening, a wall in the park opening) and raid waves
## from the layout's RaidSpawnPoints, marching to its GatherPoint.
## What is real and what is not: the structures and residents are sandbox stand-ins
## (b23_fake_structure.gd, b23_fake_resident.gd). Lane C's own nodes replace them in C-17 / C-18.
##
## Run alone (F6). Raw keys: 1 = raid wave at every spawn point, 2 = root crusher + debris ram at
## the south point, K = knock the player down (bag and FieldState must stay as they were).
## Headless: a short scripted run that prints PASS / FAIL, then quits.

const GUARD_ID := &"b23_sandbox_guard"
const WAVE := [
	preload("res://data/monsters/vine_tendril.tres"),
	preload("res://data/monsters/vine_tendril.tres"),
	preload("res://data/monsters/rubble_bug.tres"),
]
const CRUSHER := preload("res://data/monsters/root_crusher.tres")
const RAM := preload("res://data/monsters/debris_ram.tres")
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const STRUCTURE_SCRIPT := preload("res://field/_sandbox/b23_fake_structure.gd")
const RESIDENT_SCRIPT := preload("res://field/_sandbox/b23_fake_resident.gd")
## Openings in the base map forest edge (layout Navigation/ForestEdge: south trail gap, west gap).
const SOUTH_GATE := Vector3(8.0, 1.5, 26.0)
const PARK_WALL := Vector3(-58.0, 1.5, -4.0)
const DEMO_TIMEOUT := 60.0

var _events: PackedStringArray = []
var _guard_weapon: StringName = &""
var _failures := 0

@onready var _layout: Node3D = $Layout
@onready var _player: Player = $Player
@onready var _raiders: Node3D = $Raiders
@onready var _label: Label = $DebugLayer/InfoLabel


func _ready() -> void:
	_player.field_rules = false
	_player.downed.connect(func() -> void: _log("player down (Player.downed only)"))
	EventBus.player_downed.connect(func() -> void: _log("EventBus.player_downed (should not happen)"))
	EventBus.companion_stranded.connect(func(id: StringName, _r: StringName) -> void:
		_log("companion_stranded %s (should not happen)" % id))
	EventBus.monster_killed.connect(func(id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		_log("killed %s" % id))
	_place_player()
	_add_structure(SOUTH_GATE, Vector3(10.0, 3.0, 1.0), true)
	_add_structure(PARK_WALL, Vector3(1.0, 3.0, 10.0), false)
	var gather := _gather_point()
	for offset in [Vector3(-2.0, 0.0, 1.0), Vector3(2.0, 0.0, 1.0)]:
		var resident: CharacterBody3D = RESIDENT_SCRIPT.new()
		resident.position = gather + offset
		resident.down.connect(func() -> void: _log("resident down"))
		add_child(resident)
	_add_guard(gather + Vector3(2.0, 0.0, 4.0))
	if DisplayServer.get_name() == "headless":
		_run_demo.call_deferred()


func _exit_tree() -> void:
	if _guard_weapon != &"":
		Armory.remove_item(_guard_weapon)


func _process(_delta: float) -> void:
	var lines := PackedStringArray(["Raiders: %d   Player hp %.0f%s" % [_raiders.get_child_count(),
		_player.health, "  (down)" if _player.is_downed else ""]])
	lines.append("1 wave  2 siege  K player down")
	for i in range(maxi(0, _events.size() - 8), _events.size()):
		lines.append(_events[i])
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			spawn_wave()
		KEY_2:
			spawn_siege()
		KEY_K:
			_player.take_damage(_player.health + 1.0)


## One wave of field monsters at every RaidSpawnPoint.
func spawn_wave() -> void:
	for point in _raid_points():
		for def: MonsterDef in WAVE:
			spawn_raider(def, point)
	_log("wave from %d points" % _raid_points().size())


func spawn_siege() -> void:
	for point in _raid_points():
		if point.direction_id() == &"south":
			spawn_raider(CRUSHER, point)
			spawn_raider(RAM, point)
	_log("siege at south")


## What Lane C does per raider: def, raid_goal, no field drops, position, add.
func spawn_raider(def: MonsterDef, point: RaidSpawnPoint) -> Monster:
	var m := def.scene.instantiate() as Monster
	m.def = def
	m.raid_goal = _gather_point()
	m.drop_mult = 0.0
	var angle := randf() * TAU
	m.position = point.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf() * point.spread_radius
	m.attack_landed.connect(func(target: Node3D, _info: Dictionary) -> void:
		if RaidMarch.structure_of(target) != null:
			_log("%s hits %s" % [def.id, target.name]))
	_raiders.add_child(m, true)
	return m


func _add_structure(pos: Vector3, size: Vector3, gate: bool) -> Node3D:
	var s: StaticBody3D = STRUCTURE_SCRIPT.new()
	s.name = "FakeGate" if gate else "FakeWall"
	s.set(&"is_gate", gate)
	s.set(&"size", size)
	s.set(&"durability", 300.0 if gate else 100.0)
	s.position = pos
	s.connect(&"broken", func(node: Node3D) -> void: _log("%s broken" % node.name))
	add_child(s)
	return s


func _add_guard(post_pos: Vector3) -> void:
	var post := Marker3D.new()
	post.name = "GuardPost"
	post.position = post_pos
	add_child(post)
	_guard_weapon = Armory.create_item(&"pistol", Enums.Rarity.COMMON)
	Armory.equip(GUARD_ID, Enums.EquipSlot.MAIN, _guard_weapon)
	var guard: FieldCompanion = COMPANION_SCENE.instantiate()
	guard.setup(GUARD_ID, {"name": "경비", "stats": {&"str": 5, &"dex": 5, &"sense": 5}})
	guard.field_rules = false
	guard.guard_post = post
	guard.position = post_pos
	guard.downed.connect(func() -> void: _log("guard down (stays down, not stranded)"))
	add_child(guard)


func _place_player() -> void:
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is PlayerSpawn:
			_player.global_position = (node as Node3D).global_position
			return


func _gather_point() -> Vector3:
	var gather := _layout.get_node_or_null(^"GatherPoint") as Node3D
	return gather.global_position if gather else Vector3.ZERO


func _raid_points() -> Array[RaidSpawnPoint]:
	var points: Array[RaidSpawnPoint] = []
	for node in get_tree().get_nodes_in_group(RaidSpawnPoint.MARKER_GROUP):
		if node is RaidSpawnPoint:
			points.append(node)
	return points


func _log(text: String) -> void:
	_events.append(text)
	print("[b23] ", text)


# --- Headless demo --------------------------------------------------------

func _run_demo() -> void:
	if not _layout.get(&"navigation_baked"):
		await _layout.navigation_ready
	var field_before := FieldState.save_data()
	var bag_before := Bag.save_data()
	# A crusher right outside the park wall: it must path to it and break it (x3 on walls).
	var points := _raid_points()
	var crusher := spawn_raider(CRUSHER, points[0])
	crusher.global_position = PARK_WALL + Vector3(-3.0, -1.5, 0.0)
	crusher.raid_goal = PARK_WALL + Vector3(6.0, -1.5, 0.0)
	var t := 0.0
	while get_node_or_null(^"FakeWall") != null and t < DEMO_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_expect(get_node_or_null(^"FakeWall") == null, "root crusher broke the park wall")
	# A field monster from the east point has no opening on its side: it must follow the navmesh
	# round to the south opening, break the gate and get inside the school wall.
	var east: RaidSpawnPoint = null
	for point in points:
		if point.direction_id() == &"east":
			east = point
	var vine := spawn_raider(WAVE[0], east)
	var last := vine.global_position
	t = 0.0
	while is_instance_valid(vine) and not _inside_wall(last) and t < DEMO_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(vine):
			last = vine.global_position
	_expect(_inside_wall(last), "a raider from the east point walked the navmesh into the base")
	_player.take_damage(_player.health + 1.0)
	await get_tree().process_frame
	_expect(_player.is_downed, "player is down")
	_expect(FieldState.save_data() == field_before, "FieldState unchanged after the base player went down")
	_expect(Bag.save_data() == bag_before, "bag unchanged after the base player went down")
	print("b23_defense_test: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Inside the forest edge: north of the south opening, east of the west opening.
func _inside_wall(pos: Vector3) -> bool:
	return pos.z < SOUTH_GATE.z - 1.0 and pos.x > PARK_WALL.x + 1.0


func _expect(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		push_error("b23_defense_test: " + what)
