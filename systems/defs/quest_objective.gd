class_name QuestObjective
extends Resource
## One goal inside a QuestDef. Owner: Lane A (task A-13).
## Stored as a sub-resource of data/quests/<id>.tres.
## Design reference: docs/design/13-world-narrative.md "퀘스트 유형", 07-residents.md "신뢰도" (개인 요청)
##
## How each kind moves forward (systems/quests/quests.gd listens to EventBus):
##   VISIT    sortie_ended with "extracted" in `region_id`. With `companion_id` that resident must
##            have gone along (sortie_started loadout) and not been stranded (개인 요청 "데려가기").
##   RECOVER  sortie_ended: `count` of `target_id` came home in the loot (a resource id from
##            data/resources/, or an item def id from data/items/). Items in the safe pocket count
##            even after going down. `region_id` set = only loot from that region counts.
##   RESCUE   rescue_completed during a sortie in `region_id` (&"" = anywhere). `target_id` set =
##            only the rescued profile with that "id".
##   BUILD    building_completed for a building of def `target_id` (data/buildings/).
##   DEFEND   the quest's start day + `day_offset`: raid_resolved that day with outcome LOSS fails the
##            quest, anything better completes it. A day with no raid at all also completes it.

enum Kind { VISIT, RECOVER, RESCUE, BUILD, DEFEND }

## Kind names used in Quests.active_field_objectives() and the debug console.
const KIND_NAMES: Array[StringName] = [&"visit", &"recover", &"rescue", &"build", &"defend"]
## companion_id value that means "whoever gave this quest" (templated personal requests).
const GIVER := &"giver"

## Unique inside its quest, lowercase snake case.
@export var id: StringName
@export var kind: Kind = Kind.VISIT
## Shown in the quest log (Lane D). One short line.
@export var text: String
## Field region (levels/field/<region_id>/). VISIT needs one; RECOVER/RESCUE use it as a filter.
@export var region_id: StringName
## RECOVER: resource id or item def id. RESCUE: rescued profile id (&"" = anyone). BUILD: building def id.
@export var target_id: StringName
@export var count := 1
## VISIT: resident who must come along and come back. GIVER = the quest giver.
@export var companion_id: StringName
## Field objectives: name of the marker node in the region layout where Lane B puts the goal
## (keepsake pickup, crying child ...). &"" = Lane B picks a spot.
@export var marker: StringName
## Words under the double yellow diamond on the minimap / M map, e.g. "의사는 이 건물 안에 있다".
## "" = the objective text.
@export var marker_label: String = ""
## RECOVER: take the recovered resources out of storage when the quest completes (keepsakes).
@export var consume := false
## DEFEND: which day to hold, counted from the day the quest started.
@export var day_offset := 0


## True for goals that happen inside a field region (listed by Quests.active_field_objectives).
func is_field() -> bool:
	return kind in [Kind.VISIT, Kind.RECOVER, Kind.RESCUE] and region_id != &""
