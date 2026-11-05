class_name ResidentModel
extends Node3D
## Pack character model for a resident: rescue target, field companion, base resident.
## Owner: Lane D. B (RescueTarget, FieldCompanion) and C (ResidentAgent) add one and call
## show_resident(); they never touch the meshes.
##
## pick() chooses the model from resident data (age, gender, access needs, former job, rescue
## walking style). show_resident() loads it at runtime, so no scene depends on the private
## assets/ submodule: without it (CI, clones without access) it returns false and the caller
## keeps its greybox. Plays idle / walk from how fast this node moves.
##
## Models: City People Free Samples and People with Disabilities (assets/LICENSES.md), same rig.
## City People models have no animations of their own: idle / walk come from Animations.fbx/,
## with bone position keys scaled to the model's bones (the child would float otherwise).
## A disability model goes only to someone whose data has that need or walking style.

const CITY := "res://assets/characters/city_people_free/"
const DISABLED := "res://assets/characters/people_with_disabilities/rig-animated-fbx/"
const ANIMS := CITY + "Animations.fbx/"

const WHEELCHAIR_M := DISABLED + "wheelchair_man_ani.fbx"
const WHEELCHAIR_F := DISABLED + "wheelchair_teen_ani.fbx"
const CANE_M := DISABLED + "cane_man_ani.fbx"
const CRUTCHES_M := DISABLED + "crutches_man_ani.fbx"
const CRUTCHES_F := DISABLED + "crutches_woman_ani.fbx"
const CHILD := CITY + "little_boy_B.fbx"
const ELDER_F := CITY + "elder_Female_A.fbx"
const POLICE_F := CITY + "police_Female_A.fbx"
const DOCTOR_M := CITY + "Doctor_Male_B.fbx"
const WORKER_M := CITY + "worker_Male_constructor_B.fbx"
const CASUAL_F: Array[String] = [CITY + "casual_Female_G.fbx", CITY + "casual_Female_K.fbx"]
const CASUAL_M: Array[String] = [CITY + "casual_Male_G.fbx", CITY + "casual_Male_K.fbx"]
const DOCTOR_JOBS: Array[StringName] = [&"doctor", &"nurse"]
const WORKER_JOBS: Array[StringName] = [&"carpenter", &"mechanic", &"electrician", &"farmer", &"laborer"]

## City People animation files per body: [idle, walk].
const ANIM_F: Array[String] = ["idle_f_1_150f", "locom_f_basicWalk_30f"]
const ANIM_M: Array[String] = ["idle_m_1_200f", "locom_m_basicWalk_30f"]
const ANIM_ELDER_F: Array[String] = ["idle_f_2_190f", "locom_f_slowWalk_40f"]
const FEMALE_MODELS: Array[String] = [ELDER_F, POLICE_F, CITY + "casual_Female_G.fbx", CITY + "casual_Female_K.fbx"]
## Clip names inside the People with Disabilities files.
const DISABLED_IDLE := &"idle"
const DISABLED_WALK := &"forward"
const IDLE := &"idle"
const WALK := &"walk"
const LIBRARY := &"resident"

## Teens wear adult models a little smaller; babies the child model smaller.
const TEEN_SCALE := 0.92
const BABY_SCALE := 0.6
## Moving faster than this (m/s, flat) plays walk.
const WALK_SPEED := 0.3
const BLEND_SEC := 0.2

## Node hidden once a model is shown (the caller's greybox). Empty = none.
@export var fallback: NodePath = ^"../Greybox"

var _path := ""
var _model: Node3D
var _player: AnimationPlayer
var _idle: StringName = &""
var _walk: StringName = &""
var _last_pos := Vector3.INF

## model path -> AnimationLibrary built for that model (City People only).
static var _libraries: Dictionary = {}


## Model file for a resident (ResidentData fields; a rescue profile works too).
## move_type: RescueSpawn.Move in the field, -1 at the base (then access_needs decide).
static func pick(r: Dictionary, move_type := -1) -> String:
	var female := gender_of(r) == ResidentData.GENDER_FEMALE
	var age := int(r.get("age_stage", Enums.AgeStage.ADULT))
	var elder := age == Enums.AgeStage.ELDER
	var young := age <= Enums.AgeStage.TEEN
	var needs: Array = r.get("access_needs", [])
	var mobility := Enums.AccessNeed.MOBILITY in needs
	var wheelchair := move_type == RescueSpawn.Move.WHEELCHAIR or (move_type < 0 and mobility and not elder)
	if wheelchair:
		return WHEELCHAIR_F if female or young else WHEELCHAIR_M
	var walking_aid := move_type == RescueSpawn.Move.SUPPORTED or move_type == RescueSpawn.Move.SLOW
	if (mobility or walking_aid) and age > Enums.AgeStage.CHILD:
		if female:
			return CRUTCHES_F
		return CANE_M if elder else CRUTCHES_M
	if age <= Enums.AgeStage.CHILD:
		return CHILD
	if elder and female:
		return ELDER_F
	var job := StringName(r.get("former_job", &""))
	if female and job == &"police":
		return POLICE_F
	if not female and DOCTOR_JOBS.has(job):
		return DOCTOR_M
	if not female and WORKER_JOBS.has(job):
		return WORKER_M
	var casual := CASUAL_F if female else CASUAL_M
	return casual[_id_hash(r) % casual.size()]


## The resident's gender, or one fixed by id when the data has none (rescue profiles), so the
## field and the base agree. RescueManager stores it in the profile before the rescue.
static func gender_of(r: Dictionary) -> StringName:
	var g := StringName(r.get("gender", &""))
	if ResidentData.GENDERS.has(g):
		return g
	return ResidentData.GENDERS[_id_hash(r) % ResidentData.GENDERS.size()]


## Size for the age stage (the models are adult or child sized already).
static func scale_for(r: Dictionary) -> float:
	match int(r.get("age_stage", Enums.AgeStage.ADULT)):
		Enums.AgeStage.BABY:
			return BABY_SCALE
		Enums.AgeStage.TEEN:
			return TEEN_SCALE
	return 1.0


## Shows the model for `r`. False when the model file is missing (the fallback stays).
## Calling again with data that picks the same model does nothing.
func show_resident(r: Dictionary, move_type := -1) -> bool:
	var path := pick(r, move_type)
	if path == _path and _model != null:
		_model.scale = Vector3.ONE * scale_for(r)
		return true
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	clear()
	_path = path
	_model = scene.instantiate() as Node3D
	# Imported facing +Z; our bodies face -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * scale_for(r)
	add_child(_model)
	_setup_animation()
	var fb := get_node_or_null(fallback) as Node3D
	if fb != null:
		fb.visible = false
	return true


## Removes the model and shows the fallback again.
func clear() -> void:
	if _model != null:
		remove_child(_model)
		_model.queue_free()
	_model = null
	_player = null
	_path = ""
	var fb := get_node_or_null(fallback) as Node3D
	if fb != null:
		fb.visible = true


func model_path() -> String:
	return _path


func has_model() -> bool:
	return _model != null


## &"idle", &"walk" or &"" (no model / no animation).
func current_motion() -> StringName:
	if _player == null:
		return &""
	return WALK if _player.current_animation == _walk else IDLE


func _process(delta: float) -> void:
	if _player == null or delta <= 0.0:
		return
	var pos := global_position
	var speed := 0.0
	if _last_pos != Vector3.INF:
		speed = Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / delta
	_last_pos = pos
	var want := _walk if speed > WALK_SPEED else _idle
	if _player.current_animation != want:
		_player.play(want, BLEND_SEC)


func _setup_animation() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_player = players[0] as AnimationPlayer
	if _path.begins_with(DISABLED):
		if not _player.has_animation(DISABLED_IDLE) or not _player.has_animation(DISABLED_WALK):
			_player = null
			return
		_idle = DISABLED_IDLE
		_walk = DISABLED_WALK
		for n in [_idle, _walk]:
			_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	else:
		var lib := _library_for(_path, _model)
		if lib == null:
			_player = null
			return
		if _player.has_animation_library(LIBRARY):
			_player.remove_animation_library(LIBRARY)
		_player.add_animation_library(LIBRARY, lib)
		_idle = StringName("%s/%s" % [LIBRARY, IDLE])
		_walk = StringName("%s/%s" % [LIBRARY, WALK])
	_player.play(_idle)


## idle / walk for one City People model, built once and shared by every resident wearing it.
static func _library_for(path: String, model: Node) -> AnimationLibrary:
	if _libraries.has(path):
		return _libraries[path]
	var names := ANIM_M
	if path == ELDER_F:
		names = ANIM_ELDER_F
	elif FEMALE_MODELS.has(path):
		names = ANIM_F
	var skel := _skeleton(model)
	if skel == null:
		return null
	var lib := AnimationLibrary.new()
	for i in 2:
		var anim := _retargeted(ANIMS + names[i] + ".fbx", skel)
		if anim == null:
			return null
		lib.add_animation(IDLE if i == 0 else WALK, anim)
	_libraries[path] = lib
	return lib


## The clip of an animation file, fitted to `skel`: tracks for bones the model lacks are dropped,
## bone position keys are scaled by the model's bone length over the clip rig's.
static func _retargeted(file: String, skel: Skeleton3D) -> Animation:
	if not ResourceLoader.exists(file):
		return null
	var scene := load(file) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	var src_skel := _skeleton(root)
	var anim: Animation = null
	if not players.is_empty() and src_skel != null:
		var p := players[0] as AnimationPlayer
		var list := p.get_animation_list()
		if not list.is_empty():
			anim = p.get_animation(list[0]).duplicate(true) as Animation
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := String(anim.track_get_path(t).get_concatenated_subnames())
			var to := skel.find_bone(bone)
			if to < 0:
				anim.remove_track(t)
				continue
			if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
				continue
			var from := src_skel.find_bone(bone)
			var src_len := src_skel.get_bone_rest(from).origin.length() if from >= 0 else 0.0
			var k := skel.get_bone_rest(to).origin.length() / src_len if src_len > 0.0001 else 1.0
			if is_equal_approx(k, 1.0):
				continue
			for key in anim.track_get_key_count(t):
				anim.track_set_key_value(t, key, (anim.track_get_key_value(t, key) as Vector3) * k)
	root.free()
	return anim


static func _skeleton(root: Node) -> Skeleton3D:
	var skels := root.find_children("*", "Skeleton3D", true, false)
	for s in skels:
		if (s as Skeleton3D).get_bone_count() > 1:
			return s
	return null


static func _id_hash(r: Dictionary) -> int:
	return absi(String(r.get("id", "")).hash())
