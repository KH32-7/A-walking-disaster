extends Node
## Autoload `SceneRouter`. Owner: Lane A (task A-05).
## Swaps the world scene under main.tscn's `World` node and drives the phase changes.
## Lanes never call get_tree().change_scene_*() themselves - they ask the router.

const BASE_SCENE := "res://levels/base/base_school/base_school.tscn"
## Field region scenes follow levels/field/<region_id>/<region_id>.tscn (Lane B).
const REGION_SCENE_FMT := "res://levels/field/%s/%s.tscn"


func go_to_base() -> void:
	# TODO(A-05): load BASE_SCENE into main.tscn/World, set phase MORNING or EVENING.
	pass


func go_to_field(loadout: Dictionary) -> void:
	# TODO(A-05): load REGION_SCENE_FMT % [id, id] for loadout.region_id, emit EventBus.sortie_started(loadout).
	pass
