extends Node
## Autoload `Fx`. Owner: Lane D (D-18).
## Gameplay code calls `Fx.spawn(&"hit_spark", position, {"element": Enums.Element.GREEN})`
## and never instances VFX scenes directly, so art can change without touching gameplay.
##
## Effects: data/ui/effects/<id>.tres (EffectDef: scene + base_params + sound). The id catalogue and
## each id's params are in vfx/README.md. Unknown ids warn once and do nothing.
## Hit feedback (damage numbers, hit flash, hurt sound) is not spawned by gameplay: HitFeedback listens
## to monsters' `damaged` and the player's `health_changed` (same duck-typed pattern as D-05 markers).
## Settings.reduce_flash dims every flash (FxEffect.flash_k). Camera shake / hit-stop / knockback are
## Lane B's (camera, combat); Fx never moves the camera.

const EFFECTS_DIR := "res://data/ui/effects"

## Preview/tests: effects stop moving on their own and only advance through `advance(delta)`.
var manual_step := false
## Preview/tests: -1 follow Settings.reduce_flash, 0 off, 1 on (without touching the settings file).
var reduced_flash_override := -1
var effects: Dictionary = {}  # StringName -> EffectDef
var feedback: HitFeedback

var _alive: Dictionary = {}  # StringName -> Array[FxEffect], oldest first
var _warned: Dictionary = {}
var _seq := 0


func _ready() -> void:
	_load_effects()
	feedback = HitFeedback.new()
	feedback.name = &"HitFeedback"
	add_child(feedback)
	# A finished sortie or base scene must not leave a swamp lying on the next map.
	EventBus.flow_state_changed.connect(func(_s: Enums.FlowState) -> void: clear())


func spawn(effect_id: StringName, position: Vector3, params: Dictionary = {}) -> void:
	spawn_node(effect_id, position, params)


## Same as spawn() but returns the effect (or null). For previews and tests.
func spawn_node(effect_id: StringName, position: Vector3, params: Dictionary = {}) -> FxEffect:
	var def: EffectDef = effects.get(effect_id)
	if def == null or def.scene == null:
		if not _warned.has(effect_id):
			_warned[effect_id] = true
			push_warning("Fx: unknown effect id '%s' (data/ui/effects/)" % effect_id)
		return null
	if not is_inside_tree() or not position.is_finite():
		return null
	var fx := def.scene.instantiate() as FxEffect
	if fx == null:
		push_warning("Fx: scene of '%s' is not an FxEffect" % effect_id)
		return null
	var p := _combo_params(def.combo_id)
	p.merge(def.base_params, true)
	p.merge(params, true)
	p["effect_id"] = effect_id
	add_child(fx)
	fx.global_position = position
	fx.setup(p)
	_track(effect_id, fx, def.max_alive)
	var snd := def.sound_crit if p.get("crit", false) and def.sound_crit != &"" else def.sound
	if snd != &"" and not p.get("silent", false):
		Audio.play(snd, position)
	return fx


func _process(delta: float) -> void:
	if not manual_step:
		HitFlash.step(delta)


## Steps every live effect and hit flash (only needed when manual_step is on).
func advance(delta: float) -> void:
	for fx in live_effects():
		fx.advance(delta)
	HitFlash.step(delta)


func live_effects() -> Array[FxEffect]:
	var out: Array[FxEffect] = []
	for child in get_children():
		if child is FxEffect and not child.is_queued_for_deletion():
			out.append(child)
	return out


func clear() -> void:
	for fx in live_effects():
		fx.queue_free()
	_alive.clear()
	HitFlash.clear()


func reduced_flash() -> bool:
	if reduced_flash_override >= 0:
		return reduced_flash_override == 1
	return bool(Settings.get_value(&"reduce_flash"))


## Seeds for effect randomness: sequential while manual_step (repeatable screenshots), random otherwise.
func next_seed() -> int:
	_seq += 1
	return _seq * 7919 if manual_step else randi()


func get_def(effect_id: StringName) -> EffectDef:
	return effects.get(effect_id)


func _track(effect_id: StringName, fx: FxEffect, max_alive: int) -> void:
	var list: Array = _alive.get(effect_id, [])
	list = list.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion())
	list.append(fx)
	while max_alive > 0 and list.size() > max_alive:
		var old: FxEffect = list.pop_front()
		old.queue_free()
	_alive[effect_id] = list


## Combo zones read their size and time from A's ComboDef (data/essences/combos/<id>.tres) so the
## picture matches the rule. Caller params still win.
func _combo_params(combo_id: StringName) -> Dictionary:
	if combo_id == &"":
		return {}
	var path := "res://data/essences/combos/%s.tres" % combo_id
	if not ResourceLoader.exists(path):
		return {}
	var combo := load(path)
	var out: Dictionary = {}
	if combo != null and &"effect_params" in combo:
		out = (combo.get(&"effect_params") as Dictionary).duplicate()
	return out


func _load_effects() -> void:
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		var f := file.trim_suffix(".remap")
		if not f.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [EFFECTS_DIR, f]) as EffectDef
		if def != null and def.id != &"":
			effects[def.id] = def
