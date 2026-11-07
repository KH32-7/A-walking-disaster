extends Node
## Autoload `Journal`. Owner: Lane A (task A-17).
## The survival journal (생존 일지): turns the day's events into one-line entries like
## "12일차. 지은이 처음으로 활짝 웃었다." and writes the ending epilogue, one or two lines per resident.
## No LLM: every line comes from the hand-written templates in ai/journal_templates/
## (schema systems/defs/journal_template.gd). Design: docs/design/15-ai-features.md
## "생존 일지와 에필로그", 13-world-narrative.md "엔딩", 14-ui-controls-accessibility.md (일지 화면).
##
## Journal listens to EventBus by itself: rescue_completed / resident_joined (rescued, joined,
## returned), resident_left, resident_died, companion_stranded, relationship_changed (friend, lover,
## spouse/married, separated), raid_resolved, sortie_ended, building_completed,
## night_event_started (only event ids that have a "night_<id>" template) and day_started
## (a quiet line for a day with no entries).
## quest_completed of a PERSONAL quest (A-13) is recorded as request_completed for its giver.
## Events without a signal call record() directly, for example:
##   Journal.record(&"prejudice_resolved", {"resident_id": who, "other_id": toward})  # C-16
##
## Lane D (일지 화면): days(), entries_for_day(day), entries_for_resident(id), people(), epilogue().
## A day holds at most MAX_ENTRIES_PER_DAY entries; a higher priority event replaces the lowest one,
## so redraw the day from entries_for_day() on journal_entry_added instead of appending.

const TEMPLATES_DIR := "res://ai/journal_templates"
## Entries kept per day (가안). Lower template priority drops first.
const MAX_ENTRIES_PER_DAY := 3
const DAY_PREFIX := "%d일차. "
const QUIET_DAY := &"quiet_day"
## Placeholder values when a name or place is unknown.
const FALLBACK_TEXT := {"name": "누군가", "other": "누군가", "building": "새 시설", "region": "바깥"}
## relationship_changed stage -> entry kind. Stage ids come from Lane C (C-14); aliases are fine.
const STAGE_KINDS := {
	&"friend": &"friend",
	&"lover": &"lover",
	&"comrade": &"comrade",
	&"spouse": &"wedding",
	&"married": &"wedding",
	&"separated": &"separated",
}
const OUTCOME_KINDS := {
	Enums.RaidOutcome.FLAWLESS: &"raid_flawless",
	Enums.RaidOutcome.WIN: &"raid_win",
	Enums.RaidOutcome.NARROW: &"raid_narrow",
	Enums.RaidOutcome.LOSS: &"raid_loss",
}
## Korean region names in lines. TODO(B): read the region's display name once data/regions has one.
const REGION_NAMES := {&"flooded_mall": "침수 상가", &"hospital": "병원"}
## Journal moments that can become a resident's second epilogue line, best first by template priority.
const HIGHLIGHTS := {
	&"wedding": &"epilogue_family",
	&"prejudice_resolved": &"epilogue_reconciled",
	&"returned": &"epilogue_returned",
	&"rescued": &"epilogue_rescued",
	&"request_completed": &"epilogue_request",
	&"lover": &"epilogue_bond",
	&"friend": &"epilogue_bond",
}
## Korean particles: either spelling -> [after a final consonant, after a vowel] (core/korean_text.gd).
const PARTICLES := KoreanText.PARTICLES

## id -> JournalTemplate
var templates: Dictionary = {}

## Entries in the order they were written:
## {"day": int, "kind": StringName, "text": String ("N일차. " + body), "body": String,
##  "residents": Array[StringName], "priority": int}
var _entries: Array = []
## Everyone the journal has met, so names survive residents leaving Colony:
## id -> {"name": String, "joined_day": int, "fate": StringName (&"", &"stranded", &"left", &"dead"),
##        "moments": [{"kind", "other", "day"}]}  (every recorded event, even ones a full day dropped)
var _people: Dictionary = {}
## Last day_started seen; a quiet line is written only for a day the journal watched end.
var _last_day := 0
## resident_joined / rescue_completed arrive in either order in the same frame; sorted out at frame end.
var _pending_joins: Array[StringName] = []
var _pending_rescues: Array = []
var _flush_queued := false
var _last_line: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_templates()
	_rng.randomize()
	SaveSystem.register_provider(&"journal", self)
	EventBus.day_started.connect(_on_day_started)
	EventBus.rescue_completed.connect(_on_rescue_completed)
	EventBus.resident_joined.connect(_on_resident_joined)
	EventBus.resident_left.connect(_on_resident_left)
	EventBus.resident_died.connect(_on_resident_died)
	EventBus.companion_stranded.connect(_on_companion_stranded)
	EventBus.relationship_changed.connect(_on_relationship_changed)
	EventBus.raid_resolved.connect(_on_raid_resolved)
	EventBus.sortie_ended.connect(_on_sortie_ended)
	EventBus.building_completed.connect(_on_building_completed)
	EventBus.night_event_started.connect(_on_night_event_started)
	EventBus.quest_completed.connect(_on_quest_completed)
	_register_debug()


## A-13: a finished personal request is a moment in the giver's story.
func _on_quest_completed(quest_id: StringName) -> void:
	var def: QuestDef = Quests.get_def(quest_id)
	if def == null or def.type != Enums.QuestType.PERSONAL:
		return
	var giver := Quests.giver_of(quest_id)
	if giver != &"":
		record(&"request_completed", {"resident_id": giver})


# --- Write API -----------------------------------------------------------------

## Writes one entry of `kind` (a template id) for today. Context fills the template's placeholders;
## "resident_id" / "other_id" look up {name} / {other} (and tie the entry to those residents),
## "day" overrides GameState.day. Returns true if the entry is in the day's list (false when the
## kind is unknown or the day is full of more important entries).
func record(kind: StringName, context: Dictionary = {}) -> bool:
	var template: JournalTemplate = templates.get(kind)
	if template == null or template.lines.is_empty():
		push_warning("Journal: unknown entry kind '%s'" % kind)
		return false
	var ctx := context.duplicate()
	var day := int(ctx.get("day", GameState.day))
	ctx["day"] = day
	var residents: Array[StringName] = []
	for pair in [["resident_id", "name"], ["other_id", "other"]]:
		var id := StringName(ctx.get(pair[0], &""))
		if id == &"":
			continue
		residents.append(id)
		if not ctx.has(pair[1]):
			ctx[pair[1]] = _name_of(id)
		_remember(id, str(ctx[pair[1]]), day)
	for i in residents.size():
		var other: StringName = residents[1 - i] if residents.size() == 2 else &""
		_people[residents[i]]["moments"].append({"kind": kind, "other": other, "day": day})
	var body := fill(_pick(template), ctx)
	return _store({
		"day": day, "kind": kind, "text": DAY_PREFIX % day + body, "body": body,
		"residents": residents, "priority": template.priority,
	})


# --- Read API (Lane D 일지 화면) ---------------------------------------------------

## Days that have entries, ascending.
func days() -> Array[int]:
	var result: Array[int] = []
	for e in _entries:
		if not int(e["day"]) in result:
			result.append(int(e["day"]))
	result.sort()
	return result


## Entries of one day (copies) in the order they happened. Format: see `_entries`.
func entries_for_day(day: int) -> Array:
	return _entries.filter(func(e): return e["day"] == day).map(func(e): return e.duplicate(true))


## Entries that name this resident, oldest first.
func entries_for_resident(resident_id: StringName) -> Array:
	return _entries.filter(func(e): return resident_id in e["residents"]).map(func(e): return e.duplicate(true))


## Every entry, oldest first.
func all_entries() -> Array:
	return _entries.duplicate(true)


## Residents the journal knows (current, stranded, gone), in the order they arrived.
func people() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in _people:
		ids.append(id)
	for id in Colony.active_resident_ids():
		if not id in ids:
			ids.append(id)
	ids.sort_custom(func(a, b): return _joined_day(a) < _joined_day(b) \
		or (_joined_day(a) == _joined_day(b) and String(a) < String(b)))
	return ids


## Name for a resident id, even after they left Colony.
func resident_name(resident_id: StringName) -> String:
	return _name_of(resident_id)


## Ending epilogue, one card per resident (13 "엔딩"):
## [{"resident_id": StringName, "name": String, "status": StringName (&"active", &"missing",
##   &"left", &"dead"), "lines": Array[String] (1-2 lines)}].
## `ending` is Enums.EndingChoice (LEAVE / STAY) or -1 before the choice. Lines are stable: the
## same journal always gives the same epilogue.
func epilogue(ending: int = -1) -> Array:
	var cards: Array = []
	for id in people():
		var status := _status_of(id)
		var joined := _joined_day(id)
		var ctx := {"name": _name_of(id), "joined": joined, "days": maxi(GameState.day - joined + 1, 1)}
		var first := StringName("epilogue_" + String(status))
		if status == &"active":
			match ending:
				Enums.EndingChoice.STAY: first = &"epilogue_stay"
				Enums.EndingChoice.LEAVE: first = &"epilogue_leave"
		var lines: Array[String] = [_stable_line(first, id, ctx)]
		var highlight := _highlight(id)
		if not highlight.is_empty():
			ctx["other"] = _name_of(highlight["other"]) if highlight["other"] != &"" else FALLBACK_TEXT["other"]
			lines.append(_stable_line(HIGHLIGHTS[highlight["kind"]], id, ctx))
		elif status == &"active":
			lines.append(_stable_line(&"epilogue_quiet", id, ctx))
		cards.append({"resident_id": id, "name": ctx["name"], "status": status, "lines": lines})
	return cards


## Fills {key} and {key|particle} placeholders. Missing keys use FALLBACK_TEXT (or "").
static func fill(template: String, context: Dictionary) -> String:
	var regex := RegEx.create_from_string("\\{(\\w+)(?:\\|([^}]+))?\\}")
	var out := ""
	var pos := 0
	for m in regex.search_all(template):
		out += template.substr(pos, m.get_start() - pos)
		var key := m.get_string(1)
		var value := str(context[key]) if context.has(key) else str(FALLBACK_TEXT.get(key, ""))
		if value == "":
			value = str(FALLBACK_TEXT.get(key, ""))
		out += value + particle(value, m.get_string(2))
		pos = m.get_end()
	return out + template.substr(pos)


## The form of a Korean particle that fits after `word` ("이" after 지은 -> "이", after 민수 -> "가").
static func particle(word: String, which: String) -> String:
	return KoreanText.particle(word, which)


# --- Signal reactions ----------------------------------------------------------

func _on_day_started(day: int) -> void:
	var ended := day - 1
	if ended >= 1 and _last_day == ended and entries_for_day(ended).is_empty():
		record(QUIET_DAY, {"day": ended})
	_last_day = day


func _on_rescue_completed(rescued: Dictionary) -> void:
	_pending_rescues.append({"id": StringName(rescued.get("id", &"")), "name": str(rescued.get("name", ""))})
	_queue_flush()


func _on_resident_joined(resident_id: StringName) -> void:
	if not resident_id in _pending_joins:
		_pending_joins.append(resident_id)
	_queue_flush()


func _on_resident_left(resident_id: StringName, _reason: StringName) -> void:
	_flush_arrivals()
	record(&"left", {"resident_id": resident_id})
	_people[resident_id]["fate"] = &"left"


func _on_resident_died(resident_id: StringName, _cause: StringName) -> void:
	_flush_arrivals()
	record(&"died", {"resident_id": resident_id})
	_people[resident_id]["fate"] = &"dead"


func _on_companion_stranded(resident_id: StringName, region_id: StringName) -> void:
	record(&"stranded", {"resident_id": resident_id, "region": _region_name(region_id)})
	_people[resident_id]["fate"] = &"stranded"


func _on_relationship_changed(a: StringName, b: StringName, stage: StringName) -> void:
	var kind: StringName = STAGE_KINDS.get(stage, &"")
	if kind != &"":
		record(kind, {"resident_id": a, "other_id": b})


func _on_raid_resolved(result: Dictionary) -> void:
	var kind: StringName = OUTCOME_KINDS.get(int(result.get("outcome", -1)), &"")
	if kind != &"":
		record(kind)


func _on_sortie_ended(result: Dictionary) -> void:
	var region := _region_name(StringName(result.get("region_id", &"")))
	if bool(result.get("downed", false)):
		record(&"sortie_downed", {"region": region})
	elif bool(result.get("extracted", false)) and Array(result.get("rescued", [])).is_empty():
		# A sortie that brought someone home is already in the journal as a rescue.
		record(&"sortie_extracted", {"region": region})


func _on_building_completed(building_uid: StringName) -> void:
	record(&"building_completed", {"building": _building_name(building_uid)})


func _on_night_event_started(event_id: StringName, participants: Array) -> void:
	var kind := StringName("night_" + String(event_id))
	if not templates.has(kind):
		return
	var ctx := {}
	if participants.size() > 0:
		ctx["resident_id"] = StringName(participants[0])
	if participants.size() > 1:
		ctx["other_id"] = StringName(participants[1])
	record(kind, ctx)


# --- Save provider "journal" ---------------------------------------------------

func save_data() -> Dictionary:
	_flush_arrivals()
	return {"entries": _entries.duplicate(true), "people": _people.duplicate(true), "last_day": _last_day}


## Accepts data straight from save_data() or after a JSON round trip; {} is a new journal.
func load_data(data: Dictionary) -> void:
	_pending_joins.clear()
	_pending_rescues.clear()
	_entries = []
	for e: Dictionary in data.get("entries", []):
		var residents: Array[StringName] = []
		for id in e.get("residents", []):
			residents.append(StringName(id))
		_entries.append({
			"day": int(e.get("day", 1)), "kind": StringName(e.get("kind", &"")),
			"text": str(e.get("text", "")), "body": str(e.get("body", "")),
			"residents": residents, "priority": int(e.get("priority", 0)),
		})
	_people = {}
	var saved_people: Dictionary = data.get("people", {})
	for key in saved_people:
		var p: Dictionary = saved_people[key]
		var moments: Array = []
		for m: Dictionary in p.get("moments", []):
			moments.append({"kind": StringName(m.get("kind", &"")), "other": StringName(m.get("other", &"")),
				"day": int(m.get("day", 0))})
		_people[StringName(key)] = {
			"name": str(p.get("name", "")), "joined_day": int(p.get("joined_day", 1)),
			"fate": StringName(p.get("fate", &"")), "moments": moments,
		}
	_last_day = int(data.get("last_day", 0))


# --- Internals -----------------------------------------------------------------

func _store(entry: Dictionary) -> bool:
	var day: int = entry["day"]
	# A quiet-day line gives way to anything that really happened that day.
	if entry["kind"] != QUIET_DAY:
		_entries = _entries.filter(func(e): return not (e["day"] == day and e["kind"] == QUIET_DAY))
	var lowest := -1
	var count := 0
	for i in _entries.size():
		if _entries[i]["day"] != day:
			continue
		count += 1
		if lowest < 0 or _entries[i]["priority"] < _entries[lowest]["priority"]:
			lowest = i
	if count >= MAX_ENTRIES_PER_DAY:
		if entry["priority"] <= _entries[lowest]["priority"]:
			return false
		_entries.remove_at(lowest)
	_entries.append(entry)
	EventBus.journal_entry_added.emit(day, entry["text"])
	return true


func _queue_flush() -> void:
	if not _flush_queued:
		_flush_queued = true
		_flush_arrivals.call_deferred()


## Turns this frame's resident_joined / rescue_completed into rescued, returned or joined entries.
func _flush_arrivals() -> void:
	_flush_queued = false
	var joins := _pending_joins.duplicate()
	var rescues := _pending_rescues.duplicate()
	_pending_joins.clear()
	_pending_rescues.clear()
	for id: StringName in joins:
		var name := _name_of(id)
		var kind := &"joined"
		if _people.has(id) and _people[id]["fate"] == &"stranded":
			kind = &"returned"
		for i in rescues.size():
			if rescues[i]["id"] == id or (rescues[i]["name"] != "" and rescues[i]["name"] == name):
				rescues.remove_at(i)
				if kind == &"joined":
					kind = &"rescued"
				break
		_remember(id, name, GameState.day)
		_people[id]["fate"] = &""
		record(kind, {"resident_id": id, "name": name})
	# A rescue nobody turned into a resident (no Colony in a sandbox) still goes in the journal.
	for r: Dictionary in rescues:
		if r["id"] != &"":
			record(&"rescued", {"resident_id": r["id"], "name": r["name"] if r["name"] != "" else _name_of(r["id"])})
		else:
			record(&"rescued", {"name": r["name"]})


func _remember(id: StringName, name: String, day: int) -> void:
	if not _people.has(id):
		_people[id] = {"name": "", "joined_day": day, "fate": &"", "moments": []}
	if name != "" and name != FALLBACK_TEXT["name"]:
		_people[id]["name"] = name


func _name_of(id: StringName) -> String:
	var name := str(Colony.get_resident(id).get("name", ""))
	if name == "" and _people.has(id):
		name = _people[id]["name"]
	return name if name != "" else FALLBACK_TEXT["name"]


func _joined_day(id: StringName) -> int:
	if _people.has(id):
		return int(_people[id]["joined_day"])
	return int(Colony.get_resident(id).get("joined_day", 1))


func _status_of(id: StringName) -> StringName:
	var r := Colony.get_resident(id)
	if not r.is_empty():
		match int(r.get("status", Enums.ResidentStatus.ACTIVE)):
			Enums.ResidentStatus.DEAD: return &"dead"
			Enums.ResidentStatus.STRANDED, Enums.ResidentStatus.MISSING: return &"missing"
		return &"active"
	match StringName(_people.get(id, {}).get("fate", &"")):
		&"dead": return &"dead"
		&"left": return &"left"
		&"stranded": return &"missing"
	return &"active"


## The resident's most important journal moment that has an epilogue line, {} if none.
func _highlight(id: StringName) -> Dictionary:
	var best: Dictionary = {}
	var best_priority := -1
	for m: Dictionary in _people.get(id, {}).get("moments", []):
		var template: JournalTemplate = templates.get(m["kind"])
		if HIGHLIGHTS.has(m["kind"]) and template != null and template.priority > best_priority:
			best = m
			best_priority = template.priority
	return best


func _pick(template: JournalTemplate) -> String:
	var count := template.lines.size()
	var index := _rng.randi_range(0, count - 1)
	if count > 1 and index == _last_line.get(template.id, -1):
		index = (index + 1 + _rng.randi_range(0, count - 2)) % count
	_last_line[template.id] = index
	return template.lines[index]


func _stable_line(template_id: StringName, resident_id: StringName, ctx: Dictionary) -> String:
	var template: JournalTemplate = templates.get(template_id)
	if template == null or template.lines.is_empty():
		push_warning("Journal: missing epilogue template '%s'" % template_id)
		return ""
	var index := absi(hash(String(resident_id) + ":" + String(template_id))) % template.lines.size()
	return fill(template.lines[index], ctx)


func _region_name(region_id: StringName) -> String:
	return REGION_NAMES.get(region_id, FALLBACK_TEXT["region"])


func _building_name(uid: StringName) -> String:
	var building: Dictionary = Colony.get_building(uid) if Colony.has_method(&"get_building") else {}
	var def: BuildingDef = null
	if not building.is_empty():
		def = BaseDB.get_building(StringName(building.get("def_id", &"")))
	return def.display_name if def != null and def.display_name != "" else FALLBACK_TEXT["building"]


func _load_templates() -> void:
	templates.clear()
	for file in ResourceLoader.list_directory(TEMPLATES_DIR):
		if file.ends_with(".tres"):
			var template := load(TEMPLATES_DIR.path_join(file)) as JournalTemplate
			if template == null or template.id == &"":
				push_error("Journal: %s is not a JournalTemplate with an id" % file)
				continue
			templates[template.id] = template


# --- Debug console ---------------------------------------------------------------

func _register_debug() -> void:
	DebugConsole.register(&"journal", _cmd_journal,
		"journal [day N | add <kind> [resident_id] [other_id] | epilogue [stay|leave]] - 생존 일지")


func _cmd_journal(args: PackedStringArray) -> String:
	var sub := args[0] if args.size() > 0 else "day"
	match sub:
		"add":
			if args.size() < 2:
				return "usage: journal add <kind> [resident_id] [other_id]"
			var ctx := {}
			if args.size() > 2:
				ctx["resident_id"] = StringName(args[2])
			if args.size() > 3:
				ctx["other_id"] = StringName(args[3])
			return "added" if record(StringName(args[1]), ctx) else "not added (unknown kind or day full)"
		"epilogue":
			var ending := -1
			if args.size() > 1:
				ending = Enums.EndingChoice.LEAVE if args[1] == "leave" else Enums.EndingChoice.STAY
			var out := PackedStringArray()
			for card: Dictionary in epilogue(ending):
				out.append("%s: %s" % [card["name"], " ".join(card["lines"])])
			return "\n".join(out) if not out.is_empty() else "(no residents)"
		_:
			var day := int(args[1]) if sub == "day" and args.size() > 1 else GameState.day
			var out := PackedStringArray()
			for e: Dictionary in entries_for_day(day):
				out.append(e["text"])
			return "\n".join(out) if not out.is_empty() else "(%d일차 기록 없음)" % day
