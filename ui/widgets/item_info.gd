class_name ItemInfo
## Turns a bag entry / item uid / resource id into display data (name, rarity, size, tooltip info).
## Reads Armory / Economy only; computes no rules. Owner: Lane D.

const SLOT_NAMES := ["주무기", "보조", "머리", "몸", "다리", "장신구", "가방"]
const CLASS_NAMES := ["총", "칼", "둔기"]
const STAT_NAMES := {"damage": "공격력", "attack_interval": "공격 간격", "range": "사거리", "noise": "소음",
	"magazine": "탄창", "defense": "방어", "noise_mod": "이동 소음", "max_hp": "최대 체력",
	"crit_pctp": "치명", "stamina_pct": "스태미나"}
const ICON_DIR := "res://art/icons/items/"

static var _icons: Dictionary = {}


## Icon for a data id (item def id, resource id, essence id). null = no art yet, callers draw text.
static func icon(id: StringName) -> Texture2D:
	if not _icons.has(id):
		var path := ICON_DIR + String(id) + ".png"
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


static func for_entry(e: Dictionary) -> Dictionary:
	if StringName(e.get("kind", &"")) == &"item":
		var d := for_item(StringName(e.ref))
		d["count"] = 1
		return d
	var d := for_resource(StringName(e.get("ref", &"")))
	d["count"] = int(e.get("amount", 1))
	return d


static func for_resource(id: StringName) -> Dictionary:
	var def: Variant = Economy.get_def(id)
	var name := String(def.name) if def != null else String(id)
	var cat := ["기본 자원", "가공 자원", "필드 자원", "마물 자원", "특수 자원"]
	var tag: String = cat[clampi(int(def.category), 0, 4)] if def != null else "소모품"
	return {"name": name, "rarity": 0, "kind": &"resource", "icon": id, "tooltip": {"title": name, "rarity": -1,
		"tags": [tag], "desc": "", "stats": [["창고 보유", str(Economy.get_amount(id))]]}}


static func for_item(uid: StringName, compare_with: StringName = &"") -> Dictionary:
	var it: ItemInstance = Armory.get_item(uid)
	if it == null:
		return {"name": String(uid), "rarity": 0, "kind": &"item", "tooltip": {"title": String(uid)}}
	var def: ItemDef = Armory.get_def(it.def_id)
	var name := def.name if def != null else String(it.def_id)
	if it.upgrade_level > 0:
		name += " +%d" % it.upgrade_level
	var stats: Dictionary = Armory.get_item_stats(uid)
	var other: Dictionary = Armory.get_item_stats(compare_with) if compare_with != &"" else {}
	var rows := []
	for k: String in STAT_NAMES:
		if not stats.has(k) or typeof(stats[k]) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var v := float(stats[k])
		if is_zero_approx(v) and k in ["magazine", "range", "noise_mod", "defense"]:
			continue
		var mark := ""
		if other.has(k) and typeof(other[k]) in [TYPE_INT, TYPE_FLOAT]:
			var o := float(other[k])
			var better := v < o if k in ["attack_interval", "noise", "noise_mod"] else v > o
			if not is_equal_approx(v, o):
				mark = "up" if better else "dn"
		rows.append([STAT_NAMES[k], _fmt(k, v), mark])
	rows.append(["내구도", "%d/%d" % [roundi(it.durability), roundi(def.durability_max if def else 100.0)], ""])
	var tags := [SLOT_NAMES[clampi(int(def.slot), 0, 6)] if def else "장비"]
	if def != null and int(def.slot) <= Enums.EquipSlot.SUB:
		tags.append(CLASS_NAMES[clampi(int(def.combat_class), 0, 2)])
	return {"name": name, "rarity": int(it.rarity), "kind": &"item", "icon": it.def_id, "slot": int(def.slot) if def else -1,
		"tooltip": {"title": name, "rarity": int(it.rarity), "tags": tags, "desc": "", "stats": rows,
			"foot": ["%d×%d칸" % [def.size.x, def.size.y] if def else "", "강화 +%d" % it.upgrade_level],
			"action": "비교: 장착 중" if compare_with != &"" else ""}}


## Before/after rows for the craft screen (D-12): [[label, before, after, "up"|"dn"|""]].
## Both are Armory.get_item_stats()-shaped. `after` empty = only the current values.
## Lower is better for attack_interval / noise / noise_mod. Also the durability and the
## essence parts (display name, attack element, combo) when they change.
static func compare_rows(before: Dictionary, after: Dictionary) -> Array:
	var rows := []
	var other := after if not after.is_empty() else before
	if String(before.get("display_name", "")) != String(other.get("display_name", "")):
		rows.append(["이름", String(before.get("display_name", "")), String(other.get("display_name", "")), ""])
	for k: String in STAT_NAMES:
		var a: Variant = before.get(k)
		var b: Variant = other.get(k)
		if typeof(a) not in [TYPE_INT, TYPE_FLOAT] and typeof(b) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var va := float(a) if typeof(a) in [TYPE_INT, TYPE_FLOAT] else 0.0
		var vb := float(b) if typeof(b) in [TYPE_INT, TYPE_FLOAT] else 0.0
		if is_zero_approx(va) and is_zero_approx(vb) and k in ["magazine", "range", "noise_mod", "defense"]:
			continue
		var mark := ""
		if not is_equal_approx(va, vb):
			var better := vb < va if k in ["attack_interval", "noise", "noise_mod"] else vb > va
			mark = "up" if better else "dn"
		rows.append([STAT_NAMES[k], _fmt(k, va), _fmt(k, vb), mark])
	if before.has("durability"):
		var da := float(before["durability"])
		var db := float(other.get("durability", da))
		rows.append(["내구도", str(roundi(da)), str(roundi(db)), "up" if db > da + 0.01 else ""])
	var ea := int(before.get("element", 0))
	var eb := int(other.get("element", 0))
	if ea != 0 or eb != 0:
		rows.append(["공격 속성", UiTokens.ELEMENT_NAMES[clampi(ea, 0, 4)], UiTokens.ELEMENT_NAMES[clampi(eb, 0, 4)],
			"up" if ea != eb and eb != 0 else ""])
	var ca: Variant = before.get("combo")
	var cb: Variant = other.get("combo")
	if ca is Dictionary or cb is Dictionary:
		var na := String((ca as Dictionary).get("name", "")) if ca is Dictionary else "없음"
		var nb := String((cb as Dictionary).get("name", "")) if cb is Dictionary else "없음"
		rows.append(["조합", na, nb, "up" if na != nb and cb is Dictionary else ""])
	var ra: Dictionary = before.get("element_resist", {})
	var rb: Dictionary = other.get("element_resist", {})
	if not ra.is_empty() or not rb.is_empty():
		var sa := _resist_text(ra)
		var sb := _resist_text(rb)
		rows.append(["속성 저항", sa, sb, "up" if sa != sb and not rb.is_empty() else ""])
	return rows


## Essence effects of a weapon / accessory for display (D-12): [[element, text], ...].
## Reads Armory.get_item_stats()["essence_effects"] (A-10, numbers are already final).
static func essence_lines(stats: Dictionary) -> Array:
	var out := []
	for e: Dictionary in stats.get("essence_effects", []):
		var p: Dictionary = e.get("params", {})
		var parts: PackedStringArray = []
		if p.has("resist_ratio"):
			parts.append("%s 피해 저항 %d%%" % [UiTokens.ELEMENT_NAMES[clampi(int(e.get("element", 0)), 0, 4)],
				_pct(p["resist_ratio"])])
		if p.has("root_chance"):
			parts.append("속박 %d%% / %s초" % [_pct(p["root_chance"]), _num(p.get("root_sec", 0.0))])
		if p.has("lifesteal_ratio"):
			parts.append("흡수 %d%%" % _pct(p["lifesteal_ratio"]))
		if p.has("stagger_bonus"):
			parts.append("경직 +%d%%" % _pct(p["stagger_bonus"]))
		if p.has("guard_break_chance"):
			parts.append("방어 파괴 %d%%" % _pct(p["guard_break_chance"]))
		if p.has("slow_chance") or p.has("slow_ratio"):
			var slow := "둔화 %s초" % _num(p.get("slow_sec", 0.0))
			if p.has("slow_chance"):
				slow = "둔화 %d%% / %s초" % [_pct(p["slow_chance"]), _num(p.get("slow_sec", 0.0))]
			if p.has("slow_ratio"):
				slow += " / 이동 −%d%%" % _pct(p["slow_ratio"])
			parts.append(slow)
		if p.has("wet_sec"):
			parts.append("젖음 %s초 (빛 피해 +%d%%)" % [_num(p["wet_sec"]), _pct(p.get("wet_light_bonus", 0.0))])
		if p.has("chain_chance"):
			parts.append("감전 %d%% / %d마리에게 %d%%" % [_pct(p["chain_chance"]), int(p.get("chain_targets", 0)),
				_pct(p.get("chain_damage_ratio", 0.0))])
		var text := ", ".join(parts)
		if float(e.get("mult", 1.0)) > 1.0:
			text += "  (같은 정수 ×%s)" % _num(e["mult"])
		out.append([int(e.get("element", 0)), text])
	return out


static func _pct(v: Variant) -> int:
	return roundi(float(v) * 100.0)


static func _num(v: Variant) -> String:
	var f := float(v)
	return str(roundi(f)) if is_equal_approx(f, roundf(f)) else "%.1f" % f


static func _resist_text(resist: Dictionary) -> String:
	if resist.is_empty():
		return "없음"
	var parts: PackedStringArray = []
	for e: int in resist:
		parts.append("%s %d%%" % [UiTokens.ELEMENT_NAMES[clampi(e, 0, 4)], roundi(float(resist[e]) * 100.0)])
	return " / ".join(parts)


static func _fmt(k: String, v: float) -> String:
	match k:
		"attack_interval":
			return "%.2f초" % v
		"noise", "noise_mod", "range":
			return "%.1fm" % v
		"crit_pctp", "stamina_pct":
			return "%+d%%" % roundi(v)
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
