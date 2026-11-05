extends Node3D
## Loads the player's character model at runtime and animates it from the player's state.
## player.tscn has no hard dependency on the private assets/ submodule: when the model or the
## animation library is missing (CI, clones without asset access) the sibling Greybox stays visible
## and nothing is animated.
##
## Clips come from res://assets/characters/anims/humanoid.res (tools/build_humanoid_anims.gd); root
## motion is already removed there. An AnimationTree built here blends them:
##
##   free_loco  BlendSpace1D  idle .. crouched walk (bare hands / melee)
##   aim_loco   BlendSpace2D  aim_rifle + 4 walks   (any gun: walk by direction to the cursor)
##   stance     Blend2        free <-> aim, eased so switching weapons doesn't pop
##   reload     OneShot       upper body only, so legs keep walking
##   shoot      OneShot       upper body only
##   dodge      OneShot       full body, time-scaled to the dodge length
##   life       Transition    alive / downed
##
## Sprint plays the same walks faster (user decision 2026-11-06, no separate run clip): with a gun
## the body faces the cursor while sprinting any direction, and only the walks exist for every
## direction.

## Model scene under res://assets/. Imported facing +Z; the player faces -Z.
@export_file("*.fbx", "*.glb", "*.tscn") var model_path := "res://assets/characters/hero/hero.fbx"
@export_file("*.res", "*.tres") var library_path := "res://assets/characters/anims/humanoid.res"
## Drawn larger than life so the hero reads from the top-down camera (user feedback 2026-11-06).
## Collision is the player's capsule and does not change.
@export var model_scale := 1.3
## Animation playback multipliers and limits (live-tunable with the \ key in debug builds).
@export var anim_tuning: PlayerAnimTuning = preload("res://data/classes/player_anim_tuning.tres")
## Node shown when the model can't be loaded.
@export var fallback: NodePath = ^"../Greybox"

const LIB := &"humanoid"
const SKELETON := "Armature/Skeleton3D"
## Bones driven by the upper-body one-shots (shoot, reload): the spine and everything above it.
const UPPER_ROOT := "mixamorig_Spine"

## Below this ground speed (m/s) the body counts as standing.
const MOVE_EPSILON := 0.3
## Ground speed at which the locomotion blend reaches the full walk.
const FULL_WALK_SPEED := 0.9
## Exponential easing rates (higher = snappier).
const BLEND_SHARPNESS := 12.0
const STANCE_SHARPNESS := 8.0
const TURN_SHARPNESS := 16.0
const SPEED_SHARPNESS := 10.0
## Crossfades (seconds).
const DODGE_FADE_IN := 0.05
const DODGE_FADE_OUT := 0.15
const UPPER_FADE := 0.12
const DOWNED_FADE := 0.25
## A single shot keeps the firing pose this long before easing back.
const SHOT_HOLD_SEC := 0.3
## Where shots are drawn from (muzzle flash, tracers): this hand bone, pushed this far along the aim.
## The hitscan itself stays at CombatTuning.muzzle_height (cover rules use that height).
const MUZZLE_BONE := "mixamorig_RightHand"
const MUZZLE_AHEAD := 0.3

## A gun weapon shows its model (PlayerModelGuns) in the right hand: it follows MUZZLE_BONE every
## time the skeleton is posed, with the barrel along the body's facing.

var _model: Node3D
var _tree: AnimationTree
var _player: Player
var _weapons: WeaponHolder
var _native := {}  # clip name -> native_speed (m/s)
var _free_blend := 0.0
var _aim_blend := Vector2.ZERO
var _stance := 0.0
var _speed_scale := 1.0
var _model_yaw := 0.0  # world yaw of the model, eased toward the player's
var _was_dodging := false
var _shot_left := 0.0
var _hand := -2  # bone index of MUZZLE_BONE, -2 = not looked up yet, -1 = missing
var _skeleton: Skeleton3D
var _gun: Node3D  # the held gun model, null when the active weapon isn't a gun
var _gun_id: StringName
var _gun_spec := {}
var _gun_units := 1.0  # the gun model's length along +X in its own units


func _ready() -> void:
	_player = get_parent() as Player
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return
	var scene := load(model_path) as PackedScene
	if scene == null:
		return
	_model = scene.instantiate() as Node3D
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * model_scale
	add_child(_model)
	var fb := get_node_or_null(fallback) as Node3D
	if fb != null:
		fb.visible = false
	_setup_animation()
	_setup_gun()


func _setup_animation() -> void:
	if _player == null or library_path.is_empty() or not ResourceLoader.exists(library_path):
		return
	var lib := load(library_path) as AnimationLibrary
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if lib == null or players.is_empty():
		return
	var anim_player := players[0] as AnimationPlayer
	anim_player.add_animation_library(LIB, lib)
	for clip in lib.get_animation_list():
		_native[String(clip)] = float(lib.get_animation(clip).get_meta(&"native_speed", 0.0))
	_tree = AnimationTree.new()
	_tree.name = &"AnimationTree"
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(anim_player)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.tree_root = _build_tree(_upper_body_paths())
	_tree.active = true
	_model_yaw = _player.global_rotation.y
	_weapons = _player.get_node_or_null(^"Weapons") as WeaponHolder
	if _weapons != null:
		_weapons.attacked.connect(_on_attacked)
		_weapons.reload_started.connect(_on_reload_started)


func _process(delta: float) -> void:
	if _tree == null:
		return
	if _player.is_downed:
		_tree.set(&"parameters/life/transition_request", "downed")
		return
	_tree.set(&"parameters/life/transition_request", "alive")
	var ground := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var speed := ground.length()
	var dodging := _player.move_state == Player.MoveState.DODGE
	_step_dodge(dodging)
	_step_turn(delta, ground if dodging else Vector3.ZERO)

	var gun := _holding_gun()
	var k := 1.0 - exp(-BLEND_SHARPNESS * delta)
	var amount := clampf(speed / FULL_WALK_SPEED, 0.0, 1.0)
	_free_blend = lerpf(_free_blend, amount, k)
	# Move direction in body space: x right, y forward.
	var local := _player.global_basis.inverse() * ground
	var dir := Vector2(local.x, -local.z).normalized() if speed > MOVE_EPSILON else Vector2.ZERO
	_aim_blend = _aim_blend.lerp(dir * amount, k)
	_stance = lerpf(_stance, 1.0 if gun else 0.0, 1.0 - exp(-STANCE_SHARPNESS * delta))
	var want_scale := _walk_scale(speed, dir if gun else Vector2.UP) * _move_mult()
	if gun:
		want_scale *= lerpf(1.0, anim_tuning.back_walk_mult, maxf(-dir.y, 0.0))
	_speed_scale = lerpf(_speed_scale, want_scale, 1.0 - exp(-SPEED_SHARPNESS * delta))

	_tree.set(&"parameters/free_loco/blend_position", _free_blend)
	_tree.set(&"parameters/aim_loco/blend_position", _aim_blend)
	_tree.set(&"parameters/stance/blend_amount", _stance)
	_tree.set(&"parameters/free_speed/scale", lerpf(1.0, _speed_scale, _free_blend))
	_tree.set(&"parameters/aim_speed/scale", lerpf(1.0, _speed_scale, minf(_aim_blend.length(), 1.0)))

	if _shot_left > 0.0:
		_shot_left -= delta
		if _shot_left <= 0.0:
			_tree.set(&"parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _step_dodge(dodging: bool) -> void:
	if dodging and not _was_dodging:
		var length := _clip_length("dodge")
		_tree.set(&"parameters/dodge_speed/scale",
				length / maxf(_player.stats.dodge_duration_sec, 0.05) * anim_tuning.dodge_mult)
		_tree.set(&"parameters/dodge/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_was_dodging = dodging


## Eases the model's yaw toward the player's facing (or the roll direction while dodging), so the
## player body's instant turns read as a quick turn instead of a snap.
func _step_turn(delta: float, override_dir: Vector3) -> void:
	var target := _player.global_rotation.y
	if override_dir.length_squared() > 0.0001:
		target = atan2(-override_dir.x, -override_dir.z)
	_model_yaw = lerp_angle(_model_yaw, target, 1.0 - exp(-TURN_SHARPNESS * delta))
	# The model faces +Z and the player -Z (add PI); the model is the player's child, so undo its yaw.
	_model.rotation.y = _model_yaw - _player.global_rotation.y + PI


## Playback scale so the feet roughly match the ground speed. dir: unit move direction in body
## space (x right, y forward).
func _walk_scale(speed: float, dir: Vector2) -> float:
	if speed < MOVE_EPSILON:
		return 1.0
	var native: float
	if _stance > 0.5:
		var fb: float = _native.get("aim_walk_forward" if dir.y >= 0.0 else "aim_walk_back", 1.0)
		var lr: float = _native.get("aim_strafe_right" if dir.x >= 0.0 else "aim_strafe_left", 1.0)
		var wf := absf(dir.y)
		var wr := absf(dir.x)
		native = (fb * wf + lr * wr) / maxf(wf + wr, 0.001)
	else:
		native = _native.get("walk", 1.0)
	if native <= 0.0:
		return 1.0
	var top := anim_tuning.max_playback
	if _player.move_state == Player.MoveState.SPRINT:
		top = anim_tuning.sprint_max_playback
	return clampf(speed / native, anim_tuning.min_playback, top)


## The tuning multiplier for the current move: sprint or walk, the same with or without a gun
## (user decision 2026-11-06).
func _move_mult() -> float:
	if _player.move_state == Player.MoveState.SPRINT:
		return anim_tuning.sprint_mult
	return anim_tuning.walk_mult


## Current walk playback speed (1.0 = clip speed). For the debug panel (\ key).
func walk_playback() -> float:
	return _speed_scale


func _clip_length(clip: String) -> float:
	var ap := _tree.get_node(_tree.anim_player) as AnimationPlayer
	return ap.get_animation(LIB + "/" + clip).length


## World point the shot is drawn from: the held gun's barrel tip, else the hand + MUZZLE_AHEAD
## along `forward`, or null without a model.
func muzzle_point(forward: Vector3) -> Variant:
	if _model == null:
		return null
	if _gun != null and _gun.visible:
		return _gun.global_transform * (_gun_spec["muzzle"] as Vector3)
	var skeleton := _model.get_node_or_null(SKELETON) as Skeleton3D
	if skeleton == null:
		return null
	if _hand == -2:
		_hand = skeleton.find_bone(MUZZLE_BONE)
	if _hand < 0:
		return null
	return skeleton.global_transform * skeleton.get_bone_global_pose(_hand).origin + forward * MUZZLE_AHEAD


## Rifle stance with any gun in hand (pistol included). Bare hands or a melee weapon use the plain
## idle / crouched walk and no rifle shoot / reload poses, even while right-click aiming / blocking
## (user decision 2026-11-06).
func _holding_gun() -> bool:
	return _weapons != null and WeaponHolder.is_gun(_weapons.current_stats())


# --- held gun -----------------------------------------------------------------------------------

func _setup_gun() -> void:
	_skeleton = _model.get_node_or_null(SKELETON) as Skeleton3D
	if _skeleton == null or _player == null:
		return
	_skeleton.skeleton_updated.connect(_place_gun)
	var weapons := _player.get_node_or_null(^"Weapons") as WeaponHolder
	if weapons != null:
		weapons.weapon_changed.connect(func(_slot: Enums.EquipSlot, uid: StringName) -> void: _hold(uid))
		_hold.call_deferred(weapons.current_uid())


## Shows the model for the item `uid` in the hand, or nothing when it isn't a gun.
func _hold(uid: StringName) -> void:
	var stats: Dictionary = Armory.get_item_stats(uid) if uid != &"" else {}
	var id := &""
	if WeaponHolder.is_gun(stats):
		var item := Armory.get_item(uid)
		id = PlayerModelGuns.id_for(item.def_id if item != null else &"")
	if id == _gun_id and (_gun != null) == (id != &""):
		return
	if _gun != null:
		_gun.queue_free()
		_gun = null
	_gun_id = id
	if id == &"":
		return
	var scene := PlayerModelGuns.scene_of(id)
	if scene == null:
		return
	_gun_spec = PlayerModelGuns.GUNS[id]
	_gun_units = PlayerModelGuns.length_units(id)
	_gun = scene.instantiate() as Node3D
	_gun.name = &"HeldGun"
	_gun.top_level = true  # placed in world space by _place_gun, so the hand's scale doesn't stack
	add_child(_gun)
	_place_gun()


## Puts the gun's grip in the right hand with the barrel along the body's facing (level), after the
## animation has posed the skeleton. Hidden while downed.
func _place_gun() -> void:
	if _gun == null or _skeleton == null:
		return
	_gun.visible = not _player.is_downed
	if not _gun.visible:
		return
	if _hand == -2:
		_hand = _skeleton.find_bone(MUZZLE_BONE)
	if _hand < 0:
		return
	var hand := _skeleton.global_transform * _skeleton.get_bone_global_pose(_hand).origin
	# The model is imported facing +Z.
	var forward := Vector3(_model.global_basis.z.x, 0.0, _model.global_basis.z.z).normalized()
	if forward.length_squared() < 0.5:
		return
	var s: float = float(_gun_spec["length"]) * model_scale / _gun_units
	var b := Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).scaled(Vector3.ONE * s)
	var grip := hand + (forward * PlayerModelGuns.HOLD_AHEAD - Vector3.UP * PlayerModelGuns.HOLD_DROP) * model_scale
	_gun.global_transform = Transform3D(b, grip - b * (_gun_spec["grip"] as Vector3))


func _on_attacked(kind: StringName, _combo_step: int) -> void:
	if kind != &"shot" or _tree == null or not _holding_gun():
		return
	_tree.set(&"parameters/shoot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_shot_left = SHOT_HOLD_SEC


func _on_reload_started(duration_sec: float) -> void:
	if _tree == null or not _holding_gun():
		return
	_tree.set(&"parameters/reload_speed/scale", _clip_length("reload") / maxf(duration_sec, 0.1))
	_tree.set(&"parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# --- tree ---------------------------------------------------------------------------------------

func _upper_body_paths() -> Array[NodePath]:
	var out: Array[NodePath] = []
	var skel := _model.get_node_or_null(SKELETON) as Skeleton3D
	if skel == null:
		return out
	var root := skel.find_bone(UPPER_ROOT)
	if root < 0:
		return out
	var stack: Array[int] = [root]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(NodePath("%s:%s" % [SKELETON, skel.get_bone_name(b)]))
		for c in skel.get_bone_children(b):
			stack.append(c)
	return out


func _clip(clip: String) -> AnimationNodeAnimation:
	var n := AnimationNodeAnimation.new()
	n.animation = StringName(LIB + "/" + clip)
	return n


func _build_tree(upper: Array[NodePath]) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()

	var free := AnimationNodeBlendSpace1D.new()
	free.min_space = 0.0
	free.max_space = 1.0
	free.add_blend_point(_clip("idle"), 0.0, -1, &"idle")
	free.add_blend_point(_clip("walk"), 1.0, -1, &"walk")
	bt.add_node(&"free_loco", free)
	bt.add_node(&"free_speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"free_speed", 0, &"free_loco")

	var aim := AnimationNodeBlendSpace2D.new()
	aim.min_space = Vector2(-1, -1)
	aim.max_space = Vector2(1, 1)
	aim.add_blend_point(_clip("aim_rifle"), Vector2.ZERO, -1, &"aim_rifle")
	aim.add_blend_point(_clip("aim_walk_forward"), Vector2(0, 1), -1, &"aim_walk_forward")
	aim.add_blend_point(_clip("aim_walk_back"), Vector2(0, -1), -1, &"aim_walk_back")
	aim.add_blend_point(_clip("aim_strafe_right"), Vector2(1, 0), -1, &"aim_strafe_right")
	aim.add_blend_point(_clip("aim_strafe_left"), Vector2(-1, 0), -1, &"aim_strafe_left")
	bt.add_node(&"aim_loco", aim)
	bt.add_node(&"aim_speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"aim_speed", 0, &"aim_loco")

	bt.add_node(&"stance", AnimationNodeBlend2.new())
	bt.connect_node(&"stance", 0, &"free_speed")
	bt.connect_node(&"stance", 1, &"aim_speed")

	var last := &"stance"
	for spec: Array in [["reload", "reload"], ["shoot", "shoot_rifle"]]:
		var node := StringName(spec[0])
		var clip_node := StringName(spec[0] + "_clip")
		var speed_node := StringName(spec[0] + "_speed")
		var one := _one_shot(UPPER_FADE, UPPER_FADE)
		one.filter_enabled = true
		for p in upper:
			one.set_filter_path(p, true)
		bt.add_node(clip_node, _clip(spec[1]))
		bt.add_node(speed_node, AnimationNodeTimeScale.new())
		bt.connect_node(speed_node, 0, clip_node)
		bt.add_node(node, one)
		bt.connect_node(node, 0, last)
		bt.connect_node(node, 1, speed_node)
		last = node

	bt.add_node(&"dodge_clip", _clip("dodge"))
	bt.add_node(&"dodge_speed", AnimationNodeTimeScale.new())
	bt.connect_node(&"dodge_speed", 0, &"dodge_clip")
	bt.add_node(&"dodge", _one_shot(DODGE_FADE_IN, DODGE_FADE_OUT))
	bt.connect_node(&"dodge", 0, last)
	bt.connect_node(&"dodge", 1, &"dodge_speed")

	var life := AnimationNodeTransition.new()
	life.xfade_time = DOWNED_FADE
	life.add_input("alive")
	life.add_input("downed")
	bt.add_node(&"life", life)
	bt.add_node(&"downed_clip", _clip("downed"))
	bt.connect_node(&"life", 0, &"dodge")
	bt.connect_node(&"life", 1, &"downed_clip")

	bt.connect_node(&"output", 0, &"life")
	return bt


func _one_shot(fade_in: float, fade_out: float) -> AnimationNodeOneShot:
	var one := AnimationNodeOneShot.new()
	one.fadein_time = fade_in
	one.fadeout_time = fade_out
	one.mix_mode = AnimationNodeOneShot.MIX_MODE_BLEND
	return one
