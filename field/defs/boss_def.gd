class_name BossDef
extends Resource
## Boss rules on top of a MonsterDef (B-19). data/monsters/bosses/<monster_id>.tres.
## Fields follow docs/design/04-monsters.md "데이터 정의" BossDef: monster_id, phases[], patterns[],
## first_kill_reward, respawn_days. All numbers are drafts (가안).

const DIR := "res://data/monsters/bosses/"

@export var monster_id: StringName = &""
## Hp ratios where the next phase starts. Design 04: [0.5] (phase 2 at 50%).
@export var phases: Array[float] = [0.5]
## Pattern cooldowns are divided by this per phase (index 0 = phase 1). Design 04: "패턴이 빨라집니다".
@export var phase_speed: Array[float] = [1.0, 1.5]
## Tried in list order: the first one ready and in range is used.
@export var patterns: Array[BossPattern] = []
## Wait after one pattern ends before the next can start.
@export var pattern_gap_sec: float = 1.0
## The boss's own rules (a BossMechanic script): special patterns (BossPattern.action), immunity, guard...
## Empty: only the common area and summon patterns.
@export var mechanic: Script
@export var respawn_days: int = 3
## First day the boss shows up at its arena (design 12 "보스 첫 도전": park 4~6, mall 12~18).
## Before it the arena stays empty, so a new player does not walk into a boss on day 1.
@export var first_day: int = 1
## Spawned asleep, it lies buried and climbs out on its first wake (BossMonster intro). Off for a boss
## whose mechanic hides it another way (the serpent starts underwater).
@export var buried_intro := true

@export_group("First kill")
## GameState flags set on the first kill. The park boss: blueprint_essence_workshop (Lane C's
## data/buildings/essence_workshop.tres requires_flags).
@export var first_kill_flags: Array[StringName] = []
## Shown once in the field notification.
@export var first_kill_text: String = ""
## Drop table for the first kill (no gear: the unique reward replaces it, 04 "드롭").
@export var first_kill_drop_table_id: StringName = &""

@export_group("Out of combat")
## Hp ratio healed per second while the boss is not fighting (sleeping, wandering).
## Returning home heals at MonsterRules.RETURN_REGEN_RATIO. At full hp it is back to phase 1.
@export var regen_ratio: float = 0.05


static func for_monster(monster_id: StringName) -> BossDef:
	var path := DIR + String(monster_id) + ".tres"
	return load(path) as BossDef if ResourceLoader.exists(path) else null


## 1-based phase for an hp ratio.
func phase_for(hp_ratio: float) -> int:
	var phase := 1
	for threshold in phases:
		if hp_ratio <= threshold:
			phase += 1
	return phase


func speed_for(phase: int) -> float:
	if phase_speed.is_empty():
		return 1.0
	return phase_speed[clampi(phase - 1, 0, phase_speed.size() - 1)]
