extends Node
## Autoload `UI`. Owner: Lane D (D-01). Rules: ui/UI_RULES.md.
## Opens/closes screens and owns the HUD layer. Gameplay lanes call `UI.open(&"bag")`
## etc.; they never add Control nodes to the tree themselves (sandbox debug UI excepted).
## Design reference: docs/design/14-ui-controls-accessibility.md
##
## Layers (CanvasLayer):  hud (10)  <  screens (20)  <  overlay (30: subtitles, toasts)
## Screen scenes may implement:  open_with(args: Dictionary)  and  on_closing()
## open_with runs before _ready on the first open, and again (in the tree) on a re-open.

signal screen_opened(screen_id: StringName)
signal screen_closed(screen_id: StringName)
## The build panel asked to place a building (D-06). Lane C starts the grid placement preview
## (C-03) and calls Colony.place_building() when the player confirms.
signal build_requested(def_id: StringName)
## The site card asked to move a construction site / building (D-06 재설계 ③). Lane C runs
## BuildMode.start_move(uid) and then show_build_place().
signal build_move_requested(uid: StringName)
## The theme was rebuilt (text size / high contrast changed). Screens normally just inherit it.
signal theme_changed(theme: Theme)

const SCREENS_DIR := "res://data/ui/screens"

var theme: Theme
## Root Controls for each layer. Put HUD widgets under `hud`, never under `screens`.
var hud: Control
var screens: Control
var overlay: Control
var subtitle: SubtitleBox
## D-15: full-screen colour-blind filter (Settings.color_filter) and menu TTS (Settings.tts_menu).
var color_filter: ColorFilterLayer
var menu_reader: MenuReader

var _defs: Dictionary = {}  # StringName -> ScreenDef
var _scenes: Dictionary = {}  # StringName -> PackedScene (registered in code)
var _stack: Array[Dictionary] = []  # [{id, node, def}], last = top
var _paused_by_ui := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = _make_layer(&"HudLayer", 10)
	screens = _make_layer(&"ScreenLayer", 20)
	overlay = _make_layer(&"OverlayLayer", 30)
	subtitle = SubtitleBox.new()
	subtitle.name = &"Subtitle"
	overlay.add_child(subtitle)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE)
	subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle.offset_bottom = -200
	# D-15: colour-blind filter above every layer, menu TTS on focus changes.
	color_filter = ColorFilterLayer.new()
	color_filter.name = &"ColorFilterLayer"
	add_child(color_filter)
	menu_reader = MenuReader.new()
	menu_reader.name = &"MenuReader"
	add_child(menu_reader)
	_add_d16_nodes()
	_rebuild_theme()
	_load_defs()
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.radio_message.connect(_on_radio_message)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
	EventBus.sortie_started.connect(_on_sortie_started)
	_last_flow = GameState.flow_state
	Colony.night_events_ready.connect(_on_night_events_ready)
	_connect_loss()
	raid_flow = RaidFlow.new()
	raid_flow.name = &"RaidFlow"
	add_child(raid_flow)
	resident_events = ResidentEventFlow.new()  # #125: 아이 맞이·이름 짓기·편견 소문
	resident_events.name = &"ResidentEventFlow"
	add_child(resident_events)
	_on_flow_state_changed(GameState.flow_state)


## D-16: explored-area memory for the field map, notification toasts while no HUD shows them,
## and the radio voice (TTS).
var explore: FieldExplore
var notice_toast: NoticeToast
var radio_voice: RadioVoice


func _add_d16_nodes() -> void:
	explore = FieldExplore.new()
	explore.name = &"FieldExplore"
	add_child(explore)
	radio_voice = RadioVoice.new()
	radio_voice.name = &"RadioVoice"
	add_child(radio_voice)
	notice_toast = NoticeToast.new()
	notice_toast.name = &"NoticeToast"
	overlay.add_child(notice_toast)
	notice_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
	notice_toast.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	notice_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notice_toast.offset_right = -52
	notice_toast.offset_bottom = -22


## The field HUD (D-04). Created on first use, shown only in FlowState.FIELD.
var field_hud: FieldHud
## Noise rings, monster ?/!, edge arrows (D-05). Lives with the field HUD.
var world_markers: WorldMarkers
## Aim reticle + hit markers in place of the OS cursor (B-28). Lives with the field HUD.
var aim_reticle: AimReticle


func show_field_hud(on: bool) -> void:
	if on and field_hud == null:
		world_markers = WorldMarkers.new()
		world_markers.name = &"WorldMarkers"
		hud.add_child(world_markers)  # under the HUD widgets
		field_hud = FieldHud.new()
		field_hud.name = &"FieldHud"
		hud.add_child(field_hud)
		aim_reticle = AimReticle.new()
		aim_reticle.name = &"AimReticle"
		hud.add_child(aim_reticle)  # over the HUD widgets
	for n: Control in [field_hud, world_markers]:
		if n != null:
			n.visible = on
			n.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if aim_reticle != null:
		aim_reticle.visible = on
		# Always: it must give the cursor back while the game is paused under a screen.
		aim_reticle.process_mode = Node.PROCESS_MODE_ALWAYS if on else Node.PROCESS_MODE_DISABLED


## Base HUD (D-06): top bar, notifications, bottom menu. Shown in the base flow states.
var base_hud: BaseHud
const BASE_STATES := [Enums.FlowState.BASE_MORNING, Enums.FlowState.BASE_STAY, Enums.FlowState.EVENING,
	Enums.FlowState.NIGHT]


func show_base_hud(on: bool) -> void:
	if on and base_hud == null:
		base_hud = BaseHud.new()
		base_hud.name = &"BaseHud"
		hud.add_child(base_hud)
	if base_hud != null:
		base_hud.visible = on
		base_hud.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		if on:
			base_hud.refresh()


## Raid screens (D-14): warning / result / emergency return, and the direct defense HUD.
var build_place_hud: BuildPlaceHud


## D-06 재설계 ②놓기: overlay for a running BuildMode (단계 띠, 고른 건물, 커서 카드, 키 안내).
## Hides the base HUD while it is up. On placed → opens the site card (③); on cancel → back to the list.
func show_build_place(build_mode: Node) -> void:
	if is_instance_valid(build_place_hud):
		build_place_hud.queue_free()
	build_place_hud = BuildPlaceHud.new()
	build_place_hud.name = &"BuildPlaceHud"
	hud.add_child(build_place_hud)
	build_place_hud.bind(build_mode)
	if base_hud != null:
		base_hud.visible = false
	build_place_hud.tree_exited.connect(func() -> void:
		if base_hud != null and GameState.flow_state in BASE_STATES:
			base_hud.visible = true)


var raid_flow: RaidFlow
var resident_events: ResidentEventFlow
var raid_hud: RaidDefenseHud
const RAID_STATES := [Enums.FlowState.BASE_DAY_RAID, Enums.FlowState.NIGHT_RAID]


func show_raid_hud(on: bool) -> void:
	if on and raid_hud == null:
		raid_hud = RaidDefenseHud.new()
		raid_hud.name = &"RaidDefenseHud"
		hud.add_child(raid_hud)
	if raid_hud != null:
		raid_hud.visible = on
		raid_hud.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


## Loot hook (D-08): when the player's current interactable (Player.interacting(), B-03) is a
## container that finishes opening, the bag screen opens with it. Tab opens the bag alone.
var _watched_container: Node = null


func _process(_delta: float) -> void:
	if GameState.flow_state != Enums.FlowState.FIELD:
		return
	var p := get_tree().get_first_node_in_group(&"player")
	if p == null or not p.has_method(&"interacting"):
		return
	var c: Node = p.call(&"interacting")
	if c != _watched_container:
		if _watched_container != null and is_instance_valid(_watched_container) 				and _watched_container.is_connected(&"opened", _on_container_opened):
			_watched_container.disconnect(&"opened", _on_container_opened)
		_watched_container = c
		if c != null and c.has_signal(&"opened"):
			c.connect(&"opened", _on_container_opened)


func _on_container_opened(_slot_count: int) -> void:
	open(&"bag", {"container": _watched_container})


func _input(event: InputEvent) -> void:
	if GameState.flow_state == Enums.FlowState.FIELD and _stack.is_empty() and event.is_action_pressed(&"bag"):
		open(&"bag")
		get_viewport().set_input_as_handled()
	elif GameState.flow_state == Enums.FlowState.FIELD and _stack.is_empty() and event.is_action_pressed(&"map"):
		open(&"map")  # D-16
		get_viewport().set_input_as_handled()


## Flow screens (D-07): opened when the router enters the state, closed when it leaves.
const FLOW_SCREENS := {
	Enums.FlowState.TITLE: &"title",  # D-19
	Enums.FlowState.SORTIE_PREP: &"sortie_prep",
	Enums.FlowState.RESULT: &"result",
	Enums.FlowState.EVENING: &"evening",
}


var _last_flow: Enums.FlowState = Enums.FlowState.TITLE


func _on_flow_state_changed(state: Enums.FlowState) -> void:
	show_field_hud(state == Enums.FlowState.FIELD)
	show_base_hud(state in BASE_STATES)
	show_raid_hud(state in RAID_STATES)
	for st: Enums.FlowState in FLOW_SCREENS:
		var id: StringName = FLOW_SCREENS[st]
		if st == state:
			if has_screen(id) and not is_open(id):
				open(id)
		elif is_open(id):
			close(id)
	# D-13: 입주 의식 for survivors brought home, on top of the evening screen.
	if state == Enums.FlowState.EVENING and _in_game() and has_screen(&"welcome") and not is_open(&"welcome") \
			and not ResidentEventFlow.welcome_queue().is_empty():
		open(&"welcome")
	# D-19: transition card (출격 / 귀환 / 쓰러짐 / 불러오기) above the screen just opened.
	var t := LoadingScreen.transition_for(_last_flow, state)
	_last_flow = state
	if not t.is_empty() and has_screen(&"loading"):
		open(&"loading", t)


## D-19: the sortie card learns the region once the router announces the loadout.
func _on_sortie_started(loadout: Dictionary) -> void:
	if is_open(&"loading"):
		open(&"loading", {"kind": &"sortie", "region_id": StringName(loadout.get("region_id", &""))})


## D-13: tonight's events (C-14) play in the night event screen.
func _on_night_events_ready(_events: Array) -> void:
	if _in_game() and has_screen(&"night_event") and not is_open(&"night_event"):
		open(&"night_event")


## #125 part 3 (C-20): the morning funeral scene, a notice when someone goes missing, and a nudge
## to the memorial at night while someone grieves.
func _connect_loss() -> void:
	Colony.funeral_ready.connect(_on_funeral_ready)
	Colony.resident_missing.connect(_on_resident_missing)
	EventBus.flow_state_changed.connect(_on_loss_flow)


func _on_funeral_ready(resident_ids: Array) -> void:
	if _in_game() and has_screen(&"funeral") and not resident_ids.is_empty():
		open(&"funeral", {"resident_ids": resident_ids})


func _on_resident_missing(resident_id: StringName) -> void:
	LossText.note_missing(resident_id)
	EventBus.notification_posted.emit("@residents ◆ %s을(를) 끝내 찾지 못했어요 · 실종" % LossText.display_name(resident_id), &"danger")


func _on_loss_flow(state: Enums.FlowState) -> void:
	if state != Enums.FlowState.NIGHT or not MemorialScreen.has_stone():
		return
	for id in Colony.active_resident_ids():
		if int(Colony.get_resident(id).get("grief_days", 0)) > 0:
			EventBus.notification_posted.emit("@memorial 추모비에 다녀올 수 있어요 (슬픔 −1일)", &"info")
			return


## Auto-opened scenes (welcome, night events) only inside a running scene, not in --script test runs.
func _in_game() -> bool:
	return get_tree().current_scene != null


# --- public API (contracts.md) ---

func open(screen_id: StringName, args: Dictionary = {}) -> void:
	var idx := _index_of(screen_id)
	if idx >= 0:
		# Already open: bring to top and refresh args.
		var entry: Dictionary = _stack[idx]
		_stack.remove_at(idx)
		_stack.append(entry)
		screens.move_child(entry.node, -1)
		_call_open(entry.node, args)
		_refresh_visibility()
		return
	var def := _get_def(screen_id)
	var packed := _get_scene(screen_id, def)
	if packed == null:
		push_error("UI.open: no scene for screen '%s'" % screen_id)
		return
	var node := packed.instantiate()
	if not node is Control:
		push_error("UI.open: screen '%s' root must be a Control" % screen_id)
		node.free()
		return
	node.name = String(screen_id)
	(node as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.process_mode = Node.PROCESS_MODE_ALWAYS if def.pauses_game else Node.PROCESS_MODE_INHERIT
	# First open: hand the args over before _ready so the screen builds with them.
	_call_open(node, args)
	screens.add_child(node)
	_stack.append({"id": screen_id, "node": node, "def": def})
	_refresh_visibility()
	screen_opened.emit(screen_id)


func close(screen_id: StringName) -> void:
	var idx := _index_of(screen_id)
	if idx < 0:
		return
	var entry: Dictionary = _stack[idx]
	_stack.remove_at(idx)
	var node: Node = entry.node
	if node.has_method(&"on_closing"):
		node.call(&"on_closing")
	screens.remove_child(node)
	node.queue_free()
	_refresh_visibility()
	screen_closed.emit(screen_id)


# --- extra helpers (Lane D and sandboxes) ---

func close_top() -> void:
	if not _stack.is_empty():
		close(_stack.back().id)


func close_all() -> void:
	while not _stack.is_empty():
		close_top()


func is_open(screen_id: StringName) -> bool:
	return _index_of(screen_id) >= 0


func top() -> StringName:
	return &"" if _stack.is_empty() else _stack.back().id


func stack_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for e in _stack:
		out.append(e.id)
	return out


func get_screen(screen_id: StringName) -> Control:
	var idx := _index_of(screen_id)
	return null if idx < 0 else _stack[idx].node


## Register a screen from code (previews, tests). `scene` is a PackedScene or a res:// path.
func register_screen(screen_id: StringName, scene: Variant, opts: Dictionary = {}) -> void:
	var def := ScreenDef.new()
	def.id = screen_id
	def.pauses_game = bool(opts.get("pauses_game", false))
	def.closes_on_cancel = bool(opts.get("closes_on_cancel", true))
	def.is_overlay = bool(opts.get("is_overlay", false))
	def.hides_hud = bool(opts.get("hides_hud", true))
	if scene is PackedScene:
		_scenes[screen_id] = scene
	elif scene is String:
		def.scene_path = scene
	_defs[screen_id] = def


func has_screen(screen_id: StringName) -> bool:
	return _defs.has(screen_id)


# --- internals ---

func _unhandled_input(event: InputEvent) -> void:
	if _stack.is_empty():
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		var def: ScreenDef = _stack.back().def
		if def.closes_on_cancel:
			# MenuScreens may route "back" through the game flow (sortie prep → cancel_sortie_prep).
			var node: Node = _stack.back().node
			if node.has_method(&"close"):
				node.call(&"close")
			else:
				close_top()
			get_viewport().set_input_as_handled()


func _make_layer(layer_name: StringName, layer: int) -> Control:
	var cl := CanvasLayer.new()
	cl.name = layer_name
	cl.layer = layer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	var root := Control.new()
	root.name = &"Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(root)
	return root


func _rebuild_theme() -> void:
	theme = UiThemeBuilder.build(int(Settings.get_value(&"text_size")), bool(Settings.get_value(&"high_contrast")))
	for root in [hud, screens, overlay]:
		root.theme = theme
	theme_changed.emit(theme)


func _load_defs() -> void:
	var dir := DirAccess.open(SCREENS_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var def := load("%s/%s" % [SCREENS_DIR, file]) as ScreenDef
		if def != null and def.id != &"":
			_defs[def.id] = def


func _get_def(screen_id: StringName) -> ScreenDef:
	if _defs.has(screen_id):
		return _defs[screen_id]
	var def := ScreenDef.new()
	def.id = screen_id
	return def


func _get_scene(screen_id: StringName, def: ScreenDef) -> PackedScene:
	if _scenes.has(screen_id):
		return _scenes[screen_id]
	if def.scene_path.is_empty() or not ResourceLoader.exists(def.scene_path):
		return null
	return load(def.scene_path) as PackedScene


func _index_of(screen_id: StringName) -> int:
	for i in _stack.size():
		if _stack[i].id == screen_id:
			return i
	return -1


func _call_open(node: Node, args: Dictionary) -> void:
	if node.has_method(&"open_with"):
		node.call(&"open_with", args)


## Only the top non-overlay screen and the overlays above it are visible.
## The game pauses while any open screen asks for it; HUD hides while any screen asks for it.
func _refresh_visibility() -> void:
	var show_from := 0
	for i in range(_stack.size() - 1, -1, -1):
		if not (_stack[i].def as ScreenDef).is_overlay:
			show_from = i
			break
	var pause := false
	var hide_hud := false
	for i in _stack.size():
		var def: ScreenDef = _stack[i].def
		(_stack[i].node as Control).visible = i >= show_from
		pause = pause or def.pauses_game
		hide_hud = hide_hud or def.hides_hud
	hud.visible = not hide_hud
	if pause != _paused_by_ui:
		_paused_by_ui = pause
		get_tree().paused = pause


func _on_settings_changed(key: StringName) -> void:
	if key == &"text_size" or key == &"high_contrast":
		_rebuild_theme()


func _on_radio_message(speaker_id: StringName, text: String, priority: int) -> void:
	subtitle.show_line(_speaker_name(speaker_id), text, priority)


## Display names for radio speakers. Residents come from Colony when C exposes names.
func _speaker_name(speaker_id: StringName) -> String:
	if speaker_id == &"broadcaster":
		return "방송실 지기"
	var r: Dictionary = Colony.get_resident(speaker_id)
	if r.has("name"):
		return String(r.name)
	return String(speaker_id)
