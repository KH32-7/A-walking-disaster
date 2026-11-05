extends Node3D
## Loads the player's character model at runtime, so player.tscn has no hard dependency on the
## private assets/ submodule. When the model is missing (CI, clones without asset access) the
## sibling Greybox stays visible instead.

## Model scene under res://assets/. Imported facing +Z; the player faces -Z.
@export_file("*.fbx", "*.glb", "*.tscn") var model_path := "res://assets/characters/hero/hero.fbx"
## Node shown when the model can't be loaded.
@export var fallback: NodePath = ^"../Greybox"


func _ready() -> void:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		return
	var scene := load(model_path) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	model.rotation.y = PI
	add_child(model)
	var fb := get_node_or_null(fallback) as Node3D
	if fb != null:
		fb.visible = false
