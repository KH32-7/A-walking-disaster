class_name VehicleDef
extends Resource
## One vehicle kind. Data: data/vehicles/<id>.tres.
## Design reference: docs/design/02-field.md "탈것" (가안).

enum Surface { LAND, WATER }

## Lowercase snake case, same as the file name.
@export var id: StringName
@export var name: String
@export var surface: Surface = Surface.LAND
## Riders including the driver.
@export var seats: int = 1

@export_group("Movement")
## m/s at full throttle.
@export var speed: float = 8.0
## m/s².
@export var acceleration: float = 12.0
## Degrees per second.
@export var turn_speed_deg: float = 180.0

@export_group("Noise")
## NoiseTable action emitted continuously while moving (&"" = silent).
@export var noise_action: StringName

@export_group("Condition")
@export var max_durability: float = 60.0
@export var wheelchair_ok := false
## Chance that a field-spawned one needs a mechanic before it runs.
@export_range(0.0, 1.0, 0.05) var field_broken_chance: float = 0.0
## Hurts and pushes monsters it hits (car).
@export var ram := false

@export_group("Look")
## Model scene; null = graybox box of body_size.
@export var model: PackedScene
## Turns the model so its front faces -Z (Godot forward). Kenney models face +Z: 180.
@export var model_yaw_deg: float = 0.0
## Collision box (m), also the graybox size.
@export var body_size := Vector3(1.0, 1.2, 1.8)
