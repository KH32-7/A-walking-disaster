class_name SkillDef
extends Resource
## One class skill (B-13). Data: data/classes/skills/<id>.tres, referenced by ClassDef.skill_q / skill_e.
## Fields follow docs/design/03-combat-classes.md "데이터 정의" SkillDef; runtime-only fields are
## grouped under "Runtime". ClassSkills (player) and CompanionSkill (Q only) run them by id.
## All numbers are 가안.

@export var id: StringName = &""
@export var cooldown_sec: float = 10.0
## precision_shot: focus time / suppressive_fire, shadow_step, brace: how long it lasts.
@export var duration_sec: float = 0.0
## Damage x this (precision_shot next shot, dash_slash, shadow_step first attack, slam).
@export var damage_mult: float = 1.0
## slam: hit radius / brace: taunt radius / dash_slash: half width of the hit path (m).
@export var radius: float = 0.0
## NoiseTable action emitted on use (&"" = none). Gunshots and swings make their own noise.
@export var noise: StringName = &""
## Added to every hit of the skill: [{"id": &"slow"}, {"id": &"stagger", "duration": 1.5}] (StatusHolder).
@export var status_effects: Array[Dictionary] = []

@export_group("Runtime")
## Off = the key does nothing and the HUD leaves the slot out (03 "데모 범위": Q only).
@export var enabled: bool = true
## dash_slash: dash length (m).
@export var distance: float = 0.0
## brace: damage taken x this while active (-60% = 0.4).
@export var damage_taken_mult: float = 1.0
## Weapon stat that scales the cooldown (sniper rifle "정조준 쿨 -50%": aim_cooldown_mult 0.5).
@export var cooldown_stat: StringName = &""


## Cooldown for a skill used with a weapon of these Armory stats.
func cooldown_for(weapon_stats: Dictionary) -> float:
	if cooldown_stat == &"":
		return cooldown_sec
	return cooldown_sec * float(weapon_stats.get(cooldown_stat, 1.0))
