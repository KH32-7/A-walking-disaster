extends Node3D
## Hospital region. Assembly: layout (B), dressing (D, optional), spawners, extraction, rescue,
## hidden routes, lost gear, camera and the player. Run alone with F6 to walk the map.
## Map source: build/hospital_map.json (Claude's design), layout built by build/build_layout.gd.
## BossSpawner puts the surgical lamp wraith at the operating theatre's boss arena.
## Design: docs/design/02-field.md "지역", "맵 구조", "병원 맵"

const DRESSING_PATH := "res://levels/field/hospital/dressing.tscn"
## Pack dressing (built by build/build_layout.gd); needs the private assets/ submodule. Without it
## (CI) the layout's greybox stays.
const BUILDINGS_PATH := "res://levels/field/hospital/buildings.tscn"
const CityKit := preload("res://field/buildings/city_kit.gd")
const PLAYER_SCENE := preload("res://field/player/player.tscn")

## PlayerSpawn marker to start at: &"main" (south road, main gate) or &"east" (south road, east end).
@export var spawn_id: StringName = &"main"
@export var spawn_player := true

var player: Node3D

@onready var _layout: Node3D = $Layout
@onready var _camera: FieldCamera = $FieldCamera


func _ready() -> void:
	CityKit.attach(self, _layout, BUILDINGS_PATH)
	if ResourceLoader.exists(DRESSING_PATH):
		add_child((load(DRESSING_PATH) as PackedScene).instantiate())
		$GreyboxLighting.queue_free()
	if spawn_player:
		player = _spawn_player()


func _spawn_player() -> Node3D:
	var spawn := _find_spawn()
	if spawn == null:
		push_error("Hospital: no PlayerSpawn %s" % spawn_id)
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
