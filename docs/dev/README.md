# 개발 분업 개요

목표: 튜토리얼을 뺀 **코어 기능이 전부 돌아가는 빌드**. 팀원 4명이 레인 하나씩, 각자 Claude Code로 작업한다.
규칙은 루트 [CLAUDE.md](../../CLAUDE.md), 레인 사이의 연결은 [contracts.md](contracts.md)에 있다.

## 레인

| 레인 | 한 줄 요약 | 작업 목록 | 담당자 |
|---|---|---|---|
| A 코어·시스템 | 하루 흐름·저장·자원·아이템·강화·각인·퀘스트·AI 무전/생성 | [lane-a-core.md](lane-a-core.md) | (미정) |
| B 필드 | 플레이어·전투·클래스·소음·마물·루팅·구조·탈출·필드 맵 레이아웃 | [lane-b-field.md](lane-b-field.md) | (미정) |
| C 기지 | 건설·주민·관계·인구·습격·방어·기지 맵 레이아웃 | [lane-c-base.md](lane-c-base.md) | (미정) |
| D 표현·콘텐츠 | 모든 UI·아트 임포트·셰이더·맵 꾸미기·VFX·사운드·에셋 | [lane-d-presentation.md](lane-d-presentation.md) | (미정) |

담당자가 정해지면 위 표와 `.github/CODEOWNERS`를 채운다(A 담당).

## 마일스톤

| 마일스톤 | 목표 | 끝났다고 보는 기준 |
|---|---|---|
| **M0 기반** | 각 레인이 자기 샌드박스에서 작업을 시작할 수 있다 | 계약 확정, 마커 씬 세트, 샌드박스 씬, UI 테마, 툰 셰이더, 테스트 러너 |
| **M1 한 바퀴** | 하루 한 바퀴가 그레이박스로 돈다 | 기지(침상·벌목장) → 출격(침수 상가, 마물 1종, 루팅, 구조 1명, 탈출) → 저녁 정산 → 밤 습격 자동 판정 → 다음 날. 저장·불러오기 |
| **M2 코어 전부** | 기획의 코어 시스템이 모두 동작한다 (데모 범위 콘텐츠) | 클래스 3종·마법 각인·방어전·관계·결혼·아이 맞이·편견 이벤트·전초기지·AI 무전·모든 UI 화면 |
| M3 콘텐츠 확장 | 정식 범위 | 지역 5곳, 보스 5종, 건물 전체, 계절, 교역, 엔딩 |

튜토리얼은 이번 범위가 아니다(나중에 별도).

## 의존 순서 (먼저 끝나야 하는 것)

- **A-01 계약**, **B-02 필드 마커**, **C-01 기지 마커**, **D-01 UI 테마**는 M0 첫날 끝낸다. 다른 레인이 기다린다.
- B와 C는 A의 `Armory`(A-07)·`Economy`(A-06)가 나오기 전엔 contracts.md의 함수 시그니처대로 **가짜 값**을 돌려주는
  자기 샌드박스용 스텁을 `_sandbox/`에 두고 작업한다. 실제 오토로드를 고치지 않는다.
- D는 B·C의 신호와 getter만 보고 UI를 만든다. 데이터가 아직 없으면 `ui/_preview/`의 가짜 데이터로 화면을 만든다.
- 통합(main.tscn에서 하루 한 바퀴)은 A-05가 맡는다.

## 브랜치·PR

1. `git pull --rebase origin main`
2. `git switch -c lane-<x>/<태스크ID>-<짧은설명>`
3. 작업, 커밋 메시지는 `[태스크ID] 내용`
4. 머지 전 확인(아래) → PR → 같은 레인이 아닌 팀원 1명이 훑어본다 → squash 머지
5. 자기 레인 문서의 체크박스를 같은 PR에서 체크한다

## 머지 전 확인

```sh
GODOT=/path/to/godot bash tools/headless_check.sh
```

임포트 → 5프레임 실행 → 모든 스크립트 로드(`tools/check_scripts.gd`, `addons/` 제외) → 테스트(`tests/run_tests.gd`) 순서로 돌고,
`SCRIPT ERROR`·`Parse Error`가 나오거나 테스트가 하나라도 실패하면 `OK` 대신 `FAILED`로 끝난다.
GitHub Actions(`.github/workflows/check.yml`)가 PR마다 같은 스크립트를 돌린다. CI는 비공개 `assets/` 서브모듈 없이 돌기 때문에
`res://assets/...` 누락 경고는 실패로 치지 않는다.

Windows(Git Bash)에서 Steam판:

```sh
GODOT="/c/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" bash tools/headless_check.sh
```

테스트만 돌리기: `godot --headless --path . --script res://tests/run_tests.gd -- --lane=field`
(테스트 파일은 `tests/<lane>/test_*.gd`, `run() -> bool`. RefCounted나 Node 상속, `await` 가능)

## Claude Code에게 일 맡기는 법

- 한 세션에 태스크 하나. "B-05 해줘. 레인 문서의 완료 조건을 지켜."처럼 태스크 ID로 시킨다.
- 끝나면 완료 조건을 하나씩 확인시키고, 샌드박스 씬에서 실행해 본다.
- 다른 레인 파일을 고쳐야 한다고 하면 멈추고 요청 이슈로 돌린다.
