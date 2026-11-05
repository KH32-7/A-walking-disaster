extends SceneTree
## Bakes the Mixamo FBX clips in res://assets/characters/anims/ into one AnimationLibrary
## (res://assets/characters/anims/humanoid.res) that the player model plays by name.
##
##   godot --headless --path . --script res://tools/build_humanoid_anims.gd
##
## Per clip: loop mode, optional trim, and root motion removed (Hips X/Z pinned to the first
## frame; Y kept so crouches, rolls and falls still read). The removed travel speed is stored as
## metadata "native_speed" (m/s) so the player can scale playback to its real speed.
## Needs the private assets/ submodule; does nothing useful without it.

const DIR := "res://assets/characters/anims/"
const OUT := DIR + "humanoid.res"
const HIPS := ^"Armature/Skeleton3D:mixamorig_Hips"
const FPS := 30.0

## file stem -> {loop, trim: [start, end] seconds, native_speed for clips filmed in place}
const CLIPS := {
	"idle": {"loop": true},
	"walk": {"loop": true, "native_speed": 1.3},  # Mixamo "Crouched Walking", in place
	"aim_rifle": {"loop": true},
	"aim_walk_forward": {"loop": true},
	"aim_walk_back": {"loop": true},
	"strafe_a": {"loop": true},  # moves to the character's right
	"strafe_b": {"loop": true},  # moves to the character's left
	"dodge": {"trim": [0.85, 2.05]},  # Mixamo "Stand To Roll": keep the roll only
	"reload": {},
	"shoot_rifle": {},
	"downed": {},
}
## Library names for the strafes (the FBX names don't say which side).
const RENAME := {"strafe_a": "aim_strafe_right", "strafe_b": "aim_strafe_left"}


func _init() -> void:
	var lib := AnimationLibrary.new()
	for stem: String in CLIPS:
		var path := DIR + stem + ".fbx"
		if not ResourceLoader.exists(path):
			printerr("missing ", path)
			continue
		var anim := _bake(path, CLIPS[stem])
		if anim != null:
			lib.add_animation(StringName(RENAME.get(stem, stem)), anim)
			print("%-18s len %.2fs  native_speed %.2f m/s" % [RENAME.get(stem, stem), anim.length,
					float(anim.get_meta(&"native_speed", 0.0))])
	var err := ResourceSaver.save(lib, OUT)
	print("saved ", OUT, " (", lib.get_animation_list().size(), " clips) err=", err)
	quit(0 if err == OK else 1)


func _bake(path: String, opts: Dictionary) -> Animation:
	var scene := load(path) as PackedScene
	var root := scene.instantiate()
	var players := root.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		root.free()
		return null
	var ap := players[0] as AnimationPlayer
	var src := ap.get_animation(ap.get_animation_list()[0])
	root.free()

	var anim := src.duplicate(true) as Animation
	var trim: Array = opts.get("trim", [])
	if not trim.is_empty():
		anim = _trimmed(src, trim[0], trim[1])
	anim.loop_mode = Animation.LOOP_LINEAR if opts.get("loop", false) else Animation.LOOP_NONE

	var native := float(opts.get("native_speed", 0.0))
	var hips := anim.find_track(HIPS, Animation.TYPE_POSITION_3D)
	if hips >= 0 and anim.track_get_key_count(hips) > 0:
		var first: Vector3 = anim.track_get_key_value(hips, 0)
		var last: Vector3 = anim.track_get_key_value(hips, anim.track_get_key_count(hips) - 1)
		var travel := Vector2(last.x - first.x, last.z - first.z).length()
		if native == 0.0 and anim.length > 0.0 and travel > 0.05:
			native = travel / anim.length
		for k in anim.track_get_key_count(hips):
			var p: Vector3 = anim.track_get_key_value(hips, k)
			anim.track_set_key_value(hips, k, Vector3(first.x, p.y, first.z))
	if native > 0.0:
		anim.set_meta(&"native_speed", native)
	return anim


## A copy of src between t0 and t1 (seconds), resampled at FPS and shifted to start at 0.
func _trimmed(src: Animation, t0: float, t1: float) -> Animation:
	var out := Animation.new()
	out.length = t1 - t0
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var nt := out.add_track(type)
		out.track_set_path(nt, src.track_get_path(t))
		out.track_set_interpolation_type(nt, src.track_get_interpolation_type(t))
		var steps := int(ceil(out.length * FPS))
		for i in steps + 1:
			var time := minf(i / FPS, out.length)
			match type:
				Animation.TYPE_POSITION_3D:
					out.position_track_insert_key(nt, time, src.position_track_interpolate(t, t0 + time))
				Animation.TYPE_ROTATION_3D:
					out.rotation_track_insert_key(nt, time, src.rotation_track_interpolate(t, t0 + time))
				Animation.TYPE_SCALE_3D:
					out.scale_track_insert_key(nt, time, src.scale_track_interpolate(t, t0 + time))
	return out
