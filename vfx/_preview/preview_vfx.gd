extends Node3D
## D-18 preview: every Fx id on a grey field under the field camera (55° pitch, FOV 60).
## Views: combat (gun, melee, hit sparks, damage numbers, hit flash), elements, combos, release,
## blast (explosion, neon moth, noise lure), telegraph, monsters and boss (D-17: the real models with their
## attack and death effects; needs assets/). Keys 1-8 switch views, R replays, F toggles
## Settings.reduce_flash. Effects run on a fixed 60 fps timeline (Fx.manual_step) so shots repeat.
## Optional: -- --view=combat --shot=user://vfx.png --t=0.12        (one frame at 0.12 s)
##           -- --view=combat --shot=user://vfx.png --t=0.05,0.15,0.3  (user://vfx_0.png, _1, _2)
##           -- --reduce_flash

const VIEWS := ["combat", "elements", "combos", "release", "blast", "telegraph", "monsters", "boss"]
const DT := 1.0 / 60.0
const LOOP_SEC := 3.6

class FakeMonster:
	extends MeshInstance3D
	signal damaged(amount: float, info: Dictionary)
	var state: int = Enums.AIState.CHASE

	func _init(pos: Vector3, look: String) -> void:
		position = pos
		var cm := CapsuleMesh.new()
		cm.radius = 0.45
		cm.height = 1.5
		mesh = cm
		material_override = load("res://art/materials/%s.tres" % look)
		add_to_group(&"field_monsters")

class FakePlayer:
	extends MeshInstance3D
	signal health_changed(current: float, maximum: float)
	var health := 100.0

	func _init(pos: Vector3) -> void:
		position = pos
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.7
		mesh = cm
		material_override = load("res://art/materials/toon_default.tres")
		add_to_group(&"player")

	func hurt(amount: float) -> void:
		health -= amount
		health_changed.emit(health, 100.0)

var _view := "combat"
var _shot := ""
var _times: Array[float] = []
var _clock := 0.0
var _timeline: Array[Dictionary] = []  # {t, call: Callable}
var _stage: Node3D
var _cam: Camera3D
var _anims: Array[AnimationPlayer] = []  # D-17 models, stepped with the timeline


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			_view = a.trim_prefix("--view=")
		elif a.begins_with("--shot="):
			_shot = a.trim_prefix("--shot=")
		elif a.begins_with("--t="):
			for s in a.trim_prefix("--t=").split(","):
				_times.append(float(s))
		elif a == "--reduce_flash":
			Fx.reduced_flash_override = 1  # never write the player's settings file from a preview
	if _times.is_empty():
		_times = [0.15]
	Fx.manual_step = true
	# The title screen (D-19) opens on boot over any scene; a VFX preview shows only the world.
	for layer in UI.get_children():
		if layer is CanvasLayer and layer.name != &"ColorFilterLayer":
			(layer as CanvasLayer).visible = false
	_world()
	_build_view()
	if _shot != "":
		_capture()


func _world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("8fb5c4")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c3cfd6")
	e.ambient_light_energy = 0.55
	e.glow_enabled = true
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60, 0.2, 60)
	ground.mesh = bm
	ground.position.y = -0.1
	# Field concrete in shade: mid grey, so both glows and dark outlines have to read on it.
	var mat := (load("res://art/materials/toon_concrete.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"albedo", Color(0.56, 0.57, 0.55))
	ground.material_override = mat
	add_child(ground)


func _aim(focus: Vector3, dist: float) -> void:
	var yaw := deg_to_rad(45.0)
	var pitch := deg_to_rad(55.0)
	_cam.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	_cam.look_at(focus)


func _build_view() -> void:
	if _stage:
		_stage.free()
	Fx.clear()
	_stage = Node3D.new()
	add_child(_stage)
	_timeline.clear()
	_anims.clear()
	_clock = 0.0
	match _view:
		"elements":
			_elements()
		"combos":
			_combos()
		"release":
			_release()
		"blast":
			_blast()
		"telegraph":
			_telegraph()
		"monsters":
			_monsters()
		"boss":
			_boss()
		_:
			_combat()
	Fx.feedback.scan()


func _at(t: float, call: Callable) -> void:
	_timeline.append({"t": t, "call": call})


## t < 0: the effect started before the shot (a lure mid-fuse) and catches up when it appears.
func _fx(t: float, id: StringName, pos: Vector3, params: Dictionary = {}) -> void:
	_at(t, func() -> void:
		var fx := Fx.spawn_node(id, pos, params)
		if fx and t < 0.0:
			fx.advance(-t))


## Review caption on the ground just in front of `pos` (below it on screen, clear of damage numbers).
func _caption(pos: Vector3, text: String) -> void:
	pos = Vector3(pos.x + 0.9, 0.05, pos.z + 0.9)
	var l := Label3D.new()
	l.text = text
	l.font = UiThemeBuilder.font_kr(700)
	l.font_size = 30
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0011
	l.no_depth_test = true
	l.position = pos
	_stage.add_child(l)


func _box(pos: Vector3, size: Vector3, look: String = "toon_wood") -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = load("res://art/materials/%s.tres" % look)
	_stage.add_child(mi)


# --- views ---------------------------------------------------------------------------------------

func _combat() -> void:
	_aim(Vector3(0.5, 0.5, 0), 15.0)
	var player := FakePlayer.new(Vector3(-3.5, 0.85, 1.5))
	_stage.add_child(player)
	var m1 := FakeMonster.new(Vector3(3, 0.75, -2), "toon_foliage")
	var m2 := FakeMonster.new(Vector3(4.5, 0.75, 1.5), "toon_foliage")
	var m3 := FakeMonster.new(Vector3(1, 0.75, 3.5), "toon_wood")
	for m in [m1, m2, m3]:
		_stage.add_child(m)
	_box(Vector3(5.5, 1.0, -4.5), Vector3(4, 2, 0.6), "toon_concrete")
	var muzzle := player.position + Vector3(0.5, 0.4, -0.3)
	var aim1: Vector3 = m1.position + Vector3(0, 0.3, 0)
	_fx(0.0, &"muzzle_flash", muzzle, {"direction": (aim1 - muzzle).normalized()})
	_fx(0.0, &"bullet_tracer", muzzle, {"to": aim1})
	_at(0.06, func() -> void:
		Fx.spawn(&"hit_spark", aim1, {"element": Enums.Element.WATER})
		m1.damaged.emit(18.0, {"position": aim1 + Vector3.UP * 0.4, "element": Enums.Element.WATER}))
	var wall := Vector3(4.8, 1.2, -4.15)
	_fx(0.04, &"muzzle_flash", muzzle, {"direction": (wall - muzzle).normalized()})
	_fx(0.04, &"bullet_tracer", muzzle, {"to": wall})
	_fx(0.11, &"bullet_impact", wall, {"normal": Vector3(0, 0, 1)})
	var crit_at: Vector3 = m2.position + Vector3(0, 0.4, 0)
	_at(0.02, func() -> void:
		Fx.spawn(&"hit_spark", crit_at, {"crit": true, "weak_point": true})
		m2.damaged.emit(46.0, {"position": crit_at + Vector3.UP * 0.5, "crit": true, "weak_point": true}))
	_fx(0.0, &"melee_swing", m3.position + Vector3(-1.2, -0.75, -0.6), {"direction": Vector3(1, 0, 0.6), "combo_step": 1})
	var blunt_at: Vector3 = m3.position + Vector3(0, 0.3, 0)
	_at(0.04, func() -> void:
		Fx.spawn(&"hit_spark", blunt_at, {"element": Enums.Element.GREEN})
		m3.damaged.emit(24.0, {"element": Enums.Element.GREEN})
		m3.damaged.emit(3.0, {"status_tick": true, "element": Enums.Element.GREEN, "position": blunt_at + Vector3(0.4, 0.9, 0)}))
	_fx(0.0, &"perfect_block", Vector3(-1.0, 0, -2.5))
	_at(0.03, func() -> void: player.hurt(12.0))
	_caption(Vector3(-3.5, 2.6, 1.5), "플레이어 피격 (-12, 붉은 번쩍임)")
	_caption(Vector3(-1.0, 2.4, -2.5), "완벽 막기")
	_caption(Vector3(3, 2.4, -2), "물 속성 적중")
	_caption(Vector3(4.5, 2.6, 1.5), "치명타 + 약점")
	_caption(Vector3(1, 2.4, 3.5), "근접 + 초록 + 지속 피해")
	_caption(Vector3(5.5, 2.6, -4.5), "총알 벽 착탄")


func _elements() -> void:
	_aim(Vector3(0, 0.5, 0), 12.0)
	var ids := [[&"element_green", "초록 · 꽃잎"], [&"element_stone", "돌 · 사각"],
		[&"element_water", "물 · 물방울"], [&"element_light", "빛 · 번개"]]
	for i in ids.size():
		var pos := Vector3(-4.5 + i * 3.0, 0, 1.5 - i * 1.0)
		_stage.add_child(FakeMonster.new(pos + Vector3.UP * 0.75, "toon_default"))
		_fx(0.0, ids[i][0], pos)
		_caption(pos + Vector3.UP * 2.5, ids[i][1])


func _combos() -> void:
	_aim(Vector3(0, 0.5, 0.5), 17.0)
	var ids := [[&"combo_thorn_bush", "가시 덤불 (초록+돌)"], [&"combo_swamp", "늪 (초록+물)"],
		[&"combo_photosynthesis", "광합성 (초록+빛)"], [&"combo_mud", "진흙 (돌+물)"],
		[&"combo_shard_burst", "파편 폭발 (돌+빛)"], [&"combo_shock_puddle", "감전 웅덩이 (물+빛)"]]
	for i in ids.size():
		var pos := Vector3(-5.0 + (i % 3) * 5.0, 0, -2.5 + (i / 3) * 5.5)
		var params := {}
		if ids[i][0] == &"combo_photosynthesis":
			params = {"radius": 2.2}  # preview only: design 5 m would cover the neighbours
		if ids[i][0] == &"combo_shock_puddle":
			params = {"chain": [pos + Vector3(1.6, 0, -0.6), pos + Vector3(0.6, 0, 1.7)]}
			_stage.add_child(FakeMonster.new(pos + Vector3(1.6, 0.75, -0.6), "toon_default"))
			_stage.add_child(FakeMonster.new(pos + Vector3(0.6, 0.75, 1.7), "toon_default"))
		_fx(0.0, ids[i][0], pos, params)
		_caption(pos + Vector3.UP * 2.4, ids[i][1])


func _release() -> void:
	_aim(Vector3(0.5, 0.5, 0), 17.0)
	var ids := [[&"release_gun", "총 해방 · 속성탄 5발 (빛)", Enums.Element.LIGHT, Vector3(-6, 0, 2)],
		[&"release_blade", "칼 해방 · 칼날 폭풍 3m (초록)", Enums.Element.GREEN, Vector3(0, 0, -1)],
		[&"release_blunt", "둔기 해방 · 대지 강타 5m (돌)", Enums.Element.STONE, Vector3(6, 0, 2.5)]]
	for spec in ids:
		_stage.add_child(FakePlayer.new(spec[3] + Vector3.UP * 0.85))
		_fx(0.0, spec[0], spec[3], {"element": spec[2], "direction": Vector3(1, 0, -0.5)})
		_caption(spec[3] + Vector3.UP * 2.8, spec[1])


func _blast() -> void:
	_aim(Vector3(0, 0.5, 0), 14.0)
	_fx(0.0, &"explosion", Vector3(-4, 0, 0.5), {"radius": 3.0})
	_caption(Vector3(-4, 3.2, 0.5), "폭발 3m")
	_fx(0.0, &"neon_moth_blast", Vector3(1.5, 0.8, -2))
	_caption(Vector3(1.5, 3.0, -2), "네온 나방 자폭")
	_fx(-2.0, &"noise_lure", Vector3(3, 0, 2.5), {"silent": true})
	_caption(Vector3(3, 1.6, 2.5), "소음 미끼 (2초 남음)")
	_fx(-3.9, &"noise_lure", Vector3(5.5, 0, -1.5), {"silent": true})
	_caption(Vector3(5.5, 1.6, -1.5), "소음 미끼 (터짐)")


func _telegraph() -> void:
	_aim(Vector3(0.5, 0, 0.5), 20.0)
	var boss := FakeMonster.new(Vector3(0, 1.2, 0), "toon_foliage")
	boss.scale = Vector3.ONE * 1.6
	_stage.add_child(boss)
	_fx(0.0, &"boss_telegraph", Vector3(-5.5, 0, -2), {"shape": &"circle", "radius": 2.5})
	_caption(Vector3(-5.5, 1.4, -2), "원 2.5m")
	_fx(0.0, &"boss_telegraph", Vector3(0, 0, 0), {"shape": &"cone", "radius": 6.0, "angle_deg": 70.0,
		"direction": Vector3(1, 0, 1)})
	_caption(Vector3(2.5, 1.4, 3.0), "부채꼴 70°")
	_fx(0.0, &"boss_telegraph", Vector3(-4, 0, 3), {"shape": &"line", "length": 7.0, "width": 1.6,
		"direction": Vector3(1, 0, 0.3)})
	_caption(Vector3(-1, 1.4, 4.2), "직선 돌진")
	_fx(0.0, &"boss_telegraph", Vector3(6, 0, -4), {"shape": &"ring", "radius": 3.0, "inner": 1.6, "kind": &"warn"})
	_caption(Vector3(6, 1.4, -4), "고리 (둔화, 주황)")


## D-17: each model swings (attack_started), its effect lands ATTACK_WINDUP_SEC later, then two die.
func _monsters() -> void:
	_aim(Vector3(0, 0.6, 1.0), 14.0)
	var face := Vector3(1, 0, 1).normalized()
	var rows := [
		[&"vine_tendril", &"monster_claw", Enums.Element.GREEN, "덩굴촉수: 할퀴기"],
		[&"rubble_bug", &"monster_bite", Enums.Element.STONE, "잔해 벌레: 물기"],
		[&"statue", &"monster_slam", Enums.Element.STONE, "석상: 내려찍기"],
		[&"swamp_blob", &"monster_splash", Enums.Element.WATER, "늪 덩어리: 물 튀김"],
		[&"spore_pod", &"monster_cast", Enums.Element.GREEN, "포자낭: 포자 쏘기"],
		[&"signal_wraith", &"monster_cast", Enums.Element.LIGHT, "신호 망령: 전기 구체"],
	]
	for i in rows.size():
		var pos := Vector3(-5.0 + 5.0 * (i % 3), 0, -2.5 + 5.0 * floorf(i / 3.0))
		var v := _model(rows[i][0], pos, face)
		if v:
			_at(0.0, v._on_attack_started)
		_fx(MonsterRules.ATTACK_WINDUP_SEC, rows[i][1], pos, {"direction": face, "element": rows[i][2]})
		_caption(pos, rows[i][3])
	_fx(1.2, &"monster_scream", Vector3(0, 0, 2.5), {"element": Enums.Element.GREEN})
	_fx(1.6, &"monster_death", Vector3(-5, 0, -2.5), {"element": Enums.Element.GREEN, "radius": 0.7})
	_fx(1.6, &"monster_death", Vector3(5, 0, -2.5), {"element": Enums.Element.STONE, "radius": 1.1})


func _boss() -> void:
	_aim(Vector3(0, 1.0, 1.5), 22.0)
	var face := Vector3(1, 0, 1).normalized()
	var v := _model(&"ancient_tree_giant", Vector3(-2, 0, -2), face)
	if v:
		_at(0.0, v._on_pattern_started.bind(&"slam"))
		_at(1.4, v._on_pattern_started.bind(&"root_burst"))
	_fx(0.6, &"boss_slam", Vector3(-2, 0, -2) + face * 2.5, {"radius": 3.0, "element": Enums.Element.GREEN})
	_caption(Vector3(-2, 0, -2) + face * 2.5, "내려찍기 3m")
	_fx(1.9, &"boss_root_burst", Vector3(-2, 0, -2), {"direction": Vector3(1, 0, 0.2), "length": 10.0,
		"element": Enums.Element.GREEN})
	_caption(Vector3(4, 0, -1), "뿌리 솟기 (직선)")
	for p in [Vector3(-3, 0, 4), Vector3(0, 0, 5), Vector3(3, 0, 4)]:
		_fx(0.3, &"boss_summon_pods", p, {"radius": 1.2, "element": Enums.Element.GREEN})
	_caption(Vector3(0, 0, 5), "포자낭 소환")


## A D-17 model facing `face`, its animation stepped by the timeline. Null without assets/.
func _model(id: StringName, pos: Vector3, face: Vector3) -> MonsterVisual:
	var scene := load("res://art/monsters/%s.tscn" % id) as PackedScene
	if scene == null:
		return null
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = atan2(-face.x, -face.z)
	_stage.add_child(holder)
	var v := scene.instantiate() as MonsterVisual
	holder.add_child(v)
	if v.anim:
		v.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_anims.append(v.anim)
	v.set_process(false)
	return v


# --- timeline ------------------------------------------------------------------------------------

func _advance_to(t: float) -> void:
	while _clock < t - 0.0001:
		_spawn_due()
		Fx.advance(DT)
		for a in _anims:
			a.advance(DT)
		_clock += DT
	_spawn_due()


func _spawn_due() -> void:
	for item in _timeline:
		if not item.get("done", false) and item.t <= _clock + 0.0001:
			item["done"] = true
			item.call.call()


func _capture() -> void:
	for i in _times.size():
		_advance_to(_times[i])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := _shot if _times.size() == 1 else _shot.replace(".png", "_%d.png" % i)
		get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()


func _process(delta: float) -> void:
	if _shot != "":
		return
	_advance_to(_clock + delta)
	if _clock > LOOP_SEC:
		_build_view()


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or _shot != "":
		return
	if k.keycode >= KEY_1 and k.keycode < KEY_1 + VIEWS.size():
		_view = VIEWS[k.keycode - KEY_1]
		_build_view()
	elif k.keycode == KEY_R:
		_build_view()
	elif k.keycode == KEY_F:
		Fx.reduced_flash_override = 0 if Fx.reduced_flash() else 1
		_build_view()
