class_name RescueSpawn
extends Resource
## One rescue target that can appear in a region (B-10). Lives in data/regions/<region>/rescues/.
## Design reference: docs/design/02-field.md "구조 이벤트", "함께 나오기 (호위)", "데이터 정의" (RescueSpawn).
## Added beyond the design table: move_type (the walking style decides speed, noise and nav layer)
## and card_rounds (COMMUNICATION only).

## Demo types (02 "데모 범위"). SURROUNDED / HIDING / CAPTURED come later: add at the end only.
enum Type { TRAPPED, INJURED, COMMUNICATION }
## 02 "함께 나오기" 이동 방식.
enum Move { WALK, SLOW, WHEELCHAIR, SUPPORTED, CHILD }

## Rescue profile id (DemoProfiles / data/resident_pool). Exactly one of template_id / resident_id.
@export var template_id: StringName = &""
## A stranded resident to bring back. TODO(B-11/C): Colony has no "return a stranded resident" call yet.
@export var resident_id: StringName = &""
@export var rescue_type := Type.INJURED
## The spawn goes only to a RescueSpot that has every one of these tags. Empty = any spot.
@export var spawn_tags: Array[StringName] = []
## Bag item used up by the rescue. INJURED: first_aid_kit. Empty = none.
@export var required_item: StringName = &""
## TODO(B-17/B-20): a party member with this trait (from Colony) will help. Stored only for now.
@export var required_trait: StringName = &""
@export var move_type := Move.WALK
## COMMUNICATION: the picture card rounds, in order (02: 3지선다 2회).
@export var card_rounds: Array[PictureCardRound] = []
## Spawns only once GameState has this flag (story rescues: the intro doctor needs intro_talked).
@export var required_flag: StringName = &""


## Id used for the party (ExtractionManager) and rescue_completed.
func party_id() -> StringName:
	return resident_id if resident_id != &"" else template_id


## Wheelchairs never use stairs: nav layer 2 only (B-12 bakes layer 1 = walkers, layer 2 = no stairs).
func navigation_layers() -> int:
	return 0b10 if move_type == Move.WHEELCHAIR else 0b01
