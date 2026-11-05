extends Node3D
## Sandbox-only debug ring (B-05): shows every EventBus.noise_emitted radius on the floor
## for a moment. The real in-game ring (white/orange/red) is D-05; keep this out of shipped scenes.

const SHOW_SEC := 0.8
const RING_WIDTH := 0.15
const RING_HEIGHT := 0.05
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.8)


func _ready() -> void:
	EventBus.noise_emitted.connect(_on_noise_emitted)


func _on_noise_emitted(pos: Vector3, radius: float, _source: Node) -> void:
	var mesh := TorusMesh.new()
	mesh.outer_radius = radius
	mesh.inner_radius = maxf(radius - RING_WIDTH, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = RING_COLOR
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = mat
	ring.scale = Vector3(1.0, RING_HEIGHT / RING_WIDTH, 1.0)
	add_child(ring)
	ring.global_position = Vector3(pos.x, 0.05, pos.z)
	var tween := ring.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, SHOW_SEC)
	tween.tween_callback(ring.queue_free)
