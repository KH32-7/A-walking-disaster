# 개발 개요

목표: 튜토리얼을 뺀 **코어 기능이 전부 돌아가는 빌드**. 규칙은 루트 [CLAUDE.md](../../CLAUDE.md),
기능 사이의 공개 함수·신호는 [contracts.md](contracts.md)에 있다.

**M2까지는 4명이 레인(A~D)을 나눠 파일 소유권을 지켰다. M2 이후로 레인 구분과 소유권은 없다.**
누구든 어느 파일이든 고치고, 다른 사람 파일이라고 요청 이슈를 거치지 않는다.

## 작업 목록 (기록)

M0~M2 태스크는 아래 문서에 기능별로 남아 있다. 앞으로의 할 일도 기능에 맞는 문서에 이어 적는다.

| 기능 | 한 줄 요약 | 작업 목록 |
|---|---|---|
| 코어·시스템 (A) | 하루 흐름·저장·자원·아이템·강화·각인·퀘스트·무전 | [lane-a-core.md](lane-a-core.md) |
| 필드 (B) | 플레이어·전투·클래스·소음·마물·루팅·구조·탈출·필드 맵 | [lane-b-field.md](lane-b-field.md) |
| 기지 (C) | 건설·주민·관계·인구·습격·방어·기지 맵 | [lane-c-base.md](lane-c-base.md) |
| 표현·콘텐츠 (D) | UI·아트·셰이더·맵 꾸미기·VFX·사운드·에셋 | [lane-d-presentation.md](lane-d-presentation.md) |

## 마일스톤

| 마일스톤 | 목표 | 끝났다고 보는 기준 |
|---|---|---|
| **M0 기반** | 각 레인이 자기 샌드박스에서 작업을 시작할 수 있다 | 계약 확정, 마커 씬 세트, 샌드박스 씬, UI 테마, 툰 셰이더, 테스트 러너 |
| **M1 한 바퀴** | 하루 한 바퀴가 그레이박스로 돈다 | 기지(침상·벌목장) → 출격(침수 상가, 마물 1종, 루팅, 구조 1명, 탈출) → 저녁 정산 → 밤 습격 자동 판정 → 다음 날. 저장·불러오기 |
| **M2 코어 전부** | 기획의 코어 시스템이 모두 동작한다 (데모 범위 콘텐츠) | 클래스 3종·마법 각인·방어전·관계·결혼·아이 맞이·편견 이벤트·전초기지·AI 무전·모든 UI 화면 |
| M3 콘텐츠 확장 | 정식 범위 | 지역 5곳, 보스 5종, 건물 전체, 계절, 교역, 엔딩 |

튜토리얼은 이번 범위가 아니다(나중에 별도).

## 브랜치·PR

1. `git pull --rebase origin main`
2. `git switch -c <태스크ID 또는 종류>-<짧은설명>` (예: `C-22-migration`, `fix/fx-light`)
3. 작업, 커밋 메시지는 `[태스크ID] 내용` (태스크가 없으면 `[fix]`, `[docs]` 등)
4. 머지 전 확인(아래) → PR → squash 머지
5. 작업 목록 문서에 그 태스크가 있으면 같은 PR에서 체크한다

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
(테스트 파일은 `tests/<core|field|base|ui>/test_*.gd`, `run() -> bool`. RefCounted나 Node 상속, `await` 가능)

## Claude Code에게 일 맡기는 법

- 한 세션에 할 일 하나. "C-22 해줘. 작업 목록의 완료 조건을 지켜."처럼 태스크 ID나 내용으로 시킨다.
- 끝나면 완료 조건을 하나씩 확인시키고, 샌드박스 씬이나 main.tscn에서 실행해 본다.
- 필요한 파일은 어느 폴더든 바로 고친다. 공개 함수·신호를 바꾸면 쓰는 곳과 contracts.md를 같이 고친다.
