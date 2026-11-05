extends Node
## D-10: RegionDressing reads a sibling Layout read-only and adds environment, water and vines.


func run() -> bool:
	var ok := true
	var map := Node3D.new()
	add_child(map)
	var layout := Node3D.new()
	layout.name = "Layout"
	map.add_child(layout)
	var wall := CSGBox3D.new()
	wall.name = "Wall0"
	wall.size = Vector3(20, 3, 0.3)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("c9ccc6")
	wall.material = gm
	layout.add_child(wall)
	var water_root := Node3D.new()
	water_root.name = "DeepWater"
	layout.add_child(water_root)
	var surf := CSGBox3D.new()
	surf.name = "Surface0"
	surf.size = Vector3(10, 0.1, 10)
	water_root.add_child(surf)
	var standing := _lamp_post(map, Vector3(5, 0, 5), false)
	_lamp_post(map, Vector3(-5, 0, 5), true)
	# The layout builder's own omni over each post (also over the fallen one) and a light tower's.
	var builder_lamps: Array[OmniLight3D] = []
	for at: Vector3 in [Vector3(5, 6.4, 5), Vector3(-5, 6.4, 5), Vector3(30, 7.0, 0)]:
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		map.add_child(lamp, true)
		lamp.position = at
		builder_lamps.append(lamp)
	var d: RegionDressing = load("res://levels/field/flooded_mall/dressing.tscn").instantiate()
	map.add_child(d)
	await get_tree().process_frame
	await get_tree().process_frame
	ok = _expect(d.street_light_count() == 1, "only the standing lamp post lights up (%d)" % d.street_light_count()) and ok
	ok = _expect(not builder_lamps[0].visible and not builder_lamps[1].visible and builder_lamps[2].visible,
		"the builder's lamp-post omnis go off, a light tower's stays") and ok
	var spot: SpotLight3D = null
	for c in d.get_children():
		if c is SpotLight3D:
			spot = c
	if spot != null:
		ok = _expect(spot.global_position.distance_to(standing.global_position + Vector3(0, 6.5, 0)) < 0.2,
			"the lamp hangs at the top of the post") and ok
		ok = _expect((-spot.global_basis.z).dot(Vector3.DOWN) > 0.99, "the lamp shines straight down") and ok
		FieldState.dusk_started.emit()
		ok = _expect(is_equal_approx(spot.light_energy, d.street_light_energy * d.street_light_dusk_mult),
			"lamps brighten at dusk") and ok
	ok = _expect(d.get_node_or_null(^"DressingEnvironment") != null and d.get_node_or_null(^"Sun") != null,
		"environment + sun added") and ok
	ok = _expect(wall.material is ShaderMaterial, "greybox wall drawn with the toon shader") and ok
	ok = _expect(gm.albedo_color == Color("c9ccc6"), "layout material resource itself untouched") and ok
	ok = _expect((surf.material as ShaderMaterial).shader == preload("res://art/shaders/water_toon.gdshader"),
		"deep-water surface gets the water shader") and ok
	ok = _expect(d.get_child_count() > 4, "vines / debris added") and ok
	ok = _expect(ResourceLoader.exists("res://art/dressing/presets/base_school.tscn"), "base dressing preset exists") and ok
	map.queue_free()
	return ok


## A stand-in for the pack lamp post (6.8 m box) that the dressing recognises by its scene file.
func _lamp_post(map: Node3D, at: Vector3, fallen: bool) -> Node3D:
	var post := Node3D.new()
	post.scene_file_path = "res://assets/environment/city/american_suburb/models/outdoor_environment/parking_lot_light_pole_01.fbx"
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 6.8, 0.3)
	mi.mesh = box
	mi.position = Vector3(0, 3.4, 0)
	post.add_child(mi)
	map.add_child(post)
	post.position = at
	if fallen:
		post.rotation_degrees = Vector3(0, 0, 90)
	return post


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
