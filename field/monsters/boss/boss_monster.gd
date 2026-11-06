class_name BossMonster
extends Monster
## A boss on top of the common monster AI (B-19). Root script of boss scenes; BossSpawner puts it
## at a BossArena. Adds: phases by hp ratio, telegraphed area patterns and summons (BossDef),
## the arena leash, out-of-combat recovery, first-kill reward and the respawn day.
## Rules (drafts):
## - Arena: the boss never goes farther than arena_radius from the arena center. Past it, it walks
##   home (Monster RETURN: ignores hits and noise, heals MonsterRules.RETURN_REGEN_RATIO per second).
## - Out of combat (asleep or wandering) it heals boss.regen_ratio per second. At full hp the fight
##   resets: phase 1, cooldowns cleared, its summons vanish.
## - Phases only go up during a fight (healing above 50% does not undo phase 2).
## - Every attack is a pattern with a 1 s ground warning; there is no plain melee hit.
## - First kill: BossDef.first_kill_flags (the park boss: blueprint_essence_workshop) on the kill
##   itself, not on extraction. Respawn: FieldState.boss_respawn_day[boss id] = day + respawn_days.
## - A boss's own rules live in BossDef.mechanic (BossMechanic hooks). hold(sec) hands it the body for a
##   while (dive, stance): no AI, no patterns, only the mechanic's on_tick and statuses.
## - Intro (BossDef.buried_intro): spawned asleep it lies buried with only its top showing. The first
##   wake holds it for MonsterRules.BOSS_INTRO_SEC (hits ignored) while it climbs out and roars.
## Design: docs/design/04-monsters.md "보스", "드롭"; 06-magic-essence.md (정수 공방 설계도)

signal phase_changed(phase: int)
## Ground area of an attack about to land: the Fx boss_telegraph params (shape, radius, inner,
## angle_deg, length, width, direction, duration, kind) plus "position" and "pattern_id".
## Lane D's Fx draws it from the same Dictionary.
signal telegraph_started(area: Dictionary)
## A pattern began its windup (Lane D: roar, animation). Summons have no ground area.
signal pattern_started(pattern_id: StringName)
signal defeated(first_kill: bool)
## Climbed out of the ground after its first wake (the intro is over, the fight starts).
signal woke

const BOSS_GROUP := &"field_bosses"
const INTRO_FX_BREAK := &"monster_slam"
const INTRO_FX_ROAR := &"monster_scream"
const INTRO_SOUND := &"monster_growl"
## First clip the model has is played while it climbs out.
const INTRO_CLIPS: Array[StringName] = [&"Rise", &"Scream", &"Attack"]
const FX_TELEGRAPH := &"boss_telegraph"
const MONSTER_DIR := "res://data/monsters/"
const FIGHT_STATES: Array[Enums.AIState] = [Enums.AIState.SUSPICIOUS, Enums.AIState.INVESTIGATE,
		Enums.AIState.CHASE, Enums.AIState.ATTACK]

## Loaded from data/monsters/bosses/<def.id>.tres when left empty.
@export var boss: BossDef
## Set by BossSpawner: leash distance from home (the arena center).
var arena_radius: float = 15.0
## Region the respawn day is kept for.
var region_id: StringName = &""
var phase := 1
## BossDef.mechanic instance, or null.
var mechanic: BossMechanic

## pattern id -> seconds until it can be used again
var _cooldowns: Dictionary = {}
var _gap := 0.0
var _cast: BossPattern
var _cast_left := 0.0
var _cast_area: Dictionary = {}
var _summons: Array[Monster] = []
var _first_kill := false
var _hold_left := 0.0
## Spawned asleep: lies in the ground until the first wake (intro).
var _buried := false
var _bury_depth := 0.0
var _rise_from_y := 0.0
var _intro_left := 0.0
## The intro roar played (true for a boss that never had an intro).
var _landed := true


func _ready() -> void:
	super._ready()
	if def == null:
		return
	add_to_group(BOSS_GROUP)
	if boss == null:
		boss = BossDef.for_monster(def.id)
	if boss == null:
		push_error("%s has no BossDef in %s" % [def.id, BossDef.DIR])
	elif boss.mechanic:
		mechanic = boss.mechanic.new() as BossMechanic
		if mechanic == null:
			push_error("%s: BossDef.mechanic is not a BossMechanic" % def.id)
		else:
			mechanic.boss = self
			mechanic.on_added()
	if start_state == Enums.AIState.SLEEP and boss and boss.buried_intro:
		_bury()


func tick(delta: float) -> void:
	if is_dead():
		return
	_intro_left = maxf(_intro_left - delta, 0.0)
	_step_intro()
	if mechanic:
		mechanic.on_tick(delta)
		if is_dead():
			return
	if _hold_left > 0.0:
		_hold_left -= delta
		status.step(delta)
		return
	if _cast != null:
		_step_cast(delta)
		return
	_gap -= delta
	for id in _cooldowns:
		_cooldowns[id] -= delta
	if _is_leash_state() and _flat_distance(home) > arena_radius:
		_set_state(Enums.AIState.RETURN)
	super.tick(delta)
	if is_dead():
		return
	_recover(delta)
	_try_pattern()


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if is_in_intro():
		return
	if mechanic and not is_dead():
		amount = mechanic.filter_damage(amount, info)
		if amount <= 0.0:
			return
	super.take_damage(amount, info)
	if is_dead() or boss == null or max_hp <= 0.0:
		return
	var next := boss.phase_for(hp / max_hp)
	if next > phase:
		phase = next
		phase_changed.emit(phase)
		if mechanic:
			mechanic.on_phase_changed(phase)


## Hands the body to the mechanic for `sec` seconds (dive, stance, stunned): the AI and patterns pause,
## the mechanic's on_tick keeps running and moves the boss itself. 0 ends it early.
func hold(sec: float) -> void:
	_hold_left = maxf(sec, 0.0)
	if _hold_left > 0.0:
		_stop()


func is_held() -> bool:
	return _hold_left > 0.0


## Lying in the ground, asleep (spawned asleep and never woken).
func is_buried() -> bool:
	return _buried


## Climbing out after the first wake: hits are ignored.
func is_in_intro() -> bool:
	return _intro_left > 0.0


func _set_state(new_state: Enums.AIState) -> void:
	var waking := _buried and state == Enums.AIState.SLEEP and new_state != Enums.AIState.SLEEP
	super._set_state(new_state)
	if waking and not is_dead():
		_rise()


# --- Intro ----------------------------------------------------------------

## Sinks the model so only its top shows (a mound in the arena), hides the core and outline.
## The model moves, not the Visual node: CombatFeel.flinch springs the Visual node back to its rest.
func _bury() -> void:
	_buried = true
	var model := _intro_model()
	if model:
		_bury_depth = _mesh_top(model) * (1.0 - MonsterRules.BOSS_BURY_SHOW)
		model.position.y -= _bury_depth
	else:
		var body := get_node_or_null(^"Body") as Node3D
		if body:
			body.visible = false  # grey box without the model (no assets)
	_set_intro_look(false)


## First wake: ground breaks, it climbs out, then roars (shake + hit-stop) and the fight starts.
func _rise() -> void:
	_buried = false
	_landed = false
	_intro_left = MonsterRules.BOSS_INTRO_SEC
	hold(MonsterRules.BOSS_INTRO_SEC)
	Fx.spawn(INTRO_FX_BREAK, global_position, {"radius": MonsterRules.BOSS_INTRO_FX_RADIUS, "element": def.family})
	Audio.play(INTRO_SOUND, global_position)
	CombatFeel.shake(self, MonsterRules.BOSS_INTRO_SHAKE_START, global_position)
	var visual := get_node_or_null(^"Visual") as MonsterVisual
	if visual:
		for clip in INTRO_CLIPS:
			if visual.has_clip(clip):
				visual.play_once(clip)
				break
	var model := _intro_model()
	if model:
		_rise_from_y = model.position.y
	else:
		var body := get_node_or_null(^"Body") as Node3D
		if body:
			body.visible = true


## Driven by tick(): climbs out over BOSS_RISE_SEC (overshoots a little), then lands once.
func _step_intro() -> void:
	if _landed:
		return
	var t := minf((MonsterRules.BOSS_INTRO_SEC - _intro_left) / MonsterRules.BOSS_RISE_SEC, 1.0)
	var model := _intro_model()
	if model:
		model.position.y = Tween.interpolate_value(_rise_from_y, _bury_depth, t, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT)
	if t >= 1.0:
		_land_intro()


func _land_intro() -> void:
	_landed = true
	_set_intro_look(true)
	Fx.spawn(INTRO_FX_ROAR, global_position, {"element": def.family})
	CombatFeel.shake(self, MonsterRules.BOSS_INTRO_SHAKE_LAND, global_position)
	CombatFeel.hit_stop(self, MonsterRules.BOSS_INTRO_STOP_SEC)
	woke.emit()


func _set_intro_look(on: bool) -> void:
	_set_outline(on)
	var core := get_node_or_null(^"WeakPoint/Core") as Node3D
	if core:
		core.visible = on


func _intro_model() -> Node3D:
	return get_node_or_null(^"Visual/Model") as Node3D


## Top of the meshes under `root` above the boss's feet (metres).
func _mesh_top(root: Node3D) -> float:
	var top := 0.0
	var to_boss := global_transform.affine_inverse()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		top = maxf(top, (to_boss * mi.global_transform * mi.get_aabb()).end.y)
	return top


## Drops the pattern in its windup without landing it (a stun from the mechanic).
func cancel_cast() -> void:
	_cast = null
	_cast_area = {}


## Fighting: noticed someone, chasing, attacking or mid-pattern.
func is_engaged() -> bool:
	return not is_dead() and (_cast != null or state in FIGHT_STATES)


## The pattern in its windup, or null.
func casting() -> BossPattern:
	return _cast


## Field HUD boss bar (Player.hud_state()["boss"]).
func hud_state() -> Dictionary:
	return {"name": def.name, "hp": hp, "hp_max": max_hp, "phase": phase,
		"phase_count": boss.phases.size() + 1 if boss else 1}


## The engaged boss whose arena the player is in or near, as hud_state(); {} when none.
static func hud_for(player: Node3D) -> Dictionary:
	for node in player.get_tree().get_nodes_in_group(BOSS_GROUP):
		var b := node as BossMonster
		if b == null or not b.is_engaged():
			continue
		if b._flat_distance_from_home(player.global_position) <= b.arena_radius + MonsterRules.BOSS_HUD_MARGIN:
			return b.hud_state()
	return {}


## Drop table for MonsterDrops: the first kill has its own (no gear roll).
func drop_table_id() -> StringName:
	if _first_kill and boss and boss.first_kill_drop_table_id != &"":
		return boss.first_kill_drop_table_id
	return def.drop_table_id


## Is `point` inside a telegraph area (flat distance, the y axis is ignored)?
static func area_contains(area: Dictionary, point: Vector3) -> bool:
	var to: Vector3 = point - area["position"]
	to.y = 0.0
	var dist := to.length()
	var dir: Vector3 = area.get("direction", Vector3.FORWARD)
	match StringName(area.get("shape", &"")):
		&"circle":
			return dist <= area["radius"]
		&"ring":
			return dist >= area.get("inner", 0.0) and dist <= area["radius"]
		&"cone":
			return dist <= area["radius"] and (dist < 0.01 \
					or rad_to_deg(dir.angle_to(to)) <= float(area["angle_deg"]) * 0.5)
		&"line":
			var along := to.dot(dir)
			return along >= 0.0 and along <= area["length"] \
					and (to - dir * along).length() <= float(area["width"]) * 0.5
	return false


# --- Patterns -------------------------------------------------------------

func _try_pattern() -> void:
	if boss == null or _gap > 0.0 or not status.can_act() or not _target_valid():
		return
	if state != Enums.AIState.CHASE and state != Enums.AIState.ATTACK:
		return
	var dist := _distance_to(target)
	for pattern in boss.patterns:
		if _cooldowns.get(pattern.id, 0.0) > 0.0 or dist < pattern.range_min or dist > pattern.range_max:
			continue
		if pattern.is_summon() and _alive_summons() >= pattern.summon_max_alive:
			continue
		if mechanic and not mechanic.can_use(pattern):
			continue
		_start(pattern)
		return


func _start(pattern: BossPattern) -> void:
	_cast = pattern
	_cast_left = pattern.windup_sec
	_cooldowns[pattern.id] = pattern.cooldown_sec / boss.speed_for(phase)
	_stop()
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)
	_cast_area = {} if pattern.shape == &"" else area_for(pattern, target.global_position)
	pattern_started.emit(pattern.id)
	if not _cast_area.is_empty():
		telegraph_started.emit(_cast_area)
		Fx.spawn(FX_TELEGRAPH, _cast_area["position"], _cast_area)
	if mechanic:
		mechanic.on_pattern_started(pattern, _cast_area)


## Windup: the boss stands still (statuses still tick), then the pattern lands.
func _step_cast(delta: float) -> void:
	status.step(delta)
	if is_dead():
		return
	_stop()
	_cast_left -= delta
	if _cast_left > 0.0:
		return
	var pattern := _cast
	var area := _cast_area
	_cast = null
	_cast_area = {}
	_gap = boss.pattern_gap_sec
	if mechanic and mechanic.land_pattern(pattern, area):
		return
	if pattern.is_summon():
		summon(pattern)
	elif not area.is_empty():
		hit_area(pattern, area)


## The telegraph area of `pattern` aimed at `target_pos` (Fx boss_telegraph params + position, pattern_id).
func area_for(pattern: BossPattern, target_pos: Vector3) -> Dictionary:
	var dir := target_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -global_basis.z
		dir.y = 0.0
	dir = dir.normalized()
	var center := global_position
	match pattern.anchor:
		BossPattern.Anchor.FRONT:
			center += dir * pattern.offset
		BossPattern.Anchor.TARGET:
			center = Vector3(target_pos.x, global_position.y, target_pos.z)
	return {"pattern_id": pattern.id, "shape": pattern.shape, "position": center, "direction": dir,
		"radius": pattern.radius, "inner": pattern.inner, "angle_deg": pattern.angle_deg,
		"length": pattern.length, "width": pattern.width, "duration": pattern.windup_sec,
		"kind": pattern.kind}


## Damages everyone inside `area` and plays boss_<pattern.id>. Mechanics may call it for their own hits.
func hit_area(pattern: BossPattern, area: Dictionary) -> void:
	var info := {"source": self, "element": def.family, "monster_id": def.id,
		"pattern_id": pattern.id, "position": area["position"]}
	if not pattern.status.is_empty():
		info["status"] = pattern.status.duplicate(true)
	var amount := attack_damage() * pattern.damage_mult
	var fx := area.duplicate()
	fx["element"] = def.family
	if float(area.get("length", 0.0)) > 0.0:  # line patterns: D's effect runs to the far end
		fx["to"] = area["position"] + area["direction"] * float(area["length"])
	Fx.spawn(StringName("boss_%s" % pattern.id), area["position"], fx)
	for body in area_targets(area):
		body.take_damage(amount, info.duplicate(true))
		attack_landed.emit(body, info)


## The player and allies (companions, rescuees) standing inside the area.
func area_targets(area: Dictionary) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if node is Node3D and node.has_method(&"take_damage"):
			found.append(node)
	var shape := SphereShape3D.new()
	shape.radius = maxf(area["radius"], area["length"]) + 1.0
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, area["position"])
	query.collision_mask = 1 << (Enums.LAYER_ALLY - 1)
	for hit in get_world_3d().direct_space_state.intersect_shape(query):
		var body := hit.collider as Node3D
		if body and body.has_method(&"take_damage") and not found.has(body):
			found.append(body)
	var inside: Array[Node3D] = []
	inside.assign(found.filter(func(body: Node3D) -> bool: return area_contains(area, body.global_position)))
	return inside


## Spawns pattern.summon_id around the target (inside the arena). Mechanics may call it too.
func summon(pattern: BossPattern) -> void:
	var summon_def := load(MONSTER_DIR + String(pattern.summon_id) + ".tres") as MonsterDef
	var parent := get_parent() as Node3D
	if summon_def == null or summon_def.scene == null or parent == null:
		push_warning("%s: cannot summon %s" % [def.id, pattern.summon_id])
		return
	var around := target.global_position if _target_valid() else global_position
	var count := mini(pattern.summon_count, pattern.summon_max_alive - _alive_summons())
	for i in count:
		var at := _summon_point(pattern, around, i, count)
		var m := summon_def.scene.instantiate() as Monster
		m.def = summon_def
		m.home = at
		# Summons drop nothing, so a boss fight is not a material farm.
		m.drop_mult = 0.0
		m.position = parent.to_local(at)
		if _target_valid():
			m.target = target
			m.start_state = Enums.AIState.CHASE
		m.name = String(summon_def.id)
		parent.add_child(m, true)
		_summons.append(m)
		Fx.spawn(StringName("boss_%s" % pattern.id), at, {"radius": 1.2, "element": def.family})


## Spread evenly around the target, pulled back inside the arena.
func _summon_point(pattern: BossPattern, around: Vector3, index: int, count: int) -> Vector3:
	var angle := TAU * index / maxf(count, 1) + randf() * TAU / maxf(count, 1)
	var dist := randf_range(pattern.summon_dist_min, pattern.summon_dist_max)
	var at := around + Vector3(cos(angle), 0.0, sin(angle)) * dist
	var from_home := at - home
	from_home.y = 0.0
	var limit := maxf(arena_radius - 1.0, 0.0)
	if from_home.length() > limit:
		at = home + from_home.normalized() * limit
	at.y = global_position.y
	return at


func _alive_summons() -> int:
	_summons.assign(_summons.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not m.is_dead()))
	return _summons.size()


# --- Out of combat, death -------------------------------------------------

func _recover(delta: float) -> void:
	if boss == null or (state != Enums.AIState.SLEEP and state != Enums.AIState.WANDER):
		return
	if hp < max_hp:
		hp = minf(max_hp, hp + max_hp * boss.regen_ratio * delta)
	if hp >= max_hp and (phase != 1 or not _cooldowns.is_empty() or _alive_summons() > 0):
		_reset_fight()


func _reset_fight() -> void:
	_cooldowns.clear()
	_gap = 0.0
	_hold_left = 0.0
	for m in _summons:
		if is_instance_valid(m):
			m.vanish()
	_summons.clear()
	if phase != 1:
		phase = 1
		phase_changed.emit(phase)
	if mechanic:
		mechanic.on_reset()


## Patterns replace the plain melee hit (ATTACK state only keeps the boss close and facing).
func _perform_attack() -> void:
	pass


func _die() -> void:
	_first_kill = boss != null and FieldState.boss_kill_count(def.id) == 0
	if mechanic:
		mechanic.on_died()
	super._die()
	if boss == null:
		return
	FieldState.record_boss_kill(region_id, def.id, GameState.day + boss.respawn_days)
	if _first_kill:
		for flag in boss.first_kill_flags:
			GameState.set_flag(flag)
		if boss.first_kill_text != "":
			EventBus.notification_posted.emit(boss.first_kill_text, &"info")
	defeated.emit(_first_kill)


func _flat_distance_from_home(point: Vector3) -> float:
	var to := point - home
	to.y = 0.0
	return to.length()
