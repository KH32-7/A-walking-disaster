class_name MonsterBehavior
extends RefCounted
## Base for per-monster features listed in MonsterDef.behaviors (B-07).
## Monster creates one instance per id from Monster.BEHAVIORS and calls these hooks.

var monster: Monster


func on_state_changed(_old_state: Enums.AIState, _new_state: Enums.AIState) -> void:
	pass


## Add effect keys to the hit info before it reaches the target.
func modify_attack(_info: Dictionary) -> void:
	pass


## Called once, before monster_killed is emitted and the monster is freed.
func on_died() -> void:
	pass
