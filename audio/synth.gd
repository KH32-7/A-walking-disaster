class_name Synth
## Placeholder sounds made in code (D-11). Owner: Lane D. No audio files in the public repo:
## each recipe builds an AudioStreamWAV once and caches it. Replace by setting AudioEventDef.stream.

const RATE := 22050

static var _cache: Dictionary = {}


static func make(recipe: StringName) -> AudioStreamWAV:
	if _cache.has(recipe):
		return _cache[recipe]
	var s: AudioStreamWAV
	match recipe:
		&"shot_light": s = _shot(0.18, 900.0, 0.9)
		&"shot_heavy": s = _shot(0.32, 500.0, 1.0)
		&"shot_boom": s = _shot(0.5, 260.0, 1.0)
		&"click": s = _tone(0.03, 2200.0, 0.0, 0.5, 0.0, 0.6)
		&"reload": s = _concat([_noise(0.05, 0.5, 3000.0), _silence(0.12), _noise(0.07, 0.6, 1800.0)])
		&"swing": s = _sweep_noise(0.22, 600.0, 2400.0, 0.5)
		&"thud": s = _tone(0.16, 120.0, -60.0, 0.9, 0.35, 0.0)
		&"block": s = _concat([_tone(0.08, 900.0, -200.0, 0.6, 0.4, 0.2), _noise(0.05, 0.3, 4000.0)])
		&"ting": s = _tone(0.45, 1760.0, 0.0, 0.5, 0.0, 0.0, 6.0)
		&"break": s = _noise(0.35, 0.9, 900.0)
		&"step": s = _noise(0.06, 0.35, 700.0)
		&"splash": s = _sweep_noise(0.4, 2600.0, 500.0, 0.55)
		&"hurt": s = _tone(0.22, 220.0, -80.0, 0.7, 0.5, 0.15)
		&"monster_sus": s = _tone(0.32, 330.0, 330.0, 0.5, 0.2, 0.0, 9.0)
		&"monster_alert": s = _concat([_tone(0.1, 880.0, 0.0, 0.6, 0.0, 0.1), _tone(0.16, 660.0, 0.0, 0.6, 0.0, 0.1)])
		&"monster_growl": s = _tone(0.6, 70.0, 20.0, 0.8, 0.6, 0.4)
		&"leaf_rustle": s = _noise(0.5, 0.35, 5000.0)
		&"open": s = _concat([_noise(0.08, 0.4, 1200.0), _tone(0.12, 520.0, 120.0, 0.35, 0.1, 0.0)])
		&"pickup": s = _concat([_tone(0.06, 660.0, 0.0, 0.4, 0.0, 0.0), _tone(0.09, 990.0, 0.0, 0.4, 0.0, 0.0)])
		&"ui_click": s = _tone(0.04, 1400.0, -300.0, 0.35, 0.0, 0.0)
		&"ui_open": s = _tone(0.12, 520.0, 380.0, 0.3, 0.0, 0.0)
		&"ui_close": s = _tone(0.12, 900.0, -380.0, 0.3, 0.0, 0.0)
		&"ui_confirm": s = _concat([_tone(0.07, 784.0, 0.0, 0.35, 0.0, 0.0), _tone(0.12, 1175.0, 0.0, 0.35, 0.0, 0.0)])
		&"ui_error": s = _concat([_tone(0.08, 330.0, 0.0, 0.4, 0.2, 0.0), _tone(0.12, 262.0, 0.0, 0.4, 0.2, 0.0)])
		&"radio_blip": s = _concat([_noise(0.06, 0.25, 3500.0), _tone(0.08, 1320.0, 0.0, 0.3, 0.0, 0.0)])
		&"extract": s = _chord(1.2, [523.25, 659.25, 783.99], 0.3)
		&"warning": s = _concat([_tone(0.2, 740.0, 0.0, 0.55, 0.0, 0.0), _silence(0.08), _tone(0.2, 740.0, 0.0, 0.55, 0.0, 0.0)])
		&"music_base": s = _music_base()
		&"music_field": s = _music_field()
		&"music_chase": s = _music_chase()
		&"music_night": s = _music_pad([110.0, 130.81, 164.81], 8.0, 0.18)
		&"music_raid": s = _music_raid()
		_: s = _tone(0.1, 440.0, 0.0, 0.3, 0.0, 0.0)
	_cache[recipe] = s
	return s


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


static func _env(t: float, dur: float, attack := 0.005) -> float:
	if t < attack:
		return t / attack
	return pow(maxf(0.0, 1.0 - (t - attack) / maxf(0.001, dur - attack)), 2.0)


## Sine with pitch slide, optional square-ish grit and vibrato.
static func _tone(dur: float, f0: float, slide: float, amp: float, grit: float, noise: float, vib := 0.0) -> AudioStreamWAV:
	return _wav(_tone_s(dur, f0, slide, amp, grit, noise, vib))


static func _tone_s(dur: float, f0: float, slide: float, amp: float, grit: float, noise: float, vib := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 100.0)
	for i in n:
		var t := float(i) / RATE
		var f := f0 + slide * t / dur + (sin(t * TAU * vib) * f0 * 0.03 if vib > 0.0 else 0.0)
		ph += TAU * f / RATE
		var v := sin(ph)
		v = lerpf(v, signf(v), grit)
		v += rng.randf_range(-1.0, 1.0) * noise
		out[i] = v * amp * _env(t, dur)
	return out


static func _noise(dur: float, amp: float, cutoff: float) -> AudioStreamWAV:
	return _wav(_noise_s(dur, amp, cutoff))


static func _noise_s(dur: float, amp: float, cutoff: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff)
	var a := clampf(TAU * cutoff / RATE, 0.0, 1.0)
	var y := 0.0
	for i in n:
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * amp * 2.5 * _env(float(i) / RATE, dur)
	return out


static func _sweep_noise(dur: float, c0: float, c1: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var a := clampf(TAU * lerpf(c0, c1, t / dur) / RATE, 0.0, 1.0)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * amp * 2.5 * sin(PI * t / dur)
	return _wav(out)


static func _shot(dur: float, body: float, amp: float) -> AudioStreamWAV:
	var a := _noise_s(dur, amp, 3500.0)
	var b := _tone_s(dur * 0.6, body, -body * 0.6, amp * 0.8, 0.3, 0.0)
	for i in b.size():
		a[i] = clampf(a[i] + b[i], -1.0, 1.0)
	return _wav(a)


static func _silence(dur: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(dur * RATE))
	return _wav(out)


static func _concat(parts: Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	for p: AudioStreamWAV in parts:
		data.append_array(p.data)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


static func _chord(dur: float, freqs: Array, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var start := k * 0.08
			if t >= start:
				v += sin(TAU * float(freqs[k]) * (t - start)) * _env(t - start, dur - start, 0.01)
		out[i] = v * amp / freqs.size() * 1.6
	return _wav(out)


## Plucked note (Karplus-Strong-ish via decaying harmonics) mixed into `out` at `at` seconds.
static func _pluck(out: PackedFloat32Array, at: float, f: float, amp: float, dur := 1.2) -> void:
	var s := int(at * RATE)
	var n := mini(int(dur * RATE), out.size() - s)
	for i in n:
		var t := float(i) / RATE
		var v := sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) * exp(-t * 6.0) + 0.25 * sin(TAU * f * 3.0 * t) * exp(-t * 9.0)
		out[s + i] += v * amp * exp(-t * 3.2)


static func _music_base() -> AudioStreamWAV:
	# Warm acoustic loop: C - Am - F - G, arpeggiated plucks, 4 bars at 84 bpm.
	var bar := 60.0 / 84.0 * 4.0
	var out := PackedFloat32Array()
	out.resize(int(bar * 4 * RATE))
	var chords := [[261.63, 329.63, 392.0], [220.0, 261.63, 329.63], [174.61, 220.0, 261.63], [196.0, 246.94, 293.66]]
	var beat := bar / 8.0
	for c in 4:
		var ch: Array = chords[c]
		_pluck(out, c * bar, float(ch[0]) * 0.5, 0.22, bar)
		for k in 8:
			_pluck(out, c * bar + k * beat, float(ch[k % 3]) * (2.0 if k == 7 else 1.0), 0.12, 1.0)
	return _wav(_soft_clip(out), true)


static func _music_field() -> AudioStreamWAV:
	var dur := 12.0
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var wind := _noise_s(dur, 0.18, 400.0)
	for i in n:
		var t := float(i) / RATE
		var pad := (sin(TAU * 98.0 * t) + sin(TAU * 146.83 * t) * 0.6 + sin(TAU * 196.0 * t) * 0.3) * 0.07
		var swell := 0.6 + 0.4 * sin(TAU * t / dur)
		out[i] = pad * swell + wind[i] * (0.6 + 0.4 * sin(TAU * t / 6.0))
	return _wav(_loop_fade(out), true)


static func _music_chase() -> AudioStreamWAV:
	var bar := 60.0 / 132.0 * 4.0
	var out := PackedFloat32Array()
	out.resize(int(bar * 2 * RATE))
	for k in 16:
		var at := k * bar / 8.0
		var s := int(at * RATE)
		for i in mini(int(0.12 * RATE), out.size() - s):
			var t := float(i) / RATE
			out[s + i] += sin(TAU * (73.42 if k % 4 != 3 else 87.31) * t) * 0.3 * exp(-t * 18.0)
	return _wav(_soft_clip(out), true)


static func _music_pad(freqs: Array, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t + sin(TAU * 0.3 * t) * 0.5)
		out[i] = v * amp / freqs.size() * (0.7 + 0.3 * sin(TAU * t / dur))
	return _wav(_loop_fade(out), true)


static func _music_raid() -> AudioStreamWAV:
	var bar := 60.0 / 120.0 * 4.0
	var out := PackedFloat32Array()
	out.resize(int(bar * 2 * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for k in 16:
		var at := k * bar / 8.0
		var s := int(at * RATE)
		var kick := k % 4 == 0
		for i in mini(int(0.2 * RATE), out.size() - s):
			var t := float(i) / RATE
			if kick:
				out[s + i] += sin(TAU * (60.0 + 80.0 * exp(-t * 30.0)) * t) * 0.6 * exp(-t * 10.0)
			elif k % 4 == 2:
				out[s + i] += rng.randf_range(-1, 1) * 0.3 * exp(-t * 25.0)
			else:
				out[s + i] += rng.randf_range(-1, 1) * 0.08 * exp(-t * 60.0)
	return _wav(_soft_clip(out), true)


static func _soft_clip(a: PackedFloat32Array) -> PackedFloat32Array:
	for i in a.size():
		a[i] = tanh(a[i] * 1.2) * 0.9
	return a


static func _loop_fade(a: PackedFloat32Array) -> PackedFloat32Array:
	var f := int(0.25 * RATE)
	for i in f:
		var k := float(i) / f
		a[i] *= k
		a[a.size() - 1 - i] *= k
	return a
