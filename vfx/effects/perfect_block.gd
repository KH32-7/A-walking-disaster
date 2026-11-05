extends FxEffect
## &"perfect_block": gold star at chest height, two expanding rings, 8 sparks flung out sideways and a
## gold ring on the ground. params: none (B passes the weapon holder position = the player's feet).

const HEIGHT := 1.1


func _build() -> void:
	lifetime = 0.45
	var at := Vector3.UP * HEIGHT
	var star := sprite(UiTokens.Shape.STAR, Color(UiTokens.ACCENT, maxf(flash_k, 0.5)), 0.3, Blend.ADD)
	star.node.position = at
	star.size1 = 0.7
	star.ease_size = 0.25
	star.life = 0.2
	star.fade_from = 0.3
	star.energy = 0.8 + 0.3 * flash_k
	for i in 2:
		var r := sprite(FxShapes.Extra.RING, Color(1, 0.95, 0.8) if i == 0 else UiTokens.ACCENT, 0.3, Blend.ADD)
		r.node.position = at
		r.delay = i * 0.06
		r.size1 = 1.0 + i * 0.3
		r.ease_size = 0.3
		r.life = 0.3
		r.fade_from = 0.25
	for i in 8:
		var s := sprite(FxShapes.Extra.SHARD, UiTokens.ACCENT, 0.11, Blend.ADD)
		s.node.position = at
		var a := TAU * i / 8.0 + rng.randf_range(-0.2, 0.2)
		s.vel = Vector3(cos(a), rng.randf_range(-0.2, 0.4), sin(a)) * rng.randf_range(5.0, 7.0)
		s.drag = 7.0
		s.align = true
		s.stretch = 0.2
		s.squash = Vector2(0.55, 1.0)
		s.life = 0.24
	var g := ground(FxShapes.Extra.RING, Color(UiTokens.ACCENT, 0.8), 0.4, Vector3.ZERO, Blend.ADD)
	g.size1 = 2.2
	g.ease_size = 0.3
	g.life = 0.35
	g.fade_from = 0.2
