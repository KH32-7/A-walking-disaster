extends Node
## Autoload `Look`. Owner: Lane A. Full-screen stylized look (prototype, user request 2026-11-06):
## keeps a screen quad with core/look/stylized_post.gdshader in front of whichever Camera3D is
## current, so field and base scenes need no changes. Numbers: `tuning` (data/look/look_tuning.tres).
## Turned on/off with `tuning.enabled` (debug: \ panel or console `look`). Also drives the global
## shader uniform `toon_amount` (art/shaders/toon_local_light.gdshaderinc) from `tuning.toon_amount`.
##
## The player (group "player") gets extra readability (user feedback 2026-11-06: grey hero on a
## grey road): a bright outline (hero_outline_px). Its materials move to the transparent pass, drawn
## after the outline and after the screen quad, so the outline stays behind the body and the
## painterly filter skips the player.

const SHADER := preload("res://core/look/stylized_post.gdshader")
const HERO_OUTLINE := preload("res://core/look/hero_outline.gdshader")
## Above the screen quad (RENDER_PRIORITY_MIN): body over its own outline.
const HERO_PRIORITY := 10
const HERO_SCAN_SEC := 0.5  # the held gun model comes and goes, so rescan the player's meshes

var tuning: LookTuning = preload("res://data/look/look_tuning.tres")

var _quad: MeshInstance3D
var _material: ShaderMaterial
var _hero_scan := 0.0
var _toon_amount := -1.0  # last value sent to the global shader uniform, -1 = not sent yet


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# Draw before every other transparent object so effects and world labels stay on top, unfiltered.
	_material.render_priority = Material.RENDER_PRIORITY_MIN
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	_quad = MeshInstance3D.new()
	_quad.name = &"StylizedLookQuad"
	_quad.mesh = mesh
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader puts it over the whole screen; never let it be frustum culled.
	_quad.custom_aabb = AABB(Vector3(-1.0e5, -1.0e5, -1.0e5), Vector3(2.0e5, 2.0e5, 2.0e5))


func _process(delta: float) -> void:
	if tuning.toon_amount != _toon_amount:
		_toon_amount = tuning.toon_amount
		RenderingServer.global_shader_parameter_set(&"toon_amount", _toon_amount)
	_hero_scan -= delta
	if _hero_scan <= 0.0:
		_hero_scan = HERO_SCAN_SEC
		_style_hero()
	var cam := get_viewport().get_camera_3d() if tuning.enabled else null
	if cam == null:
		if _quad.get_parent() != null:
			_quad.get_parent().remove_child(_quad)
		return
	if _quad.get_parent() != cam:
		if _quad.get_parent() != null:
			_quad.get_parent().remove_child(_quad)
		cam.add_child(_quad, false, Node.INTERNAL_MODE_BACK)
		_quad.position = Vector3(0.0, 0.0, -cam.near * 2.0)
	for p: StringName in LookTuning.PARAMS:
		_material.set_shader_parameter(p, tuning.get(p))


## Gives every mesh under the player the hero materials for the current tuning. Each mesh keeps its
## original surface overrides in metadata and is rebuilt only when the wanted state changes.
func _style_hero() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	var styled := tuning.enabled or tuning.hero_outline_px > 0.0
	var key := [styled, tuning.hero_outline_px, tuning.hero_outline_color]
	for mi: MeshInstance3D in player.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.material_override != null or (mi.has_meta(&"look_key") and mi.get_meta(&"look_key") == key):
			continue
		if not mi.has_meta(&"look_orig"):
			var orig := []
			for i in mi.get_surface_override_material_count():
				orig.append(mi.get_surface_override_material(i))
			mi.set_meta(&"look_orig", orig)
		var orig: Array = mi.get_meta(&"look_orig")
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, orig[i])
			if styled:
				mi.set_surface_override_material(i, _hero_material(mi.get_active_material(i)))
		mi.set_meta(&"look_key", key)


func _hero_material(base: Material) -> Material:
	if base == null:
		return null
	var m := base.duplicate() as Material
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		m.render_priority = HERO_PRIORITY
	if tuning.hero_outline_px > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = HERO_OUTLINE
		outline.render_priority = HERO_PRIORITY - 1
		outline.set_shader_parameter(&"outline_px", tuning.hero_outline_px)
		outline.set_shader_parameter(&"outline_color", tuning.hero_outline_color)
		var last := m
		while last.next_pass != null:
			last.next_pass = last.next_pass.duplicate()
			last = last.next_pass
		last.next_pass = outline
	return m


func _exit_tree() -> void:
	if _quad != null and _quad.get_parent() == null:
		_quad.free()
