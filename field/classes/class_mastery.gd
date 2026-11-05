class_name ClassMastery
extends RefCounted
## Class mastery XP (B-13). 03: "그 계열 무기로 피해를 주거나 처치하면 오릅니다", 보조무기 50%.
## Lane B decides the XP, A-11 Progression stores it (add_mastery) and owns the level curve.
## XP is fractional per hit, so the remainder is kept here and whole points are sent on.
## The remainder is not saved (at most 1 XP per class is lost per sortie).

## 가안: XP per point of attacker-side damage, per kill, and the sub weapon slot factor.
const XP_PER_DAMAGE := 0.1
const XP_PER_KILL := 5.0
const SUB_WEAPON_MULT := 0.5

## Enums.CombatClass -> XP not sent yet (< 1).
var _pending: Dictionary = {}


## XP for one hit: damage x XP_PER_DAMAGE, + XP_PER_KILL when it killed, x0.5 with the sub weapon.
static func xp_for(damage: float, killed: bool, sub_weapon: bool) -> float:
	var xp := maxf(damage, 0.0) * XP_PER_DAMAGE + (XP_PER_KILL if killed else 0.0)
	return xp * (SUB_WEAPON_MULT if sub_weapon else 1.0)


## Current mastery of a class (1 when there is none, e.g. no weapon).
static func level(combat_class: int) -> int:
	if combat_class < 0 or combat_class >= Enums.CombatClass.size():
		return 1
	return Progression.mastery_level(combat_class)


## Adds one hit's XP to `combat_class`. Returns the mastery level after it.
func gain(combat_class: int, damage: float, killed: bool, sub_weapon: bool) -> int:
	if combat_class < 0 or combat_class >= Enums.CombatClass.size():
		return 1
	var total: float = _pending.get(combat_class, 0.0) + xp_for(damage, killed, sub_weapon)
	var whole := floori(total)
	_pending[combat_class] = total - whole
	if whole <= 0:
		return level(combat_class)
	return Progression.add_mastery(combat_class, whole)
