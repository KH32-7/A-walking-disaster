class_name FxEffect
extends Node3D
## Base of every D-18 effect. Owner: Lane D. Created only by `Fx.spawn` (gameplay never instances these).
## An effect is a handful of flat shape sprites (vfx/fx_shapes.gd) animated by script, so it looks the
## same every run, can be stepped frame by frame for screenshots (`Fx.manual_step`) and needs no GPU
## particles. Subclasses override `_build()` (make parts from `params`) and optionally `_tick(k, delta)`.
## Readability rules: element = shape + colour (UiTokens), never colour alone; bright flashes are scaled
## by `flash_k` (Settings.reduce_flash -> dimmer, no white pops).

enum Blend { GROUND, OUTLINE, MIX, ADD }

const SHADER_MIX := preload("res://vfx/shaders/fx_mix.gdshader")
const SHADER_ADD := preload("res://vfx/shaders/fx_add.gdshader")
const OUTLINE_COLOR := Color(0.04, 0.05, 0.07, 0.8)
const OUTLINE_SCALE := 1.3
## Camera-facing sprites are drawn this much bigger than their nominal size so a 0.1 m spark is still
## a few pixels at the far field zoom (24 m). Ground shapes keep their size: it is a real radius.
const BILLBOARD_SCALE := 1.5
## Brightness multiplier and white-pop alpha when Settings.reduce_flash is on.
const REDUCED_FLASH_K := 0.35

static var _materials: Dictionary = {}


class Part:
	extends RefCounted
	var node: MeshInstance3D
	var outline: MeshInstance3D
	var vel := Vector3.ZERO
	var gravity := 0.0
	var drag := 0.0
	var spin := 0.0
	var spin_vel := 0.0
	var squash := Vector2.ONE
	var life := 1.0
	var age := 0.0
	var delay := 0.0
	var size0 := 1.0
	var size1 := 1.0
	var ease_size := 0.4  # ease() curve for size0 -> size1 (<1: fast start)
	var color := Color.WHITE
	var energy := 1.0
	var fade_in := 0.0  # part of life spent fading in
	var fade_from := 0.5  # part of life after which it fades out
	var align := false  # spin follows the on-screen velocity (sparks, streaks)
	var stretch := 0.0  # extra length per m/s when aligned
	var auto := true  # false: the effect animates it itself
	var scale_k := 1.0  # BILLBOARD_SCALE for camera-facing sprites

	func apply(cam_basis: Basis) -> void:
		var k := clampf(age / life, 0.0, 1.0)
		var s := lerpf(size0, size1, ease(k, ease_size))
		node.scale = Vector3.ONE * maxf(s * scale_k, 0.0001)
		var a := 1.0
		if fade_in > 0.0 and k < fade_in:
			a = k / fade_in
		if k > fade_from:
			a *= 1.0 - (k - fade_from) / maxf(1.0 - fade_from, 0.0001)
		var sq := squash
		if align and vel.length_squared() > 0.0001:
			var v := cam_basis.inverse() * vel
			spin = atan2(-v.x, v.y)
			sq.y *= 1.0 + stretch * Vector2(v.x, v.y).length()
		set_look(Color(color, color.a * a), spin, sq)

	func set_look(c: Color, angle: float, sq: Vector2 = Vector2.ONE) -> void:
		node.set_instance_shader_parameter(&"tint", c)
		node.set_instance_shader_parameter(&"energy", energy)
		node.set_instance_shader_parameter(&"spin", angle)
		node.set_instance_shader_parameter(&"squash", sq)
		if outline:
			outline.set_instance_shader_parameter(&"tint", Color(OUTLINE_COLOR, OUTLINE_COLOR.a * c.a))
			outline.set_instance_shader_parameter(&"spin", angle)
			outline.set_instance_shader_parameter(&"squash", sq)


var params: Dictionary = {}
var age := 0.0
var lifetime := 0.5
var flash_k := 1.0
var reduced_flash := false
var rng := RandomNumberGenerator.new()
var _parts: Array[Part] = []


## Called by Fx right after the node enters the tree at its position.
func setup(p: Dictionary) -> void:
	params = p
	reduced_flash = Fx.reduced_flash()
	flash_k = REDUCED_FLASH_K if reduced_flash else 1.0
	rng.seed = int(p.get("seed", Fx.next_seed()))
	_build()
	_apply_parts()


func _build() -> void:
	pass


## k = age / lifetime (0..1). For hand-animated parts and lights.
func _tick(_k: float, _delta: float) -> void:
	pass


func _process(delta: float) -> void:
	if not Fx.manual_step:
		advance(delta)


func advance(delta: float) -> void:
	age += delta
	for part in _parts:
		if not part.auto:
			continue
		if part.delay > 0.0:
			part.delay -= delta
			part.node.visible = part.delay <= 0.0
			if part.outline:
				part.outline.visible = part.node.visible
			continue
		part.age += delta
		part.node.position += part.vel * delta
		part.vel.y -= part.gravity * delta
		if part.drag > 0.0:
			part.vel *= exp(-part.drag * delta)
		part.spin += part.spin_vel * delta
	_tick(clampf(age / lifetime, 0.0, 1.0), delta)
	_apply_parts()
	if age >= lifetime:
		queue_free()


func _apply_parts() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cb := global_basis.inverse() * cam.global_basis if cam else Basis()
	for part in _parts:
		if part.auto and part.delay <= 0.0:
			if part.age >= part.life:
				part.node.visible = false
				if part.outline:
					part.outline.visible = false
				continue
			part.node.visible = true
			if part.outline:
				part.outline.visible = true
			part.apply(cb)


# --- builders ------------------------------------------------------------------------------------

## A shape sprite (UiTokens.Shape or FxShapes.Extra). billboard: faces the camera. outline: dark copy
## behind it so it reads on any ground.
func sprite(shape: int, color: Color, size: float, blend: Blend = Blend.MIX, billboard: bool = true,
		outline: bool = false) -> Part:
	var part := Part.new()
	part.node = _mesh_node(FxShapes.mesh(shape), blend, billboard)
	part.color = color
	part.size0 = size
	part.size1 = size
	part.life = lifetime
	part.scale_k = BILLBOARD_SCALE if billboard else 1.0
	if outline:
		part.outline = _mesh_node(FxShapes.mesh(shape), Blend.OUTLINE, billboard)
		part.outline.scale = Vector3.ONE * OUTLINE_SCALE
		part.outline.position = Vector3.ZERO
		part.node.add_child(part.outline)
	add_child(part.node)
	_parts.append(part)
	return part


## Flat shape lying on the ground (XZ plane) at local `pos`.
func ground(shape: int, color: Color, size: float, pos: Vector3 = Vector3.ZERO, blend: Blend = Blend.GROUND) -> Part:
	var part := sprite(shape, color, size, blend, false)
	part.node.position = pos + Vector3.UP * 0.03
	part.node.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	return part


## Camera-facing ribbon through `points` (local), for lightning arcs and tracer lines.
func ribbon(points: PackedVector3Array, width: float, color: Color, blend: Blend = Blend.ADD) -> Part:
	var part := Part.new()
	part.node = _mesh_node(ribbon_mesh(points, width), blend, false)
	part.color = color
	part.life = lifetime
	add_child(part.node)
	_parts.append(part)
	return part


## The mesh behind ribbon(): quads through `points` (local), widened across the camera view.
func ribbon_mesh(points: PackedVector3Array, width: float) -> ArrayMesh:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var view_dir := (global_basis.inverse() * cam.global_basis.z) if cam else Vector3.UP
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in points.size():
		var along := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := along.cross(view_dir).normalized() * width * 0.5
		if side == Vector3.ZERO:
			side = Vector3.RIGHT * width * 0.5
		verts.append(points[i] - side)
		verts.append(points[i] + side)
		if i < points.size() - 1:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	if verts.size() >= 4:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Jagged line from a to b (local) for lightning.
func zigzag(a: Vector3, b: Vector3, segments: int, jitter: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a])
	var dir := b - a
	var side := dir.cross(Vector3.UP).normalized()
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	for i in range(1, segments):
		var t := float(i) / segments
		pts.append(a + dir * t + side * rng.randf_range(-jitter, jitter) + Vector3.UP * rng.randf_range(-jitter, jitter) * 0.5)
	pts.append(b)
	return pts


## Random unit vector in a cone of `spread` radians around `dir`.
func cone_dir(dir: Vector3, spread: float) -> Vector3:
	var d := dir.normalized()
	var ortho := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var r := ortho.rotated(d, rng.randf() * TAU)
	return d.rotated(r, rng.randf() * spread).normalized()


func p_float(key: String, default: float) -> float:
	return float(params.get(key, default))


func p_element() -> int:
	return int(params.get("element", Enums.Element.NONE))


## Element colour, or `none_color` for Element.NONE.
func element_color(none_color: Color = Color.WHITE) -> Color:
	var e := p_element()
	return none_color if e == Enums.Element.NONE else UiTokens.element_color(e)


func _mesh_node(m: Mesh, blend: Blend, billboard: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = material(blend, billboard)
	return mi


static func material(blend: Blend, billboard: bool) -> ShaderMaterial:
	var key := int(blend) * 2 + int(billboard)
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_ADD if blend == Blend.ADD else SHADER_MIX
	mat.set_shader_parameter(&"billboard", billboard)
	mat.render_priority = [-2, 0, 1, 2][blend]
	_materials[key] = mat
	return mat
