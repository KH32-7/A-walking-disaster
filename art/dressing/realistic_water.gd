class_name RealisticWater
extends RefCounted
## The water look shared by the base lakes (ForestDressing) and the field's flooded water
## (RegionDressing): art/shaders/realistic_water.gdshader with its noise textures made in code.
## One place for the colours and depth feel, so the base pond and a flooded street look the same.

const SHADER := preload("res://art/shaders/realistic_water.gdshader")
const COLOR_SHALLOW := Color(0.45, 0.62, 0.55)
const COLOR_DEEP := Color(0.04, 0.12, 0.26)
const BEERS_LAW := 0.9
const DEPTH_OFFSET := -0.5
const REFRACTION := 0.03
## Shallow overlays sit a few cm over the ground: the water is that thin everywhere, so full foam
## would cover them. They get none...
const SHALLOW_FOAM := 0.0
## ...and more of the water colour over the ground they show through, so a flooded street reads as
## water rather than wet gravel.
const SHALLOW_COLOR := Color(0.32, 0.52, 0.52)
## Depth-buffer water is drawn at most this deep (m): the field's deep channels have nothing under
## them, and the middle of a base pond is about this deep (ForestDressing fake depth).
const FIELD_MAX_DEPTH := 2.7

static var _textures := {}  # shared noise textures, made once


## A water material. fake_depth > 0: depth from UV2.x (0 at the shore, 1 in the middle) x fake_depth
## metres, for water on flat ground with no real bottom (base lakes). 0: the real depth below the
## surface from the depth buffer (field channels and ponds).
static func material(fake_depth := 0.0, shallow := false) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	sm.set_shader_parameter(&"uv_sampler", _texture(&"uv", 11, 0.006, false))
	sm.set_shader_parameter(&"normalmap_a_sampler", _texture(&"normal_a", 23, 0.02, true))
	sm.set_shader_parameter(&"normalmap_b_sampler", _texture(&"normal_b", 37, 0.045, true))
	sm.set_shader_parameter(&"foam_sampler", _texture(&"foam", 51, 0.03, false, true))
	sm.set_shader_parameter(&"fake_depth", fake_depth)
	sm.set_shader_parameter(&"beers_law", BEERS_LAW)
	sm.set_shader_parameter(&"depth_offset", DEPTH_OFFSET)
	sm.set_shader_parameter(&"refraction", REFRACTION)
	sm.set_shader_parameter(&"color_shallow", COLOR_SHALLOW)
	sm.set_shader_parameter(&"color_deep", COLOR_DEEP)
	if fake_depth <= 0.0:
		sm.set_shader_parameter(&"max_depth", FIELD_MAX_DEPTH)
	if shallow:
		sm.set_shader_parameter(&"foam_level", SHALLOW_FOAM)
		sm.set_shader_parameter(&"color_shallow", SHALLOW_COLOR)
	return sm


## Seamless noise for the water shader (made here, so no texture files are needed).
static func _texture(key: StringName, seed_value: int, frequency: float, normal_map: bool,
		cellular := false) -> NoiseTexture2D:
	if _textures.has(key):
		return _textures[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	if cellular:
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.as_normal_map = normal_map
	tex.bump_strength = 6.0
	tex.noise = noise
	_textures[key] = tex
	return tex
