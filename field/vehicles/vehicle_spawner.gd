class_name VehicleSpawner
extends Node3D
## Puts vehicles on a share of the VehicleSpot markers each sortie (TUNING.spawn_ratio), plus the one
## brought from the base (FieldState.vehicle_uid). Field-found ones are broken with
## def.field_broken_chance (durability 0 until a mechanic fixes them), else full.
## Add one to a region scene; vehicles become its children. Design: 02 "탈것" (가안).

## Only VehicleSpots under this node are used. Empty = this node's parent.
@export var spots_root: NodePath
@export var spawn_on_ready := true

var spawned: Array[FieldVehicle] = []


func _ready() -> void:
	if spawn_on_ready:
		var rng := RandomNumberGenerator.new()
		# Own stream of the sortie seed, so vehicles do not shift the extraction draw.
		rng.seed = hash([FieldState.sortie_seed, &"vehicles"]) if FieldState.sortie_seed >= 0 else randi()
		# Deferred so markers later in the tree have joined their group.
		spawn.call_deferred(rng, FieldState.vehicle_uid)


## Clears earlier vehicles and places new ones. Same seed, same result.
func spawn(rng: RandomNumberGenerator, brought_uid: StringName = &"") -> Array[FieldVehicle]:
	for v in spawned:
		if is_instance_valid(v):
			v.queue_free()
	spawned.clear()
	var spots := _find_spots()
	var brought := Garage.def_of(brought_uid) if brought_uid != &"" else null
	var dock: VehicleSpot = null
	if brought != null and brought.surface == VehicleDef.Surface.WATER:
		dock = _first_spot(spots, VehicleDef.Surface.WATER)
		if dock != null:
			spots.erase(dock)
	_shuffle(spots, rng)
	for spot: VehicleSpot in spots.slice(0, roundi(spots.size() * FieldVehicle.TUNING.spawn_ratio)):
		var def := _pick_def(spot, rng)
		if def != null:
			var broken := rng.randf() < def.field_broken_chance
			_place(def, 0.0 if broken else def.max_durability, &"", spot.global_transform)
	if brought != null:
		_place(brought, Garage.durability(brought_uid), brought_uid, _brought_transform(brought, dock))
	# Left here on an earlier sortie: back where they stood (one chance, Garage).
	for uid in Garage.lost_in_region(FieldState.region_id):
		_place(Garage.def_of(uid), Garage.durability(uid), uid, Garage.lost_transform(uid))
	return spawned


func _place(def: VehicleDef, durability: float, uid: StringName, at: Transform3D) -> FieldVehicle:
	var v := FieldVehicle.new()
	v.setup(def, durability, uid)
	add_child(v)
	v.global_transform = at
	spawned.append(v)
	return v


## The spot's own list, else every vehicle of its surface. Sorted so the same seed picks the same.
func _pick_def(spot: VehicleSpot, rng: RandomNumberGenerator) -> VehicleDef:
	var ids: Array[StringName] = spot.vehicle_ids.duplicate()
	if ids.is_empty():
		for id: StringName in Garage.defs:
			if Garage.get_def(id).surface == spot.surface:
				ids.append(id)
	ids.sort()
	var picked := ids.filter(func(id: StringName) -> bool: return Garage.is_vehicle(id))
	return null if picked.is_empty() else Garage.get_def(picked[rng.randi_range(0, picked.size() - 1)])


## Land: beside the player's spawn. Water: the dock spot (the sortie screen only offers boats where
## the region has one).
func _brought_transform(def: VehicleDef, dock: VehicleSpot) -> Transform3D:
	if def.surface == VehicleDef.Surface.WATER:
		return dock.global_transform if dock != null else global_transform
	var spawn_point := get_tree().get_first_node_in_group(PlayerSpawn.GROUP) as Node3D
	if spawn_point == null:
		return global_transform
	var t := spawn_point.global_transform
	t.origin += t.basis.x.normalized() * FieldVehicle.TUNING.brought_offset_m
	return t


func _first_spot(spots: Array[VehicleSpot], surface: VehicleDef.Surface) -> VehicleSpot:
	var matching := spots.filter(func(s: VehicleSpot) -> bool: return s.surface == surface)
	matching.sort_custom(func(a: VehicleSpot, b: VehicleSpot) -> bool: return String(a.name) < String(b.name))
	return null if matching.is_empty() else matching[0]


func _find_spots() -> Array[VehicleSpot]:
	var root := get_node_or_null(spots_root) if not spots_root.is_empty() else get_parent()
	var out: Array[VehicleSpot] = []
	for node in get_tree().get_nodes_in_group(VehicleSpot.GROUP):
		if node is VehicleSpot and root and root.is_ancestor_of(node):
			out.append(node)
	out.sort_custom(func(a: VehicleSpot, b: VehicleSpot) -> bool: return String(a.name) < String(b.name))
	return out


## Fisher-Yates with the given rng (Array.shuffle() would ignore the seed).
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
