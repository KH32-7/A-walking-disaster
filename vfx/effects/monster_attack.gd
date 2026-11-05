extends FxEffect
## D-17 monster attack effects. One script, `mode` from the EffectDef base_params:
##   claw    three slash streaks in front (vine tendril, root crusher)       params: direction, range
##   slam    ground shockwave + dust + family debris (statue, golem, ram)   params: radius
##   bite    snapping crescents + sparks (rubble bug)                        params: direction
##   splash  water ring + droplets (swamp blob, mist, serpent)               params: radius
##   scream  rings from the head + drifting spores (spore pod alarm)         params: height
##   cast    a charging family shape that pops (signal wraith, spore pod)  params: direction, height
##   death   family shapes burst, dust slumps, ring fades (every monster)    params: radius
##   roots   spikes erupting along a line (tree giant root burst)            params: direction, length
##   summon  rotating ground glyph + rising petals (boss summons)            params: radius
## Every mode reads `element` (family colour and shape, UiTokens): colour is never the only cue.
## Sizes are metres at scale_k 1 unless a part is a camera-facing spark. reduce_flash: no white pops.

const DUST := Color(0.62, 0.58, 0.52, 0.75)
const DEBRIS := Color(0.42, 0.4, 0.37)
const WHITE := Color(1.0, 0.97, 0.9)

var _mode := &"slam"
var _dir := Vector3.FORWARD
var _col := WHITE
var _shape := UiTokens.Shape.SQUARE
var _glyph: Part


func _build() -> void:
	_mode = StringName(params.get("mode", &"slam"))
	var d: Vector3 = params.get("direction", Vector3.FORWARD)
	d.y = 0.0
	_dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_col = element_color(WHITE)
	var e := p_element()
	_shape = UiTokens.Shape.SQUARE if e == Enums.Element.NONE else UiTokens.element_shape(e)
	match _mode:
		&"claw": _claw()
		&"slam": _slam()
		&"bite": _bite()
		&"splash": _splash()
		&"scream": _scream()
		&"cast": _cast()
		&"death": _death()
		&"roots": _roots()
		&"summon": _summon()
		_: _slam()


func _tick(k: float, _delta: float) -> void:
	if _glyph:
		_glyph.spin = k * TAU * 0.5


# --- modes ---------------------------------------------------------------------------------------

func _claw() -> void:
	lifetime = 0.34
	var reach := p_float("range", 1.6)
	var side := _dir.cross(Vector3.UP).normalized()
	for i in 3:
		var off := side * (float(i) - 1.0) * 0.22
		var a := Vector3.UP * 1.25 + off + _dir * 0.25 - side * 0.35
		var b := Vector3.UP * 0.35 + off + _dir * reach + side * 0.35
		var pts := PackedVector3Array()
		for j in 7:
			var t := float(j) / 6.0
			pts.append(a.lerp(b, t) + _dir * sin(t * PI) * 0.25)
		var r := ribbon(pts, 0.15, Color(_col.lightened(0.25), 0.95))
		r.delay = 0.03 * i
		r.life = 0.26
		r.fade_from = 0.2
		r.energy = 1.2 * maxf(flash_k, 0.5)
	for i in 6:
		var s := sprite(_shape, _col, 0.07, Blend.MIX, true, true)
		s.node.position = Vector3.UP * 0.8 + _dir * reach * 0.8
		s.vel = cone_dir(_dir + Vector3.UP * 0.3, 0.9) * rng.randf_range(2.5, 4.5)
		s.gravity = 9.0
		s.spin_vel = rng.randf_range(-8.0, 8.0)
		s.life = 0.4
		s.delay = 0.06


func _slam() -> void:
	lifetime = 1.0
	var r := p_float("radius", 1.6)
	var ring := ground(FxShapes.Extra.RING, Color(_col.lightened(0.2), 0.9), r * 0.2, Vector3.ZERO, Blend.ADD)
	ring.size1 = r * 1.1
	ring.ease_size = 0.3
	ring.life = 0.35
	ring.fade_from = 0.25
	var crack := ground(UiTokens.Shape.STAR, Color(0.1, 0.09, 0.08, 0.6), r * 0.5)
	crack.size1 = r * 0.75
	crack.spin = rng.randf() * TAU
	crack.fade_in = 0.05
	crack.fade_from = 0.55
	for i in 10:
		var a := TAU * i / 10.0 + rng.randf_range(-0.25, 0.25)
		var dust := sprite(UiTokens.Shape.CIRCLE, DUST, r * 0.12, Blend.MIX, true, true)
		dust.node.position = Vector3(cos(a), 0.15, sin(a)) * r * 0.3
		dust.vel = Vector3(cos(a), rng.randf_range(0.2, 0.6), sin(a)) * r * 2.2
		dust.drag = 4.0
		dust.size1 = r * rng.randf_range(0.18, 0.28)
		dust.scale_k = 1.0
		dust.life = 0.8
		dust.fade_in = 0.08
		dust.fade_from = 0.35
	for i in 9:
		var deb := sprite(_shape, DEBRIS if i % 2 == 0 else _col, rng.randf_range(0.08, 0.14) * sqrt(r), Blend.MIX, true, true)
		deb.node.position = Vector3.UP * 0.2
		deb.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(0.8, 1.6), rng.randf_range(-1, 1)).normalized() * rng.randf_range(3.5, 6.5) * sqrt(r)
		deb.gravity = 16.0
		deb.spin_vel = rng.randf_range(-12.0, 12.0)
		deb.life = rng.randf_range(0.55, 0.8)
		deb.fade_from = 0.7
	if not reduced_flash:
		var pop := sprite(UiTokens.Shape.STAR, Color(WHITE, 0.8), r * 0.25, Blend.ADD)
		pop.node.position = Vector3.UP * 0.3
		pop.size1 = r * 0.5
		pop.scale_k = 1.0
		pop.life = 0.12
		pop.fade_from = 0.1


func _bite() -> void:
	lifetime = 0.3
	var at := Vector3.UP * 0.25 + _dir * 0.45
	var side := _dir.cross(Vector3.UP).normalized()
	for s: float in [-1.0, 1.0]:
		var c := sprite(FxShapes.Extra.CRESCENT, Color(_col.lightened(0.3), 0.95), 0.32, Blend.ADD)
		c.node.position = at + side * 0.18 * s
		c.vel = -side * 1.6 * s
		c.drag = 10.0
		c.spin = PI * 0.5 * s
		c.life = 0.16
		c.fade_from = 0.4
	for i in 5:
		var sp := sprite(_shape, _col, 0.05, Blend.ADD)
		sp.node.position = at
		sp.vel = cone_dir(_dir, 1.0) * rng.randf_range(2.0, 3.5)
		sp.align = true
		sp.stretch = 0.08
		sp.life = 0.22
		sp.delay = 0.05


func _splash() -> void:
	lifetime = 0.9
	var r := p_float("radius", 1.4)
	var water := element_color(UiTokens.element_color(Enums.Element.WATER))
	for i in 2:
		var ring := ground(FxShapes.Extra.RING, Color(water.lightened(0.3), 0.85), r * 0.25, Vector3.ZERO, Blend.ADD)
		ring.size1 = r * (1.0 + 0.4 * i)
		ring.delay = 0.12 * i
		ring.life = 0.5
		ring.fade_from = 0.3
	var pool := ground(UiTokens.Shape.CIRCLE, Color(water.darkened(0.3), 0.45), r * 0.5)
	pool.size1 = r * 0.9
	pool.fade_in = 0.05
	pool.fade_from = 0.5
	for i in 14:
		var drop := sprite(UiTokens.Shape.DROP, water, rng.randf_range(0.07, 0.12), Blend.MIX, true, true)
		drop.node.position = Vector3.UP * 0.3
		drop.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(1.2, 2.2), rng.randf_range(-1, 1)).normalized() * rng.randf_range(3.0, 5.0) * sqrt(r)
		drop.gravity = 14.0
		drop.align = true
		drop.stretch = 0.05
		drop.life = rng.randf_range(0.5, 0.75)
		drop.fade_from = 0.7


func _scream() -> void:
	lifetime = 1.2
	var head := Vector3.UP * p_float("height", 1.3)
	# Sound rings run out along the ground (how far the alarm carries reads at a glance), small ones pulse at the head.
	for i in 3:
		var ring := ground(FxShapes.Extra.RING, Color(_col.lightened(0.35), 0.8), 0.5, Vector3.ZERO, Blend.ADD)
		ring.size1 = 3.0 + i * 0.8
		ring.ease_size = 0.5
		ring.delay = 0.14 * i
		ring.life = 0.6
		ring.fade_from = 0.2
		var pulse := sprite(FxShapes.Extra.RING, Color(_col.lightened(0.35), 0.85), 0.15, Blend.ADD)
		pulse.node.position = head
		pulse.size1 = 0.55
		pulse.delay = 0.14 * i
		pulse.life = 0.35
		pulse.fade_from = 0.3
	for i in 12:
		var spore := sprite(UiTokens.Shape.PETAL if p_element() == Enums.Element.GREEN else _shape,
				Color(_col.lightened(0.15), 0.9), rng.randf_range(0.06, 0.1), Blend.MIX, true, true)
		spore.node.position = head
		spore.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 0.8), rng.randf_range(-1, 1)).normalized() * rng.randf_range(1.2, 2.6)
		spore.drag = 1.6
		spore.gravity = -0.4
		spore.spin_vel = rng.randf_range(-3.0, 3.0)
		spore.delay = 0.05
		spore.life = 1.0
		spore.fade_in = 0.1
		spore.fade_from = 0.5


func _cast() -> void:
	lifetime = 0.55
	var at := Vector3.UP * p_float("height", 1.4) + _dir * 0.4
	var core := sprite(_shape, _col, 0.15, Blend.ADD, true, true)
	core.node.position = at
	core.size1 = 0.55
	core.ease_size = 2.0
	core.spin_vel = 6.0
	core.life = 0.45
	core.fade_from = 0.85
	core.energy = 1.3 * maxf(flash_k, 0.5)
	for i in 8:
		var a := TAU * i / 8.0
		var sp := sprite(UiTokens.Shape.CIRCLE, Color(_col.lightened(0.3), 0.9), 0.08, Blend.ADD)
		var off := Vector3(cos(a), sin(a) * 0.6, sin(a)) * 0.7
		sp.node.position = at + off
		sp.vel = -off * 2.0
		sp.life = 0.35
		sp.fade_in = 0.2
		sp.fade_from = 0.6
	if not reduced_flash:
		var pop := sprite(UiTokens.Shape.STAR, Color(WHITE, 0.85), 0.3, Blend.ADD)
		pop.node.position = at
		pop.size1 = 0.7
		pop.delay = 0.4
		pop.life = 0.12
		pop.fade_from = 0.1


func _death() -> void:
	lifetime = 1.4
	var r := p_float("radius", 0.9)
	var mid := Vector3.UP * r * 0.8
	for i in 8:
		var bit := sprite(_shape, _col, rng.randf_range(0.08, 0.14) * sqrt(r), Blend.MIX, true, true)
		bit.node.position = mid
		bit.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(0.4, 1.2), rng.randf_range(-1, 1)).normalized() * rng.randf_range(2.0, 3.8) * sqrt(r)
		bit.gravity = 7.0
		bit.spin_vel = rng.randf_range(-8.0, 8.0)
		bit.life = rng.randf_range(0.6, 0.9)
		bit.fade_from = 0.5
	for i in 7:
		var smoke := sprite(UiTokens.Shape.CIRCLE, Color(_col.darkened(0.45), 0.55), r * 0.25, Blend.MIX, true, true)
		var a := TAU * i / 7.0
		smoke.node.position = Vector3(cos(a), 0.2, sin(a)) * r * 0.4
		smoke.vel = Vector3(cos(a) * 0.6, rng.randf_range(0.5, 1.0), sin(a) * 0.6)
		smoke.drag = 1.5
		smoke.size1 = r * 0.55
		smoke.scale_k = 1.0
		smoke.delay = 0.15
		smoke.life = 1.1
		smoke.fade_in = 0.15
		smoke.fade_from = 0.35
	var ring := ground(FxShapes.Extra.RING, Color(_col, 0.7), r * 0.4, Vector3.ZERO, Blend.ADD)
	ring.size1 = r * 1.6
	ring.life = 0.7
	ring.fade_from = 0.2
	var core := sprite(_shape, Color(_col.lightened(0.3), 1.0), 0.35 * sqrt(r), Blend.ADD, true, true)
	core.node.position = mid
	core.size1 = 0.02
	core.ease_size = 1.5
	core.spin_vel = 4.0
	core.life = 0.5
	core.energy = 1.2 * maxf(flash_k, 0.5)


func _roots() -> void:
	lifetime = 1.1
	var length := p_float("length", 6.0)
	var n := int(clampf(length / 0.7, 4, 14))
	var side := _dir.cross(Vector3.UP).normalized()
	for i in n:
		var t := (float(i) + 0.5) / n
		var at := _dir * length * t + side * rng.randf_range(-0.3, 0.3)
		var tall := rng.randf_range(0.7, 1.1)
		var spike := sprite(FxShapes.Extra.SPIKE, Color(0.5, 0.36, 0.22) if i % 2 == 0 else _col.darkened(0.2),
				tall, Blend.MIX, true, true)
		spike.node.position = at + Vector3.UP * tall * 0.9
		spike.spin = rng.randf_range(-0.3, 0.3)
		spike.size0 = tall * 0.15
		spike.ease_size = 0.25
		spike.delay = t * 0.3
		spike.life = 0.8
		spike.fade_from = 0.65
		for j in 2:
			var clod := sprite(UiTokens.Shape.SQUARE, DEBRIS, 0.09, Blend.MIX, true, true)
			clod.node.position = at + Vector3.UP * 0.1
			clod.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(2.0, 3.5), rng.randf_range(-1, 1))
			clod.gravity = 12.0
			clod.spin_vel = rng.randf_range(-10.0, 10.0)
			clod.delay = t * 0.3
			clod.life = 0.55
		var crack := ground(UiTokens.Shape.CIRCLE, Color(0.1, 0.08, 0.06, 0.5), 0.35, at)
		crack.delay = t * 0.3
		crack.life = 0.9
		crack.fade_from = 0.6
		var leaf := sprite(UiTokens.Shape.PETAL, _col, 0.08, Blend.MIX, true, true)
		leaf.node.position = at + Vector3.UP * 0.4
		leaf.vel = Vector3(rng.randf_range(-1, 1), rng.randf_range(1.0, 2.0), rng.randf_range(-1, 1)) * 1.5
		leaf.gravity = 5.0
		leaf.delay = t * 0.3 + 0.05
		leaf.life = 0.6


func _summon() -> void:
	lifetime = 1.4
	var r := p_float("radius", 2.2)
	_glyph = ground(UiTokens.Shape.STAR, Color(_col, 0.75), r * 0.3, Vector3.ZERO, Blend.ADD)
	_glyph.size1 = r
	_glyph.ease_size = 0.3
	_glyph.fade_in = 0.1
	_glyph.fade_from = 0.6
	var ring := ground(FxShapes.Extra.RING, Color(_col.lightened(0.3), 0.85), r, Vector3.ZERO, Blend.ADD)
	ring.size1 = r * 1.05
	ring.fade_in = 0.1
	ring.fade_from = 0.6
	for i in 14:
		var a := TAU * i / 14.0
		var p := sprite(UiTokens.Shape.PETAL if p_element() == Enums.Element.GREEN else _shape,
				Color(_col.lightened(0.2), 0.9), 0.09, Blend.MIX, true, true)
		p.node.position = Vector3(cos(a), 0.1, sin(a)) * r * 0.9
		p.vel = Vector3(-cos(a) * 0.5, rng.randf_range(1.5, 2.5), -sin(a) * 0.5)
		p.drag = 1.2
		p.spin_vel = rng.randf_range(-4.0, 4.0)
		p.delay = rng.randf_range(0.0, 0.4)
		p.life = 0.9
		p.fade_from = 0.5

