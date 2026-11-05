extends FxEffect
## &"muzzle_flash": star pop + two flame tongues along `direction`.
## params: direction (Vector3, B: shot forward). Settings.reduce_flash: dimmer star.
## No point light: on the toon ground a short light shows as a hard-edged blob, not a glow.

const COLOR := Color(1.0, 0.86, 0.45)
const CORE := Color(1.0, 0.98, 0.9)


func _build() -> void:
	lifetime = 0.08
	var dir: Vector3 = params.get("direction", Vector3.FORWARD)
	dir = dir.normalized() if dir.length_squared() > 0.0 else Vector3.FORWARD
	var star := sprite(UiTokens.Shape.STAR, Color(CORE, maxf(flash_k, 0.5)), 0.34, Blend.ADD)
	star.size1 = 0.2
	star.spin = rng.randf() * TAU
	star.energy = 0.8 + 0.4 * flash_k
	star.fade_from = 0.2
	for i in 2:
		var f := sprite(FxShapes.Extra.SHARD, COLOR, 0.32 - i * 0.08, Blend.ADD)
		f.node.position = dir * (0.2 + i * 0.14)
		f.vel = dir * 0.01  # only to align the tongue with the barrel on screen
		f.align = true
		f.squash = Vector2(0.9, 1.6)
		f.energy = 0.8 + 0.3 * flash_k
		f.fade_from = 0.3
