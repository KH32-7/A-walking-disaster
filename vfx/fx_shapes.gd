class_name FxShapes
extends RefCounted
## Flat shape meshes for VFX (D-18). Owner: Lane D. Same silhouettes as the UI badges
## (ui/widgets/shape_badge.gd, UiTokens.Shape) so an element reads the same in menus and the world:
## green petal, stone square, water drop, light bolt. Extra VFX shapes: STAR (flash), RING, PLUS (heal),
## SHARD (thin diamond), CRESCENT (blade arc).
## Meshes lie in the XY plane, radius 1, centred; billboard or rotate them in the effect.

enum Extra { RING = 100, PLUS, SHARD, CRESCENT, SPIKE }

static var _cache: Dictionary = {}


static func element_shape(element: int) -> int:
	return UiTokens.element_shape(element)


static func element_color(element: int) -> Color:
	return UiTokens.element_color(element)


## Cached ArrayMesh for a UiTokens.Shape or an Extra value.
static func mesh(shape: int) -> ArrayMesh:
	if _cache.has(shape):
		return _cache[shape]
	var m: ArrayMesh
	if shape == Extra.RING:
		m = _ring_mesh(0.78, 1.0, 40)
	else:
		m = _poly_mesh(polygon(shape, 1.0))
	_cache[shape] = m
	return m


static func polygon(shape: int, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		UiTokens.Shape.CIRCLE:
			for i in 24:
				var a := TAU * i / 24.0
				pts.append(Vector2(cos(a), sin(a)) * r * 0.9)
		UiTokens.Shape.SQUARE:
			var h := r * 0.78
			pts = PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
		UiTokens.Shape.TRIANGLE:
			pts = PackedVector2Array([Vector2(0, r * 0.92), Vector2(r * 0.92, -r * 0.8), Vector2(-r * 0.92, -r * 0.8)])
		UiTokens.Shape.DIAMOND:
			pts = PackedVector2Array([Vector2(0, r), Vector2(r, 0), Vector2(0, -r), Vector2(-r, 0)])
		UiTokens.Shape.STAR:
			for i in 10:
				var a := PI / 2.0 + i * PI / 5.0
				var rr := r if i % 2 == 0 else r * 0.42
				pts.append(Vector2(cos(a), sin(a)) * rr)
		UiTokens.Shape.PETAL:
			# One leaf-like petal (pointed both ends), narrower than the UI 4-lobe badge so a
			# swirl of them reads as petals at small size.
			for i in 20:
				var t := i / 20.0 * TAU
				pts.append(Vector2(sin(t) * r * 0.42 * (1.0 - 0.25 * cos(t)), cos(t) * r))
		UiTokens.Shape.DROP:
			# Tip up, round belly below (counter-clockwise from the tip).
			pts.append(Vector2(0, r))
			for i in 15:
				var a := lerpf(PI * 0.5 + 0.7, PI * 2.5 - 0.7, i / 14.0)
				pts.append(Vector2(0, -r * 0.3) + Vector2(cos(a), sin(a)) * r * 0.62)
		UiTokens.Shape.BOLT:
			# UI bolt flipped to Y-up.
			for p in [Vector2(0.2, -1), Vector2(-0.6, 0.15), Vector2(-0.02, 0.15), Vector2(-0.25, 1),
					Vector2(0.6, -0.2), Vector2(0.05, -0.2)]:
				pts.append(Vector2(p.x, -p.y) * r)
		Extra.PLUS:
			var a := r * 0.3
			pts = PackedVector2Array([Vector2(-a, r), Vector2(a, r), Vector2(a, a), Vector2(r, a), Vector2(r, -a),
				Vector2(a, -a), Vector2(a, -r), Vector2(-a, -r), Vector2(-a, -a), Vector2(-r, -a), Vector2(-r, a),
				Vector2(-a, a)])
		Extra.SHARD:
			pts = PackedVector2Array([Vector2(0, r), Vector2(r * 0.28, 0), Vector2(0, -r), Vector2(-r * 0.28, 0)])
		Extra.SPIKE:
			pts = PackedVector2Array([Vector2(0, r), Vector2(r * 0.22, -r), Vector2(-r * 0.22, -r)])
		Extra.CRESCENT:
			for i in 17:
				var a := lerpf(-PI * 0.42, PI * 0.42, i / 16.0)
				pts.append(Vector2(sin(a), cos(a)) * r)
			for i in 17:
				var a := lerpf(PI * 0.42, -PI * 0.42, i / 16.0)
				var thick := 0.62 + 0.3 * (absf(a) / (PI * 0.42))
				pts.append(Vector2(sin(a), cos(a)) * r * thick)
		_:
			return polygon(UiTokens.Shape.CIRCLE, r)
	return pts


static func _poly_mesh(pts: PackedVector2Array) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(pts)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	for p in pts:
		verts.append(Vector3(p.x, p.y, 0.0))
		uvs.append(p * 0.5 + Vector2(0.5, 0.5))
	return _arrays(verts, uvs, idx)


static func _ring_mesh(inner: float, outer: float, steps: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in steps + 1:
		var a := TAU * i / steps
		var d := Vector3(cos(a), sin(a), 0.0)
		verts.append(d * inner)
		verts.append(d * outer)
		uvs.append(Vector2(float(i) / steps, 0.0))
		uvs.append(Vector2(float(i) / steps, 1.0))
		if i < steps:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	return _arrays(verts, uvs, idx)


static func _arrays(verts: PackedVector3Array, uvs: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3(0, 0, 1))
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
