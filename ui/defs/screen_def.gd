class_name ScreenDef
extends Resource
## One openable screen. Owner: Lane D (D-01). Data: data/ui/screens/<id>.tres.
## UI loads every .tres in data/ui/screens/ at start; UI.register_screen() adds more at runtime.

@export var id: StringName
@export_file("*.tscn") var scene_path: String
## Pauses the game tree while open (bag, settings...). Base screens with time stopped also pause.
@export var pauses_game := false
## Esc / ui_cancel closes it when it is the top screen.
@export var closes_on_cancel := true
## Other screens stay visible underneath (overlays like the confirm dialog).
@export var is_overlay := false
## Hides the field HUD while open.
@export var hides_hud := true
