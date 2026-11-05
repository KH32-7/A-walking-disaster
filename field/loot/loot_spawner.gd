class_name LootSpawner
extends Node3D
## Puts loot containers on a random part of the LootSpot markers each sortie (B-08).
## Add one to a region layout. Containers become children of this node.
## Design: docs/design/02-field.md "맵 구조" (루팅 상자는 출격마다 바뀝니다)

const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")

## Region whose loot tables apply when a LootSpot has no loot_table_id.
@export var region_id: StringName = &"flooded_mall"
## Share of LootSpots that get a container each sortie (가안, tune with B-12).
@export_range(0.0, 1.0, 0.05) var spawn_ratio: float = 0.6
## Only LootSpots under this node are used. Empty = this node's parent.
@export var spots_root: NodePath
@export var spawn_on_ready := true

var spawned: Array[LootContainer] = []


func _ready() -> void:
	if spawn_on_ready:
		# Deferred so LootSpot markers later in the tree have joined their group.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		spawn.call_deferred(rng)


## Clears earlier containers and places new ones. Same seed, same result.
func spawn(rng: RandomNumberGenerator) -> Array[LootContainer]:
	for c in spawned:
		if is_instance_valid(c):
			c.queue_free()
	spawned.clear()
	var spots := _find_spots()
	var count := roundi(spots.size() * spawn_ratio)
	if spawn_ratio > 0.0:
		count = maxi(count, mini(1, spots.size()))
	_shuffle(spots, rng)
	for i in count:
		var c := _make_container(spots[i], rng)
		if c:
			spawned.append(c)
	return spawned


func _make_container(spot: LootSpot, rng: RandomNumberGenerator) -> LootContainer:
	var def := LootData.container_def(spot.container_type)
	if def == null:
		push_warning("LootSpawner: no container def for %s" % LootSpot.ContainerType.keys()[spot.container_type])
		return null
	var c: LootContainer = CONTAINER_SCENE.instantiate()
	c.def = def
	c.loot_table = LootData.resolve_table(spot.loot_table_id, region_id, spot.container_type)
	if c.loot_table == null:
		push_warning("LootSpawner: no loot table for %s" % spot.get_path())
	add_child(c)
	c.global_transform = spot.global_transform
	c.roll_contents(rng)
	return c


func _find_spots() -> Array[LootSpot]:
	var root := get_node_or_null(spots_root) if not spots_root.is_empty() else get_parent()
	var out: Array[LootSpot] = []
	for node in get_tree().get_nodes_in_group(LootSpot.GROUP):
		if node is LootSpot and root and root.is_ancestor_of(node):
			out.append(node)
	return out


## Fisher-Yates with the given rng (Array.shuffle() would ignore the seed).
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
