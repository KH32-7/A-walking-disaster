class_name CommandPress
extends RefCounted
## companion_command (V) split by press length (user decision for B-17, 2026-11-05):
## tap = 구조자 숨기 / 따라오기 (B-10 RescueManager), hold = 동행 주민 모드 전환 (B-17 CompanionManager).
## Each listener keeps its own instance and feeds it the same input every frame.

enum Result { NONE, TAP, HOLD }

## Held at least this long = HOLD (fires once while still held). Released earlier = TAP.
const HOLD_SEC := 0.5

## Seconds held, -1 while up.
var _held := -1.0
var _fired := false


func update(pressed: bool, delta: float) -> Result:
	if pressed:
		if _held < 0.0:
			_held = 0.0
			_fired = false
		else:
			_held += delta
		if not _fired and _held >= HOLD_SEC:
			_fired = true
			return Result.HOLD
		return Result.NONE
	var was_down := _held >= 0.0
	_held = -1.0
	return Result.TAP if was_down and not _fired else Result.NONE
