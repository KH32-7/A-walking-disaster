// Haesol toon shader. Owner: Lane D (D-03). Design: docs/design/16-art-sound.md "아트 방향".
// 2~3 band diffuse + rim light + optional soft specular. Outline is a separate next_pass
// material (outline.gdshader). Characters use MToon (D-09); this is for props, buildings, monsters.
// Body lives in toon_common.gdshaderinc (shared with toon_double_sided.gdshader).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

#include "res://art/shaders/toon_common.gdshaderinc"
