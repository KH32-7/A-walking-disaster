extends ResidentSceneScreen
## A newcomer's first words (D-13, user decision 2026-11-06: no five-step 입주 의식). Owner: Lane D.
## The rescued person thanks you and says who they are in one line, over the base, with their story,
## the one like they tell you and where they will sleep as small notes. "반가워요" (Enter) finishes
## the arrival through Colony.complete_arrival() (C-13); the bed was already given by
## Colony.add_resident (a free bed, or 임시 거처). Name, nickname and look are not chosen here.
## open_with({"resident_id": id}); without an id it takes the oldest ResidentEventFlow.welcome_queue().

const THANKS := "고마워요, 덕분에 살았어요."


func _init() -> void:
	title_text = "새 식구"
	footer_keys = [["Enter", "반가워요"], ["Esc", "나중에"]]
	header_resources = []
	dialog_layout = DialogBox.Layout.CENTER
	use_column = false  # nothing goes in the right column, so no blurred strip there


func _start() -> void:
	if resident_id == &"" or Colony.arrival_info(resident_id).is_empty():
		var waiting := ResidentEventFlow.welcome_queue()  # family children get child_naming (#125)
		resident_id = waiting[0] if not waiting.is_empty() else &""
	var r := resident()
	if resident_id == &"" or r.is_empty():
		set_subtitle("")
		dialog.say("", "맞이할 사람이 없어요. 필드에서 구한 사람이 기지에 오면 여기서 인사해요.")
		dialog.set_notes([])
		dialog.set_choices([[&"close", "닫기"]])
		return
	set_subtitle(String(r.get("name", "")))
	dialog.say(String(r.get("name", "")), intro_line(r), resident_id)
	dialog.set_notes(intro_notes(r))
	dialog.set_choices([[&"hello", "반가워요"]])


## "고마워요, 덕분에 살았어요. 저는 윤기철이에요."
static func intro_line(r: Dictionary) -> String:
	var nm := String(r.get("name", ""))
	return "%s 저는 %s%s." % [THANKS, nm, _ieyo(nm)]


## Story (narration), the first like and the bed, each as a small note under the line.
func intro_notes(r: Dictionary) -> Array:
	var notes: Array = []
	var bg := String(r.get("story", {}).get("background", ""))
	if bg != "":
		notes.append([bg, UiTokens.TEXT_ON_CREAM])
	var likes: Array = r.get("likes", [])
	if not likes.is_empty():
		notes.append(["좋아하는 것: %s" % ResidentText.tag_name(StringName(likes[0])), UiTokens.TEXT_ON_CREAM])
	var bed := StringName(r.get("bed_id", &""))
	notes.append(["잠자리: %s" % ("임시 거처, 침상이 생기면 옮겨요" if bed == &"" else "침상 배정됨"), UiTokens.TEXT_ON_CREAM_DIM])
	return notes


func _on_choice(id: StringName) -> void:
	if id != &"hello":
		close()
		return
	Colony.complete_arrival(resident_id)
	var more := ResidentEventFlow.welcome_queue()
	more.erase(resident_id)
	if more.is_empty():
		close()
		return
	resident_id = more[0]
	_start()


## 이에요 after a final consonant, 예요 after a vowel ("윤기철이에요", "서하은이에요", "이소아예요").
static func _ieyo(word: String) -> String:
	if word.is_empty():
		return "예요"
	var c := word.unicode_at(word.length() - 1)
	if c < 0xAC00 or c > 0xD7A3:
		return "이에요"
	return "이에요" if (c - 0xAC00) % 28 != 0 else "예요"
