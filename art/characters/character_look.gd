@tool
class_name CharacterLook
extends Node3D
## Character appearance (D-09). Owner: Lane D. B (player, companions) and C (residents) instance
## art/characters/character.tscn and call apply(resident.appearance) - they never touch meshes.
##
## Two bodies:
##  - VRoid model (AppearancePreset.base_model, a .vrm/.glb/.tscn under res://assets/characters/vroid/):
##    materials whose name contains HAIR / SKIN / CLOTH (VRoid export naming) are tinted.
##    Needs the godot-vrm addon for .vrm (requested from Lane A).
##  - Placeholder (no model yet): a toon primitive humanoid, ~1.6 m, same colours and hair shapes,
##    so screens and maps look right before the art lands.
## Height scales with age stage (child 0.7, teen 0.9, elder 0.97).

const PRESET_DIR := "res://data/ui/appearance"
const TOON := preload("res://art/materials/toon_default.tres")
const AGE_SCALE := [0.5, 0.7, 0.9, 1.0, 0.97]

@export var preset_id: StringName = &"rescuer":
	set(v):
		preset_id = v
		if is_inside_tree():
			apply({})
@export_range(0, 4) var age_stage := 3:
	set(v):
		age_stage = v
		if is_inside_tree():
			apply(_last)

var _last: Dictionary = {}
var _body: Node3D
static var _presets: Dictionary = {}


func _ready() -> void:
	apply(_last)


static func presets() -> Dictionary:
	if _presets.is_empty():
		var dir := DirAccess.open(PRESET_DIR)
		if dir != null:
			for f in dir.get_files():
				var file := f.trim_suffix(".remap")
				if file.ends_with(".tres"):
					var p := load(PRESET_DIR.path_join(file)) as AppearancePreset
					if p != null:
						_presets[p.id] = p
	return _presets


static func preset_ids() -> Array:
	var ids := presets().keys()
	ids.sort()
	return ids


## appearance: {"preset", "hair", "hair_color", "outfit_color", "skin"} (all optional).
func apply(appearance: Dictionary) -> void:
	_last = appearance
	var p: AppearancePreset = presets().get(StringName(appearance.get("preset", preset_id)))
	if p == null:
		p = AppearancePreset.new()
	var look := {
		"hair": String(appearance.get("hair", p.hair)),
		"hair_color": appearance.get("hair_color", p.hair_color),
		"skin": appearance.get("skin", p.skin),
		"outfit": appearance.get("outfit_color", p.outfit_color),
		"accent": appearance.get("outfit_accent", p.outfit_accent),
	}
	if _body != null:
		remove_child(_body)
		_body.queue_free()
		_body = null
	if not p.base_model.is_empty() and ResourceLoader.exists(p.base_model):
		var scene := load(p.base_model) as PackedScene
		if scene != null:
			_body = scene.instantiate()
			add_child(_body)
			_tint_model(_body, look)
	if _body == null:
		_body = _placeholder(look)
		add_child(_body)
	var k: float = AGE_SCALE[clampi(age_stage, 0, 4)]
	_body.scale = Vector3.ONE * k


func _tint_model(root: Node, look: Dictionary) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var m := mi.mesh.surface_get_material(i) if mi.mesh else null
			if m == null:
				continue
			var key := m.resource_name.to_upper()
			var col: Variant = null
			if "HAIR" in key:
				col = look.hair_color
			elif "SKIN" in key or "FACE" in key:
				col = look.skin
			elif "CLOTH" in key or "TOPS" in key or "BOTTOMS" in key:
				col = look.outfit
			if col == null:
				continue
			var dup := m.duplicate()
			for prop in [&"albedo_color", &"_Color"]:
				if prop in dup:
					dup.set(prop, col)
			if dup is ShaderMaterial:
				(dup as ShaderMaterial).set_shader_parameter(&"_Color", col)
				(dup as ShaderMaterial).set_shader_parameter(&"albedo", col)
			mi.set_surface_override_material(i, dup)


func _mat(c: Color) -> ShaderMaterial:
	var m := TOON.duplicate() as ShaderMaterial
	m.set_shader_parameter(&"albedo", c)
	return m


func _placeholder(look: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = &"Placeholder"
	var outfit := _mat(look.outfit)
	var accent := _mat(look.accent)
	var skin := _mat(look.skin)
	var hair := _mat(look.hair_color)
	_part(root, _capsule(0.13, 0.75), Vector3(-0.11, 0.38, 0), _mat(Color(look.outfit).darkened(0.35)))
	_part(root, _capsule(0.13, 0.75), Vector3(0.11, 0.38, 0), _mat(Color(look.outfit).darkened(0.35)))
	_part(root, _capsule(0.24, 0.62), Vector3(0, 0.98, 0), outfit)
	_part(root, _box(Vector3(0.5, 0.07, 0.3)), Vector3(0, 0.83, 0), accent)
	_part(root, _capsule(0.08, 0.55), Vector3(-0.31, 1.0, 0), outfit).rotation_degrees.z = -8
	_part(root, _capsule(0.08, 0.55), Vector3(0.31, 1.0, 0), outfit).rotation_degrees.z = 8
	_part(root, _sphere(0.065), Vector3(-0.34, 0.72, 0), skin)
	_part(root, _sphere(0.065), Vector3(0.34, 0.72, 0), skin)
	_part(root, _sphere(0.2), Vector3(0, 1.47, 0), skin)
	match String(look.hair):
		"short":
			_part(root, _sphere(0.215), Vector3(0, 1.52, -0.02), hair).scale = Vector3(1, 0.8, 1)
		"bob":
			_part(root, _sphere(0.22), Vector3(0, 1.5, -0.07), hair).scale = Vector3(1.05, 0.95, 1)
		"long":
			_part(root, _sphere(0.22), Vector3(0, 1.5, -0.02), hair).scale = Vector3(1, 0.9, 1)
			_part(root, _box(Vector3(0.36, 0.5, 0.12)), Vector3(0, 1.2, -0.14), hair)
		"tied":
			_part(root, _sphere(0.215), Vector3(0, 1.52, -0.02), hair).scale = Vector3(1, 0.8, 1)
			_part(root, _sphere(0.1), Vector3(0, 1.55, -0.24), hair)
		"cap":
			_part(root, _cyl(0.22, 0.12), Vector3(0, 1.6, 0), accent)
			_part(root, _box(Vector3(0.3, 0.03, 0.18)), Vector3(0, 1.56, 0.2), accent)
	return root


func _part(root: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	root.add_child(mi)
	return mi


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


func _cyl(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = h
	return m
