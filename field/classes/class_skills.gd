class_name ClassSkills
extends Node
## Player class runtime (B-13): skills Q / E, passives (mastery 5 and 10), class on-hit effects and
## mastery XP. Created by Player (`ClassSkills.attach(self)`, child "ClassSkills").
## The class is the main weapon's family (Armory.get_combat_class); data in data/classes/.
##
## Hooks it sets on the player's WeaponHolder ("Weapons") and Player:
## - WeaponHolder.hit_filter = filter_hit: skill multipliers, passives, on-hit statuses.
## - WeaponHolder.shot_pierces (precision shot armed), WeaponHolder.reload_mult (gun passive).
## - Player.incoming_damage_filter wraps the WeaponHolder's block filter (brace).
## - Shadow step: the player joins STEALTH_GROUP (Monster.can_see is false) and its footstep
##   noise is pushed below 0 (NoiseEmitter emits nothing at radius 0).
## Mastery XP: WeaponHolder.hit_landed during a sortie (ClassMastery).
## Fx and Audio ids are the skill id (precision_shot, dash_slash ...) at the player's position.
## Design reference: docs/design/03-combat-classes.md "클래스"

## Used a skill (Lane D: cast effects, HUD flash). slot = &"q" or &"e".
signal skill_used(slot: StringName, skill_id: StringName)
## A lasting skill ended: precision shot fired, suppressive fire, shadow step, brace.
signal skill_ended(skill_id: StringName)

const NODE_NAME := &"ClassSkills"
const NODE_PATH := ^"ClassSkills"
## Monsters cannot see bodies in this group (shadow step).
const STEALTH_GROUP := &"stealthed"
const SLOTS: Array[StringName] = [&"q", &"e"]
const HUD_KEYS := {&"q": "Q", &"e": "E"}
## Dash slash travel time (the hits land at the start).
const DASH_SEC := 0.15
## Added to footstep radii while hidden: far below any footstep radius, so they come out 0.
const SILENT_FOOTSTEP_M := -100.0
## Suppressive fire repeats its 25 m noise this often while it lasts.
const SUPPRESS_NOISE_SEC := 1.0

var mastery := ClassMastery.new()

var _player: Player
var _holder: WeaponHolder
var _prev_incoming: Callable
## Skill id -> seconds left / full cooldown of its last use. By id, not slot: a weapon swap in a
## test scene changes the class, and its skills keep their own timers.
var _cooldown: Dictionary = {}
var _cooldown_max: Dictionary = {}
## Skill running per effect, null when off.
var _precision: SkillDef
var _focus_left := 0.0
var _armed := false
var _suppress: SkillDef
var _suppress_left := 0.0
var _suppress_noise_left := 0.0
var _stealth: SkillDef
var _stealth_left := 0.0
var _footstep_before := 0.0
var _brace: SkillDef
var _brace_left := 0.0
var _dash_left := 0.0
var _dash_from := Vector3.ZERO
var _dash_to := Vector3.ZERO


## Creates the runtime as a child of `player`. Call it from the player's @onready.
static func attach(player: Player) -> ClassSkills:
	var skills := ClassSkills.new()
	skills.name = NODE_NAME
	player.add_child(skills)
	return skills


## HUD `skills` key (issue #28): [{key, left, max}] for each enabled skill of the player's class.
static func hud_list(player: Node) -> Array:
	var skills := player.get_node_or_null(NODE_PATH) as ClassSkills
	return skills.hud_skills() if skills != null else []


## BLUNT mastery 10 "방어 파괴한 적에게 아군 피해 +15%" for any party member's hit on `victim`.
## Companions call this from their own damage (B-17).
static func party_damage_mult(victim: Node, tree: SceneTree) -> float:
	var player := tree.get_first_node_in_group(Player.GROUP) if tree != null else null
	var skills := player.get_node_or_null(NODE_PATH) as ClassSkills if player != null else null
	return skills.armor_broken_mult(victim) if skills != null else 1.0


func _ready() -> void:
	_player = get_parent() as Player
	_holder = _player.get_node_or_null(^"Weapons") as WeaponHolder if _player else null
	if _holder == null:
		push_error("ClassSkills must be a child of a Player with a Weapons node")
		set_physics_process(false)
		return
	_holder.hit_filter = filter_hit
	_holder.attacked.connect(_on_attacked)
	_holder.hit_landed.connect(_on_hit_landed)
	_holder.weapon_changed.connect(_on_weapon_changed)
	_prev_incoming = _player.incoming_damage_filter
	_player.incoming_damage_filter = filter_incoming
	_player.downed.connect(cancel_all)


func _physics_process(delta: float) -> void:
	if _player.is_downed:
		return
	step(delta, {
		"skill_q": Input.is_action_just_pressed(&"skill_q"),
		"skill_e": Input.is_action_just_pressed(&"skill_e"),
	})


## One step. Split from input reading so tests can drive it. input: {"skill_q": bool, "skill_e": bool}
func step(delta: float, input: Dictionary) -> void:
	for id: StringName in _cooldown:
		_cooldown[id] = maxf(_cooldown[id] - delta, 0.0)
	_holder.reload_mult = 1.0 - passive(&"reload_fast")
	_step_effects(delta)
	if input.get("skill_q", false):
		use(&"q")
	if input.get("skill_e", false):
		use(&"e")


# --- Public ---------------------------------------------------------------

## The player's class (Enums.CombatClass), -1 with no main weapon.
func combat_class() -> int:
	return Armory.get_combat_class(_holder.owner_id)


func class_def() -> ClassDef:
	return ClassDef.for_class(combat_class())


## The enabled skill in `slot` (&"q" / &"e") of the player's class, or null.
func skill_for(slot: StringName) -> SkillDef:
	var def := class_def()
	if def == null:
		return null
	var skill: SkillDef = def.skill_q if slot == &"q" else def.skill_e
	return skill if skill != null and skill.enabled else null


func cooldown_left(slot: StringName) -> float:
	var skill := skill_for(slot)
	return _cooldown.get(skill.id, 0.0) if skill != null else 0.0


## Value of a passive of the player's class at its current mastery (0 = locked or not this class).
func passive(id: StringName) -> float:
	var def := class_def()
	return def.passive_value(id, ClassMastery.level(def.id)) if def != null else 0.0


## Lasting effects now: [{"id", "time_left"}] (precision shot armed = time_left 0). Lane D: visuals.
func active() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _precision != null:
		out.append({"id": _precision.id, "time_left": _focus_left})
	for pair: Array in [[_suppress, _suppress_left], [_stealth, _stealth_left], [_brace, _brace_left]]:
		if pair[0] != null:
			out.append({"id": (pair[0] as SkillDef).id, "time_left": pair[1]})
	return out


func is_hidden() -> bool:
	return _stealth != null


func hud_skills() -> Array:
	var out: Array = []
	for slot: StringName in SLOTS:
		var skill := skill_for(slot)
		if skill != null:
			out.append({"key": HUD_KEYS[slot], "left": cooldown_left(slot),
				"max": _cooldown_max.get(skill.id, skill.cooldown_sec)})
	return out


## Uses the skill in `slot`. Switches to the main weapon first when another family is in hand.
## False when there is none, it is cooling down, or the player cannot act.
func use(slot: StringName) -> bool:
	var skill := skill_for(slot)
	if skill == null or cooldown_left(slot) > 0.0 or not _can_act() or not _hold_class_weapon():
		return false
	var was_hidden := _stealth != null and skill.id != &"shadow_step"
	match skill.id:
		&"precision_shot":
			_precision = skill
			_focus_left = skill.duration_sec
			_armed = false
		&"suppressive_fire":
			_suppress = skill
			_suppress_left = skill.duration_sec
			_suppress_noise_left = SUPPRESS_NOISE_SEC
		&"dash_slash":
			_start_dash(skill)
		&"shadow_step":
			_start_stealth(skill)
		&"slam":
			for monster in SkillTargets.monsters_in_radius(_player, _player.global_position, skill.radius):
				_holder.skill_hit(monster, skill.damage_mult, _skill_info(skill))
		&"brace":
			_brace = skill
			_brace_left = skill.duration_sec
			for monster in SkillTargets.monsters_in_radius(_player, _player.global_position, skill.radius):
				monster.chase(_player)  # 도발
		_:
			push_warning("ClassSkills: unknown skill %s" % skill.id)
			return false
	if was_hidden:
		_end_stealth()  # a damaging skill is the first attack out of hiding
	_cooldown_max[skill.id] = skill.cooldown_for(_holder.current_stats())
	_cooldown[skill.id] = _cooldown_max[skill.id]
	_emit_noise(skill.noise)
	Audio.play(skill.id, _player.global_position)
	Fx.spawn(skill.id, _player.global_position, {"direction": _player.facing(), "radius": skill.radius})
	skill_used.emit(slot, skill.id)
	return true


## Stops every lasting effect (downed).
func cancel_all() -> void:
	_end_precision()
	_end_suppress()
	_end_stealth()
	_end_brace()
	_dash_left = 0.0


## WeaponHolder.hit_filter: (target, amount, info) -> amount. May add info["status"].
func filter_hit(target: Node, amount: float, info: Dictionary) -> float:
	var stats := _holder.current_stats()
	var family := int(stats.get("combat_class", -1))
	var def := class_def()
	if _armed:
		amount *= _precision.damage_mult
	if _stealth != null:
		amount *= _stealth.damage_mult
	if _suppress != null and family == Enums.CombatClass.GUN:
		_add_status(info, _suppress.status_effects)
	amount *= armor_broken_mult(target)
	if def == null or family != def.id:
		return amount
	_add_status(info, def.hit_status)
	var finisher := int(stats.get("guard_break_hits", _holder.tuning.combo_hits))
	if int(info.get("combo_step", 0)) >= finisher:
		_add_status(info, def.finisher_status)
	if target is MonsterWeakPoint:
		amount *= 1.0 + passive(&"weak_point_bonus")
	if info.get("backstab", false):
		amount *= 1.0 + passive(&"backstab_bonus")
	_apply_status_passives(info)
	return amount


## Player.incoming_damage_filter: block first (WeaponHolder), then brace -60% and no knockback.
func filter_incoming(amount: float, info: Dictionary) -> float:
	if _prev_incoming.is_valid():
		amount = _prev_incoming.call(amount, info)
	if _brace == null or amount <= 0.0:
		return amount
	var kept: Array = []
	for entry: Dictionary in info.get("status", []):
		var def := StatusHolder.get_def(entry.get("id", &""))
		if def == null or def.knockback_m <= 0.0:
			kept.append(entry)
	if info.has("status"):
		info["status"] = kept
	return amount * _brace.damage_taken_mult


## x(1 + armor_broken_bonus) when `victim` has armor break and the passive is unlocked, else 1.
func armor_broken_mult(victim: Node) -> float:
	var bonus := passive(&"armor_broken_bonus")
	var monster := SkillTargets.monster_of(victim)
	if bonus <= 0.0 or monster == null or not monster.status.has(&"armor_break"):
		return 1.0
	return 1.0 + bonus


# --- Internals ------------------------------------------------------------

func _can_act() -> bool:
	return not _player.is_downed and _player.status.can_act() and _holder.can_act() and _dash_left <= 0.0


## The weapon in hand must be the class's family (its damage is the skill's base).
func _hold_class_weapon() -> bool:
	var family := combat_class()
	if int(_holder.current_stats().get("combat_class", -1)) != family:
		_holder.switch_to(Enums.EquipSlot.MAIN)
	return family >= 0 and int(_holder.current_stats().get("combat_class", -1)) == family


func _step_effects(delta: float) -> void:
	if _precision != null and not _armed:
		_focus_left = maxf(_focus_left - delta, 0.0)
		if _focus_left <= 0.0:
			_armed = true
			_holder.shot_pierces = true
	if _suppress != null:
		_suppress_left -= delta
		_suppress_noise_left -= delta
		if _suppress_noise_left <= 0.0:
			_suppress_noise_left += SUPPRESS_NOISE_SEC
			_emit_noise(_suppress.noise)
		if _suppress_left <= 0.0 or not WeaponHolder.is_gun(_holder.current_stats()):
			_end_suppress()
		else:
			_holder.fire()  # 연사: every attack_interval, magazine and reload as usual
	if _stealth != null:
		_stealth_left -= delta
		if _stealth_left <= 0.0:
			_end_stealth()
	if _brace != null:
		_brace_left -= delta
		if _brace_left <= 0.0:
			_end_brace()
	if _dash_left > 0.0:
		_dash_left = maxf(_dash_left - delta, 0.0)
		var p := _dash_from.lerp(_dash_to, 1.0 - _dash_left / DASH_SEC)
		_player.global_position = Vector3(p.x, _player.global_position.y, p.z)
		_player.velocity = Vector3(0.0, _player.velocity.y, 0.0)


func _start_dash(skill: SkillDef) -> void:
	var dir := _player.facing()
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_dash_from = _player.global_position
	_dash_to = _dash_from + dir * SkillTargets.clear_distance(_player, _dash_from, dir, skill.distance)
	for monster in SkillTargets.monsters_on_segment(_player, _dash_from, _dash_to, skill.radius):
		_holder.skill_hit(monster, skill.damage_mult, _skill_info(skill))
	_dash_left = DASH_SEC


func _start_stealth(skill: SkillDef) -> void:
	if _stealth == null:
		var noise := _noise()
		_footstep_before = noise.footstep_bonus_m if noise else 0.0
		if noise:
			noise.footstep_bonus_m = SILENT_FOOTSTEP_M
		_player.add_to_group(STEALTH_GROUP)
	_stealth = skill
	_stealth_left = skill.duration_sec


func _end_precision() -> void:
	if _precision == null:
		return
	var id := _precision.id
	_precision = null
	_armed = false
	_holder.shot_pierces = false
	skill_ended.emit(id)


func _end_suppress() -> void:
	if _suppress == null:
		return
	var id := _suppress.id
	_suppress = null
	skill_ended.emit(id)


func _end_stealth() -> void:
	if _stealth == null:
		return
	var id := _stealth.id
	_stealth = null
	var noise := _noise()
	if noise:
		noise.footstep_bonus_m = _footstep_before
	_player.remove_from_group(STEALTH_GROUP)
	skill_ended.emit(id)


func _end_brace() -> void:
	if _brace == null:
		return
	var id := _brace.id
	_brace = null
	skill_ended.emit(id)


func _skill_info(skill: SkillDef) -> Dictionary:
	return {"status": skill.status_effects.duplicate(true), "skill": skill.id}


static func _add_status(info: Dictionary, entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		return
	var list: Array = info.get("status", []).duplicate()
	for entry in entries:
		list.append(entry.duplicate())
	info["status"] = list


## Blade 10: bleed stacks up to 2. Blunt 5: stagger lasts +30%.
func _apply_status_passives(info: Dictionary) -> void:
	var bleed_cap := int(passive(&"bleed_stacks"))
	var stagger := passive(&"stagger_longer")
	if bleed_cap <= 0 and stagger <= 0.0:
		return
	for entry: Dictionary in info.get("status", []):
		match entry.get("id", &""):
			&"bleed":
				if bleed_cap > 0:
					entry["stacks_max"] = bleed_cap
			&"stagger":
				if stagger > 0.0:
					var def := StatusHolder.get_def(&"stagger")
					entry["duration"] = float(entry.get("duration", def.duration_sec)) * (1.0 + stagger)


func _emit_noise(action: StringName) -> void:
	var noise := _noise()
	if noise != null and action != &"":
		noise.emit(action)


func _noise() -> NoiseEmitter:
	return _player.get_node_or_null(^"Noise") as NoiseEmitter


func _on_attacked(kind: StringName, _combo_step: int) -> void:
	if kind == &"shot" and _armed:
		_end_precision()
	_end_stealth()


func _on_hit_landed(target: Node, amount: float, _info: Dictionary) -> void:
	if not FieldState.in_sortie():
		return
	var monster := SkillTargets.monster_of(target)
	var family := int(_holder.current_stats().get("combat_class", -1))
	mastery.gain(family, amount, monster != null and monster.is_dead(),
			_holder.active_slot == Enums.EquipSlot.SUB)


func _on_weapon_changed(_slot: Enums.EquipSlot, _uid: StringName) -> void:
	_end_precision()
	_end_suppress()
