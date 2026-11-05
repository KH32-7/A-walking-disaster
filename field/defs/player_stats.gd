class_name PlayerStats
extends Resource
## Player base numbers (B-03). Values live in data/classes/player_base.tres.
## Design reference: docs/design/03-combat-classes.md "플레이어 기본 수치" (가안)

@export_group("Health")
@export var max_health: float = 100.0
@export var health_per_level: float = 5.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
## Per second, starting regen_delay_sec after the last stamina use.
@export var stamina_regen: float = 25.0
@export var stamina_regen_delay_sec: float = 0.8
@export var sprint_stamina_per_sec: float = 10.0

@export_group("Movement (m/s)")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.0
@export var aim_move_speed: float = 2.5
## How fast velocity reaches the target speed.
@export var acceleration: float = 30.0

@export_group("Dodge")
@export var dodge_distance: float = 3.5
## Not in the design doc yet (가안). Distance is covered over this time.
@export var dodge_duration_sec: float = 0.35
@export var dodge_invuln_sec: float = 0.3
@export var dodge_stamina: float = 25.0
