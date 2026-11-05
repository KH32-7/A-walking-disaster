class_name RadioTrigger
extends Resource
## One kind of broadcaster line and its rules. Owner: Lane A (task A-14).
## Data: data/radio/<id>.tres. Design reference: docs/design/15-ai-features.md "AI 무전병"
## (template lines only - the team does not use an LLM).

## Lowercase snake case, same as the file name. Callers use it: Radio.say(&"low_ammo", {...}).
@export var id: StringName
## Five or so lines in the broadcaster's voice. {name} placeholders are filled from the context.
@export var lines: Array[String] = []
## The same trigger stays quiet this long after it spoke (halved on "often").
@export var cooldown_sec := 60.0
## Higher wins when lines compete during combat; passed on to EventBus.radio_message.
@export var priority := 1
## Guidance lines are muted when the radio frequency setting is "off". Story lines (morning
## broadcast) are not.
@export var guidance := true
## &"" no limit, &"sortie" once per sortie, &"day" once per day.
@export var once_per: StringName
