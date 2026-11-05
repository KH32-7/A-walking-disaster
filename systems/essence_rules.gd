class_name EssenceRules
## Essence / engraving / combo / refining numbers and effect calculation (task A-10). No game state:
## Armory keeps the items and calls these. Defs load once from data/essences/ on first use.
## Design reference: docs/design/06-magic-essence.md. All numbers are 가안 and live here or in the .tres.

const ESSENCES_DIR := "res://data/essences"
const COMBOS_DIR := "res://data/essences/combos"

## Essence workshop building (data/buildings/essence_workshop.tres). Engraving, refining (Lv2).
const FACILITY := &"essence_workshop"
const REFINE_FACILITY_LEVEL := 2
## Trait effect key (data/traits/monster_mark.tres, "마물 흔적") that marks the essence expert.
const MARK_EFFECT := &"essence_workshop_efficiency"

## Id parts: essence_<element>_<grade>. Index = Enums.Element / Enums.EssenceGrade.
const ELEMENT_KEYS: Array[String] = ["", "green", "stone", "water", "light"]
const GRADE_KEYS: Array[String] = ["low", "mid", "high"]

## Engraving cost: 1 essence + family material of the same element (by grade) + scrap.
const ENGRAVE_ESSENCE_QTY := 1
const ENGRAVE_FAMILY_QTY: Array[int] = [2, 4, 6]
const ENGRAVE_SCRAP := 5
## Removing an engraving (the essence is lost). The design gives no cost (가안: free).
const REMOVE_COST := {}
## "슬롯 열기" on a Common weapon: parts 3, scrap 10, gives 1 slot.
const OPEN_SLOT_COST := {&"parts": 3, &"scrap": 10}
const OPEN_SLOT_COUNT := 1

## Refining: 3 of the same essence -> 1 of the next grade. The essence expert needs one fewer.
const REFINE_INPUT := 3
const REFINE_MARK_DISCOUNT := 1
## Disassembling a magic weapon: each engraved essence comes back with this chance.
const DISASSEMBLE_RETURN_CHANCE := 0.5

## Two engravings of the same element: no combo, the effect x1.5 (scaling keys only).
const SAME_ELEMENT_MULT := 1.5
## Combo chance goes from ComboDef.proc_rate to proc_rate_high when the average grade >= this.
const COMBO_HIGH_AVG_GRADE := Enums.EssenceGrade.MID

const SCRAP := &"scrap"

static var _essences: Dictionary = {}
static var _combos: Dictionary = {}


# --- Definitions ---

## essence id -> EssenceDef
static func essences() -> Dictionary:
	if _essences.is_empty():
		_essences = _load_dir(ESSENCES_DIR, "EssenceDef")
	return _essences


## combo id -> ComboDef
static func combos() -> Dictionary:
	if _combos.is_empty():
		_combos = _load_dir(COMBOS_DIR, "ComboDef")
	return _combos


static func get_essence(essence_id: StringName) -> EssenceDef:
	return essences().get(essence_id)


static func is_essence(essence_id: StringName) -> bool:
	return essences().has(essence_id)


## essence_<element>_<grade>, or &"" for Element.NONE / bad values.
static func make_id(element: int, grade: int) -> StringName:
	if element <= Enums.Element.NONE or element >= ELEMENT_KEYS.size() or grade < 0 or grade >= GRADE_KEYS.size():
		return &""
	return StringName("essence_%s_%s" % [ELEMENT_KEYS[element], GRADE_KEYS[grade]])


## Every essence id, sorted.
static func list_essences() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(essences().keys())
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Combo for two different elements (any order), or null.
static func get_combo(element_a: int, element_b: int) -> ComboDef:
	if element_a == element_b:
		return null
	for id: StringName in combos():
		var combo: ComboDef = combos()[id]
		if (combo.element_a == element_a and combo.element_b == element_b) \
				or (combo.element_a == element_b and combo.element_b == element_a):
			return combo
	return null


# --- Costs ---

## {essence: 1, family material: 2/4/6, scrap: 5}. Empty for an unknown essence.
static func engrave_cost(essence_id: StringName) -> Dictionary:
	var def := get_essence(essence_id)
	if def == null:
		return {}
	var cost := {essence_id: ENGRAVE_ESSENCE_QTY}
	cost[UpgradeRules.family_material(def.element)] = ENGRAVE_FAMILY_QTY[def.grade]
	cost[SCRAP] = ENGRAVE_SCRAP
	return cost


## Essences used per refine.
static func refine_input(has_mark: bool) -> int:
	return REFINE_INPUT - (REFINE_MARK_DISCOUNT if has_mark else 0)


## Same element, next grade, or &"" at HIGH / unknown.
static func refine_output(essence_id: StringName) -> StringName:
	var def := get_essence(essence_id)
	if def == null or def.grade >= Enums.EssenceGrade.HIGH:
		return &""
	return make_id(def.element, def.grade + 1)


## Essences returned when disassembling, one roll each. Returns {id: n}.
static func roll_disassemble(essence_ids: Array, rng: RandomNumberGenerator) -> Dictionary:
	var back := {}
	for id in essence_ids:
		if rng.randf() < DISASSEMBLE_RETURN_CHANCE:
			back[StringName(id)] = back.get(StringName(id), 0) + 1
	return back


# --- Effects ---

## What a weapon with these engravings does (`by_slot`: essence id per slot, &"" = empty).
## Returns {"element": Enums.Element (first filled slot; NONE if none), "effects": Array, "combo": Dictionary or null}.
## Each effect: {"element", "essence_ids" [ids], "grade" (highest), "mult" (1.0 or SAME_ELEMENT_MULT),
## "params" {...final numbers...}}. Combo: {"id", "name", "elements" [a, b], "proc_rate", "trigger", "params"}.
static func weapon_effects(by_slot: Array) -> Dictionary:
	var defs := _filled(by_slot)
	var out := {"element": Enums.Element.NONE, "effects": [], "combo": null}
	if defs.is_empty():
		return out
	out["element"] = defs[0].element
	if defs.size() >= 2 and defs[0].element == defs[1].element:
		out["effects"] = [_merged_effect(defs[0], defs[1])]
		return out
	var effects: Array = []
	for def in defs:
		effects.append(_effect(def, [def], def.effect_params.duplicate(true), 1.0))
	out["effects"] = effects
	if defs.size() >= 2:
		var combo := get_combo(defs[0].element, defs[1].element)
		if combo != null:
			var high := (defs[0].grade + defs[1].grade) / 2.0 >= COMBO_HIGH_AVG_GRADE
			out["combo"] = {"id": combo.id, "name": combo.name, "elements": [defs[0].element, defs[1].element],
				"proc_rate": combo.proc_rate_high if high else combo.proc_rate, "trigger": combo.trigger,
				"params": combo.effect_params.duplicate(true)}
	return out


## Accessory engravings: {Enums.Element: resist ratio}, summed per element.
static func accessory_resist(by_slot: Array) -> Dictionary:
	var out := {}
	for def in _filled(by_slot):
		out[def.element] = out.get(def.element, 0.0) + def.resist_ratio
	return out


## Accessory engravings as effect entries (for listing): params {"resist_ratio"}.
static func accessory_effects(by_slot: Array) -> Array:
	var effects: Array = []
	for def in _filled(by_slot):
		effects.append(_effect(def, [def], {"resist_ratio": def.resist_ratio}, 1.0))
	return effects


## Name modifier of the main (first filled) essence, or "".
static func name_prefix(by_slot: Array) -> String:
	var defs := _filled(by_slot)
	return defs[0].name_prefix if not defs.is_empty() else ""


# --- Internals ---

static func _filled(by_slot: Array) -> Array[EssenceDef]:
	var defs: Array[EssenceDef] = []
	for id in by_slot:
		var def := get_essence(StringName(id))
		if def != null:
			defs.append(def)
	return defs


## Two of the same element: scaling keys averaged then x SAME_ELEMENT_MULT (chances capped at 1).
## With the same essence twice this is exactly "그 효과가 1.5배".
static func _merged_effect(a: EssenceDef, b: EssenceDef) -> Dictionary:
	var high := a if a.grade >= b.grade else b
	var params := high.effect_params.duplicate(true)
	for key: StringName in high.scaling_keys:
		var avg := (float(a.effect_params.get(String(key), 0.0)) + float(b.effect_params.get(String(key), 0.0))) / 2.0
		var value := avg * SAME_ELEMENT_MULT
		if String(key).ends_with("_chance"):
			value = minf(value, 1.0)
		params[String(key)] = snappedf(value, 0.0001)
	return _effect(high, [a, b], params, SAME_ELEMENT_MULT)


static func _effect(main: EssenceDef, sources: Array, params: Dictionary, mult: float) -> Dictionary:
	var ids: Array = []
	var grade := 0
	for def: EssenceDef in sources:
		ids.append(def.id)
		grade = maxi(grade, def.grade)
	return {"element": main.element, "essence_ids": ids, "grade": grade, "mult": mult, "params": params}


static func _load_dir(dir: String, type_name: String) -> Dictionary:
	var out := {}
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".tres"):
			continue
		var res := load(dir.path_join(file))
		if res == null or res.get_script() == null or res.get_script().get_global_name() != type_name \
				or StringName(res.get("id")) == &"":
			push_error("EssenceRules: %s/%s is not a %s with an id" % [dir, file, type_name])
			continue
		out[res.id] = res
	return out
