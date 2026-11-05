class_name RegionDressing
extends Node3D
## Map dressing (D-10). Owner: Lane D. Lives in levels/<field|base>/<map>/dressing.tscn; the map's
## assembly scene (B/C) instances it next to its Layout at runtime, so no other lane's scene is saved.
##
## Reads the sibling Layout (read-only geometry) and adds Lane D visuals on top:
##   environment (sky, fog, sun, glow), toon skin (each greybox StandardMaterial3D colour is drawn
##   with the toon shader instead - layout files are untouched), flood water shader on deep-water
##   surfaces, vines along wall tops, dead neon signs, warm lights in IndoorZones, floating debris,
##   street lights on the standing pack lamp posts (field), and for the base: laundry lines, a
##   bonfire light, flower pots.
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
@export_group("Street lights")
## Standing pack lamp posts (STREET_LAMP_SCENES) get a downward spot light and a glowing bulb, so
## the streets get pools of light and the map reads in depth. Fallen posts stay dark.
@export var street_lights := true
@export var street_light_color := Color("ffd59a")
@export var street_light_energy := 3.0
## Multiplier from dusk (FieldState.dusk_started) on, and again at night.
@export var street_light_dusk_mult := 1.6
@export var street_light_night_mult := 2.4
@export var street_light_range := 14.0
@export_range(10.0, 89.0) var street_light_angle := 55.0
## Spots further than this from the camera stop casting shadows (and fade out at twice this).
@export var street_light_shadow_distance := 45.0
## About this share of the lamps flicker (seeded).
@export_range(0.0, 1.0) var street_light_flicker := 0.15

var _rng := RandomNumberGenerator.new()
var _toon_cache: Dictionary = {}
var _bobbers: Array[Node3D] = []
var _t := 0.0
var _fire: OmniLight3D
var _street_spots: Array[SpotLight3D] = []
var _flicker_spots: Array[SpotLight3D] = []
var _street_mult := 1.0

## Pack lamp posts that light up (CityKit places them into the region's buildings scene).
const STREET_LAMP_SCENES := ["parking_lot_light_pole_01.fbx"]
## The bulb hangs this far below the top of the post.
const STREET_LAMP_DROP := 0.3
## A builder "Lamp" light this close (m, on the ground) to a lamp post belongs to it.
const BUILDER_LAMP_MATCH := 1.0


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
	if street_lights and kind == Kind.FIELD:
		_street_lights()
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
	for i in _flicker_spots.size():
		var s := _flicker_spots[i]
		if is_instance_valid(s):
			# Mostly on, with short dips (a bad contact, not a strobe: reduce_flash keeps it gentle).
			var dip := 1.0 if sin(_t * 1.7 + i * 3.1) > -0.85 else 0.35
			s.light_energy = street_light_energy * _street_mult * dip


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


## Lights every standing lamp post of the region (its buildings scene is a sibling, put there by
## CityKit before this node is added). Without the private assets/ there are no posts and no lights.
func _street_lights() -> void:
	var region := get_parent()
	var no_flicker := bool(Settings.get_value(&"reduce_flash"))
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bulb_mat.albedo_color = street_light_color.lightened(0.3)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = street_light_color
	bulb_mat.emission_energy_multiplier = 3.0
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.16
	bulb_mesh.height = 0.32
	var post_spots: Array[Vector2] = []  # the foot of every post, standing or fallen
	for n in region.find_children("*", "Node3D", true, false):
		if not _is_street_lamp(n):
			continue
		var mi := n as MeshInstance3D
		if mi == null:
			for c in n.find_children("*", "MeshInstance3D", true, false):
				mi = c as MeshInstance3D
				break
		if mi == null or not mi.is_visible_in_tree():
			continue
		var xf := mi.global_transform
		var box := mi.get_aabb()
		# The pack FBX roots carry a stray offset (CityKit), so the post is located by its mesh.
		var foot := xf * Vector3(box.get_center().x, box.position.y, box.get_center().z)
		post_spots.append(Vector2(foot.x, foot.z))
		if xf.basis.y.normalized().dot(Vector3.UP) < 0.9:
			continue  # fallen post
		var top := xf * Vector3(box.get_center().x, box.end.y, box.get_center().z)
		var at := top - Vector3.UP * STREET_LAMP_DROP
		var spot := SpotLight3D.new()
		spot.name = &"StreetLight"
		spot.light_color = street_light_color
		spot.light_energy = street_light_energy
		spot.spot_range = street_light_range
		spot.spot_angle = street_light_angle
		spot.spot_attenuation = 0.8
		spot.shadow_enabled = true
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = street_light_shadow_distance
		spot.distance_fade_shadow = street_light_shadow_distance
		spot.distance_fade_length = street_light_shadow_distance
		add_child(spot)
		spot.global_position = at
		spot.global_rotation = Vector3(-PI / 2.0, 0.0, 0.0)  # straight down
		var bulb := MeshInstance3D.new()
		bulb.mesh = bulb_mesh
		bulb.material_override = bulb_mat
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bulb)
		bulb.global_position = at
		_street_spots.append(spot)
		if not no_flicker and _rng.randf() < street_light_flicker:
			_flicker_spots.append(spot)
	_hide_builder_lamps(region, post_spots)
	if _street_spots.is_empty():
		return
	FieldState.dusk_started.connect(_set_street_mult.bind(street_light_dusk_mult))
	FieldState.night_started.connect(_set_street_mult.bind(street_light_night_mult))
	if FieldState.is_night():
		_set_street_mult(street_light_night_mult)
	elif FieldState.is_dusk():
		_set_street_mult(street_light_dusk_mult)


## The layout builder (field/build/layout_builder.gd LAMP_LIGHTS) also bakes a plain "Lamp" omni light
## over each lamp post into the buildings scene, even over fallen ones. The posts' lights are the
## spots above, so those omnis are switched off (light towers keep theirs).
func _hide_builder_lamps(region: Node, post_spots: Array[Vector2]) -> void:
	if post_spots.is_empty():
		return
	for n in region.find_children("Lamp*", "OmniLight3D", true, false):
		var p := (n as Node3D).global_position
		for s in post_spots:
			if Vector2(p.x, p.z).distance_to(s) < BUILDER_LAMP_MATCH:
				(n as OmniLight3D).visible = false
				break


func _is_street_lamp(n: Node) -> bool:
	var path := n.scene_file_path
	if path.is_empty():
		return false
	for file: String in STREET_LAMP_SCENES:
		if path.ends_with("/" + file):
			return true
	return false


func _set_street_mult(mult: float) -> void:
	_street_mult = mult
	for s in _street_spots:
		if is_instance_valid(s):
			s.light_energy = street_light_energy * mult


## Standing lit lamp posts (tests and previews).
func street_light_count() -> int:
	return _street_spots.size()


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
