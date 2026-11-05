class_name PlayerAnimTuning
extends Resource
## Player animation playback numbers. Values live in data/classes/player_anim_tuning.tres (tuned by
## the user in game, 2026-11-06; the live tuning panel has been removed).
##
## Walk clips play at (ground speed / the bare-hand walk's own speed 1.3 m/s), clamped to
## min..max_playback, then multiplied by the multiplier for the current move. Gun walks use the same
## number, adjusted only so their steps come at the same rate as the bare-hand walk.
## Example: walk 4.5 m/s / 1.3 = 3.46, clamped to 2.4, x walk_mult 0.6 = 1.44.

@export_group("Multipliers")
## Walk, bare hands and gun alike (crouched walk / 4-way rifle walks).
@export_range(0.1, 4.0, 0.05) var walk_mult: float = 1.0
## Sprint (the same walks played faster), bare hands and gun alike.
@export_range(0.1, 4.0, 0.05) var sprint_mult: float = 1.0
## Extra multiplier for the backward part of a gun walk (walking away from the cursor).
@export_range(0.1, 4.0, 0.05) var back_walk_mult: float = 1.3
## Roll. 1.0 = the roll clip fits the dodge exactly; higher ends the roll pose early.
@export_range(0.1, 4.0, 0.05) var dodge_mult: float = 1.0

@export_group("Limits")
## Walk playback never goes below / above these before the multiplier.
@export_range(0.1, 2.0, 0.05) var min_playback: float = 0.7
@export_range(0.5, 6.0, 0.05) var max_playback: float = 2.4
## Sprint has its own top: matching the walks to sprint speed needs ~4-5x (user feedback 2026-11-06).
@export_range(0.5, 8.0, 0.05) var sprint_max_playback: float = 4.5
