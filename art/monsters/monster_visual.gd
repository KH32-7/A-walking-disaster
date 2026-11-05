class_name MonsterVisual
extends Node3D
## D-17 monster look: the rigged model from assets/monsters, re-skinned with the toon material, and an
## AnimationPlayer driven only by the parent monster's public state (signals + velocity). Owner: Lane D.
## Lane B never touches the model: the Monster finds res://art/monsters/<def.id>.tscn and adds it as
## its "Visual" child (field/monsters/monster_base.gd). Clip names come from assets/monsters/README.md.
##
## Signals read from the parent (all optional, so the scene also runs in previews):
##   state_changed(old, new)  attack_started(info)  damaged(amount, info)  died(monster)
##   pattern_started(id)  (bosses)
## Movement clip is picked from the parent's horizontal speed each frame.
## On a kill (died with hp <= 0) the visual leaves the monster as a corpse: monster_death burst, Death
## clip, a short hold, then it sinks into the ground and frees itself. vanish() (moth blast) leaves none.

## The model scene (an imported .glb). Its front is glTF +Z; the monster looks down -Z, so it is turned.
@export var model: PackedScene
## Extra scale on top of the model's own metres (models are authored at their design size).
@export var model_scale := 1.0
## Lifts or shifts the model (flyers hover at their collision height).
@export var model_offset := Vector3.ZERO
## Clip for attack_started (spore pod Shoot, neon moth Explode, serpent TailSwing).
@export var attack_clip := &"Attack"
## Boss pattern id -> clip name (falls back to "Attack").
@export var pattern_clips: Dictionary = {}
## Below this horizontal speed (m/s) the monster counts as standing still.
@export var still_speed := 0.12

const TOON := preload("res://art/materials/toon_default.tres")
const LOOPED := [&"Idle", &"Walk", &"Run", &"Move", &"Swim", &"Fly", &"Freeze"]
const MOVE_CLIPS := [&"Walk", &"Move", &"Swim", &"Fly"]
const BLEND := 0.18
const CORPSE_HOLD := 0.6
const CORPSE_SINK := 0.5

var anim: AnimationPlayer
var _monster: Node3D
var _locked := false   # a one-shot (attack, hit, wake...) is playing
var _dead := false
var _frozen := false
var _size := Vector3.ONE


func _ready() -> void:
	if model == null:
		return
	var inst := model.instantiate()
	inst.name = "Model"
	inst.rotation.y = PI
	inst.scale = Vector3.ONE * model_scale
	inst.position = model_offset
	add_child(inst)
	_apply_toon(inst)
	_size = _measure(inst) * model_scale
	anim = _find_anim(inst)
	if anim:
		for clip in anim.get_animation_list():
			var a := anim.get_animation(clip)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR if StringName(clip) in LOOPED else Animation.LOOP_NONE
		anim.animation_finished.connect(_on_finished)
		_play(&"Idle")
	_monster = get_parent() as Node3D
	if _monster:
		_connect(&"state_changed", _on_state_changed)
		_connect(&"attack_started", _on_attack_started)
		_connect(&"damaged", _on_damaged)
		_connect(&"died", _on_died)
		_connect(&"pattern_started", _on_pattern_started)


func has_clip(clip: StringName) -> bool:
	return anim != null and anim.has_animation(clip)


func current_clip() -> StringName:
	return anim.current_animation if anim else &""


func _process(_delta: float) -> void:
	if anim == null or _dead or _locked or _monster == null:
		return
	var v: Vector3 = _monster.get("velocity") if "velocity" in _monster else Vector3.ZERO
	var speed := Vector2(v.x, v.z).length()
	var st: int = int(_monster.get("state")) if "state" in _monster else -1
	if has_clip(&"Freeze"):   # statue: frozen until a noise wakes it
		var quiet := speed < still_speed and st in [Enums.AIState.SLEEP, Enums.AIState.WANDER, Enums.AIState.RETURN]
		if quiet:
			_frozen = true
			_play(&"Freeze")
			return
		if _frozen and has_clip(&"Wake"):
			_frozen = false
			_one_shot(&"Wake")
			return
		_frozen = false
	if speed < still_speed:
		_play(&"Idle")
	elif st == Enums.AIState.CHASE and has_clip(&"Run"):
		_play(&"Run")
	else:
		for c in MOVE_CLIPS:
			if has_clip(c):
				_play(c)
				return
		_play(&"Idle")


func _on_state_changed(_old: int, new_state: int) -> void:
	if new_state == Enums.AIState.CHASE and has_clip(&"Scream") and not _dead:
		_one_shot(&"Scream")   # spore pod: the alarm scream when it spots you
	elif new_state == Enums.AIState.CHASE and has_clip(&"Rise") and not _locked and not _dead:
		_one_shot(&"Rise")     # serpent rears up before it comes at you


func _on_attack_started(_info: Dictionary = {}) -> void:
	if _dead:
		return
	_one_shot(attack_clip if has_clip(attack_clip) else &"Attack")


func _on_pattern_started(id: StringName) -> void:
	if _dead:
		return
	var clip: StringName = pattern_clips.get(id, &"Attack")
	_one_shot(clip if has_clip(clip) else &"Attack")


func _on_damaged(amount: float, _info: Dictionary = {}) -> void:
	if _dead or amount <= 0.0 or not has_clip(&"Hit"):
		return
	if _locked and current_clip() != &"Hit":
		return   # never cut an attack short for a flinch
	_one_shot(&"Hit")


func _on_died(_m = null) -> void:
	_dead = true
	var killed := _monster != null and "hp" in _monster and float(_monster.get("hp")) <= 0.0
	var world := _monster.get_parent() if _monster else null
	if not killed or world == null:
		return
	var def: Resource = _monster.get("def") if "def" in _monster else null
	var family: int = int(def.get("family")) if def and "family" in def else Enums.Element.NONE
	Fx.spawn(&"monster_death", global_position, {"element": family,
		"radius": clampf(maxf(_size.x, _size.z) * 0.5, 0.4, 3.5)})
	if not has_clip(&"Death"):
		return
	reparent(world, true)
	anim.play(&"Death", BLEND)
	var tw := create_tween()
	tw.tween_interval(anim.get_animation(&"Death").length + CORPSE_HOLD)
	tw.tween_property(self, ^"position:y", position.y - _size.y, CORPSE_SINK)
	tw.tween_callback(queue_free)


func _on_finished(_clip: StringName) -> void:
	if _dead:
		return
	_locked = false


func _one_shot(clip: StringName) -> void:
	if not has_clip(clip):
		return
	_locked = true
	anim.stop()
	anim.play(clip, BLEND)


func _play(clip: StringName) -> void:
	if not has_clip(clip):
		return
	if anim.current_animation != clip:
		anim.play(clip, BLEND)


func _connect(sig: StringName, call: Callable) -> void:
	if _monster.has_signal(sig) and not _monster.is_connected(sig, call):
		_monster.connect(sig, call)


## Rest-pose bounds of every mesh under `root`, in root space (metres before model_scale).
static func _measure(root: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D()
		var p: Node = mi
		while p != null and p != root:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var b := t * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size if not first else Vector3.ONE


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


## Every surface gets the toon material with the model's own albedo texture (outline pass included).
static func _apply_toon(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var src := mi.get_active_material(s)
				var tex: Texture2D = null
				if src is BaseMaterial3D:
					tex = (src as BaseMaterial3D).albedo_texture
				var mat := TOON.duplicate() as ShaderMaterial
				mat.set_shader_parameter(&"albedo", Color.WHITE)
				if tex:
					mat.set_shader_parameter(&"albedo_texture", tex)
				mi.set_surface_override_material(s, mat)
	for c in n.get_children():
		_apply_toon(c)
