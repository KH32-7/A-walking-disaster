class_name ComboDef
extends Resource
## Combination magic: two different elements engraved on one weapon (task A-10). Owner: Lane A.
## Data: data/essences/combos/<id>.tres. Design reference: docs/design/06-magic-essence.md "조합 마법".
## Element order does not matter (EssenceRules.get_combo sorts the pair).

## Lowercase snake case, same as the file name.
@export var id: StringName
@export var element_a: Enums.Element = Enums.Element.GREEN
@export var element_b: Enums.Element = Enums.Element.STONE
## Display name shown by Lane D.
@export var name: String
## Short effect text for Lane D.
@export var description: String
## Chance to fire per trigger.
@export var proc_rate := 0.2
## Chance when the two essences' average grade is EssenceRules.COMBO_HIGH_AVG_GRADE or higher.
@export var proc_rate_high := 0.3
## When it may fire: &"hit" (on hit) or &"kill" (on kill). Lane B (B-15) runs it.
@export var trigger: StringName = &"hit"
## Effect numbers. Same units as EssenceDef.effect_params.
@export var effect_params: Dictionary = {}
