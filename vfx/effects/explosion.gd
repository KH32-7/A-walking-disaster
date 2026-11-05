extends FxEffect
## &"explosion" and &"neon_moth_blast": fireball, ground shockwave out to `radius`, debris and smoke.
## params: radius (m, the damage radius when B has one), element (tints the fireball and adds that
## element's shapes to the debris). Neon moth (base_params element = LIGHT) also throws bolt arcs.
## Settings.reduce_flash: no white core. Sizes here are real metres (scale_k 1), from `radius`.

const FIRE := Color(1.0, 0.62, 0.25)
const CORE := Color(1.0, 0.95, 0.8)
const SMOKE := Color(0.5, 0.5, 0.52, 0.7)
const DEBRIS := Color(0.45, 0.43, 0.4)

var _r := 3.0


func _build() -> void:
	lifetime = 1.3
	_r = p_float("radius", 3.0)
	var e := p_element()
	var fire := FIRE if e == Enums.Element.NONE else UiTokens.element_color(e)
	var mid := Vector3.UP * maxf(_r * 0.3, 0.7)
	if not reduced_flash:
		var core := sprite(UiTokens.Shape.CIRCLE, CORE, _r * 0.2, Blend.ADD)
		core.node.position = mid
		core.size1 = _r * 0.5
		core.scale_k = 1.0
		core.ease_size = 0.2
		core.life = 0.16
		core.fade_from = 0.2
		core.energy = 1.1
	var ball := sprite(UiTokens.Shape.CIRCLE, fire, _r * 0.25, Blend.MIX, true, true)
	ball.node.position = mid
	ball.size1 = _r * 0.45
	ball.scale_k = 1.0
	ball.ease_size = 0.25
	ball.life = 0.38
	ball.fade_from = 0.35
	var star := sprite(UiTokens.Shape.STAR, Color(fire.lightened(0.4), maxf(flash_k, 0.4)), _r * 0.3, Blend.ADD)
	star.node.position = mid
	star.size1 = _r * 0.65
	star.scale_k = 1.0
	star.ease_size = 0.25
	star.life = 0.22
	star.fade_from = 0.2
	star.spin = rng.randf() * TAU
	var shock := ground(FxShapes.Extra.RING, Color(fire.lightened(0.3), 0.9), _r * 0.2, Vector3.ZERO, Blend.ADD)
	shock.size1 = _r * 1.05
	shock.ease_size = 0.3
	shock.life = 0.4
	shock.fade_from = 0.3
	var scorch := ground(UiTokens.Shape.CIRCLE, Color(0.08, 0.08, 0.09, 0.55), _r * 0.4)
	scorch.size1 = _r * 0.55
	scorch.fade_in = 0.05
	scorch.fade_from = 0.6
	for i in 8:
		var sm := sprite(UiTokens.Shape.CIRCLE, SMOKE, _r * 0.12, Blend.MIX, true, true)
		var a := TAU * i / 8.0 + rng.randf_range(-0.3, 0.3)
		sm.node.position = mid + Vector3(cos(a), 0.0, sin(a)) * _r * 0.2
		sm.vel = Vector3(cos(a) * _r * 0.7, rng.randf_range(0.8, 1.6), sin(a) * _r * 0.7)
		sm.drag = 3.5
		sm.size1 = _r * rng.randf_range(0.18, 0.26)
		sm.scale_k = 1.0
		sm.ease_size = 0.4
		sm.delay = 0.08
		sm.life = 1.1
		sm.fade_in = 0.1
		sm.fade_from = 0.35
	var shape := UiTokens.Shape.SQUARE if e == Enums.Element.NONE else UiTokens.element_shape(e)
	for i in 10:
		var d := sprite(shape, DEBRIS if i % 2 == 0 or e == Enums.Element.NONE else fire, rng.randf_range(0.07, 0.13) * _r / 3.0 + 0.04, Blend.MIX, true, true)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.4), rng.randf_range(-1, 1)).normalized()
		d.node.position = mid
		d.vel = dir * rng.randf_range(4.0, 8.0) * sqrt(_r / 3.0)
		d.gravity = 14.0
		d.spin_vel = rng.randf_range(-10.0, 10.0)
		d.life = rng.randf_range(0.6, 0.9)
		d.fade_from = 0.7
	if e == Enums.Element.LIGHT:
		for i in 5:
			var a := TAU * i / 5.0 + rng.randf_range(-0.3, 0.3)
			var tip := Vector3(cos(a), rng.randf_range(0.0, 0.5), sin(a)) * _r
			var arc := ribbon(zigzag(mid, tip, 6, _r * 0.08), 0.08, fire.lightened(0.3))
			arc.energy = 0.8 + 0.3 * flash_k
			arc.delay = rng.randf_range(0.0, 0.15)
			arc.life = 0.16
			arc.fade_from = 0.4
