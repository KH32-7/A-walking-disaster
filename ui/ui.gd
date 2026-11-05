extends Node
## Autoload `UI`. Owner: Lane D (D-01). Rules: ui/UI_RULES.md.
## Opens/closes screens and owns the HUD layer. Gameplay lanes call `UI.open(&"bag")`
## etc.; they never add Control nodes to the tree themselves (sandbox debug UI excepted).
## Design reference: docs/design/14-ui-controls-accessibility.md
##
## Layers (CanvasLayer):  hud (10)  <  screens (20)  <  overlay (30: subtitles, toasts)
## Screen scenes may implement:  open_with(args: Dictionary)  and  on_closing()

signal screen_opened(screen_id: StringName)
signal screen_closed(screen_id: StringName)
## The theme was rebuilt (text size / high contrast changed). Screens normally just inherit it.
signal theme_changed(theme: Theme)

const SCREENS_DIR := "res://data/ui/screens"

var theme: Theme
## Root Controls for each layer. Put HUD widgets under `hud`, never under `screens`.
var hud: Control
var screens: Control
var overlay: Control
var subtitle: SubtitleBox

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
	_rebuild_theme()
	_load_defs()
	EventBus.settings_changed.connect(_on_settings_changed)
	EventBus.radio_message.connect(_on_radio_message)
	EventBus.flow_state_changed.connect(_on_flow_state_changed)
	_on_flow_state_changed(GameState.flow_state)


## The field HUD (D-04). Created on first use, shown only in FlowState.FIELD.
var field_hud: FieldHud


func show_field_hud(on: bool) -> void:
	if on and field_hud == null:
		field_hud = FieldHud.new()
		field_hud.name = &"FieldHud"
		hud.add_child(field_hud)
	if field_hud != null:
		field_hud.visible = on
		field_hud.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _on_flow_state_changed(state: Enums.FlowState) -> void:
	show_field_hud(state == Enums.FlowState.FIELD)


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
	screens.add_child(node)
	_stack.append({"id": screen_id, "node": node, "def": def})
	_call_open(node, args)
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
