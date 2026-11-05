class_name CompanionSkill
extends RefCounted
## A companion's class Q skill (B-13, B-17 hook). 03 "동행 주민 전투": Q only, cooldown x1.5
## (FieldCompanion keeps the cooldown and 적성 rule; this only runs the effect).
## Same SkillDef data as the player, aimed at the companion's target instead of the cursor:
## - precision_shot: focuses duration_sec, then one shot x damage_mult through every monster on
##   the line to the target (stops at walls, range = weapon range).
## - dash_slash: dashes toward the target up to `distance`, hits everything on the path.
## - slam: hits everything within `radius` around the companion, with the skill's statuses.
## Damage base = FieldCompanion.hit_damage() (weapon x 적성 x 능력치, no crit, no class mastery).

## Half width of the precision shot's piercing line (m).
const PIERCE_HALF_WIDTH := 0.4
const DASH_SEC := 0.15


## Runs the Q skill of the weapon's family. `deal` = the companion's (victim, amount, info) damage call.
static func run(companion: FieldCompanion, stats: Dictionary, target: Node3D, deal: Callable) -> void:
	var skill := ClassDef.skill_q_for(int(stats.get("combat_class", -1)))
	if skill == null or target == null or not companion.is_inside_tree():
		return
	match skill.id:
		&"precision_shot":
			await companion.get_tree().create_timer(skill.duration_sec, false, true).timeout
			if not is_instance_valid(companion) or not is_instance_valid(target) \
					or companion.state != FieldCompanion.State.ACTIVE:
				return
			_pierce(companion, stats, target, skill, deal)
		&"dash_slash":
			_dash(companion, stats, target, skill, deal)
		&"slam":
			for monster in SkillTargets.monsters_in_radius(companion, companion.global_position, skill.radius):
				deal.call(monster, companion.hit_damage(stats, 1.0) * skill.damage_mult, _info(companion, stats, skill, monster))
		_:
			return
	if not is_instance_valid(companion):
		return
	var noise := companion.get_node_or_null(^"Noise") as NoiseEmitter
	if noise != null and skill.noise != &"":
		noise.emit(skill.noise)
	Audio.play(skill.id, companion.global_position)
	Fx.spawn(skill.id, companion.global_position, {"radius": skill.radius})


static func _pierce(companion: FieldCompanion, stats: Dictionary, target: Node3D, skill: SkillDef,
		deal: Callable) -> void:
	var from := companion.global_position
	var dir := target.global_position - from
	var reach := SkillTargets.clear_distance(companion, from, dir, float(stats.get("range", 10.0)))
	var to := from + Vector3(dir.x, 0.0, dir.z).normalized() * reach
	Fx.spawn(&"bullet_tracer", from + Vector3.UP * SkillTargets.BODY_HEIGHT, {"to": to + Vector3.UP * SkillTargets.BODY_HEIGHT})
	for monster in SkillTargets.monsters_on_segment(companion, from, to, PIERCE_HALF_WIDTH):
		deal.call(monster, companion.hit_damage(stats, 1.0) * skill.damage_mult, _info(companion, stats, skill, monster))


static func _dash(companion: FieldCompanion, stats: Dictionary, target: Node3D, skill: SkillDef,
		deal: Callable) -> void:
	var from := companion.global_position
	var dir := target.global_position - from
	var to := from + Vector3(dir.x, 0.0, dir.z).normalized() \
			* SkillTargets.clear_distance(companion, from, dir, skill.distance)
	for monster in SkillTargets.monsters_on_segment(companion, from, to, skill.radius):
		deal.call(monster, companion.hit_damage(stats, 1.0) * skill.damage_mult, _info(companion, stats, skill, monster))
	companion.create_tween().tween_property(companion, ^"global_position", Vector3(to.x, from.y, to.z), DASH_SEC)


static func _info(companion: FieldCompanion, stats: Dictionary, skill: SkillDef, victim: Node3D) -> Dictionary:
	return {
		"source": companion,
		"element": stats.get("element", Enums.Element.NONE),
		"weapon": stats.get("def_id", &""),
		"position": victim.global_position,
		"status": skill.status_effects.duplicate(true),
		"skill": skill.id,
	}
