class_name MonsterSpawner
extends Node3D
## Spawns monsters at every MonsterNest marker in the scene (B-07).
## Put one in a region scene next to the layout. Each nest gets one pack at start,
## then 1 to 2 more every spawn_interval_sec while under the nest's max_alive and
## the region cap (MonsterRules.REGION_MAX_ALIVE).
## At night (FieldState.is_night(), B-21) nest timers run FieldState.night.spawn_mult faster,
## new monsters may be elite, and every monster gets the night sight and drop multipliers.
## Design reference: docs/design/04-monsters.md "등장", 01-flow-time.md "필드의 밤"

signal monster_spawned(monster: Monster, nest: MonsterNest)

## Spawn pool. A nest picks NORMAL tier defs whose family matches the nest.
@export var monster_defs: Array[MonsterDef] = []
## Limits the pool to defs listing this region. Empty = no region filter.
@export var region_id: StringName = &""
## Spawn one pack (def.group_min to group_max) per nest right away.
@export var spawn_initial_pack: bool = true

## [{"nest": MonsterNest, "timer": float, "alive": Array[Monster], "pack": MonsterPack}]
var _nests: Array[Dictionary] = []
var _collected := false


func _ready() -> void:
	FieldState.night_started.connect(_on_night_started)


func _process(delta: float) -> void:
	tick(delta)


## Advances nest timers. Tests call this with large deltas.
func tick(delta: float) -> void:
	if not _collected:
		# Nests join their group in their own _ready, so collect on the first tick.
		_collected = true
		_collect_nests()
	for entry in _nests:
		var nest: MonsterNest = entry.nest
		if not is_instance_valid(nest):
			continue
		entry.timer -= delta * (FieldState.night.spawn_mult if FieldState.is_night() else 1.0)
		while entry.timer <= 0.0:
			entry.timer += nest.spawn_interval_sec
			spawn_at(entry, randi_range(MonsterRules.NEST_SPAWN_MIN, MonsterRules.NEST_SPAWN_MAX), null)


func alive_count(nest: MonsterNest) -> int:
	for entry in _nests:
		if entry.nest == nest:
			_prune(entry)
			return entry.alive.size()
	return 0


func region_alive_count() -> int:
	return get_tree().get_nodes_in_group(Monster.GROUP).size()


func _collect_nests() -> void:
	for node in get_tree().get_nodes_in_group(MonsterNest.GROUP):
		var nest := node as MonsterNest
		var entry := {"nest": nest, "timer": nest.spawn_interval_sec, "alive": [], "pack": MonsterPack.new()}
		_nests.append(entry)
		if spawn_initial_pack:
			var def := _pick_def(nest)
			if def:
				spawn_at(entry, randi_range(def.group_min, def.group_max), def)


## Spawns up to `count` monsters at a nest. def = null picks one per monster.
func spawn_at(entry: Dictionary, count: int, def: MonsterDef) -> void:
	var nest: MonsterNest = entry.nest
	_prune(entry)
	for i in count:
		if entry.alive.size() >= nest.max_alive or region_alive_count() >= MonsterRules.REGION_MAX_ALIVE:
			return
		var pick := def if def else _pick_def(nest)
		if pick == null or pick.scene == null:
			push_warning("MonsterSpawner: no spawnable def for nest %s" % nest.name)
			return
		var monster := pick.scene.instantiate() as Monster
		monster.def = pick
		monster.home = nest.global_position
		monster.wander_radius = nest.wander_radius
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * randf() * MonsterRules.SPAWN_SCATTER_RADIUS
		monster.position = to_local(nest.global_position + offset)
		(entry.pack as MonsterPack).add(monster)
		monster.name = String(pick.id)
		add_child(monster, true)
		entry.alive.append(monster)
		if FieldState.is_night():
			apply_night(monster, true)
		monster_spawned.emit(monster, nest)


func _pick_def(nest: MonsterNest) -> MonsterDef:
	var pool: Array[MonsterDef] = []
	for def in monster_defs:
		if def == null or def.family != nest.family or def.tier != Enums.MonsterTier.NORMAL:
			continue
		if region_id != &"" and not def.regions.is_empty() and not def.regions.has(region_id):
			continue
		pool.append(def)
	return pool.pick_random() if not pool.is_empty() else null


## Night rules on one monster. drop_mult, sight_mult and make_elite() come with B-18;
## until it lands the guards skip them. TODO(B-18 merged): test the real multipliers.
## Static so RoamingSpawner applies the same rules.
static func apply_night(monster: Monster, roll_elite: bool) -> void:
	var rules := FieldState.night
	if "sight_mult" in monster:
		monster.set(&"sight_mult", rules.sight_mult)
	if "drop_mult" in monster:
		monster.set(&"drop_mult", rules.drop_mult)
	if roll_elite and monster.has_method(&"make_elite") and randf() < rules.elite_chance:
		monster.call(&"make_elite")


## Monsters already out when night falls see less and drop more, but do not turn elite.
func _on_night_started() -> void:
	for entry in _nests:
		_prune(entry)
		for monster: Monster in entry.alive:
			apply_night(monster, false)


func _prune(entry: Dictionary) -> void:
	entry.alive = entry.alive.filter(func(m: Variant) -> bool: return is_instance_valid(m) and not m.is_dead())
