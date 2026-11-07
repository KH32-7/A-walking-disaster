@tool
class_name ExtractPoint
extends FieldMarker
## Extraction candidate (3 per map, 2 active per sortie). B-09 reads these.
## Data: id, type, wait_sec, noise_radius (02-field.md "데이터 정의").

const GROUP := &"field_extract_points"

enum Type { NORMAL, GENERATOR, KEY, BATTERY, HELICOPTER }

@export var id: StringName = &"":
	set(value):
		id = value
		_refresh()
@export var type: Type = Type.NORMAL:
	set(value):
		type = value
		_refresh()
## Seconds to stand in the zone before extracting (NORMAL: 5, GENERATOR: 20).
@export var wait_sec: float = 5.0:
	set(value):
		wait_sec = value
		_refresh()
## Noise made while waiting (GENERATOR: 25m).
@export var noise_radius: float = 0.0:
	set(value):
		noise_radius = value
		_refresh()
## Radius of the standing zone.
@export var zone_radius: float = 3.0:
	set(value):
		zone_radius = value
		_refresh()


## Shows (true) or removes the in-world beacon (ExtractBeacon). ExtractionManager.activate() calls
## this for every candidate: only the points open this sortie get one.
func set_active(on: bool) -> void:
	var beacon := get_node_or_null(^"ExtractBeacon")
	if on and beacon == null and not Engine.is_editor_hint():
		add_child(ExtractBeacon.new(zone_radius))
	elif not on and beacon != null:
		beacon.queue_free()


func _marker_group() -> StringName:
	return GROUP


func _gizmo_color() -> Color:
	return Color(0.2, 0.75, 1.0)


func _gizmo_label() -> String:
	return "ExtractPoint %s (%s, %ss)" % [id, Type.keys()[type], wait_sec]


func _build_gizmo() -> void:
	_add_ring(zone_radius)
	_add_cylinder(0.15, 3.0)
	if noise_radius > 0.0:
		_add_ring(noise_radius)


func _marker_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if id == &"":
		warnings.append("id is empty.")
	if wait_sec < 0.0:
		warnings.append("wait_sec is negative.")
	return warnings
