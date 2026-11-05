class_name DefenseBattle
extends Node3D
## 직접 방어전 (C-17, docs/design/10-raids-defense.md "직접 방어전"). The base scene adds one when
## Colony.defense_requested fires. It uses Lane B's combat parts the way field/README.md (B-23) says:
## raiders are MonsterDef scenes with raid_goal and no drops, guards are FieldCompanion with
## field_rules = false at a post, facilities are RaidStructure bodies, residents are ResidentAgent
## bodies on layer 3. Lane D's HUD (D-14) reads the signals and calls skip_to_auto() / move_guard() /
## reinstall_traps().
##
## 3파, 파 사이 20초 준비. 승리: 모든 파 처치 또는 5분 버팀 (남은 마물은 물러남).
## 패배: 대피소 문이 부서지거나 플레이어와 경비가 모두 쓰러짐. 결과는 Colony.finish_direct_defense().

signal prep_started(next_wave: int, seconds: float)
signal wave_started(wave: int, total: int, count: int)
signal finished(result: Dictionary)

const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const STRUCTURE_HEIGHT := 2.6

enum State { IDLE, PREP, WAVE, DONE }

var state := State.IDLE
var raid: Dictionary = {}
var first_wave := 1
## Current wave (1-based); first_wave - 1 before the first one starts.
var wave := 0
var waves: Array = []
var prep_left := 0.0
var elapsed := 0.0
## Raiders still alive in this wave.
var alive: Array = []
var broken: Array = []
var hurt: Array = []
## (def: MonsterDef, position: Vector3, goal: Vector3) -> Node3D with signal died(monster).
## Tests swap it for stand-ins; the default instantiates the monster scene (B-23).
var raider_factory: Callable

var _layout: Node3D
var _player: Node
var _crowd: ResidentCrowd
var _views: Node3D
var _guards := {}         # resident_id -> FieldCompanion
var _posts := {}          # post name -> Marker3D
var _structures := {}     # building uid -> RaidStructure
var _rng := RandomNumberGenerator.new()


func setup(p_raid: Dictionary, p_first_wave: int, layout: Node3D = null, player: Node = null,
		crowd: ResidentCrowd = null, views: Node3D = null) -> void:
	raid = p_raid
	first_wave = clampi(p_first_wave, 1, DefenseRules.WAVES)
	_layout = layout
	_player = player
	_crowd = crowd
	_views = views
	_rng.seed = hash(String(raid.get("raid_id", "")))


## Composes the waves, puts up facilities, posts the guards, moves the residents, starts the first prep.
func start() -> void:
	waves = DefenseRules.compose_waves(raid, _rng)
	wave = first_wave - 1
	if _views != null and _views.has_method(&"refresh"):
		_views.call(&"refresh")  # views are built a frame late after loading; posts need them now
	_make_posts()
	_spawn_structures()
	_spawn_guards()
	_place_residents(true)
	_begin_prep()


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if state == State.DONE or state == State.IDLE:
		return
	elapsed += delta
	if _lost():
		_finish(false)
		return
	if elapsed >= DefenseRules.SURVIVE_SEC:
		_finish(true)
		return
	match state:
		State.PREP:
			prep_left -= delta
			if prep_left <= 0.0:
				_start_wave()
		State.WAVE:
			alive = alive.filter(func(m): return is_instance_valid(m))
			if alive.is_empty():
				if wave >= DefenseRules.WAVES:
					_finish(true)
				else:
					_begin_prep()


## 자동 판정으로 넘기기 (+20%).
func skip_to_auto() -> Dictionary:
	if state == State.DONE:
		return {}
	state = State.DONE
	_cleanup()
	var result := Colony.skip_direct_defense()
	finished.emit(result)
	queue_free()
	return result


## Names of the places a guard can stand (초소·문·대피소 앞, 모임터).
func post_names() -> Array:
	return _posts.keys()


## Moves a guard to another post (D: drag between waves).
func move_guard(resident_id: StringName, post_name: StringName) -> bool:
	if not _guards.has(resident_id) or not _posts.has(post_name):
		return false
	_guards[resident_id].set(&"guard_post", _posts[post_name])
	return true


## 함정 재설치 during the prep: every used-up trap that can be paid for. Returns how many.
func reinstall_traps() -> int:
	if state != State.PREP:
		return 0
	var n := 0
	for uid in Colony.building_ids(&"spike_trap", true):
		if Colony.reinstall_trap(uid):
			n += 1
	return n


func guard_ids() -> Array:
	return _guards.keys()


# --- Flow ---------------------------------------------------------------------

func _begin_prep() -> void:
	state = State.PREP
	prep_left = DefenseRules.PREP_SEC
	prep_started.emit(wave + 1, DefenseRules.PREP_SEC)


func _start_wave() -> void:
	wave += 1
	state = State.WAVE
	var defs: Array = waves[wave - 1] if wave - 1 < waves.size() else []
	var points := _spawn_points()
	var goal := _goal()
	for i in defs.size():
		var p: Vector3 = points[i % points.size()] if not points.is_empty() else goal + Vector3(20.0, 0.0, 0.0)
		var angle := _rng.randf() * TAU
		var m := _make_raider(defs[i], p + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(0.0, 3.0), goal)
		if m != null:
			alive.append(m)
	wave_started.emit(wave, DefenseRules.WAVES, alive.size())


func _make_raider(def: MonsterDef, pos: Vector3, goal: Vector3) -> Node3D:
	var m: Node3D
	if raider_factory.is_valid():
		m = raider_factory.call(def, pos, goal)
	else:
		m = def.scene.instantiate() as Node3D
		m.set(&"def", def)
		m.set(&"raid_goal", goal)
		m.set(&"drop_mult", 0.0)
		m.position = pos
	if m == null:
		return null
	if m.has_signal(&"died"):
		m.connect(&"died", _on_raider_died)
	if m.get_parent() == null:
		add_child(m)
	return m


func _on_raider_died(monster: Variant) -> void:
	alive.erase(monster)


func _lost() -> bool:
	if broken.any(func(uid): return Colony.get_building(uid).get("def_id", &"") == DefenseRules.SHELTER):
		return true  # 대피소 문이 부서짐
	var player_down: bool = _player != null and bool(_player.get(&"is_downed"))
	if _player == null and _guards.is_empty():
		return false
	if not player_down and _player != null:
		return false
	for id in _guards:
		if not _guard_down(_guards[id]):
			return false
	return true


func _guard_down(guard: Node) -> bool:
	return not is_instance_valid(guard) or int(guard.get(&"state")) == FieldCompanion.State.DOWNED


func _finish(won: bool) -> void:
	state = State.DONE
	var guards_down: Array = []
	for id in _guards:
		if _guard_down(_guards[id]):
			guards_down.append(id)
	_cleanup()
	var result := Colony.finish_direct_defense({"won": won, "broken": broken.duplicate(), "guards_down": guards_down,
		"hurt": hurt.duplicate()})
	finished.emit(result)
	queue_free()


## Raiders retreat, guards go back to their base bodies, facilities stop being targets.
func _cleanup() -> void:
	for m in alive:
		if is_instance_valid(m):
			m.queue_free()
	alive.clear()
	for id in _guards:
		if is_instance_valid(_guards[id]):
			_guards[id].queue_free()
	for uid in _structures:
		if is_instance_valid(_structures[uid]):
			_structures[uid].queue_free()
	_place_residents(false)


# --- Setup of the map ---------------------------------------------------------

func _make_posts() -> void:
	var gather := Marker3D.new()
	gather.name = "Post_gather"
	add_child(gather)
	gather.global_position = _gather_point()
	_posts[&"gather"] = gather
	for view in _building_views():
		var def_id: StringName = view.get_meta(&"def_id", &"")
		if def_id in DefenseRules.POST_BUILDINGS:
			var post := Marker3D.new()
			post.name = "Post_%s" % view.get_meta(&"building_uid")
			add_child(post)
			post.global_position = view.global_position
			_posts[StringName(post.name)] = post


func _spawn_structures() -> void:
	for view in _building_views():
		var uid: StringName = view.get_meta(&"building_uid", &"")
		var b := Colony.get_building(uid)
		var def := BaseDB.get_building(b.get("def_id", &""))
		if def == null or not b.get("completed", false) or b.get("damaged", false):
			continue
		if not (def.id in DefenseRules.WALLS or def.id in DefenseRules.GATES or def.id == DefenseRules.SHELTER):
			continue
		var cells := BaseGrid.footprint(def, int(b["rotation"]))
		var s := RaidStructure.create(uid, def.id, Vector2(cells.x, cells.y) * ColonyMarker.CELL_SIZE, STRUCTURE_HEIGHT)
		s.broken.connect(func(gone: StringName) -> void: broken.append(gone))
		add_child(s)
		s.global_position = view.global_position
		_structures[uid] = s


func _spawn_guards() -> void:
	var post_list := _posts.values().filter(func(p): return String(p.name) != "Post_gather")
	var i := 0
	for id in Colony.active_resident_ids():
		if Colony.job_of(id) != &"guard" or not WorkRules.can_work(Colony.get_resident(id)):
			continue
		var post: Marker3D = post_list[i % post_list.size()] if not post_list.is_empty() else _posts[&"gather"]
		i += 1
		var guard := COMPANION_SCENE.instantiate() as FieldCompanion
		guard.setup(id, Colony.get_resident(id))
		guard.field_rules = false
		guard.guard_post = post
		add_child(guard)
		guard.global_position = post.global_position
		_guards[id] = guard


## Battle on: guards' base bodies step aside; residents who can reach the shelter go in (out of
## reach), the others stay targets and report hits. Battle off: everyone back to normal.
func _place_residents(battle: bool) -> void:
	if _crowd == null:
		return
	var sheltered := Colony.has_completed(RaidRules.SHELTER) and RaidRules.ALARMS.any(func(a): return Colony.has_completed(a))
	for id in Colony.active_resident_ids():
		var agent := _crowd.agent(id)
		if agent == null:
			continue
		if not battle:
			agent.visible = true
			agent.set_reachable(true)
			if agent.hurt.is_connected(_on_resident_hurt):
				agent.hurt.disconnect(_on_resident_hurt)
			continue
		if _guards.has(id):
			agent.visible = false
			agent.set_reachable(false)
			continue
		var hears: bool = Colony.hearing_alarm() or not Enums.AccessNeed.HEARING in Colony.get_resident(id)["access_needs"]
		agent.set_reachable(not (sheltered and hears))
		if not agent.hurt.is_connected(_on_resident_hurt):
			agent.hurt.connect(_on_resident_hurt)


func _on_resident_hurt(resident_id: StringName) -> void:
	if not resident_id in hurt:
		hurt.append(resident_id)


func _building_views() -> Array:
	if _views == null:
		return []
	return _views.get_children().filter(func(n): return n.is_in_group(BuildingViews.VIEW_GROUP) and not n.is_queued_for_deletion())


func _spawn_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var all: Array[Vector3] = []
	if _layout == null:
		return out
	var dirs: Array = raid.get("directions", [])
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is RaidSpawnPoint:
			all.append((node as Node3D).global_position)
			if (node as RaidSpawnPoint).direction_id() in dirs:
				out.append((node as Node3D).global_position)
	return out if not out.is_empty() else all


## 행진 목표: 대피소 앞, 없으면 모임터.
func _goal() -> Vector3:
	for view in _building_views():
		if view.get_meta(&"def_id", &"") == DefenseRules.SHELTER:
			return view.global_position
	return _gather_point()


func _gather_point() -> Vector3:
	var gather := _layout.get_node_or_null(^"GatherPoint") as Node3D if _layout != null else null
	return gather.global_position if gather != null else global_position
