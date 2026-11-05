class_name RegionDressing
extends Node3D
## Map dressing (D-10). Owner: Lane D. Lives in levels/<field|base>/<map>/dressing.tscn; the map's
## assembly scene (B/C) instances it next to its Layout at runtime, so no other lane's scene is saved.
##
## Reads the sibling Layout (read-only geometry) and adds Lane D visuals on top:
##   environment (sky, fog, sun, glow), toon skin (each greybox StandardMaterial3D colour is drawn
##   with the toon shader instead - layout files are untouched), flood water shader on deep-water
##   surfaces, vines along wall tops, dead neon signs, warm lights in IndoorZones, floating debris,
##   and for the base: laundry lines, a bonfire light, flower pots.
## Everything is seeded, so the same map always looks the same.
## Design 16 "아트 방향": 회백 콘크리트 + 청록 수면 + 초록 덩굴, 맑은 하늘, 꺼진 네온.

const TOON := preload("res://art/materials/toon_default.tres")
const FOLIAGE := preload("res://art/materials/toon_foliage.tres")
const WOOD := preload("res://art/materials/toon_wood.tres")
const WATER := preload("res://art/shaders/water_toon.gdshader")

enum Kind { FIELD, BASE }

@export var kind: Kind = Kind.FIELD
@export var seed_value := 7
@export_group("Light")
@export var sky_top := Color("6fb3de")
@export var sky_horizon := Color("cfe7ef")
@export var ground_color := Color("8a9a95")
@export var sun_color := Color("fff3e0")
@export var sun_energy := 1.25
@export var sun_rotation := Vector3(-52, -38, 0)
@export var ambient := Color("b9cbd6")
@export var ambient_energy := 0.55
@export var fog_color := Color("b8d6da")
@export var fog_density := 0.0025
@export var shade_tint := Color("6b7f8c") ## toon shadow colour mixed into skinned materials
@export_range(0.0, 1.0) var shade_tint_mix := 0.5
@export var sun_shadow_distance := 80.0
@export_group("Post")
@export var tonemap: Environment.ToneMapper = Environment.TONE_MAPPER_FILMIC
@export var exposure := 1.0
@export var agx_contrast := 1.25
@export var glow_intensity := 0.6
@export var glow_bloom := 0.05
@export var ssao := false
@export var ssao_intensity := 2.0
@export var adjust := false
@export var contrast := 1.0
@export var saturation := 1.0
@export var grade: Gradient ## per-channel 1D LUT (GradientTexture1D); null = none
@export_group("Dressing")
@export var toon_skin := true
@export var vines_per_10m := 3.0
@export var neon_signs := 6
@export var debris_count := 24
@export var interior_lights := true
@export var vine_color := Color("5e9a4a")

var _rng := RandomNumberGenerator.new()
var _toon_cache: Dictionary = {}
var _bobbers: Array[Node3D] = []
var _t := 0.0
var _fire: OmniLight3D


func _ready() -> void:
	_rng.seed = seed_value
	_environment()
	var layout := _find_layout()
	if layout == null:
		push_warning("RegionDressing: no sibling Layout found; only the environment is added")
		return
	# CSG shapes are built at the end of the frame.
	await get_tree().process_frame
	if toon_skin:
		_skin(layout)
	_water(layout)
	var walls := _walls(layout)
	_vines(walls)
	if kind == Kind.FIELD:
		_neon(walls)
	if interior_lights:
		_interior_lights(layout)
	if kind == Kind.BASE:
		_base_life(layout, walls)


func _process(delta: float) -> void:
	_t += delta
	for i in _bobbers.size():
		var b := _bobbers[i]
		if is_instance_valid(b):
			b.position.y = b.get_meta(&"y0", 0.0) + sin(_t * 1.3 + i) * 0.04
			b.rotation.z = sin(_t * 0.9 + i * 2.0) * 0.06
	if _fire != null:
		_fire.light_energy = 1.4 + sin(_t * 9.0) * 0.12 + sin(_t * 23.0) * 0.08


func _find_layout() -> Node3D:
	var p := get_parent()
	if p == null:
		return null
	var l := p.get_node_or_null(^"Layout")
	return l as Node3D


# ---------------- environment ----------------

func _environment() -> void:
	var env := WorldEnvironment.new()
	env.name = &"DressingEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = sky_top
	sm.sky_horizon_color = sky_horizon
	sm.ground_horizon_color = sky_horizon
	sm.ground_bottom_color = ground_color
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = ambient_energy
	e.tonemap_mode = tonemap
	e.tonemap_exposure = exposure
	e.tonemap_agx_contrast = agx_contrast
	e.glow_enabled = true
	e.glow_intensity = glow_intensity
	e.glow_bloom = glow_bloom
	e.ssao_enabled = ssao
	e.ssao_intensity = ssao_intensity
	e.adjustment_enabled = adjust
	e.adjustment_contrast = contrast
	e.adjustment_saturation = saturation
	if grade != null:
		var lut := GradientTexture1D.new()
		lut.gradient = grade
		e.adjustment_color_correction = lut
	e.fog_enabled = true
	e.fog_light_color = fog_color
	e.fog_density = fog_density
	e.fog_aerial_perspective = 0.1
	e.fog_sky_affect = 0.3
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = &"Sun"
	sun.rotation_degrees = sun_rotation
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = sun_shadow_distance
	add_child(sun)


# ---------------- toon skin ----------------

func _skin(layout: Node) -> void:
	for n in layout.find_children("*", "CSGShape3D", true, false):
		var s := n as CSGShape3D
		if not s.visible:
			continue
		var m: Variant = s.get(&"material") if &"material" in s else null
		if m is StandardMaterial3D and not _is_water(s):
			s.set(&"material", _toon_for((m as StandardMaterial3D).albedo_color))
		elif m == null and s.material_override is StandardMaterial3D:
			s.material_override = _toon_for((s.material_override as StandardMaterial3D).albedo_color)


func _toon_for(c: Color) -> ShaderMaterial:
	var key := c.to_html()
	if not _toon_cache.has(key):
		var t := TOON.duplicate() as ShaderMaterial
		t.set_shader_parameter(&"albedo", c)
		t.set_shader_parameter(&"shade_color", c.darkened(0.35).lerp(shade_tint, shade_tint_mix))
		_toon_cache[key] = t
	return _toon_cache[key]


func _is_water(s: Node) -> bool:
	# Field layouts tag every water surface (B-26, field/build/layout_builder.gd WATER_SURFACE_GROUP).
	if s.is_in_group(&"water_surface"):
		return true
	var nm := String(s.name)
	if nm == "Chan" or nm.begins_with("Water") or nm.begins_with("Channel"):
		return true
	return "Surface" in nm and s.get_parent() != null and "Water" in String(s.get_parent().name)


# ---------------- water ----------------

func _water(layout: Node) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	if bool(Settings.get_value(&"reduce_flash")):
		mat.set_shader_parameter(&"sparkle_amount", 0.0)
	# Shallow overlays (a few cm over the ground) would read as foam everywhere: the foam is the depth
	# difference to what is under the surface. They get a thin foam band only (B-26 feedback 2026-11-06).
	var shallow_mat := mat.duplicate() as ShaderMaterial
	shallow_mat.set_shader_parameter(&"foam_width", 0.005)
	for n in layout.find_children("*", "CSGShape3D", true, false):
		if not _is_water(n):
			continue
		var is_shallow := n.get_parent() != null and String(n.get_parent().name) == "Overlays"
		(n as CSGShape3D).set(&"material", shallow_mat if is_shallow else mat)
		var box := (n as CSGShape3D).get_aabb()
		var xf := (n as Node3D).global_transform
		for i in int(debris_count / 2.0):
			var local := Vector3(_rng.randf_range(box.position.x, box.end.x), box.end.y,
				_rng.randf_range(box.position.z, box.end.z))
			_float_debris(xf * local)


func _float_debris(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(_rng.randf_range(0.4, 1.4), 0.08, _rng.randf_range(0.15, 0.35))
	mi.mesh = bm
	mi.material_override = WOOD
	add_child(mi)
	mi.global_position = at + Vector3.UP * 0.03
	mi.rotation.y = _rng.randf() * TAU
	mi.set_meta(&"y0", mi.position.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bobbers.append(mi)


# ---------------- walls / vines / neon ----------------

## [{xf: Transform3D (global), size: Vector3}] for every visible CSGBox3D named like a wall.
func _walls(layout: Node) -> Array:
	var out := []
	for n in layout.find_children("*", "CSGBox3D", true, false):
		var b := n as CSGBox3D
		var nm := String(b.name)
		var parent_name := String(b.get_parent().name) if b.get_parent() else ""
		if not b.visible or b.operation != CSGShape3D.OPERATION_UNION:
			continue
		if not ("Wall" in nm or "Wall" in parent_name or nm in ["North", "South", "East", "West", "Outer"]):
			continue
		if b.size.y < 1.2:
			continue
		out.append({"xf": b.global_transform, "size": b.size})
	return out


func _vines(walls: Array) -> void:
	for w: Dictionary in walls:
		var s: Vector3 = w.size
		var along_x := s.x >= s.z
		var length := s.x if along_x else s.z
		var count := int(length / 10.0 * vines_per_10m * _rng.randf_range(0.5, 1.5))
		for i in count:
			var u := _rng.randf_range(-0.5, 0.5) * length
			var local := Vector3(u, s.y * 0.5, 0) if along_x else Vector3(0, s.y * 0.5, u)
			var side := (1.0 if _rng.randf() > 0.5 else -1.0) * ((s.z if along_x else s.x) * 0.5 + 0.05)
			if along_x:
				local.z = side
			else:
				local.x = side
			var at: Vector3 = (w.xf as Transform3D) * local
			_vine_cluster(at, _rng.randf_range(0.6, 1.0) * minf(s.y, 3.0))


func _vine_cluster(at: Vector3, hang: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	for i in _rng.randi_range(2, 4):
		var leaf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := _rng.randf_range(0.25, 0.55)
		sm.radius = r
		sm.height = r * 1.6
		sm.radial_segments = 10
		sm.rings = 6
		leaf.mesh = sm
		leaf.material_override = _toon_for(vine_color.lightened(_rng.randf_range(-0.1, 0.12)))
		leaf.position = Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.2, 0.25), _rng.randf_range(-0.2, 0.2))
		root.add_child(leaf)
	for i in _rng.randi_range(1, 3):
		var strand := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.07
		cm.height = hang * _rng.randf_range(0.4, 1.0)
		cm.radial_segments = 6
		strand.mesh = cm
		strand.material_override = _toon_for(vine_color.darkened(0.15))
		strand.position = Vector3(_rng.randf_range(-0.5, 0.5), -cm.height * 0.5, 0)
		root.add_child(strand)


func _neon(walls: Array) -> void:
	if walls.is_empty():
		return
	var tints := [Color("ff6fa8"), Color("5fd6e6"), Color("ffd84a"), Color("9a6bd8")]
	for i in mini(neon_signs, walls.size()):
		var w: Dictionary = walls[_rng.randi_range(0, walls.size() - 1)]
		var s: Vector3 = w.size
		var along_x := s.x >= s.z
		var local := Vector3(_rng.randf_range(-0.3, 0.3) * s.x, s.y * 0.5 - 0.7, (s.z * 0.5 + 0.12)) if along_x \
			else Vector3(s.x * 0.5 + 0.12, s.y * 0.5 - 0.7, _rng.randf_range(-0.3, 0.3) * s.z)
		var sign_root := Node3D.new()
		add_child(sign_root)
		sign_root.global_transform = (w.xf as Transform3D) * Transform3D(Basis(), local)
		var frame := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 0.6, 0.12) if along_x else Vector3(0.12, 0.6, 1.8)
		frame.mesh = bm
		var m := TOON.duplicate() as ShaderMaterial
		m.set_shader_parameter(&"albedo", Color("2d3238"))
		frame.material_override = m
		sign_root.add_child(frame)
		var tube := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(1.4, 0.08, 0.05) if along_x else Vector3(0.05, 0.08, 1.4)
		tube.mesh = tb
		var tm := TOON.duplicate() as ShaderMaterial
		# Dead neon by day: the tube colour without glow (design 16 "꺼진 네온").
		tm.set_shader_parameter(&"albedo", (tints[i % tints.size()] as Color).darkened(0.45))
		tube.material_override = tm
		tube.position = Vector3(0, 0.05, 0.07) if along_x else Vector3(0.07, 0.05, 0)
		sign_root.add_child(tube)


# ---------------- lights ----------------

func _interior_lights(layout: Node) -> void:
	for n in layout.find_children("*", "Area3D", true, false):
		if not n.get_class() == "Area3D" or not n.has_method(&"set_roofs_hidden"):
			continue
		var shape := n.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		var at: Vector3 = (shape.global_position if shape else (n as Node3D).global_position)
		var l := OmniLight3D.new()
		l.light_color = Color("ffcf8a")
		l.light_energy = 0.8
		l.omni_range = 9.0
		l.shadow_enabled = false
		add_child(l)
		l.global_position = at + Vector3.UP * 2.4


# ---------------- base ----------------

func _base_life(layout: Node, walls: Array) -> void:
	var yard := layout.find_child("Zone_FrontYard", true, false) as Node3D
	var center := yard.global_position if yard else Vector3.ZERO
	_fire = OmniLight3D.new()
	_fire.light_color = Color("ff9a4a")
	_fire.light_energy = 1.4
	_fire.omni_range = 7.0
	add_child(_fire)
	_fire.global_position = center + Vector3(0, 1.0, 0)
	var pit := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 0.7
	cm.height = 0.3
	pit.mesh = cm
	pit.material_override = _toon_for(Color("6b5f58"))
	add_child(pit)
	pit.global_position = center + Vector3(0, 0.15, 0)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.35
	fm.height = 0.8
	flame.mesh = fm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://art/shaders/element_glow.gdshader")
	gm.set_shader_parameter(&"glow_color", Color("ff9a4a"))
	flame.material_override = gm
	add_child(flame)
	flame.global_position = center + Vector3(0, 0.6, 0)
	# laundry lines and flower pots along the main hall front
	var hall := layout.find_child("Outer", true, false) as CSGBox3D
	if hall != null:
		var s := hall.size
		var front := hall.global_transform * Vector3(0, -s.y * 0.5, s.z * 0.5 + 1.2)
		for i in 7:
			var pot := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.28
			pm.bottom_radius = 0.2
			pm.height = 0.4
			pot.mesh = pm
			pot.material_override = _toon_for(Color("c8714e"))
			add_child(pot)
			pot.global_position = front + Vector3((i - 3) * 1.6, 0.2, 0)
			var plant := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.32
			sm.height = 0.5
			plant.mesh = sm
			plant.material_override = FOLIAGE
			add_child(plant)
			plant.global_position = pot.global_position + Vector3(0, 0.38, 0)
		_laundry(front + Vector3(-6, 2.2, 7.5), front + Vector3(6, 2.2, 7.5))


func _laundry(a: Vector3, b: Vector3) -> void:
	var line := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.015
	cm.height = a.distance_to(b)
	line.mesh = cm
	line.material_override = _toon_for(Color("efeadf"))
	add_child(line)
	line.global_position = (a + b) * 0.5
	line.look_at(b, Vector3.UP)
	line.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var cols := [Color("e8a23a"), Color("57c2c9"), Color("efeadf"), Color("d9705c"), Color("5fc46b"), Color("a7c0d8")]
	var n := 9
	for i in n:
		var t := (i + 0.5) / n
		var cloth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, _rng.randf_range(0.5, 0.8), 0.03)
		cloth.mesh = bm
		cloth.material_override = _toon_for(cols[i % cols.size()])
		add_child(cloth)
		cloth.global_position = a.lerp(b, t) + Vector3(0, -bm.size.y * 0.5 - 0.02, 0)
		cloth.look_at(cloth.global_position + (b - a).cross(Vector3.UP), Vector3.UP)
