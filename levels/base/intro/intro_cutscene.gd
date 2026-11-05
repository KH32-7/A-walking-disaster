class_name IntroCutscene
extends Node3D
## New-game intro (사용자 요청 2026-11-06), run by base_school on a new game until the hero walks out
## of the 낡은 집 again:
##   1. Black, radio static: the 방송실 지기's broadcast.
##   2. Cinematic: dawn over the clearing, the hero runs up the dirt road with swamp blobs bounding
##      after him, dives into the house and slams the door; the blobs splat against it.
##   3. Title card, then inside the house (IntroHouse): the hero catches his breath.
##   4. Play: open the case (spotlight) → take the 권총 → equip it → talk to the injured 한도윤 →
##      walk out. The steps and spotlights are IntroTutorial's (UI.tutorial); this scene builds the
##      places, runs the camera and the talk, and sets the flags it checks.
## Hold Esc during 1–3 to skip to 4. Owner: Lane D (presentation) with base_school (Lane C).

const GROUP := &"intro_cutscene"
const FLAG_PENDING := &"intro_pending"  # set by SceneRouter.start_new_game
const FLAG_HOUSE_DONE := &"intro_house_done"  # walked out of the house
const FLAG_TALKED := &"intro_talked"  # 한도윤 asked for the doctor
const HOUSE_DEF := &"old_house"
const HOUSE_CELL := Vector2i(17, 12)
const HOUSE_SIZE := Vector2i(6, 7)
const HOUSE_ZONE := &"front_yard"
## Front door of the old_house model from the footprint centre (south face, the porch).
const DOOR_OFFSET := Vector3(-3.1, 0, 6.3)  # fallback without the model (greybox)
## Porch / door position along the south face, from the west end (0..1).
const DOOR_ALONG := 0.16
const INTERIOR_AT := Vector3(600, 0, 600)
const SLIME_SCENE := "res://art/monsters/swamp_blob.tscn"
const SLIME_COUNT := 7
const PATIENT := {
	"id": &"intro_doyun",
	"name": "한도윤",
	"age_stage": Enums.AgeStage.ADULT,
	"former_job": &"police",
	"traits": [&"brave"],
	"health": Enums.HealthState.INJURED,
	"recover_days": 5,
	"story": {
		"background": "첫날, 다리를 물린 채 낡은 집에 숨어 있던 전직 경찰. 권총이 든 가방을 지키고 있었다.",
		"fragments": ["의사를 찾아 달라고 부탁했다."],
		"first_line": "다리만 나으면, 나도 같이 나갈게.",
	},
}
const TALK := [
	["한도윤", "…거기 누구야? 마물은… 아, 사람이구나. 문은 제대로 잠갔지?"],
	["한도윤", "다리를 물렸어. 피는 멎었는데, 혼자서는 못 걸어."],
	["한도윤", "그 총, 우리 서에서 챙겨 온 거야. 잘 챙겼네. 밖에선 그거 없으면 못 버텨."],
	["한도윤", "방송 들었어? 공원 관리사무소에 의사 선생님이 숨어 있대."],
	["한도윤", "의사만 있으면 여기에 의무실을 차릴 수 있어. 나도, 앞으로 다칠 사람들도 살 수 있고."],
	["한도윤", "부탁이야. 공원에 가서 그 사람을 데려와 줘."],
]

var base: Node3D  # base_school
var interior: IntroHouse
var player: Player
var _cam: Camera3D
var _slimes: Array[Node3D] = []
var _path: Array[Vector3] = []
var _skipped := false
var _shake := 0.0
var _cam_follow: Callable = Callable()
var _door := Vector3.ZERO
var _house_uid := &""
var _house_center := Vector3.ZERO
var _phase := &""
var _dolly_gen := 0


## Slime look-alike for the cutscene: the monster Visual reads `velocity` and `state` from its parent.
class SlimePuppet extends Node3D:
	var velocity := Vector3.ZERO
	var state := Enums.AIState.CHASE
	var lag := 0.0
	var side := 0.0
	var hop := 0.0
	var stopped := false


static func pending() -> bool:
	return GameState.has_flag(FLAG_PENDING) and not GameState.has_flag(FLAG_HOUSE_DONE)


func _ready() -> void:
	add_to_group(GROUP)
	base = get_parent() as Node3D
	player = base.get(&"player") as Player
	_place_house()
	interior = IntroHouse.new()
	interior.name = "IntroHouse"
	add_child(interior)
	interior.global_position = INTERIOR_AT
	interior.show_patient(PATIENT)
	interior.talk_requested.connect(_on_talk)
	interior.exit_requested.connect(_on_exit)
	_cam = Camera3D.new()
	_cam.name = "CinematicCamera"
	_cam.fov = 42.0
	add_child(_cam)
	UI.cinematic.skip_requested.connect(_skip)
	_run.call_deferred()


func _exit_tree() -> void:
	if UI.cinematic.skip_requested.is_connected(_skip):
		UI.cinematic.skip_requested.disconnect(_skip)
	if player != null and is_instance_valid(player):
		player.script_input = {}


## Phase name for the tutorial and tests: &"cinematic", &"house", &"done".
func phase() -> StringName:
	return _phase


## The house on the grid (story building, free and finished). Kept on later loads.
func _place_house() -> void:
	var uid := &""
	for id: StringName in Colony.buildings:
		if Colony.buildings[id]["def_id"] == HOUSE_DEF:
			uid = id
	if uid == &"":
		uid = Colony.place_building(HOUSE_DEF, HOUSE_CELL, 0, HOUSE_ZONE, false)
		Colony.complete_building(uid)
	_house_uid = uid
	var grid: BaseGrid = base.get(&"grid")
	_house_center = grid.footprint_center(HOUSE_ZONE, HOUSE_CELL, HOUSE_SIZE)
	_door = _house_center + DOOR_OFFSET


## The front door from the house as drawn (BuildingModels.VISUAL_SCALE and the model may change):
## the porch is the west end of the south face. Called once the view exists.
func _find_door() -> void:
	var box := AABB()
	var first := true
	for v in get_tree().get_nodes_in_group(BuildingViews.VIEW_GROUP):
		if v.get_meta(&"building_uid", &"") != _house_uid:
			continue
		for mi in (v as Node).find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			if b.size.y < 1.0:
				continue  # the patio slab, the mailbox
			box = b if first else box.merge(b)
			first = false
	if first:
		return
	_door = Vector3(box.position.x + box.size.x * DOOR_ALONG, _house_center.y, box.end.z + 0.35)


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame  # BuildingViews refresh is deferred
	_find_door()
	if GameState.has_flag(FLAG_TALKED):
		_enter_house(false)  # loaded mid-intro after the talk: straight to walking out
		return
	_phase = &"cinematic"
	await _cinematic()
	if not _skipped:
		_enter_house(true)


# ---------------- cinematic ----------------

func _cinematic() -> void:
	var ci := UI.cinematic
	ci.reset()
	ci.film = true
	ci.cut(true)
	ci.bars(true, 0.01)
	ci.skippable = true
	Audio.set_music_state(&"night")
	base.call(&"set_player_mode", true)
	_cam.current = true
	player.visible = false
	# 1 — the broadcast over black
	await _wait(0.8)
	Audio.play(&"radio_static_open")
	ci.caption("치익… 여기는… 공원 숲 방송실…", 2.4)
	await _wait(2.9)
	if _skipped: return
	Audio.play(&"radio_blip")
	ci.caption("살아 있는 사람, 들리면… 숲 속 공터로 와요. 여기는 아직… 치익—", 3.2)
	await _wait(3.6)
	if _skipped: return
	# 2a — dawn wide: high over the clearing, drifting down toward the house
	var start := _door + Vector3(1.5, 0, 44)
	player.global_position = start
	player.visible = true
	player.rotation.y = 0.0
	_path = [_door + Vector3(1.2, 0, 26), _door + Vector3(-0.4, 0, 9), _door + Vector3(0, 0, 1.4), _door + Vector3(0, 0, -0.4)]
	_spawn_slimes(start + Vector3(0, 0, 9))
	_frame(_house_center + Vector3(-2, 24, -16), start + Vector3(0, 0, -6))
	ci.fade_to(0.0, 1.4)
	_dolly(_house_center + Vector3(-2, 24, -16), _house_center + Vector3(2, 15, -8),
		start + Vector3(0, 0, -6), start + Vector3(0, 1, -14), 3.6)
	await _wait(0.9)
	if _skipped: return
	Audio.set_music_state(&"chase")
	_start_run()
	Audio.play(&"monster_water_chase", start + Vector3(0, 0, 9))
	await _wait(2.4)
	if _skipped: return
	# 2b — in front of him, low, looking back: he runs at us, the blobs bound behind
	_cam_follow = func(_d: float) -> void:
		var ahead := player.global_position + Vector3(-1.6, 1.1, -5.5)
		_cam.global_position = _cam.global_position.lerp(ahead, 0.12)
		_aim(player.global_position + Vector3(0, 1.3, 2.5))
	_cam.global_position = player.global_position + Vector3(-1.6, 1.1, -5.5)
	Audio.play(&"monster_water_chase", player.global_position + Vector3(0, 0, 6))
	await _wait(2.6)
	if _skipped: return
	# 2c — behind him, over the shoulder: the porch ahead, he dives in; the door is never shown
	_cam_follow = func(_d: float) -> void:
		var behind := player.global_position + Vector3(1.3, 2.3, 4.8)
		_cam.global_position = _cam.global_position.lerp(behind, 0.15)
		_aim(player.global_position + Vector3(0, 1.2, -5.0))
	_cam.global_position = player.global_position + Vector3(1.3, 2.3, 4.8)
	while not _path.is_empty() and not _skipped:
		await get_tree().process_frame
	if _skipped: return
	_cam_follow = Callable()
	player.visible = false
	player.script_input = {"world_move": Vector3.ZERO}
	_hero_clip(&"")
	# SLAM: a hard cut to black on the bang
	Audio.play(&"wall_hit_wood", _door)
	ci.cut(true)
	await _wait(0.55)
	if _skipped: return
	# 3 — through the door: the blobs leap at it (at us) and splat, one after another
	_frame(_door + Vector3(0, 1.5, -0.15), _door + Vector3(0, 0.6, 8.0))
	_cam.fov = 58.0
	_shake = 0.5
	ci.cut(false)
	for s in _slimes:
		s.stopped = false
	await _wait(3.0)
	_cam.fov = 42.0
	if _skipped: return
	await ci.fade_to(1.0, 0.7).finished
	if _skipped: return
	_free_slimes()
	ci.bars(false, 0.01)
	UI.hud.visible = false
	await ci.title("A walking disaster", "1일차 · 봄, 새벽", 1.8).finished
	ci.skippable = false


func _skip() -> void:
	if _phase != &"cinematic" or _skipped:
		return
	_skipped = true
	_hero_clip(&"")
	_dolly_gen += 1
	_cam_follow = Callable()
	_path.clear()
	_free_slimes()
	UI.cinematic.cut(true)
	_enter_house(true)


## Hero inside, catching his breath; the camera eases from close to the play view.
func _enter_house(from_cinematic: bool) -> void:
	_phase = &"house"
	var ci := UI.cinematic
	ci.skippable = false
	ci.bars(false, 0.01)
	ci.cut(true)
	base.call(&"set_player_mode", true)
	_cam.current = false
	player.visible = true
	player.script_input = {"world_move": Vector3.ZERO}
	player.global_position = interior.spawn_point() if not GameState.has_flag(FLAG_TALKED) else interior.patient_point() + Vector3(2.2, 0, 1.0)
	player.rotation.y = PI
	var fcam: Node = base.get(&"field_camera")
	if fcam != null and fcam.has_method(&"snap"):
		fcam.call(&"snap")
	interior.door.enabled = GameState.has_flag(FLAG_TALKED)
	if UI.base_hud != null:
		UI.base_hud.visible = false  # no 건설 / 출격 keys inside the house
	Audio.set_music_state(&"base")
	await _wait(0.3)
	if from_cinematic:
		_cam.current = true
		var p := player.global_position
		_frame(p + Vector3(1.2, 1.5, 2.6), p + Vector3(0, 1.2, 0))
		ci.bars(true, 0.01)
		ci.fade_to(0.0, 1.2)
		ci.caption("하아… 하아… 살았다.", 2.2)
		var play_cam := _play_cam()
		_dolly(p + Vector3(1.2, 1.5, 2.6), play_cam.global_position, p + Vector3(0, 1.2, 0), p, 3.0)
		await _wait(3.1)
		ci.bars(false, 0.6)
		_cam.current = false
		var fc := _play_cam()
		if fc:
			fc.current = true
	else:
		ci.fade_to(0.0, 0.6)
	UI.hud.visible = true
	ci.film = false
	player.script_input = {}


func _play_cam() -> Camera3D:
	var fcam: Node = base.get(&"field_camera")
	if fcam is Camera3D:
		return fcam as Camera3D
	return fcam.find_child("*", true, false) as Camera3D if fcam != null else null


# ---------------- house ----------------

func _on_talk() -> void:
	if UI.cinematic.is_talking():
		return
	player.script_input = {"world_move": Vector3.ZERO}
	player.look_at(Vector3(interior.patient_point().x, player.global_position.y, interior.patient_point().z), Vector3.UP, true)
	var lines := TALK.duplicate()
	if GameState.has_flag(FLAG_TALKED):
		lines = [["한도윤", "공원 관리사무소야. 의사 선생님을… 부탁해."]]
	UI.cinematic.bars(true, 0.5)
	await UI.cinematic.talk(lines)
	UI.cinematic.bars(false, 0.5)
	if not GameState.has_flag(FLAG_TALKED):
		GameState.set_flag(FLAG_TALKED)
		if Colony.get_resident(PATIENT["id"]).is_empty():
			Colony.add_resident(PATIENT.duplicate(true))
	interior.door.enabled = true
	player.script_input = {}


func _on_exit() -> void:
	if not GameState.has_flag(FLAG_TALKED):
		return
	player.script_input = {"world_move": Vector3.ZERO}
	Audio.play(&"ui_confirm")
	await UI.cinematic.fade_to(1.0, 0.5).finished
	GameState.set_flag(FLAG_HOUSE_DONE)
	player.script_input = {}
	base.call(&"set_player_mode", false)
	var bc: BaseCamera = base.get(&"base_camera")
	if bc != null:
		bc.focus = _door + Vector3(0, 0, 4)
	_phase = &"done"
	interior.queue_free()
	await UI.cinematic.fade_to(0.0, 0.7).finished
	UI.cinematic.reset()
	if UI.base_hud != null:
		UI.base_hud.visible = true
	queue_free()


# ---------------- motion ----------------

func _start_run() -> void:
	_hero_clip(&"run")  # Mixamo Running (cutscenes only; play sprints with the walks)
	for s in _slimes:
		s.stopped = false


## The hero model's cutscene clip (PlayerModel.play_clip), &"" = back to normal.
func _hero_clip(clip: StringName) -> void:
	var m := player.get_node_or_null(^"Model") if player != null else null
	if m != null and m.has_method(&"play_clip"):
		m.call(&"play_clip", clip)


func _physics_process(delta: float) -> void:
	if player == null:
		return
	if not _path.is_empty() and _phase == &"cinematic":
		var to := _path[0] - player.global_position
		to.y = 0.0
		if to.length() < 0.7:
			_path.pop_front()
		player.stamina = player.stats.max_stamina
		player.script_input = {"world_move": to.normalized() if to.length() > 0.01 else Vector3.ZERO,
			"sprint": true}
	_move_slimes(delta)


func _process(delta: float) -> void:
	if interior != null and is_instance_valid(interior) and _phase == &"house":
		# 한도윤 talks once the gun is in hand (the tutorial order: case first).
		interior.patient.enabled = Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) != &""
	if _cam_follow.is_valid():
		_cam_follow.call(delta)
	if _shake > 0.0 and _cam.current:
		_shake = maxf(_shake - delta * 1.8, 0.0)
		var k := _shake * _shake * 0.35
		_cam.h_offset = randf_range(-k, k)
		_cam.v_offset = randf_range(-k, k)
	elif _cam.current:
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


func _spawn_slimes(at: Vector3) -> void:
	if not ResourceLoader.exists(SLIME_SCENE):
		return
	var packed := load(SLIME_SCENE) as PackedScene
	for i in SLIME_COUNT:
		var s := SlimePuppet.new()
		s.name = "Slime%d" % i
		s.lag = 2.2 + i * 0.75 + randf() * 0.4
		s.side = (i % 2 * 2 - 1) * (0.8 + (i / 2) * 0.9)
		s.hop = randf() * TAU
		s.stopped = true
		var vis := packed.instantiate()
		s.add_child(vis)
		s.scale = Vector3.ONE * randf_range(0.85, 1.25)
		add_child(s)
		s.global_position = at + Vector3(s.side, 0, i * 1.3)
		_slimes.append(s)


## Each blob chases a point `lag` m behind the hero; once he is in, they pile into the door,
## splat (squash + sound + a small shake) and bounce back.
func _move_slimes(delta: float) -> void:
	for s in _slimes:
		if not is_instance_valid(s) or s.stopped:
			continue
		var inside := not player.visible
		var goal: Vector3
		if inside:
			goal = _door + Vector3(s.side * 0.35, 0, 1.0)
		else:
			var back := Vector3(0, 0, 1) if _path.is_empty() else (player.global_position - _path[0]).normalized()
			back.y = 0.0
			goal = player.global_position + back * s.lag + back.cross(Vector3.UP) * s.side
		var to := goal - s.global_position
		to.y = 0.0
		var speed := 7.4 if not inside else 8.5
		var step := to.normalized() * minf(speed * delta, to.length())
		s.velocity = step / maxf(delta, 0.0001)
		s.global_position += step
		if to.length() > 0.3:
			s.look_at(s.global_position + to, Vector3.UP, true)
		s.hop += delta * 9.0
		var vis := s.get_child(0) as Node3D
		if vis:
			vis.position.y = absf(sin(s.hop)) * 0.35
		if inside and to.length() < 0.35:
			_splat(s)


func _splat(s: SlimePuppet) -> void:
	s.stopped = true
	s.velocity = Vector3.ZERO
	Audio.play(&"splash", s.global_position)
	_shake = maxf(_shake, 0.35)
	var vis := s.get_child(0) as Node3D
	var tw := create_tween()
	tw.tween_property(s, ^"scale", Vector3(s.scale.x * 1.5, s.scale.y * 0.45, s.scale.z * 1.5), 0.08)
	tw.tween_property(s, ^"scale", s.scale, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var away := s.global_position + Vector3(s.side * 0.5, 0, 1.8 + randf() * 1.2)
	tw.parallel().tween_property(s, ^"global_position", away, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if vis and vis.has_method(&"play_once"):
		vis.call(&"play_once", &"Attack")


func _free_slimes() -> void:
	for s in _slimes:
		if is_instance_valid(s):
			s.queue_free()
	_slimes.clear()


# ---------------- camera ----------------

func _frame(pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_aim(look)


func _aim(look: Vector3) -> void:
	if not _cam.global_position.is_equal_approx(look):
		_cam.look_at(look, Vector3.UP)


## Smooth move from (a, look_a) to (b, look_b) in `sec`.
func _dolly(a: Vector3, b: Vector3, look_a: Vector3, look_b: Vector3, sec: float) -> void:
	_dolly_gen += 1
	var gen := _dolly_gen
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(t: float) -> void:
		if gen != _dolly_gen:
			return  # a newer shot took the camera
		_cam.global_position = a.lerp(b, t)
		_aim(look_a.lerp(look_b, t)), 0.0, 1.0, sec)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
