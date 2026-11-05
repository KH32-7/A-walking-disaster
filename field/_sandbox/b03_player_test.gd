extends Node3D
## B-03 sandbox: field sandbox + player. Run alone (F6).
## Uses the B-04 FieldCamera: Z/C rotate, +/- zoom (sandbox-registered actions).

const SandboxCameraInput := preload("res://field/_sandbox/sandbox_camera_input.gd")

@onready var _player: Player = $Player
@onready var _label: Label = $DebugLayer/PlayerLabel


func _ready() -> void:
	SandboxCameraInput.ensure()


func _process(_delta: float) -> void:
	_label.text = "Move: %s\nAiming: %s\nSpeed: %.1f m/s\nStamina: %.0f\nHealth: %.0f" % [
		Player.MoveState.keys()[_player.move_state],
		_player.is_aiming,
		Vector2(_player.velocity.x, _player.velocity.z).length(),
		_player.stamina,
		_player.health,
	]
