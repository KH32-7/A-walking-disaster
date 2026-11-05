class_name RaidRules
## Pure raid rules (C-08): threat, occurrence, strength, automatic judgment.
## Ref: docs/design/10-raids-defense.md "위협도", "발생 규칙", "습격 규모와 유형", "자동 판정".
## All numbers are 가안 (design placeholders) and live here in one place.

const THREAT_MAX := 100
## T_next = T + 3 + N_base + S − 2P − G
const THREAT_DAILY := 3.0
const THREAT_SEASON := 1.0          # 여름·겨울 +1
const THREAT_PER_OUTPOST := 2.0
const SCOUT_SENSE_BONUS_AT := 7     # 감각 7 이상 정찰 주민은 1.5명
const SCOUT_BONUS_WEIGHT := 1.5
const THREAT_AFTER_WIN := 20
const THREAT_AFTER_LOSS := 30

const FIRST_RAID_DAY := 5           # 5일차 전에는 습격 없음
## 직접 방어전 (C-17 / B-23). Off for now (사용자 요청 2026-11-06): every raid is judged
## automatically (RaidMode.AUTO). The battle code stays; turn this on to bring it back.
static var DIRECT_DEFENSE := false
## 습격 전체 (밤·낮·출격 중). Off for now (사용자 요청 2026-11-06): no raid is rolled.
## `force` rolls (debug `raid` command, tests) still work. Turn on to bring raids back.
static var RAIDS := false
## Night: threat → chance. Below 60 only a small swarm raid can happen.
const NIGHT_CHANCES := [[100, 1.0], [80, 0.5], [60, 0.3]]
const NIGHT_LOW_CHANCE := 0.05
const SMALL_RAID_STRENGTH_MULT := 0.5  # 소규모 무리 (가안)
const DAY_THRESHOLD := 70
const DAY_CHANCE := 0.2

## I = (10 + 1.5D + 2N + B_tier) × r, r ∈ [0.8, 1.2]
const STRENGTH_BASE := 10.0
const STRENGTH_PER_DAY := 1.5
const STRENGTH_PER_RESIDENT := 2.0
const STRENGTH_TIER_BONUS: Array[float] = [0.0, 20.0, 50.0]
const STRENGTH_RANDOM_MIN := 0.8
const STRENGTH_RANDOM_MAX := 1.2

## Raid types (10 "습격 규모와 유형"): weight, min tier, number of directions, monster family.
const TYPES := {
	&"swarm": {"weight": 50, "tier_min": Enums.BaseTier.CAMP, "directions": Vector2i(1, 1), "family": Enums.Element.NONE},
	&"wave": {"weight": 25, "tier_min": Enums.BaseTier.CAMP, "directions": Vector2i(2, 3), "family": Enums.Element.NONE},
	&"siege": {"weight": 15, "tier_min": Enums.BaseTier.SETTLEMENT, "directions": Vector2i(1, 1), "family": Enums.Element.NONE},
	&"fog": {"weight": 5, "tier_min": Enums.BaseTier.CAMP, "directions": Vector2i(1, 1), "family": Enums.Element.WATER},
	&"vine": {"weight": 5, "tier_min": Enums.BaseTier.CAMP, "directions": Vector2i(1, 1), "family": Enums.Element.GREEN},
}
const DIRECTIONS: Array[StringName] = [&"north", &"east", &"south", &"west"]
## Day raid radio warning with a guard post (10 "예고").
const DAY_WARNING_SEC := 60.0
## 출격 중 낮 습격: 출격 시작 뒤 이만큼 지나 경보가 온다 (초, 가안).
const FIELD_RAID_AFTER_SEC := Vector2(90.0, 300.0)

## Defense facility effects in the automatic judgment (10 "방어 시설", C-18, 가안).
const DECOY_CUT_MAX := 0.3            # 소음 미끼: 하나당 강도 −10%, 합쳐서 최대 −30%
const FOG_UNLIT_STRENGTH_MULT := 1.2  # 안개 습격: 조명탑이 없으면 강도 +20% (시야 −50%)
const LAMP_ESSENCE_PER_RAID := 2      # 정수 등불: 습격마다 하급 정수 2 (없으면 기여 0)
const LOW_ESSENCES: Array[StringName] = [&"essence_green_low", &"essence_stone_low", &"essence_water_low", &"essence_light_low"]
## 수리 (10 "수리"): 비용 = 건설 비용 30%, 작업 = 건설 진행도 50%. 벽 내구도는 건설 주민이 하루 100씩.
const REPAIR_COST_SHARE := 0.3
const REPAIR_WORK_SHARE := 0.5
const WALL_REPAIR_PER_DAY := 100

## Outcome bands by R (10 "자동 판정").
const RATIO_FLAWLESS := 1.5
const RATIO_WIN := 1.0
const RATIO_NARROW := 0.7
## Player present but chose 자동 판정으로 넘기기: defense +20%.
const PLAYED_BONUS := 1.2
## Uncertainty shown by the radio prediction (A-14): R × [0.85, 1.15] (가안).
const PREDICT_SPREAD := 0.15

## Guard power P_g = 무기 공격력 × 적성 ÷ 10 + 방어구 방어력 ÷ 10 + 감각 × 0.5, 무기 없으면 1/3.
const GUARD_WEAPON_DIV := 10.0
const GUARD_ARMOR_DIV := 10.0
const GUARD_SENSE_MULT := 0.5
const GUARD_UNARMED_MULT := 1.0 / 3.0
## 적성 (07 "클래스 적성과 주민 장비"): 상 +15%, 중 0, 하 −30%.
const APTITUDE_MULT := {Enums.Aptitude.LOW: 0.7, Enums.Aptitude.MID: 1.0, Enums.Aptitude.HIGH: 1.15}
const CLASS_KEYS := {Enums.CombatClass.GUN: &"gun", Enums.CombatClass.BLADE: &"blade", Enums.CombatClass.BLUNT: &"blunt"}

## Damage tables (10 "자동 판정"). Facility counts are [min, max].
const FLAWLESS_LOOT_SHARE := 0.3
const WIN_DURABILITY_LOSS := Vector2(0.1, 0.2)
const WIN_GUARD_INJURY := 0.1
const NARROW_DAMAGED := Vector2i(1, 2)
const NARROW_GUARD_INJURY := 0.3
const NARROW_CIVILIAN_INJURY := 0.2
const LOSS_DAMAGED := Vector2i(2, 4)
const LOSS_STORAGE_SHARE := 0.2
const LOSS_GUARD_SERIOUS := 0.5
const LOSS_GUARD_DEATH := 0.1
const LOSS_CIVILIAN_DEATH := 0.05
const LOSS_MORALE := -10
const INJURY_DAYS := 3
const SERIOUS_INJURY_DAYS := 7      # 보호 모드에서 사망 대신 중상 7일
## Never damaged by raids (10: 침상, 방송실, 대피소).
const INDESTRUCTIBLE: Array[StringName] = [&"bed", &"dormitory", &"family_house", &"radio_room", &"shelter"]
## Alarm + shelter → non-combatants take no damage.
const ALARMS: Array[StringName] = [&"warning_bell", &"warning_light"]
const SHELTER := &"shelter"
## Family → raid loot material (11 "자원 목록" 계열 재료). Essences: TODO(A-10).
const FAMILY_MATERIAL := {
	Enums.Element.GREEN: &"vine_fiber", Enums.Element.STONE: &"stone_shard",
	Enums.Element.WATER: &"water_moss", Enums.Element.LIGHT: &"neon_dust",
}


## Night/day raid chance for the current threat. `small` = only a small swarm can come.
static func raid_chance(time: int, threat: int) -> Dictionary:
	if time == Enums.RaidTime.DAY:
		return {"chance": DAY_CHANCE if threat >= DAY_THRESHOLD else 0.0, "small": false}
	for row in NIGHT_CHANCES:
		if threat >= row[0]:
			return {"chance": row[1], "small": false}
	return {"chance": NIGHT_LOW_CHANCE, "small": true}


static func strength(day: int, population: int, tier: int, r: float) -> float:
	return (STRENGTH_BASE + STRENGTH_PER_DAY * day + STRENGTH_PER_RESIDENT * population
		+ STRENGTH_TIER_BONUS[clampi(tier, 0, STRENGTH_TIER_BONUS.size() - 1)]) * r


static func pick_type(tier: int, rng: RandomNumberGenerator) -> StringName:
	var total := 0
	for t: StringName in TYPES:
		if tier >= TYPES[t]["tier_min"]:
			total += TYPES[t]["weight"]
	var roll := rng.randi_range(1, total)
	for t: StringName in TYPES:
		if tier < TYPES[t]["tier_min"]:
			continue
		roll -= TYPES[t]["weight"]
		if roll <= 0:
			return t
	return &"swarm"


static func pick_directions(type: StringName, rng: RandomNumberGenerator) -> Array[StringName]:
	var span: Vector2i = TYPES[type]["directions"]
	var pool := DIRECTIONS.duplicate()
	var picked: Array[StringName] = []
	for i in rng.randi_range(span.x, span.y):
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked


static func outcome_for(ratio: float) -> Enums.RaidOutcome:
	if ratio >= RATIO_FLAWLESS:
		return Enums.RaidOutcome.FLAWLESS
	if ratio >= RATIO_WIN:
		return Enums.RaidOutcome.WIN
	if ratio >= RATIO_NARROW:
		return Enums.RaidOutcome.NARROW
	return Enums.RaidOutcome.LOSS


## P_g for one guard. `weapon` / `armor_defense` come from Armory (A-07).
static func guard_power(resident: Dictionary, weapon: Dictionary, armor_defense: float) -> float:
	var p := armor_defense / GUARD_ARMOR_DIV + int(resident["stats"].get(&"sense", 0)) * GUARD_SENSE_MULT
	if weapon.is_empty():
		p *= GUARD_UNARMED_MULT
	else:
		var key: StringName = CLASS_KEYS.get(int(weapon.get("combat_class", -1)), &"")
		var apt := int(resident["class_aptitude"].get(key, Enums.Aptitude.MID))
		p += float(weapon.get("damage", 0.0)) * APTITUDE_MULT[apt] / GUARD_WEAPON_DIV
	return p * (1.0 + WorkRules.trait_sum(resident, &"guard_power"))
