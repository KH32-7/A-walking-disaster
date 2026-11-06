class_name MonsterDropPile
extends StaticBody3D
## What a killed monster left behind (B-18). Sits on physics layer 7 (interactable), so
## Player.interact() picks it up: everything that fits goes into the Bag at once, the rest
## stays here. Gear is created in Armory only when it goes into the bag.
## MonsterDrops.drop_for() makes these.
##
## Look (user request 2026-11-06: one white box read as nothing): the drops pop out of the body one
## by one and scatter. Resources show as their item icons, one chip per piece (MAX_CHIPS in all);
## gear lands as a bag with the "not looted yet" yellow outline (LootContainer.OUTLINE_FRESH).
## Only rare-or-better gear gets a short beam in its rarity colour and the loot_rare chime.
## Picking up pulls the taken chips into the player.

## What went into the bag this time. Lane D can show a notice.
signal picked_up(resources: Dictionary, item_uids: Array[StringName])

const CityKit := preload("res://field/buildings/city_kit.gd")
const BEAM_SHADER := preload("res://field/markers/extract_beacon.gdshader")
const OUTLINE_MATERIAL := preload("res://art/materials/outline.tres")
## Look numbers (가안).
const MAX_CHIPS := 6
const CHIP_SIZE := 0.42  # m, icon width
const CHIP_HOVER := 0.25  # m, icon centre above the ground
const SPREAD_MIN := 0.35  # m from the centre
const SPREAD_MAX := 1.2
const POP_START_HEIGHT := 0.8  # m, where the drops leave the body
const POP_INTERVAL := 0.06  # s between drops
const POP_SEC := 0.38
const POP_HEIGHT := 1.1  # m, arc peak above the straight line
const BOUNCE_HEIGHT := 0.18
const BOUNCE_SEC := 0.16
const SUCK_SEC := 0.22
const GEAR_LOOK := ["gameplay_props", "backpack", 1.0]  # CityKit folder, piece, scale
const BEAM_MIN_RARITY := Enums.Rarity.RARE
const BEAM_HEIGHT := 3.0
const BEAM_RADIUS := 0.3
const BEAM_SEC := 2.5
const OUTLINE_PX := 6.0
## The interact shape covers the scatter.
const INTERACT_RADIUS := SPREAD_MAX + 0.3

## {resource_id: count} still on the ground.
var resources: Dictionary = {}
## [{"def_id": StringName, "rarity": int}] still on the ground.
var gear: Array[Dictionary] = []
var monster_id: StringName = &""

## resource id -> chips (Node3D) still on the ground.
var _chips: Dictionary = {}
## One look per gear entry, same order as `gear`.
var _gear_looks: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = 1 << (Enums.LAYER_INTERACTABLE - 1)
	collision_mask = 0
	var sphere := SphereShape3D.new()
	sphere.radius = INTERACT_RADIUS
	($CollisionShape3D as CollisionShape3D).shape = sphere
	_rng.seed = hash(global_position.snapped(Vector3.ONE * 0.01))
	_pop_out()


## Prompt the HUD shows next to the interact key (#28).
func interact_label() -> String:
	return "줍기"


## Player.interact() calls begin_open on interactables (same name as LootContainer).
func begin_open(interactor: Node3D) -> bool:
	var got: Dictionary = {}
	for id: StringName in resources.keys():
		var added := Bag.try_add(id, resources[id])
		if added > 0:
			got[id] = added
			resources[id] -= added
		if resources[id] <= 0:
			resources.erase(id)
			_suck(_chips.get(id, []), interactor)
			_chips.erase(id)
	var uids: Array[StringName] = []
	var left: Array[Dictionary] = []
	var left_looks: Array[Node3D] = []
	for i in gear.size():
		var entry := gear[i]
		var look: Node3D = _gear_looks[i] if i < _gear_looks.size() else null
		var uid := Armory.create_item(entry.def_id, entry.rarity)
		if uid != &"" and Bag.add_item(uid) >= 0:
			uids.append(uid)
			_suck([look], interactor)
		else:
			if uid != &"":
				Armory.remove_item(uid)  # no room: it stays on the ground
			left.append(entry)
			left_looks.append(look)
	gear = left
	_gear_looks = left_looks
	if not got.is_empty() or not uids.is_empty():
		Audio.play(&"item_pickup")
	picked_up.emit(got, uids)
	if is_empty():
		queue_free()
	return true


func is_empty() -> bool:
	return resources.is_empty() and gear.is_empty()


## Resource chips on the ground (tests).
func chip_count() -> int:
	var n := 0
	for list: Array in _chips.values():
		n += list.size()
	return n


# --- Look ----------------------------------------------------------------------

func _pop_out() -> void:
	var drops: Array = []  # [Node3D, is_rare_gear]
	for i in gear.size():
		var look := _make_gear_look(gear[i])
		_gear_looks.append(look)
		drops.append([look, int(gear[i].rarity) >= BEAM_MIN_RARITY])
	var counts := _chip_counts()
	for id: StringName in counts:
		var list: Array = []
		for n in counts[id]:
			var chip := _make_chip(id)
			list.append(chip)
			drops.append([chip, false])
		_chips[id] = list
	# The greybox box stays only as the fallback gear look.
	($Mesh as Node3D).visible = false
	var step := TAU / maxf(drops.size(), 1.0)
	var turn := _rng.randf() * TAU
	for i in drops.size():
		var angle := turn + step * i + _rng.randf_range(-0.4, 0.4) * step
		var land := Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(SPREAD_MIN, SPREAD_MAX)
		_launch(drops[i][0], land, i * POP_INTERVAL, drops[i][1], i == drops.size() - 1)


## Chips per resource: one per piece, at least one each, MAX_CHIPS in all.
func _chip_counts() -> Dictionary:
	var out: Dictionary = {}
	var room := MAX_CHIPS
	for id: StringName in resources:
		if room <= 0:
			break
		out[id] = 1
		room -= 1
	for id: StringName in out:
		var more := mini(int(resources[id]) - 1, room)
		out[id] += maxi(more, 0)
		room -= maxi(more, 0)
	return out


func _make_chip(id: StringName) -> Node3D:
	var chip := Node3D.new()
	add_child(chip)
	var sprite := Sprite3D.new()
	sprite.texture = ItemInfo.icon(id)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if sprite.texture != null:
		sprite.pixel_size = CHIP_SIZE / maxf(sprite.texture.get_width(), 1.0)
	sprite.position.y = CHIP_HOVER
	chip.add_child(sprite)
	return chip


## A bag from the city pack, or the greybox box without the packs. Yellow outline either way.
func _make_gear_look(_entry: Dictionary) -> Node3D:
	var look := Node3D.new()
	add_child(look)
	var meshes: Array = []
	if CityKit.available():
		var part := CityKit.prop_part(GEAR_LOOK[1], Vector2.ZERO, _rng.randf() * TAU, 0.0, GEAR_LOOK[2])
		if not part.is_empty():
			var node := CityKit.place(look, GEAR_LOOK[0], GEAR_LOOK[1], part.xf)
			if node != null:
				meshes = node.find_children("*", "GeometryInstance3D", true, false)
	if meshes.is_empty():
		var box := ($Mesh as MeshInstance3D).duplicate() as MeshInstance3D
		box.visible = true
		box.position = Vector3(0.0, 0.1, 0.0)
		look.add_child(box)
		meshes = [box]
	var outline := OUTLINE_MATERIAL.duplicate() as ShaderMaterial
	outline.set_shader_parameter(&"outline_color", LootContainer.OUTLINE_FRESH)
	outline.set_shader_parameter(&"outline_px", OUTLINE_PX)
	for g: GeometryInstance3D in meshes:
		g.material_overlay = outline
	return look


## Flies `node` from the body to `land` in an arc, bounces once, then the landing touches.
func _launch(node: Node3D, land: Vector3, delay: float, rare: bool, last: bool) -> void:
	var start := Vector3(0.0, POP_START_HEIGHT, 0.0)
	node.position = start
	node.scale = Vector3.ONE * 0.4
	node.visible = delay <= 0.0
	var tw := node.create_tween()
	node.set_meta(&"pop_tween", tw)  # _suck() stops it when picked up mid-flight
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(node.show)
	tw.tween_method(func(t: float) -> void:
		node.position = start.lerp(land, t) + Vector3.UP * POP_HEIGHT * 4.0 * t * (1.0 - t)
		node.scale = Vector3.ONE * lerpf(0.4, 1.0, minf(t * 2.0, 1.0)), 0.0, 1.0, POP_SEC)
	tw.tween_method(func(t: float) -> void:
		node.position = land + Vector3.UP * BOUNCE_HEIGHT * 4.0 * t * (1.0 - t), 0.0, 1.0, BOUNCE_SEC)
	tw.tween_callback(func() -> void: _landed(node, rare, last))


func _landed(node: Node3D, rare: bool, last: bool) -> void:
	if rare:
		_beam(node)
		Audio.play(&"loot_rare", node.global_position)
	if last:
		Audio.play(&"item_pickup")


## Short rarity-colour column over rare-or-better gear; fades out after BEAM_SEC.
func _beam(look: Node3D) -> void:
	var rarity := Enums.Rarity.RARE
	var i := _gear_looks.find(look)
	if i >= 0:
		rarity = int(gear[i].rarity)
	var mesh := CylinderMesh.new()
	mesh.top_radius = BEAM_RADIUS * 1.4
	mesh.bottom_radius = BEAM_RADIUS
	mesh.height = BEAM_HEIGHT
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter(&"color", UiTokens.rarity_color(rarity))
	mat.set_shader_parameter(&"strength", 0.6)
	mat.set_shader_parameter(&"fade_up", true)
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = BEAM_HEIGHT * 0.5
	look.add_child(beam)
	var tw := beam.create_tween()
	tw.tween_interval(BEAM_SEC)
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter(&"strength", a), 0.6, 0.0, 0.5)
	tw.tween_callback(beam.queue_free)


## Taken: the pieces fly into the picker and shrink away. They leave the pile first, so an
## emptied pile can go at once.
func _suck(nodes: Array, interactor: Node3D) -> void:
	var holder := get_parent()
	for node: Node3D in nodes:
		if not is_instance_valid(node):
			continue
		if holder == null or not is_inside_tree():
			node.queue_free()
			continue
		var pop: Tween = node.get_meta(&"pop_tween", null)
		if pop != null and pop.is_valid():
			pop.kill()
		node.visible = true
		var from := node.global_position
		node.reparent(holder)
		var tw := node.create_tween()
		tw.tween_method(func(t: float) -> void:
			var to := (interactor.global_position + Vector3.UP * 0.9) if is_instance_valid(interactor) \
					else from + Vector3.UP * 1.5
			node.global_position = from.lerp(to, t * t)
			node.scale = Vector3.ONE * (1.0 - t * 0.9), 0.0, 1.0, SUCK_SEC)
		tw.tween_callback(node.queue_free)
