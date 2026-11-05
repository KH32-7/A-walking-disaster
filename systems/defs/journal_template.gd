class_name JournalTemplate
extends Resource
## Lines for one kind of survival-journal entry (or one epilogue line). Owner: Lane A (task A-17).
## Data: ai/journal_templates/<id>.tres. Design reference: docs/design/15-ai-features.md
## "생존 일지와 에필로그" (template lines only - the team does not use an LLM).
##
## Placeholders: {name}, {other}, {building}, {region}, {joined}, {days} ... filled from the context.
## A Korean particle after a placeholder goes inside the braces so it matches the last syllable:
## "{name|이}" -> "지은이" / "민수가", also |을 |은 |과 |아 |으로 |이랑 (either spelling of the pair).
## Lines must follow the review rules in 15 "검수 규칙": no belittling of disability, age, origin or
## gender, no pity ("불쌍한"), no heroizing ("장애를 극복한"), no stereotypes, no graphic violence.

## Entry kind, same as the file name (Journal.record(&"rescued", ...)). Epilogue lines use
## &"epilogue_<status>" / &"epilogue_<highlight>".
@export var id: StringName
## Several lines; one is picked at random (never the same one twice in a row).
## Daily lines get the "N일차. " prefix from Journal, so they do not include the day.
@export var lines: Array[String] = []
## When a day has more than Journal.MAX_ENTRIES_PER_DAY entries, the lowest priority ones drop.
## Also decides which entry becomes a resident's epilogue highlight. Unused for epilogue lines.
@export var priority := 10
