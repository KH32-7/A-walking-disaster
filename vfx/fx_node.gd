class_name FxNode
extends Node3D
## One live effect (D-18). Owner: Lane D. Fx builds it from an FxDef; it frees itself when done.
## Pieces: GPUParticles3D (PARTICLES), MeshInstance3D (MESH, GROUND, BEAM), OmniLight3D (LIGHT).
## Every texture and mesh comes from res://assets/vfx/ by path; a missing file drops that layer and an
## effect with no layer left is not built at all (clone without the assets submodule: silent).
## TELEGRAPH (boss area warning) is the exception: it is gameplay information, drawn by a repo shader
## and shown with or without assets.

const SHADER_ADD := preload("res://vfx/shaders/fx_add.gdshader")
const SHADER_MIX := preload("res://vfx/shaders/fx_mix.gdshader")
const SHADER_TELEGRAPH := preload("res://vfx/shaders/fx_telegraph.gdshader")
const TELEGRAPH_SHAPES := {&"circle": 0, &"ring": 1, &"cone": 2, &"line": 3}
static var _telegraph_mat: ShaderMaterial
## BEAM: default streak speed when params.speed is not given (m/s).
const TRACER_SPEED := 120.0
## Looping layers fade out over this many seconds at the end of the effect.
const LOOP_FADE_OUT := 0.4
## Settings.reduce_flash: flash layers and lights keep this much.
const REDUCED_FLASH := 0.35

static var _exists := {}  # path -> bool
static var _meshes := {}  # path -> [Mesh, Transform3D] or null
static var _materials := {}  # "layer id/element/texture" -> ShaderMaterial
static var _process_mats := {}  # "layer id/element/k/dim" -> ParticleProcessMaterial

var effect_id: StringName
var params: Dictionary = {}
var lifetime := 0.5
var age := 0.0

var _parts: Array[Dictionary] = []  # {layer, node, k, started}
var _dim := 1.0


## False when nothing could be built (all layers filtered out or their files missing).
func build(def: FxDef, p: Dictionary, reduced_flash: bool) -> bool:
	effect_id = def.id
	params = p
	_dim = REDUCED_FLASH if reduced_flash else 1.0
	var radius := float(p.get("radius", 0.0))
	var k := radius / def.base_radius if radius > 0.0 and def.base_radius > 0.0 else 1.0
	var element := int(p.get("element", Enums.Element.NONE))
	lifetime = def.lifetime
	var fixed := def.lifetime_param != &"" and p.has(def.lifetime_param)
	if fixed:
		lifetime = maxf(float(p[def.lifetime_param]), 0.05)
	for layer in def.layers:
		if layer == null or not _matches(layer.when, p):
			continue
		if layer.night_only and not Fx.night_lights:
			continue
		var lk := k if layer.follow_radius else 1.0
		var node := _make(layer, element, lk)
		if node == null:
			continue
		add_child(node)
		node.visible = false
		_parts.append({"layer": layer, "node": node, "k": lk, "started": false})
		if not fixed:
			lifetime = maxf(lifetime, _layer_end(layer))
		elif layer.kind == FxLayer.Kind.TELEGRAPH:
			lifetime += layer.lifetime  # stays solid through the wind-up, then lingers this long
	# Lights need no texture, so on a clone without assets/ an effect can end up as a lone light.
	# That counts as "assets missing" too: skip it like the rest (Fx docs, test_monster_visuals).
	if _parts.is_empty() or _parts.all(func(part): return part["layer"].kind == FxLayer.Kind.LIGHT):
		return false
	advance(0.0)
	return true


func _process(delta: float) -> void:
	advance(delta)


## Steps the effect. Tests and previews may call it directly.
func advance(delta: float) -> void:
	age += delta
	for part in _parts:
		_update(part)
	if age >= lifetime and not is_queued_for_deletion():
		queue_free()


static func file_exists(path: String) -> bool:
	if path.is_empty():
		return true
	if not _exists.has(path):
		_exists[path] = ResourceLoader.exists(path)
	return _exists[path]


static func _matches(when: Dictionary, p: Dictionary) -> bool:
	for key in when:
		if not p.has(key) or p[key] != when[key]:
			return false
	return true


func _layer_end(layer: FxLayer) -> float:
	match layer.kind:
		FxLayer.Kind.PARTICLES:
			# Emission spreads over one lifetime when explosiveness < 1, then the last particle lives one more.
			return layer.delay + layer.lifetime * (2.0 - layer.explosiveness)
		FxLayer.Kind.BEAM:
			if layer.travel_speed > 0.0 or params.has("speed"):
				return layer.delay + _travel_time(layer) + layer.lifetime
	return layer.delay + layer.lifetime


func _texture_path(layer: FxLayer, element: int) -> String:
	if element > 0 and element < layer.element_textures.size() and not layer.element_textures[element].is_empty():
		return layer.element_textures[element]
	return layer.texture


func _color(layer: FxLayer, element: int) -> Color:
	var c := layer.color
	if layer.tint_element and element > 0:
		var e := UiTokens.element_color(element)
		c = Color(c.r * e.r, c.g * e.g, c.b * e.b, c.a)
	if layer.flash:
		c.a *= _dim
	return c


# --- building -------------------------------------------------------------------------------

func _make(layer: FxLayer, element: int, k: float) -> Node3D:
	if layer.kind == FxLayer.Kind.TELEGRAPH:
		return _make_telegraph(layer)
	var tex_path := _texture_path(layer, element)
	if layer.kind != FxLayer.Kind.LIGHT and (tex_path.is_empty() or not file_exists(tex_path)):
		return null
	if not layer.mesh.is_empty() and not file_exists(layer.mesh):
		return null
	match layer.kind:
		FxLayer.Kind.PARTICLES:
			return _make_particles(layer, element, k, tex_path)
		FxLayer.Kind.MESH:
			return _make_mesh(layer, element, tex_path)
		FxLayer.Kind.GROUND:
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE
			var pivot := Node3D.new()
			if layer.align == FxLayer.Align.DIRECTION:
				var d := _direction()
				_face(pivot, Vector3(d.x, 0.0, d.z))
			var mi := _mesh_node(plane, Transform3D.IDENTITY, _material(layer, element, tex_path, false))
			if layer.spin:
				mi.rotate_y(randf() * TAU)
			pivot.add_child(mi)
			pivot.set_meta(&"mesh", mi)
			return pivot
		FxLayer.Kind.BEAM:
			return _make_beam(layer, element, tex_path)
		FxLayer.Kind.LIGHT:
			var light := OmniLight3D.new()
			light.light_color = _color(layer, element)
			light.omni_range = layer.light_range * k
			light.shadow_enabled = false
			light.position = layer.offset
			return light
	return null


func _make_particles(layer: FxLayer, element: int, k: float, tex_path: String) -> Node3D:
	var gp := GPUParticles3D.new()
	gp.amount = maxi(layer.amount, 1)
	gp.lifetime = maxf(layer.lifetime, 0.01)
	gp.one_shot = not layer.loop
	gp.explosiveness = layer.explosiveness
	gp.emitting = false
	gp.local_coords = false  # world space: gravity stays down whichever way the emitter faces
	gp.position = layer.offset
	if layer.align == FxLayer.Align.DIRECTION or layer.follow_direction:
		_face(gp, _direction())
	var reach := layer.emit_radius * k + layer.speed.y * k * layer.lifetime + layer.size.y * k * maxf(layer.end_scale, 1.0) * layer.stretch
	reach = maxf(reach + absf(layer.gravity) * layer.lifetime * layer.lifetime * 0.5, 0.5)
	gp.visibility_aabb = AABB(-Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	gp.process_material = _process_material(layer, element, k)
	var draw: Mesh
	if not layer.mesh.is_empty():
		var entry: Variant = _mesh_entry(layer.mesh)
		if entry == null:
			return null
		draw = entry[0]
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, layer.stretch)
		if layer.align == FxLayer.Align.FLAT:
			quad.orientation = PlaneMesh.FACE_Y
		draw = quad
	gp.draw_pass_1 = draw
	gp.material_override = _material(layer, element, tex_path, true)
	return gp


## params.direction (shots, skills) or params.normal (bullet_impact).
func _direction() -> Vector3:
	return params.get("direction", params.get("normal", Vector3.ZERO))


## Turns a piece so its -Z (the authored `direction` FORWARD) points along `d`.
static func _face(node: Node3D, d: Vector3) -> void:
	if d.length() < 0.001:
		return
	var n := d.normalized()
	node.basis = Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.99 else Vector3.FORWARD)


func _process_material(layer: FxLayer, element: int, k: float) -> ParticleProcessMaterial:
	var key := "%d/%d/%.3f/%.2f" % [layer.get_instance_id(), element, k, _dim]
	if _process_mats.has(key):
		return _process_mats[key]
	var pm := ParticleProcessMaterial.new()
	pm.direction = layer.direction
	pm.spread = layer.spread_deg
	pm.initial_velocity_min = layer.speed.x * k
	pm.initial_velocity_max = layer.speed.y * k
	pm.gravity = Vector3(0.0, -layer.gravity, 0.0)
	pm.scale_min = layer.size.x * k
	pm.scale_max = layer.size.y * k
	if not is_equal_approx(layer.end_scale, 1.0):
		var curve := Curve.new()
		curve.max_value = maxf(1.0, layer.end_scale)
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, layer.end_scale))
		var ct := CurveTexture.new()
		ct.curve = curve
		pm.scale_curve = ct
	if layer.spin:
		pm.angle_min = -180.0
		pm.angle_max = 180.0
	if layer.emit_radius > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = layer.emit_radius * k
	if layer.align == FxLayer.Align.VELOCITY:
		pm.particle_flag_align_y = true
	if layer.sheet.x * layer.sheet.y > 1:
		pm.anim_speed_min = 1.0
		pm.anim_speed_max = 1.0
	pm.color = _color(layer, element)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0 if layer.fade_in > 0.0 else 1.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	if layer.fade_in > 0.0:
		ramp.add_point(layer.fade_in, Color.WHITE)
	ramp.add_point(clampf(1.0 - layer.fade_out, layer.fade_in + 0.001, 0.999), Color.WHITE)
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	_process_mats[key] = pm
	return pm


func _make_mesh(layer: FxLayer, element: int, tex_path: String) -> Node3D:
	var entry: Variant = _mesh_entry(layer.mesh)
	if entry == null:
		return null
	var pivot := Node3D.new()
	pivot.position = layer.offset
	if layer.align == FxLayer.Align.DIRECTION:
		_face(pivot, _direction())
	var fix := Transform3D(Basis.from_euler(layer.mesh_rotation_deg * (PI / 180.0)), Vector3.ZERO)
	var mi := _mesh_node(entry[0], fix * (entry[1] as Transform3D), _material(layer, element, tex_path, false))
	mi.position = Vector3.ZERO
	pivot.add_child(mi)
	pivot.set_meta(&"mesh", mi)
	if layer.spin:
		pivot.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	return pivot


func _make_beam(layer: FxLayer, element: int, tex_path: String) -> Node3D:
	var to: Vector3 = params.get("to", global_position)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	plane.center_offset = Vector3(0.0, 0.0, -0.5)  # starts at the origin, runs along -Z
	var mi := _mesh_node(plane, Transform3D.IDENTITY, _material(layer, element, tex_path, false))
	var dir := to - global_position
	_face(mi, dir)
	mi.set_meta(&"length", dir.length())
	return mi


## Flat quad around the origin, turned to params.direction (yaw only); the shader cuts the shape.
func _make_telegraph(layer: FxLayer) -> Node3D:
	var shape: int = TELEGRAPH_SHAPES.get(StringName(params.get("shape", &"circle")), 0)
	var radius := float(params.get("radius", 1.0))
	var extent := maxf(radius, float(params.get("length", 0.0))) + 0.2
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * extent * 2.0
	if _telegraph_mat == null:
		_telegraph_mat = ShaderMaterial.new()
		_telegraph_mat.shader = SHADER_TELEGRAPH
	var mi := _mesh_node(plane, Transform3D.IDENTITY, _telegraph_mat)
	mi.position = layer.offset + Vector3(0.0, 0.04, 0.0)
	var d := _direction()
	_face(mi, Vector3(d.x, 0.0, d.z))
	mi.set_instance_shader_parameter(&"fx_shape", shape)
	mi.set_instance_shader_parameter(&"fx_radius", radius)
	mi.set_instance_shader_parameter(&"fx_inner", float(params.get("inner", 0.0)))
	mi.set_instance_shader_parameter(&"fx_half_angle", deg_to_rad(float(params.get("angle_deg", 60.0))) * 0.5)
	mi.set_instance_shader_parameter(&"fx_length", float(params.get("length", radius)))
	mi.set_instance_shader_parameter(&"fx_width", float(params.get("width", 1.0)))
	return mi


func _mesh_node(mesh: Mesh, xform: Transform3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xform
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## [Mesh, transform of that mesh inside the imported scene], or null.
static func _mesh_entry(path: String) -> Variant:
	if _meshes.has(path):
		return _meshes[path]
	var entry: Variant = null
	var res := load(path)
	if res is Mesh:
		entry = [res, Transform3D.IDENTITY]
	elif res is PackedScene:
		var root := (res as PackedScene).instantiate()
		var found := root.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var mi := found[0] as MeshInstance3D
			var xform := mi.transform
			var n := mi.get_parent()
			while n != null and n != root:
				if n is Node3D:
					xform = (n as Node3D).transform * xform
				n = n.get_parent()
			entry = [mi.mesh, xform]
		root.free()
	_meshes[path] = entry
	return entry


func _material(layer: FxLayer, element: int, tex_path: String, particle: bool) -> ShaderMaterial:
	var key := "%d/%s/%d" % [layer.get_instance_id(), tex_path, int(particle)]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_MIX if layer.blend == FxLayer.Blend.MIX else SHADER_ADD
	mat.set_shader_parameter(&"tex", load(tex_path))
	mat.set_shader_parameter(&"particle", particle)
	var align := 2
	if particle and layer.mesh.is_empty():
		align = {FxLayer.Align.VELOCITY: 1, FxLayer.Align.FLAT: 2}.get(layer.align, 0)
	mat.set_shader_parameter(&"align", align)
	mat.set_shader_parameter(&"channel", int(layer.channel))
	mat.set_shader_parameter(&"frames", Vector2(layer.sheet))
	mat.set_shader_parameter(&"dissolve", layer.dissolve)
	mat.set_shader_parameter(&"uv_scroll", layer.uv_scroll)
	mat.set_shader_parameter(&"rotate_uv", layer.rotate_uv)
	_materials[key] = mat
	return mat


# --- stepping --------------------------------------------------------------------------------

func _update(part: Dictionary) -> void:
	var layer: FxLayer = part["layer"]
	var node: Node3D = part["node"]
	var local := age - layer.delay
	if local < 0.0:
		return
	if not part["started"]:
		part["started"] = true
		node.visible = true
		if node is GPUParticles3D:
			(node as GPUParticles3D).restart()
	if node is GPUParticles3D:
		if layer.loop and age >= lifetime - layer.lifetime:
			(node as GPUParticles3D).emitting = false
		return
	var t := clampf(local / maxf(layer.lifetime, 0.001), 0.0, 1.0)
	var alpha := _fade(layer, t)
	if layer.loop:
		alpha = (smoothstep(0.0, 1.0, t) if layer.fade_in > 0.0 else 1.0) \
			* clampf((lifetime - age) / LOOP_FADE_OUT, 0.0, 1.0)
	var element := int(params.get("element", Enums.Element.NONE))
	var k: float = part["k"]
	var s: float = lerpf(layer.grow.x, layer.grow.y, ease(t, 0.4)) * k
	match layer.kind:
		FxLayer.Kind.TELEGRAPH:
			# Danger red / warning orange from params.kind; the fill tracks the whole wind-up.
			var c := UiTokens.WARN if String(params.get("kind", "danger")) == "warn" else UiTokens.DANGER
			var windup := maxf(lifetime - layer.lifetime, 0.01)
			c.a = clampf((lifetime - age) / maxf(layer.lifetime, 0.01), 0.0, 1.0) * clampf(age / 0.1, 0.0, 1.0)
			node.set_instance_shader_parameter(&"fx_color", c)
			node.set_instance_shader_parameter(&"fx_age", clampf(age / windup, 0.0, 1.0))
		FxLayer.Kind.LIGHT:
			(node as OmniLight3D).light_energy = layer.light_energy * alpha * _dim
		FxLayer.Kind.MESH:
			node.scale = Vector3.ONE * maxf(s, 0.001)
			_set_instance(node.get_meta(&"mesh"), layer, element, alpha, t, 1.0)
		FxLayer.Kind.GROUND:
			var mi: MeshInstance3D = node.get_meta(&"mesh")
			mi.position = layer.offset + Vector3(0.0, 0.03, 0.0)
			mi.scale = Vector3(maxf(s, 0.001), 1.0, maxf(s, 0.001))
			_set_instance(mi, layer, element, alpha, t, 1.0)
		FxLayer.Kind.BEAM:
			_update_beam(node as MeshInstance3D, layer, element, alpha, local, k)


func _update_beam(mi: MeshInstance3D, layer: FxLayer, element: int, alpha: float, local: float, k: float) -> void:
	var full: float = mi.get_meta(&"length", 0.0)
	var width := layer.grow.x * k
	if layer.travel_speed <= 0.0 and not params.has("speed"):
		mi.position = layer.offset
		mi.scale = Vector3(width, 1.0, maxf(full, 0.001))
		_set_instance(mi, layer, element, alpha, clampf(local / maxf(layer.lifetime, 0.001), 0.0, 1.0), maxf(full / maxf(width * 4.0, 0.01), 1.0))
		return
	# Travelling streak: its head runs from the origin to `to`, then the tail catches up.
	var speed := _speed(layer)
	var head := minf(local * speed, full)
	var tail := clampf(local * speed - layer.grow.y, 0.0, full)
	var fwd := -mi.basis.z.normalized()
	mi.position = layer.offset + fwd * tail
	mi.scale = Vector3(width, 1.0, maxf(head - tail, 0.001))
	var after := maxf(local - _travel_time(layer), 0.0)
	var a := 1.0 - clampf(after / maxf(layer.lifetime, 0.001), 0.0, 1.0)
	_set_instance(mi, layer, element, a, 0.0, 1.0)


func _speed(layer: FxLayer) -> float:
	return float(params.get("speed", layer.travel_speed if layer.travel_speed > 0.0 else TRACER_SPEED))


func _travel_time(layer: FxLayer) -> float:
	var to: Vector3 = params.get("to", Vector3.ZERO)
	var dist := (to - global_position).length() if params.has("to") else 0.0
	return (dist + layer.grow.y) / maxf(_speed(layer), 0.01)


func _set_instance(mi: GeometryInstance3D, layer: FxLayer, element: int, alpha: float, t: float, uv_length: float) -> void:
	var c := _color(layer, element)
	c.a *= alpha
	mi.set_instance_shader_parameter(&"fx_color", c)
	mi.set_instance_shader_parameter(&"fx_age", t)
	mi.set_instance_shader_parameter(&"fx_uv_length", uv_length)


static func _fade(layer: FxLayer, t: float) -> float:
	var a := 1.0
	if layer.fade_in > 0.0:
		a *= smoothstep(0.0, layer.fade_in, t)
	if layer.fade_out > 0.0:
		a *= 1.0 - smoothstep(1.0 - layer.fade_out, 1.0, t)
	return a
