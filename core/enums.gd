class_name Enums
## Shared enums used by every lane. Owner: Lane A.
## Rule: only ADD values at the end of an enum. Never reorder or remove -
## saved games and .tres files store these as integers.

enum Phase { MORNING, SORTIE, STAY, EVENING, NIGHT }
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

## Monster family == magic element. Strong against: LIGHT > WATER > STONE > GREEN > LIGHT.
enum Element { NONE, GREEN, STONE, WATER, LIGHT }
enum EssenceGrade { LOW, MID, HIGH }

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
enum CombatClass { GUN, BLADE, BLUNT }
enum Aptitude { LOW, MID, HIGH }
enum EquipSlot { MAIN, SUB, HEAD, BODY, LEGS, ACCESSORY, BAG }

enum AgeStage { BABY, CHILD, TEEN, ADULT, ELDER }
enum AccessNeed { MOBILITY, LANGUAGE, HEARING, CARE }
enum HealthState { OK, INJURED, SICK }
enum ResidentStatus { ACTIVE, STRANDED, MISSING, DEAD }

enum MonsterTier { NORMAL, ELITE, BOSS, SIEGE }
enum AIState { SLEEP, WANDER, SUSPICIOUS, INVESTIGATE, CHASE, ATTACK, RETURN }

enum BaseTier { CAMP, SETTLEMENT, FORTRESS }
enum RaidOutcome { FLAWLESS, WIN, NARROW, LOSS }

## Fine-grained game flow driven by SceneRouter (design 01 "게임 상태").
## `Phase` is the coarse day phase saved with the game; each FlowState maps to one Phase
## (see GameState.PHASE_OF_FLOW). TITLE has no phase.
enum FlowState {
	TITLE,
	BASE_MORNING,
	SORTIE_PREP,
	FIELD,
	RESULT,
	BASE_STAY,
	BASE_DAY_RAID,
	EVENING,
	NIGHT,
	NIGHT_RAID,
	NIGHT_EVENT,
}

## Data enums from the design "데이터 정의" tables, shared because more than one lane reads them.
enum ResourceCategory { BASIC, PROCESSED, FIELD, MONSTER, SPECIAL }  # 11 ResourceDef
enum ExtractType { NORMAL, GENERATOR, KEY, BATTERY }  # 02 ExtractPoint
enum RelationFlag { LOVERS, MARRIED, RIVAL, GUARDIAN }  # 08 Relation
enum ArrivalMethod { BIRTH, ADOPTION }  # 08 Arrival
enum RaidTime { DAY, NIGHT }  # 10 RaidResult
enum RaidMode { AUTO, PLAYED }  # 10 RaidResult
enum QuestType { MAIN, PERSONAL, RUMOR, COMMUNITY, TRADE }  # 13 QuestDef
enum RequestType { FIND, ESCORT, CRAFT, PROTECT }  # 07/13 personal requests
enum EndingChoice { LEAVE, STAY }  # 13 EndingState

## Physics layer bit numbers (1-based, matches project.godot [layer_names]).
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ALLY := 3
const LAYER_MONSTER := 4
const LAYER_PLAYER_PROJECTILE := 5
const LAYER_MONSTER_PROJECTILE := 6
const LAYER_INTERACTABLE := 7
const LAYER_TRIGGER := 8


## Element multiplier when an attack of `attack` hits a target of `target`.
static func element_multiplier(attack: Element, target: Element) -> float:
	if attack == Element.NONE or target == Element.NONE:
		return 1.0
	if _beats(attack, target):
		return 1.5
	if _beats(target, attack):
		return 0.75
	return 1.0


static func _beats(a: Element, b: Element) -> bool:
	match a:
		Element.LIGHT:
			return b == Element.WATER
		Element.WATER:
			return b == Element.STONE
		Element.STONE:
			return b == Element.GREEN
		Element.GREEN:
			return b == Element.LIGHT
	return false
