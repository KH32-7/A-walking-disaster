# 레인 A — 코어·시스템·AI

하루 흐름, 저장, 자원·아이템·장비 백엔드, 강화·각인 계산, 퀘스트, 무전(템플릿), 통합을 맡는다.
**LLM·생성형 AI는 쓰지 않는다**(팀 결정). A-15는 제외, A-16·A-17은 손으로 쓴 데이터·템플릿으로 대체한다.
다른 세 레인이 기대는 기반이라 **M0 태스크를 가장 먼저** 끝낸다.

- 소유: `core/`, `systems/`, `ai/`, `tools/`, `project.godot`, `main.tscn`, `data/{items,recipes,resources,essences,quests,radio,resident_pool}/`, `tests/core/`, `tests/run_tests.gd`, `docs/dev/`, `docs/design/`, `.github/`
- 이미 있는 뼈대: 오토로드 9개(`EventBus`, `Settings`, `GameState`, `InputSetup`, `SaveSystem`, `Economy`, `Armory`, `Radio`, `SceneRouter`), `Enums`

## 체크리스트

- [ ] **A-01** 계약 관리 (EventBus·Enums·contracts.md) · M0
- [ ] **A-02** 헤드리스 검사 + GitHub Actions + CODEOWNERS · M0
- [ ] **A-03** 디버그 콘솔 (치트) · M0
- [x] **A-04** 저장 시스템 · M1
- [x] **A-05** main.tscn + SceneRouter + 하루 흐름 상태 머신 · M1
- [x] **A-06** Economy (자원 정의·창고 한도·소비) · M1
- [x] **A-07** 아이템·장비 체계 (Armory) · M1
- [x] **A-08** 가방 격자 인벤토리 백엔드 · M1
- [x] **A-12** Settings 저장 + 난이도 프리셋 · M1
- [x] **A-14** Radio 디렉터 (트리거·템플릿, 오프라인) · M1
- [ ] **A-09** 강화·수리·제작 로직 + 레시피 · M2
- [ ] **A-10** 정수·각인·조합·정제 계산 · M2
- [ ] **A-11** 경험치·레벨·특기 · M2
- [ ] **A-13** 퀘스트·스토리 플래그 + 개인 요청 · M2
- [x] ~~**A-15** LLM 클라이언트 + 키 보관 프록시~~ · 제외 (LLM 미사용)
- [ ] **A-16** 생존자 풀 (손으로 작성) + 스키마 검증 · M2
- [ ] **A-17** 생존 일지 + 엔딩 에필로그 · M2
- [ ] **A-18** 교역 (무리 3곳) · M3

---

### A-01 계약 관리 · M0
- 만들 것: `core/event_bus.gd`, `core/enums.gd`, `docs/dev/contracts.md` 검토·보완. 다른 레인 요청 이슈 처리.
- 완료 조건: B·C·D가 첫 태스크를 시작하며 필요한 신호를 요청했고 반영됨. contracts.md의 공개 함수 목록이 실제 파일과 같다.
- 참고: `docs/dev/contracts.md`

### A-02 헤드리스 검사 + CI · M0
- 만들 것: `.github/workflows/check.yml` (Godot 4.7 헤드리스로 `--import` 후 `--quit-after 5`, 출력에 `SCRIPT ERROR`·`Parse Error`가 있으면 실패), `tests/run_tests.gd` (각 레인 `tests/<lane>/test_*.gd`의 `run() -> bool` 호출), `.github/CODEOWNERS` 채우기.
- 완료 조건: 일부러 문법 오류를 넣은 PR에서 CI가 실패한다. `godot --headless --script res://tests/run_tests.gd`가 결과를 출력한다.

### A-03 디버그 콘솔 · M0
- 만들 것: `core/debug/` 의 개발용 콘솔(백틱 키). 명령: `res <id> <n>`, `day next`, `phase <name>`, `raid now`, `give <item_id>`, `resident add`, `godmode`.
  다른 레인이 명령을 등록할 수 있게 `DebugConsole.register(name, callable)`를 둔다(오토로드 추가 필요 시 `project.godot`도 A가).
- 완료 조건: 출시 빌드(`OS.is_debug_build() == false`)에서는 열리지 않는다.

### A-04 저장 시스템 · M1
- 만들 것: `SaveSystem.save_slot/load_slot` 구현. JSON, 슬롯 3개, `version` 필드, 자동 저장 시점(아침 시작·출격 직전·탈출 직후), 필드 중 종료용 "중단 저장" 1개(불러오면 삭제).
- 완료 조건: 모든 provider(`game`, `economy`, `armory`, `field`, `colony`)를 저장·복원하는 왕복 테스트가 `tests/core/`에 있다. 버전이 다른 파일은 안전하게 거부한다.
- 참고: `docs/design/01-flow-time.md` "저장"

### A-05 main.tscn + SceneRouter + 하루 흐름 · M1
- 만들 것: `main.tscn`에 `World`(Node3D) 노드. `SceneRouter`가 기지/필드 씬을 `World` 밑에 교체. 상태 머신: 아침 → 출격 준비 → 필드 → 결과 → 저녁 정산 → 밤 → 다음 날, "기지에 머무르기" 분기, 낮 습격 분기.
  저녁 정산 순서: `Colony.settle_day()`(C가 생산·소비 계산) 결과 → `Economy.apply` → `EventBus.evening_settled`. 밤: `Colony.roll_raid()` → 결과에 따라 방어전 또는 이벤트.
- 완료 조건: 디버그 명령만으로 하루 3번을 처음부터 끝까지 돌릴 수 있다(씬이 비어 있어도). 단계마다 `phase_changed`가 정확히 한 번 나온다.
- 의존: C-05(`settle_day` 시그니처 합의), B-09(`sortie_ended` 결과 형식)
- 참고: `docs/design/01-flow-time.md` "하루 구조", "게임 상태"

### A-06 Economy · M1
- 만들 것: `systems/defs/resource_def.gd`, `data/resources/*.tres`(기획 11 탭 자원 전부), 창고 한도(기본 200 + 창고 건물 보너스는 C가 `Economy.set_cap_bonus()`로 반영), 한도 넘치면 버림, 희귀 자원은 한도 제외.
- 완료 조건: 한도·음수 방지·희귀 제외 단위 테스트.
- 참고: `docs/design/11-economy.md`

### A-07 아이템·장비 체계 · M1
- 만들 것: `systems/defs/item_def.gd`, `item_instance.gd`, `affix.gd`, `data/items/`(05 탭 무기 15종·방어구 기본형). `Armory`: 인스턴스 생성(등급·부가 옵션 굴림), 장착/해제(`equip(owner_id, slot, uid)`), 클래스 계열 검사, 최종 스탯 계산(등급 배율, 강화 배율, 부가 옵션, 소음 보정 합 상한 +3m), 내구도 0이면 성능 50%, 무기고 목록.
- 완료 조건: 플레이어와 주민 모두 같은 API로 장착된다. `get_item_stats`가 05 탭 수치를 재현하는 테스트.
- 참고: `docs/design/05-gear.md`

### A-08 가방 격자 인벤토리 · M1
- 만들 것: `systems/bag.gd` — 격자 크기(가방 장비로 결정), 아이템 크기·회전, 놓기 가능 판정, 안전 주머니 2칸, 탈출 시 창고·무기고로 옮기기, 쓰러짐 시 비우기(안전 주머니 제외).
- 완료 조건: 놓기·회전·겹침 거부 테스트. B가 줍기에, D가 가방 UI에 같은 API를 쓴다.
- 참고: `docs/design/02-field.md` "루팅"

### A-09 강화·수리·제작 · M2
- 만들 것: 강화 비용 공식(n단계: 고철 10n, 부품 n, 6 이상 희귀 부품, 9 이상 계열 재료), 시설 레벨 상한(C의 시설 레벨을 getter로 읽음), 강화 옮기기, 수리, 레시피(`systems/defs/recipe.gd`, `data/recipes/`), 제작 등급 확률(손재주), 주민 작업 생산품(탄약 등)은 C의 정산에서 호출할 함수로 제공.
- 완료 조건: 비용·확률 단위 테스트. UI(D-12)가 쓸 `preview_upgrade(uid) -> Dictionary`.
- 참고: `docs/design/05-gear.md` "강화", "제작"

### A-10 정수·각인 계산 · M2
- 만들 것: `systems/defs/essence_def.gd`, `combo_def.gd`, `data/essences/`(4속성 × 3등급), 각인·덮어쓰기·제거, 일반 무기 슬롯 열기, 정제(3→1), 분해 반환 50%, 조합 판정. 결과는 `Armory.get_item_stats`의 `element`, `essence_effects`, `combo`로 노출. **전투 중 효과 발동은 B-15**가 한다.
- 완료 조건: 06 탭 표 수치가 그대로 나오는 테스트.
- 참고: `docs/design/06-magic-essence.md`

### A-11 경험치·레벨·특기 · M2
- 만들 것: `systems/progression.gd` — XP 공식(100 × L^1.4), 행동별 XP(신호를 듣고 적립), 레벨당 체력 +5, 3레벨마다 특기 선택, 클래스 숙련은 B가 계산하고 여기에 저장만 하도록 `add_mastery(class, xp)`.
- 참고: `docs/design/12-progression-balance.md`, `03-combat-classes.md` "플레이어 레벨"

### A-12 Settings + 난이도 · M1
- 만들 것: `ConfigFile` 저장, 난이도 프리셋 4종(이야기·보통·어려움·하드코어) → 개별 값 일괄 설정, 보호 모드 항목 개별 토글.
- 참고: `docs/design/12-progression-balance.md` "난이도", `14-ui-controls-accessibility.md`

### A-13 퀘스트·플래그 · M2
- 만들 것: `systems/quests/`, `systems/defs/quest_def.gd`, `data/quests/`. 유형: 메인·개인 요청·무전 소문·공동체·교역. 목표 종류: 지역 방문, 아이템 회수, 사람 데려오기, 기지 제작, 특정 날 방어. 필드 목표(유품 위치 등)는 B가 읽을 수 있게 `active_field_objectives(region_id)` 제공.
- 참고: `docs/design/13-world-narrative.md` "퀘스트 유형"

### A-14 Radio 디렉터 · M1
- 만들 것: 트리거 테이블(`data/radio/`), 쿨다운, 빈도 설정(Settings), 템플릿 문장 풀(유형당 5개), 아침 방송. `EventBus.radio_message` 발신. 낮 습격 예상 결과 구간은 `Colony`의 판정 함수를 호출해 얻는다.
- 완료 조건: LLM 없이 전부 동작한다.
- 참고: `docs/design/15-ai-features.md` "AI 무전병"

### ~~A-15 LLM 클라이언트 + 프록시~~ · 제외
- LLM을 쓰지 않기로 해서 하지 않는다. 아래는 기록용.
- 만들 것: `ai/llm_client.gd`(HTTPRequest, 타임아웃 5초, 실패 시 폴백), 키를 서버에 두는 작은 프록시(저장소의 `tools/llm_proxy/`는 A 소유로 새로 만듦, 키는 환경 변수). 게임에는 키가 절대 들어가지 않는다. 설정의 "AI 끄기".
- 참고: `docs/design/15-ai-features.md` "기술 구성"

### A-16 생존자 풀 · M2
- 만들 것: 기획 07 "데이터 정의"를 따르는 생존자 스키마(`systems/defs/`), 손으로 쓴 `data/resident_pool/` 항목, 스키마·금지어 검증 스크립트(`tools/`). 데모 3명 먼저, 이후 늘린다. C는 이 풀에서 구조 대상을 꺼낸다.
- (원래 계획: LLM으로 생성 후 검수. LLM 미사용으로 손 작성으로 바꿈.)
- 완료 조건: 생성물은 사람이 읽고 `reviewed = true`로 표시한 것만 게임에 나온다.
- 참고: `docs/design/15-ai-features.md` "생존자 생성", "검수 규칙"

### A-17 생존 일지 + 에필로그 · M2
- 만들 것: 사건 신호를 듣고 하루 기록 한 줄 생성(템플릿), `journal_entry_added` 발신, 엔딩용 주민별 요약.
- 참고: `docs/design/15-ai-features.md` "생존 일지"

### A-18 교역 · M3
- 만들 것: 교역 무리 3곳 데이터, 7일 제안, 물물교환, 우호도. UI는 D.
- 참고: `docs/design/11-economy.md` "교역"
