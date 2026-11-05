extends SceneTree
## D-20 listening preview: renders the placeholder music layers and monster sounds to .wav files, mixed
## the same way Audio does (MusicLayerDef.volume_db + Audio.MUSIC_DB per stem, all stems in sync).
##
##   godot --headless --path . --script res://audio/_preview/render_listen.gd -- --out=C:/some/dir
##
## Writes music_base_growth.wav (population 0 -> 3 -> 6 -> 10, one loop each), music_festival.wav,
## music_field_chase.wav (field -> chase -> field), music_night.wav, music_raid.wav and
## monster_<family>.wav (suspicious, chase, attack, hurt, death with gaps).

const RAMP_SEC := 0.6
const GAP_SEC := 0.45

## The Audio autoload (not a compile-time identifier in a --script SceneTree).
var audio: Node
var _music_db := 0.0


func _initialize() -> void:
	await process_frame
	audio = root.get_node(^"Audio")
	_music_db = float(audio.get_script().get_script_constant_map()["MUSIC_DB"])
	var out := OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var t0 := Time.get_ticks_msec()
	for id in audio.layer_order:
		MusicSynth.make(audio.layers[id].synth)
	print("stems built in %d ms" % (Time.get_ticks_msec() - t0))
	_music(out.path_join("music_base_growth.wav"), [
		audio.layers_for(&"base", 0), audio.layers_for(&"base", 3),
		audio.layers_for(&"base", 6), audio.layers_for(&"base", 10)])
	var fest: Array = audio.layers_for(&"festival", 10)
	_music(out.path_join("music_festival.wav"), [fest, fest])
	_music(out.path_join("music_field_chase.wav"), [
		audio.layers_for(&"field", 0), audio.layers_for(&"chase", 0), audio.layers_for(&"chase", 0),
		audio.layers_for(&"field", 0)])
	_music(out.path_join("music_night.wav"), [audio.layers_for(&"night", 0), audio.layers_for(&"night", 0)])
	_music(out.path_join("music_raid.wav"), [audio.layers_for(&"raid", 0), audio.layers_for(&"raid", 0)])
	for fam in MonsterSynth.FAMILIES:
		var all := PackedFloat32Array()
		for act in MonsterSynth.ACTIONS:
			var ev: AudioEventDef = audio.get_event(StringName("monster_%s_%s" % [fam, act]))
			all.append_array(MonsterSynth.samples(ev.synth))
			var gap := PackedFloat32Array()
			gap.resize(int(GAP_SEC * Synth.RATE))
			all.append_array(gap)
		_save(out.path_join("monster_%s.wav" % fam), all)
	quit(0)


## One loop per segment; each segment lists the audible layer ids. Gains ramp at segment starts.
func _music(path: String, segments: Array) -> void:
	var n := MusicSynth.loop_samples()
	var mix := PackedFloat32Array()
	mix.resize(n * segments.size())
	var ramp := int(RAMP_SEC * Synth.RATE)
	for id: StringName in audio.layer_order:
		var l: MusicLayerDef = audio.layers[id]
		if not segments.any(func(seg: Array) -> bool: return id in seg):
			continue
		var stem := MusicSynth.samples(l.synth)
		var full := db_to_linear(l.volume_db + _music_db)
		var prev := 0.0
		for s in segments.size():
			var g := full if id in segments[s] else 0.0
			for i in n:
				var k := minf(1.0, float(i) / ramp)
				mix[s * n + i] += stem[i] * lerpf(prev, g, k)
			prev = g
	_save(path, mix)


func _save(path: String, a: PackedFloat32Array) -> void:
	var peak := 0.0
	for v in a:
		peak = maxf(peak, absf(v))
	if peak > 0.95:
		for i in a.size():
			a[i] *= 0.95 / peak
	var w := Synth._wav(a)
	w.save_to_wav(path)
	print("%s  %.1f s  peak %.2f" % [path.get_file(), a.size() / float(Synth.RATE), peak])
