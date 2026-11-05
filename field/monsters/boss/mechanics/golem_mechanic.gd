extends BossMechanic
## 방파제 골렘 (docs/design/04-monsters.md "보스"): wave slam and rock throw are common patterns (data). This
## script runs its guard stance and the way to break it.
## - Guard (action &"guard"): it plants itself for params.guard_sec with a stone shield on (Fx), defense x
##   params.defense_mult. No attacks meanwhile.
## - A blunt weapon hit (ItemDef.combat_class BLUNT, 04 "둔기 방어 파괴로 태세 해제") breaks the guard at once:
##   shield shatters, it staggers params.break_stagger_sec. Other hits just do less damage.
## Numbers are in data/monsters/bosses/breakwater_golem.tres (pattern params), all drafts.

const GUARD_FX := &"boss_guard"
const BREAK_FX := &"boss_guard_break"

var guarding := false

var _guard_left := 0.0
var _guard_pattern: BossPattern
var _shield: Node3D  # the guard Fx, removed when the guard ends early


func on_tick(delta: float) -> void:
	if not guarding:
		return
	_guard_left -= delta
	boss.velocity = Vector3.ZERO
	if _guard_left <= 0.0:
		_end_guard()


func can_use(pattern: BossPattern) -> bool:
	return not guarding or pattern.action == &""


func land_pattern(pattern: BossPattern, _area: Dictionary) -> bool:
	if pattern.action != &"guard":
		return false
	_guard_pattern = pattern
	guarding = true
	_guard_left = float(pattern.params.get("guard_sec", 8.0))
	boss.hold(_guard_left)
	_shield = Fx.spawn_node(GUARD_FX, boss.global_position, {"element": boss.def.family, "duration": _guard_left})
	return true


func filter_damage(amount: float, info: Dictionary) -> float:
	if not guarding or StatusHolder.is_tick(info):
		return amount
	if is_blunt(info):
		_break_guard()
		return amount
	# Defense x mult, through the same curve Monster.take_damage uses: scale by the factor ratio.
	var d := boss.def.defense
	var mult := float(_guard_pattern.params.get("defense_mult", 2.0)) if _guard_pattern else 2.0
	return amount * MonsterRules.defense_factor(d * mult) / MonsterRules.defense_factor(d)


func on_reset() -> void:
	if guarding:
		_end_guard()


func on_died() -> void:
	guarding = false


## The hit came from a blunt weapon (club, bat, hammer...): info["weapon"] is the ItemDef id.
static func is_blunt(info: Dictionary) -> bool:
	var id := StringName(info.get("weapon", &""))
	if id == &"":
		return false
	var item := Armory.get_def(id)
	return item != null and item.combat_class == Enums.CombatClass.BLUNT


func _break_guard() -> void:
	_end_guard()
	Fx.spawn(BREAK_FX, boss.global_position, {"element": boss.def.family})
	var sec := float(_guard_pattern.params.get("break_stagger_sec", 2.0)) if _guard_pattern else 2.0
	boss.status.apply(&"stagger", {"duration": sec})
	var visual := boss.get_node_or_null(^"Visual") as MonsterVisual
	if visual:
		visual.play_once(&"Hit")


func _end_guard() -> void:
	guarding = false
	_guard_left = 0.0
	boss.hold(0.0)
	if is_instance_valid(_shield):
		_shield.queue_free()
	_shield = null
