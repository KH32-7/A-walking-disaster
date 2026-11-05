class_name HitFlash
extends RefCounted
## Brief "I got hit" flash on a character (D-18). Owner: Lane D.
## Puts one shared overlay material (vfx/shaders/hit_flash.gdshader) on every mesh under `target`
## for `sec` seconds and fades it out. Only the overlay slot is used, and only when it is empty, so the
## character's own materials are never replaced. Settings.reduce_flash: a weaker tint instead of a
## white pop. Stepped by Fx (`Fx.advance` in previews), not by tweens, so screenshots repeat.

const SHADER := preload("res://vfx/shaders/hit_flash.gdshader")
const SEC := 0.14
const PEAK := 0.85
const REDUCED_PEAK := 0.3

static var _material: ShaderMaterial
## {target: Node, meshes: Array[GeometryInstance3D], t: float, sec: float, peak: float}
static var _active: Array[Dictionary] = []


static func flash(target: Node, color: Color = Color.WHITE, sec: float = SEC) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var meshes := meshes_of(target)
	if meshes.is_empty():
		return
	for e in _active:
		if e.target == target:
			_active.erase(e)
			break
	for gi in meshes:
		if gi.material_overlay == null:
			gi.material_overlay = _material
		gi.set_instance_shader_parameter(&"flash_color", color)
	var peak := REDUCED_PEAK if Fx.reduced_flash() else PEAK
	_active.append({"target": target, "meshes": meshes, "t": 0.0, "sec": sec, "peak": peak})
	_apply(_active.back())


static func step(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var e: Dictionary = _active[i]
		e.t += delta
		if not is_instance_valid(e.target) or e.t >= e.sec:
			_end(e)
			_active.remove_at(i)
		else:
			_apply(e)


static func clear() -> void:
	for e in _active:
		_end(e)
	_active.clear()


static func active_count() -> int:
	return _active.size()


static func _apply(e: Dictionary) -> void:
	var k: float = 1.0 - e.t / e.sec
	for gi in e.meshes:
		if is_instance_valid(gi):
			gi.set_instance_shader_parameter(&"flash", e.peak * k * k)


static func _end(e: Dictionary) -> void:
	for gi in e.meshes:
		if is_instance_valid(gi) and gi.material_overlay == _material:
			gi.set_instance_shader_parameter(&"flash", 0.0)
			gi.material_overlay = null


## Meshes the flash goes on: every GeometryInstance3D under target except text, sprites and effects.
static func meshes_of(target: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [target]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is FxEffect:
			continue
		if n is GeometryInstance3D and not n is Label3D and not n is SpriteBase3D and (n as Node3D).visible:
			out.append(n)
		stack.append_array(n.get_children())
	return out


static func is_flashing(gi: GeometryInstance3D) -> bool:
	return _material != null and gi.material_overlay == _material
