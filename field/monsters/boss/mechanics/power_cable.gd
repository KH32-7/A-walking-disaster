class_name PowerCable
extends StaticBody3D
## One of the neon colossus's three power cables (docs/design/04-monsters.md "보스": 전원 케이블 3개 끊으면 무력화).
## Weapons hit it like a monster: it sits on the monster layer and has take_damage(). The glowing mesh is the
## cue to aim at. colossus_mechanic.gd keeps the cable's hp, cuts it and restores it.

signal hit(cable: PowerCable, amount: float, info: Dictionary)

var cut := false


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_MONSTER - 1)
	collision_mask = 0


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if not cut and amount > 0.0 and not StatusHolder.is_tick(info):
		hit.emit(self, amount, info)


func set_cut(on: bool) -> void:
	cut = on
	visible = not on
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred(&"disabled", on)
