class_name ConsumableDef
extends Resource
## One consumable kind (B-16). Data lives in data/classes/consumables/<id>.tres; the id is the same
## as the bag resource id (data/resources/, contracts "아이템 id 규칙").
## Fields follow docs/design/03-combat-classes.md "데이터 정의" Consumable (id, effect, use_sec,
## can_move, noise); the numbers for each effect are grouped below. All numbers are 가안.

## SELF: heals and statuses on the user after use_sec. The rest are thrown at the aim point and
## act where they land: LURE (noise after delay_sec), FLASH (blind, mist reveal), BLAST (damage).
enum Effect { SELF, LURE, FLASH, BLAST }

@export var id: StringName = &""
## Shown when data/resources/<id>.tres has no ResourceDef yet (Lane A adds those).
@export var name: String = ""
@export var effect: Effect = Effect.SELF
## Seconds of holding still (or walking slowly) before it works. 0 = at once (thrown items).
@export var use_sec: float = 0.0
## True: the user may walk at ConsumableUser.USE_MOVE_MULT while using it. False: stands still.
@export var can_move: bool = false
## NoiseTable action (field/noise/noise_table.tres) made where the effect happens. &"" = silent.
@export var noise: StringName = &""
## Lower comes first when free quick slots are filled (keys 3 to 6).
@export var slot_priority: int = 0

@export_group("Self")
@export var heal: float = 0.0
## Progression.perk_bonus() stat that raises `heal` by that many percent (구급상자 효과 +20%).
@export var heal_perk_stat: StringName = &""
## Status removed from the user (bandage: bleed).
@export var remove_status: StringName = &""
## Status put on the user (painkiller).
@export var add_status: StringName = &""

@export_group("Thrown")
## Effect radius around the landing point (flash, blast).
@export var radius: float = 0.0
@export var damage: float = 0.0
## Seconds from landing to the effect (lure).
@export var delay_sec: float = 0.0
## Status put on monsters in the radius (flash: blind).
@export var target_status: StringName = &""
## LIGHT family monsters in the radius heal this share of their max hp instead (flash).
@export var light_heal_ratio: float = 0.0
