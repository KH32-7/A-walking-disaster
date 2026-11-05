// Toon shader without backface culling, for leaf/grass cards, billboards and thin two-sided
// props. Owner: Lane D (D-03). Same uniforms as toon.gdshader; Godot flips NORMAL on back faces.
// Use with alpha_cut and without the outline next_pass (the inverted hull ignores alpha).
shader_type spatial;
render_mode diffuse_toon, specular_disabled, cull_disabled;

#include "res://art/shaders/toon_common.gdshaderinc"
