class_name ExtractionManager
extends Node
## Extraction and sortie result (B-09). Put one in each region scene.
## Picks ACTIVE_COUNT of the map's ExtractPoint markers per sortie (same seed = same points),
## runs the stand-in-zone countdown, the conditional types (generator / key / battery), the
## "leave them behind?" check for party members, and builds the sortie result.
##
## Lane D: find this node with get_tree().get_first_node_in_group(ExtractionManager.GROUP),
## listen to the signals below and show the map marks, progress and the confirm dialog.
## Party members (companions B-17, rescued B-10): Node3D in group PARTY_GROUP with
## `party_id: StringName`, `display_name: String`, `party_kind: StringName` (KIND_*).
## Design reference: docs/design/02-field.md "탈출"

## The active points changed (sortie start). Lane D marks them on the map.
signal active_points_changed(point_ids: Array[StringName])
## Countdown started at `point_id`. `wait_sec` already includes wait_multiplier.
signal extraction_started(point_id: StringName, wait_sec: float)
## Player left the zone (or went down) before extracting.
signal extraction_cancelled(point_id: StringName)
## Player stands at a KEY / BATTERY point without the item. Sent once per visit.
signal extraction_blocked(point_id: StringName, required_item: StringName)
## Countdown done but party members are farther than PARTY_RADIUS.
## people: [{"id": StringName, "name": String, "kind": StringName}]. Answer with answer_leave_behind().
signal leave_behind_requested(point_id: StringName, people: Array)
## The sortie is over (extracted or downed). Same Dictionary as get_result().
signal sortie_result_ready(result: Dictionary)

const GROUP := &"field_extraction"
## Shared with B-10 rescue: rescued people and companions are on physics layer 3 (ally) and in this group.
const PARTY_GROUP := &"escorts"
const KIND_COMPANION := &"companion"
const KIND_RESCUED := &"rescued"

# --- Rules (02 "탈출"). Drafts (가안). Wait seconds live on each ExtractPoint marker. ---
## Active extraction points per sortie, out of the map's candidates (02 "맵 구조": 3 candidates, 2 active).
const ACTIVE_COUNT := 2
## Party members farther than this from the player trigger the leave-behind question.
const PARTY_RADIUS := 6.0
## The zone is a cylinder: zone_radius around the marker, this far above or below it.
const ZONE_HALF_HEIGHT := 2.0
## Bag item each conditional type needs. One is used up on extraction.
const REQUIRED_ITEM := {
	ExtractPoint.Type.KEY: &"key",
	ExtractPoint.Type.BATTERY: &"battery",
}
## NoiseTable action repeated while a generator runs (25m).
const GENERATOR_NOISE := &"generator"

enum State { IDLE, COUNTING, CONFIRM, WAITING_PARTY, DONE }

## Region id written into the result and companion_stranded.
@export var region_id: StringName = &""
## Seed for picking the active points. -1 = random. TODO(A-05): pass the sortie seed from the loadout.
@export var sortie_seed := -1
## Pick the active points on _ready. Tests turn this off and call activate() themselves.
@export var auto_activate := true
## Every wait_sec is multiplied by this. B-22 emergency return sets it to 0.
@export var wait_multiplier := 1.0

var state := State.IDLE

var _active: Array[ExtractPoint] = []
var _current: ExtractPoint
var _elapsed := 0.0
var _blocked_at: ExtractPoint
var _pending_people: Array = []
var _noise: NoiseEmitter
var _sortie_sec := 0.0
var _kills: Dictionary = {}
var _result: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.monster_killed.connect(_on_monster_killed)
	EventBus.player_downed.connect(_on_player_downed)
	if auto_activate:
		# Deferred so every marker in the scene has joined its group first.
		activate.call_deferred(randi() if sortie_seed < 0 else sortie_seed)


func _physics_process(delta: float) -> void:
	tick(delta)


# --- Public ---

## Picks ACTIVE_COUNT points from every ExtractPoint in the tree. Same seed and same
## candidates = same result (candidates are sorted by id first).
func activate(seed_value: int) -> void:
	var candidates: Array[ExtractPoint] = []
	for node in get_tree().get_nodes_in_group(ExtractPoint.GROUP):
		if node is ExtractPoint:
			candidates.append(node)
	candidates.sort_custom(func(a: ExtractPoint, b: ExtractPoint) -> bool: return String(a.id) < String(b.id))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Partial Fisher-Yates: the first ACTIVE_COUNT slots end up random.
	for i in mini(ACTIVE_COUNT, candidates.size()):
		var j := rng.randi_range(i, candidates.size() - 1)
		var swap := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	_active = candidates.slice(0, ACTIVE_COUNT)
	active_points_changed.emit(active_point_ids())


func active_points() -> Array[ExtractPoint]:
	return _active.duplicate()


func active_point_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for p in _active:
		ids.append(p.id)
	return ids


## Point being counted down / confirmed, or &"".
func current_point_id() -> StringName:
	return _current.id if _current != null else &""


## 0..1 countdown progress at the current point (Lane D's ring). 1 while confirming.
func progress() -> float:
	if _current == null:
		return 0.0
	var wait := _wait_for(_current)
	return 1.0 if wait <= 0.0 else clampf(_elapsed / wait, 0.0, 1.0)


## Answer to leave_behind_requested. true = leave them (they are stranded) and extract now.
## false = wait: extraction happens as soon as everyone is within PARTY_RADIUS.
func answer_leave_behind(leave: bool) -> void:
	if state != State.CONFIRM:
		return
	if leave:
		_complete(_pending_people)
	else:
		state = State.WAITING_PARTY
	_pending_people = []


## The finished sortie's result ({} until extraction or downing). Format: see _build_result().
func get_result() -> Dictionary:
	return _result


## One step of the extraction logic. _physics_process calls it; tests call it directly.
func tick(delta: float) -> void:
	if state == State.DONE:
		return
	_sortie_sec += delta
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	if player == null or player.get("is_downed") == true:
		_cancel()
		return
	var here := _point_under(player.global_position)
	if here != _blocked_at:
		_blocked_at = null
	if state != State.IDLE and here != _current:
		_cancel()
	match state:
		State.IDLE:
			if here != null:
				_try_start(here)
		State.COUNTING:
			_elapsed += delta
		State.WAITING_PARTY:
			if _people_outside(player).is_empty():
				_complete([])
	if state == State.COUNTING and _elapsed >= _wait_for(_current):
		_on_wait_done(player)


# --- Internals ---

func _point_under(pos: Vector3) -> ExtractPoint:
	for p in _active:
		var d := pos - p.global_position
		if Vector2(d.x, d.z).length() <= p.zone_radius and absf(d.y) <= ZONE_HALF_HEIGHT:
			return p
	return null


func _wait_for(point: ExtractPoint) -> float:
	return maxf(point.wait_sec * wait_multiplier, 0.0)


func _has_required_item(point: ExtractPoint) -> bool:
	return not REQUIRED_ITEM.has(point.type) or Bag.count_of(REQUIRED_ITEM[point.type]) > 0


func _try_start(point: ExtractPoint) -> void:
	if not _has_required_item(point):
		if _blocked_at != point:
			_blocked_at = point
			extraction_blocked.emit(point.id, REQUIRED_ITEM[point.type])
		return
	_current = point
	_elapsed = 0.0
	state = State.COUNTING
	if point.type == ExtractPoint.Type.GENERATOR:
		_start_generator(point)
	extraction_started.emit(point.id, _wait_for(point))


func _start_generator(point: ExtractPoint) -> void:
	_noise = NoiseEmitter.new()
	_noise.name = "GeneratorNoise"
	_noise.raining = GameState.is_raining()
	# Child of the marker: the noise comes from the generator, not the player.
	point.add_child(_noise)
	_noise.start_continuous(GENERATOR_NOISE)


func _stop_generator() -> void:
	if _noise != null:
		_noise.stop_continuous()
		_noise.queue_free()
		_noise = null


func _cancel() -> void:
	if state == State.IDLE or state == State.DONE:
		return
	var point_id := _current.id
	_stop_generator()
	_current = null
	_elapsed = 0.0
	_pending_people = []
	state = State.IDLE
	extraction_cancelled.emit(point_id)


func _on_wait_done(player: Node3D) -> void:
	_stop_generator()
	var outside := _people_outside(player)
	if outside.is_empty():
		_complete([])
		return
	_pending_people = outside
	state = State.CONFIRM
	leave_behind_requested.emit(_current.id, outside.duplicate(true))


func _people_outside(player: Node3D) -> Array:
	var out := []
	for member in _party():
		if member.global_position.distance_to(player.global_position) > PARTY_RADIUS:
			out.append(_person(member))
	return out


func _party() -> Array[Node3D]:
	var members: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(PARTY_GROUP):
		if node is Node3D:
			members.append(node)
	return members


func _person(member: Node3D) -> Dictionary:
	return {
		"id": StringName(str(member.get("party_id"))),
		"name": str(member.get("display_name")),
		"kind": StringName(str(member.get("party_kind"))),
	}


func _complete(left_behind: Array) -> void:
	var point := _current
	if REQUIRED_ITEM.has(point.type) and not Bag.remove_item(REQUIRED_ITEM[point.type], 1):
		# The item left the bag during the countdown.
		_cancel()
		return
	var stranded: Array[StringName] = []
	for person: Dictionary in left_behind:
		stranded.append(person["id"])
		if person["kind"] == KIND_COMPANION:
			EventBus.companion_stranded.emit(person["id"], region_id)
	var rescued: Array[StringName] = []
	var companions: Array[StringName] = []
	for member in _party():
		var person := _person(member)
		if stranded.has(person["id"]):
			continue
		if person["kind"] == KIND_RESCUED:
			rescued.append(person["id"])
		else:
			companions.append(person["id"])
	# Unload before the signal: the autosave after extraction_completed must see the base stock.
	var loot := Bag.unload_to_base()
	_finish(_build_result(true, point.id, loot, rescued, companions, stranded))
	EventBus.extraction_completed.emit(point.id)


func _on_player_downed() -> void:
	if state == State.DONE:
		return
	_cancel()
	# B-11 handles the bag loss, lost gear and companion_stranded. Everyone with us is stranded.
	var stranded: Array[StringName] = []
	for member in _party():
		stranded.append(_person(member)["id"])
	var empty: Array[StringName] = []
	_finish(_build_result(false, &"", {}, empty, empty, stranded))


func _finish(result: Dictionary) -> void:
	_current = null
	state = State.DONE
	_result = result
	sortie_result_ready.emit(result)


func _on_monster_killed(monster_id: StringName, _element: Enums.Element, _position: Vector3) -> void:
	if state != State.DONE:
		_kills[monster_id] = int(_kills.get(monster_id, 0)) + 1


## Sortie result. Proposed format for EventBus.sortie_ended (A-05 agreement pending).
func _build_result(extracted: bool, point_id: StringName, loot: Dictionary,
		rescued: Array[StringName], companions: Array[StringName], stranded: Array[StringName]) -> Dictionary:
	var total := 0
	for n: int in _kills.values():
		total += n
	return {
		"extracted": extracted,
		"downed": not extracted,
		"region_id": region_id,
		"point_id": point_id,
		# Bag.unload_to_base(): {"resources": {id: n}, "discarded": {id: n}, "items": [uid]}. {} when downed.
		"loot": loot,
		"kills": total,
		"kills_by_monster": _kills.duplicate(),
		"rescued": rescued,
		"companions": companions,
		"stranded": stranded,
		"duration_sec": _sortie_sec,
		"xp": 0,  # TODO(A-11): mastery / xp
	}
