class_name MagicZone
extends Node3D
## Ground zone a "hit" combo leaves at the target (B-15): thorn bush (가시 덤불, damage per second +
## slow) and swamp (늪, slow). Living monsters inside get the slow, refreshed every SLOW_REFRESH_SEC
## so it ends soon after they walk out. Damage is dealt once a second as flat tick damage
## (take_damage info "status_tick" = combo id: no defense, element factor or reaction, like bleed).
## Lane D: Fx.spawn(&"essence_combo", position, {"id", "radius", "duration"}) when it appears.
## Design reference: docs/design/06-magic-essence.md "조합 마법"

const TICK_SEC := 1.0
const SLOW_REFRESH_SEC := 0.25
const EPS := 0.0001

var combo_id: StringName
var radius := 1.0
var duration := 1.0
var dps := 0.0
## Slow move multiplier inside (1 - slow_ratio). 1 = no slow.
var move_mult := 1.0
var element: Enums.Element = Enums.Element.NONE

var _left := 0.0
var _tick_left := TICK_SEC
var _slow_left := 0.0


## Adds a zone for `combo` (get_item_stats().combo) under `parent` at `pos`. Null for combos that
## leave no zone. The zone steps itself; tests may set_physics_process(false) and call step().
static func create(parent: Node, pos: Vector3, combo: Dictionary, zone_element: Enums.Element) -> MagicZone:
	var p: Dictionary = combo.get("params", {})
	if not p.has("zone_sec") or parent == null:
		return null
	var zone := MagicZone.new()
	zone.name = "MagicZone_%s" % combo.get("id", &"")
	zone.combo_id = combo.get("id", &"")
	zone.radius = float(p.get("zone_radius", 1.0))
	zone.duration = float(p["zone_sec"])
	zone.dps = float(p.get("dps", 0.0))
	zone.move_mult = clampf(1.0 - float(p.get("slow_ratio", 0.0)), 0.0, 1.0)
	zone.element = zone_element
	zone._left = zone.duration
	parent.add_child(zone)
	zone.global_position = pos
	Fx.spawn(&"essence_combo", pos, {"id": zone.combo_id, "radius": zone.radius, "duration": zone.duration})
	return zone


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	_left -= delta
	_slow_left -= delta
	var inside := SkillTargets.monsters_in_radius(self, global_position, radius)
	if move_mult < 1.0 and _slow_left <= EPS:
		_slow_left += SLOW_REFRESH_SEC
		for monster in inside:
			monster.status.apply(&"slow", {"duration": SLOW_REFRESH_SEC + EPS, "move_mult": move_mult})
	if dps > 0.0:
		_tick_left -= delta
		if _tick_left <= EPS and _left > -EPS:
			_tick_left += TICK_SEC
			for monster in inside:
				monster.take_damage(dps * TICK_SEC, {"status_tick": combo_id, "element": element})
	if _left <= EPS:
		queue_free()
		set_physics_process(false)


func time_left() -> float:
	return maxf(_left, 0.0)
