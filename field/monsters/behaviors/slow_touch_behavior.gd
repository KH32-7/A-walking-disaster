extends MonsterBehavior
## &"slow_touch" (mist contact, elite swamp blob): every hit slows the target.
## The target reads info["slow_sec"] and info["slow_mult"] (move speed x slow_mult).
## TODO(B-14): switch to the status effect format B-14 decides.


func modify_attack(info: Dictionary) -> void:
	info["slow_sec"] = MonsterRules.TOUCH_SLOW_SEC
	info["slow_mult"] = MonsterRules.TOUCH_SLOW_MULT
