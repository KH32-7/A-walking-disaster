extends Node
## D-18: every effect .tres is an FxDef named after its file, every id gameplay calls exists,
## effects free themselves, max_alive holds, unknown ids and missing assets give null, damage numbers show.
## Works with or without the assets submodule (CI has none: effects are skipped silently).

## Ids Lane B calls today (weapon_holder, companion, magic_weapon, magic_zone, thrown_consumable,
## self_destruct_behavior, class/companion skills).
const GAMEPLAY_IDS := [&"hit_spark", &"muzzle_flash", &"bullet_tracer", &"bullet_impact", &"perfect_block",
	&"neon_moth_blast", &"essence_release", &"essence_chain", &"essence_combo",
	&"consumable_grenade", &"consumable_flashbang", &"consumable_noise_lure",
	&"brace", &"dash_slash", &"precision_shot", &"shadow_step", &"slam", &"suppressive_fire", &"boss_telegraph",
	&"melee_swing", &"monster_claw", &"monster_slam", &"monster_bite", &"monster_splash", &"monster_scream", &"monster_cast",
	&"monster_death", &"boss_slam", &"boss_root_burst", &"boss_summon_pods"]
const COMBO_IDS := [&"thorn_bush", &"swamp", &"mud", &"photosynthesis", &"shard_burst", &"shock_puddle"]
const PROBE_TEXTURE := "res://assets/vfx/magic_arsenal/textures/modular/glow01.png"


func run() -> bool:
	var ok := true
	var has_assets := ResourceLoader.exists(PROBE_TEXTURE)
	Fx.clear()
	var dir := DirAccess.open(Fx.EFFECTS_DIR)
	ok = _expect(dir != null, "effects dir exists") and ok
	if dir != null:
		for file in dir.get_files():
			var name := file.trim_suffix(".remap")
			if not name.ends_with(".tres"):
				continue
			var def := load("%s/%s" % [Fx.EFFECTS_DIR, name]) as FxDef
			ok = _expect(def != null and String(def.id) == name.get_basename(), "%s is an FxDef with its file name as id" % name) and ok
	for id in GAMEPLAY_IDS:
		ok = _expect(Fx.has_effect(id), "gameplay id %s has an effect" % id) and ok
	for id in COMBO_IDS:
		ok = _expect(Fx.has_effect(StringName("essence_combo_%s" % id)), "combo %s has an effect" % id) and ok

	var at := Vector3(0, 0, 0)
	var spark := Fx.spawn_node(&"hit_spark", at, {"element": Enums.Element.WATER, "crit": true, "silent": true})
	ok = _expect((spark != null) == has_assets, "hit_spark built only when assets exist (assets: %s)" % has_assets) and ok
	# The boss warning is gameplay information: drawn by a repo shader, shown even without assets.
	var warn := Fx.spawn_node(&"boss_telegraph", at, {"shape": &"line", "length": 14.0, "width": 2.0,
		"direction": Vector3.FORWARD, "duration": 1.5, "kind": &"danger", "silent": true})
	ok = _expect(warn != null, "boss_telegraph builds with or without assets") and ok
	if warn != null:
		ok = _expect(warn.lifetime > 1.5 and warn.lifetime < 2.0, "boss_telegraph lasts the wind-up plus a short linger") and ok
		warn.advance(5.0)
	var zone := Fx.spawn_node(&"essence_combo", at, {"id": &"swamp", "radius": 2.0, "duration": 3.0, "silent": true})
	if has_assets:
		ok = _expect(zone != null and zone.effect_id == &"essence_combo_swamp", "essence_combo picks its variant by id") and ok
		ok = _expect(zone != null and is_equal_approx(zone.lifetime, 3.0), "zone lives params.duration") and ok
		for id in GAMEPLAY_IDS:
			var fx := Fx.spawn_node(id, at, {"direction": Vector3.FORWARD, "to": at + Vector3(5, 0, 0),
				"normal": Vector3.UP, "radius": 3.0, "element": Enums.Element.GREEN, "silent": true})
			ok = _expect(fx != null, "%s builds with assets" % id) and ok
		for fx in Fx.live_effects():
			fx.advance(30.0)
		ok = _expect(Fx.live_effects().is_empty(), "effects free themselves after their life") and ok
		for i in 60:
			Fx.spawn(&"hit_spark", at, {"silent": true})
		ok = _expect(Fx.live_effects().size() <= Fx.effects[&"hit_spark"].max_alive, "hit_spark capped at max_alive") and ok
	Fx.clear()
	ok = _expect(Fx.spawn_node(&"no_such_effect", at) == null, "unknown id gives null") and ok

	var label := Fx.feedback.show_number(at, "12", UiTokens.TEXT)
	ok = _expect(label != null and label.text == "12", "damage number shows") and ok
	label.queue_free()
	return ok


func _expect(cond: bool, what: String) -> bool:
	if not cond:
		push_error("test_fx: " + what)
	return cond
