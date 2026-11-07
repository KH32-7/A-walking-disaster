class_name ConsumableUser
extends Node
## Player quick-slot consumables (B-16): keys 3 to 6 (item_1..item_4), use time, throwing.
## The player creates it with `ConsumableUser.attach(self)` (child "Consumables") and passes its
## step input through filter_input(). An item leaves the Bag only when it works: a SELF item when
## its use time ends, a thrown one when it leaves the hand. Thrown ones: ThrownConsumable.
##
## Quick slots (가안): sticky auto-assignment. A consumable kind in the bag takes the lowest free
## slot (ConsumableDef.slot_priority order when several show up at once) and keeps it until the bag
## has none left, so a key means the same item for the whole sortie. A 5th kind waits for a free slot.
##
## Use rules (가안 where 03 is silent): one at a time. While using, walking follows can_move
## (x USE_MOVE_MULT, no sprint) or stops. Dodging, attacking, reloading, stagger / knockback or going
## down cancels it and keeps the item. A hit alone does not cancel.
## Design reference: docs/design/03-combat-classes.md "소모품"

signal use_started(id: StringName, duration_sec: float)
signal use_finished(id: StringName)
signal use_cancelled(id: StringName)
signal thrown(id: StringName, target: Vector3)

const NODE_NAME := &"Consumables"
const DIR := "res://data/classes/consumables/"
const SLOT_COUNT := 4
const SLOT_ACTIONS: Array[StringName] = [&"item_1", &"item_2", &"item_3", &"item_4"]
## Walking speed share while using a can_move item (03 구급상자 "느리게 이동 가능").
const USE_MOVE_MULT := 0.5
## Throws land on the aim point, at most this far (m). With no aim point yet: this far ahead.
const THROW_MAX_RANGE := 12.0
const THROW_DEFAULT_RANGE := 8.0
## Hand height the throw leaves from (m).
const THROW_HEIGHT := 1.4
const HOLD_LABEL := "%s 사용 중"

static var _defs: Dictionary = {}
static var _sorted: Array[ConsumableDef] = []
static var _loaded := false

## Consumable id per quick slot (key 3 + index), &"" = empty.
var slots: Array[StringName] = [&"", &"", &"", &""]

var _player: Player
var _using: ConsumableDef
var _left := 0.0


## Creates the user as a child of `player`. Call it from the player's @onready.
static func attach(player: Player) -> ConsumableUser:
	var user := ConsumableUser.new()
	user.name = NODE_NAME
	player.add_child(user)
	return user


## data/classes/consumables/<id>.tres, or null.
static func get_def(id: StringName) -> ConsumableDef:
	_load_defs()
	return _defs.get(id)


## Every consumable kind, slot_priority first.
static func all_defs() -> Array[ConsumableDef]:
	_load_defs()
	return _sorted


## Bag name (ResourceDef) if Lane A has one, else the ConsumableDef name.
static func display_name(id: StringName) -> String:
	var res := Economy.get_def(id)
	if res != null and res.name != "":
		return res.name
	var def := get_def(id)
	return def.name if def != null and def.name != "" else String(id)


static func _load_defs() -> void:
	if _loaded:
		return
	_loaded = true
	# list_directory handles exported (remapped) resources too.
	for file in ResourceLoader.list_directory(DIR):
		if not file.ends_with(".tres"):
			continue
		var def := load(DIR.path_join(file)) as ConsumableDef
		if def == null or def.id == &"":
			push_error("ConsumableUser: %s is not a ConsumableDef with an id" % file)
			continue
		_defs[def.id] = def
		_sorted.append(def)
	_sorted.sort_custom(func(a: ConsumableDef, b: ConsumableDef) -> bool:
		return a.slot_priority < b.slot_priority \
				or (a.slot_priority == b.slot_priority and String(a.id) < String(b.id)))


func _ready() -> void:
	_player = get_parent() as Player
	EventBus.bag_changed.connect(refresh_slots)
	refresh_slots()
	var weapons: WeaponHolder = _player.get_node_or_null(^"Weapons") as WeaponHolder if _player else null
	if weapons:
		weapons.attacked.connect(func(_kind: StringName, _step: int) -> void: cancel())
		weapons.reload_started.connect(func(_sec: float) -> void: cancel())


func _physics_process(delta: float) -> void:
	for i in SLOT_COUNT:
		if Input.is_action_just_pressed(SLOT_ACTIONS[i]) and not Player.input_blocked() \
				and not (_player != null and _player.is_riding()):
			use_slot(i)
	step(delta)


# --- Using ------------------------------------------------------------------

## Uses whatever sits in quick slot `index` (0 = key 3). False when nothing happened.
func use_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	return use(slots[index])


## Starts using (SELF) or throws one `id` from the bag. False when it cannot start.
func use(id: StringName) -> bool:
	var def := get_def(id)
	if def == null or is_using() or not _can_act() or Bag.count_of(id) <= 0:
		return false
	if def.effect != ConsumableDef.Effect.SELF:
		return _throw(def)
	if def.use_sec <= 0.0:
		return _finish(def)
	_using = def
	_left = def.use_sec
	use_started.emit(id, def.use_sec)
	return true


## Advances the use timer. Tests call this directly.
func step(delta: float) -> void:
	if _using == null:
		return
	if not _can_act():
		cancel()
		return
	_left -= delta
	if _left <= 0.0:
		var def := _using
		_using = null
		_left = 0.0
		_finish(def)


## Stops the current use. The item stays in the bag.
func cancel() -> void:
	if _using == null:
		return
	var id := _using.id
	_using = null
	_left = 0.0
	use_cancelled.emit(id)


func is_using() -> bool:
	return _using != null


## Id being used, or &"".
func using_id() -> StringName:
	return _using.id if _using else &""


## Player.step passes its input through here: slow or stop walking, no sprint, a dodge cancels.
func filter_input(input: Dictionary) -> Dictionary:
	if _using == null:
		return input
	if input.get("dodge", false):
		cancel()
		return input
	var move: Vector2 = input.get("move", Vector2.ZERO)
	return input.merged({"move": move * USE_MOVE_MULT if _using.can_move else Vector2.ZERO,
			"sprint": false}, true)


## Heals and statuses of a SELF item on the player (perk bonus included).
func apply_self(def: ConsumableDef) -> void:
	var amount := def.heal
	if def.heal_perk_stat != &"":
		amount *= 1.0 + Progression.perk_bonus(def.heal_perk_stat) / 100.0
	if amount > 0.0:
		_player.health = minf(_player.health + amount, _player.stats.max_health)
		_player.health_changed.emit(_player.health, _player.stats.max_health)
	if def.remove_status != &"":
		_player.status.remove(def.remove_status)
	if def.add_status != &"":
		_player.status.apply(def.add_status)
	Audio.play(StringName("consumable_%s" % def.id), _player.global_position)


## Where a throw would land now: the aim point, pulled in to THROW_MAX_RANGE.
func throw_target() -> Vector3:
	var origin := _player.global_position
	var aim: Variant = _player.aim_point()
	var flat := _player.facing() * THROW_DEFAULT_RANGE
	var y := origin.y
	if aim != null:
		flat = (aim as Vector3) - origin
		y = (aim as Vector3).y
	flat.y = 0.0
	flat = flat.limit_length(THROW_MAX_RANGE)
	return Vector3(origin.x + flat.x, y, origin.z + flat.z)


func _finish(def: ConsumableDef) -> bool:
	if not Bag.consume(def.id, 1):
		use_cancelled.emit(def.id)
		return false
	apply_self(def)
	use_finished.emit(def.id)
	return true


func _throw(def: ConsumableDef) -> bool:
	var parent := _player.get_parent()
	if parent == null or not Bag.consume(def.id, 1):
		return false
	var target := throw_target()
	var from := _player.global_position + Vector3.UP * THROW_HEIGHT
	var item := ThrownConsumable.new()
	item.def = def
	item.thrower = _player
	parent.add_child(item)
	item.global_position = from
	item.launch(target)
	Audio.play(&"consumable_throw", from)
	thrown.emit(def.id, target)
	return true


## Downed, staggered, knocked back or mid-dodge: no using.
func _can_act() -> bool:
	return _player != null and not _player.is_downed and _player.status.can_act() \
			and _player.move_state != Player.MoveState.DODGE


# --- Quick slots and HUD ------------------------------------------------------

## Frees slots whose item ran out, then gives new kinds the lowest free slots. Runs on bag_changed.
func refresh_slots() -> void:
	for i in SLOT_COUNT:
		if slots[i] != &"" and Bag.count_of(slots[i]) <= 0:
			slots[i] = &""
	for def in all_defs():
		if slots.has(def.id) or Bag.count_of(def.id) <= 0:
			continue
		var free := slots.find(&"")
		if free < 0:
			return
		slots[free] = def.id


## Player.hud_state() "consumables": 4 entries, {name, count, rarity} or null (issue #28).
func hud_slots() -> Array:
	var out: Array = []
	for id in slots:
		out.append(null if id == &"" else {"name": display_name(id), "count": Bag.count_of(id), "rarity": 0})
	return out


## Player.hud_state() "hold" while using: {label, progress}, else {}.
func hold_state() -> Dictionary:
	if _using == null:
		return {}
	return {"label": HOLD_LABEL % display_name(_using.id),
			"progress": clampf(1.0 - _left / _using.use_sec, 0.0, 1.0)}
