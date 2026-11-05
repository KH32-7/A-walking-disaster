class_name RoofFader
extends Node
## Feeds the player position into roof_fade materials. Owner: Lane D (D-03).
## Put one in a dressing.tscn, add the roof/upper-wall materials to `materials`, and point
## `target` at the player (or leave empty: it finds the first node in group "player").
## Fading turns on only while the target is inside one of `interior_areas` (if any are set).

@export var target: Node3D
@export var materials: Array[ShaderMaterial] = []
@export var interior_areas: Array[Area3D] = []
@export var fade_speed := 6.0

var _amount := 0.0


func _process(delta: float) -> void:
	if target == null:
		target = get_tree().get_first_node_in_group(&"player") as Node3D
		if target == null:
			return
	var inside := interior_areas.is_empty()
	var body := target as PhysicsBody3D
	for a in interior_areas:
		if a != null and body != null and a.overlaps_body(body):
			inside = true
			break
	_amount = move_toward(_amount, 1.0 if inside else 0.0, delta * fade_speed)
	for m in materials:
		if m == null:
			continue
		m.set_shader_parameter(&"player_position", target.global_position)
		m.set_shader_parameter(&"fade_amount", _amount)
