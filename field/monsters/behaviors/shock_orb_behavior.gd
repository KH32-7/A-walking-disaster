extends MonsterBehavior
## &"shock_orb" (signal wraith): instead of a melee hit it fires a ShockOrb at the target.
## The orb leaves a ShockField where it lands. orb_fan (elite) raises `orbs` to fire a fan.

const ORB_SCENE := preload("res://field/monsters/projectiles/shock_orb.tscn")

var orbs := 1


func replace_attack(info: Dictionary) -> bool:
	var parent := monster.get_parent()
	var target := monster.target
	if parent == null or not is_instance_valid(target):
		return true
	var origin := monster.global_position + Vector3.UP * MonsterRules.SIGHT_RAY_HEIGHT
	var aim := target.global_position + Vector3.UP * MonsterRules.SIGHT_RAY_HEIGHT - origin
	if aim.length() < 0.01:
		aim = -monster.global_basis.z
	aim = aim.normalized()
	for orb in make_orbs(origin, aim, info):
		parent.add_child(orb)
	return true


## Orbs ready to add next to the monster, spread around `aim` when orbs > 1.
func make_orbs(origin: Vector3, aim: Vector3, info: Dictionary) -> Array[ShockOrb]:
	var out: Array[ShockOrb] = []
	for i in orbs:
		var angle := deg_to_rad(MonsterRules.ORB_FAN_ANGLE_DEG) * (i - (orbs - 1) * 0.5)
		var orb := ORB_SCENE.instantiate() as ShockOrb
		orb.velocity = aim.rotated(Vector3.UP, angle) * MonsterRules.ORB_SPEED
		orb.damage = monster.attack_damage()
		orb.info = info.duplicate()
		orb.info["shock_sec"] = MonsterRules.SHOCK_SEC
		orb.shooter = monster
		orb.position = origin
		out.append(orb)
	return out
