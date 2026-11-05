class_name PictureCardRound
extends Resource
## One picture card question for a COMMUNICATION rescue (B-10). Lane D draws the prompt and the
## three cards from these ids; the field only checks the answer.
## Design reference: docs/design/02-field.md "구조 이벤트" (소통: 그림 카드 고르기, 3지선다 2회).

## What the rescuer tries to say (Lane D picks the picture), e.g. &"come_with_us".
@export var prompt_id: StringName = &""
## Card ids shown, left to right. Three cards.
@export var options: Array[StringName] = []
## Index of the right card in options.
@export var answer := 0
