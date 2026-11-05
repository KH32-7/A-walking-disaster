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

# --- Roaming packs (RoamingSpawner). Not in the design yet (user request 2026-11-05). ---
## Packs scattered over outdoor navmesh when the region loads.
const ROAM_START_GROUPS := 5
## One more pack this often (night: FieldState.night.spawn_mult faster, like the nests).
const ROAM_INTERVAL_SEC := 90.0
const ROAM_GROUP_MIN := 1
const ROAM_GROUP_MAX := 3
## Roaming monsters alive at once. They also count toward REGION_MAX_ALIVE.
const ROAM_MAX_ALIVE := 12
## New packs appear at least this far from the player and off camera.
const ROAM_MIN_PLAYER_DIST := 40.0
## Packs placed at load keep this far from the player.
const ROAM_START_MIN_PLAYER_DIST := 50.0
## Spawn points keep this far from nests and from other roaming packs' homes.
const ROAM_CLEAR_NEST := 20.0
const ROAM_SPREAD := 30.0
## A roaming pack wanders around its spawn point inside this radius.
const ROAM_WANDER_RADIUS := 25.0
## Navmesh points higher than this (2F, decks) are not spawn points.
const ROAM_MAX_Y := 1.5
## Random navmesh points tried per pack before giving up until the next try.
const ROAM_POINT_TRIES := 40

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

# --- B-18 behaviors (04 "마물 목록" 특징). Not in the design yet unless noted. ---
## &"noise_only" (statue): stands still once nothing was heard for this long.
const STATUE_QUIET_SEC := 3.0
## &"mist": seen only within 3 m (design). A flash reveals it for MIST_FLASH_SEC.
const MIST_REVEAL_RANGE := 3.0
const MIST_FLASH_SEC := 5.0
## &"slow_touch" (mist contact): slow put on the hit info.
## TODO(B-14): the status system decides how hit info carries slow.
const TOUCH_SLOW_SEC := 2.0
const TOUCH_SLOW_MULT := 0.7
## &"self_destruct" (neon moth): self-destruct noise radius (design 15 m).
const SELF_DESTRUCT_NOISE := 15.0
## &"shock_orb" (signal wraith): ranged orb, 3 s shock field where it lands (design 3 s).
const ORB_SPEED := 12.0
const ORB_MAX_RANGE := 16.0
const SHOCK_FIELD_SEC := 3.0
const SHOCK_FIELD_RADIUS := 1.5
const SHOCK_FIELD_TICK_SEC := 0.5
const SHOCK_FIELD_TICK_DAMAGE := 3.0
## TODO(B-14): the status system decides how hit info carries shock.
const SHOCK_SEC := 1.0
## &"orb_fan" (elite signal wraith): orbs per attack and the angle between them.
const ORB_FAN_COUNT := 3
const ORB_FAN_ANGLE_DEG := 20.0
## &"rally" (elite pattern, 04 example "주변 덩굴손을 불러모음"): on spotting a target,
## same-family monsters this close start chasing it too.
const RALLY_RADIUS := 15.0

## Any monster notices a target this close even without sight (blind statue attacks).
const TOUCH_SENSE_RANGE := 2.0

# --- Elite (04 "정예") ---
const ELITE_HP_MULT := 3.0
const ELITE_ATTACK_MULT := 1.5
const ELITE_SIZE_MULT := 1.3


## Target-side defense factor from the 03 damage formula: 100 / (100 + R).
static func defense_factor(defense: float) -> float:
	return 100.0 / (100.0 + maxf(defense, 0.0))
