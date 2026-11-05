class_name MonsterWeakPoint
extends Area3D
## Glowing core (발광 핵) on a monster (B-07). Hits here deal
## MonsterRules.WEAK_POINT_MULT. On the monster layer so weapon queries that
## include areas can hit it.


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_MONSTER - 1)
	collision_mask = 0
	monitoring = false


func take_damage(amount: float, info: Dictionary = {}) -> void:
	var monster := _find_monster()
	if monster == null:
		return
	var hit := info.duplicate()
	hit["weak_point"] = true
	monster.take_damage(amount, hit)


func _find_monster() -> Monster:
	var node := get_parent()
	while node != null and not node is Monster:
		node = node.get_parent()
	return node as Monster
