extends BossMechanic
## 가라앉은 간판뱀 (docs/design/04-monsters.md "보스"): it only takes damage out of the water.
## - Underwater it is immune and swims after you; a ripple trail shows where it is (no extra HUD).
## - It surfaces to attack: tail swing (cone) and splash (orange ring: slow + wet, no damage), then stays up
##   for the pattern's params.surface_sec before sinking again. That window is when it can be hurt.
## - Dive (action &"dive"): sinks, swims close, marks a line for params.aim_sec, then charges out of the
##   water along it and hits whoever is still on the line. It is up and hittable right after.
## Numbers are in data/monsters/bosses/sunken_sign_serpent.tres (pattern params), all drafts.

enum Dive { NONE, SWIM, AIM, CHARGE }

## Seconds between two ripples while it swims underwater.
const WAKE_SEC := 0.35
const WAKE_FX := &"monster_splash"
const SPLASH_FX := &"boss_splash"

var submerged := false
## Seconds left above water before it sinks again (only counts while it is not attacking).
var surfaced_left := 0.0

var _dive := Dive.NONE
var _dive_left := 0.0
var _dive_pattern: BossPattern
var _dive_area: Dictionary = {}
var _dive_dir := Vector3.FORWARD
var _wake := 0.0


func on_added() -> void:
	_set_submerged(true, 0.0)


func on_tick(delta: float) -> void:
	match _dive:
		Dive.SWIM:
			_swim(delta)
		Dive.AIM:
			_aim(delta)
		Dive.CHARGE:
			_charge(delta)
		Dive.NONE:
			if not submerged and boss.casting() == null:
				surfaced_left -= delta
				if surfaced_left <= 0.0:
					_set_submerged(true)
	if submerged:
		_wake -= delta
		var v := Vector2(boss.velocity.x, boss.velocity.z)
		if _wake <= 0.0 and v.length() > 0.5:
			_wake = WAKE_SEC
			Fx.spawn(WAKE_FX, boss.global_position, {"radius": 0.6, "silent": true})


func on_pattern_started(pattern: BossPattern, _area: Dictionary) -> void:
	if pattern.action == &"dive":
		return  # the Dive clip plays; it sinks when the windup ends
	_set_submerged(false, 0.3, false)  # comes up to swing or splash
	surfaced_left = maxf(surfaced_left, float(pattern.params.get("surface_sec", 3.0)))


func land_pattern(pattern: BossPattern, area: Dictionary) -> bool:
	match pattern.action:
		&"dive":
			_begin_dive(pattern)
			return true
		&"splash":
			_splash(pattern, area)
			surfaced_left = float(pattern.params.get("surface_sec", 3.0))
			return true
	surfaced_left = float(pattern.params.get("surface_sec", 3.0))
	return false


func filter_damage(amount: float, _info: Dictionary) -> float:
	return 0.0 if submerged else amount


func on_reset() -> void:
	_dive = Dive.NONE
	boss.hold(0.0)
	_set_submerged(true)


func is_diving() -> bool:
	return _dive != Dive.NONE


# --- Dive -----------------------------------------------------------------

func _begin_dive(pattern: BossPattern) -> void:
	_dive_pattern = pattern
	_set_submerged(true, 0.25)
	_dive = Dive.SWIM
	_dive_left = float(pattern.params.get("swim_sec", 1.6))
	# Longer than the whole dive; ended with hold(0) after the charge.
	boss.hold(_dive_left + float(pattern.params.get("aim_sec", 1.0)) + float(pattern.params.get("charge_sec", 0.35)) + 1.0)


## Swims toward the target until it is close enough for the charge (or out of time).
func _swim(delta: float) -> void:
	_dive_left -= delta
	var to := _to_target()
	var reach := _dive_pattern.length * 0.6
	if to.length() > reach:
		boss.velocity = to.normalized() * float(_dive_pattern.params.get("swim_speed", 11.0))
	else:
		boss.velocity = Vector3.ZERO
	_face(to)
	if _dive_left <= 0.0 or to.length() <= reach:
		_start_aim(to)


func _start_aim(to: Vector3) -> void:
	_dive = Dive.AIM
	_dive_left = float(_dive_pattern.params.get("aim_sec", 1.0))
	boss.velocity = Vector3.ZERO
	_dive_dir = to.normalized() if to.length() > 0.01 else -boss.global_basis.z
	_dive_dir.y = 0.0
	_dive_dir = _dive_dir.normalized()
	_face(_dive_dir)
	_dive_area = {"pattern_id": _dive_pattern.id, "shape": &"line", "position": boss.global_position,
		"direction": _dive_dir, "radius": 0.0, "inner": 0.0, "angle_deg": 0.0,
		"length": _dive_pattern.length, "width": _dive_pattern.width, "duration": _dive_left,
		"kind": _dive_pattern.kind}
	boss.telegraph_started.emit(_dive_area)
	Fx.spawn(BossMonster.FX_TELEGRAPH, _dive_area["position"], _dive_area)


func _aim(delta: float) -> void:
	_dive_left -= delta
	boss.velocity = Vector3.ZERO
	if _dive_left > 0.0:
		return
	_dive = Dive.CHARGE
	_dive_left = float(_dive_pattern.params.get("charge_sec", 0.35))
	_set_submerged(false, 0.15, false)
	var visual := _visual()
	if visual:
		visual.play_once(&"Charge")
	boss.velocity = _dive_dir * (_dive_pattern.length / maxf(_dive_left, 0.05))


func _charge(delta: float) -> void:
	_dive_left -= delta
	if _dive_left > 0.0:
		return
	boss.velocity = Vector3.ZERO
	_dive = Dive.NONE
	boss.hit_area(_dive_pattern, _dive_area)
	surfaced_left = float(_dive_pattern.params.get("surface_sec", 4.0))
	boss.hold(0.0)


# --- Splash, helpers --------------------------------------------------------

## Orange ring: slows and wets everyone inside, no damage (the ring colour means "no damage").
func _splash(pattern: BossPattern, area: Dictionary) -> void:
	var fx := area.duplicate()
	fx["element"] = boss.def.family
	Fx.spawn(SPLASH_FX, area["position"], fx)
	for body in boss.area_targets(area):
		var holder := body.get_node_or_null(NodePath(StatusHolder.NODE_NAME)) as StatusHolder
		if holder == null:
			continue
		holder.apply(&"slow", {"duration": float(pattern.params.get("slow_sec", 2.0))})
		holder.apply(&"wet")


func _set_submerged(on: bool, sec: float = 0.4, rise: bool = true) -> void:
	if on != submerged and sec > 0.0:
		Fx.spawn(WAKE_FX, boss.global_position, {"radius": 1.6, "silent": true})
	submerged = on
	var visual := _visual()
	if visual:
		visual.sink(on, sec, rise)
	else:
		var body := boss.get_node_or_null(^"Body") as Node3D
		if body:
			body.visible = not on  # grey box without the model (no assets): gone underwater
	var core := boss.get_node_or_null(^"WeakPoint/Core") as Node3D
	if core:
		core.visible = not on
	# The red enemy outline (Monster._set_outline) would show it through the water; the ripples do that job.
	boss._set_outline(not on)


func _to_target() -> Vector3:
	if not is_instance_valid(boss.target):
		return Vector3.ZERO
	var to := boss.target.global_position - boss.global_position
	to.y = 0.0
	return to


func _face(dir: Vector3) -> void:
	if Vector2(dir.x, dir.z).length() > 0.01:
		boss.rotation.y = atan2(-dir.x, -dir.z)


func _visual() -> MonsterVisual:
	return boss.get_node_or_null(^"Visual") as MonsterVisual
