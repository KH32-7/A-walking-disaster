class_name ResidentTemplate
extends Resource
## One hand-written survivor in the rescue pool. Owner: Lane A (task A-16).
## Data: data/resident_pool/<id>.tres. Runtime access: the `ResidentPool` autoload.
## Design reference: docs/design/07-residents.md "데이터 정의", 15-ai-features.md "생존자 생성",
## "검수 규칙" (the team writes these by hand - no LLM).
##
## to_profile() returns the same Dictionary shape Lane C's Colony.add_resident(profile) takes
## (see base/residents/resident_data.gd). Fields left empty here (stats, class_aptitude) are
## rolled by ResidentData.create().
##
## Only entries with `reviewed = true` reach the game. A person on the team reads every text
## field against the review rules before flipping it; validate() only catches what a machine can.

## Lowercase snake case, same as the file name. Becomes the resident id when it joins.
@export var id: StringName
## Fictional name. Never a real person.
@export var name: String
## Optional starting nickname (the player can rename at the 입주 의식).
@export var nickname: String
@export var age_stage: Enums.AgeStage = Enums.AgeStage.ADULT
## A key of ResidentData.FORMER_JOB_MAIN_STAT (decides the main stat).
@export var former_job: StringName = &"laborer"
## Exactly two TraitDef ids from data/traits, not exclusive with each other.
@export var traits: Array[StringName] = []
## Two ids each (lowercase snake case).
@export var likes: Array[StringName] = []
@export var dislikes: Array[StringName] = []
## Enums.AccessNeed values (참여 조건).
@export var access_needs: Array[int] = []
## &"female" / &"male" (ResidentData.GENDERS). &"" = rolled 50/50 when the person joins (C-15).
@export var gender: StringName
## 출신 태그, lowercase snake case (e.g. &"migrant"). Not traits: a background that opens
## B-20 hidden routes (07 "출신은 특성이 아니라 사연", issue #107).
@export var origin_tags: Array[StringName] = []
## Optional partial stats {&"str"|&"dex"|&"sense"|&"heart": 1..10}. Missing ones are rolled.
@export var stats: Dictionary = {}
## Optional partial aptitude {&"gun"|&"blade"|&"blunt": Enums.Aptitude}. Missing ones are rolled.
@export var class_aptitude: Dictionary = {}

@export_group("Story")
## 사연 요약, 200 characters max.
@export_multiline var background: String
## Two story fragments revealed at trust 20 and 60, 150 characters max each.
@export var fragments: Array[String] = []
## What this person brings to the base (기여), one line, 60 characters max.
## The review rule "필요와 기여가 함께 드러남" - needs come from access_needs and the story.
@export var contribution: String
## First line when found, 40 characters max.
@export var first_line: String
## Three lines spoken while escorted, 40 characters max each.
@export var rescue_lines: Array[String] = []
## Where they are found, for the rescue scene / radio rumour ("멈춘 고층 승강기 안").
@export var situation: String

@export_group("Signature")
## 고유 스킬 (07 신뢰도 "동행 시 고유 스킬"). As a companion it replaces the class Q:
## any weapon, no 적성 rule. null = class Q as usual. FieldCompanion reads it from ResidentPool.
@export var signature_skill: SkillDef
## Said in a bubble right after the signature skill, 40 characters max.
@export var signature_line: String

@export_group("Pool")
## Region id where this person can be found. &"" = any region.
@export var region_id: StringName
## One of the three demo survivors (docs/design/12 "데모 30분 흐름").
@export var demo := false
## Set by a person after reading every text field against the review rules.
@export var reviewed := false

const BANNED_WORDS_PATH := "res://tools/resident_banned_words.txt"
## Age stages a survivor can have (babies are born in the base, never rescued).
const AGE_STAGES: Array[int] = [Enums.AgeStage.CHILD, Enums.AgeStage.TEEN, Enums.AgeStage.ADULT, Enums.AgeStage.ELDER]
const TRAIT_COUNT := 2
const LIKE_COUNT := 2
const FRAGMENT_COUNT := 2
const RESCUE_LINE_COUNT := 3
## Text limits in characters (15 "생존자 생성" 출력 필드 표).
const NAME_MAX := 10
const NICKNAME_MAX := 6
const BACKGROUND_MAX := 200
const FRAGMENT_MAX := 150
const LINE_MAX := 40
const CONTRIBUTION_MAX := 60
const SITUATION_MAX := 40

static var _snake := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


## The profile Dictionary for Colony.add_resident(). A fresh deep copy every call.
## Keys Colony does not know (contribution, first_line, rescue_lines, situation) are ignored by
## ResidentData.create() but let the rescue scene and UI show the survivor's lines.
func to_profile() -> Dictionary:
	var p := {
		"id": id,
		"name": name,
		"age_stage": age_stage,
		"former_job": former_job,
		"traits": traits.duplicate(),
		"likes": likes.duplicate(),
		"dislikes": dislikes.duplicate(),
		"access_needs": access_needs.duplicate(),
		"origin_tags": origin_tags.duplicate(),
		"story": {
			"background": background,
			"fragments": fragments.duplicate(),
			"requests": [],
		},
		"contribution": contribution,
		"first_line": first_line,
		"rescue_lines": rescue_lines.duplicate(),
		"situation": situation,
	}
	if nickname != "":
		p["nickname"] = nickname
	if gender != &"":
		p["gender"] = gender
	if not stats.is_empty():
		p["stats"] = stats.duplicate()
	if not class_aptitude.is_empty():
		p["class_aptitude"] = class_aptitude.duplicate()
	return p


## Every text field a reviewer has to read, in display order.
func texts() -> PackedStringArray:
	var out := PackedStringArray([name, nickname, background, contribution, first_line, situation])
	out.append_array(PackedStringArray(fragments))
	out.append_array(PackedStringArray(rescue_lines))
	if signature_line != "":
		out.append(signature_line)
	return out


## Machine-checkable review rules. Empty result = valid. `banned` comes from
## load_banned_words(); an empty list skips the word check (exported builds have no tools/).
func validate(banned: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var errors := PackedStringArray()
	if not _snake.search(String(id)):
		errors.append("id '%s' is not lowercase snake case" % id)
	_check_text(errors, "name", name, NAME_MAX, true)
	_check_text(errors, "nickname", nickname, NICKNAME_MAX, false)
	if int(age_stage) not in AGE_STAGES:
		errors.append("age_stage %d is not CHILD/TEEN/ADULT/ELDER" % age_stage)
	if not ResidentData.FORMER_JOB_MAIN_STAT.has(former_job):
		errors.append("former_job '%s' is not in ResidentData.FORMER_JOB_MAIN_STAT" % former_job)

	if traits.size() != TRAIT_COUNT:
		errors.append("traits: %d given, need %d" % [traits.size(), TRAIT_COUNT])
	for t in traits:
		if BaseDB.get_trait(t) == null:
			errors.append("trait '%s' is not in data/traits" % t)
	if traits.size() == 2 and (traits[0] == traits[1] or ResidentData.traits_conflict(traits[0], traits[1])):
		errors.append("traits %s are the same or exclusive" % [traits])

	for field in ["likes", "dislikes"]:
		var values: Array[StringName] = get(field)
		if values.size() != LIKE_COUNT:
			errors.append("%s: %d given, need %d" % [field, values.size(), LIKE_COUNT])
		for v in values:
			if not _snake.search(String(v)):
				errors.append("%s id '%s' is not lowercase snake case" % [field, v])
	for v in likes:
		if v in dislikes:
			errors.append("'%s' is both liked and disliked" % v)

	var seen_needs := {}
	for n in access_needs:
		if n < 0 or n >= Enums.AccessNeed.size():
			errors.append("access_needs value %d is not an Enums.AccessNeed" % n)
		elif seen_needs.has(n):
			errors.append("access_needs repeats %d" % n)
		seen_needs[n] = true

	for key in stats:
		if StringName(key) not in ResidentData.STAT_KEYS:
			errors.append("stats key '%s' is not one of %s" % [key, ResidentData.STAT_KEYS])
		elif not (stats[key] is int) or stats[key] < ResidentData.STAT_MIN or stats[key] > ResidentData.STAT_MAX:
			errors.append("stats %s = %s is not an int in %d..%d" % [key, stats[key], ResidentData.STAT_MIN, ResidentData.STAT_MAX])
	for key in class_aptitude:
		if StringName(key) not in ResidentData.CLASS_KEYS:
			errors.append("class_aptitude key '%s' is not one of %s" % [key, ResidentData.CLASS_KEYS])
		elif not (class_aptitude[key] is int) or class_aptitude[key] < 0 or class_aptitude[key] >= Enums.Aptitude.size():
			errors.append("class_aptitude %s = %s is not an Enums.Aptitude" % [key, class_aptitude[key]])

	_check_text(errors, "background", background, BACKGROUND_MAX, true)
	_check_text(errors, "contribution", contribution, CONTRIBUTION_MAX, true)
	_check_text(errors, "first_line", first_line, LINE_MAX, true)
	_check_text(errors, "situation", situation, SITUATION_MAX, false)
	if fragments.size() != FRAGMENT_COUNT:
		errors.append("fragments: %d given, need %d" % [fragments.size(), FRAGMENT_COUNT])
	for i in fragments.size():
		_check_text(errors, "fragments[%d]" % i, fragments[i], FRAGMENT_MAX, true)
	if rescue_lines.size() != RESCUE_LINE_COUNT:
		errors.append("rescue_lines: %d given, need %d" % [rescue_lines.size(), RESCUE_LINE_COUNT])
	for i in rescue_lines.size():
		_check_text(errors, "rescue_lines[%d]" % i, rescue_lines[i], LINE_MAX, true)
	if gender != &"" and gender not in ResidentData.GENDERS:
		errors.append("gender '%s' is not one of %s" % [gender, ResidentData.GENDERS])
	for tag in origin_tags:
		if not _snake.search(String(tag)):
			errors.append("origin_tags '%s' is not lowercase snake case" % tag)
	if region_id != &"" and not _snake.search(String(region_id)):
		errors.append("region_id '%s' is not lowercase snake case" % region_id)
	if signature_skill != null:
		if signature_skill.id not in CompanionSkill.RUNNERS:
			errors.append("signature_skill id '%s' is not one of %s" % [signature_skill.id, CompanionSkill.RUNNERS])
		_check_text(errors, "signature_line", signature_line, LINE_MAX, true)
	elif signature_line != "":
		errors.append("signature_line without a signature_skill")

	for word in find_banned_words(banned):
		errors.append("banned word '%s'" % word)
	return errors


## Banned words that appear in any text field (case-insensitive substring match).
func find_banned_words(banned: PackedStringArray) -> PackedStringArray:
	var found := PackedStringArray()
	var all := "\n".join(texts()).to_lower()
	for word in banned:
		if all.contains(word.to_lower()) and word not in found:
			found.append(word)
	return found


## One word or phrase per line; blank lines and lines starting with # are skipped.
## Returns an empty list if the file is missing (exported builds).
static func load_banned_words(path: String = BANNED_WORDS_PATH) -> PackedStringArray:
	var words := PackedStringArray()
	if not FileAccess.file_exists(path):
		return words
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw.strip_edges()
		if line != "" and not line.begins_with("#"):
			words.append(line)
	return words


static func _check_text(errors: PackedStringArray, field: String, value: String, max_len: int, required: bool) -> void:
	if required and value.strip_edges() == "":
		errors.append("%s is empty" % field)
	elif value.length() > max_len:
		errors.append("%s is %d characters (max %d)" % [field, value.length(), max_len])
