extends BossMechanic
## 수술등 망령 (docs/design/04-monsters.md "보스"): flash, scalpel throw, two clones. Only the real one casts a
## shadow, so in the clone phase you read the ground, not a HUD.
## - Flash (action &"flash"): orange ring (no damage). Whoever is still inside is blinded params.blind_sec.
## - Scalpels (action &"scalpels"): params.count red lines fanned params.spread_deg apart toward you, thrown
##   when the windup ends. One hit per person even where the lines overlap. Bleed.
## - Clones (action &"clones"): smoke, then it and params.count clones stand around you params.spread away
##   (the real one at a random spot). A clone pops on the first hit; all go after params.life_sec.
## Numbers are in data/monsters/bosses/surgical_lamp_wraith.tres (pattern params), all drafts.

const DECOY_SCENE := preload("res://field/monsters/wraith_decoy.tscn")
const SCALPEL_FX := &"boss_scalpels"
const FLASH_FX := &"boss_flash"
const CLONES_FX := &"boss_clones"

var decoys: Array[Monster] = []

var _lines: Array[Dictionary] = []
var _decoys_left := 0.0


func on_tick(delta: float) -> void:
	if decoys.is_empty():
		return
	_decoys_left -= delta
	if _decoys_left <= 0.0:
		_clear_decoys()
	else:
		decoys.assign(decoys.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not m.is_dead()))


func can_use(pattern: BossPattern) -> bool:
	return pattern.action != &"clones" or _alive_decoys() == 0


func on_pattern_started(pattern: BossPattern, _area: Dictionary) -> void:
	if pattern.action != &"scalpels" or not is_instance_valid(boss.target):
		return
	_lines.clear()
	var count := int(pattern.params.get("count", 3))
	var spread := deg_to_rad(float(pattern.params.get("spread_deg", 22.0)))
	var base := boss.area_for(pattern, boss.target.global_position)
	var dir: Vector3 = base["direction"]
	for i in count:
		var area := base.duplicate()
		area["shape"] = &"line"
		area["position"] = boss.global_position
		area["direction"] = dir.rotated(Vector3.UP, spread * (i - (count - 1) * 0.5))
		_lines.append(area)
		boss.telegraph_started.emit(area)
		Fx.spawn(BossMonster.FX_TELEGRAPH, area["position"], area)


func land_pattern(pattern: BossPattern, area: Dictionary) -> bool:
	match pattern.action:
		&"scalpels":
			_throw(pattern)
			return true
		&"flash":
			_flash(pattern, area)
			return true
		&"clones":
			_clones(pattern)
			return true
	return false


func on_reset() -> void:
	_clear_decoys()


func on_died() -> void:
	_clear_decoys()


# --- Patterns -------------------------------------------------------------

func _throw(pattern: BossPattern) -> void:
	var hit: Array[Node3D] = []
	for line in _lines:
		var fx := line.duplicate()
		fx["element"] = boss.def.family
		fx["to"] = line["position"] + line["direction"] * float(line["length"]) + Vector3.UP * 1.6
		Fx.spawn(SCALPEL_FX, line["position"] + Vector3.UP * 1.6, fx)
		for body in boss.area_targets(line):
			if not hit.has(body):
				hit.append(body)
	var info := {"source": boss, "element": boss.def.family, "monster_id": boss.def.id, "pattern_id": pattern.id,
		"position": boss.global_position}
	if not pattern.status.is_empty():
		info["status"] = pattern.status.duplicate(true)
	var amount := boss.attack_damage() * pattern.damage_mult
	for body in hit:
		body.take_damage(amount, info.duplicate(true))
		boss.attack_landed.emit(body, info)
	_lines.clear()


## Orange ring: no damage, blinds whoever did not step out.
func _flash(pattern: BossPattern, area: Dictionary) -> void:
	var fx := area.duplicate()
	fx["element"] = boss.def.family
	Fx.spawn(FLASH_FX, boss.global_position, fx)
	for body in boss.area_targets(area):
		var holder := body.get_node_or_null(NodePath(StatusHolder.NODE_NAME)) as StatusHolder
		if holder:
			holder.apply(&"blind", {"duration": float(pattern.params.get("blind_sec", 2.0))})


func _clones(pattern: BossPattern) -> void:
	var parent := boss.get_parent() as Node3D
	if parent == null:
		return
	_clear_decoys()
	var count := int(pattern.params.get("count", 2))
	var around := boss.target.global_position if is_instance_valid(boss.target) else boss.global_position
	var spread := float(pattern.params.get("spread", 5.0))
	var spots: Array[Vector3] = []
	var turn := randf() * TAU
	for i in count + 1:
		var a := turn + TAU * i / float(count + 1)
		spots.append(_in_arena(around + Vector3(cos(a), 0.0, sin(a)) * spread))
	var real_index := randi() % spots.size()
	var decoy_def := _decoy_def()
	for i in spots.size():
		Fx.spawn(CLONES_FX, spots[i], {"element": boss.def.family})
		if i == real_index:
			boss.global_position = spots[i]
			continue
		var m := DECOY_SCENE.instantiate() as Monster
		m.def = decoy_def
		m.home = spots[i]
		m.position = parent.to_local(spots[i])
		m.rotation.y = boss.rotation.y
		if is_instance_valid(boss.target):
			m.target = boss.target
			m.start_state = Enums.AIState.CHASE
		m.name = "%s_clone" % boss.def.id
		parent.add_child(m, true)
		decoys.append(m)
	_decoys_left = float(pattern.params.get("life_sec", 12.0))


## Same look (def id finds the same model), one hit, no damage, no drops.
func _decoy_def() -> MonsterDef:
	var d := boss.def.duplicate() as MonsterDef
	d.tier = Enums.MonsterTier.NORMAL
	d.hp = 1.0
	d.attack = 0.0
	d.behaviors = []
	d.elite_behaviors = []
	d.drop_table_id = &""
	return d


func _in_arena(at: Vector3) -> Vector3:
	var from_home := at - boss.home
	from_home.y = 0.0
	var limit := maxf(boss.arena_radius - 1.0, 0.0)
	if from_home.length() > limit:
		at = boss.home + from_home.normalized() * limit
	at.y = boss.global_position.y
	return at


func _alive_decoys() -> int:
	decoys.assign(decoys.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not m.is_dead()))
	return decoys.size()


func _clear_decoys() -> void:
	for m in decoys:
		if is_instance_valid(m) and not m.is_dead():
			m.vanish()
	decoys.clear()
