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
## While the body faces the cursor (gun or aiming), walking straight away from where it faces is
## this much slower; sideways is unchanged, in between eases. User feedback 2026-11-06 (가안).
@export_range(0.1, 1.0, 0.05) var backpedal_speed_mult: float = 0.6
## How fast velocity reaches the target speed.
@export var acceleration: float = 30.0

@export_group("Dodge")
@export var dodge_distance: float = 3.5
## Not in the design doc yet (가안). Distance is covered over this time.
@export var dodge_duration_sec: float = 0.35
@export var dodge_invuln_sec: float = 0.3
@export var dodge_stamina: float = 25.0

@export_group("Vault")
## Pushing into low cover (B-06 low_cover group) this long climbs over it (가안). 0 = off.
@export var vault_hold_sec: float = 0.25
## Highest obstacle top above the feet (m). Same as LOW_COVER_MAX_H (city_kit, layout_builder).
@export var vault_max_height: float = 1.2
## Thickest obstacle it climbs over (m).
@export var vault_max_depth: float = 1.2
@export var vault_duration_sec: float = 0.45
## How far the feet clear the top at the arc's peak (m).
@export var vault_clearance: float = 0.15

@export_group("Interaction")
## Reach for loot containers and other interactables (가안, not in the design doc).
@export var interact_range: float = 1.5
