class_name RescueManager
extends Node
## Spawns the sortie's rescue targets on RescueSpots and runs the companion command (B-10).
## Put one in each region assembly scene with that region's RescueSpawn list.
##
## - spawn(): up to max_per_sortie spawns, in list order, skipping people who already live in
##   the base (Colony.get_resident). Each goes on a random free RescueSpot with all its tags.
## - companion_command (V): everyone following hides; if nobody follows, the hidden follow again.
## - Extraction (B-09 ExtractionManager.sortie_result_ready, before extraction_completed):
##   EventBus.rescue_completed(profile) for every rescued person that came out. Colony turns it
##   into a resident (contracts.md: Colony listens to rescue_completed and calls add_resident).
## Lane D: find this node in GROUP and listen to target_spawned for each person's signals.
## Design reference: docs/design/02-field.md "구조 이벤트", "함께 나오기 (호위)".

signal target_spawned(target: RescueTarget)

const GROUP := &"field_rescue"
const EXTRACTION_GROUP := ExtractionManager.GROUP
const TARGET_SCENE := preload("res://field/rescue/rescue_target.tscn")

@export var spawns: Array[RescueSpawn] = []
## 02: 출격당 0~2명, 구조자 최대 2명.
@export var max_per_sortie := 2
## -1 = the sortie's loadout seed (FieldState.sortie_seed), or random without SceneRouter.
@export var sortie_seed := -1
## Tests turn this off and call spawn() themselves.
@export var spawn_on_ready := true

var targets: Array[RescueTarget] = []
var _completed := {}


func _ready() -> void:
	add_to_group(GROUP)
	_connect_extraction.call_deferred()
	if spawn_on_ready:
		var rng := RandomNumberGenerator.new()
		if sortie_seed >= 0:
			rng.seed = sortie_seed
		elif FieldState.sortie_seed >= 0:
			# Same loadout seed as ExtractionManager: a reload gets the same people in the same spots.
			rng.seed = FieldState.sortie_seed
		else:
			rng.randomize()
		spawn.call_deferred(rng)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"companion_command"):
		toggle_command()


## Places the sortie's rescue targets. Returns them (also kept in `targets`).
func spawn(rng: RandomNumberGenerator) -> Array[RescueTarget]:
	var spots: Array[RescueSpot] = []
	for node in get_tree().get_nodes_in_group(RescueSpot.GROUP):
		if node is RescueSpot:
			spots.append(node)
	spots.sort_custom(func(a: Node, b: Node) -> bool: return str(a.get_path()) < str(b.get_path()))
	var placed: Array[RescueTarget] = []
	for s in spawns:
		if placed.size() >= max_per_sortie:
			break
		var profile := profile_for(s)
		if profile.is_empty() or (s.template_id != &"" and not Colony.get_resident(s.template_id).is_empty()):
			continue
		var free := spots.filter(func(spot: RescueSpot) -> bool: return _matches(spot, s))
		if free.is_empty():
			continue
		var spot: RescueSpot = free[rng.randi_range(0, free.size() - 1)]
		spots.erase(spot)
		var t: RescueTarget = TARGET_SCENE.instantiate()
		t.setup(s, profile, spot.spawn_tags.duplicate())
		add_child(t)
		t.global_transform = spot.global_transform
		placed.append(t)
		targets.append(t)
		target_spawned.emit(t)
	return placed


## Hide everyone following; if nobody follows, call the hidden back. Returns true if anyone obeyed.
func toggle_command() -> bool:
	var following := targets.filter(func(t: RescueTarget) -> bool:
		return is_instance_valid(t) and t.state == RescueTarget.State.FOLLOW)
	var obeyed := false
	if not following.is_empty():
		for t: RescueTarget in following:
			obeyed = t.command_hide() or obeyed
		return obeyed
	for t in targets:
		if is_instance_valid(t) and t.state == RescueTarget.State.HIDE:
			obeyed = t.command_follow() or obeyed
	return obeyed


## Sends rescue_completed for the rescued people among `party_ids` (once each).
func complete_rescues(party_ids: Array) -> void:
	for t in targets:
		if not is_instance_valid(t) or not t.is_rescued() or not party_ids.has(t.party_id):
			continue
		if _completed.has(t.party_id):
			continue
		_completed[t.party_id] = true
		if t.spawn.template_id != &"":
			EventBus.rescue_completed.emit(t.profile.duplicate(true))
		# TODO(B-11/C): a returning stranded resident (resident_id) needs its own Colony call.


## Rescue profile for a spawn. Templates come from Lane C's DemoProfiles until the pool exists.
## TODO(C/A-16): replace with the Colony call from the request issue (pool lookup by id / tags).
static func profile_for(s: RescueSpawn) -> Dictionary:
	if s.resident_id != &"":
		return Colony.get_resident(s.resident_id)
	for p: Dictionary in DemoProfiles.PROFILES:
		if p.get("id", &"") == s.template_id:
			return p.duplicate(true)
	push_warning("RescueManager: no rescue profile '%s'" % s.template_id)
	return {}


func _matches(spot: RescueSpot, s: RescueSpawn) -> bool:
	for tag in s.spawn_tags:
		if not spot.spawn_tags.has(tag):
			return false
	return true


func _connect_extraction() -> void:
	var manager := get_tree().get_first_node_in_group(EXTRACTION_GROUP)
	if manager != null and manager.has_signal(&"sortie_result_ready"):
		manager.connect(&"sortie_result_ready", _on_sortie_result)


func _on_sortie_result(result: Dictionary) -> void:
	if result.get("extracted", false):
		complete_rescues(result.get("rescued", []))
