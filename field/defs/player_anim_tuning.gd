class_name PlayerAnimTuning
extends Resource
## Player animation playback numbers. Values live in data/classes/player_anim_tuning.tres and can be
## tuned live with the debug panel (\ key) (core/debug/anim_tuning_panel.gd).
##
## Walk clips play at (ground speed / the clip's own speed), clamped to min..max_playback, then
## multiplied by the multiplier for the current move. 1.0 = feet match the ground.

@export_group("Multipliers")
## Walk with no gun (body faces the move direction).
@export_range(0.1, 4.0, 0.05) var walk_mult: float = 1.0
## Sprint (the same walks played faster).
@export_range(0.1, 4.0, 0.05) var sprint_mult: float = 1.0
## Walk with a gun / while aiming (4-way rifle walks).
@export_range(0.1, 4.0, 0.05) var aim_walk_mult: float = 1.0
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
