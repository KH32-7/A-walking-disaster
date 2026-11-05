extends Node3D
## City park region (B-24). Assembly: layout (B), dressing (D, optional), spawners, extraction,
## rescue, hidden routes, lost gear, camera and the player. Run alone with F6 to walk the map.
## Map source: build/city_park_map.json (user-confirmed), layout built by build/build_layout.gd.
## The boss arena marker is in the layout; the ancient tree giant itself is B-19.
## Design: docs/design/02-field.md "지역", "맵 구조"
## TODO(A-05): SceneRouter.go_to_field(loadout) picks spawn_id from the loadout.

const DRESSING_PATH := "res://levels/field/city_park/dressing.tscn"
const PLAYER_SCENE := preload("res://field/player/player.tscn")

## PlayerSpawn marker to start at: &"main" (south avenue, main gate) or &"east" (east road).
@export var spawn_id: StringName = &"main"
@export var spawn_player := true

var player: Node3D

@onready var _layout: Node3D = $Layout
@onready var _camera: FieldCamera = $FieldCamera


func _ready() -> void:
	if ResourceLoader.exists(DRESSING_PATH):
		add_child((load(DRESSING_PATH) as PackedScene).instantiate())
		$GreyboxLighting.queue_free()
	if spawn_player:
		player = _spawn_player()


func _spawn_player() -> Node3D:
	var spawn := _find_spawn()
	if spawn == null:
		push_error("CityPark: no PlayerSpawn %s" % spawn_id)
		return null
	var node := PLAYER_SCENE.instantiate() as Node3D
	add_child(node)
	node.global_transform = spawn.global_transform
	_camera.target = node
	_camera.snap()
	return node


func _find_spawn() -> PlayerSpawn:
	for node in _layout.find_children("*", "Marker3D"):
		if node is PlayerSpawn and node.spawn_id == spawn_id:
			return node
	return null
