class_name LoadingTips
extends Resource
## One-line tips for the loading / transition card (D-19). Owner: Lane D. Data: data/ui/loading_tips.tres.
## Every tip must match the design docs (docs/design/), never a number the code could change later.

@export var tips: Array[String] = []


## A tip picked by `seed` (stable for the same seed), or "" when the list is empty.
func pick(seed: int) -> String:
	if tips.is_empty():
		return ""
	return tips[posmod(seed, tips.size())]
