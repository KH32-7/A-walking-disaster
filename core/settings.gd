extends Node
## Autoload `Settings`. Owner: Lane A (task A-12). Lane D builds the settings UI on top of it.
## Accessibility + difficulty values every lane reads. Never read these from a UI node.
## Design reference: docs/design/14-ui-controls-accessibility.md, 12-progression-balance.md "난이도"
##
## Two kinds of values:
## - Preferences (accessibility, audio, controls): saved to `path` (ConfigFile) on every change,
##   shared by all save slots.
## - Difficulty (DIFFICULTY_KEYS): belong to the playthrough. They are also kept in the ConfigFile as
##   the default for the next new game, and saved with each game through the "difficulty" save
##   provider, so loading a slot restores that run's difficulty.

const DEFAULTS := {
	# accessibility: subtitles
	&"subtitles": true,
	&"subtitle_size": 1,  # 0 small, 1 medium, 2 large
	&"subtitle_bg_alpha": 0.6,
	&"subtitle_speaker": true,
	# accessibility: sound visualisation
	&"sound_arrows": true,
	&"sound_icons": true,
	# accessibility: colour / screen
	&"color_filter": 0,  # 0 off, 1 protanopia, 2 deuteranopia, 3 tritanopia
	&"high_contrast": false,
	&"reduce_flash": false,
	&"reduce_shake": false,
	&"camera_zoom": 1.0,
	# accessibility: input
	&"aim_assist": 1,  # 0 off, 1 weak, 2 medium, 3 strong
	&"toggle_aim": false,
	&"toggle_sprint": false,
	&"toggle_block": false,
	&"one_hand": false,
	&"hold_instead_mash": false,
	# accessibility: speed / text / speech
	&"game_speed": 1.0,  # field only, 0.5 .. 1.0
	&"text_size": 1,
	&"dyslexic_font": false,
	&"tts_menu": false,
	&"ai_radio_frequency": 1,  # 0 off, 1 when needed, 2 often (template radio, no LLM)
	&"radio_voice": true,
	# audio (linear 0..1)
	&"volume_master": 1.0,
	&"volume_music": 0.8,
	&"volume_sfx": 1.0,
	&"volume_voice": 1.0,
	# difficulty (see PRESETS)
	&"difficulty": &"normal",
	&"monster_mult": 1.0,
	&"raid_mult": 1.0,
	&"permadeath": true,  # false: residents get 7 days of severe injury instead of dying
	&"strand_days": 5,  # 0: stranded companions never get lost
	&"keep_bag_on_down": false,
	&"instant_loot": false,
	&"hardcore": false,  # player death deletes the save. Chosen at new game only.
}

## Design 12 "난이도". Story = protect mode: each item can still be toggled on its own afterwards.
const PRESETS := {
	&"story": {&"monster_mult": 0.7, &"raid_mult": 0.6, &"permadeath": false, &"strand_days": 0,
		&"keep_bag_on_down": true, &"instant_loot": true, &"hardcore": false},
	&"normal": {&"monster_mult": 1.0, &"raid_mult": 1.0, &"permadeath": true, &"strand_days": 5,
		&"keep_bag_on_down": false, &"instant_loot": false, &"hardcore": false},
	&"hard": {&"monster_mult": 1.3, &"raid_mult": 1.3, &"permadeath": true, &"strand_days": 3,
		&"keep_bag_on_down": false, &"instant_loot": false, &"hardcore": false},
	&"hardcore": {&"monster_mult": 1.3, &"raid_mult": 1.5, &"permadeath": true, &"strand_days": 3,
		&"keep_bag_on_down": false, &"instant_loot": false, &"hardcore": true},
}
## Shown as the difficulty once individual items no longer match a preset.
const CUSTOM := &"custom"
const DIFFICULTY_KEYS := [&"difficulty", &"monster_mult", &"raid_mult", &"permadeath",
	&"strand_days", &"keep_bag_on_down", &"instant_loot", &"hardcore"]
const SECTION := "settings"

## Tests point this elsewhere.
var path := "user://settings.cfg"
var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	# SaveSystem loads after Settings, so it registers the "difficulty" provider itself.
	load_from_disk()


func get_value(key: StringName) -> Variant:
	if not values.has(key):
		push_error("Settings: unknown key '%s'" % key)
		return null
	return values[key]


## Sets one value, saves the file and emits settings_changed. Unknown keys and wrong types are
## refused (returns false). Changing a difficulty item turns the difficulty into "custom" unless the
## result still matches a preset. `hardcore` cannot be changed here (use apply_preset at new game).
func set_value(key: StringName, value: Variant) -> bool:
	if not DEFAULTS.has(key):
		push_error("Settings: unknown key '%s'" % key)
		return false
	if key == &"hardcore" or key == &"difficulty":
		push_error("Settings: use apply_preset() to change '%s'" % key)
		return false
	var converted: Variant = _convert(key, value)
	if converted == null:
		push_error("Settings: '%s' expects %s, got %s" % [key, type_string(typeof(DEFAULTS[key])), value])
		return false
	if values[key] == converted:
		return true
	values[key] = converted
	EventBus.settings_changed.emit(key)
	if key in DIFFICULTY_KEYS:
		_refresh_difficulty_name()
	save_to_disk()
	return true


## Sets every difficulty item from a preset (&"story", &"normal", &"hard", &"hardcore").
## Hardcore can only be entered or left when `new_game` is true (title screen).
func apply_preset(preset_id: StringName, new_game := false) -> bool:
	if not PRESETS.has(preset_id):
		push_error("Settings: unknown difficulty preset '%s'" % preset_id)
		return false
	var preset: Dictionary = PRESETS[preset_id]
	if not new_game and preset[&"hardcore"] != values[&"hardcore"]:
		return false
	for key: StringName in preset:
		_set_silent(key, preset[key])
	_set_silent(&"difficulty", preset_id)
	save_to_disk()
	return true


## Preset whose values match the current difficulty items, or CUSTOM.
func matching_preset() -> StringName:
	for id: StringName in PRESETS:
		var preset: Dictionary = PRESETS[id]
		var same := true
		for key: StringName in preset:
			if values[key] != preset[key]:
				same = false
				break
		if same:
			return id
	return CUSTOM


func reset_to_defaults(include_difficulty := false) -> void:
	for key: StringName in DEFAULTS:
		if include_difficulty or not key in DIFFICULTY_KEYS:
			_set_silent(key, DEFAULTS[key])
	save_to_disk()


# --- ConfigFile ---

func save_to_disk() -> bool:
	var cfg := ConfigFile.new()
	for key: StringName in values:
		cfg.set_value(SECTION, String(key), values[key])
	var err := cfg.save(path)
	if err != OK:
		push_error("Settings: cannot save %s (%s)" % [path, error_string(err)])
	return err == OK


## Missing file: keep defaults. Unknown keys and values of the wrong type are ignored.
func load_from_disk() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for name in cfg.get_section_keys(SECTION) if cfg.has_section(SECTION) else PackedStringArray():
		var key := StringName(name)
		if not DEFAULTS.has(key):
			continue
		var converted: Variant = _convert(key, cfg.get_value(SECTION, name))
		if converted != null:
			values[key] = converted


# --- Save provider "difficulty" (per playthrough) ---

func save_data() -> Dictionary:
	var out := {}
	for key: StringName in DIFFICULTY_KEYS:
		out[key] = values[key]
	return out


func load_data(data: Dictionary) -> void:
	for key: StringName in DIFFICULTY_KEYS:
		var value: Variant = data.get(key, data.get(String(key), DEFAULTS[key]))
		var converted: Variant = _convert(key, value)
		_set_silent(key, converted if converted != null else DEFAULTS[key])


# --- Internals ---

func _set_silent(key: StringName, value: Variant) -> void:
	if values.get(key) == value and typeof(values.get(key)) == typeof(value):
		return
	values[key] = value
	EventBus.settings_changed.emit(key)


func _refresh_difficulty_name() -> void:
	_set_silent(&"difficulty", matching_preset())


## Returns `value` as the type of the key's default, or null if it cannot be.
func _convert(key: StringName, value: Variant) -> Variant:
	var want := typeof(DEFAULTS[key])
	var have := typeof(value)
	if have == want:
		return value
	match want:
		TYPE_FLOAT:
			return float(value) if have == TYPE_INT else null
		TYPE_INT:
			return int(value) if have == TYPE_FLOAT and is_equal_approx(value, roundf(value)) else null
		TYPE_STRING_NAME:
			return StringName(value) if have == TYPE_STRING else null
	return null
