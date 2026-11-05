class_name CompanionManager
extends Node
## Spawns the sortie's companion residents next to the player and switches their mode (B-17).
## Put one in each region assembly scene (next to RescueManager).
##
## - spawn(): one FieldCompanion per FieldState.companions id (the loadout's "companions", B-11),
##   up to tuning.max_companions, beside the player. Skips ids Colony does not know, residents who
##   are not ACTIVE, and children / teens (07: 아이·청소년은 전투 배정 불가).
## - Hold companion_command (V) = next mode for everyone (공격적 -> 신중 -> 엄호). A short tap stays
##   RescueManager's 숨기 / 따라오기 (CommandPress).
## Lane D: find this node in GROUP and listen to companion_spawned for each companion's signals.
## Design reference: docs/design/03-combat-classes.md "동행 주민 전투", 02-field.md "함께 나오기".

signal companion_spawned(companion: FieldCompanion)
signal mode_changed(mode: FieldCompanion.Mode)

const GROUP := &"field_companion_manager"
const COMPANION_SCENE := preload("res://field/companion/field_companion.tscn")
const NOT_FIGHTING_AGES: Array[int] = [Enums.AgeStage.BABY, Enums.AgeStage.CHILD, Enums.AgeStage.TEEN]

@export var tuning: CompanionTuning = FieldCompanion.DEFAULT_TUNING
## Tests turn this off and call spawn() themselves.
@export var spawn_on_ready := true

var companions: Array[FieldCompanion] = []
var mode := FieldCompanion.Mode.AGGRESSIVE
var _press := CommandPress.new()


func _ready() -> void:
	add_to_group(GROUP)
	if spawn_on_ready:
		# Deferred: the player is placed on its PlayerSpawn first.
		spawn.call_deferred()


func _process(delta: float) -> void:
	var held := Input.is_action_pressed(&"companion_command") and not Player.input_blocked()
	if _press.update(held, delta) == CommandPress.Result.HOLD:
		cycle_mode()


## Places the sortie's companions (FieldState.companions) beside the player.
func spawn() -> Array[FieldCompanion]:
	return spawn_ids(FieldState.companions)


## Places these residents beside the player. Returns them (also kept in `companions`).
func spawn_ids(ids: Array[StringName]) -> Array[FieldCompanion]:
	var placed: Array[FieldCompanion] = []
	var player := get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	for id in ids:
		if companions.size() >= tuning.max_companions:
			break
		var data := Colony.get_resident(id)
		if not can_come(data):
			push_warning("CompanionManager: resident '%s' cannot come out" % id)
			continue
		var c: FieldCompanion = COMPANION_SCENE.instantiate()
		c.setup(id, data)
		c.mode = mode
		add_child(c)
		c.global_position = _slot_position(player, companions.size())
		companions.append(c)
		placed.append(c)
		companion_spawned.emit(c)
	return placed


## Known, ACTIVE, and old enough for combat (07).
static func can_come(data: Dictionary) -> bool:
	if data.is_empty():
		return false
	if int(data.get("status", Enums.ResidentStatus.ACTIVE)) != Enums.ResidentStatus.ACTIVE:
		return false
	return not NOT_FIGHTING_AGES.has(int(data.get("age_stage", Enums.AgeStage.ADULT)))


## 공격적 -> 신중 -> 엄호 -> 공격적, for every companion.
func cycle_mode() -> FieldCompanion.Mode:
	set_mode(((mode + 1) % FieldCompanion.Mode.size()) as FieldCompanion.Mode)
	return mode


func set_mode(next: FieldCompanion.Mode) -> void:
	mode = next
	for c in companions:
		if is_instance_valid(c):
			c.set_mode(mode)
	mode_changed.emit(mode)


## Right, then left of the player (or this node without a player).
func _slot_position(player: Node3D, index: int) -> Vector3:
	if player == null:
		return get_parent().global_position if get_parent() is Node3D else Vector3.ZERO
	var right := player.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var side := 1.0 if index % 2 == 0 else -1.0
	return player.global_position + right * side * tuning.spawn_offset * (1 + floori(index / 2.0))
