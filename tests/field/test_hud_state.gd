extends Node
## Issue #28: Player.hud_state() gives the field HUD (D-04) hp, stamina, weapons, compass
## markers for active extraction points, the interact prompt and the hold bar.

const PLAYER_SCENE := preload("res://field/player/player.tscn")
const CONTAINER_SCENE := preload("res://field/loot/loot_container.tscn")

var _ok := true
var _made: Array[StringName] = []


func run() -> bool:
	_ok = true
	var p: Player = PLAYER_SCENE.instantiate()
	add_child(p)
	_equip(Enums.EquipSlot.MAIN, &"pistol")
	_equip(Enums.EquipSlot.SUB, &"dagger")

	var s := p.hud_state()
	_expect(s.get("hp") == p.health and s.get("hp_max") == p.stats.max_health, "hp and hp_max")
	_expect(is_equal_approx(s.get("stamina", -1.0), 1.0), "full stamina is 1.0")
	var weapons: Array = s.get("weapons", [])
	_expect(weapons.size() == 2, "two weapons listed")
	if weapons.size() == 2:
		_expect(weapons[0].get("name") == Armory.get_def(&"pistol").name, "weapon name from ItemDef")
		_expect(weapons[0].get("melee") == false and weapons[0].has("ammo"), "active gun shows ammo")
		_expect(weapons[1].get("melee") == true, "dagger is melee")
	_expect(s.get("weapon_index") == 0, "MAIN is active")
	_expect(s.get("prompt") == {} and s.get("hold") == {}, "nothing to interact with")

	var c: LootContainer = CONTAINER_SCENE.instantiate()
	c.def = load("res://data/loot/containers/medicine.tres")
	c.loot_table = load("res://data/loot/tables/flooded_mall_medicine.tres")
	c.position = Vector3(0.0, 0.0, -1.0)
	add_child(c)
	for i in 3:
		await get_tree().physics_frame
	s = p.hud_state()
	_expect(s.get("prompt") == {"key": "F", "label": "약품장 뒤지기"}, "prompt names the container")
	p.interact()
	s = p.hud_state()
	_expect(s.get("hold", {}).get("label") == "약품장 뒤지는 중", "hold bar while opening")
	_expect(s.get("prompt") == {}, "no prompt while holding")

	var point := ExtractPoint.new()
	point.id = &"ex_hud"
	point.position = Vector3(0.0, 0.0, -30.0)
	add_child(point)
	var manager := ExtractionManager.new()
	manager.auto_activate = false
	add_child(manager)
	manager.activate(1)
	s = p.hud_state()
	var markers: Array = s.get("compass_markers", [])
	_expect(markers.size() == 1 and markers[0].get("kind") == &"extract", "extract marker")
	if markers.size() == 1:
		_expect(is_equal_approx(markers[0].get("bearing"), 0.0), "point straight north is bearing 0")
		_expect(is_equal_approx(markers[0].get("dist"), 30.0), "distance on the ground")

	manager.free()
	point.free()
	c.free()
	p.free()
	for uid in _made:
		Armory.unequip(Armory.PLAYER_ID, Armory.get_item(uid).slot)
		Armory.remove_item(uid)
	return _ok


func _equip(slot: Enums.EquipSlot, def_id: StringName) -> void:
	var previous := Armory.get_equipped(Armory.PLAYER_ID, slot)
	if previous != &"":
		Armory.unequip(Armory.PLAYER_ID, slot)
	var uid := Armory.create_item(def_id, Enums.Rarity.COMMON)
	Armory.equip(Armory.PLAYER_ID, slot, uid)
	_made.append(uid)


func _expect(cond: bool, what: String) -> void:
	if not cond:
		push_error("test_hud_state: %s" % what)
		_ok = false
