extends Node3D
## B-05 noise test scene. Instances field_sandbox.tscn and fires noises from keys.
## Sandbox only: debug keys use raw keycodes, not project input actions.

const ARMOR_STUB := preload("res://field/_sandbox/stubs/armory_armor_stub.gd")

const KEY_ACTIONS := {
	KEY_1: &"aim_walk", KEY_2: &"walk", KEY_3: &"sprint", KEY_4: &"roll",
	KEY_5: &"blade_attack", KEY_6: &"blunt_attack", KEY_7: &"pistol", KEY_8: &"rifle",
	KEY_9: &"shotgun", KEY_0: &"suppressed_gun",
}

@onready var _emitter: NoiseEmitter = $NoiseSource/NoiseEmitter
@onready var _label: Label = $DebugLayer/HelpLabel

var _last := "없음"


func _ready() -> void:
	# FieldSandbox (child) already ran _ready and may have installed armory_stub.gd.
	# Swap to the armor stub, which extends it, so weapons and armor both answer.
	Armory.set_script(ARMOR_STUB)
	EventBus.noise_emitted.connect(_on_noise_emitted)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if KEY_ACTIONS.has(key.keycode):
		var action: StringName = KEY_ACTIONS[key.keycode]
		var radius := _emitter.emit(action)
		if radius <= 0.0:
			_last = "%s: 0m (소리 없음)" % action
	elif key.keycode == KEY_G:
		if _emitter.is_continuous():
			_emitter.stop_continuous()
		else:
			_emitter.start_continuous(&"generator")
	elif key.keycode == KEY_R:
		_emitter.raining = not _emitter.raining
	elif key.keycode == KEY_A:
		_emitter.armory_owner_id = &"" if _emitter.armory_owner_id != &"" else Armory.PLAYER_ID
	else:
		return
	_refresh()


func _on_noise_emitted(_pos: Vector3, radius: float, source: Node) -> void:
	_last = "%s: %.2fm" % [source.name, radius]
	_refresh()


func _refresh() -> void:
	_label.text = "\n".join([
		"B-05 소음 테스트",
		"1 조준 걷기 / 2 걷기 / 3 달리기 / 4 구르기 / 5 칼 / 6 둔기",
		"7 권총 / 8 소총 / 9 산탄총 / 0 소음기 총",
		"G 발전기 켜기, 끄기: %s" % ("켜짐" if _emitter.is_continuous() else "꺼짐"),
		"R 비: %s" % ("옴" if _emitter.raining else "안 옴"),
		"A 방어구(진압 헬멧 + 고철 갑옷): %s" % ("입음" if _emitter.armory_owner_id != &"" else "벗음"),
		"마지막 소음: %s" % _last,
	])
