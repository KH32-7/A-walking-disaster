class_name DefenseRules
## 직접 방어전 (C-17, docs/design/10-raids-defense.md "직접 방어전"). Combat parts are Lane B's
## (B-23, field/README.md). All numbers are 가안 and live here.

## 3파, 파 사이 20초 준비 (함정 재설치·경비 배치), 5분 버티면 승리(남은 마물은 물러남).
const WAVES := 3
const PREP_SEC := 20.0
const SURVIVE_SEC := 300.0
## 긴급 귀환으로 돌아오면 2파부터 (1파는 자동 판정으로 끝난 것으로 친다).
const EMERGENCY_FIRST_WAVE := 2

## 습격 강도 I → 마물 포인트. 등급별 포인트. 한 파 최대 마릿수.
const POINTS_PER_STRENGTH := 0.5
const TIER_POINTS := {
	Enums.MonsterTier.NORMAL: 1, Enums.MonsterTier.ELITE: 3, Enums.MonsterTier.BOSS: 8, Enums.MonsterTier.SIEGE: 5,
}
const MAX_PER_WAVE := 12
const MONSTERS_DIR := "res://data/monsters"
## 공성 습격(siege)은 마지막 파에 공성 마물을 넣는다.
const SIEGE_TYPE := &"siege"

## 마물이 부술 수 있는 시설 (C-18 10 탭 표). 벽·목책은 structure_damage_mult(뿌리 파쇄자 ×3)를 받는다.
const WALLS: Array[StringName] = [&"palisade", &"stone_wall", &"iron_wall"]
const GATES: Array[StringName] = [&"wooden_gate", &"iron_gate"]
## 대피소 문이 부서지면 패배.
const SHELTER := &"shelter"
## 경비를 세울 수 있는 자리: 초소·문·대피소 앞.
const POST_BUILDINGS: Array[StringName] = [&"guard_post", &"wooden_gate", &"iron_gate", &"shelter"]

## 결과: 이기고 잃은 것이 없으면 완승, 2개 이하면 승리, 그보다 많으면 간신히 (잃은 것 = 부서진 시설 +
## 끝까지 쓰러진 경비 + 다친 주민). 지면 패배 표.
const WIN_MAX_HARM := 2



## Monster defs a raid can use: same family (NONE = any), no bosses; siege-only units apart.
static func monster_pool(family: int) -> Dictionary:
	var normal: Array[MonsterDef] = []
	var siege: Array[MonsterDef] = []
	var dir := DirAccess.open(MONSTERS_DIR)
	if dir == null:
		return {"normal": normal, "siege": siege}
	var files := dir.get_files()
	files.sort()
	for f in files:
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var def := load(MONSTERS_DIR.path_join(file)) as MonsterDef
		if def == null or def.scene == null or def.tier == Enums.MonsterTier.BOSS:
			continue
		if def.tier == Enums.MonsterTier.SIEGE:
			siege.append(def)
		elif family == Enums.Element.NONE or def.family == family:
			normal.append(def)
	if normal.is_empty() and family != Enums.Element.NONE:
		return monster_pool(Enums.Element.NONE)
	return {"normal": normal, "siege": siege}


## The waves of one raid: Array (per wave) of Array[MonsterDef]. Points are split evenly.
static func compose_waves(raid: Dictionary, rng: RandomNumberGenerator) -> Array:
	var pool := monster_pool(int(raid.get("family", Enums.Element.NONE)))
	var normal: Array = pool["normal"]
	var total := maxi(roundi(float(raid.get("strength", 10.0)) * POINTS_PER_STRENGTH), WAVES)
	var waves: Array = []
	for w in WAVES:
		var budget := total / WAVES + (1 if w < total % WAVES else 0)
		var wave: Array[MonsterDef] = []
		if w == WAVES - 1 and StringName(raid.get("type", &"")) == SIEGE_TYPE:
			for def: MonsterDef in pool["siege"]:
				if budget >= TIER_POINTS[def.tier]:
					wave.append(def)
					budget -= TIER_POINTS[def.tier]
		while budget > 0 and wave.size() < MAX_PER_WAVE and not normal.is_empty():
			var def: MonsterDef = normal[rng.randi_range(0, normal.size() - 1)]
			wave.append(def)
			budget -= int(TIER_POINTS.get(def.tier, 1))
		waves.append(wave)
	return waves


## Outcome of a played defence. `harm` = structures broken + guards left down + residents hurt.
static func outcome(won: bool, harm: int) -> Enums.RaidOutcome:
	if not won:
		return Enums.RaidOutcome.LOSS
	if harm == 0:
		return Enums.RaidOutcome.FLAWLESS
	return Enums.RaidOutcome.WIN if harm <= WIN_MAX_HARM else Enums.RaidOutcome.NARROW
