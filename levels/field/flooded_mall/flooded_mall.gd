extends Node3D
## Flooded mall region (B-12). Assembly: layout (B), dressing (D, optional), spawners, extraction,
## lost gear, camera and the player. Run alone with F6 to walk the map.
## Map source: build/flooded_mall_map.json (user-confirmed), layout built by build/build_layout.gd.
## Design: docs/design/02-field.md "지역", "맵 구조"
## TODO(A-05): SceneRouter.go_to_field(loadout) picks spawn_id from the loadout.

const DRESSING_PATH := "res://levels/field/flooded_mall/dressing.tscn"
## B-26 pack meshes of the kit buildings (built by build/build_layout.gd). They need the private
## assets/ submodule; without it (CI) the layout's greybox stays.
const BUILDINGS_PATH := "res://levels/field/flooded_mall/buildings.tscn"
const KIT_GREYBOX_GROUP := &"kit_greybox"
const CityKit := preload("res://field/buildings/city_kit.gd")
const PLAYER_SCENE := preload("res://field/player/player.tscn")

## PlayerSpawn marker to start at: &"main" (sortie 1, north gate) or &"east" (sortie 2, coast road).
@export var spawn_id: StringName = &"main"
@export var spawn_player := true

var player: Node3D

@onready var _layout: Node3D = $Layout
@onready var _camera: FieldCamera = $FieldCamera


func _ready() -> void:
	_add_buildings()
	if ResourceLoader.exists(DRESSING_PATH):
		add_child((load(DRESSING_PATH) as PackedScene).instantiate())
		$GreyboxLighting.queue_free()
	if spawn_player:
		player = _spawn_player()


## Swaps the kit buildings' greybox for the pack meshes. The greybox roofs leave the IndoorZone
## roof group so entering a building does not show them again.
func _add_buildings() -> void:
	if not CityKit.available() or not ResourceLoader.exists(BUILDINGS_PATH):
		return
	var kit := (load(BUILDINGS_PATH) as PackedScene).instantiate()
	add_child(kit)
	# Layout CSG that stays (stairs, ramp) gets pack textures; Lane D's toon skin leaves ShaderMaterials.
	var skins: Dictionary = kit.get_meta(&"layout_skins", {})
	for path: NodePath in skins:
		var shape := _layout.get_node_or_null(path)
		if shape != null:
			shape.set(&"material", skins[path])
	for node in get_tree().get_nodes_in_group(KIT_GREYBOX_GROUP):
		node.remove_from_group(CityKit.ROOF_GROUP)
		(node as Node3D).visible = false


func _spawn_player() -> Node3D:
	var spawn := _find_spawn()
	if spawn == null:
		push_error("FloodedMall: no PlayerSpawn %s" % spawn_id)
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
