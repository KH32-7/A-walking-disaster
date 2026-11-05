class_name CompanionTuning
extends Resource
## Companion resident numbers (B-17). Values live in data/classes/companion_tuning.tres. All 가안.
## Weapon numbers (spread, reload, noise, crit, wear) come from the item stats and CombatTuning,
## the same as the player's.
## Design reference: docs/design/03-combat-classes.md "동행 주민 전투",
## 07-residents.md "능력치", "클래스 적성과 주민 장비", 02-field.md "함께 나오기 (호위)".

@export_group("Health")
## 03: 체력 = 80 + 힘 x 5 + 방어구.
@export var base_health := 80.0
@export var health_per_str := 5.0
## 03: 쓰러지면 30초 안에 일으켜야 하고(F 3초), 못 하면 고립.
@export var downed_sec := 30.0
@export var revive_sec := 3.0
## The helper moving farther than this from where they started helping cancels it (m).
@export var revive_cancel_distance := 0.5
## Health after being helped up, x max health (same as rescued people).
@export var revive_health_ratio := 0.5

@export_group("Damage")
## 07 적성: 상 피해 +15% / 중 보정 없음 / 하 피해 -30%. Key = Enums.Aptitude.
@export var aptitude_damage_mult: Dictionary[int, float] = {0: 0.7, 1: 1.0, 2: 1.15}
## 07 능력치: 둔기 피해 +3%/힘, 칼 피해 +3%/손재주.
@export var stat_damage_per_point := 0.03
## 07 능력치: 총 확산 -3%/감각.
@export var spread_per_sense := 0.03
## Melee reach on top of the weapon range (target body radius, m).
@export var melee_reach_bonus := 0.4

@export_group("Skill Q")
## 07: 적성 상만 스킬 사용 가능. Enums.Aptitude.
@export var skill_min_aptitude := 2
## 03: 클래스 스킬 1(Q)만 쓰며 쿨타임은 x1.5.
## The base cooldown is the class's skill_q (data/classes/).
@export var skill_cooldown_mult := 1.5

@export_group("AI")
## 공격적: attacks visible monsters this close to itself (m).
@export var engage_radius := 12.0
## 엄호: attacks monsters this close to the person it guards (m).
@export var cover_radius := 6.0
## Never chases farther than this from the player (or the guarded person) (m).
@export var leash_distance := 10.0
## Target search interval (s).
@export var retarget_sec := 0.3

@export_group("Movement")
## Stops this close to the player / guarded person (m).
@export var follow_distance := 2.0
## Farther than this from the player: runs (player sprint speed) to catch up (m).
@export var catchup_distance := 6.0
@export var repath_sec := 0.25
## Spawned this far to the side of the player, one slot per companion (m).
@export var spawn_offset := 1.5
## 02 동시 인원: 동행 주민 1명(후반 2명). The sortie prep picks how many; this is the hard cap.
@export var max_companions := 2
## NoiseTable footstep action per Mode (03 신중: 소음 최소).
@export var mode_footstep: Dictionary[int, StringName] = {0: &"escort_walk", 1: &"companion_quiet", 2: &"escort_walk"}
