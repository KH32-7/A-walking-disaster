class_name MonsterBehavior
extends RefCounted
## Base for per-monster features listed in MonsterDef.behaviors (B-07).
## Monster creates one instance per id from Monster.BEHAVIORS and calls these hooks.

var monster: Monster


## Called once right after the behavior is attached (in Monster._ready, or by make_elite()).
func on_added() -> void:
	pass


## Every AI step, before the state machine runs (also while stunned).
func on_tick(_delta: float) -> void:
	pass


## The monster heard a noise in range (EventBus.noise_emitted or a direct hear()).
func on_heard(_point: Vector3, _source: Node) -> void:
	pass


## True while the monster must stand still: no moving, turning or attacking (statue).
func blocks_action() -> bool:
	return false


func on_state_changed(_old_state: Enums.AIState, _new_state: Enums.AIState) -> void:
	pass


## Add effect keys to the hit info before it reaches the target.
func modify_attack(_info: Dictionary) -> void:
	pass


## Return true to replace the melee hit with something else (projectile, self-destruct).
## `info` already went through modify_attack. The monster still emits attack_landed.
func replace_attack(_info: Dictionary) -> bool:
	return false


## Called once, before monster_killed is emitted and the monster is freed.
func on_died() -> void:
	pass
