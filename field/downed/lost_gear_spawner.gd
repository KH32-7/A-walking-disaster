class_name LostGearSpawner
extends Node3D
## Put one in each field region scene (B-11). Spawns a LostGearPoint for every lost gear drop
## the player can recover this sortie (FieldState.recoverable_gear()). Works whether the region
## scene loads before or after EventBus.sortie_started.

const POINT_SCENE := preload("res://field/downed/lost_gear_point.tscn")

## First item uid of a drop -> its LostGearPoint, so a second call does not spawn it twice.
var _spawned := {}


func _ready() -> void:
	EventBus.sortie_started.connect(_on_sortie_started)
	spawn_points()


func spawn_points() -> Array[LostGearPoint]:
	var made: Array[LostGearPoint] = []
	for drop: Dictionary in FieldState.recoverable_gear():
		var key: StringName = drop["item_uids"][0]
		if _spawned.has(key):
			continue
		var point: LostGearPoint = POINT_SCENE.instantiate()
		point.item_uids = drop["item_uids"]
		add_child(point)
		point.global_position = drop["position"]
		_spawned[key] = point
		made.append(point)
	return made


func _on_sortie_started(_loadout: Dictionary) -> void:
	# Points from an earlier sortie hold gear that is gone now.
	for point in _spawned.values():
		if is_instance_valid(point):
			point.queue_free()
	_spawned.clear()
	spawn_points()
