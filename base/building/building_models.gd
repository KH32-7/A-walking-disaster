extends RefCounted
## What each base building looks like, made of American Suburb models (BuildingViews, base dressing).
## Used by BuildingViews for completed buildings and by the base dressing for the prebuilt 방송실.
## Models are found by file name at runtime, so a clone without the private
## assets/ submodule just gets grey boxes.
##
## Each part: [model, u, v, fw, fd, rot_deg, mode, y]
##   u, v    part centre as a fraction of the footprint (-0.5 .. 0.5), x and z
##   fw, fd  the largest size the part may take, as a fraction of the footprint width / depth
##   rot_deg turn around Y (multiples of 90)
##   mode    "fit" (default): uniform scale so it fits fw × fd (at most FIT_MAX_SCALE)
##           "fill": stretch x/z to exactly fw × fd (floors, pads)
##   y       lift in metres (default 0)

const SUBURB_DIR := "res://assets/environment/city/american_suburb/models/"
const NATURE_DIR := "res://assets/environment/nature/pure_nature_redwood/models/"
const CELL := 2.0
const FIT_MAX_SCALE := 1.6
## Every building model is drawn this much larger than its footprint, scaled from the footprint's
## centre (user feedback 2026-11-06: buildings looked small next to the forest). The grid footprint,
## placement and collision are unchanged; only the look grows.
const VISUAL_SCALE := 1.35

## Buildings with no grid size in data (prebuilt / attached) get a sandbox footprint here.
const SIZE_OVERRIDE := {&"radio_room": Vector2i(3, 3)}
const NAME_OVERRIDE := {&"radio_room": "방송실"}

const MODELS := {
	# 주거
	&"bed": [["military_folding_cot", 0, -0.1, 0.9, 0.8, 0], ["rolled_sleeping_bag", 0.2, 0.35, 0.4, 0.2, 90]],
	&"dormitory": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["exterior_only_house_01", 0, 0, 0.95, 0.95, 0]],
	&"family_house": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["exterior_only_house_04", 0, -0.05, 0.95, 0.85, 0], ["rural_mailbox_01", 0.42, 0.45, 0.1, 0.1, 0]],
	# 생산
	&"lumber_yard": [["firewood_rack", -0.15, -0.25, 0.7, 0.4, 0], ["redwood_hollow_log_0", 0.1, 0.25, 0.8, 0.35, 90], ["wheelbarrow", 0.38, -0.3, 0.25, 0.25, 0]],
	&"quarry": [["rubble_dense_1", -0.1, -0.1, 0.8, 0.8, 0], ["wheelbarrow", 0.35, 0.3, 0.3, 0.3, 0], ["tool_box", -0.35, 0.35, 0.2, 0.2, 0]],
	&"salvage_yard": [["pile_garbage_01", -0.2, -0.1, 0.6, 0.7, 0], ["military_vehicle_parts_crate", 0.3, -0.25, 0.35, 0.35, 0], ["barrel_01", 0.3, 0.3, 0.2, 0.2, 0]],
	&"vegetable_garden": [["house_wooden_deck_c_2x4m", 0, 0, 1, 1, 0, "fill"], ["magnus_1", -0.25, -0.25, 0.4, 0.4, 0, "fit", 0.1], ["magnus_2", 0.25, -0.25, 0.4, 0.4, 0, "fit", 0.1], ["magnus_1", -0.25, 0.25, 0.4, 0.4, 90, "fit", 0.1], ["compost_bin", 0.3, 0.3, 0.3, 0.3, 0, "fit", 0.1]],
	&"rain_tank": [["plastic_barrel_01", -0.25, -0.25, 0.4, 0.4, 0], ["plastic_barrel_02", 0.25, -0.25, 0.4, 0.4, 0], ["plastic_barrel_01", -0.25, 0.25, 0.4, 0.4, 0], ["garden_hose", 0.25, 0.25, 0.35, 0.35, 0]],
	# 가공
	&"kitchen": [["canopy_01", 0, 0, 1, 1, 0], ["kitchen_a_01", 0, -0.3, 0.8, 0.3, 0], ["charcoal_grill_ball", -0.3, 0.3, 0.25, 0.2, 0], ["fridge_01", 0.35, 0.25, 0.25, 0.2, 180]],
	&"carpentry_shop": [["house_wooden_deck_c_4x4m", 0, 0, 1, 1, 0, "fill"], ["backyard_shed_03", -0.2, -0.2, 0.55, 0.55, 0], ["workbench", 0.28, 0.2, 0.35, 0.25, 0], ["firewood_rack", -0.25, 0.32, 0.45, 0.25, 0], ["pallet", 0.3, -0.3, 0.3, 0.3, 0]],
	# 생활
	&"dining_hall": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["military_field_canopy_01", 0, 0, 0.95, 0.95, 0], ["outdoor_dining_table_a", -0.2, -0.1, 0.35, 0.3, 0], ["outdoor_dining_table_b", 0.2, 0.15, 0.35, 0.3, 0], ["patio_umbrella", 0.35, -0.35, 0.2, 0.2, 0]],
	&"bonfire": [["campfire_patio", 0, 0, 1, 1, 0]],
	&"infirmary": [["military_arched_tent_exterior", 0, 0, 0.95, 0.95, 0], ["medical_supplies_crate", 0.38, 0.4, 0.2, 0.15, 0], ["medical_duffel_bag", -0.38, 0.42, 0.18, 0.12, 0]],
	&"memorial": [["sheriff_office_monument_sign", 0, 0, 0.9, 0.9, 0]],
	# 제작
	&"workshop": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["military_field_canopy_01", 0, 0, 0.95, 0.95, 0], ["workbench", -0.2, -0.3, 0.4, 0.25, 0], ["tool_cabinet", 0.3, -0.35, 0.25, 0.2, 0], ["military_vehicle_parts_crate", 0.25, 0.25, 0.3, 0.3, 0], ["tool_box_green", -0.3, 0.3, 0.15, 0.15, 0]],
	&"sewing_room": [["backyard_shed_04", 0, -0.1, 0.8, 0.7, 0], ["ironing_board", -0.3, 0.38, 0.3, 0.15, 0], ["basket_dirty_clothes", 0.3, 0.38, 0.15, 0.15, 0]],
	&"essence_workshop": [["military_command_tent_exterior", 0, 0, 0.95, 0.95, 0], ["display_cabinet_01", 0.38, 0.4, 0.2, 0.15, 0]],
	# 포용
	&"ramp": [["house_wooden_deck_c_2x4m", 0, 0, 1, 1, 0, "fill"], ["house_porch_railing_a_2m", -0.45, 0, 0.1, 1, 90]],
	&"elevator": [["concrete_patio_2x2m", 0, 0, 1, 1, 0, "fill"], ["guard_booth_metal", 0, 0, 0.8, 0.8, 0], ["electrical_panel", 0.42, 0.42, 0.15, 0.1, 0]],
	&"picture_sign": [["campaign_yard_sign_01", 0, 0, 0.8, 0.8, 0]],
	&"warning_light": [["traffic_light_small", 0, 0, 0.6, 0.6, 0]],
	&"daycare": [["house_wooden_deck_c_4x4m", 0, 0, 1, 1, 0, "fill"], ["small_kids_slide", -0.2, -0.2, 0.5, 0.5, 0], ["wooden_swing", 0.25, 0.15, 0.45, 0.5, 90], ["backyard_trampoline", -0.25, 0.3, 0.35, 0.35, 0]],
	&"classroom": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["military_field_canopy_01", 0, 0, 0.95, 0.95, 0], ["plastic_table", 0, -0.1, 0.4, 0.3, 0], ["chair_01", -0.2, 0.2, 0.12, 0.15, 180], ["chair_02", 0, 0.2, 0.12, 0.15, 180], ["chair_03", 0.2, 0.2, 0.12, 0.15, 180], ["bookcase_01", -0.4, -0.35, 0.15, 0.25, 90]],
	# 보관
	&"warehouse": [["backyard_shed_05", 0, -0.1, 0.9, 0.8, 0], ["store_inventory_stack_01", -0.3, 0.38, 0.3, 0.2, 0], ["cardboard_box_01", 0.3, 0.4, 0.15, 0.15, 0], ["pallet", 0.1, 0.4, 0.25, 0.2, 0]],
	&"armory_room": [["backyard_shed_03", 0, -0.1, 0.85, 0.75, 0], ["armory_cabinet_01", -0.3, 0.38, 0.25, 0.15, 0], ["military_rifle_crate", 0.25, 0.4, 0.3, 0.15, 0], ["ammo_box", 0.42, 0.25, 0.12, 0.1, 0]],
	# 군사
	&"training_ground": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["basketball_hoop", -0.38, -0.38, 0.2, 0.2, 0], ["sandbag_pile_01", 0.2, -0.3, 0.4, 0.2, 0], ["anti_tank_hedgehog", -0.15, 0.2, 0.2, 0.2, 0], ["military_rifle_crate", 0.3, 0.3, 0.25, 0.15, 0]],
	# 특수
	&"radio_room": [["house_wooden_deck_c_4x4m", 0, 0, 1, 1, 0, "fill"], ["backyard_shed_05", -0.1, -0.1, 0.7, 0.7, 0], ["electrical_pole_01", 0.38, -0.38, 0.15, 0.15, 0], ["satellite_dish", 0.3, 0.3, 0.2, 0.2, 0], ["speaker_box", -0.4, 0.4, 0.12, 0.12, 0], ["handheld_radio", 0.1, 0.42, 0.08, 0.08, 0]],
	&"radio_tower": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["electrical_pole_03", 0, 0, 0.3, 0.3, 0], ["satellite_dish", -0.3, 0.3, 0.3, 0.3, 0], ["satellite_dish", 0.3, -0.3, 0.3, 0.3, 90]],
	# 설비
	&"generator": [["concrete_patio_2x2m", 0, 0, 1, 1, 0, "fill"], ["military_generator_large", 0, -0.05, 0.85, 0.75, 0], ["fuel_canister", 0.4, 0.4, 0.15, 0.15, 0]],
	&"solar_panel": [["solar_battery_01", 0, -0.1, 0.9, 0.7, 0], ["portable_power_station", 0.35, 0.38, 0.2, 0.15, 0]],
	# 방어
	&"palisade": [["fence_d_2m", 0, 0, 1, 0.3, 0]],
	&"stone_wall": [["concrete_road_barrier", 0, 0, 1, 0.5, 0]],
	&"iron_wall": [["hesco_barrier_01", 0, 0, 1, 1, 0]],
	&"wooden_gate": [["fence_c_gate", 0, 0, 1, 0.5, 0]],
	&"iron_gate": [["fence_b_gate", 0, 0, 1, 0.5, 0]],
	&"guard_post": [["guard_booth", 0, -0.1, 0.7, 0.7, 0], ["sandbag_pile_02", 0, 0.38, 0.8, 0.2, 0]],
	&"shelter": [["concrete_patio_4x4m", 0, 0, 1, 1, 0, "fill"], ["backyard_shed_01", 0, 0, 0.65, 0.65, 0], ["sandbag_pile_03", 0, -0.43, 0.8, 0.12, 0], ["sandbag_pile_04", -0.43, 0, 0.8, 0.12, 90], ["sandbag_pile_05", 0.43, 0, 0.8, 0.12, 90]],
	&"spike_trap": [["spike_strip", 0, 0, 0.9, 0.9, 0]],
	&"warning_bell": [["flagpole", 0, 0, 0.5, 0.5, 0]],
	&"essence_lamp": [["parking_lot_light_pole_02", 0, 0, 0.6, 0.6, 0]],
	&"light_tower": [["mobile_light_tower", 0, 0, 0.9, 0.9, 0]],
	&"noise_decoy": [["speaker_box", 0, 0, 0.6, 0.6, 0], ["tv_box", 0.25, 0.3, 0.3, 0.3, 0]],
}

static var _index := {}
static var _parts := {}


## Every FBX in both packs by base name (e.g. "backyard_shed_03" -> its res:// path).
static func build_index() -> void:
	if not _index.is_empty():
		return
	_scan(SUBURB_DIR)
	_scan(NATURE_DIR)


static func has_assets() -> bool:
	build_index()
	return not _index.is_empty()


static func missing_models() -> PackedStringArray:
	build_index()
	var out := PackedStringArray()
	for id: StringName in MODELS:
		for part: Array in MODELS[id]:
			if not _index.has(part[0]) and not out.has(part[0]):
				out.append(part[0])
	return out


static func _scan(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_scan(dir + sub + "/")
	for f in d.get_files():
		if f.get_extension().to_lower() == "fbx":
			_index[f.get_basename()] = dir + f


## [{mesh, xform}] of one model, cached. Empty when the model is missing.
static func mesh_parts(model: String) -> Array:
	build_index()
	if _parts.has(model):
		return _parts[model]
	var out: Array = []
	var path: String = _index.get(model, "")
	if path != "" and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene:
			var root := scene.instantiate()
			_collect(root, Transform3D.IDENTITY, out, true)
			root.free()
	_parts[model] = out
	return out


static func _collect(node: Node, parent_xf: Transform3D, out: Array, is_root: bool) -> void:
	var xf := parent_xf
	if node is Node3D and not is_root:
		xf = parent_xf * (node as Node3D).transform
	var mi := node as MeshInstance3D
	if mi and mi.mesh and mi.visible:
		var mesh: Mesh = mi.mesh
		var overridden := mi.material_override != null
		for s in mesh.get_surface_count():
			overridden = overridden or mi.get_surface_override_material(s) != null
		if overridden and mesh is ArrayMesh:
			mesh = mesh.duplicate() as Mesh
			for s in mesh.get_surface_count():
				var m := mi.material_override if mi.material_override else mi.get_surface_override_material(s)
				if m:
					mesh.surface_set_material(s, m)
		out.append({"mesh": mesh, "xform": xf})
	for child in node.get_children():
		_collect(child, xf, out, false)


static func model_aabb(model: String) -> AABB:
	var box := AABB()
	var first := true
	for p: Dictionary in mesh_parts(model):
		var b: AABB = p["xform"] * (p["mesh"] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Transform that puts `model` with its footprint centre at (x, y, z), turned and scaled.
static func fit_transform(model: String, at: Vector3, rot_deg: float, local_w: float, local_d: float,
		fill := false, max_scale := FIT_MAX_SCALE) -> Transform3D:
	var box := model_aabb(model)
	if box.size.x <= 0.001 or box.size.z <= 0.001:
		return Transform3D(Basis.IDENTITY, at)
	var sc := Vector3.ONE
	if fill:
		sc = Vector3(local_w / box.size.x, 1.0, local_d / box.size.z)
	else:
		var k := clampf(minf(local_w / box.size.x, local_d / box.size.z), 0.02, max_scale)
		sc = Vector3(k, k, k)
	var basis := Basis(Vector3.UP, deg_to_rad(rot_deg)) * Basis.from_scale(sc)
	var anchor := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return Transform3D(basis, at - basis * anchor)


## A node with every part of one building, centred on its footprint. Grey box if nothing loads.
static func build(def_id: StringName, size_cells: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = String(def_id)
	var w := size_cells.x * CELL
	var d := size_cells.y * CELL
	var placed := 0
	for part: Array in MODELS.get(def_id, []):
		var model: String = part[0]
		if mesh_parts(model).is_empty():
			continue
		var rot: float = part[5]
		var swapped := int(roundf(rot / 90.0)) % 2 != 0
		var tw: float = part[3] * w
		var td: float = part[4] * d
		var fill: bool = part.size() > 6 and part[6] == "fill"
		var lift: float = part[7] if part.size() > 7 else 0.0
		var at := Vector3(part[1] * w, lift, part[2] * d)
		var xf := fit_transform(model, at, rot, td if swapped else tw, tw if swapped else td, fill)
		var holder := Node3D.new()
		holder.name = "%s_%d" % [model, placed]
		holder.transform = Transform3D(Basis.from_scale(Vector3.ONE * VISUAL_SCALE)) * xf
		for p: Dictionary in mesh_parts(model):
			var mi := MeshInstance3D.new()
			mi.mesh = p["mesh"]
			mi.transform = p["xform"]
			holder.add_child(mi)
		root.add_child(holder)
		placed += 1
	if placed == 0:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(w - 0.2, 2.0, d - 0.2)
		box.mesh = mesh
		box.position.y = 1.0
		root.add_child(box)
	return root
