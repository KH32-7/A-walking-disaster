class_name AimReticle
extends Control
## B-28 aim reticle. Takes the OS cursor's place in the field (the player already watches the cursor,
## so shot and hit feedback live here instead of in a new HUD widget, CLAUDE.md 8).
## - Gun: four ticks on a ring whose radius is the current spread at the aim distance. Opens a little
##   on every shot, shows the reload as an arc, shakes on an empty trigger.
## - Melee: a small dot.
## - Hit marker (player hits on monsters only): white X; crit or weak point: ACCENT X, larger
##   (the same colour as crit damage numbers); kill: big thick white X and a ring that opens.
## The OS cursor is hidden only while this is shown and no screen is open (pause, bag, map...).
## Created by UI.show_field_hud next to the field HUD. All sizes are px at 1080p, placeholders (가안).

const RING_MIN := 10.0
const RING_MAX := 160.0
const TICK_LEN := 7.0
const LINE_W := 2.0
const OUTLINE_W := 2.0  # dark rim around every line, so it reads on bright ground
const DOT_R := 2.0
const SHOT_PULSE_PX := 7.0
const SHOT_PULSE_SEC := 0.1
const SHAKE_PX := 5.0
const SHAKE_SEC := 0.25
const SHAKE_HZ := 40.0
const RELOAD_PAD := 6.0
## Hit markers: gap from the centre, line length, width, seconds, start scale.
const MARK_GAP := 6.0
const MARKS := {
	&"hit": {"len": 8.0, "w": 2.0, "sec": 0.15, "pop": 1.2},
	&"crit": {"len": 11.0, "w": 2.5, "sec": 0.22, "pop": 1.4},
	&"kill": {"len": 14.0, "w": 3.5, "sec": 0.32, "pop": 1.5},
}
const MARK_RANK := {&"hit": 0, &"crit": 1, &"kill": 2}
const KILL_RING_FROM := 10.0
const KILL_RING_TO := 30.0

var _player: Player
var _holder: WeaponHolder
var _use_stick := false
var _cursor_hidden := false
var _pulse := 0.0
var _shake := 0.0
var _time := 0.0
var _reload_left := 0.0
var _reload_len := 0.0
var _mark := &""
var _mark_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_set_cursor_hidden(false)
	elif what == NOTIFICATION_EXIT_TREE:
		_set_cursor_hidden(false)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_use_stick = false
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		_use_stick = true


func _process(delta: float) -> void:
	_bind()
	_time += delta
	_pulse = maxf(_pulse - delta / SHOT_PULSE_SEC, 0.0)
	_shake = maxf(_shake - delta / SHAKE_SEC, 0.0)
	_reload_left = maxf(_reload_left - delta, 0.0)
	if _mark != &"":
		_mark_t += delta
		if _mark_t >= float(MARKS[_mark]["sec"]):
			_mark = &""
	_set_cursor_hidden(is_visible_in_tree() and _player != null and UI.top() == &"")
	queue_redraw()


## Called by the weapon holder's hit_landed. Public for tests.
func show_hit(kind: StringName) -> void:
	if _mark != &"" and MARK_RANK[_mark] > MARK_RANK[kind]:
		return  # a kill marker is not cut short by the next pellet
	_mark = kind
	_mark_t = 0.0


static func hit_kind(target: Node, info: Dictionary) -> StringName:
	var monster := target as Monster
	if monster == null and target is MonsterWeakPoint:
		monster = target.get_parent() as Monster
	if monster == null:
		return &""
	if not is_instance_valid(monster) or monster.is_dead():
		return &"kill"
	if info.get("crit", false) or target is MonsterWeakPoint:
		return &"crit"
	return &"hit"


func _bind() -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	_holder = null
	if _player == null:
		return
	_holder = _player.get_node_or_null(^"Weapons") as WeaponHolder
	if _holder == null:
		return
	_holder.attacked.connect(func(kind: StringName, _step: int) -> void:
		if kind == &"shot":
			_pulse = 1.0)
	_holder.dry_fired.connect(func() -> void: _shake = 1.0)
	_holder.reload_started.connect(func(sec: float) -> void:
		_reload_len = maxf(sec, 0.01)
		_reload_left = sec)
	_holder.reload_finished.connect(func() -> void: _reload_left = 0.0)
	_holder.weapon_changed.connect(func(_slot: Enums.EquipSlot, _uid: StringName) -> void: _reload_left = 0.0)
	_holder.hit_landed.connect(func(target: Node, _amount: float, info: Dictionary) -> void:
		var kind := hit_kind(target, info)
		if kind != &"":
			show_hit(kind))


func _set_cursor_hidden(hide: bool) -> void:
	if hide == _cursor_hidden:
		return
	_cursor_hidden = hide
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if hide else Input.MOUSE_MODE_VISIBLE


func _draw() -> void:
	if _player == null or not is_instance_valid(_player) or _player.is_downed:
		return
	var center := _center()
	if not center.is_finite():
		return
	center.x += sin(_time * TAU * SHAKE_HZ) * SHAKE_PX * _shake
	var gun := _holder != null and WeaponHolder.is_gun(_holder.current_stats())
	if gun:
		var r := _ring_radius(center) + SHOT_PULSE_PX * _pulse
		for i in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5)
			_line(center + d * r, center + d * (r + TICK_LEN), UiTokens.TEXT, LINE_W)
		if _reload_left > 0.0:
			var done := 1.0 - _reload_left / _reload_len
			var rr := r + TICK_LEN + RELOAD_PAD
			draw_arc(center, rr, -PI * 0.5, -PI * 0.5 + TAU * done, 48, UiTokens.SHADOW, LINE_W + OUTLINE_W * 2.0, true)
			draw_arc(center, rr, -PI * 0.5, -PI * 0.5 + TAU * done, 48, UiTokens.TEXT_DIM, LINE_W, true)
	draw_circle(center, DOT_R + OUTLINE_W * 0.5, UiTokens.SHADOW)
	draw_circle(center, DOT_R, UiTokens.TEXT)
	_draw_mark(center)


func _draw_mark(center: Vector2) -> void:
	if _mark == &"":
		return
	var m: Dictionary = MARKS[_mark]
	var t := clampf(_mark_t / float(m["sec"]), 0.0, 1.0)
	var k := lerpf(float(m["pop"]), 1.0, minf(t * 3.0, 1.0))
	var color := UiTokens.ACCENT if _mark == &"crit" else UiTokens.TEXT
	color.a = 1.0 - t * t
	for i in 4:
		var d := Vector2.ONE.normalized().rotated(i * PI * 0.5)
		_line(center + d * MARK_GAP * k, center + d * (MARK_GAP + float(m["len"])) * k, color, float(m["w"]))
	if _mark == &"kill":
		var ring := UiTokens.TEXT
		ring.a = 1.0 - t
		draw_arc(center, lerpf(KILL_RING_FROM, KILL_RING_TO, t), 0.0, TAU, 40, ring, 2.0, true)


func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var rim := UiTokens.SHADOW
	rim.a *= color.a
	draw_line(a, b, rim, width + OUTLINE_W * 2.0, true)
	draw_line(a, b, color, width, true)


## Mouse: the cursor itself (no lag). Stick: the player's aim point on screen.
func _center() -> Vector2:
	if not _use_stick:
		return get_local_mouse_position()
	var cam := get_viewport().get_camera_3d()
	var aim: Variant = _player.aim_point()
	if cam == null or aim == null or cam.is_position_behind(aim):
		return Vector2.INF
	return cam.unproject_position(aim) - get_global_rect().position


## Screen radius of the spread cone at the aim distance.
func _ring_radius(center: Vector2) -> float:
	var cam := get_viewport().get_camera_3d()
	var aim: Variant = _player.aim_point()
	if cam == null or aim == null:
		return RING_MIN
	var flat: Vector3 = (aim as Vector3) - _player.global_position
	flat.y = 0.0
	var dist := flat.length()
	if dist < 0.1:
		return RING_MIN
	var half := deg_to_rad(_holder.current_spread_deg() * 0.5)
	var side := flat.normalized().cross(Vector3.UP) * dist * tan(half)
	var a := cam.unproject_position(aim)
	var b := cam.unproject_position((aim as Vector3) + side)
	return clampf(a.distance_to(b), RING_MIN, RING_MAX)
