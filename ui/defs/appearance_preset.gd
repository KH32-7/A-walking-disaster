class_name AppearancePreset
extends Resource
## One appearance preset (D-09). Owner: Lane D. Data: data/ui/appearance/<id>.tres.
## Design 07 "입주 의식" step 3 (머리 모양·색, 옷 색 프리셋 조합). Display only - no stats.
## A resident's `appearance` Dictionary (Colony, C) stores ids/colours:
##   {"preset": StringName, "hair": StringName, "hair_color": Color, "outfit_color": Color, "skin": Color}
## CharacterLook.apply() reads that Dictionary; missing keys fall back to this preset.

@export var id: StringName
@export var display_name := ""
## Hair mesh id. VRM: the hair material/mesh name prefix in the .vrm; placeholder: a shape id.
@export_enum("short", "bob", "long", "tied", "cap") var hair := "short"
@export var hair_color := Color("3b2a22")
@export var skin := Color("f0d7bf")
@export var outfit_color := Color("5f7d6a")
@export var outfit_accent := Color("d9c7a3")
## VRoid base model under res://assets/characters/vroid/ (empty until the pipeline lands).
@export_file("*.vrm", "*.tscn", "*.glb") var base_model := ""
## Age stage the preset suits (Enums.AgeStage); -1 = any.
@export var age_stage := -1
