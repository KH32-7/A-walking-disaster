extends FxEffect
## Combo magic (design 06 "조합 마법"), one look per ComboDef in data/essences/combos/.
## Size and time come from that ComboDef's effect_params (EffectDef.combo_id), so the picture matches
## the rule; the caller may still pass radius / zone_radius / zone_sec / duration_sec.
## Each combo mixes the shapes of its two elements, so it reads without colour:
##   combo_thorn_bush     green+stone  thorn spikes standing in a ring patch      (zone_radius, zone_sec)
##   combo_swamp          green+water  murky pool, rising bubbles, floating petals (zone_radius, zone_sec)
##   combo_photosynthesis green+light  heal ring out to radius, rising "+" signs   (radius)
##   combo_mud            stone+water  mud splat, guard-break square split, drips (duration_sec)
##   combo_shard_burst    stone+light  square shards blown out to radius, bolts   (radius)
##   combo_shock_puddle   water+light  puddle with bolts arcing along `chain`      (chain: Array[Vector3])

const GREEN := Enums.Element.GREEN
const STONE := Enums.Element.STONE
const WATER := Enums.Element.WATER
const LIGHT := Enums.Element.LIGHT
const POP := 0.15
## Wet earth for the mud combo (stone + water): saturated so it reads on grey concrete.
const MUD := Color(0.47, 0.33, 0.19)

var _sway: Array[Part] = []
var _hold := 3.0


func _build() -> void:
	match StringName(String(params.get("effect_id", &"")).trim_prefix("combo_")):
		&"thorn_bush":
			_thorn_bush()
		&"swamp":
			_swamp()
		&"photosynthesis":
			_photosynthesis()
		&"mud":
			_mud()
		&"shard_burst":
			_shard_burst()
		&"shock_puddle":
			_shock_puddle()
		_:
			_shard_burst()


func _tick(_k: float, _delta: float) -> void:
	# Hand-animated zone parts: pop up, sway while the zone holds, sink at the end.
	for part in _sway:
		var grow := clampf((age - part.delay) / POP, 0.0, 1.0)
		var sink := clampf((lifetime - age) / 0.3, 0.0, 1.0)
		var s := part.size1 * part.scale_k * ease(grow, 0.4) * sink
		part.node.visible = age >= part.delay
		part.node.scale = Vector3.ONE * maxf(s, 0.0001)
		var sway := sin(age * 5.0 + part.spin_vel) * 0.12
		part.set_look(part.color, part.spin + sway, part.squash)


func _col(e: int) -> Color:
	return UiTokens.element_color(e)


## Ground patch: filled disc + edge ring, fades in and out, lasts the whole effect.
func _patch(radius: float, fill: Color, edge: Color) -> void:
	var disc := ground(UiTokens.Shape.CIRCLE, fill, radius / 0.9)
	disc.fade_in = 0.06
	disc.fade_from = 0.85
	var ring := ground(FxShapes.Extra.RING, edge, radius)
	ring.node.position.y += 0.01
	ring.fade_in = 0.06
	ring.fade_from = 0.85
	ring.size0 = radius * 0.6
	ring.size1 = radius
	ring.ease_size = 0.15


func _standing(shape: int, color: Color, size: float, pos: Vector3, delay: float, squash := Vector2.ONE) -> Part:
	var p := sprite(shape, color, size, Blend.MIX, true, true)
	p.auto = false
	p.node.position = pos
	p.size1 = size
	p.delay = delay
	p.squash = squash
	p.spin = rng.randf_range(-0.25, 0.25)
	p.spin_vel = rng.randf() * TAU  # sway phase
	p.node.visible = false
	_sway.append(p)
	return p


func _thorn_bush() -> void:
	var r := p_float("zone_radius", 1.5)
	lifetime = p_float("zone_sec", 3.0) + 0.3
	_patch(r, Color(_col(GREEN).darkened(0.55), 0.4), Color(_col(GREEN), 0.85))
	for i in 11:
		var a := TAU * i / 11.0 + rng.randf_range(-0.2, 0.2)
		var d := r * (0.35 + 0.55 * rng.randf())
		var tall := rng.randf_range(0.45, 0.7)
		var col := _col(GREEN).darkened(0.1) if i % 2 == 0 else _col(STONE)
		_standing(FxShapes.Extra.SPIKE, col, tall, Vector3(cos(a) * d, tall * 0.9, sin(a) * d), i * 0.02, Vector2(1.1, 1.0))
	for i in 5:
		var a := TAU * i / 5.0
		_standing(UiTokens.Shape.PETAL, _col(GREEN), 0.14, Vector3(cos(a), 0.0, sin(a)) * r * 0.3 + Vector3.UP * 0.12, 0.1)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		_standing(UiTokens.Shape.SQUARE, _col(STONE).darkened(0.2), 0.1, Vector3(cos(a), 0.0, sin(a)) * r * 0.7 + Vector3.UP * 0.1, 0.12)


func _swamp() -> void:
	var r := p_float("zone_radius", 2.0)
	var hold := p_float("zone_sec", 3.0)
	lifetime = hold + 0.3
	var murk := _col(GREEN).lerp(_col(WATER), 0.45).darkened(0.5)
	_patch(r, Color(murk, 0.62), Color(_col(WATER), 0.8))
	for i in 16:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.85
		var b := sprite(FxShapes.Extra.RING, Color(_col(WATER).lightened(0.3), 0.9), 0.08, Blend.MIX)
		b.node.position = Vector3(cos(a) * d, 0.08, sin(a) * d)
		b.vel = Vector3.UP * 0.25
		b.size0 = 0.04
		b.size1 = rng.randf_range(0.12, 0.2)
		b.delay = rng.randf() * (hold - 0.4)
		b.life = 0.45
		b.fade_from = 0.7
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		_standing(UiTokens.Shape.PETAL, _col(GREEN), 0.14, Vector3(cos(a), 0.0, sin(a)) * r * 0.55 + Vector3.UP * 0.1, 0.05)
	for i in 3:
		var a := TAU * i / 3.0 + 1.2
		_standing(UiTokens.Shape.DROP, _col(WATER), 0.12, Vector3(cos(a), 0.0, sin(a)) * r * 0.35 + Vector3.UP * 0.12, 0.08)


func _photosynthesis() -> void:
	var r := p_float("radius", 5.0)
	lifetime = 1.4
	var heal := UiTokens.GOOD
	for i in 2:
		var ring := ground(FxShapes.Extra.RING, Color(_col(GREEN) if i == 0 else _col(LIGHT), 0.85), 0.3, Vector3.ZERO, Blend.ADD)
		ring.delay = i * 0.12
		ring.size1 = r
		ring.ease_size = 0.35
		ring.life = 0.8
		ring.fade_from = 0.5
	var glow := ground(UiTokens.Shape.CIRCLE, Color(_col(GREEN), 0.18), r * 0.2, Vector3.ZERO, Blend.ADD)
	glow.size1 = r * 1.05
	glow.ease_size = 0.35
	glow.life = 1.0
	glow.fade_from = 0.4
	for i in 9:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * r * 0.85
		var p := sprite(FxShapes.Extra.PLUS, heal, 0.2, Blend.MIX, true, true)
		p.node.position = Vector3(cos(a) * d, 0.3, sin(a) * d)
		p.vel = Vector3.UP * 1.3
		p.drag = 1.0
		p.delay = 0.1 + rng.randf() * 0.35
		p.life = 0.8
		p.fade_in = 0.15
		p.fade_from = 0.55
	for i in 8:
		var a := TAU * i / 8.0
		var leaf := sprite(UiTokens.Shape.PETAL if i % 2 == 0 else UiTokens.Shape.BOLT,
				_col(GREEN) if i % 2 == 0 else _col(LIGHT), 0.13, Blend.MIX, true, true)
		leaf.node.position = Vector3(cos(a), 0.4, sin(a)) * 0.4
		leaf.vel = Vector3(cos(a) * 2.5, 1.2, sin(a) * 2.5)
		leaf.drag = 2.0
		leaf.spin_vel = 4.0 if i % 2 == 0 else 0.0
		leaf.life = 0.9
		leaf.fade_from = 0.5


func _mud() -> void:
	var hold := p_float("duration_sec", 3.0)
	lifetime = hold + 0.3
	var mud := MUD
	var blob := ground(UiTokens.Shape.CIRCLE, Color(mud, 0.85), 0.4)
	var rim := ground(FxShapes.Extra.RING, Color(_col(WATER), 0.7), 0.5)
	rim.size1 = 1.3
	rim.ease_size = 0.15
	rim.fade_from = 0.85
	blob.size1 = 1.3
	blob.ease_size = 0.15
	blob.fade_from = 0.85
	for i in 10:
		var d := sprite(UiTokens.Shape.DROP if i % 2 == 0 else UiTokens.Shape.SQUARE,
				mud.lightened(0.15) if i % 3 else _col(WATER).darkened(0.2), rng.randf_range(0.12, 0.18), Blend.MIX, true, true)
		var a := TAU * i / 10.0
		d.node.position = Vector3.UP * 1.0
		d.vel = Vector3(cos(a) * 2.2, rng.randf_range(1.5, 3.0), sin(a) * 2.2)
		d.gravity = 12.0
		d.align = i % 2 == 0
		d.spin_vel = 0.0 if i % 2 == 0 else rng.randf_range(-8.0, 8.0)
		d.life = 0.55
		d.fade_from = 0.7
	# Guard break: a stone square splits in two and falls away (shape, not colour).
	for side in [-1.0, 1.0]:
		var half := sprite(FxShapes.Extra.SHARD, _col(STONE), 0.28, Blend.MIX, true, true)
		half.node.position = Vector3(side * 0.08, 1.5, 0.0)
		half.vel = Vector3(side * 1.4, 1.2, 0.0)
		half.gravity = 7.0
		half.spin = side * 0.3
		half.spin_vel = side * 5.0
		half.life = 0.6
		half.fade_from = 0.5
	for i in 6:
		var drip := sprite(UiTokens.Shape.DROP, mud.lightened(0.1), 0.08, Blend.MIX, true, true)
		var a := rng.randf() * TAU
		drip.node.position = Vector3(cos(a) * 0.25, 1.3, sin(a) * 0.25)
		drip.vel = Vector3.DOWN * 0.5
		drip.gravity = 6.0
		drip.delay = 0.4 + rng.randf() * (hold - 0.8)
		drip.life = 0.5
		drip.fade_from = 0.7


func _shard_burst() -> void:
	var r := p_float("radius", 2.0)
	lifetime = 0.8
	var star := sprite(UiTokens.Shape.STAR, Color(_col(LIGHT), maxf(flash_k, 0.5)), 0.3, Blend.ADD)
	star.node.position = Vector3.UP * 0.9
	star.size1 = r * 0.4
	star.ease_size = 0.25
	star.life = 0.2
	star.fade_from = 0.3
	star.energy = 0.8 + 0.3 * flash_k
	var ring := ground(FxShapes.Extra.RING, Color(_col(STONE).lightened(0.2), 0.9), 0.2, Vector3.ZERO, Blend.ADD)
	ring.size1 = r
	ring.ease_size = 0.3
	ring.life = 0.4
	ring.fade_from = 0.4
	for i in 12:
		var a := TAU * i / 12.0 + rng.randf_range(-0.15, 0.15)
		var s := sprite(UiTokens.Shape.SQUARE, _col(STONE) if i % 2 == 0 else _col(STONE).darkened(0.3), 0.15, Blend.MIX, true, true)
		s.node.position = Vector3.UP * 0.9
		s.vel = Vector3(cos(a), rng.randf_range(-0.1, 0.4), sin(a)) * r * 4.5
		s.drag = 5.0
		s.gravity = 3.0
		s.spin = rng.randf() * TAU
		s.spin_vel = rng.randf_range(-12.0, 12.0)
		s.life = 0.6
		s.fade_from = 0.6
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var arc := ribbon(zigzag(Vector3.UP * 0.9, Vector3(cos(a), 0.3, sin(a)) * r, 5, 0.18), 0.07, _col(LIGHT))
		arc.energy = 0.8 + 0.3 * flash_k
		arc.delay = 0.03 + rng.randf() * 0.1
		arc.life = 0.15
		arc.fade_from = 0.4
		var b := sprite(UiTokens.Shape.BOLT, _col(LIGHT), 0.15, Blend.MIX, true, true)
		b.node.position = Vector3(cos(a), 0.4, sin(a)) * r * 0.8
		b.delay = 0.05
		b.life = 0.4
		b.fade_from = 0.4


func _shock_puddle() -> void:
	var r := p_float("radius", 1.5)
	lifetime = 1.2
	_patch(r, Color(_col(WATER).darkened(0.35), 0.55), Color(_col(WATER), 0.85))
	var pts: Array[Vector3] = [Vector3.UP * 0.3]
	for p in params.get("chain", []):
		if p is Vector3:
			pts.append(to_local(p) + Vector3.UP * 0.9)
	if pts.size() == 1:
		for i in 3:
			var a := TAU * i / 3.0 + rng.randf_range(-0.3, 0.3)
			pts.append(Vector3(cos(a), 0.15, sin(a)) * r * 0.85)
	var from_center: bool = (params.get("chain", []) as Array).is_empty()
	for flick in 3:
		for i in range(1, pts.size()):
			var a: Vector3 = pts[0] if from_center else pts[i - 1]
			var arc := ribbon(zigzag(a, pts[i], 7, 0.2), 0.12, _col(LIGHT))
			arc.energy = 0.8 + 0.3 * flash_k
			arc.delay = flick * 0.22 + i * 0.04
			arc.life = 0.14
			arc.fade_from = 0.5
	for i in range(1, pts.size()):
		var b := sprite(UiTokens.Shape.BOLT, _col(LIGHT), 0.2, Blend.MIX, true, true)
		b.node.position = pts[i] + Vector3.UP * 0.25
		b.life = 0.9
		b.fade_from = 0.6
		var d := sprite(UiTokens.Shape.DROP, _col(WATER), 0.12, Blend.MIX, true, true)
		d.node.position = pts[i]
		d.vel = Vector3.UP * 2.5
		d.gravity = 9.0
		d.life = 0.5
		d.fade_from = 0.6
