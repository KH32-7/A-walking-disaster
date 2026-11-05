extends Node
## D-09: appearance presets load (5+), apply() builds a body, colours come from the appearance dict.


func run() -> bool:
	var ok := true
	var ids := CharacterLook.preset_ids()
	ok = _expect(ids.size() >= 5, "at least 5 appearance presets (%d)" % ids.size()) and ok
	var c: CharacterLook = load("res://art/characters/character.tscn").instantiate()
	add_child(c)
	c.apply({"preset": &"bob_teal", "hair_color": Color.RED})
	ok = _expect(c.get_child_count() == 1 and c.get_child(0).get_child_count() > 5, "placeholder body built") and ok
	var reds := 0
	for n in c.get_child(0).get_children():
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if m != null and m.get_shader_parameter(&"albedo") == Color.RED:
			reds += 1
	ok = _expect(reds >= 1, "hair colour override applied") and ok
	c.age_stage = 1
	ok = _expect(c.get_child(c.get_child_count() - 1).scale.x < 1.0, "child scale") and ok
	c.queue_free()
	return ok


func _expect(cond: bool, message: String) -> bool:
	if not cond:
		printerr(message)
	return cond
