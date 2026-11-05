/*
Realistic Water Shader, ported to Godot 4.7 for "A walking disaster" (base lake and pond).

Original: Realistic Water Shader for Godot 3.4
https://github.com/godot-extended-libraries/godot-realistic-water
Modified to work with Godot 3.4 with thanks to jmarceno.

Copyright (c) 2019 UnionBytes, Achim Menzel (alias AiYori)
Copyright (c) 2019 Realistic Water Shader Contributors
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
-- UnionBytes
-- YouTube: www.youtube.com/user/UnionBytes

Changes in this port:
- Godot 4 syntax (source_color, MODEL_MATRIX, NORMAL_MAP, screen/depth texture uniforms) and reverse-Z depth.
- wave_height scales the Gerstner vertex offset (0 = calm lake, the waves still bend the normals).
- max_depth caps the depth-buffer thickness (the field's deep water has nothing under it).
- fake_depth: the base lakes sit on flat ground, so the water depth can come from UV2.x
  (0 at the shore, 1 in the middle) × fake_depth metres instead of the depth buffer. 0 = depth buffer.
- Caustics come from two scrolling samples of uv_sampler instead of a 16-layer texture array.
- Textures are made in code (NoiseTexture2D) by the dressing; any noise / normal map works.
*/

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx, blend_mix;

// Wave settings:
uniform float wave_speed = 0.5;                       // Speed scale for the waves
uniform float wave_height = 0.0;                      // Vertex offset scale (0 = flat surface)
uniform vec4 wave_a = vec4(1.0, 1.0, 0.35, 3.0);     // xy = Direction, z = Steepness, w = Length
uniform vec4 wave_b = vec4(1.0, 0.6, 0.30, 1.55);
uniform vec4 wave_c = vec4(1.0, 1.3, 0.25, 0.9);

// Surface settings:
uniform vec2 sampler_scale = vec2(0.25, 0.25);
uniform vec2 sampler_direction = vec2(0.05, 0.04);

uniform sampler2D uv_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_sampler_scale = vec2(0.25, 0.25);
uniform float uv_sampler_strength = 0.04;

uniform sampler2D normalmap_a_sampler : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normalmap_b_sampler : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform sampler2D foam_sampler : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float foam_level = 0.5;

// Volume settings:
uniform float refraction = 0.075;
uniform vec4 color_deep : source_color = vec4(0.04, 0.13, 0.27, 1.0);
uniform vec4 color_shallow : source_color = vec4(0.42, 0.62, 0.58, 1.0);
uniform float beers_law = 2.0;
uniform float depth_offset = -0.75;
uniform float fake_depth = 0.0;
// Depth-buffer water deeper than this (m) is drawn as this deep: field channels have no bottom under them.
uniform float max_depth = 1000.0;

// Caustics:
uniform float caustic_strength = 1.0;
uniform float caustic_scale = 0.12;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float view_distance;
varying vec3 vertex_normal;
varying vec3 vertex_binormal;
varying vec3 vertex_tangent;
varying vec3 world_pos;
varying float shore;

vec4 wave(vec4 parameter, vec2 position, float time, inout vec3 tangent, inout vec3 binormal) {
	float wave_steepness = parameter.z;
	float wave_length = parameter.w;
	float k = 2.0 * 3.14159265359 / wave_length;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(parameter.xy);
	float f = k * (dot(d, position) - c * time);
	float a = wave_steepness / k;
	tangent += normalize(vec3(1.0 - d.x * d.x * (wave_steepness * sin(f)), d.x * (wave_steepness * cos(f)), -d.x * d.y * (wave_steepness * sin(f))));
	binormal += normalize(vec3(-d.x * d.y * (wave_steepness * sin(f)), d.y * (wave_steepness * cos(f)), 1.0 - d.y * d.y * (wave_steepness * sin(f))));
	return vec4(d.x * (a * cos(f)), a * sin(f) * 0.25, d.y * (a * cos(f)), 0.0);
}

void vertex() {
	float time = TIME * wave_speed;
	vec4 v = vec4(VERTEX, 1.0);
	vec3 wpos = (MODEL_MATRIX * v).xyz;
	vec3 tang = vec3(0.0);
	vec3 bin = vec3(0.0);
	vec4 offset = wave(wave_a, wpos.xz, time, tang, bin);
	offset += wave(wave_b, wpos.xz, time, tang, bin);
	offset += wave(wave_c, wpos.xz, time, tang, bin);
	v += offset * wave_height;
	vertex_tangent = normalize(tang);
	vertex_binormal = normalize(bin);
	vertex_normal = normalize(cross(vertex_binormal, vertex_tangent));
	TANGENT = vertex_tangent;
	BINORMAL = vertex_binormal;
	NORMAL = vertex_normal;
	world_pos = (MODEL_MATRIX * v).xyz;
	view_distance = max(-(MODELVIEW_MATRIX * v).z, 0.5);
	shore = UV2.x;
	UV = world_pos.xz * sampler_scale;
	VERTEX = v.xyz;
}

void fragment() {
	// UV motion
	vec2 uv_offset = sampler_direction * TIME;
	vec2 uv_sampler_uv = UV * uv_sampler_scale + uv_offset;
	vec2 uv_sampler_uv_offset = uv_sampler_strength * texture(uv_sampler, uv_sampler_uv).rg * 2.0 - 1.0;
	vec2 uv = UV + uv_sampler_uv_offset;

	// Normal map
	vec3 normalmap = texture(normalmap_a_sampler, uv - uv_offset * 2.0).rgb * 0.75;
	normalmap += texture(normalmap_b_sampler, uv + uv_offset).rgb * 0.25;

	// Refraction UV
	vec3 ref_normalmap = normalmap * 2.0 - 1.0;
	ref_normalmap = normalize(vertex_tangent * ref_normalmap.x + vertex_binormal * ref_normalmap.y + vertex_normal * ref_normalmap.z);
	vec2 ref_uv = SCREEN_UV + (ref_normalmap.xy * refraction) / view_distance * 10.0;

	// Water thickness below this pixel (metres)
	float thickness;
	if (fake_depth > 0.0) {
		thickness = shore * fake_depth;
	} else {
		float depth_raw = texture(depth_tex, ref_uv).r;
		vec4 view = INV_PROJECTION_MATRIX * vec4(ref_uv * 2.0 - 1.0, depth_raw, 1.0);
		float ground = -view.z / view.w;
		thickness = min(ground + VERTEX.z, max_depth);
	}

	float depth_blend = exp((thickness + depth_offset) * -beers_law);
	depth_blend = clamp(1.0 - depth_blend, 0.0, 1.0);
	float depth_blend_pow = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

	// Ground seen through the water
	vec3 screen_color = textureLod(screen_tex, ref_uv, depth_blend_pow * 2.5).rgb;
	vec3 dye_color = mix(color_shallow.rgb, color_deep.rgb, depth_blend_pow);
	vec3 color = mix(screen_color * dye_color, dye_color * 0.25, depth_blend_pow * 0.5);

	// Caustics: two scrolling noise samples, bright where they cross
	vec2 cp = world_pos.xz * caustic_scale;
	float n1 = texture(uv_sampler, cp + vec2(TIME * 0.031, TIME * 0.017)).r;
	float n2 = texture(uv_sampler, cp * 1.13 - vec2(TIME * 0.023, TIME * 0.029) + 0.37).r;
	float caustic = pow(clamp(1.0 - abs(n1 - n2) * 5.0, 0.0, 1.0), 6.0);
	color *= 1.0 + caustic * (1.0 - depth_blend) * 1.5 * caustic_strength;

	// Foam where the water is thin (shore, rocks)
	if (thickness < 1.0) {
		float foam_noise = clamp(pow(texture(foam_sampler, (uv * 4.0) - uv_offset).r, 10.0) * 40.0, 0.0, 0.2);
		float foam_mix = clamp(pow((1.0 - thickness + foam_noise), 8.0) * foam_noise * 0.4 * foam_level * 2.0, 0.0, 1.0);
		color = mix(color, vec3(1.0), foam_mix);
	}

	ALBEDO = color;
	METALLIC = 0.1;
	ROUGHNESS = 0.2;
	SPECULAR = 0.2 + depth_blend_pow * 0.4;
	NORMAL_MAP = normalmap;
	NORMAL_MAP_DEPTH = 1.25;
}
