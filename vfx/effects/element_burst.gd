extends FxEffect
## &"element_green" | &"element_stone" | &"element_water" | &"element_light": an element taking effect
## on a target (essence proc, status applied, element weak hit). Each element moves differently AND
## uses its own shape, so it reads without colour (design 06, UI_RULES §2):
##   green  petals spiral up and out around a leaf ring
##   stone  square chunks thrown up and falling, ground crack spikes
##   water  drops splash up in a crown, ripples on the ground
##   light  bolts burst outward with jagged arcs
## params: element (from base_params), scale (1 = man-sized target).

const HEIGHT := 1.0


func _build() -> void:
	lifetime = 0.8
	var s := p_float("scale", 1.0)
	match p_element():
		Enums.Element.GREEN:
			_green(s)
		Enums.Element.STONE:
			_stone(s)
		Enums.Element.WATER:
			_water(s)
		Enums.Element.LIGHT:
			_light(s)
		_:
			_green(s)


func _green(s: float) -> void:
	var col := UiTokens.element_color(Enums.Element.GREEN)
	var dark := col.darkened(0.35)
	for i in 10:
		var p := sprite(UiTokens.Shape.PETAL, col if i % 2 == 0 else dark.lightened(0.15), 0.16 * s, Blend.MIX, true, true)
		var a := TAU * i / 10.0
		p.node.position = Vector3(cos(a) * 0.55, 0.5, sin(a) * 0.55) * s
		p.vel = Vector3(cos(a + 0.9), rng.randf_range(1.0, 1.8), sin(a + 0.9)) * 1.7 * s
		p.drag = 2.0
		p.gravity = -0.3
		p.spin = a
		p.spin_vel = 5.0
		p.delay = i * 0.02
		p.life = 0.65
		p.fade_from = 0.55
	var ring := ground(FxShapes.Extra.RING, Color(col, 0.75), 0.3 * s)
	ring.size1 = 1.3 * s
	ring.ease_size = 0.35
	ring.life = 0.5
	ring.fade_from = 0.3
	var core := sprite(UiTokens.Shape.PETAL, Color(col.lightened(0.4), 0.9 * maxf(flash_k, 0.6)), 0.25 * s, Blend.ADD)
	core.node.position = Vector3.UP * HEIGHT
	core.size1 = 0.6 * s
	core.life = 0.25
	core.fade_from = 0.2


func _stone(s: float) -> void:
	var col := UiTokens.element_color(Enums.Element.STONE)
	for i in 9:
		var c := sprite(UiTokens.Shape.SQUARE, col if i % 3 else col.darkened(0.3), rng.randf_range(0.1, 0.18) * s, Blend.MIX, true, true)
		var a := TAU * i / 9.0 + rng.randf_range(-0.2, 0.2)
		c.node.position = Vector3(cos(a), 0.1, sin(a)) * 0.25 * s
		c.vel = Vector3(cos(a) * rng.randf_range(1.2, 2.2), rng.randf_range(3.5, 5.0), sin(a) * rng.randf_range(1.2, 2.2)) * s
		c.gravity = 16.0
		c.spin = rng.randf() * TAU
		c.spin_vel = rng.randf_range(-9.0, 9.0)
		c.life = 0.7
		c.fade_from = 0.75
	for i in 6:
		var k := ground(FxShapes.Extra.SPIKE, Color(col.darkened(0.45), 0.85), 0.55 * s)
		k.spin = TAU * i / 6.0 + rng.randf_range(-0.25, 0.25)
		var dir := Vector2(0, 1).rotated(k.spin)
		k.node.position += Vector3(dir.x, 0.0, -dir.y) * 0.55 * s * 0.6  # mesh +Y lies along world -Z
		k.size0 = 0.1 * s
		k.size1 = 0.55 * s
		k.ease_size = 0.25
		k.squash = Vector2(0.5, 1.0)
		k.life = 0.8
		k.fade_from = 0.6
	var dust := ground(UiTokens.Shape.CIRCLE, Color(col.lightened(0.3), 0.45), 0.4 * s)
	dust.size1 = 1.4 * s
	dust.ease_size = 0.3
	dust.life = 0.6
	dust.fade_from = 0.2


func _water(s: float) -> void:
	var col := UiTokens.element_color(Enums.Element.WATER)
	for i in 12:
		var d := sprite(UiTokens.Shape.DROP, col if i % 2 == 0 else col.lightened(0.35), rng.randf_range(0.09, 0.14) * s, Blend.MIX, true, true)
		var a := TAU * i / 12.0
		d.node.position = Vector3(cos(a), 0.15, sin(a)) * 0.3 * s
		d.vel = Vector3(cos(a) * 1.4, rng.randf_range(3.0, 4.2), sin(a) * 1.4) * s
		d.gravity = 13.0
		d.align = true  # drops point the way they fly
		d.squash = Vector2(1.0, 1.0)
		d.life = 0.65
		d.fade_from = 0.7
	for i in 3:
		var r := ground(FxShapes.Extra.RING, Color(col, 0.8), 0.2 * s)
		r.delay = i * 0.12
		r.size1 = (1.0 + i * 0.4) * s
		r.ease_size = 0.4
		r.life = 0.55
		r.fade_from = 0.2
	var pool := ground(UiTokens.Shape.CIRCLE, Color(col.darkened(0.2), 0.35), 0.5 * s)
	pool.size1 = 1.0 * s
	pool.life = 0.8
	pool.fade_from = 0.5


func _light(s: float) -> void:
	var col := UiTokens.element_color(Enums.Element.LIGHT)
	var center := Vector3.UP * HEIGHT
	var core := sprite(UiTokens.Shape.STAR, Color(1, 1, 0.85, maxf(flash_k, 0.5)), 0.3 * s, Blend.ADD)
	core.node.position = center
	core.size1 = 0.6 * s
	core.ease_size = 0.25
	core.life = 0.18
	core.fade_from = 0.3
	core.energy = 0.8 + 0.3 * flash_k
	for i in 6:
		var a := TAU * i / 6.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a), rng.randf_range(-0.6, 0.6), sin(a)).normalized()
		var arc := ribbon(zigzag(center, center + dir * rng.randf_range(0.9, 1.4) * s, 5, 0.16 * s), 0.07 * s, col)
		arc.energy = 0.8 + 0.3 * flash_k
		arc.delay = rng.randf_range(0.0, 0.12)
		arc.life = 0.14
		arc.fade_from = 0.3
		var b := sprite(UiTokens.Shape.BOLT, col, 0.16 * s, Blend.MIX, true, true)
		b.node.position = center + dir * 0.4 * s
		b.vel = dir * 3.0 * s
		b.drag = 4.0
		b.life = 0.5
		b.fade_from = 0.5
