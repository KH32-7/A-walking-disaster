# A walking disaster - agent guide

Godot 4.7 (Forward+) project, config name "Walking disaster's project". Main scene: `res://main.tscn`.
This repo is **public**. Paid assets live in a separate **private** repo mounted as a submodule.

싱글 플레이 포스트 아포칼립스 탑다운 익스트랙션 슈터 + 기지 건설 게임. 기획은 `docs/design/`,
개발 분업과 작업 목록은 `docs/dev/`에 있다.

## 팀 작업 규칙 (4명, 각자 Claude Code)

팀원 4명이 레인(A~D)을 하나씩 맡고, 각자 자기 Claude Code 세션으로 작업한다.
충돌을 막는 핵심은 **파일 소유권**이다. 한 파일의 주인은 한 레인뿐이다.

### 세션을 시작하면 먼저

1. 프로젝트 루트의 `CLAUDE.local.md`(git에 올라가지 않음)에서 이 사용자의 레인을 확인한다.
   없으면 사용자에게 "어느 레인(A 코어·시스템 / B 필드 / C 기지 / D 표현·콘텐츠)인가요?"라고 묻고,
   답을 `CLAUDE.local.md`에 `내 레인: B` 형식으로 적는다.
2. `docs/dev/README.md`(분업 개요)와 자기 레인 문서 `docs/dev/lane-<x>-*.md`를 읽는다.
3. 공용 계약 `docs/dev/contracts.md`를 읽는다. 다른 레인과의 연결은 전부 여기 적힌 방식으로만 한다.
4. 작업할 태스크 ID(예: `B-05`)를 사용자와 정하고, 그 태스크의 "참고" 기획 문서를 읽는다.

### 레인과 소유 경로

| 레인 | 담당 | 소유 경로 (여기만 수정) |
|---|---|---|
| A 코어·시스템 | 하루 흐름, 저장, 자원·아이템·장비 백엔드, 강화·각인 계산, 퀘스트, AI(무전·생성) | `core/`, `systems/`, `ai/`, `tools/`, `project.godot`, `main.tscn`, `tests/run_tests.gd`, `data/{items,recipes,resources,essences,quests,radio,resident_pool}/`, `tests/core/`, `docs/dev/`, `docs/design/`, `.github/` |
| B 필드 | 플레이어, 카메라, 전투·클래스, 소음, 마물 AI, 루팅, 구조·호위, 탈출, 필드 맵 레이아웃 | `field/`, `data/{classes,monsters,regions,loot}/`, `levels/field/**` (단 `dressing.tscn` 제외), `tests/field/` |
| C 기지 | 건설, 주민 시뮬, 관계·인구, 습격·방어, 기지 맵 레이아웃 | `base/`, `data/{buildings,traits,jobs,events,raids}/`, `levels/base/**` (단 `dressing.tscn` 제외), `tests/base/` |
| D 표현·콘텐츠 | 모든 UI, 아트 임포트·셰이더, 맵 꾸미기(dressing), VFX, 사운드, `assets/` 서브모듈 | `ui/`, `art/`, `audio/`, `vfx/`, `levels/**/dressing.tscn`, `data/ui/`, `assets/` 포인터, `tests/ui/` |

- **자기 레인 소유가 아닌 파일은 고치지 않는다.** 읽기·인스턴스·호출은 자유.
  필요한 변경이 있으면 사용자에게 알리고, 사용자가 원하면 `gh issue create`로 그 레인에 요청 이슈를 만든다
  (제목 `[요청→B] ...`, 라벨 `lane:B`). 급하면 해당 레인 사람에게 직접 말하게 한다.
- 소유 경로가 애매한 새 파일은 만들기 전에 사용자에게 확인한다. 루트에 새 폴더를 만들지 않는다.
- `docs/dev/lane-*.md`의 체크박스는 자기 레인 문서만 갱신한다.

### 충돌을 막는 Godot 규칙

- **`project.godot`은 A만 수정한다.** 오토로드·입력·물리 레이어는 이미 등록돼 있다.
  입력 액션은 `core/input_setup.gd` 코드로 추가한다(A 소유). 애드온 추가·활성화도 A에게 요청한다.
- **다른 레인의 `.tscn`/`.tres`는 열어서 저장하지 않는다.** Godot는 실행(F5) 때 열린 씬을 저장하므로,
  남의 씬을 탭에 열어 둔 채 실행하지 않는다. Godot AI(MCP)로 씬을 저장할 때도 자기 소유 씬만.
- 남의 씬이 필요하면 **인스턴스**해서 쓴다. 상속 씬(inherited scene)도 자기 폴더에 만든다.
- 각 레인은 자기 `_sandbox/` 씬에서 개발·테스트한다. `main.tscn`은 A만 수정한다.
- 맵은 파일을 나눈다: `levels/<field|base>/<이름>/layout.tscn`(B·C: 충돌·내비·마커)과
  `dressing.tscn`(D: 메시·조명·장식), 둘을 인스턴스하는 `<이름>.tscn`(B·C).
- 스크립트를 만들면 Godot가 생성한 `.gd.uid` 파일도 함께 커밋한다. 남의 `.uid`를 지우거나 다시 만들지 않는다.
- `class_name`은 프로젝트 전체에서 유일해야 한다. 추가하기 전에 `grep -r "class_name <이름>"`으로 확인한다.
- 공용 enum은 `core/enums.gd`(`Enums`)에만 있다. 값은 **끝에 추가만** 한다(저장 데이터가 정수로 들고 있음).
- 레인 간 통신은 `EventBus` 신호와 `contracts.md`에 적힌 공개 함수만 쓴다. 다른 레인 노드의 내부 변수를 직접 건드리지 않는다.
- 데이터는 `.tres` 리소스로 둔다. 스키마(Resource 스크립트)는 각 레인의 `defs/` 폴더에 있다.

### Git 흐름

- `main`에 직접 커밋하지 않는다. 태스크마다 브랜치: `lane-b/B-05-weapon-runtime`.
- 커밋 메시지 앞에 태스크 ID: `[B-05] 사격 확산 구현`.
- 작업 시작 전과 PR 전에 `git pull --rebase origin main`. PR은 작게, 태스크 하나당 하나.
- PR 템플릿(`.github/pull_request_template.md`)을 채운다. 다른 레인 파일이 diff에 들어가면 PR을 나눈다.
- 머지 전 `docs/dev/README.md`의 "머지 전 확인"을 돌린다(헤드리스 실행으로 스크립트 오류 확인).
- 커밋·푸시·PR 생성은 사용자가 요청했을 때만 한다.

### 기획과 수치

- 기획 원본은 Claude Docs 문서이고 `docs/design/`은 그 사본이다. 수치·규칙이 기획과 다르게 필요하면
  코드에 임의로 바꾸지 말고 사용자에게 알린다. `docs/design/` 갱신은 A가 한다.
- 수치는 전부 가안이다. 코드에 하드코딩하지 말고 `.tres` 데이터나 상수 한곳에 모은다.
- 이 저장소는 공개 저장소다. 비밀 키(LLM API 키 등)는 절대 커밋하지 않는다(`ai/`는 프록시 경유).

## Repositories

| Path | Repo | Visibility | Contents |
|---|---|---|---|
| `/` | `KH32-7/A-walking-disaster` | public | code, scenes, project settings, Godot AI plugin |
| `assets/` | `KH32-7/A-walking-disaster-assets` | **private** | paid / licensed assets, Git LFS enabled |

`assets/` is a git submodule (`.gitmodules`, relative URL `../A-walking-disaster-assets.git`, branch `main`).
In Godot it is `res://assets/...`.

**팀 규칙**: `assets/` 포인터(메인 저장소의 서브모듈 커밋)는 **D만 올린다.** 두 사람이 동시에 포인터를 올리면
충돌이 난다. 다른 레인이 에셋이 필요하면 D에게 요청한다.

## Hard rules

1. **Paid or licensed files go only under `assets/`.** Never add them anywhere else in the main repo -
   anything committed there is public forever, even if deleted later.
2. **Never make the assets repo public** and never copy its files into the main repo, an export, or an issue/PR.
3. If `assets/` is empty, the submodule is not initialized or the user has no access.
   Run `git submodule update --init`. Do **not** recreate the folder, replace it with placeholders,
   or remove the submodule.
4. Scenes in the main repo may reference `res://assets/...`. Missing-dependency warnings on a clone without
   access are expected; do not "fix" them by removing references.

## Committing asset changes (two commits, not automatic)

`git add -A` in the main repo does **not** include files inside `assets/`; the main repo only records which
assets commit to use. Always commit the submodule first, push it, then record the pointer:

```sh
git -C assets switch main          # submodule is often on a detached HEAD after clone/update
git -C assets add -A
git -C assets commit -m "Add <what>"
git -C assets push
git add assets
git commit -m "Update assets"
git push
```

- Never push a main-repo commit whose `assets` pointer refers to an unpushed submodule commit;
  teammates' clones will fail with "not our ref".
- Before committing in `assets/`, check `git -C assets branch --show-current` prints `main`.
  If it prints nothing (detached HEAD), run `git -C assets switch main` first.
- Binary types (images, audio, video, 3D, fonts, `.res`/`.scn`) are tracked by Git LFS via
  `assets/.gitattributes`. If a new binary type shows up, add it there (`git -C assets lfs track "*.ext"`)
  before committing it.
- Commit `.import` files next to their assets in the submodule. Never commit `.godot/`.
- LFS storage and bandwidth count against the repo owner's GitHub quota; avoid committing huge
  or duplicate files.

## Pulling

```sh
git pull
git submodule update --init
```

Recommended one-time local config (per clone, not stored in the repo):

```sh
git config push.recurseSubmodules on-demand   # pushing main also pushes assets
git config submodule.recurse true             # pull/checkout also updates assets
```

## Godot AI (MCP)

- `addons/godot_ai/` is Godot AI v4.4.1, enabled in `project.godot`, plus the `_mcp_game_helper` autoload.
- MCP tools work only while the Godot editor is open on this project. Each person connects their own
  client once via the **Godot AI** dock -> **Configure** (needs `uv` installed).
- Update the plugin only with the dock's **Update** button, then commit `addons/godot_ai/`.
  Never extract a release zip over the existing folder. (팀 규칙: 플러그인 업데이트는 A만.)
- Godot AI cannot write `project.godot`, `override.cfg`, or `.godot/`; edit those by hand if needed.
