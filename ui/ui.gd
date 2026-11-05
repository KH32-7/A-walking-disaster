extends Node
## Autoload `UI`. Owner: Lane D.
## Opens/closes screens and owns the HUD layer. Gameplay lanes call `UI.open(&"bag")`
## etc.; they never add Control nodes to the tree themselves (sandbox debug UI excepted).
## Design reference: docs/design/14-ui-controls-accessibility.md


func open(screen_id: StringName, args: Dictionary = {}) -> void:
	# TODO(D-xx)
	pass


func close(screen_id: StringName) -> void:
	# TODO(D-xx)
	pass
