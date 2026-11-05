extends Node
## Autoload `Settings`. Owner: Lane A (task A-12). Lane D builds the settings UI on top of it.
## Accessibility + difficulty values every lane reads. Never read these from a UI node.
## Design reference: docs/design/14-ui-controls-accessibility.md, 12-progression-balance.md

const PATH := "user://settings.cfg"

var values: Dictionary = {
	# accessibility
	&"subtitles": true,
	&"subtitle_size": 1,
	&"noise_rings": true,
	&"sound_arrows": true,
	&"color_filter": 0,
	&"reduce_flash": false,
	&"reduce_shake": false,
	&"aim_assist": 1,
	&"toggle_aim": false,
	&"toggle_sprint": false,
	&"game_speed": 1.0,
	&"tts_menu": false,
	&"ai_radio_frequency": 1,
	# difficulty / protect mode (each item can be toggled on its own)
	&"difficulty": &"normal",
	&"permadeath": true,
	&"keep_bag_on_down": false,
	&"instant_loot": false,
	&"strand_days": 5,
	&"monster_mult": 1.0,
	&"raid_mult": 1.0,
}


func get_value(key: StringName) -> Variant:
	return values.get(key)


func set_value(key: StringName, value: Variant) -> void:
	values[key] = value
	EventBus.settings_changed.emit(key)
	# TODO(A-12): persist to PATH with ConfigFile.
