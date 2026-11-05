extends FxEffect
## &"noise_lure" (design 03: thrown, makes a 15 m noise after 4 s). Spawn where it lands.
## A ticking light blinks faster and faster while a countdown ring shrinks around it (time shown by
## size, not colour), then three sound-wave rings burst out. The 15 m noise itself is Lane B's
## (EventBus.noise_emitted -> D-05 noise ring); this only shows the lure.
## params: fuse_sec (base_params, design 4 s), radius (burst ring size, m).

const BODY := Color(0.36, 0.38, 0.42)
const BEEP := &"lure_beep"

var _blink: Part
var _count: Part
var _fuse := 4.0
var _next_beep := 0.0
var _burst := false


func _build() -> void:
	_fuse = p_float("fuse_sec", 4.0)
	lifetime = _fuse + 0.8
	var can := sprite(UiTokens.Shape.SQUARE, BODY, 0.16, Blend.MIX, true, true)
	can.node.position = Vector3.UP * 0.16
	can.squash = Vector2(0.8, 1.2)
	can.life = _fuse + 0.1
	can.fade_from = 0.97
	_blink = sprite(UiTokens.Shape.CIRCLE, UiTokens.WARN, 0.11, Blend.MIX, true, true)
	_blink.auto = false
	_blink.node.position = Vector3.UP * 0.42
	_count = ground(FxShapes.Extra.RING, Color(UiTokens.WARN, 0.9), 1.2)
	_count.auto = false
	var r := p_float("radius", 3.0)
	for i in 3:
		var w := ground(FxShapes.Extra.RING, Color(UiTokens.WARN, 0.95), 0.3, Vector3.ZERO, Blend.MIX)
		w.delay = _fuse + i * 0.12
		w.size1 = r * (0.6 + i * 0.2)
		w.ease_size = 0.4
		w.life = 0.55
		w.fade_from = 0.2
		w.node.visible = false
	var pop := sprite(UiTokens.Shape.STAR, Color(UiTokens.WARN.lightened(0.3), maxf(flash_k, 0.5)), 0.3, Blend.ADD)
	pop.node.position = Vector3.UP * 0.4
	pop.delay = _fuse
	pop.size1 = 1.0
	pop.ease_size = 0.25
	pop.life = 0.25
	pop.fade_from = 0.3
	pop.node.visible = false
	_tick(0.0, 0.0)


func _tick(_k: float, _delta: float) -> void:
	var left := _fuse - age
	if left > 0.0:
		# Blink period shrinks from 0.6 s to 0.12 s as the fuse runs out.
		var period := lerpf(0.12, 0.6, clampf(left / _fuse, 0.0, 1.0))
		var on := fmod(age, period) < period * 0.45
		_blink.node.visible = true
		_blink.node.scale = Vector3.ONE * (0.13 if on else 0.09) * _blink.scale_k
		_blink.set_look(UiTokens.WARN.lightened(0.25) if on else UiTokens.WARN.darkened(0.45), 0.0)
		_count.node.visible = true
		_count.node.scale = Vector3.ONE * lerpf(0.25, 1.2, left / _fuse)
		_count.set_look(Color(UiTokens.WARN, 0.85), 0.0)
		if age >= _next_beep and not params.get("silent", false):
			Audio.play(BEEP, global_position)
			_next_beep = age + period
	else:
		_blink.node.visible = false
		_count.node.visible = false
