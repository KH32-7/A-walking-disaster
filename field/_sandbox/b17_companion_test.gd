extends Node3D
## B-17 sandbox: the real player with two companion residents on the field sandbox.
## 한만석 (pistol, 총 적성 상, so he uses Q) and 오정희 (club, wheelchair user: nav layer 2 only,
## so she takes the ramp, never the stairs). An injured elder waits on the street for 엄호.
## Nav meshes are baked here at start: layer 1 = everything, layer 2 = everything but the stairs.
##
## Run alone (F6). Headless (or P) runs a scripted demo and prints PASS / FAIL, then quits headless.
## Keys: V tap = rescued person hide / follow, V hold = companion mode (공격적 / 신중 / 엄호),
##   F interact (help a downed companion up: 3 s), sandbox-only raw keys: M spawn a monster ahead,
##   H hurt the nearest companion, K knock the nearest companion down, G first aid kit, P demo.

const HURT_DAMAGE := 25.0
const STEP_TIMEOUT := 20.0
const MONSTER_DEF := preload("res://data/monsters/swamp_blob.tres")
const WHEELCHAIR_NAV_GROUP := &"b17_nav_wheelchair"
const MONSTER_AHEAD := 7.0

var _failures := 0
var _demo_running := false
var _last_event := "-"
var _labels := {}

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $FieldSandbox/Camera3D
@onready var _companions: CompanionManager = $CompanionManager
@onready var _rescue: RescueManager = $RescueManager
@onready var _label: Label = $DebugLayer/InfoLabel

var _camera_offset := Vector3.ZERO


func _ready() -> void:
	_camera_offset = _camera.global_position - _player.global_position
	# Before CompanionManager's deferred spawn: the loadout's companions (B-11 FieldState).
	FieldState.companions.assign([_make_resident("한만석", &"pistol", {"gun": Enums.Aptitude.HIGH}, []),
		_make_resident("오정희", &"club", {"blunt": Enums.Aptitude.MID}, [Enums.AccessNeed.MOBILITY])])
	_bake_navigation()
	_companions.companion_spawned.connect(_on_companion_spawned)
	_companions.mode_changed.connect(func(mode: FieldCompanion.Mode) -> void:
		_last_event = "mode %s" % FieldCompanion.MODE_LABELS[mode])
	EventBus.monster_killed.connect(func(id: StringName, _e: Enums.Element, _p: Vector3) -> void:
		_last_event = "killed %s" % id)
	EventBus.companion_stranded.connect(func(id: StringName, _r: StringName) -> void:
		_last_event = "stranded %s" % id)
	if DisplayServer.get_name() == "headless":
		_run_demo.call_deferred()


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + _camera_offset
	var lines := PackedStringArray(["Event: %s" % _last_event, "Mode: %s" % FieldCompanion.MODE_LABELS[_companions.mode]])
	for c in _alive():
		var extra := ""
		if c.state == FieldCompanion.State.DOWNED:
			extra = "  down %.0f s" % c.down_time_left()
		elif c.target != null:
			extra = "  fighting"
		lines.append("%s: %s  hp %.0f/%.0f  Q %.1f s%s" % [c.display_name, FieldCompanion.State.keys()[c.state],
			c.health, c.max_health, c.skill_time_left(), extra])
		_labels[c].text = "%s\n%s" % [c.display_name, c.hud_entry()["command"]]
	lines.append("HUD companions: %s" % [_player.hud_state().get("companions", [])])
	lines.append("V tap hide/follow, V hold mode, F help up, M monster, H hurt, K down, G kit, P demo")
	_label.text = "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_M:
			_spawn_monster(_player.global_position + _player.facing() * MONSTER_AHEAD)
		KEY_H:
			var c := _nearest()
			if c:
				c.take_damage(HURT_DAMAGE)
		KEY_K:
			var c := _nearest()
			if c:
				c.take_damage(c.health)
		KEY_G:
			Bag.try_add(&"first_aid_kit", 1)
		KEY_P:
			if not _demo_running:
				_run_demo()


# --- Scripted demo -------------------------------------------------------------

func _run_demo() -> void:
	_demo_running = true
	# The monsters would wear the player down during the demo. Debug builds only.
	DebugConsole.godmode = true
	await get_tree().create_timer(0.5).timeout
	var list := _alive()
	_expect(list.size() == 2, "two companions spawned from the loadout")
	if list.size() < 2:
		_finish()
		return
	var gunner: FieldCompanion = list[0]
	var chair: FieldCompanion = list[1]
	_expect(gunner.global_position.distance_to(_player.global_position) < 3.0, "spawned beside the player")
	_expect(chair.navigation_layers() == FieldCompanion.NAV_NO_STAIRS, "wheelchair user: no stairs")

	print("1. 공격적: a monster ahead gets shot")
	var first := _spawn_monster(_player.global_position + Vector3(4.0, 0.0, -4.0)).get_instance_id()
	_expect(await _wait(func() -> bool: return not is_instance_id_valid(first)), "companions killed the monster")
	_expect(gunner.skill_time_left() > 0.0, "gunner (적성 상) used Q")

	print("2. 신중: only what the player hit")
	_companions.cycle_mode()
	_expect(gunner.mode == FieldCompanion.Mode.CAUTIOUS, "hold V: 신중")
	var second := _spawn_monster(_player.global_position + Vector3(-4.0, 0.0, -4.0))
	second.set_physics_process(false)  # stays put, does not start the fight itself
	await get_tree().create_timer(2.0).timeout
	_expect(is_instance_valid(second) and second.hp == second.max_hp, "untouched for 2 s")
	(_player.get_node(^"Weapons") as WeaponHolder).hit_landed.emit(second, 0.0, {})
	var second_id := second.get_instance_id()
	_expect(await _wait(func() -> bool: return not is_instance_id_valid(second_id)), "player marked it: killed")

	print("3. Down and help up (F, 3 s)")
	gunner.take_damage(gunner.health)
	_expect(gunner.state == FieldCompanion.State.DOWNED, "gunner down")
	_expect(_player.hud_state()["companions"].any(func(e: Dictionary) -> bool:
		return e["command"] == FieldCompanion.DOWNED_LABEL), "HUD shows 쓰러짐")
	_player.global_position = gunner.global_position + Vector3(0.8, 0.1, 0.0)
	_player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	_expect(_player.interact(), "F starts helping")
	_expect(await _wait(func() -> bool: return gunner.state == FieldCompanion.State.ACTIVE), "back up after 3 s")

	print("4. Not helped in time: stranded")
	chair.take_damage(chair.health)
	chair._down_left = 0.5  # sandbox shortcut for the 30 s wait
	_expect(await _wait(func() -> bool: return chair.state == FieldCompanion.State.STRANDED), "stranded")
	_expect(not FieldState.companions.has(chair.party_id), "left FieldState.companions")
	_finish()


func _finish() -> void:
	print("B17 DEMO %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	_demo_running = false
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failures > 0 else 0)


func _wait(cond: Callable) -> bool:
	var left := STEP_TIMEOUT
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().physics_frame
		left -= get_physics_process_delta_time()
	return false


func _expect(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


# --- Helpers -------------------------------------------------------------------

func _make_resident(rname: String, weapon: StringName, aptitude: Dictionary, needs: Array) -> StringName:
	var id := Colony.add_resident({"name": rname, "class_aptitude": aptitude, "access_needs": needs,
		"traits": [&"brave"], "stats": {"str": 5, "sense": 6}})
	Armory.equip(id, Enums.EquipSlot.MAIN, Armory.create_item(weapon, Enums.Rarity.COMMON))
	return id


func _spawn_monster(at: Vector3) -> Monster:
	var m: Monster = MONSTER_DEF.scene.instantiate()
	m.def = MONSTER_DEF
	add_child(m)
	m.global_position = Vector3(at.x, 0.0, at.z)
	return m


func _alive() -> Array[FieldCompanion]:
	var list: Array[FieldCompanion] = []
	for c in _companions.companions:
		if is_instance_valid(c):
			list.append(c)
	return list


func _nearest() -> FieldCompanion:
	var best: FieldCompanion = null
	for c in _alive():
		if c.state == FieldCompanion.State.ACTIVE and (best == null
				or c.global_position.distance_to(_player.global_position) < best.global_position.distance_to(_player.global_position)):
			best = c
	return best


func _on_companion_spawned(c: FieldCompanion) -> void:
	var label := Label3D.new()
	label.position.y = 2.2
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	c.add_child(label)
	_labels[c] = label


## CSG builds its meshes after _ready, so bake one frame later. Layer 2 only takes the nodes in
## WHEELCHAIR_NAV_GROUP (no stairs). Same as the B-10 sandbox.
func _bake_navigation() -> void:
	await get_tree().process_frame
	var geo := $FieldSandbox/Geometry
	for path in ["Floor", "Walls", "Cover", "Access/Deck", "Access/Ramp"]:
		geo.get_node(path).add_to_group(WHEELCHAIR_NAV_GROUP)
	_bake_region(0b01, geo, &"")
	_bake_region(0b10, geo, WHEELCHAIR_NAV_GROUP)


func _bake_region(layers: int, root: Node3D, group: StringName) -> void:
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1 << (Enums.LAYER_WORLD - 1)
	if group != &"":
		navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		navmesh.geometry_source_group_name = group
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, root)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	var region := NavigationRegion3D.new()
	region.name = "NavLayer%d" % layers
	region.navigation_layers = layers
	region.navigation_mesh = navmesh
	root.add_child(region)
