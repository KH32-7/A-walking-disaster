class_name SettingsCatalog
extends RefCounted
## What the settings screens show (D-15). Owner: Lane D.
## Names, descriptions and the steps a stepper walks through for every `Settings` key, plus the
## remappable actions and their Korean names. Values themselves live in `Settings` (A) and
## `InputMap` (InputSetup, A); this file never stores them.
## Design: docs/design/14-ui-controls-accessibility.md "접근성 설정", 12-progression-balance.md "난이도".
##
## Row kinds:
##   "toggle"  bool key, options [[false, "끔"], [true, "켬"]] unless the row gives its own.
##   "choice"  any key, explicit options [[value, label], ...].
##   "percent" float 0..1, options built from STEP (drawn with a bar).
##   "display" not a Settings key: applied live to the window (see SettingsScreen._display_*).
##   "binding" one InputSetup action (key + gamepad chips).
##   "button"  runs an action (id in "action").
## Rows with "heading" are section labels inside a tab.

const TABS: Array = [
	[&"graphics", "그래픽"],
	[&"audio", "소리"],
	[&"controls", "조작"],
	[&"access", "접근성"],
	[&"difficulty", "난이도"],
]

const OFF_ON := [[false, "끔"], [true, "켬"]]
const PERCENT_STEP := 0.1

## Steps for float / int keys. Placeholder numbers (가안) in one place.
const GAME_SPEED_STEPS := [0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const CAMERA_ZOOM_STEPS := [0.8, 0.9, 1.0, 1.1, 1.2]
const SUBTITLE_BG_STEPS := [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

const ROWS := {
	&"graphics": [
		{"heading": "화면"},
		{"key": &"gfx_window_mode", "kind": "display", "label": "창 모드",
			"desc": "창, 전체 화면, 테두리 없는 전체 화면 중에서 고릅니다.",
			"options": [[0, "창"], [1, "전체 화면"], [2, "테두리 없음"]]},
		{"key": &"gfx_vsync", "kind": "display", "label": "수직 동기화",
			"desc": "화면 찢어짐을 막습니다. 끄면 입력이 조금 빨라지지만 화면이 찢어질 수 있어요.",
			"options": OFF_ON},
		{"key": &"gfx_max_fps", "kind": "display", "label": "최대 프레임",
			"desc": "초당 그리는 화면 수의 상한입니다. 노트북이라면 낮출수록 배터리가 오래갑니다.",
			"options": [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [0, "제한 없음"]]},
		{"key": &"gfx_render_scale", "kind": "display", "label": "3D 해상도",
			"desc": "3D 장면을 그리는 해상도 배율입니다. 글자와 메뉴는 늘 선명하게 그립니다.",
			"options": [[0.5, "50%"], [0.67, "67%"], [0.75, "75%"], [0.85, "85%"], [1.0, "100%"]]},
	],
	&"audio": [
		{"heading": "음량"},
		{"key": &"volume_master", "kind": "percent", "label": "전체 음량", "desc": "모든 소리의 크기입니다."},
		{"key": &"volume_music", "kind": "percent", "label": "음악", "desc": "기지와 필드 음악의 크기입니다."},
		{"key": &"volume_sfx", "kind": "percent", "label": "효과음",
			"desc": "총소리, 발소리, 마물 소리 같은 효과음의 크기입니다."},
		{"key": &"volume_voice", "kind": "percent", "label": "음성", "desc": "무전과 대사 음성의 크기입니다."},
		{"heading": "AI 무전병"},
		{"key": &"ai_radio_frequency", "kind": "choice", "label": "안내 빈도",
			"desc": "무전병이 필드에서 얼마나 자주 말을 거는지 정합니다. 위험 경보는 끔이어도 들립니다.",
			"options": [[0, "끔"], [1, "필요할 때"], [2, "자주"]]},
		{"key": &"radio_voice", "kind": "toggle", "label": "무전 음성",
			"desc": "무전을 소리로도 들려줍니다. 끄면 자막만 나옵니다."},
	],
	&"controls": [
		{"heading": "조작 보조"},
		{"key": &"aim_assist", "kind": "choice", "label": "조준 보조",
			"desc": "가까운 마물 쪽으로 조준을 살짝 끌어당깁니다.",
			"options": [[0, "끔"], [1, "약"], [2, "중간"], [3, "강"]]},
		{"key": &"toggle_aim", "kind": "toggle", "label": "조준 토글",
			"desc": "켜면 조준 키를 한 번 눌러 켜고, 다시 눌러 끕니다. 끄면 누르고 있는 동안만 조준합니다."},
		{"key": &"toggle_sprint", "kind": "toggle", "label": "달리기 토글",
			"desc": "켜면 달리기 키를 한 번 눌러 켜고, 다시 눌러 끕니다."},
		{"key": &"toggle_block", "kind": "toggle", "label": "막기 토글",
			"desc": "켜면 근접 막기를 한 번 눌러 켜고, 다시 눌러 끕니다."},
		{"key": &"hold_instead_mash", "kind": "toggle", "label": "연타 대신 길게 누르기",
			"desc": "여러 번 눌러야 하는 행동을 길게 누르기 한 번으로 바꿉니다."},
		{"key": &"one_hand", "kind": "toggle", "label": "한 손 조작",
			"desc": "마우스나 키보드 한쪽만으로 할 수 있게 자주 쓰는 행동을 모읍니다."},
		{"heading": "키 배치"},
		# Binding rows are added from ACTIONS by the screen.
		{"key": &"bindings_reset", "kind": "button", "label": "모든 키를 기본값으로",
			"desc": "키보드, 마우스와 게임패드의 키 배치를 처음 상태로 되돌립니다.", "action": &"reset_bindings",
			"button": "되돌리기"},
	],
	&"access": [
		{"heading": "자막"},
		{"key": &"subtitles", "kind": "toggle", "label": "자막", "desc": "무전과 대사를 화면 아래에 글로 보여 줍니다."},
		{"key": &"subtitle_size", "kind": "choice", "label": "자막 크기", "desc": "자막 글자 크기입니다. 메뉴 글자와 따로 정합니다.",
			"options": [[0, "작게"], [1, "보통"], [2, "크게"]]},
		{"key": &"subtitle_bg_alpha", "kind": "choice", "label": "자막 배경",
			"desc": "자막 뒤 어두운 판의 진하기입니다. 밝은 장면에서 글이 잘 안 보이면 올리세요."},
		{"key": &"subtitle_speaker", "kind": "toggle", "label": "화자 이름",
			"desc": "누가 말하는지 이름을 노란색 굵은 글자로 붙입니다."},
		{"heading": "소리 시각화"},
		{"key": &"sound_arrows", "kind": "toggle", "label": "소리 방향 화살표",
			"desc": "화면 밖에서 난 소리와 마물의 방향을 화면 가장자리 화살표로 알려 줍니다."},
		{"key": &"sound_icons", "kind": "toggle", "label": "중요 효과음 아이콘",
			"desc": "경보, 폭발 같은 중요한 소리가 나면 아이콘과 글로도 알려 줍니다."},
		{"heading": "색"},
		{"key": &"color_filter", "kind": "choice", "label": "색약 필터",
			"desc": "화면 전체 색을 구분하기 쉽게 바꿉니다. 등급, 속성은 필터와 상관없이 늘 모양으로도 구분합니다.",
			"options": [[0, "끔"], [1, "적색약"], [2, "녹색약"], [3, "청색약"]]},
		{"key": &"high_contrast", "kind": "toggle", "label": "고대비",
			"desc": "판을 더 진하게, 선과 보조 글자를 더 밝게 합니다. HUD 글자에 검은 외곽선을 둘러요."},
		{"heading": "화면"},
		{"key": &"reduce_shake", "kind": "toggle", "label": "흔들림 줄이기",
			"desc": "화면 흔들림과 카메라 회전 연출을 없애고 바로 바꿉니다."},
		{"key": &"reduce_flash", "kind": "toggle", "label": "깜빡임, 섬광 줄이기",
			"desc": "번쩍임과 무지개빛 효과를 끄고 부드러운 단색 표시로 바꿉니다. 메뉴 뒤 흐림도 줄입니다."},
		{"key": &"camera_zoom", "kind": "choice", "label": "카메라 확대", "desc": "필드 카메라를 기본보다 가깝게 또는 멀리 둡니다."},
		{"heading": "글"},
		{"key": &"text_size", "kind": "choice", "label": "글자 크기", "desc": "메뉴와 HUD의 글자 크기입니다. 바로 바뀝니다.",
			"options": [[0, "작게"], [1, "보통"], [2, "크게"]]},
		{"key": &"dyslexic_font", "kind": "toggle", "label": "읽기 쉬운 글꼴",
			"desc": "글자 모양이 또렷한 글꼴로 바꿉니다."},
		{"key": &"tts_menu", "kind": "toggle", "label": "메뉴 읽어주기",
			"desc": "고른 메뉴 항목과 바뀐 값을 소리 내어 읽어 줍니다(운영체제 음성)."},
		{"heading": "속도"},
		{"key": &"game_speed", "kind": "choice", "label": "필드 게임 속도",
			"desc": "필드에서 시간이 흐르는 빠르기입니다. 느리게 하면 마물과 탄환도 함께 느려집니다."},
	],
	# Difficulty rows are built from Settings.PRESETS by the screen (difficulty_rows()).
	&"difficulty": [],
}

## Difficulty item names (Settings.DIFFICULTY_KEYS). Values come from Settings.PRESETS.
const DIFFICULTY_ITEMS := {
	&"monster_mult": {"label": "마물 체력, 공격", "desc": "마물의 체력과 공격력 배율입니다."},
	&"raid_mult": {"label": "습격 강도", "desc": "밤 습격에 오는 마물의 세기 배율입니다."},
	&"permadeath": {"label": "영구 사망", "desc": "끄면 주민이 죽는 대신 7일 동안 중상으로 누워 있습니다.",
		"options": [[true, "켬"], [false, "끔 (중상)"]]},
	&"strand_days": {"label": "고립 기한", "desc": "필드에 남겨진 동행자가 버틸 수 있는 날 수입니다."},
	&"keep_bag_on_down": {"label": "쓰러졌을 때 가방", "desc": "쓰러졌을 때 가방에 든 것을 지킬지 정합니다.",
		"options": [[false, "잃음"], [true, "유지"]]},
	&"instant_loot": {"label": "루팅 확인", "desc": "상자를 열 때 칸마다 확인하는 시간을 없앱니다.",
		"options": [[false, "칸마다 확인"], [true, "즉시"]]},
}

const PRESET_NAMES := {&"story": "이야기", &"normal": "보통", &"hard": "어려움", &"hardcore": "하드코어",
	&"custom": "직접 정함"}
const PRESET_DESC := {
	&"story": "보호 모드. 마물과 습격이 약하고, 주민이 죽지 않으며, 쓰러져도 가방을 지킵니다.",
	&"normal": "기획한 그대로의 난이도입니다.",
	&"hard": "마물과 습격이 강하고 고립 기한이 짧습니다.",
	&"hardcore": "어려움보다 습격이 더 세고, 플레이어가 죽으면 저장이 지워집니다. 새 게임에서만 고릅니다.",
	&"custom": "항목을 따로 바꾼 상태입니다.",
}

## Remappable actions in screen order (InputSetup.DEFAULTS ids) and their names.
const ACTIONS := [
	[&"move_up", "위로 이동"], [&"move_down", "아래로 이동"], [&"move_left", "왼쪽으로 이동"],
	[&"move_right", "오른쪽으로 이동"], [&"attack", "공격, 사격"], [&"aim", "조준, 막기"],
	[&"aim_up", "조준 위"], [&"aim_down", "조준 아래"], [&"aim_left", "조준 왼쪽"], [&"aim_right", "조준 오른쪽"],
	[&"dodge", "구르기"], [&"sprint", "달리기"], [&"reload", "재장전"], [&"interact", "상호작용"],
	[&"weapon_1", "무기 1"], [&"weapon_2", "무기 2"], [&"weapon_swap", "무기 교체"],
	[&"item_1", "소모품 1"], [&"item_2", "소모품 2"], [&"item_3", "소모품 3"], [&"item_4", "소모품 4"],
	[&"skill_q", "스킬 1"], [&"skill_e", "스킬 2"], [&"essence_release", "정수 해방"],
	[&"companion_command", "동행 명령"], [&"camera_rotate_left", "카메라 왼쪽으로 돌리기"],
	[&"camera_rotate_right", "카메라 오른쪽으로 돌리기"], [&"camera_zoom_in", "카메라 가까이"],
	[&"camera_zoom_out", "카메라 멀리"], [&"bag", "가방"], [&"map", "지도"], [&"pause", "일시정지"],
]

## The quick accessibility screen (title). Design 14: subtitles, sound visualisation, colour,
## toggles, protect mode — plus text size / contrast / shake that change how the menus read.
const QUICK_KEYS: Array[StringName] = [&"text_size", &"high_contrast", &"subtitles", &"subtitle_size",
	&"sound_arrows", &"color_filter", &"reduce_shake", &"reduce_flash", &"toggle_aim",
	&"toggle_sprint", &"tts_menu", &"protect_mode"]
const PROTECT_ROW := {"key": &"protect_mode", "kind": "protect", "label": "보호 모드",
	"desc": "이야기 난이도입니다. 마물과 습격이 약하고, 주민이 죽지 않고, 쓰러져도 가방을 지킵니다. 항목은 나중에 설정 → 난이도에서 따로 바꿀 수 있어요.",
	"options": [[false, "끔"], [true, "켬"]]}


## Row dict for a key in any tab (or the quick screen's protect row). Fills defaults for options.
static func row(key: StringName) -> Dictionary:
	if key == &"protect_mode":
		return PROTECT_ROW
	for tab: StringName in ROWS:
		for r: Dictionary in ROWS[tab]:
			if r.get("key", &"") == key:
				return with_options(r)
	return {}


static func tab_rows(tab: StringName) -> Array:
	var out: Array = []
	for r: Dictionary in ROWS.get(tab, []):
		out.append(with_options(r))
	return out


## Adds the options a row leaves out: toggles get 끔/켬, step tables get formatted labels.
static func with_options(r: Dictionary) -> Dictionary:
	if r.has("heading") or r.has("options"):
		return r
	var out := r.duplicate()
	match String(r.get("kind", "")):
		"toggle":
			out["options"] = OFF_ON
		"percent":
			var opts: Array = []
			for i in roundi(1.0 / PERCENT_STEP) + 1:
				var v := snappedf(i * PERCENT_STEP, 0.01)
				opts.append([v, "%d" % roundi(v * 100.0)])
			out["options"] = opts
		"choice":
			match r.get("key", &""):
				&"game_speed":
					out["options"] = _mult_options(GAME_SPEED_STEPS)
				&"camera_zoom":
					out["options"] = _mult_options(CAMERA_ZOOM_STEPS)
				&"subtitle_bg_alpha":
					var opts: Array = []
					for v: float in SUBTITLE_BG_STEPS:
						opts.append([v, "%d%%" % roundi(v * 100.0)])
					out["options"] = opts
	return out


static func _mult_options(steps: Array) -> Array:
	var opts: Array = []
	for v: float in steps:
		opts.append([v, mult_text(v)])
	return opts


static func mult_text(v: float) -> String:
	return "×%s" % String.num(v, 2)


## Difficulty item rows. Options are every distinct value the presets use for the key, so the
## screen never invents a number (Settings.PRESETS is the source).
static func difficulty_rows() -> Array:
	var out: Array = []
	for key: StringName in DIFFICULTY_ITEMS:
		var item: Dictionary = DIFFICULTY_ITEMS[key]
		var r := {"key": key, "kind": "choice", "label": item.label,
			"desc": "%s 따로 바꾸면 난이도 이름이 ‘%s’으로 바뀌어요." % [item.desc, PRESET_NAMES[&"custom"]]}
		if item.has("options"):
			r["options"] = item.options
		else:
			var vals: Array = []
			for id: StringName in Settings.PRESETS:
				var v: Variant = Settings.PRESETS[id].get(key)
				if v != null and not v in vals:
					vals.append(v)
			vals.sort()
			var opts: Array = []
			for v: Variant in vals:
				opts.append([v, _difficulty_value_text(key, v)])
			r["options"] = opts
		out.append(r)
	return out


static func _difficulty_value_text(key: StringName, v: Variant) -> String:
	if key == &"strand_days":
		return "없음" if int(v) == 0 else "%d일" % int(v)
	if typeof(v) == TYPE_FLOAT:
		return mult_text(v)
	return str(v)


## Label of the option matching `value`, or a formatted value when no option matches.
static func value_text(r: Dictionary, value: Variant) -> String:
	var opts: Array = r.get("options", [])
	var i := option_index(opts, value)
	if i >= 0:
		return String(opts[i][1])
	if typeof(value) == TYPE_FLOAT:
		return String.num(value, 2)
	return str(value)


## Index of `value` in options; floats match approximately. -1 if none.
static func option_index(opts: Array, value: Variant) -> int:
	for i in opts.size():
		var o: Variant = opts[i][0]
		if typeof(o) == TYPE_FLOAT or typeof(value) == TYPE_FLOAT:
			if typeof(value) in [TYPE_FLOAT, TYPE_INT] and typeof(o) in [TYPE_FLOAT, TYPE_INT] \
					and absf(float(o) - float(value)) < 0.005:
				return i
		elif o == value:
			return i
	return -1


## Nearest option index for a value that is not one of the steps (e.g. set elsewhere).
static func nearest_index(opts: Array, value: Variant) -> int:
	var i := option_index(opts, value)
	if i >= 0 or opts.is_empty():
		return i
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		var best := 0
		for j in opts.size():
			if typeof(opts[j][0]) in [TYPE_FLOAT, TYPE_INT] \
					and absf(float(opts[j][0]) - float(value)) < absf(float(opts[best][0]) - float(value)):
				best = j
		return best
	return 0


## Remappable action ids: ACTIONS order, then any InputSetup action added later (raw name).
static func action_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for a: Array in ACTIONS:
		out.append(a[0])
	for a: StringName in InputSetup.DEFAULTS:
		if not a in out:
			out.append(a)
	return out


static func action_name(action: StringName) -> String:
	for a: Array in ACTIONS:
		if a[0] == action:
			return String(a[1])
	return String(action)


# ---------------- input event names ----------------

const MOUSE_NAMES := {MOUSE_BUTTON_LEFT: "마우스 왼쪽", MOUSE_BUTTON_RIGHT: "마우스 오른쪽",
	MOUSE_BUTTON_MIDDLE: "휠 클릭", MOUSE_BUTTON_WHEEL_UP: "휠 위", MOUSE_BUTTON_WHEEL_DOWN: "휠 아래",
	MOUSE_BUTTON_XBUTTON1: "마우스 4", MOUSE_BUTTON_XBUTTON2: "마우스 5"}
const PAD_BUTTON_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "LS",
	JOY_BUTTON_RIGHT_STICK: "RS", JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→"}
const KEY_SHORT := {"Escape": "Esc", "Space": "Space", "Shift": "Shift", "Ctrl": "Ctrl", "Enter": "Enter"}


## Short display text of one binding: "W", "마우스 왼쪽", "RT", "왼쪽 스틱 ↑".
static func event_text(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode
		var s := OS.get_keycode_string(code)
		return String(KEY_SHORT.get(s, s))
	if ev is InputEventMouseButton:
		return String(MOUSE_NAMES.get(ev.button_index, "마우스 %d" % ev.button_index))
	if ev is InputEventJoypadButton:
		return String(PAD_BUTTON_NAMES.get(ev.button_index, "버튼 %d" % ev.button_index))
	if ev is InputEventJoypadMotion:
		match ev.axis:
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
			JOY_AXIS_LEFT_X:
				return "왼쪽 스틱 " + ("→" if ev.axis_value > 0 else "←")
			JOY_AXIS_LEFT_Y:
				return "왼쪽 스틱 " + ("↓" if ev.axis_value > 0 else "↑")
			JOY_AXIS_RIGHT_X:
				return "오른쪽 스틱 " + ("→" if ev.axis_value > 0 else "←")
			JOY_AXIS_RIGHT_Y:
				return "오른쪽 스틱 " + ("↓" if ev.axis_value > 0 else "↑")
	return "?"


## Identity used for conflicts: same physical key / button / axis direction = same binding.
static func event_id(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "k%d" % (ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode)
	if ev is InputEventMouseButton:
		return "m%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "b%d" % ev.button_index
	if ev is InputEventJoypadMotion:
		return "a%d%s" % [ev.axis, "+" if ev.axis_value > 0 else "-"]
	return ""


static func is_pad(ev: InputEvent) -> bool:
	return ev is InputEventJoypadButton or ev is InputEventJoypadMotion


## First binding of an action for one device class (keyboard·mouse or gamepad), or null.
static func binding(action: StringName, pad: bool) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if is_pad(ev) == pad:
			return ev
	return null


## Same as InputSetup._make_event (A), for showing / restoring one action's default keys.
static func spec_event(spec: Dictionary) -> InputEvent:
	if spec.has("key"):
		var k := InputEventKey.new()
		k.physical_keycode = spec["key"]
		return k
	if spec.has("mouse"):
		var m := InputEventMouseButton.new()
		m.button_index = spec["mouse"]
		return m
	if spec.has("joy_button"):
		var b := InputEventJoypadButton.new()
		b.button_index = spec["joy_button"]
		return b
	var a := InputEventJoypadMotion.new()
	a.axis = spec["joy_axis"][0]
	a.axis_value = spec["joy_axis"][1]
	return a


## Default binding text of an action for one device class ("" if none).
static func default_binding_text(action: StringName, pad: bool) -> String:
	for spec: Dictionary in InputSetup.DEFAULTS.get(action, []):
		var ev := spec_event(spec)
		if is_pad(ev) == pad:
			return event_text(ev)
	return ""


## Window / render values the graphics tab starts from (Backspace resets to these).
const DISPLAY_DEFAULTS := {&"gfx_window_mode": 0, &"gfx_vsync": true, &"gfx_max_fps": 0, &"gfx_render_scale": 1.0}
