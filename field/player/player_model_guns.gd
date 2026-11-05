class_name PlayerModelGuns
extends RefCounted
## Gun models the player holds in the right hand (PlayerModel): Quaternius Ultimate Gun Pack (CC0)
## under res://assets/weapons/quaternius_guns/. Per gun item id: the model file, its drawn length (m,
## before PlayerModel.model_scale; about 2/3 of real life so it doesn't swamp the 1.3x hero, user
## feedback 2026-11-06), and in the model's own units (barrel along +X, up +Y) the grip
## the hand closes on and the barrel tip. Gun items not listed here use FALLBACK.

const DIR := "res://assets/weapons/quaternius_guns/"
const FALLBACK := &"rifle"
const GUNS := {
	&"pistol": {"file": "pistol_1", "length": 0.2, "grip": Vector3(-0.08, 0.05, 0.0), "muzzle": Vector3(1.48, 0.56, 0.0)},
	&"rifle": {"file": "assault_rifle_1", "length": 0.6, "grip": Vector3(0.78, 0.2, 0.0), "muzzle": Vector3(2.92, 0.65, 0.0)},
	&"shotgun": {"file": "shotgun_1", "length": 0.68, "grip": Vector3(0.0, -0.05, 0.0), "muzzle": Vector3(3.8, 0.2, 0.0)},
	&"smg": {"file": "submachine_gun_1", "length": 0.4, "grip": Vector3(0.05, 0.2, 0.0), "muzzle": Vector3(2.27, 0.62, 0.0)},
	&"sniper_rifle": {"file": "sniper_rifle_1", "length": 0.8, "grip": Vector3(-0.2, 0.1, 0.0), "muzzle": Vector3(5.25, 0.3, 0.0)},
}
## Where the grip sits from the hand bone (the wrist), in metres before model_scale: a little ahead
## along the barrel and down into the palm.
const HOLD_AHEAD := 0.06
const HOLD_DROP := 0.03

static var _units := {}  # gun id -> model length along +X in its own units


## The gun id to show for an item def (FALLBACK for an unlisted gun).
static func id_for(def_id: StringName) -> StringName:
	return def_id if GUNS.has(def_id) else FALLBACK


static func path_of(id: StringName) -> String:
	return DIR + String(GUNS[id]["file"]) + ".fbx"


## The model scene, or null when assets/ is missing.
static func scene_of(id: StringName) -> PackedScene:
	var path := path_of(id)
	return load(path) as PackedScene if ResourceLoader.exists(path) else null


## The model's length along +X in its own units (1.0 when it can't be loaded).
static func length_units(id: StringName) -> float:
	if _units.has(id):
		return _units[id]
	var scene := scene_of(id)
	var out := 1.0
	if scene != null:
		var root := scene.instantiate() as Node3D
		var lo := INF
		var hi := -INF
		for node in root.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var xf := mi.transform
			var p := mi.get_parent()
			while p != root and p is Node3D:
				xf = (p as Node3D).transform * xf
				p = p.get_parent()
			var box := xf * mi.get_aabb()
			lo = minf(lo, box.position.x)
			hi = maxf(hi, box.end.x)
		root.free()
		if hi > lo:
			out = hi - lo
	_units[id] = out
	return out
