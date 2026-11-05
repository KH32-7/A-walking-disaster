class_name MonsterSynth
## Placeholder monster family sounds made in code (D-20). Owner: Lane D. Recipes `mon_<family>_<action>`:
## family green (수풀) / stone (잔해) / water (물) / light (네온), action suspicious / chase / attack / hurt /
## death. Design 16 "마물 시그니처": 수풀 = 잎 스침·꽃망울 터짐, 잔해 = 돌 긁힘, 물 = 물방울·거품,
## 네온 = 전기 웅웅거림. Every family's suspicious ends with the same short rising tone and chase with
## the same two-tone warning, so the state is learnt once and the family is told by its timbre.
## Called through Synth.make (AudioEventDef.synth); results are cached there.

const RATE := Synth.RATE
const FAMILIES := [&"green", &"stone", &"water", &"light"]
const ACTIONS := [&"suspicious", &"chase", &"attack", &"hurt", &"death"]
const PEAK := 0.8


static func has_recipe(recipe: StringName) -> bool:
	return String(recipe).begins_with("mon_")


static func make(recipe: StringName) -> AudioStreamWAV:
	return Synth._wav(samples(recipe))


static func samples(recipe: StringName) -> PackedFloat32Array:
	var parts := String(recipe).split("_")
	if parts.size() != 3:
		return _buf(0.1)
	var fam := StringName(parts[1])
	var act := StringName(parts[2])
	var b: PackedFloat32Array
	match fam:
		&"green": b = _green(act)
		&"stone": b = _stone(act)
		&"water": b = _water(act)
		&"light": b = _light(act)
		_: b = _buf(0.1)
	return _normalize(b)


# --- families ------------------------------------------------------------------------------------

## 수풀: leaf rustle + flower-bud pops; whip-like lash.
static func _green(act: StringName) -> PackedFloat32Array:
	match act:
		&"suspicious":
			var b := _buf(0.55)
			_rustle(b, 0.0, 0.35, 0.5, 1)
			_rise(b, 0.3)
			return b
		&"chase":
			var b := _buf(0.7)
			_rustle(b, 0.0, 0.3, 0.8, 2)
			_pop(b, 0.05, 900.0, 0.6)
			_pop(b, 0.14, 1100.0, 0.5)
			_warn(b, 0.32)
			return b
		&"attack":
			var b := _buf(0.35)
			_band(b, 0.0, 0.16, 0.6, 600.0, 5000.0, 3, 0.02, 0.0, 1.5)
			_band(b, 0.15, 0.04, 0.9, 3000.0, 0.0, 4, 0.0, 80.0)
			_pop(b, 0.17, 700.0, 0.5)
			return b
		&"hurt":
			var b := _buf(0.3)
			_rustle(b, 0.0, 0.14, 0.8, 5)
			_tone(b, 0.02, 0.12, 760.0, 480.0, 0.35, 0)
			return b
		_:
			var b := _buf(1.1)
			_rustle(b, 0.0, 0.9, 0.6, 6, 3.0)
			for k in 3:
				_pop(b, 0.1 + k * 0.13, 700.0 - k * 150.0, 0.55 - k * 0.1)
			_tone(b, 0.25, 0.6, 320.0, 150.0, 0.3, 0)
			return b


## 잔해: stone scrape / grind, heavy thud, chips, crumble.
static func _stone(act: StringName) -> PackedFloat32Array:
	match act:
		&"suspicious":
			var b := _buf(0.6)
			_scrape(b, 0.0, 0.4, 0.6, 1)
			_rise(b, 0.35)
			return b
		&"chase":
			var b := _buf(0.75)
			_scrape(b, 0.0, 0.4, 0.9, 2)
			_tone(b, 0.0, 0.4, 60.0, 50.0, 0.5, 0)
			_warn(b, 0.36)
			return b
		&"attack":
			var b := _buf(0.45)
			_tone(b, 0.0, 0.3, 95.0, 38.0, 1.0, 0)
			_band(b, 0.0, 0.18, 0.6, 300.0, 2500.0, 3, 0.0, 14.0)
			_clack(b, 0.02, 1400.0, 0.4)
			return b
		&"hurt":
			var b := _buf(0.25)
			_clack(b, 0.0, 2200.0, 0.7)
			_clack(b, 0.05, 1600.0, 0.5)
			_band(b, 0.0, 0.1, 0.3, 800.0, 4000.0, 5, 0.0, 30.0)
			return b
		_:
			var b := _buf(1.2)
			var rng := RandomNumberGenerator.new()
			rng.seed = 41
			for k in 12:
				_clack(b, 0.05 + k * 0.07 + rng.randf() * 0.03, rng.randf_range(900.0, 2400.0), 0.6 - k * 0.04)
			_band(b, 0.0, 1.0, 0.5, 40.0, 400.0, 6, 0.02, 2.5)
			_tone(b, 0.0, 0.35, 80.0, 35.0, 0.8, 0)
			return b


## 물: droplets, bubbles, splash, gurgle.
static func _water(act: StringName) -> PackedFloat32Array:
	match act:
		&"suspicious":
			var b := _buf(0.5)
			_drip(b, 0.0, 700.0, 0.5)
			_drip(b, 0.12, 900.0, 0.4)
			_rise(b, 0.25)
			return b
		&"chase":
			var b := _buf(0.75)
			_bubbles(b, 0.0, 0.35, 9, 500.0, 1300.0, 0.5, 2)
			_warn(b, 0.36)
			return b
		&"attack":
			var b := _buf(0.5)
			_band(b, 0.0, 0.4, 0.7, 400.0, 3500.0, 3, 0.01, 6.0)
			_drip(b, 0.05, 300.0, 0.7, 0.09)
			return b
		&"hurt":
			var b := _buf(0.3)
			_drip(b, 0.0, 220.0, 0.8, 0.1)
			_bubbles(b, 0.05, 0.2, 3, 600.0, 1000.0, 0.35, 5)
			return b
		_:
			var b := _buf(1.2)
			_band(b, 0.0, 1.1, 0.25, 100.0, 900.0, 6, 0.05, 2.0)
			var rng := RandomNumberGenerator.new()
			rng.seed = 23
			for k in 14:
				var t := k * 0.07
				_drip(b, t, lerpf(1100.0, 250.0, t / 1.0) * rng.randf_range(0.85, 1.15), 0.45)
			return b


## 네온: electric hum with flicker, zaps, crackle, power-down.
static func _light(act: StringName) -> PackedFloat32Array:
	match act:
		&"suspicious":
			var b := _buf(0.6)
			_hum(b, 0.0, 0.4, 120.0, 120.0, 0.45, 1)
			_rise(b, 0.35)
			return b
		&"chase":
			var b := _buf(0.75)
			_hum(b, 0.0, 0.4, 110.0, 180.0, 0.6, 2)
			_crackle(b, 0.0, 0.35, 0.5, 90.0, 3)
			_warn(b, 0.36)
			return b
		&"attack":
			var b := _buf(0.35)
			_crackle(b, 0.0, 0.25, 0.8, 200.0, 4)
			_tone(b, 0.0, 0.18, 1600.0, 300.0, 0.35, 1)
			return b
		&"hurt":
			var b := _buf(0.25)
			_crackle(b, 0.0, 0.12, 0.8, 160.0, 5)
			_tone(b, 0.0, 0.08, 1200.0, 900.0, 0.25, 1)
			return b
		_:
			var b := _buf(1.2)
			_hum(b, 0.0, 0.95, 120.0, 20.0, 0.7, 6)
			_crackle(b, 0.0, 0.3, 0.4, 120.0, 7)
			_band(b, 0.95, 0.08, 0.8, 200.0, 3000.0, 8, 0.0, 40.0)
			return b


# --- shared state cues ---------------------------------------------------------------------------

## "?" cue: short rising tone (same for every family).
static func _rise(b: PackedFloat32Array, at: float) -> void:
	_tone(b, at, 0.18, 380.0, 620.0, 0.35, 0)


## "!" cue: two-tone warning (same for every family).
static func _warn(b: PackedFloat32Array, at: float) -> void:
	_tone(b, at, 0.12, 880.0, 880.0, 0.4, 0)
	_tone(b, at + 0.14, 0.2, 660.0, 660.0, 0.4, 0)


# --- building blocks -----------------------------------------------------------------------------

static func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	return b


## Tone with exponential pitch glide. shape 0 sine, 1 square-ish.
static func _tone(b: PackedFloat32Array, at: float, dur: float, f0: float, f1: float, amp: float, shape: int) -> void:
	var s := int(at * RATE)
	var n := mini(int(dur * RATE), b.size() - s)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * f0 * pow(f1 / f0, t / dur) / RATE
		var v := sin(ph)
		if shape == 1:
			v = clampf(v * 3.0, -1.0, 1.0)
		b[s + i] += v * amp * _env(t, dur, 0.004)


## Band noise lo..hi (hi 0 = no low-pass). decay > 0: exp decay, else the soft _env shape.
## flutter > 0: random amplitude grains (leaves, scraping).
static func _band(b: PackedFloat32Array, at: float, dur: float, amp: float, lo: float, hi: float, seed: int,
		attack: float, decay: float, flutter := 0.0) -> void:
	var s := int(at * RATE)
	var n := mini(int(dur * RATE), b.size() - s)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a_hi := clampf(TAU * hi / RATE, 0.0, 1.0) if hi > 0.0 else 1.0
	var a_lo := clampf(TAU * lo / RATE, 0.0, 1.0)
	var y_hi := 0.0
	var y_lo := 0.0
	var grain := 1.0
	var grain_left := 0
	for i in n:
		var t := float(i) / RATE
		y_hi += a_hi * (rng.randf_range(-1.0, 1.0) - y_hi)
		y_lo += a_lo * (y_hi - y_lo)
		if flutter > 0.0:
			grain_left -= 1
			if grain_left <= 0:
				grain_left = rng.randi_range(80, 400)
				grain = lerpf(1.0, rng.randf(), minf(1.0, flutter * 0.5))
		var e := (minf(1.0, t / attack) if attack > 0.0 else 1.0) * (exp(-t * decay) if decay > 0.0 else _env(t, dur, 0.0))
		b[s + i] += (y_hi - y_lo) * 2.5 * amp * e * grain


static func _rustle(b: PackedFloat32Array, at: float, dur: float, amp: float, seed: int, flutter := 2.0) -> void:
	_band(b, at, dur, amp, 2500.0, 7000.0, seed, 0.03, 0.0, flutter)


static func _scrape(b: PackedFloat32Array, at: float, dur: float, amp: float, seed: int) -> void:
	_band(b, at, dur, amp, 400.0, 1600.0, seed, 0.04, 0.0, 2.0)
	_tone(b, at, dur, 55.0, 48.0, amp * 0.3, 1)


## Flower-bud pop: very short downward blip.
static func _pop(b: PackedFloat32Array, at: float, f: float, amp: float) -> void:
	_tone(b, at, 0.035, f, f * 0.35, amp, 0)
	_band(b, at, 0.008, amp * 0.6, 2000.0, 0.0, int(f), 0.0, 400.0)


## Stone chip: short resonant click.
static func _clack(b: PackedFloat32Array, at: float, f: float, amp: float) -> void:
	var s := int(at * RATE)
	var n := mini(int(0.04 * RATE), b.size() - s)
	for i in n:
		var t := float(i) / RATE
		b[s + i] += (sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.47 * t)) * amp * exp(-t * 110.0)


## Water drop: sine with a fast upward glide.
static func _drip(b: PackedFloat32Array, at: float, f: float, amp: float, dur := 0.05) -> void:
	_tone(b, at, dur, f, f * 2.4, amp, 0)


static func _bubbles(b: PackedFloat32Array, at: float, dur: float, count: int, f_lo: float, f_hi: float, amp: float,
		seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for k in count:
		_drip(b, at + rng.randf() * dur, rng.randf_range(f_lo, f_hi), amp * rng.randf_range(0.6, 1.0), 0.035)


## Neon hum: buzzy harmonics with pitch glide and random flicker drop-outs.
static func _hum(b: PackedFloat32Array, at: float, dur: float, f0: float, f1: float, amp: float, seed: int) -> void:
	var s := int(at * RATE)
	var n := mini(int(dur * RATE), b.size() - s)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ph := 0.0
	var gate := 1.0
	var gate_left := 0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(f0, f1, t / dur) / RATE
		gate_left -= 1
		if gate_left <= 0:
			gate_left = rng.randi_range(300, 1500)
			gate = 0.25 if rng.randf() < 0.3 else 1.0
		var v := sin(ph) + 0.6 * sin(ph * 2.0) + 0.45 * sin(ph * 3.0) + 0.3 * sin(ph * 5.0)
		b[s + i] += clampf(v * 0.8, -1.0, 1.0) * amp * gate * _env(t, dur, 0.02)


## Electric crackle: random sharp spikes, `density` per second.
static func _crackle(b: PackedFloat32Array, at: float, dur: float, amp: float, density: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for k in int(dur * density):
		var s := int((at + rng.randf() * dur) * RATE)
		var ln := rng.randi_range(20, 90)
		var sgn := 1.0 if rng.randf() < 0.5 else -1.0
		for i in mini(ln, b.size() - s):
			b[s + i] += sgn * rng.randf_range(0.3, 1.0) * amp * (1.0 - float(i) / ln)


static func _env(t: float, dur: float, attack: float) -> float:
	if attack > 0.0 and t < attack:
		return t / attack
	return pow(maxf(0.0, 1.0 - (t - attack) / maxf(0.001, dur - attack)), 2.0)


static func _normalize(a: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in a:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		var g := PEAK / peak
		for i in a.size():
			a[i] = clampf(a[i] * g, -1.0, 1.0)
	return a
