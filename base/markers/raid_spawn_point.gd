@tool
class_name RaidSpawnPoint
extends ColonyMarker
## Where a raid group enters the base map. `direction` matches EventBus.raid_warning info
## ("direction": StringName). Ref: docs/design/10-raids-defense.md

const MARKER_GROUP := &"base_raid_spawns"

@export_enum("north", "east", "south", "west") var direction: String = "north":
	set(v):
		direction = v
		_changed()
## Monsters spawn randomly inside this radius (m).
@export var spread_radius := 4.0:
	set(v):
		spread_radius = maxf(v, 0.0)
		_changed()


func direction_id() -> StringName:
	return StringName(direction)


func _marker_group() -> StringName:
	return MARKER_GROUP


func _helper_color() -> Color:
	return Color(0.95, 0.3, 0.3)


func _helper_mesh() -> Mesh:
	var prism := PrismMesh.new()
	prism.size = Vector3(spread_radius * 0.5 + 1.0, 2.0, 1.0)
	return prism


func _helper_offset() -> Vector3:
	return Vector3(0.0, 1.0, 0.0)


func _label_text() -> String:
	return "Raid %s (r %.0fm)" % [direction, spread_radius]


func _label_height() -> float:
	return 2.8
