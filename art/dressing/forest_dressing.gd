extends Node3D
## Base map dressing: the base is a clearing in a dense Redwood park forest (design 09 "기지 지도").
## Lives in levels/base/base_school/dressing.tscn; base_school.gd adds it next to the Layout at
## runtime. Reads the Layout (read-only) and adds visuals only, no collision:
##   environment (sky, sun, fog), ground (forest soil, clearing grass, dirt trails to every raid
##   spawn), lake and pond meshes for the Layout's Water bodies, Pure Nature Redwood forest
##   (MultiMesh, seeded), the prebuilt 방송실 and the camp around the start beds.
## Forest inside an expansion zone (서쪽 숲 등) disappears when Colony clears that zone.
## Models come from the private assets/ submodule; without it only ground, water and light remain.

const Models := preload("res://base/building/building_models.gd")
const TERRAIN := "res://assets/environment/nature/pure_nature_redwood/textures/terrain/"
## Water depth in the middle of a lake (m), from its smaller radius. The lakes sit on flat ground,
## so the water (RealisticWater, shared with the field) reads this "fake depth" instead of the
## depth buffer.
const WATER_DEPTH_PER_RADIUS := 0.3
const WATER_RINGS := 12
const WATER_SEGMENTS := 72

const SEQUOIA := ["sequoia1", "sequoia2", "sequoia3", "sequoia4", "sequoia5"]
const FIR := ["red_fir1", "red_fir2", "red_fir3", "red_fir4", "red_fir5", "red_fir6", "red_fir7", "red_fir8"]
const PINE := ["red_pine1", "red_pine2", "red_pine3", "red_pine4", "red_pine5"]
const FERNS := ["thin_fern1", "thin_fern2", "thin_fern3", "thin_fern4", "thin_fern5"]
const GRASS := ["grass_1", "grass_2", "grass_3"]
const CLOVERS := ["clovers_1", "clovers_2"]
const FUNGI := ["fungi_coral_1", "fungi_coral_2", "fungi_coral_3", "fungi_polyp_1", "fungi_polyp_2", "fungi_polyp_3"]
const BIG_BOULDERS := ["big_boulders_0", "big_boulders_1", "big_boulders_2", "big_boulders_3", "big_boulders_4", "big_boulders_5"]
const BOULDERS := ["boulder_0", "boulder_1", "boulder_2", "boulder_3", "boulder_4", "boulder_5"]
const LOGS := ["redwood_hollow_log_0", "redwood_hollow_log_1", "redwood_hollow_log_2",
	"redwood_hollow_log2_0", "redwood_hollow_log2_1", "redwood_hollow_log2_2"]
const PEBBLES := ["rubble_sparse_1", "rubble_sparse_2", "rubble_sparse_3", "boulder_1", "boulder_3"]
const CAMP_PROPS := ["food_supplies_crat", "water_canister", "hiking_backpack", "plastic_storage_bin", "cooler_box_water"]
## Camp props fit this box (m) at up to this scale, this far apart (user feedback 2026-11-06: they
## read tiny next to the buildings and the forest).
const CAMP_PROP_SIZE := Vector2(1.9, 1.6)
const CAMP_PROP_MAX_SCALE := 2.6
const CAMP_PROP_SPACING := 2.3

const MAP_MIN := Vector2(-110.0, -90.0)
const MAP_MAX := Vector2(110.0, 82.0)
const CLEARING_RADIUS := 7.0
const TRAIL_HALF_WIDTH := 1.5
const ZONE_REFRESH_SEC := 1.0

@export var seed_value := 20261106
@export var with_environment := true
@export_group("Density")
## Metres between candidate points (jittered grid). Bigger = sparser.
@export var tree_spacing := 5.2
@export var floor_spacing := 1.9
@export var grass_spacing := 1.25
## All trees are scaled by this (1 = pack size).
@export var tree_scale := 0.78
## South of the clearing the camera looks over the trees: fewer and lower trees in this band (m).
@export var camera_band := 30.0
@export_group("Look")
## Keeps the full-detail mesh longer (Godot's generated LODs strip the leaf cards first).
@export var foliage_lod_bias := 8.0
## Leaf/grass alpha_cut is multiplied by this. Mipmaps average the leaf alpha down at a distance,
## so the pack's cut (0.5) makes far trees look bare; a lower cut keeps the needles.
@export_range(0.1, 1.0) var foliage_alpha_cut_scale := 0.45
@export var fog_density := 0.0008

var _rng := RandomNumberGenerator.new()
var _layout: Node3D
var _clearing := Rect2()
var _zones := {}          # expansion zone id -> Rect2 (world xz)
var _waters: Array = []   # {centre: Vector2, radii: Vector2}
var _trails: Array = []   # PackedVector2Array polylines
var _groups := {}         # expansion zone id -> {"forest": Node3D, "grass": Node3D}
var _counts := {}
var _refresh := 0.0
var _fixed_meshes := {}     # pack mesh -> copy with lower leaf alpha_cut
var _fixed_materials := {}


func _ready() -> void:
	_rng.seed = seed_value
	if with_environment:
		_environment()
	_layout = _find_layout()
	if _layout == null:
		push_warning("forest_dressing: no sibling Layout; only the environment is added")
		return
	# Markers are placed by the Layout scene; read them after it is ready.
	await get_tree().process_frame
	_read_layout()
	_ground()
	_water()
	if Models.has_assets():
		_forest()
		_clearing_plants()
		_resource_props()
		_camp()
	_refresh_zones()


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = ZONE_REFRESH_SEC
		_refresh_zones()


## Number of nature instances placed, by model (tests, sandbox info).
func instance_counts() -> Dictionary:
	return _counts


func _find_layout() -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	var layout := parent.get_node_or_null(^"Layout") as Node3D
	if layout != null:
		return layout
	for child in parent.get_children():
		if child != self and child.get_node_or_null(^"Navigation") != null:
			return child as Node3D
	return null


# ---------------------------------------------------------------- layout

func _read_layout() -> void:
	var start := Rect2()
	var first := true
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is ZoneMarker:
			var z := node as ZoneMarker
			var size := Vector2(z.size_cells) * ColonyMarker.CELL_SIZE
			var p := Vector2(z.global_position.x, z.global_position.z)
			var rect := Rect2(p - size * 0.5, size)
			if z.starts_cleared:
				start = rect if first else start.merge(rect)
				first = false
			else:
				_zones[z.zone_id] = rect
	_clearing = start.grow(2.0)
	var water := _layout.find_child("Water", true, false)
	if water != null:
		for body in water.get_children():
			if body is Node3D and body.has_meta(&"radii"):
				_waters.append({"centre": Vector2(body.global_position.x, body.global_position.z), "radii": body.get_meta(&"radii")})
	# A dirt trail from the clearing to every raid spawn (raids come down these).
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is RaidSpawnPoint:
			var to := Vector2(node.global_position.x, node.global_position.z)
			var from := Vector2(clampf(to.x, _clearing.position.x + 6, _clearing.end.x - 6),
				clampf(to.y, _clearing.position.y + 6, _clearing.end.y - 6))
			var mid := (from + to) * 0.5 + (to - from).orthogonal().normalized() * _rng.randf_range(-3.0, 3.0)
			_trails.append(PackedVector2Array([from, from.lerp(mid, 0.5), mid, mid.lerp(to, 0.5), to]))


func in_clearing(p: Vector2, pad := 0.0) -> bool:
	var r := _clearing.grow(pad)
	var rad := CLEARING_RADIUS + pad
	if not r.has_point(p):
		return false
	var c := Vector2(clampf(p.x, r.position.x + rad, r.end.x - rad), clampf(p.y, r.position.y + rad, r.end.y - rad))
	return p.distance_to(c) <= rad


func in_water(p: Vector2, pad := 0.0) -> bool:
	for w: Dictionary in _waters:
		var d: Vector2 = (p - w["centre"]) / (w["radii"] + Vector2(pad, pad))
		if d.length_squared() < 1.0:
			return true
	return false


func trail_distance(p: Vector2) -> float:
	var best := INF
	for line: PackedVector2Array in _trails:
		for i in line.size() - 1:
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1]).distance_to(p))
	return best


func _zone_at(p: Vector2) -> StringName:
	for id: StringName in _zones:
		if (_zones[id] as Rect2).has_point(p):
			return id
	return &""


func _refresh_zones() -> void:
	for id: StringName in _groups:
		var cleared := Colony.is_zone_cleared(id)
		var g: Dictionary = _groups[id]
		(g["forest"] as Node3D).visible = not cleared
		(g["grass"] as Node3D).visible = cleared


# ---------------------------------------------------------------- environment & ground

func _environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.62)
	sky_mat.sky_horizon_color = Color(0.66, 0.78, 0.8)
	sky_mat.ground_bottom_color = Color(0.16, 0.22, 0.16)
	sky_mat.ground_horizon_color = Color(0.66, 0.78, 0.8)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.74, 0.7)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.68, 0.7)
	env.fog_density = fog_density
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)


func _terrain_material(file: String, fallback: Color, uv_metres: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = fallback
	var path := TERRAIN + file
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.albedo_color = Color.WHITE
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / uv_metres
	return m


func _ground() -> void:
	var soil := PlaneMesh.new()
	soil.size = MAP_MAX - MAP_MIN
	_add_mesh(self, "ForestFloor", soil, Vector3((MAP_MIN.x + MAP_MAX.x) * 0.5, 0.01, (MAP_MIN.y + MAP_MAX.y) * 0.5),
		_terrain_material("soil_pine_a.png", Color("4a5a36"), 6.0))
	var edge := _clearing.grow(5.0)
	_add_mesh(self, "ClearingEdge", _rounded_rect(edge.size * 0.5, CLEARING_RADIUS + 5.0), _at(edge.get_center(), 0.03),
		_terrain_material("grass_pine_a.png", Color("5f8a3a"), 5.0))
	_add_mesh(self, "Clearing", _rounded_rect(_clearing.size * 0.5, CLEARING_RADIUS), _at(_clearing.get_center(), 0.05),
		_terrain_material("grass01_a.png", Color("7fb84a"), 4.0))
	var mud := _terrain_material("mud_a.png", Color("9a4e33"), 3.0)
	for i in _trails.size():
		_add_mesh(self, "Trail%d" % i, _strip(_trails[i], TRAIL_HALF_WIDTH), Vector3(0, 0.07, 0), mud)
	# Grass that shows once an expansion zone is cleared.
	for id: StringName in _zones:
		var rect: Rect2 = _zones[id]
		var forest := Node3D.new()
		forest.name = "Forest_%s" % id
		add_child(forest)
		var grass := Node3D.new()
		grass.name = "Cleared_%s" % id
		add_child(grass)
		_add_mesh(grass, "Grass", _rounded_rect(rect.size * 0.5, 4.0), _at(rect.get_center(), 0.05),
			_terrain_material("grass01_a.png", Color("7fb84a"), 4.0))
		_groups[id] = {"forest": forest, "grass": grass}


func _water() -> void:
	var shore := _terrain_material("mud_darker_a.png", Color("6b4630"), 3.0)
	for i in _waters.size():
		var w: Dictionary = _waters[i]
		var radii: Vector2 = w["radii"]
		var water := RealisticWater.material(minf(radii.x, radii.y) * WATER_DEPTH_PER_RADIUS)
		_add_mesh(self, "Shore%d" % i, _ellipse(radii + Vector2(3.0, 3.0)), _at(w["centre"], 0.04), shore)
		_add_mesh(self, "Water%d" % i, _water_mesh(radii), _at(w["centre"], 0.12), water)


## Elliptic disc in rings; UV2.x = how deep (0 at the shore, 1 in the middle) for the fake depth.
func _water_mesh(radii: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for r in WATER_RINGS:
		var t0 := float(r) / WATER_RINGS
		var t1 := float(r + 1) / WATER_RINGS
		for k in WATER_SEGMENTS:
			var a0 := k * TAU / WATER_SEGMENTS
			var a1 := (k + 1) * TAU / WATER_SEGMENTS
			var p00 := Vector3(cos(a0) * radii.x * t0, 0, sin(a0) * radii.y * t0)
			var p01 := Vector3(cos(a1) * radii.x * t0, 0, sin(a1) * radii.y * t0)
			var p10 := Vector3(cos(a0) * radii.x * t1, 0, sin(a0) * radii.y * t1)
			var p11 := Vector3(cos(a1) * radii.x * t1, 0, sin(a1) * radii.y * t1)
			if r > 0:
				_tri_depth(st, [p00, p10, p11], [t0, t1, t1])
			_tri_depth(st, [p00, p11, p01], [t0, t1, t0])
	return st.commit()


## Triangle facing up whose vertices carry the water depth in UV2.x (t = 0 middle .. 1 shore).
static func _tri_depth(st: SurfaceTool, p: Array, t: Array) -> void:
	var order := [0, 1, 2]
	if ((p[1] as Vector3) - p[0]).cross((p[2] as Vector3) - p[0]).y > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		st.set_uv2(Vector2(1.0 - pow(t[i], 2.0), 0.0))
		st.add_vertex(p[i])


func _at(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _add_mesh(parent: Node, n: String, mesh: Mesh, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _rounded_rect(half: Vector2, r: float) -> ArrayMesh:
	r = minf(r, minf(half.x, half.y))
	var pts := PackedVector2Array()
	var corners := [Vector2(half.x - r, half.y - r), Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r), Vector2(half.x - r, -half.y + r)]
	for i in 4:
		for k in 9:
			var a := (i * 90.0 + k * 11.25) * PI / 180.0
			pts.append(corners[i] + Vector2(cos(a), sin(a)) * r)
	return _fan(pts)


func _ellipse(radii: Vector2) -> ArrayMesh:
	var pts := PackedVector2Array()
	for k in 64:
		var a := k * TAU / 64.0
		pts.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return _fan(pts)


func _fan(outline: PackedVector2Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_tri(st, Vector3.ZERO, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y))
	return st.commit()


func _strip(points: PackedVector2Array, half_w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).normalized().orthogonal() * half_w
		var q := [a + side, a - side, b - side, b + side]
		var v3: Array[Vector3] = []
		for v: Vector2 in q:
			v3.append(Vector3(v.x, 0, v.y))
		_tri(st, v3[0], v3[1], v3[2])
		_tri(st, v3[0], v3[2], v3[3])
		for k in 16:
			var a0 := k * TAU / 16.0
			var a1 := (k + 1) * TAU / 16.0
			_tri(st, Vector3(b.x, 0, b.y), Vector3(b.x + cos(a0) * half_w, 0, b.y + sin(a0) * half_w),
				Vector3(b.x + cos(a1) * half_w, 0, b.y + sin(a1) * half_w))
	return st.commit()


## Adds a triangle facing up (Godot front faces are clockwise seen from the front).
static func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	if (p1 - p0).cross(p2 - p0).y > 0.0:
		var tmp := p1
		p1 = p2
		p2 = tmp
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)


# ---------------------------------------------------------------- scatter

## Jittered grid; `accept(p)` decides, `pick(p)` returns [model, scale] or []. Instances inside an
## expansion zone go under that zone's forest node so they vanish when it is cleared.
func _scatter(spacing: float, accept: Callable, pick: Callable, rect := Rect2(), shadows := true) -> void:
	if rect.size == Vector2.ZERO:
		rect = Rect2(MAP_MIN, MAP_MAX - MAP_MIN)
	var batches := {}
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var p := Vector2(x + _rng.randf() * spacing, y + _rng.randf() * spacing)
			x += spacing
			if not accept.call(p):
				continue
			var choice: Array = pick.call(p)
			if choice.is_empty():
				continue
			var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * choice[1]), Vector3(p.x, 0, p.y))
			var key := "%s|%s" % [_zone_at(p), choice[0]]
			if not batches.has(key):
				batches[key] = []
			batches[key].append(t)
		y += spacing
	for key: String in batches:
		var zone := StringName(key.get_slice("|", 0))
		var parent: Node = self if zone == &"" else _groups[zone]["forest"]
		_multimesh(parent, key.get_slice("|", 1), batches[key], shadows)


func _multimesh(parent: Node, model: String, transforms: Array, shadows: bool) -> void:
	var parts := Models.mesh_parts(model)
	if parts.is_empty():
		return
	_counts[model] = _counts.get(model, 0) + transforms.size()
	for i in parts.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _foliage_mesh(parts[i]["mesh"])
		mm.instance_count = transforms.size()
		for k in transforms.size():
			mm.set_instance_transform(k, transforms[k] * parts[i]["xform"])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [model, i]
		mmi.multimesh = mm
		mmi.lod_bias = foliage_lod_bias
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


## The mesh with every alpha-cut surface (leaves, needles, grass) given a lower cut, cached.
func _foliage_mesh(mesh: Mesh) -> Mesh:
	if _fixed_meshes.has(mesh):
		return _fixed_meshes[mesh]
	var out := mesh
	if mesh is ArrayMesh and foliage_alpha_cut_scale < 1.0:
		var copy := mesh.duplicate() as ArrayMesh
		var changed := false
		for s in copy.get_surface_count():
			var m := copy.surface_get_material(s) as ShaderMaterial
			if m == null:
				continue
			var cut: Variant = m.get_shader_parameter(&"alpha_cut")
			if typeof(cut) == TYPE_FLOAT and cut > 0.0:
				if not _fixed_materials.has(m):
					var fixed := m.duplicate() as ShaderMaterial
					fixed.set_shader_parameter(&"alpha_cut", cut * foliage_alpha_cut_scale)
					_fixed_materials[m] = fixed
				copy.surface_set_material(s, _fixed_materials[m])
				changed = true
		if changed:
			out = copy
	_fixed_meshes[mesh] = out
	return out


func _pick(options: Array, smin: float, smax: float) -> Array:
	return [options[_rng.randi() % options.size()], _rng.randf_range(smin, smax)]


func _forest() -> void:
	_scatter(tree_spacing, _forest_ok.bind(4.0), _pick_tree)
	_scatter(floor_spacing, _forest_ok.bind(1.0), _pick_floor, Rect2(), false)
	_scatter(12.0, _forest_ok.bind(3.0), _pick_rock)
	for w: Dictionary in _waters:
		var r: Vector2 = w["radii"] + Vector2(4, 4)
		_scatter(1.5, _shore.bind(w), _pick_pebble, Rect2(w["centre"] - r, r * 2.0), false)
	_scatter(1.1, _trail_side, _pick_trail_grass, Rect2(), false)


func _forest_ok(p: Vector2, pad: float) -> bool:
	return not in_clearing(p, pad) and not in_water(p, pad * 0.8) and trail_distance(p) > TRAIL_HALF_WIDTH + pad * 0.5


func _shore(p: Vector2, w: Dictionary) -> bool:
	var d: Vector2 = (p - w["centre"]) / w["radii"]
	var dist := d.length()
	return dist > 1.03 and dist < 1.0 + 3.2 / minf(w["radii"].x, w["radii"].y)


func _trail_side(p: Vector2) -> bool:
	var d := trail_distance(p)
	return d > TRAIL_HALF_WIDTH and d < TRAIL_HALF_WIDTH + 2.0 and not in_clearing(p) and not in_water(p, 1.0)


## How far south of the clearing a point is, inside the camera band (0 = not in the band, 1 = at the edge).
func _camera_band_weight(p: Vector2) -> float:
	var below := p.y - _clearing.end.y
	if below < 0.0 or below > camera_band or p.x < _clearing.position.x - 25.0 or p.x > _clearing.end.x + 25.0:
		return 0.0
	return 1.0 - below / camera_band


func _edge_depth(p: Vector2) -> float:
	var c := _clearing.get_center()
	var h := _clearing.size * 0.5
	return maxf(absf(p.x - c.x) - h.x, absf(p.y - c.y) - h.y)


func _pick_tree(p: Vector2) -> Array:
	var band := _camera_band_weight(p)
	if band > 0.0 and _rng.randf() < 0.35 + band * 0.45:
		return []
	var low := 1.0 - band * 0.45   # south band: lower trees
	var depth := _edge_depth(p)
	var r := _rng.randf()
	var s := tree_scale * low
	if band == 0.0 and r < clampf(0.06 + depth / 80.0, 0.06, 0.4):
		return _pick(SEQUOIA, 0.8 * s, 1.2 * s)
	if r < 0.72:
		return _pick(FIR, (0.6 + minf(depth / 45.0, 0.5)) * s, (1.0 + minf(depth / 35.0, 0.4)) * s)
	return _pick(PINE, 0.7 * s, 1.15 * s)


func _pick_floor(_p: Vector2) -> Array:
	var r := _rng.randf()
	if r < 0.32:
		return _pick(FERNS, 0.8, 1.3)
	if r < 0.52:
		return _pick(GRASS, 0.9, 1.3)
	if r < 0.62:
		return _pick(["dead_leaves_1", "dead_leaves_2"], 0.8, 1.2)
	if r < 0.67:
		return _pick(["magnus_1", "magnus_2"], 0.8, 1.2)
	if r < 0.7:
		return _pick(FUNGI, 0.8, 1.3)
	if r < 0.72:
		return _pick(["branches", "red_fir_branches"], 0.8, 1.2)
	return []


func _pick_rock(_p: Vector2) -> Array:
	var r := _rng.randf()
	if r < 0.2:
		return _pick(BIG_BOULDERS, 0.3, 0.5)  # rocks halved (user feedback 2026-11-06)
	if r < 0.5:
		return _pick(BOULDERS, 0.35, 0.65)
	if r < 0.65:
		return _pick(LOGS, 0.8, 1.1)
	return []


func _pick_pebble(_p: Vector2) -> Array:
	if _rng.randf() < 0.5:
		return _pick(PEBBLES, 0.2, 0.45)
	return []


func _pick_trail_grass(_p: Vector2) -> Array:
	if _rng.randf() < 0.6:
		return _pick(GRASS + CLOVERS, 0.9, 1.3)
	return []


func _clearing_plants() -> void:
	# Only grass and white-flower clover in the clearing (buildings go here).
	_scatter(grass_spacing, _clearing_ok, _pick_clearing, _clearing.grow(4.0), false)


func _clearing_ok(p: Vector2) -> bool:
	return in_clearing(p, 3.0) and trail_distance(p) > TRAIL_HALF_WIDTH


func _pick_clearing(p: Vector2) -> Array:
	var r := _rng.randf()
	if not in_clearing(p, 0.0):
		return _pick(GRASS + ["thin_fern1", "thin_fern2"], 1.0, 1.4)
	if r < 0.3:
		return _pick(GRASS, 0.6, 1.0)
	if r < 0.42:
		return _pick(CLOVERS, 0.8, 1.2)
	return []


# ---------------------------------------------------------------- props on markers

## A tree on every TREE resource node and a boulder pile on every DEBRIS node (벌목·채석 노드).
func _resource_props() -> void:
	var trees: Array = []
	var rocks: Array = []
	for node in _layout.find_children("*", "Marker3D", true, false):
		if node is ResourceNode:
			var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), (node as Node3D).global_position)
			if (node as ResourceNode).kind == ResourceNode.Kind.TREE:
				trees.append(t.scaled_local(Vector3.ONE * tree_scale))
			else:
				rocks.append(t)
	if not trees.is_empty():
		_multimesh(self, "red_fir3", trees, true)
	if not rocks.is_empty():
		_multimesh(self, "big_boulders_2", rocks, true)
		var rubble: Array = []
		for t: Transform3D in rocks:
			rubble.append(t.translated(Vector3(2.0, 0, 1.5)))
		_multimesh(self, "rubble_dense_1", rubble, false)


## The prebuilt 방송실 at the radio work spot, sleeping bags on the start beds, supplies by the fire.
func _camp() -> void:
	var radio := _layout.find_children("Work_Radio", "Marker3D", true, false)
	if not radio.is_empty():
		var room := Models.build(&"radio_room", Vector2i(4, 3))
		room.name = "RadioRoom"
		room.position = (radio[0] as Node3D).global_position + Vector3(0, 0, -1.0)
		add_child(room)
	var beds := _layout.get_node_or_null(^"BedSpots")
	if beds != null:
		var bags: Array = []
		for spot in beds.get_children():
			if spot is Node3D:
				bags.append(Models.fit_transform("military_sleeping_bag", (spot as Node3D).global_position, 0.0, 0.9, 2.0))
		if not bags.is_empty():
			_multimesh(self, "military_sleeping_bag", bags, false)
	var gather := _layout.get_node_or_null(^"GatherPoint") as Node3D
	if gather != null:
		for i in CAMP_PROPS.size():
			var at := gather.global_position + Vector3(-5.0 + i * CAMP_PROP_SPACING, 0, -3.0)
			var holder := Node3D.new()
			holder.name = "Camp_%s" % CAMP_PROPS[i]
			holder.transform = Models.fit_transform(CAMP_PROPS[i], at, _rng.randf_range(-20, 20),
					CAMP_PROP_SIZE.x, CAMP_PROP_SIZE.y, false, CAMP_PROP_MAX_SCALE)
			for part: Dictionary in Models.mesh_parts(CAMP_PROPS[i]):
				var mi := MeshInstance3D.new()
				mi.mesh = part["mesh"]
				mi.transform = part["xform"]
				holder.add_child(mi)
			add_child(holder)
