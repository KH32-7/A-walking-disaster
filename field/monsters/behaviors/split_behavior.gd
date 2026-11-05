extends MonsterBehavior
## &"split" (swamp blob): on death it splits into MonsterRules.SPLIT_COUNT smaller
## copies, up to MonsterRules.SPLIT_MAX_GENERATIONS times. Children keep the
## parent's home and pack and go after the parent's target.


func on_died() -> void:
	var parent := monster.get_parent()
	if parent == null:
		return
	for child in make_children():
		# Deferred: death can happen inside a physics callback (melee hitbox).
		parent.add_child.call_deferred(child, true)


## Children ready to add next to the monster. Empty once the split limit is reached.
func make_children() -> Array[Monster]:
	var children: Array[Monster] = []
	if monster.split_generation >= MonsterRules.SPLIT_MAX_GENERATIONS:
		return children
	var scene: PackedScene = monster.def.scene
	if scene == null:
		scene = load(monster.scene_file_path)
	var has_target := is_instance_valid(monster.target) and monster.target.is_inside_tree()
	for i in MonsterRules.SPLIT_COUNT:
		var child := scene.instantiate() as Monster
		child.name = "%s_split%d" % [monster.def.id, monster.split_generation + 1]
		child.def = monster.def
		child.split_generation = monster.split_generation + 1
		child.hp_scale = monster.hp_scale * MonsterRules.SPLIT_HP_RATIO
		child.home = monster.home
		child.wander_radius = monster.wander_radius
		child.transform = monster.transform
		child.scale = monster.scale * MonsterRules.SPLIT_SIZE_RATIO
		var angle := TAU * i / MonsterRules.SPLIT_COUNT
		child.position += Vector3(cos(angle), 0.0, sin(angle)) * MonsterRules.SPLIT_SPREAD
		if has_target:
			child.target = monster.target
			child.start_state = Enums.AIState.CHASE
		else:
			child.start_state = Enums.AIState.SUSPICIOUS
		if monster.pack:
			monster.pack.add(child)
		children.append(child)
	return children
