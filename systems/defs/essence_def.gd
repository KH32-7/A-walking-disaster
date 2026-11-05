class_name EssenceDef
extends Resource
## One essence type: element x grade (task A-10). Owner: Lane A.
## Data: data/essences/<id>.tres, id = essence_<element>_<grade> (docs/dev/contracts.md "아이템 id 규칙").
## Essence counts live in Economy under the same id (no storage cap).
## Design reference: docs/design/06-magic-essence.md "정수", "데이터 정의" (EssenceDef).
##
## effect_params units: *_chance and *_ratio are 0..1, *_sec are seconds, *_range / *_radius are
## metres, *_bonus are added fractions (0.2 = +20%), counts are ints. Lane B (B-15) reads them
## from Armory.get_item_stats()["essence_effects"] and runs the effect in combat.

## Lowercase snake case, same as the file name.
@export var id: StringName
## Display name shown by Lane D.
@export var name: String
@export var element: Enums.Element = Enums.Element.GREEN
@export var grade: Enums.EssenceGrade = Enums.EssenceGrade.LOW
## Weapon effect numbers (design 06 table "정수").
@export var effect_params: Dictionary = {}
## effect_params keys that scale with grade. Two engravings of the same element average these and
## multiply them by EssenceRules.SAME_ELEMENT_MULT; the other keys stay as they are.
@export var scaling_keys: Array[StringName] = []
## Accessory engraving: resistance to this element's damage (design 06 "정수의 다른 쓰임").
@export var resist_ratio := 0.0
## Weapon name modifier, e.g. "덩굴 감긴" -> "덩굴 감긴 마체테" (design 06 "이름과 경관").
@export var name_prefix: String
## Effect shape hint for Lane D: petal, square, drop, bolt.
@export var vfx_shape: StringName
## Footprint in the field bag grid.
@export var size := Vector2i(1, 1)
