class_name HitFeedback
extends Node
## Hit feel that gameplay does not have to call (D-18). Owner: Lane D. Child of the Fx autoload.
## - Monsters in group "field_monsters" with `damaged(amount, info)` (B-07): damage number at the hit
##   point (info.position, else above the monster), white hit flash. Status ticks (info.status_tick):
##   small number in the element colour, no flash.
## - The player in group "player" with `health_changed(current, maximum)` (B-03): a drop shows a red
##   "-N", a red flash and the `player_hurt` sound; a rise (bandage, photosynthesis) shows a green "+N".
## Amounts are B's (already after weak point, element and defence); D computes nothing.
## Sparks and the hit sound come from B's own `Fx.spawn(&"hit_spark", ...)` call.

const SCAN_SEC := 0.25
const NUMBER_HEIGHT := 1.6
const PLAYER_FLASH := Color(1.0, 0.42, 0.36)
const MONSTER_FLASH := Color(1.0, 1.0, 1.0)
const PLAYER_GROUP := &"player"
const MONSTER_GROUP := &"field_monsters"

var _watched: Dictionary = {}  # instance_id -> true
var _player_hp: Dictionary = {}  # instance_id -> last health
var _scan_t := 0.0


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = SCAN_SEC
	scan()


## Connects to any new monster / player. Called every SCAN_SEC; tests call it directly.
func scan() -> void:
	for m in get_tree().get_nodes_in_group(MONSTER_GROUP):
		_watch(m, &"damaged", _on_monster_damaged.bind(m))
	for p in get_tree().get_nodes_in_group(PLAYER_GROUP):
		if not _watched.has(p.get_instance_id()) and &"health" in p:
			_player_hp[p.get_instance_id()] = float(p.get(&"health"))
		_watch(p, &"health_changed", _on_player_health.bind(p))


func _watch(node: Node, sig: StringName, callable: Callable) -> void:
	var id := node.get_instance_id()
	if _watched.has(id) or not node.has_signal(sig):
		return
	_watched[id] = true
	node.connect(sig, callable)
	node.tree_exiting.connect(func() -> void:
		_watched.erase(id)
		_player_hp.erase(id), CONNECT_ONE_SHOT)


func _on_monster_damaged(amount: float, info: Dictionary, monster: Node) -> void:
	if amount <= 0.0 or not is_instance_valid(monster) or not monster is Node3D:
		return
	var tick := info.has("status_tick")
	var at: Vector3 = info.get("position", (monster as Node3D).global_position + Vector3.UP * NUMBER_HEIGHT)
	Fx.spawn(&"damage_number", at, {
		"amount": amount, "kind": &"tick" if tick else &"hit", "crit": info.get("crit", false),
		"weak_point": info.get("weak_point", false), "element": info.get("element", Enums.Element.NONE)})
	if not tick:
		HitFlash.flash(monster, MONSTER_FLASH)


func _on_player_health(current: float, _maximum: float, player: Node) -> void:
	var id := player.get_instance_id()
	var before: float = _player_hp.get(id, current)
	_player_hp[id] = current
	var diff := current - before
	if absf(diff) < 0.05 or not player is Node3D:
		return
	var at := (player as Node3D).global_position + Vector3.UP * NUMBER_HEIGHT
	if diff < 0.0:
		Fx.spawn(&"damage_number", at, {"amount": -diff, "kind": &"player"})
		HitFlash.flash(player, PLAYER_FLASH)
		Audio.play(&"player_hurt", (player as Node3D).global_position)
	else:
		Fx.spawn(&"damage_number", at, {"amount": diff, "kind": &"heal"})
