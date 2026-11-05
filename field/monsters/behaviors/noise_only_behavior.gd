extends MonsterBehavior
## &"noise_only" (statue): moves only while there is noise. Once nothing was heard for
## MonsterRules.STATUE_QUIET_SEC it freezes (no moving, turning or attacking) until the
## next noise. Starts frozen. Statues are blind, so hearing is their only sense.

var quiet_time := INF


func on_tick(delta: float) -> void:
	quiet_time += delta


func on_heard(_point: Vector3, _source: Node) -> void:
	quiet_time = 0.0


func blocks_action() -> bool:
	return quiet_time > MonsterRules.STATUE_QUIET_SEC


func is_frozen() -> bool:
	return blocks_action()
