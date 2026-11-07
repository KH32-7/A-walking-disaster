class_name LootContainer
extends StaticBody3D
## A lootable container in the field (B-08). Sits on physics layer 7 (interactable).
## Flow: begin_open() -> open timer -> contents appear "unidentified" -> one slot is
## identified every REVEAL_SEC -> take(). Moving the interactor ends the session.
## Locked containers without a key are forced open, which makes noise.
## No UI here: the container screen (D-08) listens to the signals below.
## Design: docs/design/02-field.md "루팅"

enum State { CLOSED, OPENING, OPEN }

## HUD text per container kind (#28): [prompt, while opening]. Forced = locked without a key.
const LABELS := {
	LootSpot.ContainerType.DRAWER: ["뒤지기", "뒤지는 중"],
	LootSpot.ContainerType.MEDICINE: ["뒤지기", "뒤지는 중"],
	LootSpot.ContainerType.TOOLBOX: ["열기", "여는 중"],
	LootSpot.ContainerType.SUPPLY_CRATE: ["열기", "여는 중"],
	LootSpot.ContainerType.MONSTER_NEST: ["뒤지기", "뒤지는 중"],
}
const FORCED_LABELS := ["자물쇠 따기", "자물쇠 따는 중"]

## B-26 look per container kind from the private packs: [folder, piece, scale], one picked by
## position. Without the packs (CI) the greybox box stays.
const LOOKS := {
	LootSpot.ContainerType.DRAWER: [["furniture", "nightstand_01", 1.4], ["outdoor_environment", "tool_cabinet", 1.25],
		["furniture", "dresser_01", 1.1]],
	LootSpot.ContainerType.MEDICINE: [["gameplay_props", "medical_supplies_crate", 1.8],
		["gameplay_props", "medical_duffel_bag", 1.4]],
	LootSpot.ContainerType.TOOLBOX: [["gameplay_props", "tool_box_green", 1.8], ["gameplay_props", "tool_box", 1.9],
		["outdoor_environment", "tool_cabinet", 1.25]],
	LootSpot.ContainerType.SUPPLY_CRATE: [["gameplay_props", "long_hard_case", 1.4],
		["gameplay_props", "small_security_safe", 1.9], ["gameplay_props", "food_supplies_crat", 1.8]],
	LootSpot.ContainerType.MONSTER_NEST: [["nature/plants", "fungi_polyp_2", 2.4]],
}
## Outline by state, one colour per meaning: not opened yet, opened with items left. Emptied: none.
## User feedback 2026-11-05: easier to spot, so thick and bright.
const OUTLINE_FRESH := Color("ffcc33")
const OUTLINE_SEEN := Color("a8c4e0")
const OUTLINE_PX := 6.0
const OUTLINE_MATERIAL := preload("res://art/materials/outline.tres")
const CityKit := preload("res://field/buildings/city_kit.gd")

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
## Furniture piece drawn instead of the kind's crate look (LootSpot.look_piece), &"" = crate.
@export var look_piece: StringName = &""

var state := State.CLOSED
## [{"item_id": StringName, "count": int, "identified": bool}], count 0 = taken. Gear slots also
## have "rarity", blueprint slots "blueprint" and "output_id" (LootTable.roll).
var _slots: Array[Dictionary] = []
var _rolled := false
var _locked := false
var _use_key := false
var _interactor: Node3D
var _start_pos := Vector3.ZERO
var _timer := 0.0
## Contents were shown at least once.
var _seen := false
var _look: Array[GeometryInstance3D] = []
var _outlines := {}


func _ready() -> void:
	# On an upper floor it hides with the roofs of the zone below (IndoorZone.ABOVE_GROUP).
	add_to_group(IndoorZone.ABOVE_GROUP)
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0
	if def:
		_locked = def.locked
	opened.connect(func(_count: int) -> void: _refresh_outline())
	slot_taken.connect(func(_i: int, _id: StringName, _n: int) -> void: _refresh_outline())
	# The spawner sets the transform after add_child; pick the look from the final position.
	_dress.call_deferred()


## Swaps the greybox for a pack piece (when the packs are here) and draws the state outline.
func _dress() -> void:
	var greybox := get_node_or_null(^"Greybox") as GeometryInstance3D
	var looks: Array = LOOKS.get(def.type if def else LootSpot.ContainerType.DRAWER, [])
	if look_piece != &"" and CityKit.PROPS.has(look_piece):
		looks = [[CityKit.PROPS[look_piece][0], String(look_piece), 1.0]]
		_fit_shape(CityKit.PROPS[look_piece][2])
	if not looks.is_empty() and CityKit.available():
		var pick: Array = looks[absi(hash(Vector3i(global_position.round()))) % looks.size()]
		var part := CityKit.prop_part(pick[1], Vector2.ZERO, 0.0, 0.0, pick[2])
		if not part.is_empty():
			var node := CityKit.place(self, pick[0], pick[1], part.xf)
			if node != null:
				for mi in node.find_children("*", "GeometryInstance3D", true, false):
					_look.append(mi)
				if greybox != null:
					greybox.visible = false
	if _look.is_empty() and greybox != null:
		_look.append(greybox)
	_refresh_outline()


## Furniture is bigger than a crate: the interaction shape (and the greybox) take its size, centred.
func _fit_shape(size: Vector3) -> void:
	var cs := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if cs != null:
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	var greybox := get_node_or_null(^"Greybox") as MeshInstance3D
	if greybox != null:
		var mesh := (greybox.mesh as BoxMesh).duplicate() as BoxMesh
		mesh.size = size
		greybox.mesh = mesh
		greybox.position = Vector3(0.0, size.y * 0.5, 0.0)


func _refresh_outline() -> void:
	var color := OUTLINE_FRESH
	if _seen:
		color = OUTLINE_SEEN if _slots.any(func(s: Dictionary) -> bool: return s.count > 0) else Color.TRANSPARENT
	var mat: Material = null
	if color.a > 0.0:
		if not _outlines.has(color):
			var m := OUTLINE_MATERIAL.duplicate() as ShaderMaterial
			m.set_shader_parameter(&"outline_color", color)
			m.set_shader_parameter(&"outline_px", OUTLINE_PX)
			_outlines[color] = m
		mat = _outlines[color]
	for g in _look:
		if is_instance_valid(g):
			g.material_overlay = mat


func _physics_process(delta: float) -> void:
	advance(delta)


## Fills the slots now (the spawner calls this so one sortie seed gives one result).
## Without it the contents are rolled with a random seed on first open.
func roll_contents(rng: RandomNumberGenerator) -> void:
	_slots.clear()
	if loot_table:
		for drop in loot_table.roll(rng):
			var slot := drop.duplicate()  # keeps gear "rarity" and blueprint "blueprint"/"output_id"
			slot["identified"] = false
			_slots.append(slot)
	_rolled = true


## Adds one piece of gear (an ItemDef id, e.g. &"pistol") as its own slot. Taking it creates the
## item (Armory.create_item) and puts it in the bag (Bag.add_item). Used by the intro chest.
func add_gear(def_id: StringName, rarity: int = 0) -> void:
	_slots.append({"item_id": def_id, "count": 1, "identified": false, "gear": true, "rarity": rarity})
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
## Gear is created in Armory only when it fits (like MonsterDropPile). A blueprint is learned at once.
func take(index: int) -> int:
	if state != State.OPEN or index < 0 or index >= _slots.size():
		return 0
	var slot := _slots[index]
	if not slot.identified or slot.count <= 0:
		return 0
	if slot.get("gear", false):
		var uid := Armory.create_item(slot.item_id, int(slot.get("rarity", 0)))
		if uid == &"" or Bag.add_item(uid) < 0:
			if uid != &"":
				Armory.remove_item(uid)
			return 0
		slot.count = 0
		slot_taken.emit(index, slot.item_id, 1)
		return 1
	if slot.has("blueprint"):
		_learn_blueprint(slot)
		slot.count = 0
		slot_taken.emit(index, slot.item_id, 1)
		return 1
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


## Prompt the HUD shows next to the interact key (#28).
func interact_label() -> String:
	return _labels()[0]


## HUD hold bar: {"label", "progress"} while opening, {} otherwise (#28).
func hold_state() -> Dictionary:
	if state != State.OPENING:
		return {}
	return {"label": _labels()[1], "progress": open_progress()}


func _labels() -> Array:
	if _locked and not _has_key():
		return FORCED_LABELS
	return LABELS.get(def.type if def else LootSpot.ContainerType.DRAWER, LABELS[LootSpot.ContainerType.DRAWER])


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
	_seen = true
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


func _learn_blueprint(slot: Dictionary) -> void:
	var def := Armory.get_def(slot.output_id)
	var name := String(def.name) if def != null else String(slot.output_id)
	if GameState.has_flag(slot.blueprint):
		EventBus.notification_posted.emit("이미 아는 설계도예요: %s" % name, &"info")
		return
	GameState.set_flag(slot.blueprint)
	EventBus.notification_posted.emit("설계도를 익혔어요: %s" % name, &"info")


func _has_key() -> bool:
	return def != null and def.key_item_id != &"" and Bag.count_of(def.key_item_id) > 0
