extends MonsterBehavior
## &"orb_fan" (elite signal wraith): its shock_orb fires MonsterRules.ORB_FAN_COUNT orbs
## in a fan. List it after shock_orb (elite_behaviors are always added after behaviors).


func on_added() -> void:
	var orb := monster.get_behavior(&"shock_orb")
	if orb:
		orb.orbs = MonsterRules.ORB_FAN_COUNT
