class_name ItemInfo
## Turns a bag entry / item uid / resource id into display data (name, rarity, size, tooltip info).
## Reads Armory / Economy only; computes no rules. Owner: Lane D.

const SLOT_NAMES := ["주무기", "보조", "머리", "몸", "다리", "장신구", "가방"]
const CLASS_NAMES := ["총", "칼", "둔기"]
const STAT_NAMES := {"damage": "공격력", "attack_interval": "공격 간격", "range": "사거리", "noise": "소음",
	"magazine": "탄창", "defense": "방어", "noise_mod": "이동 소음", "max_hp": "최대 체력",
	"crit_pctp": "치명", "stamina_pct": "스태미나"}


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
	return {"name": name, "rarity": 0, "kind": &"resource", "tooltip": {"title": name, "rarity": -1,
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
	return {"name": name, "rarity": int(it.rarity), "kind": &"item", "slot": int(def.slot) if def else -1,
		"tooltip": {"title": name, "rarity": int(it.rarity), "tags": tags, "desc": "", "stats": rows,
			"foot": ["%d×%d칸" % [def.size.x, def.size.y] if def else "", "강화 +%d" % it.upgrade_level],
			"action": "비교: 장착 중" if compare_with != &"" else ""}}


static func _fmt(k: String, v: float) -> String:
	match k:
		"attack_interval":
			return "%.2f초" % v
		"noise", "noise_mod", "range":
			return "%.1fm" % v
		"crit_pctp", "stamina_pct":
			return "%+d%%" % roundi(v)
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
