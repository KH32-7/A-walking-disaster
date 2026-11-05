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
