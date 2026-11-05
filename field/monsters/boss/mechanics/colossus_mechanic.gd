extends BossMechanic
## 네온 거신 (docs/design/04-monsters.md "보스"): billboard laser, shock floor, neon moth summons, and three power
## cables. Cut all three and it shuts down (stands still, takes more damage), then the cables come back.
## - Laser: a common red line pattern (data). Shock floor (action &"shock_floor"): params.count red circles on
##   and around you; when they land they hit once and stay as live floor for params.zone_sec (shock status).
## - Cables (PowerCable children behind and beside it): CABLE_HP each, hit from behind or the sides. The
##   front faces you, so cutting them means getting round it.
## Numbers: pattern params in data/monsters/bosses/neon_colossus.tres, cable rules below. All drafts.

## Attacker-side damage one cable takes before it is cut (element factor applies, green beats neon).
const CABLE_HP := 150.0
## Seconds it stays shut down once the last cable is cut.
const STUN_SEC := 6.0
## Damage it takes while shut down, x this.
const STUN_DAMAGE_MULT := 1.5
## Live floor re-applies the shock status this often to whoever stands on it.
const ZONE_TICK_SEC := 0.5

const FLOOR_FX := &"boss_shock_floor"
const CUT_FX := &"boss_cable_cut"
const OVERLOAD_FX := &"boss_overload"

var cables: Array[PowerCable] = []
var stunned_left := 0.0

var _cable_hp: Dictionary = {}  # PowerCable -> hp left
var _circles: Array[Dictionary] = []
## {"area": Dictionary, "left": float, "tick": float}
var _zones: Array[Dictionary] = []


func on_added() -> void:
	for child in boss.get_children():
		var cable := child as PowerCable
		if cable == null:
			continue
		cables.append(cable)
		boss.add_collision_exception_with(cable)
		cable.hit.connect(_on_cable_hit)
	_restore_cables()


func on_tick(delta: float) -> void:
	if stunned_left > 0.0:
		stunned_left -= delta
		boss.velocity = Vector3.ZERO
		if stunned_left <= 0.0:
			_restore_cables()
	for i in range(_zones.size() - 1, -1, -1):
		var zone: Dictionary = _zones[i]
		zone["left"] -= delta
		zone["tick"] -= delta
		if zone["tick"] <= 0.0:
			zone["tick"] = ZONE_TICK_SEC
			for body in boss.area_targets(zone["area"]):
				var holder := body.get_node_or_null(NodePath(StatusHolder.NODE_NAME)) as StatusHolder
				if holder:
					holder.apply(&"shock")
		if zone["left"] <= 0.0:
			_zones.remove_at(i)


func can_use(_pattern: BossPattern) -> bool:
	return stunned_left <= 0.0


func on_pattern_started(pattern: BossPattern, area: Dictionary) -> void:
	if pattern.action != &"shock_floor" or area.is_empty():
		return
	_circles = [area]
	var count := int(pattern.params.get("count", 3))
	var spread := float(pattern.params.get("spread", 4.0))
	var turn := randf() * TAU
	for i in count - 1:
		var extra := area.duplicate()
		var a := turn + TAU * i / maxf(count - 1, 1)
		extra["position"] = area["position"] + Vector3(cos(a), 0.0, sin(a)) * spread
		_circles.append(extra)
		boss.telegraph_started.emit(extra)
		Fx.spawn(BossMonster.FX_TELEGRAPH, extra["position"], extra)


func land_pattern(pattern: BossPattern, _area: Dictionary) -> bool:
	if pattern.action != &"shock_floor":
		return false
	var zone_sec := float(pattern.params.get("zone_sec", 4.0))
	var hit: Array[Node3D] = []
	for circle in _circles:
		var fx := circle.duplicate()
		fx["element"] = boss.def.family
		fx["duration"] = zone_sec
		Fx.spawn(FLOOR_FX, circle["position"], fx)
		_zones.append({"area": circle, "left": zone_sec, "tick": ZONE_TICK_SEC})
		for body in boss.area_targets(circle):
			if not hit.has(body):
				hit.append(body)
	var info := {"source": boss, "element": boss.def.family, "monster_id": boss.def.id, "pattern_id": pattern.id}
	if not pattern.status.is_empty():
		info["status"] = pattern.status.duplicate(true)
	var amount := boss.attack_damage() * pattern.damage_mult
	for body in hit:
		body.take_damage(amount, info.duplicate(true))
		boss.attack_landed.emit(body, info)
	_circles.clear()
	return true


func filter_damage(amount: float, _info: Dictionary) -> float:
	return amount * STUN_DAMAGE_MULT if stunned_left > 0.0 else amount


func on_reset() -> void:
	stunned_left = 0.0
	_zones.clear()
	_restore_cables()


func on_died() -> void:
	_zones.clear()


func is_stunned() -> bool:
	return stunned_left > 0.0


func cable_hp(cable: PowerCable) -> float:
	return float(_cable_hp.get(cable, 0.0))


# --- Cables ---------------------------------------------------------------

func _on_cable_hit(cable: PowerCable, amount: float, info: Dictionary) -> void:
	if boss.is_dead() or cable.cut:
		return
	var element: Enums.Element = info.get("element", Enums.Element.NONE)
	var left := cable_hp(cable) - amount * Enums.element_multiplier(element, boss.def.family)
	_cable_hp[cable] = left
	if left > 0.0:
		return
	cable.set_cut(true)
	Fx.spawn(CUT_FX, cable.global_position, {"element": boss.def.family})
	for c in cables:
		if not c.cut:
			return
	_shut_down()


## All three cut: it stops mid-pattern and stands for STUN_SEC.
func _shut_down() -> void:
	stunned_left = STUN_SEC
	boss.cancel_cast()
	boss.hold(STUN_SEC)
	Fx.spawn(OVERLOAD_FX, boss.global_position, {"element": boss.def.family})
	var visual := boss.get_node_or_null(^"Visual") as MonsterVisual
	if visual:
		visual.play_once(&"Hit")


func _restore_cables() -> void:
	for cable in cables:
		_cable_hp[cable] = CABLE_HP
		cable.set_cut(false)
