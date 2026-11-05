class_name BossMechanic
extends RefCounted
## A boss's own rules on top of BossMonster (the "공략 요소" column of docs/design/04-monsters.md "보스").
## BossDef.mechanic names the script; BossMonster makes one instance and calls these hooks. Patterns with
## a BossPattern.action are this script's to run; plain area and summon patterns keep the common code.
## Examples: the serpent only takes damage out of the water, the golem's guard doubles its defense.

var boss: BossMonster


## Once, at the end of BossMonster._ready (def, boss data and the visual are set).
func on_added() -> void:
	pass


## Every AI step, first thing (also while held, see BossMonster.hold).
func on_tick(_delta: float) -> void:
	pass


## False skips this pattern for now (for example: only while submerged).
func can_use(_pattern: BossPattern) -> bool:
	return true


## The pattern's windup began. `area` is the telegraph area, {} for summons and area-less actions.
func on_pattern_started(_pattern: BossPattern, _area: Dictionary) -> void:
	pass


## The windup is over. Return true when this script did the pattern itself (the common area hit and
## summon are skipped). Patterns with an `action` should always return true.
func land_pattern(_pattern: BossPattern, _area: Dictionary) -> bool:
	return false


## Attacker-side damage before the monster's part, element and defense factors. Return 0 to ignore the hit.
func filter_damage(amount: float, _info: Dictionary) -> float:
	return amount


func on_phase_changed(_phase: int) -> void:
	pass


## The fight reset at full hp out of combat (phase 1, cooldowns cleared).
func on_reset() -> void:
	pass


## Before the kill is recorded and the boss is freed. Clean up helpers (clones, cables) here.
func on_died() -> void:
	pass
