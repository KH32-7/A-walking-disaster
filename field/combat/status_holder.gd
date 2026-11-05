class_name StatusHolder
extends Node
## Status effects on one body (B-14): the player, a monster or a rescued person.
## The body creates it with `@onready var status := StatusHolder.attach(self)` (child "Status"),
## calls step(delta) from its own step/tick, and reads the queries below for movement and actions.
##
## Hits carry effects in take_damage(amount, info):
##   info["status"] = [{"id": &"bleed"}, {"id": &"stagger", "duration": 1.5}, ...]
##   Entry keys: "id" (required), "stacks" (default 1), "duration" (seconds, default the def's),
##   "stacks_max" (raises the cap, e.g. blade mastery 10 bleed x2), "dir" (knockback, Vector3).
##   Knockback without "dir" pushes away from info["source"], else from info["position"].
##   Legacy info["bind_sec"] (vine tendril, B-07) is the same as {"id": &"bind", "duration": bind_sec}.
## Tick damage comes back to the body as take_damage(amount, {"status_tick": id, "element": e}).
## Bodies treat such hits as flat: no block, defense, part or element factor, no new statuses.
## Rules: re-applying adds stacks up to the cap and keeps the longer remaining time.
## Design reference: docs/design/03-combat-classes.md "피해 공식" 상태 이상 표, 06-magic-essence.md

## New effect, or more stacks / longer time on one already active (Lane D: icons over heads, HUD).
signal status_applied(id: StringName, stacks: int, time_left: float)
## Ran out, removed (bandage) or cleared (downed).
signal status_removed(id: StringName)

const DIR := "res://data/classes/status/"
const NODE_NAME := &"Status"
## Tick damage is dealt in steps this long (03: "초당 3 피해" = 3 every second).
const TICK_SEC := 1.0
const EPS := 0.0001

static var _defs: Dictionary = {}

## id -> {"def": StatusEffect, "stacks": int, "time_left": float, "tick_left": float, "dir": Vector3}
var _active: Dictionary = {}


## Creates the holder as a child of `body`. Call it from body's @onready or _ready.
static func attach(body: Node) -> StatusHolder:
	var holder := StatusHolder.new()
	holder.name = NODE_NAME
	body.add_child(holder)
	return holder


## data/classes/status/<id>.tres, or null.
static func get_def(id: StringName) -> StatusEffect:
	if not _defs.has(id):
		var path := DIR + String(id) + ".tres"
		_defs[id] = load(path) as StatusEffect if ResourceLoader.exists(path) else null
	return _defs[id]


## True for tick damage that came from a StatusHolder.
static func is_tick(info: Dictionary) -> bool:
	return info.has("status_tick")


func _ready() -> void:
	# The body drives step() so tests can step it with a fixed delta.
	set_process(false)
	set_physics_process(false)


# --- Applying ---------------------------------------------------------------

## Applies every effect a hit carries (info["status"], legacy info["bind_sec"]).
func apply_hit(info: Dictionary) -> void:
	if is_tick(info):
		return
	var bind_sec: float = info.get("bind_sec", 0.0)
	if bind_sec > 0.0:
		apply(&"bind", {"duration": bind_sec})
	for entry: Dictionary in info.get("status", []):
		var id: StringName = entry.get("id", &"")
		var opts := entry.duplicate()
		var def := get_def(id)
		if def != null and def.knockback_m > 0.0 and not opts.has("dir"):
			opts["dir"] = _away_from(info)
		apply(id, opts)


## Applies one effect. opts: "stacks", "duration", "stacks_max", "dir" (see the header).
## Returns false for an unknown id.
func apply(id: StringName, opts: Dictionary = {}) -> bool:
	var def := get_def(id)
	if def == null:
		push_warning("StatusHolder: unknown status %s" % id)
		return false
	var duration: float = opts.get("duration", def.duration_sec)
	var cap := maxi(def.stacks_max, int(opts.get("stacks_max", def.stacks_max)))
	var add := int(opts.get("stacks", 1))
	var e: Dictionary = _active.get(id, {"def": def, "stacks": 0, "time_left": 0.0, "tick_left": TICK_SEC})
	e["stacks"] = clampi(e["stacks"] + add, 1, maxi(cap, e["stacks"]))
	e["time_left"] = maxf(e["time_left"], duration)
	if def.knockback_m > 0.0:
		var dir: Vector3 = opts.get("dir", Vector3.ZERO)
		dir.y = 0.0
		e["dir"] = dir.normalized() if dir.length_squared() > EPS else _backward()
		e["time_left"] = duration
		e["speed"] = def.knockback_m / maxf(duration, EPS)
	_active[id] = e
	status_applied.emit(id, e["stacks"], e["time_left"])
	return true


## Removes one effect (bandage: bleed). Returns false when it was not active.
func remove(id: StringName) -> bool:
	if not _active.erase(id):
		return false
	status_removed.emit(id)
	return true


## Removes everything (downed, revived).
func clear() -> void:
	for id: StringName in _active.keys():
		remove(id)


## Advances timers and deals tick damage to the parent body.
func step(delta: float) -> void:
	if _active.is_empty():
		return
	var ticks: Array = []
	for id: StringName in _active.keys():
		var e: Dictionary = _active[id]
		var def: StatusEffect = e["def"]
		e["time_left"] -= delta
		if def.tick_damage > 0.0:
			e["tick_left"] -= delta
			# A tick counts only if it fell inside the duration (time_left - tick_left = time left then).
			while e["tick_left"] <= EPS and e["time_left"] - e["tick_left"] > -EPS:
				e["tick_left"] += TICK_SEC
				ticks.append([id, def.tick_damage * TICK_SEC * e["stacks"], def.element])
	for id: StringName in _active.keys():
		if _active[id]["time_left"] <= EPS:
			remove(id)
	# Damage last: it can down the body, which clears this holder.
	var body := get_parent()
	for t: Array in ticks:
		if body != null and body.has_method("take_damage"):
			var amount: float = t[1] * damage_taken_mult(t[2])
			body.take_damage(amount, {"status_tick": t[0], "element": t[2]})


# --- Queries ----------------------------------------------------------------

func has(id: StringName) -> bool:
	return _active.has(id)


func stacks(id: StringName) -> int:
	return _active[id]["stacks"] if _active.has(id) else 0


func time_left(id: StringName) -> float:
	return maxf(_active[id]["time_left"], 0.0) if _active.has(id) else 0.0


## Lane D: [{"id", "stacks", "time_left", "duration_sec"}] for every active effect.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in _active:
		var e: Dictionary = _active[id]
		out.append({"id": id, "stacks": e["stacks"], "time_left": maxf(e["time_left"], 0.0),
				"duration_sec": (e["def"] as StatusEffect).duration_sec})
	return out


## Product of every active move_mult. 0 while bound, staggered or pushed.
func move_mult() -> float:
	var mult := 1.0
	for e: Dictionary in _active.values():
		var def: StatusEffect = e["def"]
		mult *= 0.0 if def.stops_actions else def.move_mult
	return mult


func can_move() -> bool:
	return move_mult() > 0.0


## False while staggered or knocked back: no attacking, turning or dodging either.
func can_act() -> bool:
	for e: Dictionary in _active.values():
		if (e["def"] as StatusEffect).stops_actions:
			return false
	return true


## Multiplier for the target's defense R (armor break 0.5).
func defense_mult() -> float:
	var mult := 1.0
	for e: Dictionary in _active.values():
		mult *= (e["def"] as StatusEffect).defense_mult
	return mult


## Extra factor for damage of `element` (wet: LIGHT x1.25).
func damage_taken_mult(element: Enums.Element) -> float:
	var mult := 1.0
	if element == Enums.Element.NONE:
		return mult
	for e: Dictionary in _active.values():
		var def: StatusEffect = e["def"]
		if def.vulnerable_element == element:
			mult *= def.vulnerable_mult
	return mult


## Product of every active damage_mult (painkiller 0.8). Applies to hits and ticks alike.
func damage_mult() -> float:
	var mult := 1.0
	for e: Dictionary in _active.values():
		mult *= (e["def"] as StatusEffect).damage_mult
	return mult


## Product of every active sight_mult. 0 while blinded (flash).
func sight_mult() -> float:
	var mult := 1.0
	for e: Dictionary in _active.values():
		mult *= (e["def"] as StatusEffect).sight_mult
	return mult


## Hit damage after status factors (wet, painkiller). Tick damage only gets damage_mult().
func scale_damage(amount: float, info: Dictionary) -> float:
	if is_tick(info):
		return amount * damage_mult()
	return amount * damage_mult() * damage_taken_mult(info.get("element", Enums.Element.NONE))


## Flat push velocity while knocked back, else Vector3.ZERO.
func knockback_velocity() -> Vector3:
	for e: Dictionary in _active.values():
		if e.has("dir"):
			return e["dir"] * e["speed"]
	return Vector3.ZERO


## For bodies that set their velocity from scratch every tick (monsters, rescued people):
## scales x/z by move_mult(), or replaces them with the knockback push.
func steer(velocity: Vector3) -> Vector3:
	var push := knockback_velocity()
	if push != Vector3.ZERO:
		return Vector3(push.x, velocity.y, push.z)
	var mult := move_mult()
	return Vector3(velocity.x * mult, velocity.y, velocity.z * mult)


# --- Helpers ------------------------------------------------------------------

func _away_from(info: Dictionary) -> Vector3:
	var body := get_parent() as Node3D
	if body == null:
		return Vector3.ZERO
	var from: Variant = info.get("position")
	var source := info.get("source") as Node3D
	if source != null and source.is_inside_tree():
		from = source.global_position
	if from == null:
		return Vector3.ZERO
	return body.global_position - (from as Vector3)


func _backward() -> Vector3:
	var body := get_parent() as Node3D
	if body == null:
		return Vector3.BACK
	var back := body.global_basis.z
	back.y = 0.0
	return back.normalized() if back.length_squared() > EPS else Vector3.BACK
