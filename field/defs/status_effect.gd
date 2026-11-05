class_name StatusEffect
extends Resource
## One status effect kind (B-14). Data lives in data/classes/status/<id>.tres.
## Fields follow docs/design/03-combat-classes.md "데이터 정의" StatusEffect.
## Extra runtime fields (not in the design table) are grouped under "Runtime".
## StatusHolder applies them to the player, monsters and rescued people alike.

@export var id: StringName = &""
@export var duration_sec: float = 1.0
## Damage per second per stack, dealt once every StatusHolder.TICK_SEC.
@export var tick_damage: float = 0.0
## Movement speed multiplier while active. 0 = cannot move (bind).
@export var move_mult: float = 1.0
@export var stacks_max: int = 1

@export_group("Runtime")
## No moving, turning, attacking or dodging (stagger, knockback).
@export var stops_actions: bool = false
## Target defense R multiplier (armor break 0.5).
@export var defense_mult: float = 1.0
## Pushed this far away from the hit over duration_sec (knockback).
@export var knockback_m: float = 0.0
## Element of the tick damage. Wet raises LIGHT ticks (shock) too.
@export var element: Enums.Element = Enums.Element.NONE
## Damage of this element taken while active is multiplied by vulnerable_mult (wet: LIGHT x1.25).
@export var vulnerable_element: Enums.Element = Enums.Element.NONE
@export var vulnerable_mult: float = 1.0
## All damage taken while active is multiplied by this (B-16 painkiller 0.8).
@export var damage_mult: float = 1.0
## Sight range multiplier while active (B-16 flash blind 0: no sight and no touch sensing).
@export var sight_mult: float = 1.0
