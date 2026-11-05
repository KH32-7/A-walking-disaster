extends Node
## Sandbox-only weapon helper (B-06). Add as a child of a sandbox scene that has a Player.
## Keys (raw keycodes, not project actions):
##   F1..F6: put pistol, rifle, dagger, machete, club, pipe_wrench in the MAIN slot
##   F7: +30 of the active gun's ammo into the Bag
## Console (` key): `weapon <def_id> [main|sub] [rarity 0-4]`, `ammo <ammo_id> <count>`
## Also points the player's aim at the mouse on the ground plane.
## TODO(B-04): drop the mouse aim here once the field camera calls Player.set_aim_point().

const HOTKEY_WEAPONS := {
	KEY_F1: &"pistol",
	KEY_F2: &"rifle",
	KEY_F3: &"dagger",
	KEY_F4: &"machete",
	KEY_F5: &"club",
	KEY_F6: &"pipe_wrench",
}
const AMMO_KEY := KEY_F7
const AMMO_PER_PRESS := 30
const LABEL_POSITION := Vector2(16, 360)

var _player: Player
var _holder: WeaponHolder
var _label: Label
## def_id -> item uid made by this helper, reused on the next press.
var _made: Dictionary = {}
var _last_hit := "-"


func _ready() -> void:
	_player = get_tree().get_first_node_in_group(Player.GROUP) as Player
	if _player == null:
		push_error("weapon_debug: no Player in the scene")
		return
	_holder = _player.get_node(^"Weapons")
	_holder.hit_landed.connect(_on_hit)
	_holder.blocked.connect(func(perfect: bool) -> void:
		_last_hit = "perfect block" if perfect else "blocked")
	_holder.guard_broken.connect(func() -> void: _last_hit = "guard broken")
	_label = Label.new()
	_label.position = LABEL_POSITION
	add_child(_label)
	DebugConsole.register(&"weapon", _cmd_weapon, "weapon <def_id> [main|sub] [rarity 0-4]")
	DebugConsole.register(&"ammo", _cmd_ammo, "ammo <ammo_id> <count>")


func _process(_delta: float) -> void:
	if _player == null:
		return
	_aim_at_mouse()
	var stats := _holder.current_stats()
	var ammo := "-"
	if WeaponHolder.is_gun(stats):
		var reserve := _holder.ammo_reserve()
		ammo = "%d / %s%s" % [_holder.ammo_in_magazine(), "inf" if reserve < 0 else str(reserve),
			"  reloading" if _holder.is_reloading else ""]
	_label.text = "\n".join([
		"Weapon: %s (%s)  Ammo: %s" % [stats.get("def_id", "none"),
			Enums.EquipSlot.keys()[_holder.active_slot], ammo],
		"Spread: %.1f deg  Combo: %d  Blocking: %s  Stunned: %s" % [
			_holder.current_spread_deg() if WeaponHolder.is_gun(stats) else 0.0,
			_holder.combo_step, _holder.is_blocking, _holder.is_stunned()],
		"Last hit: %s" % _last_hit,
		"LMB attack, RMB aim/block, R reload, 1/2 swap, F1-F6 weapons, F7 ammo",
	])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if HOTKEY_WEAPONS.has(key.keycode):
		_equip(HOTKEY_WEAPONS[key.keycode], Enums.EquipSlot.MAIN, -1)
		_holder.switch_to(Enums.EquipSlot.MAIN)
	elif key.keycode == AMMO_KEY:
		var ammo_id := StringName(_holder.current_stats().get("ammo_id", &""))
		if ammo_id != &"":
			_add_ammo(ammo_id, AMMO_PER_PRESS)


func _cmd_weapon(args: PackedStringArray) -> String:
	if args.is_empty() or Armory.get_def(StringName(args[0])) == null:
		return "사용법: weapon <def_id> [main|sub] [rarity 0-4]"
	var slot := Enums.EquipSlot.SUB if args.size() > 1 and args[1] == "sub" else Enums.EquipSlot.MAIN
	var rarity := args[2].to_int() if args.size() > 2 and args[2].is_valid_int() else -1
	if not _equip(StringName(args[0]), slot, rarity):
		return "장착 실패: %s (보조 칸은 경량 무기만)" % args[0]
	_holder.switch_to(slot)
	return "%s 장착 (%s)" % [args[0], Enums.EquipSlot.keys()[slot]]


func _cmd_ammo(args: PackedStringArray) -> String:
	if args.size() != 2 or not args[1].is_valid_int():
		return "사용법: ammo <ammo_id> <count>"
	return "가방에 %d개 넣음" % _add_ammo(StringName(args[0]), args[1].to_int())


func _equip(def_id: StringName, slot: Enums.EquipSlot, rarity: int) -> bool:
	var uid: StringName = _made.get(def_id, &"")
	if uid == &"" or not Armory.has_item(uid) or rarity >= 0:
		uid = Armory.create_item(def_id, rarity)
		_made[def_id] = uid
	return Armory.equip(Armory.PLAYER_ID, slot, uid)


func _add_ammo(ammo_id: StringName, count: int) -> int:
	if Bag.grid_size == Vector2i.ZERO:
		Bag.resize_for_player()
	return count - Bag.add_resource(ammo_id, count)


func _aim_at_mouse() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var hit: Variant = Plane(Vector3.UP, _player.global_position.y).intersects_ray(
			camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if hit != null:
		_player.set_aim_point(hit)


func _on_hit(target: Node, amount: float, info: Dictionary) -> void:
	var tags: PackedStringArray = []
	for tag in ["crit", "backstab", "cover"]:
		if info.get(tag, false):
			tags.append(tag)
	if target is MonsterWeakPoint:
		tags.append("weak point")
	_last_hit = "%s %.1f %s" % [target.name, amount, " ".join(tags)]
