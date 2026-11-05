extends Node3D
## Lane B field sandbox (B-01). Run this scene alone (F6) to test field features.
## Greybox only: CSG floor, walls, cover, stairs + ramp to one raised deck.
## Debug UI lives here only (contracts.md: Control nodes allowed inside _sandbox/).

const ARMORY_STUB := preload("res://field/_sandbox/stubs/armory_stub.gd")

## Sandbox tunables, all in one place.
## Temporary quarter-view camera until B-04 (design 16 "아트 방향": about 55 deg down).
const CAMERA_PITCH_DEG := 55.0
const CAMERA_DISTANCE := 22.0
const CAMERA_FOCUS := Vector3.ZERO
## The sandbox stands in for a sortie, so FieldState.in_sortie() is true here.
const SIMULATE_SORTIE := true
## Real gear the player wears in the sandbox when nothing is equipped (A-07 items).
const SANDBOX_LOADOUT := {
	Enums.EquipSlot.MAIN: &"pistol",
	Enums.EquipSlot.SUB: &"dagger",
}

@onready var _camera: Camera3D = $Camera3D
@onready var _debug_label: Label = $DebugLayer/DebugLabel

var _armory_stubbed := false


func _ready() -> void:
	_install_stubs()
	if SIMULATE_SORTIE:
		GameState.set_phase(Enums.Phase.SORTIE)
	_place_camera()


func _process(_delta: float) -> void:
	_debug_label.text = "FPS: %d\nPhase: %s\nFlow: %s\nIn sortie: %s\nArmory: %s" % [
		Engine.get_frames_per_second(),
		Enums.Phase.keys()[GameState.phase],
		Enums.FlowState.keys()[GameState.flow_state],
		FieldState.in_sortie(),
		"stub" if _armory_stubbed else "real",
	]


## Give the player gear when nothing is equipped. The autoload files themselves are never edited.
func _install_stubs() -> void:
	if Armory.get_equipped(Armory.PLAYER_ID, Enums.EquipSlot.MAIN) != &"":
		return
	if Armory.get_def(&"pistol") != null:
		# A-07 is in: equip real items. set_script() would wipe the defs Armory loaded in _ready.
		for slot: Enums.EquipSlot in SANDBOX_LOADOUT:
			Armory.equip(Armory.PLAYER_ID, slot, Armory.create_item(SANDBOX_LOADOUT[slot]))
		return
	Armory.set_script(ARMORY_STUB)
	_armory_stubbed = true


func _place_camera() -> void:
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	_camera.position = CAMERA_FOCUS + Vector3(0.0, sin(pitch), cos(pitch)) * CAMERA_DISTANCE
	_camera.look_at(CAMERA_FOCUS)
