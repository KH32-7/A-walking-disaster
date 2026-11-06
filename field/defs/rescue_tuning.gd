class_name RescueTuning
extends Resource
## Rescue and escort numbers (B-10). Values live in data/classes/rescue_tuning.tres. All 가안.
## Design reference: docs/design/02-field.md "구조 이벤트", "함께 나오기 (호위)".

@export_group("Rescue")
## 갇힘: lock picking time while F is held (02: 10초 → 4초, user playtest 2026-11-06).
@export var lockpick_sec := 4.0
## 갇힘: letting go of F, or walking farther than this (m) from where it started, resets the gauge.
@export var lockpick_leave_m := 2.5
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
## Near follow_distance a follower walks at the player's own speed plus this much per metre of
## extra gap (1/s), capped at their walking speed. Keeps them from overtaking a slower player
## (walking backward) and stopping / starting every frame.
@export var follow_catch_up := 2.0
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

@export_group("Call out")
## A waiting person hears the player this close (m, through walls) and calls out (Lane D bubble).
@export var callout_far_m := 16.0
## Closer than this they beg for help instead (near lines).
@export var callout_near_m := 7.0
## Seconds between call outs. Coming from far into near calls out at once.
@export var callout_interval_sec := 5.0
## Lines per RescueSpawn.Type (0 갇힘, 1 부상, 2 소통). Said in turn, never the same one twice in a row.
@export var callout_far_lines: Dictionary[int, PackedStringArray] = {
	0: PackedStringArray(["저기요! 거기 누구 있어요?", "발소리... 맞죠? 사람이죠?"]),
	1: PackedStringArray(["어어... 사람 소리다...", "누구... 누구 있어요?"]),
	2: PackedStringArray(["흐윽... 흑...", "...누구?"]),
}
@export var callout_near_lines: Dictionary[int, PackedStringArray] = {
	0: PackedStringArray(["문이 꽉 끼었어요. 밖에서 좀 열어 줄래요?", "아, 진짜 왔다... 여기요, 이 문!"]),
	1: PackedStringArray(["으... 제발 살려주세요", "다리가... 말을 안 들어요..."]),
	2: PackedStringArray(["무서워... 무서워요...", "가지 마... 가지 마요..."]),
}

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
