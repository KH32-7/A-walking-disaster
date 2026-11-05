extends Node
## Autoload `Fx` (D-18). Owner: Lane D.
## Gameplay calls `Fx.spawn(&"hit_spark", position, {"element": Enums.Element.GREEN})` and never instances
## effects itself, so the look can change without touching gameplay.
##
## Effects are data: data/ui/effects/<id>.tres (FxDef + FxLayer list) built from the VFX packs in
## res://assets/vfx/. Without the assets submodule the effect is skipped silently (sound still plays).
## Unknown ids warn once. Damage numbers and hit flashes come from FxFeedback (no gameplay call needed).
## Fx never moves the camera (shake, hit-stop and knockback are Lane B's).

const EFFECTS_DIR := "res://data/ui/effects"

## Previews: -1 follow Settings.reduce_flash, 0 off, 1 on (never writes the settings file).
var reduced_flash_override := -1
var effects: Dictionary = {}  # StringName -> FxDef
var feedback: FxFeedback

var _alive: Dictionary = {}  # StringName -> Array[FxNode], oldest first
var _warned: Dictionary = {}


func _ready() -> void:
	_load_effects()
	feedback = FxFeedback.new()
	feedback.name = &"FxFeedback"
	add_child(feedback)
	# A finished sortie must not leave a swamp lying on the next map.
	EventBus.flow_state_changed.connect(func(_s: Enums.FlowState) -> void: clear())


func spawn(effect_id: StringName, position: Vector3, params: Dictionary = {}) -> void:
	spawn_node(effect_id, position, params)


## Same as spawn() but returns the effect, or null (unknown id, assets missing). Previews and tests.
func spawn_node(effect_id: StringName, position: Vector3, params: Dictionary = {}) -> FxNode:
	var def := _resolve(effect_id, params)
	if def == null:
		if not _warned.has(effect_id):
			_warned[effect_id] = true
			push_warning("Fx: unknown effect id '%s' (%s/)" % [effect_id, EFFECTS_DIR])
		return null
	if not is_inside_tree() or not position.is_finite():
		return null
	var snd := def.sound_crit if params.get("crit", false) and def.sound_crit != &"" else def.sound
	if snd != &"" and not params.get("silent", false):
		Audio.play(snd, position)
	var fx := FxNode.new()
	fx.name = String(def.id)
	add_child(fx)
	fx.global_position = position
	if not fx.build(def, params, reduced_flash()):
		fx.free()
		return null
	_track(def.id, fx, def.max_alive)
	return fx


func has_effect(effect_id: StringName) -> bool:
	return effects.has(effect_id)


func live_effects() -> Array[FxNode]:
	var out: Array[FxNode] = []
	for child in get_children():
		if child is FxNode and not child.is_queued_for_deletion():
			out.append(child)
	return out


func clear() -> void:
	for fx in live_effects():
		fx.queue_free()
	_alive.clear()


func reduced_flash() -> bool:
	if reduced_flash_override >= 0:
		return reduced_flash_override == 1
	return bool(Settings.get_value(&"reduce_flash"))


func _resolve(effect_id: StringName, params: Dictionary) -> FxDef:
	var def: FxDef = effects.get(effect_id)
	if def != null and def.variant_param != &"" and params.has(def.variant_param):
		var variant: FxDef = effects.get(StringName("%s_%s" % [effect_id, params[def.variant_param]]))
		if variant != null:
			return variant
	return def


func _track(effect_id: StringName, fx: FxNode, max_alive: int) -> void:
	var list: Array = _alive.get(effect_id, [])
	list = list.filter(func(n: Variant) -> bool: return is_instance_valid(n) and not n.is_queued_for_deletion())
	list.append(fx)
	while max_alive > 0 and list.size() > max_alive:
		(list.pop_front() as FxNode).queue_free()
	_alive[effect_id] = list


func _load_effects() -> void:
	var dir := DirAccess.open(EFFECTS_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [EFFECTS_DIR, name]) as FxDef
		if def == null or def.id == &"":
			push_warning("Fx: %s is not an FxDef with an id" % name)
			continue
		effects[def.id] = def
