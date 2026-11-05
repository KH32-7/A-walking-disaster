class_name ExtractBeacon
extends Node3D
## What an active extraction point looks like in the world (사용자 요청 2026-11-06: it read as plain
## grass). Built from code so it needs no assets: a green flare-smoke beam seen from far away, a
## glowing ring on the ground the size of the standing zone and a green light.
## ExtractPoint.set_active() adds one while the point is active this sortie.
## Green = the extract colour of the HUD and the maps (UiTokens.GOOD).

const SHADER := preload("res://field/markers/extract_beacon.gdshader")
const BEAM_HEIGHT := 16.0
const BEAM_RADIUS := 0.55
const RING_WIDTH := 0.22
const LIGHT_ENERGY := 2.0

var radius := 3.0


func _init(zone_radius := 3.0) -> void:
	radius = zone_radius
	name = "ExtractBeacon"


func _ready() -> void:
	var green := UiTokens.GOOD
	# Beam: open cylinder, additive, fading upward (the shader), pulsing gently.
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = BEAM_RADIUS * 1.6
	beam_mesh.bottom_radius = BEAM_RADIUS
	beam_mesh.height = BEAM_HEIGHT
	beam_mesh.cap_top = false
	beam_mesh.cap_bottom = false
	beam_mesh.radial_segments = 24
	var beam := _mesh(beam_mesh, _shader_mat(green, 0.55, true))
	beam.name = "Beam"
	beam.position.y = BEAM_HEIGHT * 0.5
	# Ground: a faint disc and a bright ring at the zone's edge.
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = radius
	disc_mesh.bottom_radius = radius
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 48
	var disc := _mesh(disc_mesh, _flat_mat(Color(green, 0.16)))
	disc.name = "Disc"
	disc.position.y = 0.03
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius - RING_WIDTH
	ring_mesh.outer_radius = radius
	ring_mesh.rings = 48
	var ring := _mesh(ring_mesh, _flat_mat(Color(green, 0.9)))
	ring.name = "Ring"
	ring.scale.y = 0.2
	ring.position.y = 0.06
	var light := OmniLight3D.new()
	light.name = "Light"
	light.light_color = green
	light.light_energy = LIGHT_ENERGY
	light.omni_range = radius * 2.2
	light.shadow_enabled = false
	light.position.y = 1.2
	add_child(light)


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _shader_mat(col: Color, strength: float, fade_up: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter(&"color", col)
	mat.set_shader_parameter(&"strength", strength)
	mat.set_shader_parameter(&"fade_up", fade_up)
	return mat


func _flat_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	return mat
