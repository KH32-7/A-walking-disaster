extends Node
## D-17: every field monster has a visual scene, the models carry the clips MonsterVisual plays, the
## visual follows a monster's public signals (attack, hit, death -> corpse), and every monster / boss
## attack effect id exists and frees itself. Model checks skip on a clone without assets access.

const VISUAL_DIR := "res://art/monsters/"
const MONSTER_DIR := "res://data/monsters/"
const FX_IDS := [&"monster_claw", &"monster_slam", &"monster_bite", &"monster_splash", &"monster_scream",
	&"monster_cast", &"monster_death", &"boss_slam", &"boss_root_burst", &"boss_summon_pods"]
## Extra visuals for monsters that have no MonsterDef yet (bosses and water / neon types to come).
const EXTRA_VISUALS := [&"breakwater_golem", &"sunken_sign_serpent", &"surgical_lamp_wraith", &"neon_colossus"]
const PROBE_MODEL := "res://assets/monsters/foliage/vine_tendril.glb"
const PROBE_TEXTURE := "res://assets/vfx/magic_arsenal/textures/modular/glow01.png"

class FakeMonster:
	extends Node3D
	signal state_changed(old_state: int, new_state: int)
	signal attack_started(info: Dictionary)
	signal damaged(amount: float, info: Dictionary)
	signal died(monster: Node)
	var velocity := Vector3.ZERO
	var state: int = Enums.AIState.WANDER
	var hp := 10.0
	var def: MonsterDef


func run() -> bool:
	var ok := true
	Fx.clear()
	var has_fx_assets := ResourceLoader.exists(PROBE_TEXTURE)
	for id in FX_IDS:
		ok = _expect(Fx.has_effect(id), "effect %s exists" % id) and ok
		var fx := Fx.spawn_node(id, Vector3.ZERO, {"silent": true, "element": Enums.Element.GREEN,
			"direction": Vector3.FORWARD, "to": Vector3(0, 0, -8)})
		ok = _expect((fx != null) == has_fx_assets, "effect %s builds only with VFX assets" % id) and ok
	var defs := _monster_defs()
	ok = _expect(defs.size() >= 11, "found the field monster defs (%d)" % defs.size()) and ok
	for def in defs:
		ok = _expect(ResourceLoader.exists(VISUAL_DIR + String(def.id) + ".tscn"), "%s has a visual scene" % def.id) and ok
		var fx_id: StringName = def.get("attack_fx") if "attack_fx" in def else &""  # Lane B field (B-req)
		if fx_id != &"":
			ok = _expect(Fx.has_effect(fx_id), "%s attack_fx %s is an Fx id" % [def.id, fx_id]) and ok
	# Region bosses that have no MonsterDef yet must still find their model by the same id.
	for f in DirAccess.get_files_at("res://data/regions/"):
		var region := load("res://data/regions/" + f.trim_suffix(".remap")) if f.trim_suffix(".remap").ends_with(".tres") else null
		var boss_id: StringName = region.get("boss_id") if region and "boss_id" in region else &""
		if boss_id != &"":
			ok = _expect(ResourceLoader.exists(VISUAL_DIR + String(boss_id) + ".tscn"), "region boss %s has a visual scene" % boss_id) and ok
	var boss := load(MONSTER_DIR + "bosses/ancient_tree_giant.tres")
	if boss and "patterns" in boss:
		for pattern in boss.patterns:
			ok = _expect(Fx.has_effect(StringName("boss_%s" % pattern.id)), "boss pattern %s has an effect" % pattern.id) and ok
	for fx in Fx.live_effects():
		fx.advance(30.0)
	ok = _expect(Fx.live_effects().is_empty(), "monster effects freed (%d left)" % Fx.live_effects().size()) and ok
	if not ResourceLoader.exists(PROBE_MODEL):
		print("test_monster_visuals: assets/monsters missing, model checks skipped")
	else:
		for def in defs:
			ok = _check_clips(def.id) and ok
		for id in EXTRA_VISUALS:
			ok = _check_clips(id) and ok
		ok = await _signals(defs) and ok
	Fx.clear()
	return ok


func _check_clips(id: StringName) -> bool:
	var ok := true
	var visual := (load(VISUAL_DIR + String(id) + ".tscn") as PackedScene).instantiate() as MonsterVisual
	add_child(visual)
	ok = _expect(visual.anim != null, "%s model has an AnimationPlayer" % id) and ok
	if visual.anim:
		for clip in [&"Idle", &"Hit", &"Death"]:
			ok = _expect(visual.has_clip(clip), "%s has clip %s" % [id, clip]) and ok
		ok = _expect(visual.has_clip(visual.attack_clip), "%s has its attack clip %s" % [id, visual.attack_clip]) and ok
		ok = _expect(visual.current_clip() == &"Idle", "%s starts in Idle" % id) and ok
	visual.queue_free()
	return ok


func _signals(defs: Array[MonsterDef]) -> bool:
	var ok := true
	var m := FakeMonster.new()
	for def in defs:
		if def.id == &"vine_tendril":
			m.def = def
	add_child(m)
	var visual := (load(VISUAL_DIR + "vine_tendril.tscn") as PackedScene).instantiate() as MonsterVisual
	m.add_child(visual)
	m.velocity = Vector3(3, 0, 0)
	visual._process(0.016)
	ok = _expect(visual.current_clip() in [&"Walk", &"Run"], "moving -> walk clip (got %s)" % visual.current_clip()) and ok
	m.attack_started.emit({})
	ok = _expect(visual.current_clip() == &"Attack", "attack_started -> Attack") and ok
	visual._process(0.016)
	ok = _expect(visual.current_clip() == &"Attack", "movement does not cut the attack") and ok
	m.damaged.emit(5.0, {})
	ok = _expect(visual.current_clip() == &"Attack", "a hit does not cut the attack") and ok
	visual.anim.advance(visual.anim.current_animation_length + 0.2)
	m.velocity = Vector3.ZERO
	visual._process(0.016)
	m.damaged.emit(5.0, {})
	ok = _expect(visual.current_clip() == &"Hit", "damaged when idle -> Hit") and ok
	m.hp = 0.0
	m.died.emit(m)
	ok = _expect(visual.get_parent() == self, "killed -> the visual stays as a corpse") and ok
	ok = _expect(visual.current_clip() == &"Death", "corpse plays Death") and ok
	var deaths := Fx.live_effects().filter(func(fx: FxNode) -> bool: return fx.effect_id == &"monster_death")
	ok = _expect(deaths.size() == 1, "kill spawns monster_death") and ok
	m.free()
	visual.queue_free()
	# vanish (moth self-destruct): no corpse, no burst.
	var m2 := FakeMonster.new()
	add_child(m2)
	var v2 := (load(VISUAL_DIR + "neon_moth.tscn") as PackedScene).instantiate() as MonsterVisual
	m2.add_child(v2)
	m2.died.emit(m2)
	ok = _expect(v2.get_parent() == m2, "vanish leaves no corpse") and ok
	m2.free()
	Fx.clear()
	await get_tree().process_frame
	return ok


func _monster_defs() -> Array[MonsterDef]:
	var out: Array[MonsterDef] = []
	for f in DirAccess.get_files_at(MONSTER_DIR):
		var file := f.trim_suffix(".remap")
		if file.ends_with(".tres"):
			var def := load(MONSTER_DIR + file) as MonsterDef
			if def:
				out.append(def)
	return out


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
