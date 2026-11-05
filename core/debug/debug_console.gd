extends Node
## Autoload `DebugConsole`. Owner: Lane A (task A-03).
## Developer cheat console, toggled with the backtick key (`). Pauses the game while open.
## Only active in debug builds: in a release export (OS.is_debug_build() == false) it never opens,
## execute() does nothing and `godmode` stays false.
##
## Other lanes add their own commands from their scripts (no need to edit this file):
##   DebugConsole.register(&"spawn", func(args: PackedStringArray): ..., "spawn <monster_id>")
## The callable receives the words after the command name and may return a String to print.
## Registering an existing name replaces it (Lane C replaces the `raid` / `resident` placeholders).

## Lane B reads this to ignore damage to the player. Always false in release builds.
var godmode := false

var _enabled := OS.is_debug_build()
## name -> {"callable": Callable, "help": String}
var _commands: Dictionary = {}
var _history: PackedStringArray = []
var _history_index := 0
var _was_paused := false

var _layer: CanvasLayer
var _log: RichTextLabel
var _line: LineEdit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _enabled:
		set_process_input(false)
		return
	_register_builtins()
	_build_ui()
	# Live player animation speed sliders (debug builds only): \ key or `anim`.
	var anim_panel: Node = preload("res://core/debug/anim_tuning_panel.gd").new()
	add_child(anim_panel)
	register(&"anim", func(_args: PackedStringArray) -> String:
		anim_panel.call(&"toggle")
		return "애니메이션 속도 패널 (\\ 키로도 열고 닫음)", "anim - 애니메이션 속도 패널 열기/닫기")


func is_open() -> bool:
	return _layer != null and _layer.visible


func register(command: StringName, callable: Callable, help: String = "") -> void:
	if not _enabled:
		return
	_commands[command] = {"callable": callable, "help": help}


## Runs one command line and returns what it printed. Also used by tests.
func execute(line: String) -> String:
	if not _enabled:
		return ""
	var words := line.strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	var command := StringName(words[0].to_lower())
	if not _commands.has(command):
		return "알 수 없는 명령: %s (help 참고)" % command
	var result: Variant = _commands[command]["callable"].call(words.slice(1))
	return "" if result == null else str(result)


# --- UI ---

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_QUOTELEFT:
		_set_open(not is_open())
		get_viewport().set_input_as_handled()
	elif is_open() and key.physical_keycode == KEY_UP:
		_browse_history(-1)
		get_viewport().set_input_as_handled()
	elif is_open() and key.physical_keycode == KEY_DOWN:
		_browse_history(1)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	if open == is_open():
		return
	_layer.visible = open
	if open:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_line.clear()
		_line.grab_focus()
	else:
		_line.release_focus()
		get_tree().paused = _was_paused


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	_layer.visible = false
	add_child(_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.anchor_bottom = 0.4
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.85)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.bbcode_enabled = false
	box.add_child(_log)

	_line = LineEdit.new()
	_line.placeholder_text = "명령 입력 (help)"
	_line.text_submitted.connect(_on_submitted)
	box.add_child(_line)

	_print("디버그 콘솔. help 로 명령 목록을 본다.")


func _on_submitted(line: String) -> void:
	_line.clear()
	if line.strip_edges().is_empty():
		return
	_history.append(line)
	_history_index = _history.size()
	_print("> " + line)
	var output := execute(line)
	if output != "":
		_print(output)


func _browse_history(step: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + step, 0, _history.size())
	_line.text = _history[_history_index] if _history_index < _history.size() else ""
	_line.caret_column = _line.text.length()


func _print(text: String) -> void:
	if _log != null:
		_log.add_text(text + "\n")


# --- Built-in commands ---

func _register_builtins() -> void:
	register(&"help", _cmd_help, "help - 명령 목록")
	register(&"clear", _cmd_clear, "clear - 화면 지우기")
	register(&"res", _cmd_res, "res <resource_id> <n> - 창고 자원 더하기/빼기")
	register(&"day", _cmd_day, "day next - 오늘 남은 단계를 기본 경로로 넘겨 다음 날 아침으로")
	register(&"next", _cmd_next, "next [region_id] - 하루 흐름 한 단계 진행 (SceneRouter.advance, 출격 준비에서는 지역 선택)")
	register(&"phase", _cmd_phase, "phase <%s>" % "|".join(Enums.Phase.keys()).to_lower())
	register(&"flow", _cmd_flow, "flow <%s>" % "|".join(Enums.FlowState.keys()).to_lower())
	register(&"godmode", _cmd_godmode, "godmode [on|off] - 플레이어 무적")
	register(&"weather", _cmd_weather, "weather <clear|rain> - 오늘 날씨")
	register(&"radio", _cmd_radio, "radio <trigger_id|morning> - 무전 한 줄 (쿨다운 무시 안 함)")
	register(&"give", _cmd_give, "give <item_id> [rarity 0-4] - 장비를 무기고에 지급")
	register(&"raid", _placeholder.bind("레인 C"), "raid now - 즉시 습격 (레인 C가 등록)")
	register(&"resident", _placeholder.bind("레인 C"), "resident add - 주민 추가 (레인 C가 등록)")


func _cmd_help(_args: PackedStringArray) -> String:
	# StringName sorts by pointer, so sort as plain strings for an alphabetical list.
	var names := PackedStringArray()
	for command: StringName in _commands:
		names.append(String(command))
	names.sort()
	var lines := PackedStringArray()
	for command in names:
		var help: String = _commands[command]["help"]
		lines.append(help if help != "" else String(command))
	return "\n".join(lines)


func _cmd_clear(_args: PackedStringArray) -> void:
	if _log != null:
		_log.clear()


func _cmd_res(args: PackedStringArray) -> String:
	if args.size() != 2 or not args[1].is_valid_int():
		return "사용법: res <resource_id> <n>"
	var id := StringName(args[0])
	var result := Economy.apply_detailed({id: args[1].to_int()})
	if not result["ok"]:
		return "실패: %s 이(가) 0 아래로 내려감 (현재 %d)" % [id, Economy.get_amount(id)]
	var line := "%s = %d" % [id, Economy.get_amount(id)]
	if result["discarded"].has(id):
		line += " (창고 한도 %d, %d 버려짐)" % [Economy.storage_cap(), result["discarded"][id]]
	return line


func _cmd_day(args: PackedStringArray) -> String:
	if args.size() != 1 or args[0] != "next":
		return "사용법: day next"
	var start_day := GameState.day
	for i in 20:
		if GameState.day > start_day and SceneRouter.state() == Enums.FlowState.BASE_MORNING:
			break
		if not SceneRouter.advance():
			return "진행 실패 (%s)" % Enums.FlowState.keys()[SceneRouter.state()]
	return "%d일차 아침" % GameState.day


func _cmd_next(args: PackedStringArray) -> String:
	var region := StringName(args[0]) if args.size() > 0 else &""
	if not SceneRouter.advance(region):
		return "진행 실패 (%s)" % Enums.FlowState.keys()[SceneRouter.state()]
	return "flow = %s, %d일차" % [Enums.FlowState.keys()[SceneRouter.state()], GameState.day]


func _cmd_phase(args: PackedStringArray) -> String:
	var key := args[0].to_upper() if args.size() == 1 else ""
	if not Enums.Phase.has(key):
		return "사용법: " + _commands[&"phase"]["help"]
	GameState.set_phase(Enums.Phase[key])
	return "phase = " + key


func _cmd_flow(args: PackedStringArray) -> String:
	var key := args[0].to_upper() if args.size() == 1 else ""
	if not Enums.FlowState.has(key):
		return "사용법: " + _commands[&"flow"]["help"]
	GameState.set_flow_state(Enums.FlowState[key])
	return "flow = %s (phase %s)" % [key, Enums.Phase.keys()[GameState.phase]]


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty() or args.size() > 2 or (args.size() == 2 and not args[1].is_valid_int()):
		return "사용법: give <item_id> [rarity 0-4]"
	if Armory.get_def(StringName(args[0])) == null:
		return "없는 아이템: %s" % args[0]
	var rarity := args[1].to_int() if args.size() == 2 else -1
	var uid := Armory.create_item(StringName(args[0]), rarity)
	var item := Armory.get_item(uid)
	return "%s 지급 (%s, 부가 옵션 %d개)" % [uid, Enums.Rarity.keys()[item.rarity], item.affixes.size()]


func _cmd_weather(args: PackedStringArray) -> String:
	var key := args[0].to_upper() if args.size() == 1 else ""
	if not Enums.Weather.has(key):
		return "사용법: weather <clear|rain>"
	GameState.set_weather(Enums.Weather[key])
	return "weather = " + key


func _cmd_radio(args: PackedStringArray) -> String:
	if args.size() != 1:
		return "사용법: radio <%s|morning>" % "|".join(Radio.triggers.keys())
	if args[0] == "morning":
		Radio.morning_broadcast()
		return "아침 방송"
	if not Radio.triggers.has(StringName(args[0])):
		return "없는 무전: %s" % args[0]
	return "보냄" if Radio.say(StringName(args[0]), {"direction": "북쪽", "minutes": 3, "region": "침수 상가", "range": "승리 쪽", "day": GameState.day}) else "막힘 (쿨다운·빈도·1회 제한)"


func _cmd_godmode(args: PackedStringArray) -> String:
	if args.is_empty():
		godmode = not godmode
	elif args[0] == "on" or args[0] == "off":
		godmode = args[0] == "on"
	else:
		return "사용법: godmode [on|off]"
	return "godmode " + ("on" if godmode else "off")


func _placeholder(_args: PackedStringArray, lane: String) -> String:
	return "아직 없음: %s 에서 DebugConsole.register 로 구현 예정" % lane
