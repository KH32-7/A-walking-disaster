class_name CombatTuning
extends Resource
## Weapon runtime numbers that are not item stats (B-06). Values: data/classes/combat_tuning.tres.
## Item stats (damage, attack_interval, range, magazine, pellets, ammo_id, backstab_mult ...) come
## only from Armory.get_item_stats(); this holds the 03 "근접 전투", "사격", "피해 공식" rules and the
## per-weapon-type fields of 03 "데이터 정의" WeaponType that ItemDef does not carry yet.
## Design reference: docs/design/03-combat-classes.md (가안)

@export_group("Damage formula")
## (1 + mastery_per_level x M). M = Progression class mastery (B-13); default_mastery is the
## fallback for a weapon without a family.
@export var mastery_per_level: float = 0.03
@export var default_mastery: int = 1
@export var crit_rate: float = 0.05
@export var crit_mult: float = 1.5

@export_group("Melee")
## Third hit of the combo.
@export var combo_hits: int = 3
@export var combo_finisher_mult: float = 1.5
## After a swing's attack_interval ends, the next swing continues the combo if it starts
## within this window. Index = Enums.CombatClass (GUN unused, BLADE, BLUNT).
@export var combo_window_sec: PackedFloat32Array = PackedFloat32Array([0.0, 0.35, 0.6])
## Half of this angle on each side of the facing direction is hit by a swing.
@export var melee_arc_deg: float = 100.0
## Behind = within this cone around the target's back.
@export var backstab_arc_deg: float = 90.0
## Used when the weapon stats have no backstab_mult (dagger has 2.5).
@export var backstab_mult: float = 2.0
## Durability lost per swing / per shot (05 "내구도").
@export var melee_wear: float = 0.2
@export var gun_wear: float = 0.1

@export_group("Block")
@export var block_arc_deg: float = 120.0
## Damage taken while blocking = incoming x this.
@export var block_damage_mult: float = 0.5
## Stamina lost per block = incoming damage x this.
@export var block_stamina_per_damage: float = 0.5
@export var guard_break_stun_sec: float = 1.0
@export var perfect_block_window_sec: float = 0.2
@export var perfect_block_stun_sec: float = 1.0

@export_group("Shooting")
## User decision 2026-11-06: aimed shots go exactly where you aim (no spread, no bloom).
@export var aim_spread_mult: float = 0.0
@export var moving_spread_mult: float = 1.5
## Flat speed above this counts as moving for spread.
@export var moving_speed_threshold: float = 0.5
@export var bloom_per_shot_deg: float = 1.0
## Bloom starts shrinking once no shot was fired for attack_interval x this.
@export var bloom_recover_delay_mult: float = 1.5
## Bloom shrinks back at this rate while not firing.
@export var bloom_recover_deg_per_sec: float = 6.0
## Hitscan ray height above the player's feet. Low cover (1.2m) is taller: rays pass through
## low cover (and remember it), walls and tall props block them.
@export var muzzle_height: float = 1.0
## Damage x this when the shot crossed low cover within cover_near_target_m of the target.
@export var cover_damage_mult: float = 0.5
@export var cover_near_target_m: float = 2.0
## Monsters are hit at any height on the shot line (short split slimes, rubble bugs): a box from
## this far below the shot height ...
@export var shot_hit_below: float = 1.5
## ... to this far above it. Walls are still found by the ray at muzzle_height.
@export var shot_hit_above: float = 2.0
## Aim help: half width (m) of the shot box against monsters. Index = Settings `aim_assist`
## (0 off = thin line, 1..3).
@export var shot_radius_by_assist: Array[float] = [0.0, 0.25, 0.4, 0.55]
## Starting pistol has infinite ammo (03 "사격"). TODO: a "starter" flag on the item once A adds one.
@export var infinite_ammo_defs: Array[StringName] = [&"pistol"]

@export_group("Weapon types")
## Per item def_id: spread_deg, spread_cap_deg (max bloom), reload_sec, stamina_cost, noise_action
## (NoiseTable action). Missing keys fall back to class_defaults[combat_class].
@export var weapon_types: Dictionary[StringName, Dictionary] = {}
## Index = Enums.CombatClass.
@export var class_defaults: Array[Dictionary] = []


## One field for a weapon: weapon_types[def_id][key], else class_defaults[combat_class][key], else fallback.
func weapon_value(def_id: StringName, combat_class: int, key: String, fallback: Variant) -> Variant:
	var entry: Dictionary = weapon_types.get(def_id, {})
	if entry.has(key):
		return entry[key]
	if combat_class >= 0 and combat_class < class_defaults.size():
		return class_defaults[combat_class].get(key, fallback)
	return fallback


func combo_window(combat_class: int) -> float:
	if combat_class >= 0 and combat_class < combo_window_sec.size():
		return combo_window_sec[combat_class]
	return 0.0
