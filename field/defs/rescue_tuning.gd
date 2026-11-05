class_name RescueTuning
extends Resource
## Rescue and escort numbers (B-10). Values live in data/classes/rescue_tuning.tres. All 가안.
## Design reference: docs/design/02-field.md "구조 이벤트", "함께 나오기 (호위)".

@export_group("Rescue")
## 갇힘: lock picking time (02: 10초).
@export var lockpick_sec := 10.0
## 갇힘: door health. Monsters hitting it (layer 3) break it. Not in the design (가안).
@export var door_health := 60.0
## 갇힘 실패 → 방어 이벤트: hold out this long (02 포위 "60초 동안 지키기").
@export var defend_sec := 60.0
## The rescuer moving farther than this from where the lock picking started cancels it.
@export var channel_cancel_distance := 0.3
## 소통: wrong answers before the person turns wary (02: 2회 틀리면 경계).
@export var card_strikes := 2
## Base building that makes 소통 succeed at once (07 "통역 무전기").
@export var interpreter_building: StringName = &"interpreter_radio"

@export_group("Escort")
## Speed x player walk speed per RescueSpawn.Move. SUPPORTED: the player's own speed multiplier.
@export var speed_mult: Dictionary[int, float] = {0: 1.0, 1: 0.7, 2: 1.0, 3: 0.7, 4: 1.1}
## NoiseTable action per RescueSpawn.Move (radii in field/noise/noise_table.tres).
@export var move_noise: Dictionary[int, StringName] = {
	0: &"escort_walk", 1: &"escort_slow", 2: &"escort_wheelchair", 3: &"escort_supported", 4: &"escort_child"}
## Followers stop this close to the player (m).
@export var follow_distance := 2.0
## Path refresh interval (s).
@export var repath_sec := 0.25
## 숨기: look for low cover this far away (m). None = wait where they stand.
@export var hide_search_radius := 10.0
## A supported person walks this far to the player's right (m).
@export var support_offset := 0.6
## Player within this distance picks a hidden supported person up again (m).
@export var support_pickup_range := 2.0

@export_group("Child")
## A noise at least this big (m) startles a child (02: 큰 소음에 놀라 2초 멈춤).
@export var loud_noise_radius := 10.0
@export var startle_sec := 2.0

@export_group("Health")
@export var max_health := 50.0
## 02: 30초 안에 일으키기, else stranded on the spot.
@export var downed_sec := 30.0
## 일으키기 hold (03: F 3초, the same as companions).
@export var revive_sec := 3.0
## Health after being helped up, x max_health.
@export var revive_health_ratio := 0.5
## Radio `rescuee_low_health` once when health falls under this share.
@export var low_health_ratio := 0.3
