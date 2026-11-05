class_name CombatFeel
extends RefCounted
## B-27 타격감 (hit feel). Owner: Lane B.
## Every shot gets something small (a directional camera kick). The big things are kept for rare
## moments: hit-stop on melee hits, kills and crit kills (never on a single bullet), camera shake on
## explosions, big hits on the player, essence release and slam. Monsters flinch on every real hit.
## Settings `reduce_shake` turns kick and shake off; hit-stop is not motion and stays.
## All numbers are placeholders (가안) and live here.

## Camera kick per shot (m, opposite the aim), by weapon def id. Sized for the 10~18 m camera:
## 0.25 m at the middle zoom is about 17 px (B-28, the B-27 values were too small to feel).
const KICK := {&"pistol": 0.25, &"smg": 0.15, &"rifle": 0.35, &"shotgun": 0.7, &"sniper_rifle": 0.9}
const KICK_DEFAULT := 0.3
const KICK_RETURN_SHARPNESS := 18.0
## Field of view punch per shot (degrees narrower, springs back with the kick): the view "leans in".
const FOV_PUNCH := {&"pistol": 0.8, &"smg": 0.4, &"rifle": 1.0, &"shotgun": 2.2, &"sniper_rifle": 3.0}
const FOV_PUNCH_DEFAULT := 0.8
const FOV_PUNCH_MAX := 5.0  # SMG bursts must not zoom in forever

## Hit-stop lengths in real seconds, and the time scale while stopped.
const STOP_MELEE_HIT := 0.035
const STOP_MELEE_FINISHER := 0.06
const STOP_KILL := 0.04
const STOP_CRIT_KILL := 0.075
const STOP_TIME_SCALE := 0.05

## Camera shake: trauma 0..1 adds up, decays per second, shake = trauma^2.
const SHAKE_MAX_OFFSET := 0.35  # m
const SHAKE_MAX_ROLL_DEG := 1.5
const SHAKE_DECAY := 1.8
const SHAKE_FREQ := 22.0
const SHAKE_EXPLOSION := 0.6  # at the blast centre, 0 at SHAKE_RANGE
const SHAKE_FLASHBANG := 0.25
const SHAKE_RANGE := 14.0
const SHAKE_PLAYER_HURT := 0.9  # x (damage / max health)
const SHAKE_HURT_MIN_RATIO := 0.08  # smaller hits on the player do not shake
const SHAKE_RELEASE := 0.35
const SHAKE_SLAM := 0.4
## A companion's signature skill (고유 스킬): the one big moment a companion gets.
const STOP_SIGNATURE := 0.12
const SHAKE_SIGNATURE := 0.5

## Monster flinch: its model ("Visual", else the grey-box "Body") is pushed away from the attacker
## and squashed, then springs back.
const FLINCH_SEC := 0.14
const FLINCH_PUSH := 0.2  # m, shots
const FLINCH_PUSH_MELEE := 0.35
const FLINCH_SQUASH := 0.15
const FLINCH_CRIT_MULT := 1.6
const VISUAL_NODE := ^"Visual"
const BODY_NODE := ^"Body"
## Corpse knock on a kill: the model slides this far along the killing hit (crit x FLINCH_CRIT_MULT).
const CORPSE_KNOCK := 0.5
const CORPSE_KNOCK_SEC := 0.18

static var _stop_until_ms := 0
static var _stop_token := 0
static var _ended_token := 0


## Small directional push of the camera, opposite the shot.
static func kick(from: Node, aim_dir: Vector3, def_id: StringName) -> void:
	var cam := _camera(from)
	if cam != null:
		cam.add_kick(-aim_dir.normalized() * float(KICK.get(def_id, KICK_DEFAULT)),
				float(FOV_PUNCH.get(def_id, FOV_PUNCH_DEFAULT)))


## Adds shake trauma. With `at`, it fades to nothing SHAKE_RANGE m from the camera's target.
static func shake(from: Node, trauma: float, at := Vector3.INF) -> void:
	var cam := _camera(from)
	if cam == null:
		return
	if at.is_finite() and cam.target != null:
		trauma *= falloff(cam.target.global_position.distance_to(at))
	cam.add_trauma(trauma)


## 1 at the centre, 0 at SHAKE_RANGE and beyond.
static func falloff(distance: float) -> float:
	return clampf(1.0 - distance / SHAKE_RANGE, 0.0, 1.0)


## Hit-stop length for one landed player hit (0 = none). Single bullets that do not kill get none.
static func stop_for(killed: bool, crit: bool, melee: bool, finisher: bool) -> float:
	if killed:
		return STOP_CRIT_KILL if crit else STOP_KILL
	if melee:
		return STOP_MELEE_FINISHER if finisher else STOP_MELEE_HIT
	return 0.0


## Freezes the game to STOP_TIME_SCALE for `sec` real seconds. Overlaps keep the later end
## (a shotgun's pellets or a slam's targets stop once, not once each).
static func hit_stop(from: Node, sec: float) -> void:
	if sec <= 0.0 or from == null or not from.is_inside_tree():
		return
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	if is_stopped() and until <= _stop_until_ms:
		return
	_stop_until_ms = until
	_stop_token += 1
	Engine.time_scale = STOP_TIME_SCALE
	from.get_tree().create_timer(sec, true, false, true).timeout.connect(_end_stop.bind(_stop_token))


static func is_stopped() -> bool:
	return _stop_token != _ended_token


## Only the latest stop's timer restores time (an earlier, shorter one must not cut it short).
static func _end_stop(token: int) -> void:
	if token == _stop_token:
		_ended_token = token
		Engine.time_scale = 1.0


## Pushes the monster's Body away from info.source (or just squashes it) and springs it back.
static func flinch(monster: Node3D, info: Dictionary) -> void:
	var body := monster.get_node_or_null(VISUAL_NODE) as Node3D
	if body == null or not body.visible:
		body = monster.get_node_or_null(BODY_NODE) as Node3D
	if body == null or not body.is_inside_tree():
		return
	if not body.has_meta(&"flinch_rest"):
		body.set_meta(&"flinch_rest", body.transform)
	var rest: Transform3D = body.get_meta(&"flinch_rest")
	var old: Tween = body.get_meta(&"flinch_tween") if body.has_meta(&"flinch_tween") else null
	if old != null and old.is_valid():
		old.kill()
	var k := FLINCH_CRIT_MULT if info.get("crit", false) else 1.0
	var push := (FLINCH_PUSH_MELEE if info.has("combo_step") else FLINCH_PUSH) * k
	var dir := push_dir(monster, info)
	var squash := FLINCH_SQUASH * k
	var hit := rest
	hit.origin += monster.global_basis.inverse() * dir * push
	hit.basis = rest.basis.scaled(Vector3(1.0 + squash, 1.0 - squash, 1.0 + squash))
	body.transform = hit
	var tw := body.create_tween()
	tw.tween_property(body, ^"transform", rest, FLINCH_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	body.set_meta(&"flinch_tween", tw)


## Flat direction a hit pushes `target` (away from info.source), or ZERO.
static func push_dir(target: Node3D, info: Dictionary) -> Vector3:
	var source := info.get("source") as Node3D
	if source == null or not is_instance_valid(source):
		return Vector3.ZERO
	var dir := target.global_position - source.global_position
	dir.y = 0.0
	return dir.normalized() if dir.length() > 0.001 else Vector3.ZERO


## Kill: slides a corpse (already detached from the monster) along the killing hit.
## A flinch still springing back would pull the corpse to the monster's local rest, so it stops first.
static func corpse_knock(corpse: Node3D, info: Dictionary) -> void:
	var flinch_tw: Tween = corpse.get_meta(&"flinch_tween") if corpse.has_meta(&"flinch_tween") else null
	if flinch_tw != null and flinch_tw.is_valid():
		flinch_tw.kill()
	if corpse.has_meta(&"flinch_rest"):
		corpse.basis = corpse.basis.orthonormalized()  # drop the squash (the model's rest scale is 1)
	var dir := push_dir(corpse, info)
	if dir == Vector3.ZERO or not corpse.is_inside_tree():
		return
	var dist := CORPSE_KNOCK * (FLINCH_CRIT_MULT if info.get("crit", false) else 1.0)
	var tw := corpse.create_tween()
	tw.tween_property(corpse, ^"global_position", corpse.global_position + dir * dist,
			CORPSE_KNOCK_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _camera(from: Node) -> FieldCamera:
	if from == null or not from.is_inside_tree() or Settings.get_value(&"reduce_shake"):
		return null
	return from.get_viewport().get_camera_3d() as FieldCamera
