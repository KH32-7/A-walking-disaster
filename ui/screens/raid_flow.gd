class_name RaidFlow
extends Node
## Raid screens controller (D-14). Owner: Lane D. A child of the `UI` autoload.
## Design 10 "습격·방어", 14 "습격 경보·결과", UI_RULES §9 (경보 = 안내 카드 DANGER 변형, 결과 = 정산표).
##
## Listens to EventBus raid_warning / raid_started / raid_resolved and opens:
##   raid_warning      at the base, when a raid is announced and not resolved by the end of the frame
##                     (today Colony / SceneRouter resolve stay-day and night raids in the same frame,
##                     so only the result shows; the warning appears once C-17 waits for a choice).
##   emergency_return  in the field, when B-22's EmergencyReturn node offers a return (state OFFERED).
##   raid_result       on raid_resolved. In the field ("계속 탐색") it waits for the sortie result screen
##                     and opens on top of it (10 "탈출 후 결과 화면에서 확인").
## D computes nothing: strength, prediction and outcome come from the raid info, Colony.predict_raid()
## and the resolve_raid() result.

const WARNING := &"raid_warning"
const RESULT := &"raid_result"
const EMERGENCY := &"emergency_return"

## C-17 API: the player picked 직접 방어 on the warning card (Colony.start_defense). Without it the
## direct button is disabled. 자동 판정 = Colony.resolve_raid(PLAYED), which also ends a prepared defence.
const DIRECT_API := &"start_defense"

const TYPE_NAMES := {&"swarm": "무리 습격", &"wave": "파도 습격", &"siege": "공성 습격",
	&"fog": "안개 습격", &"vine": "덩굴 침식"}
const TYPE_NOTES := {&"swarm": "한 방향, 일반 마물 위주", &"wave": "여러 방향에서 3파",
	&"siege": "공성형 마물이 벽과 문을 노림", &"fog": "물 계열, 시야 −50% (조명탑이 있으면 무효)",
	&"vine": "수풀 계열, 끝난 뒤 건물이 덩굴에 덮임"}
const DIRECTION_NAMES := {&"north": "북쪽", &"east": "동쪽", &"south": "남쪽", &"west": "서쪽"}
const OUTCOME_NAMES := ["완승", "승리", "신승", "패배"]
## Shape glyph next to every outcome word (never colour only).
const OUTCOME_GLYPHS := ["★", "●", "▲", "✕"]
const CASUALTY_NAMES := {&"injured": "다침", &"serious": "크게 다침", &"dead": "목숨을 잃음"}
const CASUALTY_GLYPHS := {&"injured": "▲", &"serious": "◆", &"dead": "✕"}

## The last raid_warning info and the last raid_resolved result (previews and late screens read them).
var last_warning: Dictionary = {}
var last_result: Dictionary = {}
var _resolved_ids: Dictionary = {}
## A result that arrived in the field, shown with the sortie result.
var _held_result: Dictionary = {}
## Opens screens only while a game scene runs (main.tscn or a preview). The headless test runner has
## no current scene, so other lanes' tests that emit raid signals do not get a pausing screen.
## true / false forces it (tests/ui/test_raid_ui.gd).
var auto_open: Variant = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.raid_warning.connect(_on_raid_warning)
	EventBus.raid_started.connect(_on_raid_started)
	EventBus.raid_resolved.connect(_on_raid_resolved)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)


# --- signal handlers ---

func _on_raid_warning(info: Dictionary) -> void:
	last_warning = info.duplicate(true)
	_after_warning.call_deferred(last_warning)


## A day raid without a guard post comes with no warning: raid_started is the first news (B-22 too).
func _on_raid_started(info: Dictionary) -> void:
	if GameState.flow_state == Enums.FlowState.FIELD:
		_after_warning.call_deferred(info.duplicate(true))


func _on_raid_resolved(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	var id := StringName(result.get("raid_id", &""))
	if id != &"":
		_resolved_ids[id] = true
	if UI.is_open(WARNING):
		UI.close(WARNING)
	if GameState.flow_state == Enums.FlowState.FIELD:
		if UI.is_open(EMERGENCY):
			UI.close(EMERGENCY)
		_held_result = last_result
		return
	_open_result.call_deferred(last_result)


func _on_flow_state_changed(state: Enums.FlowState) -> void:
	if state == Enums.FlowState.RESULT and not _held_result.is_empty():
		var r := _held_result
		_held_result = {}
		_open_result.call_deferred(r)  # after UI opened the sortie result screen
	elif state != Enums.FlowState.FIELD and UI.is_open(EMERGENCY):
		UI.close(EMERGENCY)


func _after_warning(info: Dictionary) -> void:
	if not _opens() or is_resolved(info):
		return
	if GameState.flow_state == Enums.FlowState.FIELD:
		var er := emergency_node()
		if er != null and int(er.get(&"state")) == 1 and not UI.is_open(EMERGENCY):  # EmergencyReturn.State.OFFERED
			UI.open(EMERGENCY, {"raid": info, "node": er})
		return
	if int(info.get("time", -1)) == Enums.RaidTime.DAY and GameState.flow_state != Enums.FlowState.BASE_STAY \
			and GameState.flow_state != Enums.FlowState.BASE_DAY_RAID:
		return  # a day raid while we are not at the base: the field / router handle it
	UI.open(WARNING, {"raid": info})


func _open_result(result: Dictionary) -> void:
	if _opens() and UI.has_screen(RESULT):
		UI.open(RESULT, {"result": result})


func _opens() -> bool:
	if auto_open != null:
		return bool(auto_open)
	return get_tree().current_scene != null


# --- public helpers ---

func is_resolved(raid: Dictionary) -> bool:
	var id := StringName(raid.get("raid_id", &""))
	return id != &"" and _resolved_ids.has(id)


## B-22's EmergencyReturn in the current field scene, or null.
func emergency_node() -> Node:
	return get_tree().get_first_node_in_group(&"field_emergency_return")


## The warning card's choices. AUTO = "자동 판정으로 넘기기" (player at the base: RaidMode.PLAYED, +20 %),
## direct = C-17's defense (DIRECT_API). Returns false when nothing could be called.
static func choose(raid: Dictionary, direct: bool) -> bool:
	if direct:
		if not Colony.has_method(DIRECT_API):
			return false
		Colony.call(DIRECT_API, raid)
		return true
	Colony.resolve_raid(raid, Enums.RaidMode.PLAYED)
	return true


static func can_direct() -> bool:
	return Colony.has_method(DIRECT_API)


# --- text helpers (shared by the raid screens and the defense HUD) ---

static func type_name(type: StringName) -> String:
	return TYPE_NAMES.get(type, "습격" if type == &"" else String(type))


static func type_note(type: StringName) -> String:
	return TYPE_NOTES.get(type, "")


static func directions_text(directions: Array) -> String:
	var parts := PackedStringArray()
	for d in directions:
		parts.append(DIRECTION_NAMES.get(StringName(d), String(d)))
	return "·".join(parts) if not parts.is_empty() else "방향 모름"


static func outcome_name(outcome: int) -> String:
	return OUTCOME_NAMES[clampi(outcome, 0, OUTCOME_NAMES.size() - 1)]


static func outcome_glyph(outcome: int) -> String:
	return OUTCOME_GLYPHS[clampi(outcome, 0, OUTCOME_GLYPHS.size() - 1)]


static func outcome_color(outcome: int) -> Color:
	match outcome:
		Enums.RaidOutcome.FLAWLESS:
			return UiTokens.ACCENT
		Enums.RaidOutcome.WIN:
			return UiTokens.GOOD
		Enums.RaidOutcome.NARROW:
			return UiTokens.WARN
	return UiTokens.DANGER


## "1:00" / "지금" for the time until the raid hits.
static func eta_text(raid: Dictionary) -> String:
	var sec := float(raid.get("warning_sec", 0.0))
	if sec <= 0.0:
		return "지금"
	var s := ceili(sec)
	return "%02d:%02d" % [s / 60, s % 60]


static func time_text(raid: Dictionary) -> String:
	return "낮" if int(raid.get("time", Enums.RaidTime.NIGHT)) == Enums.RaidTime.DAY else "밤"


## Building display name for a raid damage uid (Colony / BaseDB, read only).
static func building_name(uid: StringName) -> String:
	var b: Dictionary = Colony.get_building(uid)
	var def: Variant = BaseDB.get_building(StringName(b.get("def_id", &""))) if not b.is_empty() else null
	return String(def.display_name) if def != null else String(uid)


static func resident_name(id: StringName) -> String:
	var r: Dictionary = Colony.get_resident(id)
	return String(r.get("name", id))
