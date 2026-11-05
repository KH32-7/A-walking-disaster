extends Node3D
## Short soft grass carpet for the B-26 kit ground (user feedback 2026-11-06). Owner: Lane B.
## Built in _ready from the ground splat map's alpha channel (grass density, baked by
## field/build/layout_builder.gd): one blade clump per jittered grid cell where the dice say so,
## in chunked MultiMeshInstance3Ds so off-screen chunks cull. The clump mesh is generated here,
## so nothing from the asset packs is involved.

const SHADER := preload("res://field/buildings/grass_blades.gdshader")
const BLADES := 6
const CHUNK := 24.0

## Splat map (RGBA); alpha = grass density 0..1.
@export var splat: Texture2D
@export var origin := Vector2(-112.5, -112.5)
@export var size := Vector2(225.0, 225.0)
## Grid step in metres and the chance per cell at full density.
@export var step := 0.55
@export var density := 0.9
@export var height := Vector2(0.22, 0.42)
@export var ground_y := 0.01
@export var seed_value := 20261106


func _ready() -> void:
	if splat == null:
		return
	var img := splat.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mesh := _clump_mesh(rng)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var chunks := {}
	var w := img.get_width()
	var h := img.get_height()
	var y := origin.y
	while y < origin.y + size.y:
		var x := origin.x
		while x < origin.x + size.x:
			var p := Vector2(x + rng.randf() * step, y + rng.randf() * step)
			x += step
			var u := (p - origin) / size
			var a := img.get_pixel(clampi(int(u.x * w), 0, w - 1), clampi(int(u.y * h), 0, h - 1)).a
			if rng.randf() > a * density:
				continue
			var key := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
			if not chunks.has(key):
				chunks[key] = []
			var s := rng.randf_range(height.x, height.y)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * 2.2, s, s * 2.2))
			chunks[key].append(Transform3D(basis, Vector3(p.x, ground_y, p.y)))
		y += step
	for key in chunks:
		var xfs: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass_%d_%d" % [key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## A clump of BLADES tapered blades leaning out from the centre, 1 unit tall (scaled per instance).
static func _clump_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in BLADES:
		var yaw := TAU * i / BLADES + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(yaw), 0.0, sin(yaw))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.06
		var root := dir * rng.randf_range(0.0, 0.12)
		var tip := root + dir * rng.randf_range(0.15, 0.35) + Vector3.UP * rng.randf_range(0.75, 1.0)
		for v in [[root - side, 0.0], [root + side, 0.0], [tip, 1.0]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.5, v[1]))
			st.add_vertex(v[0])
	return st.commit()
