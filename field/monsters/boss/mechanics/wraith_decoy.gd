extends Monster
## 수술등 망령's clone (docs/design/04-monsters.md "보스": 분신 2개, 진짜만 그림자가 있음). Same look as the
## boss but casts no shadow. It follows you and swings for nothing (attack 0); the first real hit pops it.
## It vanishes instead of dying, so it counts as no kill and drops nothing. Made by wraith_mechanic.gd.

const POP_FX := &"boss_decoy_pop"


func _ready() -> void:
	super._ready()
	drop_mult = 0.0
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func take_damage(amount: float, info: Dictionary = {}) -> void:
	if is_dead() or amount <= 0.0 or StatusHolder.is_tick(info):
		return
	Fx.spawn(POP_FX, global_position, {"element": def.family})
	vanish()
