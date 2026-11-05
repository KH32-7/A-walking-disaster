extends MonsterBehavior
## &"rally" (elite pattern, 04 example: elite vine tendril calls nearby vine tendrils):
## on spotting a target, every same-family monster within MonsterRules.RALLY_RADIUS
## starts chasing that target too.


func on_state_changed(old_state: Enums.AIState, new_state: Enums.AIState) -> void:
	if new_state != Enums.AIState.CHASE or old_state == Enums.AIState.ATTACK:
		return
	var target := monster.target
	if not is_instance_valid(target) or not monster.is_inside_tree():
		return
	for node in monster.get_tree().get_nodes_in_group(Monster.GROUP):
		var other := node as Monster
		if other == null or other == monster or other.is_dead() or other.def.family != monster.def.family:
			continue
		if other.global_position.distance_to(monster.global_position) <= MonsterRules.RALLY_RADIUS:
			other.chase(target)
