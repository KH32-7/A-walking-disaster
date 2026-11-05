class_name ResourceDef
extends Resource
## A stackable resource kept in base storage (Economy). Owner: Lane A (task A-06).
## Data: data/resources/<id>.tres. Design reference: docs/design/11-economy.md "데이터 정의".
## Equipment is not a resource (see Armory). Essences have their own EssenceDef (A-10).

## Lowercase snake case, same as the file name.
@export var id: StringName
## Display name shown by Lane D.
@export var name: String
@export var category: Enums.ResourceCategory = Enums.ResourceCategory.BASIC
## True: shares the base storage cap (basic and processed goods).
## False: unlimited (field-only rare goods, monster materials, special items).
@export var uses_storage_cap := true
## Footprint in the field bag grid (A-08).
@export var bag_size := Vector2i(1, 1)
## How many fit in one bag cell stack.
@export var stack_max := 10
