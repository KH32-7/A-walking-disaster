class_name BossSpawner
extends Node3D
## Spawns each BossArena's boss (B-19). Put one in a region scene next to the layout.
## A killed boss stays away until FieldState.boss_respawn_day[boss_id] (design 04: 3 days). Each arena
## is checked on its own, so one region can hold several bosses (flooded mall).
## No boss before its BossDef.first_day. With RegionDef.bosses_per_day only that many arenas a day.
## Bosses start asleep at the arena center. Debug console: `boss` spawns them again at once.
## Design: docs/design/04-monsters.md "보스"

signal boss_spawned(boss: BossMonster, arena: BossArena)

const MONSTER_DIR := "res://data/monsters/"

## Region the bosses belong to (passed to BossMonster; an empty region keeps no respawn day).
@export var region_id: StringName = &""
@export var start_asleep := true

## BossArena -> BossMonster
var _bosses: Dictionary = {}
var _spawned := false


func _ready() -> void:
	DebugConsole.register(&"boss", _cmd_boss, "boss: 이 지역 보스를 지금 깨어 있는 채로 다시 소환 (리스폰 날짜 무시)")


func _process(_delta: float) -> void:
	if not _spawned:
		# Arenas join their group in their own _ready, so look on the first frame.
		_spawned = true
		spawn_all()


## Spawns today's bosses: past BossDef.first_day, picked for the day (RegionDef.bosses_per_day)
## and not waiting to respawn. A boss killed today leaves its arena empty for the rest of the day.
func spawn_all() -> void:
	_spawned = true
	var due: Array[BossArena] = []
	for node in get_tree().get_nodes_in_group(BossArena.GROUP):
		var arena := node as BossArena
		if arena != null and arena.boss_id != &"" and boss_started(arena.boss_id, GameState.day):
			due.append(arena)
	for arena in todays(due, GameState.day):
		if FieldState.boss_ready(arena.boss_id) and not is_instance_valid(_bosses.get(arena)):
			spawn_at(arena, start_asleep)


## The boss's first day (BossDef.first_day) has come.
static func boss_started(boss_id: StringName, day: int) -> bool:
	var boss := BossDef.for_monster(boss_id)
	return day >= (boss.first_day if boss else 1)


## The arenas out on `day`: all of them, or RegionDef.bosses_per_day picked by region and day.
## Picked before the respawn check, so killing today's boss does not bring out another one.
func todays(arenas: Array[BossArena], day: int) -> Array[BossArena]:
	var region := RegionDef.load_def(region_id) if region_id != &"" else null
	var count := region.bosses_per_day if region else 0
	if count <= 0 or arenas.size() <= count:
		return arenas
	var out := arenas.duplicate()
	out.sort_custom(func(a: BossArena, b: BossArena) -> bool: return String(a.boss_id) < String(b.boss_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [region_id, day])
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: BossArena = out[i]
		out[i] = out[j]
		out[j] = swap
	return out.slice(0, count)


## The boss for `arena`. Returns null when its MonsterDef or scene is missing.
func spawn_at(arena: BossArena, asleep: bool) -> BossMonster:
	var path := MONSTER_DIR + String(arena.boss_id) + ".tres"
	var def := load(path) as MonsterDef if ResourceLoader.exists(path) else null
	var boss := def.scene.instantiate() as BossMonster if def and def.scene else null
	if boss == null:
		push_warning("BossSpawner: %s is not a boss with a scene" % arena.boss_id)
		return null
	boss.def = def
	boss.region_id = region_id
	boss.arena_radius = arena.radius
	boss.home = arena.global_position
	boss.wander_radius = MonsterRules.BOSS_WANDER_RADIUS
	boss.start_state = Enums.AIState.SLEEP if asleep else Enums.AIState.WANDER
	boss.position = to_local(arena.global_position)
	boss.name = String(def.id)
	add_child(boss, true)
	_bosses[arena] = boss
	boss_spawned.emit(boss, arena)
	return boss


func boss_at(arena: BossArena) -> BossMonster:
	var boss = _bosses.get(arena)
	return boss if is_instance_valid(boss) else null


func _cmd_boss(_args: PackedStringArray) -> String:
	var names: Array[String] = []
	for node in get_tree().get_nodes_in_group(BossArena.GROUP):
		var arena := node as BossArena
		if arena == null or arena.boss_id == &"":
			continue
		var old := boss_at(arena)
		if old:
			old.vanish()
		if spawn_at(arena, false):
			names.append(String(arena.boss_id))
	return "소환: %s" % ", ".join(names) if not names.is_empty() else "보스 아레나가 없다"
