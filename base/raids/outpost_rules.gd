class_name OutpostRules
## 전초기지 (C-19, docs/design/10-raids-defense.md "방어 시설", "예고", "전초기지 위치·습격").
## Outposts stand on world-map nodes outside the base, so they are Colony data, not map buildings.
## The base map shows the four direction nodes with OutpostNode markers (same node ids).
## All numbers are 가안 and live here.

## 노드: 기지 주변 4방향 + 각 지역 입구 (data/regions/<id>.tres → "outpost_<id>", direction 없음).
const DIRECTION_NODES := {
	&"outpost_north": &"north", &"outpost_east": &"east", &"outpost_south": &"south", &"outpost_west": &"west",
}
const REGIONS_DIR := "res://data/regions"
const REGION_NODE_PREFIX := "outpost_"

## 짓기: 나무 60, 돌 30, 고철 20. 기지 밖이라 건설 주민 없이 2일 걸림 (가안).
const COST := {&"wood": 60, &"stone": 30, &"scrap": 20}
const BUILD_DAYS := 2
const DURABILITY := 400
## 주둔 2명 (가동 조건), 유지비 식량 2/일.
const GARRISON_JOB := &"garrison"
const GARRISON_SIZE := 2
const UPKEEP := {&"food": 2}
## 효과: 그 방향 습격 강도 −25%, 하루 전 예고 + 규모·계열 정보, 주변 채집 나무·고철 +5/일.
const DIRECTION_CUT := 0.25
const GATHER := {&"wood": 5, &"scrap": 5}

## 전초기지 습격: 습격의 20%는 전초기지를 노린다. 무너지면 주둔 주민이 다치고 전초기지는 멈춘다.
const RAID_TARGET_CHANCE := 0.2
const BASE_DEFENSE := 5.0           # 전초기지 자체 방어 (가안)
const LOST_INJURY_CHANCE := 1.0     # 무너지면 주둔 주민 모두 다침
## 수리: 짓는 비용의 30% (10 "수리"와 같음).
const REPAIR_SHARE := 0.3
