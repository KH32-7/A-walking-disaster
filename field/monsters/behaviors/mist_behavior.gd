extends MonsterBehavior
## &"mist": translucent, seen only when a player is within MonsterRules.MIST_REVEAL_RANGE
## or for MonsterRules.MIST_FLASH_SEC after reveal() (flash, B-16). Hidden = the greybox
## Body and WeakPoint meshes are not drawn. It can still be hit while hidden.
## TODO(D-17): real visuals can listen to visibility_changed instead of the mesh toggle.

signal visibility_changed(revealed: bool)

var revealed := true
var _flash_left := 0.0


func on_added() -> void:
	_apply(false)


func on_tick(delta: float) -> void:
	_flash_left = maxf(_flash_left - delta, 0.0)
	_apply(_flash_left > 0.0 or _player_near())


## Flash item (B-16): shows the mist for `sec` seconds.
func reveal(sec: float = MonsterRules.MIST_FLASH_SEC) -> void:
	_flash_left = maxf(_flash_left, sec)
	_apply(true)


func _player_near() -> bool:
	if not monster.is_inside_tree():
		return false
	for node in monster.get_tree().get_nodes_in_group(Monster.PLAYER_GROUP):
		if node is Node3D and (node as Node3D).global_position.distance_to(monster.global_position) \
				<= MonsterRules.MIST_REVEAL_RANGE:
			return true
	return false


func _apply(show: bool) -> void:
	if show == revealed:
		return
	revealed = show
	for path in [^"Body", ^"WeakPoint/Core"]:
		var mesh := monster.get_node_or_null(path) as Node3D
		if mesh:
			mesh.visible = show
	visibility_changed.emit(show)
