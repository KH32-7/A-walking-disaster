class_name MusicSynth
## Placeholder music stems made in code (D-20). Owner: Lane D. Made here, so they may live in the public
## repo. Every stem has the same grid: BPM 96, 4/4, 4 bars (C - Am - F - G) = LOOP_SEC 10 s, so any set
## of stems plays together in sync and Audio only fades volumes. Notes ringing past the end wrap to the
## start, so each stem loops without a seam. Built once per recipe and cached.
## Recipes are the MusicLayerDef.synth values in data/ui/music_layers/.

const RATE := Synth.RATE
const BPM := 96.0
const BARS := 4
const BEAT := 60.0 / BPM
const BAR := BEAT * 4.0
const LOOP_SEC := BAR * BARS
## Every stem is normalised to this peak; MusicLayerDef.volume_db balances them.
const PEAK := 0.5
const TABLE := 2048

## Per bar (MIDI): C, Am, F, G.
const ROOTS := [36, 33, 29, 31]
const GUITAR := [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]]
const PIANO := [[60, 64, 67, 72], [60, 64, 69], [60, 65, 69], [59, 62, 67]]
const ARP := [0, 2, 1, 2, 3, 2, 1, 2]
## [start beat, midi, length in beats]
const MELODY := [
	[0.0, 76, 1.5], [1.5, 79, 0.5], [2.0, 81, 1.0], [3.0, 79, 1.0],
	[4.0, 76, 1.5], [5.5, 72, 0.5], [6.0, 74, 1.0], [7.0, 76, 1.0],
	[8.0, 77, 1.0], [9.0, 76, 0.5], [9.5, 74, 0.5], [10.0, 72, 2.0],
	[12.0, 74, 1.0], [13.0, 71, 1.0], [14.0, 74, 1.0], [15.0, 79, 1.0],
]

static var _cache: Dictionary = {}
static var _tables: Dictionary = {}
## Audio builds stems on a worker thread at start (Audio._prewarm_music); Godot's Mutex is recursive.
static var _lock := Mutex.new()


static func make(recipe: StringName) -> AudioStreamWAV:
	_lock.lock()
	if not _cache.has(recipe):
		_cache[recipe] = Synth._wav(samples(recipe), true)
	var w: AudioStreamWAV = _cache[recipe]
	_lock.unlock()
	return w


static func has_recipe(recipe: StringName) -> bool:
	return String(recipe).begins_with("mus_")


static func loop_samples() -> int:
	return int(round(LOOP_SEC * RATE))


## Raw mono samples of one stem (loop length, normalised). Unknown recipe -> silence.
static func samples(recipe: StringName) -> PackedFloat32Array:
	var out := _buf()
	match recipe:
		&"mus_base_guitar": _base_guitar(out)
		&"mus_base_piano": _base_piano(out)
		&"mus_base_bass": _base_bass(out)
		&"mus_base_flute": _base_flute(out)
		&"mus_festival_percussion": _festival_percussion(out)
		&"mus_festival_accordion": _festival_accordion(out)
		&"mus_field_ambient": _field_ambient(out)
		&"mus_chase_pulse": _chase_pulse(out)
		&"mus_chase_drums": _chase_drums(out)
		&"mus_night_strings": _night_strings(out)
		&"mus_raid_drums": _raid_drums(out)
		&"mus_raid_brass": _raid_brass(out)
		_: return out
	return _normalize(out)


# --- stems ---------------------------------------------------------------------------------------

## Warm acoustic guitar, 8th-note arpeggio (population 0).
static func _base_guitar(out: PackedFloat32Array) -> void:
	for c in BARS:
		for k in 8:
			var m: int = GUITAR[c][ARP[k]]
			_voice(out, c * BAR + k * BEAT * 0.5, _hz(m), 1.1, 0.2, _table(&"sine"), 0.003, 3.0, 0.05,
				0.0, _table(&"bright"), 7.0)


## Piano chords on 1 and the "and" of 2 (population 3).
static func _base_piano(out: PackedFloat32Array) -> void:
	for c in BARS:
		for hit in [[0.0, 1.0], [2.5, 0.7]]:
			for m: int in PIANO[c]:
				var at: float = c * BAR + float(hit[0]) * BEAT
				_voice(out, at, _hz(m), BEAT * 2.0, 0.13 * float(hit[1]), _table(&"piano"), 0.004, 1.6, 0.12,
					0.0, _table(&"bright"), 4.0)
				_voice(out, at, _hz(m) * 1.003, BEAT * 2.0, 0.05 * float(hit[1]), _table(&"piano"), 0.004, 1.8, 0.12)


## Upright bass: root, fifth, root (population 6).
static func _base_bass(out: PackedFloat32Array) -> void:
	for c in BARS:
		var r: int = ROOTS[c]
		for note in [[0.0, r, 1.5], [2.0, r + 7, 0.9], [3.0, r + 12, 0.9]]:
			_voice(out, c * BAR + float(note[0]) * BEAT, _hz(int(note[1])), float(note[2]) * BEAT, 0.45,
				_table(&"bass"), 0.008, 2.2, 0.06)


## Whistle / flute melody (population 10).
static func _base_flute(out: PackedFloat32Array) -> void:
	for note in MELODY:
		_voice(out, float(note[0]) * BEAT, _hz(int(note[1])), float(note[2]) * BEAT * 0.95, 0.22, _table(&"flute"),
			0.06, 0.15, 0.08, 5.0)
	_noise(out, 0.0, LOOP_SEC, 0.006, 2500.0, 6000.0, 7, 0.0, 0.0)


## Festival: kick, claps on 2 and 4, tambourine 8ths.
static func _festival_percussion(out: PackedFloat32Array) -> void:
	for b in BARS * 4:
		var at := b * BEAT
		if b % 2 == 0:
			_kick(out, at, 0.5)
		else:
			_clap(out, at, 0.45)
		for h in 2:
			_noise(out, at + h * BEAT * 0.5, 0.09, 0.22 if h == 1 else 0.12, 5000.0, 0.0, 30 + b * 2 + h, 0.01, 30.0)


## Festival: accordion off-beat chord stabs (oom-PAH) with a musette detune.
static func _festival_accordion(out: PackedFloat32Array) -> void:
	for c in BARS:
		for k in 4:
			var at: float = c * BAR + (k + 0.5) * BEAT
			for m: int in PIANO[c]:
				_voice(out, at, _hz(m), BEAT * 0.35, 0.1, _table(&"reed"), 0.015, 1.5, 0.05)
				_voice(out, at, _hz(m) * 1.005, BEAT * 0.35, 0.07, _table(&"reed"), 0.015, 1.5, 0.05)
		# a short bright run at the end of each bar
		_voice(out, c * BAR + 3.75 * BEAT, _hz(int(PIANO[c][0]) + 12), BEAT * 0.2, 0.12, _table(&"reed"), 0.01, 3.0, 0.04)


## Field: wind + a soft drone on each chord root + two distant bells.
static func _field_ambient(out: PackedFloat32Array) -> void:
	_noise(out, 0.0, LOOP_SEC, 0.22, 150.0, 700.0, 3, 0.0, 0.0, 2.0)
	for c in BARS:
		var r: int = ROOTS[c] + 12
		_voice(out, c * BAR, _hz(r), BAR, 0.11, _table(&"string"), 1.0, 0.0, 1.0, 3.0)
		_voice(out, c * BAR, _hz(r + 7), BAR, 0.07, _table(&"string"), 1.2, 0.0, 1.0, 3.5)
	for bell in [[0.5, 76], [8.5, 81]]:
		_voice(out, float(bell[0]) * BEAT, _hz(int(bell[1])), 2.0, 0.08, _table(&"sine"), 0.005, 1.2, 0.3)
		_voice(out, float(bell[0]) * BEAT, _hz(int(bell[1])) * 2.76, 1.0, 0.025, _table(&"sine"), 0.005, 3.0, 0.2)


## Chase: low 16th-note pulse on the root, accented on the beat.
static func _chase_pulse(out: PackedFloat32Array) -> void:
	for c in BARS:
		for k in 16:
			var accent := 1.4 if k % 4 == 0 else (1.0 if k % 2 == 0 else 0.75)
			_voice(out, c * BAR + k * BEAT * 0.25, _hz(int(ROOTS[c]) + 12), BEAT * 0.18, 0.22 * accent,
				_table(&"saw"), 0.003, 9.0, 0.02)
		# rising tension string at the end of each second bar
		if c % 2 == 1:
			_voice(out, c * BAR + 2.0 * BEAT, _hz(int(ROOTS[c]) + 30), BEAT * 2.0, 0.08, _table(&"string"), 0.8, 0.0, 0.05, 7.0)


## Chase: kick + toms, hats in 16ths.
static func _chase_drums(out: PackedFloat32Array) -> void:
	for c in BARS:
		var at := c * BAR
		for k in [0.0, 1.75, 2.0]:
			_kick(out, at + k * BEAT, 0.55)
		for k in [1.0, 3.0]:
			_tom(out, at + k * BEAT, 180.0, 0.35)
		for k in 16:
			_noise(out, at + k * BEAT * 0.25, 0.04, 0.12 if k % 2 == 1 else 0.07, 6000.0, 0.0, 50 + k, 0.0, 70.0)


## Night: low strings (cello section) following the chords, slow bows.
static func _night_strings(out: PackedFloat32Array) -> void:
	for c in BARS:
		var at := c * BAR
		_voice(out, at, _hz(int(ROOTS[c]) + 12), BAR, 0.16, _table(&"string"), 0.6, 0.0, 0.7, 4.5)
		_voice(out, at, _hz(int(GUITAR[c][1])), BAR, 0.1, _table(&"string"), 0.8, 0.0, 0.7, 4.0)
		_voice(out, at + BAR * 0.5, _hz(int(GUITAR[c][2])), BAR * 0.5, 0.08, _table(&"string"), 0.5, 0.0, 0.6, 5.0)


## Raid: war drums, kick + snare + hats, tom fill at the end.
static func _raid_drums(out: PackedFloat32Array) -> void:
	for c in BARS:
		var at := c * BAR
		for k in [0.0, 0.75, 2.0, 2.75]:
			_kick(out, at + k * BEAT, 0.7)
		for k in [1.0, 3.0]:
			_snare(out, at + k * BEAT, 0.5)
		for k in 8:
			_noise(out, at + k * BEAT * 0.5, 0.05, 0.1, 6000.0, 0.0, 80 + k, 0.0, 60.0)
		_tom(out, at, 70.0, 0.45)
	for k in 4:
		_tom(out, 15.0 * BEAT + k * BEAT * 0.25, 200.0 - k * 30.0, 0.4)


## Raid: low brass stabs (root + fifth).
static func _raid_brass(out: PackedFloat32Array) -> void:
	for c in BARS:
		var r: int = ROOTS[c] + 12
		for k in [0.0, 1.5, 3.0]:
			var at: float = c * BAR + k * BEAT
			_voice(out, at, _hz(r), BEAT * 0.45, 0.2, _table(&"saw"), 0.025, 2.5, 0.06)
			_voice(out, at, _hz(r + 7), BEAT * 0.45, 0.14, _table(&"saw"), 0.025, 2.5, 0.06)
			_voice(out, at, _hz(r - 12), BEAT * 0.45, 0.18, _table(&"bass"), 0.01, 2.5, 0.06)


# --- building blocks -----------------------------------------------------------------------------

static func _buf() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(loop_samples())
	return out


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## One note from a wavetable, added into `out` with wrap-around. `tbl2` (optional) is a brighter table
## crossfaded out with exp(-t * bright) (plucks and hammers start bright and mellow out).
static func _voice(out: PackedFloat32Array, at: float, f: float, dur: float, amp: float, tbl: PackedFloat32Array,
		attack: float, decay: float, release := 0.05, vib := 0.0, tbl2 := PackedFloat32Array(), bright := 0.0) -> void:
	var n := out.size()
	var s := int(at * RATE)
	var count := int((dur + release) * RATE)
	var ph := 0.0
	var inc := f / RATE
	var has2 := tbl2.size() == TABLE
	for i in count:
		var t := float(i) / RATE
		var e := minf(1.0, t / attack) if attack > 0.0 else 1.0
		if decay > 0.0:
			e *= exp(-t * decay)
		if t > dur:
			e *= maxf(0.0, 1.0 - (t - dur) / release)
		var k := int(ph * TABLE) & (TABLE - 1)
		var v := tbl[k]
		if has2:
			v = lerpf(v, tbl2[k], exp(-t * bright))
		out[(s + i) % n] += v * amp * e
		var fi := inc
		if vib > 0.0 and t > 0.15:
			fi *= 1.0 + sin(TAU * vib * t) * 0.006
		ph = fmod(ph + fi, 1.0)


## Band noise (lo..hi Hz; hi 0 = no low-pass) with attack / exp decay, added with wrap-around.
## `lfo` > 0: amplitude swells that many times per loop (wind).
static func _noise(out: PackedFloat32Array, at: float, dur: float, amp: float, lo: float, hi: float, seed: int,
		attack: float, decay: float, lfo := 0.0) -> void:
	var n := out.size()
	var s := int(at * RATE)
	var count := int(dur * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a_hi := clampf(TAU * hi / RATE, 0.0, 1.0) if hi > 0.0 else 1.0
	var a_lo := clampf(TAU * lo / RATE, 0.0, 1.0)
	var y_hi := 0.0
	var y_lo := 0.0
	# A full-length noise bed: its continuation is crossfaded into the start so the loop has no click.
	var fold := int(0.4 * RATE) if count >= n else 0
	var tmp := PackedFloat32Array()
	tmp.resize(count + fold)
	for i in count + fold:
		var t := float(i) / RATE
		y_hi += a_hi * (rng.randf_range(-1.0, 1.0) - y_hi)
		y_lo += a_lo * (y_hi - y_lo)
		var e := minf(1.0, t / attack) if attack > 0.0 else 1.0
		if decay > 0.0:
			e *= exp(-t * decay)
		if lfo > 0.0:
			e *= 0.55 + 0.45 * sin(TAU * lfo * t / LOOP_SEC)
		tmp[i] = (y_hi - y_lo) * 2.5 * amp * e
	for i in fold:
		var k := float(i) / fold
		tmp[i] = tmp[i] * k + tmp[count + i] * (1.0 - k)
	for i in count:
		out[(s + i) % n] += tmp[i]


static func _kick(out: PackedFloat32Array, at: float, amp: float) -> void:
	var n := out.size()
	var s := int(at * RATE)
	var ph := 0.0
	for i in int(0.35 * RATE):
		var t := float(i) / RATE
		ph += TAU * (48.0 + 90.0 * exp(-t * 35.0)) / RATE
		out[(s + i) % n] += sin(ph) * amp * exp(-t * 9.0)


static func _tom(out: PackedFloat32Array, at: float, f: float, amp: float) -> void:
	var n := out.size()
	var s := int(at * RATE)
	var ph := 0.0
	for i in int(0.4 * RATE):
		var t := float(i) / RATE
		ph += TAU * f * (1.0 + 0.5 * exp(-t * 20.0)) / RATE
		out[(s + i) % n] += sin(ph) * amp * exp(-t * 8.0)


static func _snare(out: PackedFloat32Array, at: float, amp: float) -> void:
	_noise(out, at, 0.22, amp, 1500.0, 0.0, int(at * 100.0), 0.0, 18.0)
	_voice(out, at, 190.0, 0.12, amp * 0.6, _table(&"sine"), 0.001, 25.0, 0.02)


static func _clap(out: PackedFloat32Array, at: float, amp: float) -> void:
	for k in 3:
		_noise(out, at + k * 0.011, 0.03, amp * 0.7, 900.0, 4500.0, int(at * 100.0) + k, 0.0, 90.0)
	_noise(out, at + 0.033, 0.18, amp, 900.0, 4500.0, int(at * 100.0) + 9, 0.0, 22.0)


static func _table(kind: StringName) -> PackedFloat32Array:
	_lock.lock()
	if not _tables.has(kind):
		_tables[kind] = _build_table(kind)
	var t: PackedFloat32Array = _tables[kind]
	_lock.unlock()
	return t


static func _build_table(kind: StringName) -> PackedFloat32Array:
	var harm: Array = [1.0]
	match kind:
		&"bright": harm = [1.0, 0.6, 0.45, 0.3, 0.2, 0.14, 0.1]
		&"piano": harm = [1.0, 0.45, 0.22, 0.12, 0.06]
		&"bass": harm = [1.0, 0.35, 0.1]
		&"flute": harm = [1.0, 0.08, 0.12]
		&"reed": harm = [1.0, 0.15, 0.55, 0.1, 0.35, 0.05, 0.2]
		&"saw": harm = [1.0, 0.5, 0.33, 0.25, 0.2, 0.16, 0.14, 0.12]
		&"string": harm = [1.0, 0.4, 0.24, 0.16, 0.11, 0.08]
	var t := PackedFloat32Array()
	t.resize(TABLE)
	var peak := 0.0
	for i in TABLE:
		var v := 0.0
		for h in harm.size():
			v += sin(TAU * (h + 1) * i / TABLE) * float(harm[h])
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in TABLE:
		t[i] /= peak
	return t


static func _normalize(a: PackedFloat32Array) -> PackedFloat32Array:
	var peak := 0.0
	for v in a:
		peak = maxf(peak, absf(v))
	if peak > 0.0:
		var g := PEAK / peak
		for i in a.size():
			a[i] *= g
	return a
