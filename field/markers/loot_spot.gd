@tool
class_name LootSpot
extends FieldMarker
## Candidate position for a loot container. Open time, lock and noise come from
## the container data (B-08), not from the marker.

const GROUP := &"field_loot_spots"

## Container kinds from 02-field.md "루팅".
enum ContainerType { DRAWER, MEDICINE, TOOLBOX, SUPPLY_CRATE, MONSTER_NEST }

@export var container_type: ContainerType = ContainerType.DRAWER:
	set(value):
		container_type = value
		_refresh()
## Empty = use the region's loot table.
@export var loot_table_id: StringName = &"":
	set(value):
		loot_table_id = value
		_refresh()
## Furniture this container is (CityKit.PROPS piece, e.g. &"locker"), drawn by the container in
## place of the kind's crate look. Such spots are part of a room's furniture, so they always spawn
## (LootSpawner); their collision is baked into the building. Empty = a loose crate.
@export var look_piece: StringName = &"":
	set(value):
		look_piece = value
		_refresh()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(1.0, 0.85, 0.2)


func _gizmo_label() -> String:
	var table := " [%s]" % loot_table_id if loot_table_id != &"" else ""
	var look := " (%s)" % look_piece if look_piece != &"" else ""
	return "LootSpot %s%s%s" % [ContainerType.keys()[container_type], table, look]


func _build_gizmo() -> void:
	_add_box(Vector3(0.8, 0.6, 0.5))
