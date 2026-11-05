class_name FieldExplore
extends Node
## "탐색한 영역" for the field map (D-16, design 14 "지도"). Owner: Lane D.
## Presentation memory only: while the flow state is FIELD it samples the player's position and
## remembers which CELL-sized squares of the ground came within REVEAL_RADIUS. It decides nothing
## in the game and is not saved (a resumed sortie starts with a clear fog). Cleared on sortie_started.
## UI owns one (UI.explore); tests and previews can make their own and call reveal().

## World metres per fog cell (가안).
const CELL := 4.0
## How far around the player the map counts as seen (가안).
const REVEAL_RADIUS := 18.0
## Seconds between samples.
const SAMPLE_SEC := 0.25

## Vector2i cell -> true
var cells: Dictionary = {}
var _t := 0.0


func _ready() -> void:
	EventBus.sortie_started.connect(func(_l: Dictionary) -> void: clear())


func _process(delta: float) -> void:
	if GameState.flow_state != Enums.FlowState.FIELD:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = SAMPLE_SEC
	var p := get_tree().get_first_node_in_group(&"player") as Node3D
	if p != null:
		reveal(p.global_position)


func clear() -> void:
	cells.clear()


## Marks every cell whose centre is within `radius` of `world` (x/z) as seen.
func reveal(world: Vector3, radius: float = REVEAL_RADIUS) -> void:
	var c := cell_of(world)
	var r := ceili(radius / CELL)
	var r2 := radius * radius
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var cell := c + Vector2i(dx, dz)
			var centre := Vector2((cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL)
			if centre.distance_squared_to(Vector2(world.x, world.z)) <= r2:
				cells[cell] = true


func is_seen(world: Vector3) -> bool:
	return cells.has(cell_of(world))


static func cell_of(world: Vector3) -> Vector2i:
	return Vector2i(floori(world.x / CELL), floori(world.z / CELL))
