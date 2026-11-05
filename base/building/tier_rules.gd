class_name TierRules
## Base tiers and facility levels (C-10, docs/design/09-base-building.md "기지 단계", "건설 규칙").
## All numbers are 가안 and live here.

## 캐프 → 정착지: 인구 5, 목공소, 경사로 1개, 서쪽 숲(park_a) 개간.
## 정착지 → 요새: 인구 13, 발전기 가동, 석벽 20칸 이상(C-18), 북쪽 숲(park_b) 개간.
const REQUIREMENTS := {
	Enums.BaseTier.SETTLEMENT: {
		"population": 5, "buildings": {&"carpentry_shop": 1, &"ramp": 1}, "zones": [&"park_a"], "powered_generator": false,
	},
	Enums.BaseTier.FORTRESS: {
		"population": 13, "buildings": {&"stone_wall": 20}, "zones": [&"park_b"], "powered_generator": true,
	},
}

## 시설 레벨 상한 by tier (캐프 Lv1, 정착지 Lv2, 요새 Lv3).
const LEVEL_CAP := {Enums.BaseTier.CAMP: 1, Enums.BaseTier.SETTLEMENT: 2, Enums.BaseTier.FORTRESS: 3}

## 개간 중 묻힌 상자 (09 "구역과 개간"): chance per clearing work day, and what is inside.
const BURIED_BOX_CHANCE := 0.1
const BURIED_BOX_PARTS := Vector2i(2, 4)
const BURIED_BOX_BLUEPRINT_CHANCE := 0.3
## Blueprint flags a buried box can hold (GameState flags, see BuildingDef.requires_flags).
const BURIED_BOX_BLUEPRINTS: Array[StringName] = [&"blueprint_solar", &"blueprint_essence_workshop"]
## Base clearing progress per worker per day: same as construction (10 + 힘 보정).
const CLEAR_PROGRESS_BASE := 10.0


static func level_cap(tier: int) -> int:
	return LEVEL_CAP.get(tier, 1)
