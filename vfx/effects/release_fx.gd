extends FxEffect
## Essence release (design 06 "정수 해방", X at 100 mana). One look per class, in the weapon's element.
##   release_gun    `rounds` element shapes orbit the player, then snap into the weapon one by one
##   release_blade  blade storm: `hits` crescent sweeps around the player out to `radius`
##   release_blunt  ground slam: star crack, shockwave out to `radius`, debris, dust
## params: element (Armory stats element), radius, rounds / hits (base_params, design numbers),
## direction (gun: where the weapon points).

const HEIGHT := 1.1

var _kind := &"gun"
var _orbit: Array[Part] = []
var _sweeps: Array[Part] = []
var _r := 3.0
var _col := Color.WHITE
var _hits := 4


func _build() -> void:
	_kind = StringName(String(params.get("effect_id", &"release_gun")).trim_prefix("release_"))
	_col = element_color(UiTokens.ACCENT)
	_r = p_float("radius", 3.0)
	match _kind:
		&"blade":
			_blade()
		&"blunt":
			_blunt()
		_:
			_gun()


func _gun() -> void:
	lifetime = 1.1
	var n := int(params.get("rounds", 5))
	var shape := UiTokens.element_shape(p_element()) if p_element() != Enums.Element.NONE else UiTokens.Shape.DIAMOND
	for i in n:
		var p := sprite(shape, _col, 0.2, Blend.MIX, true, true)
		p.auto = false
		_orbit.append(p)
	var ring := ground(FxShapes.Extra.RING, Color(_col, 0.85), 1.4, Vector3.ZERO, Blend.ADD)
	ring.size0 = 1.6
	ring.size1 = 0.5
	ring.ease_size = 1.6
	ring.fade_from = 0.6
	var glow := sprite(UiTokens.Shape.STAR, Color(_col.lightened(0.3), maxf(flash_k, 0.5)), 0.2, Blend.ADD)
	glow.node.position = _muzzle()
	glow.delay = 0.75
	glow.size1 = 0.9
	glow.ease_size = 0.25
	glow.life = 0.3
	glow.fade_from = 0.3
	glow.energy = 0.8 + 0.3 * flash_k


func _blade() -> void:
	_hits = int(params.get("hits", 4))
	lifetime = 0.25 * _hits + 0.35
	var edge := ground(FxShapes.Extra.RING, Color(_col, 0.7), _r)
	edge.fade_in = 0.05
	edge.fade_from = 0.85
	for i in _hits:
		for j in 3:
			var c := sprite(FxShapes.Extra.CRESCENT, _col if j > 0 else Color(1, 0.98, 0.9), _r * 0.42, Blend.ADD, false)
			c.auto = false
			c.delay = i * 0.25
			c.spin = TAU * j / 3.0 + i * 0.9
			c.node.visible = false
			_sweeps.append(c)
	var shape := UiTokens.element_shape(p_element()) if p_element() != Enums.Element.NONE else UiTokens.Shape.DIAMOND
	for i in 14:
		var p := sprite(shape, _col, 0.14, Blend.MIX, true, true)
		var a := TAU * i / 14.0
		p.node.position = Vector3(cos(a), 0.6, sin(a)) * _r * 0.4
		p.vel = Vector3(-sin(a), 0.2, cos(a)) * _r * 2.2 + Vector3(cos(a), 0, sin(a)) * 1.5
		p.drag = 2.0
		p.spin_vel = 6.0
		p.delay = rng.randf() * (lifetime - 0.6)
		p.life = 0.5
		p.fade_from = 0.5


func _blunt() -> void:
	lifetime = 1.2
	var star := sprite(UiTokens.Shape.STAR, Color(_col.lightened(0.3), maxf(flash_k, 0.5)), 0.5, Blend.ADD)
	star.node.position = Vector3.UP * 0.4
	star.size1 = _r * 0.35
	star.scale_k = 1.0
	star.ease_size = 0.25
	star.life = 0.22
	star.fade_from = 0.3
	star.energy = 0.8 + 0.3 * flash_k
	for i in 2:
		var shock := ground(FxShapes.Extra.RING, Color(_col if i == 0 else Color(1, 0.95, 0.85), 0.9), 0.4, Vector3.ZERO, Blend.ADD)
		shock.delay = i * 0.08
		shock.size1 = _r
		shock.ease_size = 0.3
		shock.life = 0.5
		shock.fade_from = 0.35
	for i in 10:
		var k := ground(FxShapes.Extra.SPIKE, Color(0.1, 0.1, 0.11, 0.7), _r * 0.4)
		k.spin = TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
		var dir := Vector2(0, 1).rotated(k.spin)
		k.node.position += Vector3(dir.x, 0.0, -dir.y) * _r * 0.3
		k.size0 = 0.1
		k.size1 = _r * rng.randf_range(0.3, 0.45)
		k.ease_size = 0.2
		k.squash = Vector2(0.35, 1.0)
		k.fade_from = 0.7
	var shape := UiTokens.element_shape(p_element()) if p_element() != Enums.Element.NONE else UiTokens.Shape.SQUARE
	for i in 16:
		var d := sprite(shape if i % 2 == 0 else UiTokens.Shape.SQUARE, _col if i % 2 == 0 else Color(0.5, 0.48, 0.45),
				rng.randf_range(0.12, 0.2), Blend.MIX, true, true)
		var a := TAU * i / 16.0
		d.node.position = Vector3(cos(a), 0.1, sin(a)) * 0.5
		d.vel = Vector3(cos(a) * rng.randf_range(2.0, 4.0), rng.randf_range(4.0, 6.5), sin(a) * rng.randf_range(2.0, 4.0)) * sqrt(_r / 5.0)
		d.gravity = 16.0
		d.spin_vel = rng.randf_range(-9.0, 9.0)
		d.life = 0.85
		d.fade_from = 0.75
	for i in 10:
		var a := TAU * i / 10.0
		var dust := sprite(UiTokens.Shape.CIRCLE, Color(0.7, 0.67, 0.62, 0.6), 0.25, Blend.MIX, true, true)
		dust.node.position = Vector3(cos(a), 0.2, sin(a)) * 0.6
		dust.vel = Vector3(cos(a), 0.15, sin(a)) * _r * 1.6
		dust.drag = 3.0
		dust.size1 = 0.55
		dust.delay = 0.04
		dust.life = 1.0
		dust.fade_from = 0.3


func _muzzle() -> Vector3:
	var d: Vector3 = params.get("direction", Vector3.FORWARD)
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 0.0 else Vector3.FORWARD
	return Vector3.UP * HEIGHT + d * 0.6


func _tick(_k: float, _delta: float) -> void:
	if _kind == &"gun":
		var n := _orbit.size()
		var dest := _muzzle()
		for i in n:
			var p := _orbit[i]
			var land := 0.45 + i * 0.08  # each round flies into the weapon in turn
			var a := TAU * i / n + age * 6.0
			var circle := Vector3(cos(a), 0.0, sin(a)) * 0.9 + Vector3.UP * (HEIGHT + sin(age * 8.0 + i) * 0.08)
			var t := clampf((age - land) / 0.18, 0.0, 1.0)
			p.node.position = circle.lerp(dest, ease(t, 2.0))
			var grow := clampf(age / 0.15, 0.0, 1.0)
			p.node.scale = Vector3.ONE * 0.28 * p.scale_k * ease(grow, 0.4) * (1.0 - t * 0.6)
			p.node.visible = t < 1.0
			p.set_look(_col, a)
	elif _kind == &"blade":
		for c in _sweeps:
			var t := (age - c.delay) / 0.3
			c.node.visible = t >= 0.0 and t <= 1.0
			if not c.node.visible:
				continue
			c.node.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			c.node.position = Vector3.UP * (0.7 + 0.15 * sin(c.spin))
			var s := _r * lerpf(0.55, 1.0, ease(t, 0.5))
			c.node.scale = Vector3.ONE * s
			var a := 1.0 - t
			c.set_look(Color(c.color, a * 0.9), c.spin - t * PI * 1.4)
