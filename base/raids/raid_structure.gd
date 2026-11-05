class_name RaidStructure
extends StaticBody3D
## A defence facility the raiders can break during a played defence (C-17 + C-18, issue #109).
## Layer 1 body in group raid_structures (gates also raid_gates), take_damage(amount, info) per
## field/README.md (B-23). Damage goes straight to the Colony building's durability; walls and
## palisades take info.structure_damage_mult (뿌리 파쇄자 ×3). At 0 it is broken: Colony marks the
## building damaged, the node leaves the groups and frees itself.

signal broken(building_uid: StringName)

var building_uid: StringName = &""
var is_wall := false
var is_gate := false


## Builds the body for one completed building. `size` = footprint in metres (x, z), `height` in metres.
static func create(uid: StringName, def_id: StringName, size: Vector2, height: float) -> RaidStructure:
	var s := RaidStructure.new()
	s.name = "Raid_%s" % uid
	s.building_uid = uid
	s.is_wall = def_id in DefenseRules.WALLS
	s.is_gate = def_id in DefenseRules.GATES or def_id == DefenseRules.SHELTER
	s.collision_layer = 1 << (Enums.LAYER_WORLD - 1)
	s.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x - 0.2, 0.5), height, maxf(size.y - 0.2, 0.5))
	shape.shape = box
	shape.position.y = height * 0.5
	s.add_child(shape)
	s.add_to_group(RaidMarch.STRUCTURE_GROUP)
	if s.is_gate:
		s.add_to_group(RaidMarch.GATE_GROUP)
	return s


func durability() -> int:
	return int(Colony.get_building(building_uid).get("durability", 0))


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if not is_in_group(RaidMarch.STRUCTURE_GROUP) or amount <= 0.0:
		return
	var mult := float(info.get("structure_damage_mult", 1.0)) if is_wall else 1.0
	if Colony.damage_building(building_uid, roundi(amount * mult)) <= 0:
		_break()


func _break() -> void:
	remove_from_group(RaidMarch.STRUCTURE_GROUP)
	remove_from_group(RaidMarch.GATE_GROUP)
	broken.emit(building_uid)
	queue_free()
