extends MonsterBehavior
## &"self_destruct" (neon moth): its attack is touching the target and blowing up.
## The target takes the monster's attack, the blast is a SELF_DESTRUCT_NOISE noise,
## and the moth vanishes without counting as a kill (no drops, no monster_killed).
## Shot down before touching = an ordinary kill.
## TODO(B-14/B-15): "빛으로 돌진" needs a light source API (flashlight, lamps). For now
## it charges by sound and sight only.


func replace_attack(info: Dictionary) -> bool:
	var target := monster.target
	if is_instance_valid(target) and target.has_method("take_damage"):
		target.take_damage(monster.attack_damage(), info)
	EventBus.noise_emitted.emit(monster.global_position, MonsterRules.SELF_DESTRUCT_NOISE, monster)
	Fx.spawn(&"neon_moth_blast", monster.global_position, {})
	monster.vanish()
	return true
