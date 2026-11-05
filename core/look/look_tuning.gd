class_name LookTuning
extends Resource
## Numbers for the full-screen stylized look (prototype, user request 2026-11-06).
## Values live in data/look/look_tuning.tres; tune live with the \ debug panel (core/debug/look_panel.gd).
## Each property is passed to core/look/stylized_post.gdshader as the uniform of the same name.

## Off = the game renders exactly as before (no extra pass).
@export var enabled := false

## Toon shading on every toon surface (global shader uniform `toon_amount`): 1 = toon, 0 = plain.
## 0 by default: toon off (user decision 2026-11-06).
@export_range(0.0, 1.0, 0.05) var toon_amount := 0.0

@export_group("Painterly")
## Kuwahara filter radius in pixels, 0 = off. Flattens photo-like texture noise into painted patches.
@export_range(0, 6, 1) var paint_radius := 3
## Pixels between painterly samples: wider strokes for the same cost.
@export_range(1.0, 4.0, 0.25) var paint_step := 2.5

@export_group("Outline")
@export_range(0.0, 4.0, 0.25) var outline_px := 1.5
## Relative depth jump (x view distance) that counts as an edge.
@export_range(0.0, 1.0, 0.01) var outline_depth := 0.12
## 1 - dot(normals) that counts as an edge.
@export_range(0.0, 2.0, 0.05) var outline_normal := 0.7
@export_range(0.0, 1.0, 0.05) var outline_strength := 0.8
@export var outline_color := Color(0.08, 0.09, 0.11)
## No outlines past this view distance (m).
@export_range(5.0, 200.0, 1.0) var outline_fade_far := 60.0

@export_group("Color")
@export_range(0.0, 2.0, 0.05) var saturation := 1.2
@export_range(0.5, 2.0, 0.05) var contrast := 1.1
@export_range(0.5, 2.0, 0.05) var brightness := 1.3
## Lightness snapped to this many steps, 0 = off.
@export_range(0, 8, 1) var bands := 0
@export_range(0.0, 1.0, 0.05) var band_mix := 0.5

@export_group("Player")
## Player outline width in screen pixels (works with the look off too), 0 = off.
@export_range(0.0, 8.0, 0.25) var hero_outline_px := 2.5
@export var hero_outline_color := Color(1.0, 0.92, 0.7)

## Shader uniform names, in panel order.
const PARAMS := [
	&"paint_radius", &"paint_step", &"outline_px", &"outline_depth", &"outline_normal", &"outline_strength",
	&"outline_color", &"outline_fade_far", &"saturation", &"contrast", &"brightness", &"bands", &"band_mix",
]
