extends Node
## The player holds a gun model in the right hand (PlayerModel.GUNS): a gun weapon shows it at the
## hand bone with the barrel along the body's facing, the shot is drawn from its barrel tip, and a
## melee weapon puts it away. Skipped without the private assets/ (CI): no model, no gun.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const HAND := "mixamorig_RightHand"

var _ok := true
var _created: Array[StringName] = []
var _previous := {}


func run() -> bool:
	if not ResourceLoader.exists("res://assets/characters/hero/hero.fbx") \
			or not ResourceLoader.exists(PlayerModelGuns.path_of(&"rifle")):
		return true
	_ok = true
	for slot in [Enums.EquipSlot.MAIN, Enums.EquipSlot.SUB]:
		_previous[slot] = Armory.get_equipped(Armory.PLAYER_ID, slot)
	_equip(&"rifle", Enums.EquipSlot.MAIN)
	_equip(&"dagger", Enums.EquipSlot.SUB)
	var player := PLAYER_SCENE.instantiate() as Player
	add_child(player)
	player.set_physics_process(false)
	await _frames(4)
	var model := player.get_node(^"Model")
	var gun := model.get_node_or_null(^"HeldGun") as Node3D
	_expect(gun != null and gun.visible, "a rifle shows a gun model")
	if gun != null:
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(HAND)).origin
		var grip: Vector3 = gun.global_transform * (PlayerModelGuns.GUNS[&"rifle"]["grip"] as Vector3)
		_expect(grip.distance_to(hand) < 0.3, "the grip is in the right hand (%.2f m)" % grip.distance_to(hand))
		var facing := -player.global_basis.z
		_expect(gun.global_basis.x.normalized().dot(facing) > 0.9, "the barrel points where the body faces")
		var length := gun.global_basis.x.length() * PlayerModelGuns.length_units(&"rifle")
		var want: float = float(PlayerModelGuns.GUNS[&"rifle"]["length"]) * (model.get(&"model_scale") as float)
		_expect(absf(length - want) < 0.05, "the rifle is its data length x model scale (%.2f m, want %.2f)" % [length, want])
		var muzzle: Variant = model.call(&"muzzle_point", facing)
		_expect(muzzle is Vector3 and ((muzzle as Vector3) - grip).dot(facing) > 0.2,
			"shots are drawn from the barrel tip, ahead of the grip")
	var weapons := player.get_node(^"Weapons") as WeaponHolder
	weapons.switch_to(Enums.EquipSlot.SUB)
	await _frames(2)
	_expect(model.get_node_or_null(^"HeldGun") == null, "a melee weapon puts the gun away")
	player.queue_free()
	for uid in _created:
		Armory.remove_item(uid)
	for slot: Enums.EquipSlot in _previous:
		if _previous[slot] != &"":
			Armory.equip(Armory.PLAYER_ID, slot, _previous[slot])
	return _ok


func _equip(def_id: StringName, slot: Enums.EquipSlot) -> void:
	var uid := Armory.create_item(def_id, Enums.Rarity.COMMON)
	_created.append(uid)
	Armory.equip(Armory.PLAYER_ID, slot, uid)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _expect(cond: bool, label: String) -> void:
	if not cond:
		_ok = false
		push_error("test_player_gun: " + label)
