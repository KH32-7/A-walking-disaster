extends Node
## Autoload `Radio`. Owner: Lane A (tasks A-14 .. A-16).
## Decides WHEN the broadcaster speaks (rule-based triggers) and WHAT is said
## (LLM wording with offline templates as fallback), then emits EventBus.radio_message.
## Other lanes never emit radio_message for the broadcaster themselves - they call `say()`
## or emit their normal gameplay signals and let the trigger table react.
## Design reference: docs/design/15-ai-features.md

const BROADCASTER := &"broadcaster"


## Queue a line. `template_id` refers to data/radio/*.tres; `context` fills its variables.
func say(template_id: StringName, context: Dictionary = {}, priority: int = 0) -> void:
	# TODO(A-14): cooldowns, frequency setting, LLM wording, fallback templates.
	pass
