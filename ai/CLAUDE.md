# ai/ — 레인 A 소유

Radio(무전 트리거·템플릿 문장, A-14)와 Journal(생존 일지·엔딩 에필로그, A-17). 폴더 이름은 기획의 "AI 무전병"에서 왔다.
- 무전 문장은 data/radio/*.tres(RadioTrigger, 스키마 systems/defs/radio_trigger.gd).
- 일지 문장은 ai/journal_templates/*.tres(JournalTemplate, 스키마 systems/defs/journal_template.gd). 조사는 `{name|이}`처럼 중괄호 안에 쓴다.
- **LLM·생성형 AI는 쓰지 않는다** (팀 결정). 무전·일지 문장은 전부 손으로 쓴 템플릿에서 나온다.
- 문장은 기획 15 "검수 규칙"을 지킨다(비하·동정·영웅화·고정관념·잔혹 묘사 금지). tests/core/test_journal.gd가 금지어를 검사한다.
- API 키나 외부 서비스 호출을 추가하지 않는다. 수치는 문장 시스템이 정하지 않는다.
작업 목록: docs/dev/lane-a-core.md, 기획: docs/design/15-ai-features.md (LLM 부분은 적용하지 않음)
