class_name NightTuning
extends Resource
## Field night rules (B-21). Values live in field/night_tuning.tres. All numbers are 가안.
## The dusk and night times are GameState.SORTIE_DUSK_SEC / SORTIE_NIGHT_SEC (12 / 15 min),
## the same constants the field HUD counts down from, so they are not repeated here.
## Design reference: docs/design/01-flow-time.md "필드의 밤", 04-monsters.md "등장"

## Off for the demo build (02 "데모 범위": 밤 시간 없음). Off = no dusk, no night, no dusk_left_sec in hud_state.
@export var enabled := true
## Nest spawn rate at night (04 "등장": 밤 x1.5). Nest timers run this much faster.
@export var spawn_mult := 1.5
## Monster sight range at night (01: 시야 -30%).
@export var sight_mult := 0.7
## Monster drops at night (01: 드롭 x1.3).
@export var drop_mult := 1.3
## Chance that a monster spawned at night is elite (04 "정예": 밤에 나옴). Not in the design yet.
@export_range(0.0, 1.0) var elite_chance := 0.15
