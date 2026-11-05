extends FxEffect
## &"bullet_impact" (mode surface) and &"hit_spark" (mode body). No blood (design 16: no gore).
## bullet_impact params: normal (Vector3). Sparks along the normal, grey chips, a dust puff.
## hit_spark params (B weapon_holder / companion): element, crit, weak_point.
##   White star pop + sparks; element hits add 4 element shapes (petal / square / drop / bolt) in the
##   element colour; crit = bigger gold star + gold ring; weak point = cyan ring + rising diamond.
## Sound: EffectDef.sound / sound_crit (Fx plays it).

const SPARK := Color(1.0, 0.82, 0.42)
const CHIP := Color(0.62, 0.62, 0.6)
const DUST := Color(0.78, 0.76, 0.72, 0.55)


func _build() -> void:
	if params.get("mode", &"body") == &"surface":
		_surface()
	else:
		_body()


func _surface() -> void:
	lifetime = 0.5
	var n: Vector3 = params.get("normal", Vector3.UP)
	n = n.normalized() if n.length_squared() > 0.0 else Vector3.UP
	var star := sprite(UiTokens.Shape.STAR, Color(1, 0.95, 0.8, maxf(flash_k, 0.5)), 0.24, Blend.ADD)
	star.size1 = 0.06
	star.life = 0.1
	star.energy = 1.0
	for i in 6:
		var s := sprite(FxShapes.Extra.SHARD, SPARK, 0.08, Blend.ADD)
		s.vel = cone_dir(n, 0.9) * rng.randf_range(3.5, 7.0)
		s.gravity = 9.0
		s.drag = 3.0
		s.align = true
		s.stretch = 0.25
		s.squash = Vector2(0.6, 1.0)
		s.life = rng.randf_range(0.14, 0.24)
		s.energy = 1.0
	for i in 3:
		var c := sprite(UiTokens.Shape.SQUARE, CHIP, rng.randf_range(0.04, 0.07), Blend.MIX, true, true)
		c.vel = cone_dir(n, 0.7) * rng.randf_range(1.5, 3.0)
		c.gravity = 12.0
		c.spin_vel = rng.randf_range(-12.0, 12.0)
		c.life = rng.randf_range(0.3, 0.45)
	var d := sprite(UiTokens.Shape.CIRCLE, DUST, 0.12, Blend.MIX)
	d.node.position = n * 0.08
	d.vel = n * 0.4
	d.size1 = 0.45
	d.ease_size = 0.3
	d.fade_from = 0.2


func _body() -> void:
	lifetime = 0.45
	var crit: bool = params.get("crit", false)
	var weak: bool = params.get("weak_point", false)
	var e := p_element()
	var big := 1.45 if crit else 1.0
	var star_color := UiTokens.ACCENT if crit else Color(1, 1, 1)
	var star := sprite(UiTokens.Shape.STAR, Color(star_color, maxf(flash_k, 0.5)), 0.22 * big, Blend.ADD)
	star.size1 = 0.66 * big
	star.ease_size = 0.25
	star.life = 0.14
	star.fade_from = 0.35
	star.spin = rng.randf() * TAU
	star.energy = 0.8 + 0.3 * flash_k
	for i in (10 if crit else 6):
		var s := sprite(FxShapes.Extra.SHARD, star_color.lerp(SPARK, 0.3), 0.09 * big, Blend.ADD)
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		s.vel = dir * rng.randf_range(4.0, 7.5) * big
		s.drag = 6.0
		s.gravity = 4.0
		s.align = true
		s.stretch = 0.2
		s.squash = Vector2(0.55, 1.0)
		s.life = rng.randf_range(0.14, 0.24)
		s.energy = 1.0
	if e != Enums.Element.NONE:
		var col := UiTokens.element_color(e)
		for i in 4:
			var p := sprite(UiTokens.element_shape(e), col, 0.14, Blend.MIX, true, true)
			var a := TAU * (i + rng.randf_range(-0.2, 0.2)) / 4.0
			p.vel = Vector3(cos(a), rng.randf_range(0.6, 1.2), sin(a)) * rng.randf_range(1.6, 2.4)
			p.gravity = 0.0 if e == Enums.Element.LIGHT else 5.0
			p.drag = 2.5
			p.spin = rng.randf() * TAU if e != Enums.Element.LIGHT else 0.0
			p.spin_vel = 0.0 if e == Enums.Element.LIGHT else rng.randf_range(-6.0, 6.0)
			p.size1 = 0.09
			p.life = 0.42
			p.fade_from = 0.55
	if crit:
		var ring := sprite(FxShapes.Extra.RING, UiTokens.ACCENT, 0.2, Blend.ADD)
		ring.size1 = 0.95
		ring.ease_size = 0.3
		ring.life = 0.26
		ring.fade_from = 0.3
		ring.energy = 0.8
	if weak:
		var r := sprite(FxShapes.Extra.RING, UiTokens.INFO, 0.25, Blend.ADD)
		r.size1 = 0.75
		r.ease_size = 0.35
		r.life = 0.3
		r.fade_from = 0.2
		var d := sprite(UiTokens.Shape.DIAMOND, UiTokens.INFO, 0.16, Blend.MIX, true, true)
		d.node.position = Vector3.UP * 0.35
		d.vel = Vector3.UP * 0.8
		d.drag = 3.0
		d.life = 0.4
		d.fade_from = 0.5
