# core/ — 공용 기반

EventBus·Enums·GameState·SaveSystem·Settings·InputSetup·SceneRouter. 여러 기능이 같이 쓰는 기반이다.
- Enums 값은 끝에 추가만. EventBus 신호 변경·삭제는 모든 리스너를 같은 PR에서 고칠 때만.
- 공개 함수가 바뀌면 docs/dev/contracts.md도 같이 고친다.
- 작업 목록(기록): docs/dev/lane-a-core.md
