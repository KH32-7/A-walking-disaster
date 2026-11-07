class_name VehicleTuning
extends Resource
## Numbers shared by every vehicle. Data: data/vehicles/tuning/vehicle_tuning.tres.
## Design reference: docs/design/02-field.md "탈것", "헬기 탈출" (가안).

@export_group("Field spawn")
## Share of VehicleSpots that get a vehicle each sortie.
@export_range(0.0, 1.0, 0.05) var spawn_ratio: float = 0.4
## Chance the rooftop helicopter extract is added on top of the 2 active ones.
@export_range(0.0, 1.0, 0.05) var helicopter_chance: float = 0.3
## A vehicle brought from the base stands this far right of the player spawn (m).
@export var brought_offset_m: float = 3.5

@export_group("Mechanic repair")
## Former job that can repair.
@export var mechanic_job: StringName = &"mechanic"
@export var repair_sec: float = 8.0
@export var repair_noise_action: StringName = &"vehicle_repair"
## Durability after a field repair of a wrecked (0) vehicle, as a share of max.
@export_range(0.0, 1.0, 0.05) var repaired_ratio: float = 0.5
@export var helicopter_repair_sec: float = 15.0
@export var helicopter_noise_action: StringName = &"helicopter_repair"
## Helicopter wreck model (null = grey box).
@export var helicopter_model: PackedScene
## The mechanic must stand this close to the vehicle (m).
@export var mechanic_range_m: float = 6.0
## Walking further than this from where the hold started cancels it (m).
@export var repair_leave_m: float = 1.5

@export_group("Riding")
## Party members this close to the player get on with them (m).
@export var board_range_m: float = 8.0
## Gap between the vehicle side and where people step off (m).
@export var exit_gap_m: float = 0.7
## Boats: walkable ground must be this close to step off (m).
@export var exit_snap_m: float = 1.5

@export_group("Ram")
@export var ram_min_speed: float = 6.0
@export var ram_damage_per_speed: float = 4.0
@export var ram_self_damage: float = 5.0
@export var ram_cooldown_sec: float = 0.5

@export_group("Damage look")
## Smoke below this share of max durability, fire below fire_ratio.
@export var smoke_ratio: float = 0.5
@export var fire_ratio: float = 0.25

@export_group("Base repair")
## Scrap 1 per this much lost durability (same as gear, 05 "내구도").
@export var durability_per_scrap: float = 10.0
