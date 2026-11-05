extends Node
## Autoload `Fx`. Owner: Lane D.
## Gameplay code calls `Fx.spawn(&"hit_spark", position, {"element": Enums.Element.GREEN})`
## and never instances VFX scenes directly, so art can change without touching gameplay.


func spawn(effect_id: StringName, position: Vector3, params: Dictionary = {}) -> void:
	# TODO(D-xx)
	pass
