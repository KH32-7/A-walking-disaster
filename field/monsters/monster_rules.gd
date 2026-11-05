class_name MonsterRules
extends RefCounted
## Every monster rule number in one place (B-07). All values are drafts (가안).
## Per-monster numbers live in MonsterDef .tres files instead.
## Design reference: docs/design/04-monsters.md, 02-field.md "소음"

# --- Hearing (02 "소음", 04 "감지와 행동") ---
## Sleeping monsters hear at half range.
const SLEEP_HEARING_MULT := 0.5
## Noises a sleeping monster must hear before it wakes up suspicious.
const SLEEP_WAKE_NOISES := 2
## Hearing this many noises inside HEARING_WINDOW_SEC turns into a chase (first + 2 more).
const HEARING_CHASE_COUNT := 3
const HEARING_WINDOW_SEC := 3.0

# --- Sight ---
## Ray height above the feet of both the monster and the target.
const SIGHT_RAY_HEIGHT := 1.0
## Vision is checked this often, not every frame.
const SIGHT_CHECK_INTERVAL := 0.2

# --- States ---
const SUSPICIOUS_SEC := 1.0
## Seconds spent looking around after reaching the noise point.
const INVESTIGATE_LOOK_SEC := 6.0
## Give up walking to the noise point after this long (blocked path).
const INVESTIGATE_TRAVEL_MAX_SEC := 10.0
## Chase turns back into investigate after the target is out of sight this long.
const LOSE_TARGET_SEC := 8.0
## Leaving attack range by this factor goes back to chase.
const ATTACK_EXIT_MULT := 1.2
## Delay before the first hit after entering attack.
const ATTACK_WINDUP_SEC := 0.4
## Leash: farther than this from home returns to the nest.
const RETURN_DISTANCE := 40.0
## Fraction of max hp healed per second while returning.
const RETURN_REGEN_RATIO := 0.05

# --- Movement ---
const WANDER_SPEED_MULT := 0.4
const WANDER_PAUSE_MIN_SEC := 1.5
const WANDER_PAUSE_MAX_SEC := 4.0
const WANDER_LEG_MAX_SEC := 8.0
const DEFAULT_WANDER_RADIUS := 20.0
## Pack followers wander inside this radius around the leader.
const PACK_FOLLOW_RADIUS := 3.0
const ARRIVE_DISTANCE := 0.6
const TURN_SPEED_DEG := 360.0
const LOOK_AROUND_SPEED_DEG := 90.0

# --- Damage (03 "피해 공식": P and R are applied on the monster side) ---
## Glowing core (발광 핵) part multiplier.
const WEAK_POINT_MULT := 2.0

# --- Spawning (04 "등장") ---
## Region-wide cap on alive monsters.
const REGION_MAX_ALIVE := 40
## Monsters added per nest spawn tick.
const NEST_SPAWN_MIN := 1
const NEST_SPAWN_MAX := 2
## Spawned monsters appear inside this radius around the nest.
const SPAWN_SCATTER_RADIUS := 2.0

# --- Behaviors (04 "마물 목록" 특징) ---
## &"bind": vine tendril hit binds for 1 s.
const BIND_SEC := 1.0
## &"alarm": spore pod scream noise radius.
const ALARM_SCREAM_RADIUS := 20.0
## &"split": swamp blob splits into 2, at most 2 times (1 -> 2 -> 4).
const SPLIT_COUNT := 2
const SPLIT_MAX_GENERATIONS := 2
## Not in the design yet: each child has this share of the parent's max hp and size.
const SPLIT_HP_RATIO := 0.5
const SPLIT_SIZE_RATIO := 0.75
## Children appear this far from the parent.
const SPLIT_SPREAD := 0.8


## Target-side defense factor from the 03 damage formula: 100 / (100 + R).
static func defense_factor(defense: float) -> float:
	return 100.0 / (100.0 + maxf(defense, 0.0))
