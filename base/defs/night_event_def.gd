class_name NightEventDef
extends Resource
## One night event (docs/design/08-relations-population.md "밤 이벤트"). Data: data/events/night/<id>.tres.
## Who can take part and what happens is in Colony (conditions per id, numbers in RelationRules);
## this holds what screens and the picker need. Lines are Lane A (Radio / AI 대화), the scene is D.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Pick weight among the events whose conditions hold tonight.
@export var weight := 10
## Always happens when its condition holds (결혼식, 이별), before the weighted picks.
@export var priority := false
## What the player can do during the scene. The first is used when nobody chooses (no screen).
@export var choices: Array[StringName] = [&"watch"]
