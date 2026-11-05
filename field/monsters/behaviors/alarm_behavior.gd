extends MonsterBehavior
## &"alarm" (spore pod): on spotting a target it screams. The scream is an ordinary
## noise on EventBus.noise_emitted, so nearby monsters hear it like any other noise.
## The spore slow (포자 투사) comes from &"slow_touch". Lane D plays the scream sound and effect.


func on_state_changed(old_state: Enums.AIState, new_state: Enums.AIState) -> void:
	# Only on spotting: ATTACK -> CHASE is the same encounter.
	if new_state == Enums.AIState.CHASE and old_state != Enums.AIState.ATTACK:
		EventBus.noise_emitted.emit(monster.global_position, MonsterRules.ALARM_SCREAM_RADIUS, monster)
		Fx.spawn(&"monster_scream", monster.global_position, {"element": monster.def.family})
