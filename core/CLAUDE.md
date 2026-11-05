# core/ — 레인 A 소유

공용 계약(EventBus·Enums·GameState·SaveSystem·Settings·InputSetup·SceneRouter). 다른 레인은 읽기만 한다.
- Enums 값은 끝에 추가만. EventBus 신호 변경·삭제는 모든 리스너를 같은 PR에서 고칠 때만.
- 공개 함수가 바뀌면 docs/dev/contracts.md도 같이 고친다.
- 작업 목록: docs/dev/lane-a-core.md
