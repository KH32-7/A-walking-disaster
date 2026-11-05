class_name LootContainer
extends StaticBody3D
## A lootable container in the field (B-08). Sits on physics layer 7 (interactable).
## Flow: begin_open() -> open timer -> contents appear "unidentified" -> one slot is
## identified every REVEAL_SEC -> take(). Moving the interactor ends the session.
## Locked containers without a key are forced open, which makes noise.
## No UI here: the container screen (D-08) listens to the signals below.
## Design: docs/design/02-field.md "루팅"

enum State { CLOSED, OPENING, OPEN }

## Seconds to identify one slot (design: 칸마다 0.5초).
const REVEAL_SEC := 0.5
## Interactor moving farther than this (m) from where it started ends the session.
const MOVE_CANCEL_DISTANCE := 0.1

## Open timer started. forcing = locked and no key, noise already emitted.
signal open_started(duration: float, forcing: bool)
## Contents are visible (unidentified slots included). Also fires when reopening.
signal opened(slot_count: int)
signal slot_revealed(index: int, item_id: StringName, count: int)
## Every slot is identified.
signal reveal_finished()
## The interactor moved away or cancel_open() was called.
signal session_ended()
signal slot_taken(index: int, item_id: StringName, count: int)

@export var def: LootContainerDef
@export var loot_table: LootTable

var state := State.CLOSED
## [{"item_id": StringName, "count": int, "identified": bool}], count 0 = taken.
var _slots: Array[Dictionary] = []
var _rolled := false
var _locked := false
var _use_key := false
var _interactor: Node3D
var _start_pos := Vector3.ZERO
var _timer := 0.0


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0
	if def:
		_locked = def.locked


func _physics_process(delta: float) -> void:
	advance(delta)


## Fills the slots now (the spawner calls this so one sortie seed gives one result).
## Without it the contents are rolled with a random seed on first open.
func roll_contents(rng: RandomNumberGenerator) -> void:
	_slots.clear()
	if loot_table:
		for drop in loot_table.roll(rng):
			_slots.append({"item_id": drop.item_id, "count": drop.count, "identified": false})
	_rolled = true


## Starts opening, or resumes identifying an already opened container.
## Returns false if someone else is using it.
func begin_open(interactor: Node3D) -> bool:
	if interactor == null or (_interactor != null and _interactor != interactor):
		return false
	_interactor = interactor
	_start_pos = interactor.global_position
	if state == State.OPEN:
		_show_contents()
		return true
	state = State.OPENING
	_timer = def.open_sec if def else 0.0
	_use_key = _locked and _has_key()
	var forcing := _locked and not _use_key
	if forcing and def.noise_on_force > 0.0:
		EventBus.noise_emitted.emit(global_position, def.noise_on_force, interactor)
	open_started.emit(_timer, forcing)
	return true


## Stops the session. An unfinished open loses its progress; identified slots stay identified.
func cancel_open() -> void:
	if _interactor == null:
		return
	_interactor = null
	if state == State.OPENING:
		state = State.CLOSED
	session_ended.emit()


## Moves the slot into the bag. Returns how many were taken (0 if unidentified or bag full).
func take(index: int) -> int:
	if state != State.OPEN or index < 0 or index >= _slots.size():
		return 0
	var slot := _slots[index]
	if not slot.identified or slot.count <= 0:
		return 0
	var added := Bag.try_add(slot.item_id, slot.count)
	if added > 0:
		slot.count -= added
		slot_taken.emit(index, slot.item_id, added)
	return added


## Copy of the slots. Unidentified slots hide their item: item_id is &"" and count 0.
func get_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in _slots:
		if slot.identified:
			out.append(slot.duplicate())
		else:
			out.append({"item_id": &"", "count": 0, "identified": false})
	return out


## 0..1 while opening, 1 once open, 0 when closed.
func open_progress() -> float:
	match state:
		State.OPEN:
			return 1.0
		State.OPENING:
			var total := def.open_sec if def else 0.0
			return 1.0 - _timer / total if total > 0.0 else 1.0
	return 0.0


func is_locked() -> bool:
	return _locked


func is_in_session() -> bool:
	return _interactor != null


## Runs the timers. Called every physics frame; tests call it directly.
func advance(delta: float) -> void:
	if _interactor == null:
		return
	if not is_instance_valid(_interactor) \
			or _interactor.global_position.distance_to(_start_pos) > MOVE_CANCEL_DISTANCE:
		cancel_open()
		return
	_timer -= delta
	if state == State.OPENING:
		if _timer > 0.0:
			return
		_finish_open()
	while state == State.OPEN and _interactor != null and _timer <= 0.0:
		var next := _next_unidentified()
		if next < 0:
			return
		_reveal(next)


func _finish_open() -> void:
	state = State.OPEN
	if _locked:
		_locked = false
		if _use_key:
			Bag.remove_item(def.key_item_id, 1)
	if not _rolled:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		roll_contents(rng)
	_show_contents()


func _show_contents() -> void:
	_timer = REVEAL_SEC
	opened.emit(_slots.size())
	if _next_unidentified() < 0:
		reveal_finished.emit()
	elif Settings.get_value(&"instant_loot"):
		while _next_unidentified() >= 0:
			_reveal(_next_unidentified())


func _reveal(index: int) -> void:
	var slot := _slots[index]
	slot.identified = true
	_timer += REVEAL_SEC
	slot_revealed.emit(index, slot.item_id, slot.count)
	if _next_unidentified() < 0:
		reveal_finished.emit()


func _next_unidentified() -> int:
	for i in _slots.size():
		if not _slots[i].identified:
			return i
	return -1


func _has_key() -> bool:
	return def != null and def.key_item_id != &"" and Bag.count_of(def.key_item_id) > 0
