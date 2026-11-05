extends Node
## B-21: the sortie clock in FieldState (dusk at 12 min, night from 15 min), the Radio dusk
## line, the HUD dusk_left_sec, night spawn rate in MonsterSpawner, and the demo switch.
## The clock is moved by hand with FieldState.advance_sortie_time(); FieldState._process is
## paused so frame time does not leak in.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const VINE := preload("res://data/monsters/vine_tendril.tres")
const DUSK := GameState.SORTIE_DUSK_SEC
const NIGHT := GameState.SORTIE_NIGHT_SEC

var _ok := true
var _dusk_count := 0
var _night_count := 0
var _radio: Array[String] = []
var _autosave_before := true
var _night_before: NightTuning


func run() -> bool:
	_ok = true
	_autosave_before = SaveSystem.autosave_enabled
	SaveSystem.autosave_enabled = false
	_night_before = FieldState.night
	FieldState.set_process(false)
	Radio.set_combat(false)
	FieldState.dusk_started.connect(_on_dusk)
	FieldState.night_started.connect(_on_night)
	EventBus.radio_message.connect(_on_radio)

	_test_clock_and_signals()
	_test_jump_sends_both()
	_test_clock_stops_and_resets()
	_test_save_round_trip()
	_test_demo_switch()
	_test_hud_dusk_left()
	_test_night_spawn_rate()
	_test_night_monster_rules_guarded()

	EventBus.sortie_ended.emit({})
	FieldState.dusk_started.disconnect(_on_dusk)
	FieldState.night_started.disconnect(_on_night)
	EventBus.radio_message.disconnect(_on_radio)
	FieldState.night = _night_before
	FieldState.set_process(true)
	SaveSystem.autosave_enabled = _autosave_before
	return _ok


# --- Tests ----------------------------------------------------------------

func _test_clock_and_signals() -> void:
	_start()
	_expect(FieldState.sortie_time() == 0.0, "clock starts at 0 on sortie_started")
	_expect(is_equal_approx(FieldState.dusk_left_sec(), DUSK), "12 min to dusk at the start")
	FieldState.advance_sortie_time(DUSK - 1.0)
	_expect(_dusk_count == 0 and not FieldState.is_dusk(), "no dusk at 11:59")
	_expect(is_equal_approx(FieldState.dusk_left_sec(), 1.0), "1 s left at 11:59")
	FieldState.advance_sortie_time(1.0)
	_expect(_dusk_count == 1 and FieldState.is_dusk(), "dusk_started at 12:00")
	_expect(FieldState.dusk_left_sec() == 0.0, "0 s left after dusk")
	_expect(_radio.size() == 1 and _radio[0].contains("3분"), "Radio dusk line says 3 minutes")
	_expect(not FieldState.is_night(), "not night yet at dusk")
	FieldState.advance_sortie_time(NIGHT - DUSK - 1.0)
	_expect(_night_count == 0, "no night at 14:59")
	FieldState.advance_sortie_time(1.0)
	_expect(_night_count == 1 and FieldState.is_night() and not FieldState.is_dusk(), "night_started at 15:00")
	FieldState.advance_sortie_time(600.0)
	_expect(_dusk_count == 1 and _night_count == 1 and _radio.size() == 1, "each signal once per sortie")


func _test_jump_sends_both() -> void:
	_start()
	var order := []
	var on_dusk := func() -> void: order.append(&"dusk")
	var on_night := func() -> void: order.append(&"night")
	FieldState.dusk_started.connect(on_dusk)
	FieldState.night_started.connect(on_night)
	FieldState.advance_sortie_time(NIGHT + 10.0)
	_expect(order == [&"dusk", &"night"], "one big step sends dusk, then night")
	FieldState.dusk_started.disconnect(on_dusk)
	FieldState.night_started.disconnect(on_night)


func _test_clock_stops_and_resets() -> void:
	_start()
	FieldState.advance_sortie_time(NIGHT)
	EventBus.sortie_ended.emit({})
	_expect(not FieldState.is_night() and FieldState.sortie_time() == 0.0, "sortie_ended clears the night")
	_start()
	_expect(not FieldState.is_dusk() and not FieldState.is_night(), "next sortie starts in daylight")


func _test_save_round_trip() -> void:
	_start()
	FieldState.advance_sortie_time(DUSK + 30.0)
	var data := FieldState.save_data()
	_start()
	FieldState.load_data(data)
	_expect(is_equal_approx(FieldState.sortie_time(), DUSK + 30.0), "suspend keeps the sortie clock")
	_expect(FieldState.is_dusk() and not FieldState.is_night(), "loaded at 12:30 is dusk")
	_expect(_dusk_count == 0, "loading does not resend dusk_started")
	FieldState.advance_sortie_time(NIGHT)
	_expect(_dusk_count == 0 and _night_count == 1, "night still comes after loading")


func _test_demo_switch() -> void:
	var off := NightTuning.new()
	off.enabled = false
	FieldState.night = off
	_start()
	FieldState.advance_sortie_time(NIGHT * 2.0)
	_expect(_dusk_count == 0 and _night_count == 0 and _radio.is_empty(), "night off: no dusk, no night, no radio")
	_expect(not FieldState.is_night() and FieldState.dusk_left_sec() < 0.0, "night off: never night, no timer")
	FieldState.night = _night_before


func _test_hud_dusk_left() -> void:
	var p: Player = PLAYER_SCENE.instantiate()
	add_child(p)
	_start()
	FieldState.advance_sortie_time(100.0)
	_expect(is_equal_approx(float(p.hud_state().get("dusk_left_sec", -1.0)), DUSK - 100.0), "hud_state dusk_left_sec")
	var off := NightTuning.new()
	off.enabled = false
	FieldState.night = off
	_expect(not p.hud_state().has("dusk_left_sec"), "night off: hud_state has no dusk_left_sec")
	FieldState.night = _night_before
	p.free()


func _test_night_spawn_rate() -> void:
	var nest := _nest()
	var spawner := _spawner()
	_start()
	spawner.tick(0.0)
	spawner.tick(nest.spawn_interval_sec / 1.5)
	_expect(spawner.alive_count(nest) == 0, "day: nothing after interval / 1.5")
	spawner.free()
	nest.free()

	nest = _nest()
	spawner = _spawner()
	FieldState.advance_sortie_time(NIGHT)
	spawner.tick(0.0)
	spawner.tick(nest.spawn_interval_sec / 1.5 - 1.0)
	_expect(spawner.alive_count(nest) == 0, "night: nothing just before interval / 1.5")
	spawner.tick(1.0)
	_expect(spawner.alive_count(nest) >= 1, "night: nest spawns 1.5x as often")
	spawner.free()
	nest.free()


## B-18 adds Monster.drop_mult, sight_mult and make_elite(). Until then this only checks the
## spawner's guards: night spawns with elite_chance 1 must not break on today's Monster.
## TODO(B-18 merged): expect drop_mult 1.3, sight_mult 0.7, and an elite at elite_chance 1.
func _test_night_monster_rules_guarded() -> void:
	var always := NightTuning.new()
	always.elite_chance = 1.0
	FieldState.night = always
	var nest := _nest()
	var spawner := _spawner()
	_start()
	spawner.tick(0.0)
	spawner.tick(nest.spawn_interval_sec)
	var day_count := spawner.alive_count(nest)
	var day_monster := spawner.get_child(0) as Monster
	FieldState.advance_sortie_time(NIGHT)
	spawner.tick(nest.spawn_interval_sec)
	_expect(spawner.alive_count(nest) > day_count, "night spawn works with the guards")
	for child in spawner.get_children():
		var m := child as Monster
		if "drop_mult" in m:
			_expect(is_equal_approx(m.get(&"drop_mult"), always.drop_mult), "night drop_mult on %s" % m.name)
		if "sight_mult" in m:
			_expect(is_equal_approx(m.get(&"sight_mult"), always.sight_mult), "night sight_mult on %s" % m.name)
	_expect(is_instance_valid(day_monster), "monsters already out survive night_started")
	FieldState.night = _night_before
	spawner.free()
	nest.free()


# --- Helpers --------------------------------------------------------------

func _start() -> void:
	EventBus.sortie_started.emit({"region_id": &"flooded_mall", "companions": []})
	_dusk_count = 0
	_night_count = 0
	_radio.clear()


func _nest() -> MonsterNest:
	var nest := MonsterNest.new()
	nest.family = VINE.family
	nest.spawn_interval_sec = 180.0
	nest.max_alive = 10
	add_child(nest)
	return nest


func _spawner() -> MonsterSpawner:
	var spawner := MonsterSpawner.new()
	spawner.monster_defs = [VINE]
	spawner.spawn_initial_pack = false
	add_child(spawner)
	return spawner


func _on_dusk() -> void:
	_dusk_count += 1


func _on_night() -> void:
	_night_count += 1


func _on_radio(_speaker: StringName, text: String, _priority: int) -> void:
	_radio.append(text)


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_night: " + label)
