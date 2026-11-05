extends MonsterBehavior
## &"alarm" (spore pod): on spotting a target it screams. The scream is an ordinary
## noise on EventBus.noise_emitted, so nearby monsters hear it like any other noise.
## TODO(B-14): spore projectile slow. Lane D plays the scream sound and effect.


func on_state_changed(old_state: Enums.AIState, new_state: Enums.AIState) -> void:
	# Only on spotting: ATTACK -> CHASE is the same encounter.
	if new_state == Enums.AIState.CHASE and old_state != Enums.AIState.ATTACK:
		EventBus.noise_emitted.emit(monster.global_position, MonsterRules.ALARM_SCREAM_RADIUS, monster)
