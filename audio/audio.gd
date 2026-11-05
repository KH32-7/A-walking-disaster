extends Node
## Autoload `Audio`. Owner: Lane D.
## Gameplay code calls `Audio.play(&"gunshot_pistol", global_position)` and never loads
## streams itself. Noise radius is NOT decided here - Lane B emits EventBus.noise_emitted;
## this only plays the sound (and the matching visual cue for accessibility).
## Design reference: docs/design/16-art-sound.md


func play(event_id: StringName, position: Vector3 = Vector3.INF) -> void:
	# TODO(D-xx): look up data/ui/audio_events, play 2D or 3D, apply bus + priority.
	pass


func set_music_state(state: StringName) -> void:
	# TODO(D-xx): BASE, FIELD, CHASE, NIGHT, RAID, FESTIVAL layers.
	pass
