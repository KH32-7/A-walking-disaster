class_name QuestDef
extends Resource
## A quest: main story step, personal request, radio rumor, community or trade job.
## Owner: Lane A (task A-13). Data: data/quests/<id>.tres.
## Design reference: docs/design/13-world-narrative.md "퀘스트 유형", "데이터 정의" (QuestDef)
##
## trigger (when Quests starts it by itself; checked every morning and after a quest completes,
## never on the title screen):
##   &"manual"  only Quests.start() (story scripts, Lane C community events, debug console)
##   &"day"     trigger_params {"day": int}: from that day on
##   &"quest"   trigger_params {"quest": StringName}: after that quest completed
##   &"flag"    trigger_params {"flag": StringName}: once GameState.has_flag(flag)
##   &"trust"   trigger_params {"trust": int}: giver_id's trust reached it (개인 요청 40 / 80)
## A quest starts at most once; completed or failed quests never come back.
##
## rewards (all optional):
##   {"resources": {res_id: int},                   -> Economy.apply
##    "items": [{"def_id": StringName, "rarity": int}],  -> Armory.create_item (무기고 보관)
##    "flags": [StringName],                        -> GameState.set_flag(flag, true)
##    "trust": int}                                 -> giver's trust (Colony.add_trust, Lane C)
##
## fail_condition (all optional):
##   {"days": int,          fails on the morning when this many days have passed since it started
##    "giver_lost": bool}   fails if the giver leaves or dies
## A DEFEND objective whose day ends in a lost raid always fails the quest.

## Lowercase snake case, same as the file name.
@export var id: StringName
@export var type: Enums.QuestType = Enums.QuestType.MAIN
## PERSONAL only: which of the four request kinds (찾기·데려가기·만들기·지키기).
@export var request_type: Enums.RequestType = Enums.RequestType.FIND
@export var title: String
@export_multiline var description: String
@export var trigger: StringName = &"manual"
@export var trigger_params: Dictionary = {}
## Resident id, &"broadcaster" (방송실 지기), or &"" for rumors with no one asking.
@export var giver_id: StringName
@export var objectives: Array[QuestObjective] = []
@export var rewards: Dictionary = {}
@export var fail_condition: Dictionary = {}
## RUMOR: what the broadcaster says when the rumor starts (morning broadcast, Radio "quest_rumor").
@export_multiline var radio_text: String
