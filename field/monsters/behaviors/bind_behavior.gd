extends MonsterBehavior
## &"bind" (vine tendril): every hit binds the target for MonsterRules.BIND_SEC.
## The target reads info["bind_sec"] in its take_damage(amount, info).
## TODO(B-03/B-14): player and companions stop moving for bind_sec.


func modify_attack(info: Dictionary) -> void:
	info["bind_sec"] = MonsterRules.BIND_SEC
