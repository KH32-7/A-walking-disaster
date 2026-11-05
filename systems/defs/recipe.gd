class_name Recipe
extends Resource
## One crafting recipe. Owner: Lane A (task A-09).
## Data: data/recipes/<id>.tres. Design reference: docs/design/05-gear.md "제작", "데이터 정의" (Recipe).
## Armory loads every recipe (Armory.recipes) and crafts with craft() / craft_by_worker().

## Lowercase snake case, same as the file name.
@export var id: StringName
## Building def id where it is made (data/buildings): workshop, sewing_room, infirmary ...
@export var facility: StringName
## Lowest building level of `facility` needed.
@export var facility_level := 1
## Resources spent per craft, resource_id -> amount (data/resources ids).
@export var inputs: Dictionary[StringName, int] = {}
## An Armory item def id (data/items, equipment) or an Economy resource id (data/resources).
@export var output_id: StringName
## Amount made per craft. Equipment recipes make 1.
@export var output_qty := 1
## Needs the GameState flag `blueprint_<id>` (Armory.blueprint_flag()). Blueprints are not spent.
@export var blueprint_required := false
## True: made by a resident's daily job and arrives at the evening settlement (ammo, consumables).
## False: the player crafts it in the morning (equipment).
@export var by_worker := false
