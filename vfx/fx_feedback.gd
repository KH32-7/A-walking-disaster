class_name FxFeedback
extends Node
## Hit feel that gameplay does not call (D-18). Owner: Lane D. Child of the Fx autoload.
## - Monster.damaged(amount, info): damage number at info.position (else above the monster) and a short
##   white flash on its meshes. Status ticks (info.status_tick): small number in the element colour, no flash.
## - Player.health_changed(current, maximum): a drop shows a red "-N", a red flash and the player_hurt
##   sound; a rise shows a green "+N".
## Amounts are Lane B's final numbers; nothing is computed here.

const NUMBER_SEC := 0.7
const NUMBER_RISE := 0.8
const NUMBER_HEIGHT := 1.6
const NUMBER_SIZE := 48
const FLASH_SEC := 0.12
const MONSTER_FLASH := Color(1.0, 1.0, 1.0, 0.8)
const PLAYER_FLASH := Color(1.0, 0.3, 0.25, 0.7)

var _player_hp: Dictionary = {}  # instance_id -> last health
var _flashes: Dictionary = {}  # instance_id -> Tween
var _font: Font


func _ready() -> void:
	if ResourceLoader.exists(UiTokens.FONT_NUM):
		_font = load(UiTokens.FONT_NUM)
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().get_nodes_in_group(Monster.GROUP) + get_tree().get_nodes_in_group(Player.GROUP):
		_on_node_added(n)


func _on_node_added(node: Node) -> void:
	if not (node is Monster or node is Player) or node.has_meta(&"fx_feedback"):
		return  # a node moved to another parent is "added" again
	node.set_meta(&"fx_feedback", true)
	if node is Monster:
		node.damaged.connect(_on_monster_damaged.bind(node))
	elif node is Player:
		node.health_changed.connect(_on_player_health.bind(node))
		# health is set in the player's _ready, after node_added.
		_remember_health.call_deferred(node.get_instance_id())
		node.tree_exiting.connect(_forget_health.bind(node.get_instance_id()), CONNECT_ONE_SHOT)


func _forget_health(id: int) -> void:
	_player_hp.erase(id)


func _remember_health(id: int) -> void:
	var player := instance_from_id(id) as Player
	if player != null:
		_player_hp[id] = player.health


func _on_monster_damaged(amount: float, info: Dictionary, monster: Node3D) -> void:
	if amount <= 0.0 or not is_instance_valid(monster):
		return
	var tick := info.has("status_tick")
	var at: Vector3 = info.get("position", monster.global_position + Vector3.UP * NUMBER_HEIGHT)
	var color := UiTokens.TEXT
	var size := 1.0
	var text := str(roundi(amount))
	if tick:
		color = UiTokens.element_color(int(info.get("element", Enums.Element.NONE)))
		size = 0.7
	elif info.get("crit", false):
		color = UiTokens.ACCENT
		size = 1.5
		text += "!"
	elif info.get("weak_point", false):
		size = 1.25
	show_number(at, text, color, size)
	if not tick:
		flash(monster, MONSTER_FLASH)


func _on_player_health(current: float, _maximum: float, player: Node3D) -> void:
	var id := player.get_instance_id()
	var before: float = _player_hp.get(id, current)
	_player_hp[id] = current
	var diff := current - before
	if absf(diff) < 0.05:
		return
	var at := player.global_position + Vector3.UP * NUMBER_HEIGHT
	if diff < 0.0:
		show_number(at, "-%d" % roundi(-diff), UiTokens.DANGER, 1.0)
		flash(player, PLAYER_FLASH)
		Audio.play(&"player_hurt", player.global_position)
	else:
		show_number(at, "+%d" % roundi(diff), UiTokens.GOOD, 1.0)


## A number that rises and fades over NUMBER_SEC. Returned for tests.
func show_number(at: Vector3, text: String, color: Color, size := 1.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.outline_modulate = UiTokens.SHADOW
	label.outline_size = 10
	label.font_size = roundi(NUMBER_SIZE * size)
	if _font != null:
		label.font = _font
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = false
	label.pixel_size = 0.006
	add_child(label)
	label.global_position = at + Vector3(randf_range(-0.15, 0.15), 0.0, 0.0)
	var tw := label.create_tween()
	tw.tween_property(label, ^"position:y", label.position.y + NUMBER_RISE, NUMBER_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(label, ^"modulate:a", 0.0, NUMBER_SEC * 0.45).set_delay(NUMBER_SEC * 0.55)
	tw.tween_callback(label.queue_free)
	return label


## Briefly overlays `color` on every mesh under `target` that has no overlay of its own.
func flash(target: Node, color: Color) -> void:
	var id := target.get_instance_id()
	var old: Tween = _flashes.get(id)
	if old != null and old.is_valid():
		old.kill()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var peak := color
	if Fx.reduced_flash():
		peak.a *= 0.35
	mat.albedo_color = peak
	var meshes: Array[MeshInstance3D] = []
	for m in target.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.material_overlay == null or mi.material_overlay.has_meta(&"fx_flash"):
			mat.set_meta(&"fx_flash", true)
			mi.material_overlay = mat
			meshes.append(mi)
	if meshes.is_empty():
		return
	var tw := create_tween()
	tw.tween_property(mat, ^"albedo_color:a", 0.0, FLASH_SEC)
	tw.tween_callback(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == mat:
				mi.material_overlay = null
		_flashes.erase(id))
	_flashes[id] = tw
