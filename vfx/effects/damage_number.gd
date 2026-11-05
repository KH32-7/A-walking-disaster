extends FxEffect
## &"damage_number" (UI_RULES §6 "피해 숫자"): rises from the hit point and fades over 0.7 s.
## params: amount (float, B's dealt damage), kind (&"hit" | &"tick" | &"player" | &"heal"), crit, weak_point,
## element. Not colour alone: crit = ACCENT + bigger + pop + "!", weak point = "◆" mark, player = "-N",
## heal = "+N", tick = small. Screen-sized (fixed_size) and drawn over the world with a dark outline.

const RISE := 0.9
const POP_SEC := 0.12
## Label3D pixel_size with fixed_size: ~font px on a 1080p screen.
const PIXEL := 0.0011
const SIZES := {&"hit": 40, &"tick": 28, &"player": 40, &"heal": 34}
const CRIT_SIZE := 54

var _label: Label3D
var _drift := Vector3.ZERO
var _pop := 1.0


func _build() -> void:
	lifetime = 0.7
	var kind: StringName = params.get("kind", &"hit")
	var crit: bool = params.get("crit", false) and kind == &"hit"
	_label = Label3D.new()
	_label.text = _text(kind, crit)
	_label.font = UiThemeBuilder.font_num()
	_label.font_size = CRIT_SIZE if crit else int(SIZES.get(kind, 40))
	_label.outline_size = 12
	_label.outline_modulate = Color(0.04, 0.05, 0.07, 0.9)
	_label.modulate = _color(kind, crit)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = PIXEL
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.outline_render_priority = 9
	_label.double_sided = true
	_label.shaded = false
	add_child(_label)
	_drift = Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.2, 0.2))
	_pop = (1.55 if crit else 1.2) if not reduced_flash else 1.0
	_tick(0.0, 0.0)


func _tick(k: float, _delta: float) -> void:
	var t := age
	_label.position = _drift * ease(k, 0.5) + Vector3.UP * RISE * ease(k, 0.45)
	var s := lerpf(_pop, 1.0, clampf(t / POP_SEC, 0.0, 1.0))
	_label.scale = Vector3.ONE * s
	var a := 1.0 if k < 0.45 else 1.0 - (k - 0.45) / 0.55
	_label.modulate.a = a
	_label.outline_modulate.a = 0.9 * a


func _text(kind: StringName, crit: bool) -> String:
	var amount := p_float("amount", 0.0)
	var n := str(int(round(amount))) if amount >= 1.0 else ("%.1f" % amount)
	match kind:
		&"player":
			return "-" + n
		&"heal":
			return "+" + n
	var s := n
	if crit:
		s += "!"
	if params.get("weak_point", false):
		s = "◆" + s
	return s


func _color(kind: StringName, crit: bool) -> Color:
	match kind:
		&"player":
			return UiTokens.DANGER
		&"heal":
			return UiTokens.GOOD
		&"tick":
			return element_color(UiTokens.TEXT_DIM)
	return UiTokens.ACCENT if crit else UiTokens.TEXT
