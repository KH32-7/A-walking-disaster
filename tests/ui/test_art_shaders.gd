extends RefCounted
## D-03: shared shaders and materials load and expose the parameters other lanes rely on.

const EXPECT := {
	"res://art/shaders/toon.gdshader": ["albedo", "shade_color", "bands", "rim_amount", "alpha_cut"],
	"res://art/shaders/outline.gdshader": ["outline_color", "outline_px"],
	"res://art/shaders/element_glow.gdshader": ["glow_color", "energy", "pulse_amount"],
	"res://art/shaders/roof_fade.gdshader": ["player_position", "fade_radius", "fade_amount"],
}
const MATERIALS := ["toon_default", "toon_concrete", "toon_foliage", "toon_wood", "toon_water",
	"outline", "roof_fade_concrete", "glow_green", "glow_stone", "glow_water", "glow_light"]


func run() -> bool:
	var ok := true
	for path: String in EXPECT:
		var sh := load(path) as Shader
		if sh == null:
			printerr("missing shader %s" % path)
			ok = false
			continue
		var names := []
		for u in sh.get_shader_uniform_list():
			names.append(String(u.name))
		for want: String in EXPECT[path]:
			if not want in names:
				printerr("%s lacks uniform %s" % [path, want])
				ok = false
	for m: String in MATERIALS:
		var mat := load("res://art/materials/%s.tres" % m) as ShaderMaterial
		if mat == null or mat.shader == null:
			printerr("material %s broken" % m)
			ok = false
	var d := load("res://art/materials/toon_default.tres") as ShaderMaterial
	if d != null and d.next_pass == null:
		printerr("toon materials should carry the outline as next_pass")
		ok = false
	return ok
