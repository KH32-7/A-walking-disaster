extends Node
## Autoload `Progression`. Owner: Lane A (task A-11).
## Player level / XP, max health from level, perks picked every few levels, and the stored
## class mastery (Lane B computes mastery XP and calls add_mastery; this only keeps it).
## Design reference: docs/design/12-progression-balance.md "경험치", 03-combat-classes.md "플레이어 레벨"
##
## XP sources (all numbers in the constants below):
##   monster_killed      -> kill XP by the MonsterDef tier (data/monsters/<id>.tres `tier`), live
##   SceneRouter         -> finish_sortie(): rescue XP (only when extracted) + extraction XP by region danger
##   raid_resolved       -> raid defence XP when the outcome is a win (FLAWLESS / WIN / NARROW)
##   other lanes / A-13  -> award(&"personal_request") etc.
## Every gain goes through add_xp(), which emits EventBus.xp_gained and level_up.

const MAX_LEVEL := 30
## XP_need(L) = floor(XP_BASE * L^XP_EXPONENT), L = current level (design 12 "경험치").
const XP_BASE := 100.0
const XP_EXPONENT := 1.4
const BASE_MAX_HP := 100
const HP_PER_LEVEL := 5
## A perk pick is earned at every multiple of this level (3, 6, ... 30).
const PERK_EVERY := 3

## XP per action (design 12 "경험치").
const XP_TABLE := {
	&"kill_normal": 5,
	&"kill_elite": 30,
	&"kill_boss": 300,
	&"kill_siege": 5,  # 가안: design gives no number for siege monsters (raid units).
	&"rescue": 50,  # per rescued person who made it out with the player
	&"extract_base": 30,  # extraction = extract_base + danger * extract_per_danger
	&"extract_per_danger": 10,
	&"personal_request": 80,
	&"raid_defended": 40,
}
const KILL_ACTION := {
	Enums.MonsterTier.NORMAL: &"kill_normal",
	Enums.MonsterTier.ELITE: &"kill_elite",
	Enums.MonsterTier.BOSS: &"kill_boss",
	Enums.MonsterTier.SIEGE: &"kill_siege",
}
const MONSTER_DEF_FMT := "res://data/monsters/%s.tres"
const REGION_DEF_FMT := "res://data/regions/%s.tres"
## Used when a region has no RegionDef yet (danger is 1..5 in design 02).
const DEFAULT_DANGER := 1
const DEFENDED_OUTCOMES := [Enums.RaidOutcome.FLAWLESS, Enums.RaidOutcome.WIN, Enums.RaidOutcome.NARROW]

## Perks (design 03 "플레이어 레벨" examples). 10 picks by level 30 = 5 perks x 2 stacks.
## `stat` is what perk_bonus() sums; `value` is added per stack. Readers:
##   bag_cells            Bag (extra cells on top of the bag grid)       Lane A / Bag
##   stamina              flat max stamina                               Lane B
##   medkit_pct           first aid kit healing +%                       Lane B
##   escort_speed_pct     rescued person move speed +%                   Lane B
##   lockpick_time_pct    door lockpicking time -% (negative)            Lane B
const PERKS := {
	&"bag_cells": {"name": "넉넉한 가방", "desc": "가방 +2칸", "stat": &"bag_cells", "value": 2, "max_stacks": 2},
	&"stamina": {"name": "단련된 체력", "desc": "스태미나 +10", "stat": &"stamina", "value": 10, "max_stacks": 2},
	&"medic": {"name": "응급 처치", "desc": "구급상자 효과 +20%", "stat": &"medkit_pct", "value": 20, "max_stacks": 2},
	&"escort": {"name": "길잡이", "desc": "구조자 이동 속도 +10%", "stat": &"escort_speed_pct", "value": 10, "max_stacks": 2},
	&"lockpick": {"name": "손재주", "desc": "문 따기 시간 −30%", "stat": &"lockpick_time_pct", "value": -30, "max_stacks": 2},
}

## Class mastery 1..MASTERY_MAX (design 03). XP to go from M to M+1 = floor(MASTERY_XP_BASE * M^XP_EXPONENT).
## 가안: the design gives no mastery curve; Lane B decides how much XP a hit / kill is worth.
const MASTERY_MAX := 10
const MASTERY_XP_BASE := 50.0

var level := 1
## XP into the current level (resets on level up). Stays 0 at MAX_LEVEL.
var xp := 0
var total_xp := 0
## Perk ids in pick order; the same id may appear up to max_stacks times.
var perks: Array[StringName] = []
## Enums.CombatClass -> {"level": int, "xp": int}
var mastery: Dictionary = {}

## XP earned since sortie_started (kills + finish_sortie), reported in the sortie result.
var _sortie_xp := 0


func _ready() -> void:
	_reset()
	SaveSystem.register_provider(&"progression", self)
	EventBus.sortie_started.connect(func(_loadout: Dictionary): _sortie_xp = 0)
	EventBus.monster_killed.connect(_on_monster_killed)
	EventBus.raid_resolved.connect(_on_raid_resolved)
	_register_debug()


# --- XP / level ---

## XP needed to go from `at_level` to the next one.
static func xp_to_next(at_level: int) -> int:
	return int(floor(XP_BASE * pow(at_level, XP_EXPONENT)))


func xp_needed() -> int:
	return 0 if level >= MAX_LEVEL else xp_to_next(level)


## XP for one action from XP_TABLE, times `count`. Returns what was actually added.
func award(action: StringName, count: int = 1) -> int:
	if not XP_TABLE.has(action):
		push_error("Progression: unknown XP action '%s'" % action)
		return 0
	return add_xp(int(XP_TABLE[action]) * count, action)


## Adds XP, levelling up as many times as it covers. Returns the XP added (0 at max level).
func add_xp(amount: int, reason: StringName = &"") -> int:
	if amount <= 0 or level >= MAX_LEVEL:
		return 0
	xp += amount
	total_xp += amount
	_sortie_xp += amount
	EventBus.xp_gained.emit(amount, reason)
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		EventBus.level_up.emit(level)
	if level >= MAX_LEVEL:
		xp = 0
	return amount


## Base max health from level (design 03: 100, +5 per level). Gear bonus comes from
## Armory.get_owner_summary(PLAYER_ID)["max_hp"]; Lane B adds the two.
func max_hp() -> int:
	return BASE_MAX_HP + HP_PER_LEVEL * (level - 1)


## SceneRouter calls this once when a sortie ends, before emitting sortie_ended.
## Awards rescue + extraction XP (only when extracted) and returns everything earned this sortie.
func finish_sortie(extracted: bool, region_id: StringName, rescued_count: int) -> int:
	if extracted:
		award(&"rescue", rescued_count)
		var danger := region_danger(region_id)
		add_xp(int(XP_TABLE[&"extract_base"]) + danger * int(XP_TABLE[&"extract_per_danger"]), &"extract")
	var earned := _sortie_xp
	_sortie_xp = 0
	return earned


## RegionDef.danger (Lane B, data/regions/<id>.tres), DEFAULT_DANGER when there is no def yet.
func region_danger(region_id: StringName) -> int:
	var def := _load_def(REGION_DEF_FMT, region_id)
	if def == null or def.get("danger") == null:
		return DEFAULT_DANGER
	return int(def.get("danger"))


## MonsterDef.tier (Lane B, data/monsters/<id>.tres), NORMAL when there is no def yet.
func monster_tier(monster_id: StringName) -> Enums.MonsterTier:
	var def := _load_def(MONSTER_DEF_FMT, monster_id)
	if def == null or def.get("tier") == null:
		return Enums.MonsterTier.NORMAL
	return int(def.get("tier")) as Enums.MonsterTier


# --- Perks ---

## Picks earned by level but not chosen yet.
func pending_perks() -> int:
	return maxi(level / PERK_EVERY - perks.size(), 0)


## Perk ids the player may choose now (every perk with stacks left), [] when no pick is pending.
func perk_choices() -> Array[StringName]:
	var out: Array[StringName] = []
	if pending_perks() <= 0:
		return out
	for id: StringName in PERKS:
		if perk_stacks(id) < int(PERKS[id]["max_stacks"]):
			out.append(id)
	return out


func choose_perk(perk_id: StringName) -> bool:
	if not perk_id in perk_choices():
		push_error("Progression: perk '%s' cannot be chosen now" % perk_id)
		return false
	perks.append(perk_id)
	EventBus.perk_chosen.emit(perk_id)
	return true


func perk_stacks(perk_id: StringName) -> int:
	return perks.count(perk_id)


## Sum of a perk stat over every chosen perk (see PERKS for the stat names). 0 if none.
func perk_bonus(stat: StringName) -> int:
	var total := 0
	for id in perks:
		var perk: Dictionary = PERKS.get(id, {})
		if perk.get("stat") == stat:
			total += int(perk["value"])
	return total


# --- Class mastery (Lane B computes, this stores) ---

static func mastery_xp_to_next(at_level: int) -> int:
	return int(floor(MASTERY_XP_BASE * pow(at_level, XP_EXPONENT)))


## Lane B: adds mastery XP to a combat class (sub-weapon 50 % is applied by B before calling).
## Returns the new mastery level. Emits mastery_level_up per level gained.
func add_mastery(combat_class: Enums.CombatClass, amount: int) -> int:
	var entry: Dictionary = mastery[combat_class]
	if amount <= 0 or int(entry["level"]) >= MASTERY_MAX:
		return int(entry["level"])
	entry["xp"] = int(entry["xp"]) + amount
	while int(entry["level"]) < MASTERY_MAX and int(entry["xp"]) >= mastery_xp_to_next(entry["level"]):
		entry["xp"] = int(entry["xp"]) - mastery_xp_to_next(entry["level"])
		entry["level"] = int(entry["level"]) + 1
		EventBus.mastery_level_up.emit(combat_class, entry["level"])
	if int(entry["level"]) >= MASTERY_MAX:
		entry["xp"] = 0
	return int(entry["level"])


func mastery_level(combat_class: Enums.CombatClass) -> int:
	return int(mastery[combat_class]["level"])


func mastery_xp(combat_class: Enums.CombatClass) -> int:
	return int(mastery[combat_class]["xp"])


# --- Signals ---

func _on_monster_killed(monster_id: StringName, _element: Enums.Element, _position: Vector3) -> void:
	award(KILL_ACTION[monster_tier(monster_id)])


func _on_raid_resolved(result: Dictionary) -> void:
	if result.get("outcome") in DEFENDED_OUTCOMES:
		award(&"raid_defended")


# --- Save provider ---

func save_data() -> Dictionary:
	var by_name := {}
	for c: int in mastery:
		by_name[Enums.CombatClass.keys()[c]] = mastery[c].duplicate()
	return {"level": level, "xp": xp, "total_xp": total_xp, "perks": perks.duplicate(), "mastery": by_name}


func load_data(data: Dictionary) -> void:
	_reset()
	level = clampi(int(data.get("level", 1)), 1, MAX_LEVEL)
	xp = maxi(int(data.get("xp", 0)), 0)
	total_xp = maxi(int(data.get("total_xp", 0)), 0)
	for id in data.get("perks", []):
		if PERKS.has(StringName(id)):
			perks.append(StringName(id))
		else:
			push_warning("Progression: unknown perk '%s' in save" % id)
	var saved_mastery: Dictionary = data.get("mastery", {})
	for c: int in mastery:
		var entry: Dictionary = saved_mastery.get(Enums.CombatClass.keys()[c], {})
		mastery[c] = {"level": clampi(int(entry.get("level", 1)), 1, MASTERY_MAX),
			"xp": maxi(int(entry.get("xp", 0)), 0)}


func _reset() -> void:
	level = 1
	xp = 0
	total_xp = 0
	perks.clear()
	mastery.clear()
	for c: int in Enums.CombatClass.values():
		mastery[c] = {"level": 1, "xp": 0}
	_sortie_xp = 0


func _load_def(fmt: String, id: StringName) -> Resource:
	if id == &"":
		return null
	var path := fmt % id
	return load(path) if ResourceLoader.exists(path) else null


# --- Debug commands ---

func _register_debug() -> void:
	DebugConsole.register(&"xp", func(args: PackedStringArray) -> String:
		if args.is_empty() or not args[0].is_valid_int():
			return "usage: xp <amount>"
		add_xp(int(args[0]), &"debug")
		return "level %d, xp %d/%d" % [level, xp, xp_needed()],
		"xp <amount>: add player XP")
	DebugConsole.register(&"perk", func(args: PackedStringArray) -> String:
		if args.is_empty():
			return "choices: %s" % [perk_choices()]
		return "ok" if choose_perk(StringName(args[0])) else "cannot choose %s" % args[0],
		"perk [id]: list perk choices or choose one")
