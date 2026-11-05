extends SettingsScreen
## "접근성 빠른 설정" on the title (D-15). Owner: Lane D. D-19's title opens it with
## UI.open(&"accessibility_quick"). Design 14: subtitles, sound visualisation, colour, toggles and
## protect mode on one screen, plus text size / contrast / shake / flash / menu reading.
## Same rows, card and preview as the full settings screen (SettingsScreen, quick = true).
## Protect mode = the story preset; it is picked before a new game, so hardcore may be left.
## open_with({"new_game": false}) when opened from inside a game.


func _init() -> void:
	super()
	quick = true
	new_game = true
	title_text = "접근성 빠른 설정"
	subtitle_text = "언제든 설정에서 다시 바꿀 수 있어요"
	footer_keys = [["Esc", "닫기"], ["← / →", "값 바꾸기"], ["Enter", "선택"], ["Backspace", "기본값"]]
