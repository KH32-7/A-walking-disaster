extends Node3D
## B-03 sandbox: field sandbox + player. Run alone (F6).
## The sandbox camera follows the player until B-04 brings the real camera.

@onready var _player: Player = $Player
@onready var _camera: Camera3D = $FieldSandbox/Camera3D
@onready var _label: Label = $DebugLayer/PlayerLabel

var _camera_offset := Vector3.ZERO


func _ready() -> void:
	_camera_offset = _camera.global_position - _player.global_position


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position + _camera_offset
	_label.text = "Move: %s\nAiming: %s\nSpeed: %.1f m/s\nStamina: %.0f\nHealth: %.0f" % [
		Player.MoveState.keys()[_player.move_state],
		_player.is_aiming,
		Vector2(_player.velocity.x, _player.velocity.z).length(),
		_player.stamina,
		_player.health,
	]
