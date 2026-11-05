extends Node3D
## Lane B field sandbox (B-01). Run this scene alone (F6) to test field features.
## Greybox only: CSG floor, walls, cover, stairs + ramp to one raised deck.
## Debug UI lives here only (contracts.md: Control nodes allowed inside _sandbox/).

## Sandbox tunables, all in one place.
## Temporary quarter-view camera until B-04 (design 16 "아트 방향": about 55 deg down).
const CAMERA_PITCH_DEG := 55.0
const CAMERA_DISTANCE := 22.0
const CAMERA_FOCUS := Vector3.ZERO
## The sandbox stands in for a sortie, so FieldState.in_sortie() is true here.
const SIMULATE_SORTIE := true
## Sandbox loadout (docs/design/05-gear.md). Real Armory items, equipped only into empty slots.
const SANDBOX_LOADOUT := {
	Enums.EquipSlot.MAIN: &"pistol",
	Enums.EquipSlot.SUB: &"dagger",
}

@onready var _camera: Camera3D = $Camera3D
@onready var _debug_label: Label = $DebugLayer/DebugLabel


func _ready() -> void:
	_equip_sandbox_loadout()
	if SIMULATE_SORTIE:
		GameState.set_phase(Enums.Phase.SORTIE)
	_place_camera()


func _process(_delta: float) -> void:
	_debug_label.text = "FPS: %d\nPhase: %s\nFlow: %s\nIn sortie: %s\nMain: %s / Sub: %s" % [
		Engine.get_frames_per_second(),
		Enums.Phase.keys()[GameState.phase],
		Enums.FlowState.keys()[GameState.flow_state],
		FieldState.in_sortie(),
		_equipped_def(Enums.EquipSlot.MAIN),
		_equipped_def(Enums.EquipSlot.SUB),
	]


func _equip_sandbox_loadout() -> void:
	for slot: Enums.EquipSlot in SANDBOX_LOADOUT:
		if Armory.get_equipped(Armory.PLAYER_ID, slot) != &"":
			continue
		var uid := Armory.create_item(SANDBOX_LOADOUT[slot], Enums.Rarity.COMMON)
		Armory.equip(Armory.PLAYER_ID, slot, uid)


func _equipped_def(slot: Enums.EquipSlot) -> String:
	var uid := Armory.get_equipped(Armory.PLAYER_ID, slot)
	return str(Armory.get_item_stats(uid).get("def_id", "none"))


func _place_camera() -> void:
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	_camera.position = CAMERA_FOCUS + Vector3(0.0, sin(pitch), cos(pitch)) * CAMERA_DISTANCE
	_camera.look_at(CAMERA_FOCUS)
