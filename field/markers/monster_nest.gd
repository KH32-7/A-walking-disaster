@tool
class_name MonsterNest
extends FieldMarker
## Monster nest. B-07 spawns monsters here every spawn_interval_sec up to
## max_alive. The region-wide cap (40) is a global rule, not a marker value.
## Design reference: docs/design/04-monsters.md "감지와 행동"

const GROUP := &"field_monster_nests"

@export var family: Enums.Element = Enums.Element.GREEN:
	set(value):
		family = value
		_refresh()
@export var spawn_interval_sec: float = 180.0:
	set(value):
		spawn_interval_sec = value
		_refresh()
@export var max_alive: int = 6:
	set(value):
		max_alive = value
		_refresh()
## Monsters from this nest wander inside this radius (shown as a ring).
@export var wander_radius: float = 20.0:
	set(value):
		wander_radius = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(1.0, 0.35, 0.25)


func _gizmo_label() -> String:
	return "MonsterNest %s (%ss, max %d)" % [Enums.Element.keys()[family], spawn_interval_sec, max_alive]


func _build_gizmo() -> void:
	_add_cylinder(1.0, 0.6)
	_add_ring(wander_radius)


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if family == Enums.Element.NONE:
		warnings.append("family is NONE. Pick a monster family.")
	if max_alive <= 0:
		warnings.append("max_alive must be at least 1.")
	if spawn_interval_sec <= 0.0:
		warnings.append("spawn_interval_sec must be positive.")
	return warnings
