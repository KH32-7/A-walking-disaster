# A walking disaster - agent guide

Godot 4.7 (Forward+) project, config name "Walking disaster's project". Main scene: `res://main.tscn`.
This repo is **public**. Paid assets live in a separate **private** repo mounted as a submodule.

싱글 플레이 포스트 아포칼립스 탑다운 익스트랙션 슈터 + 기지 건설 게임. 기획은 `docs/design/`,
작업 목록과 공용 함수·신호 정리는 `docs/dev/`에 있다.

## 작업 규칙

M2까지는 팀원 4명이 레인(A~D)을 나눠 파일 소유권을 지켰지만, **M2 이후로 레인 구분과 소유권은 없다.**
누구든 어느 폴더·파일이든(`project.godot`, `main.tscn`, 다른 사람이 만든 씬·스크립트·데이터 포함) 필요한 대로 고친다.
"다른 레인 파일이니 요청 이슈로" 같은 절차 없이 바로 작업한다. `docs/dev/lane-*.md`는 그동안의 작업 목록 기록으로 남겨 둔다.

### 세션을 시작하면 먼저

1. `docs/dev/README.md`(개요·마일스톤·머지 전 확인)를 읽는다.
2. 건드릴 기능의 공개 함수·신호는 `docs/dev/contracts.md`에서 찾는다. 바꾸면 쓰는 곳을 모두 같이 고치고 이 문서도 고친다.
3. 할 일을 사용자와 정하고, 관련 기획 문서(`docs/design/`)를 읽는다.

### Godot 규칙 (충돌·깨짐 방지)

- Godot는 실행(F5) 때 열린 씬을 저장한다. **다른 사람이 지금 고치고 있는 씬**을 탭에 열어 둔 채 실행하지 않는다.
- 맵은 파일을 나눠 둔다: `levels/<field|base>/<이름>/layout.tscn`(충돌·내비·마커), `dressing.tscn`(메시·조명·장식),
  둘을 인스턴스하는 `<이름>.tscn`. 구조를 바꾸면 쓰는 곳(테스트·생성기)을 같이 고친다.
- 스크립트를 만들면 Godot가 생성한 `.gd.uid` 파일도 함께 커밋한다. 이유 없이 `.uid`를 지우거나 다시 만들지 않는다.
- `class_name`은 프로젝트 전체에서 유일해야 한다. 추가하기 전에 `grep -r "class_name <이름>"`으로 확인한다.
- 공용 enum은 `core/enums.gd`(`Enums`)에 있다. 값은 **끝에 추가만** 한다(저장 데이터가 정수로 들고 있음).
- `EventBus` 신호나 공개 함수를 바꾸거나 지우면 모든 사용처를 같은 PR에서 고친다.
- 데이터는 `.tres` 리소스로 둔다. 스키마(Resource 스크립트)는 `systems/defs/`, `field/defs/`, `base/defs/`, `ui/` 등에 있다.

### Git 흐름

- `main`에 직접 커밋하지 않는다. 할 일마다 브랜치: `C-22-migration`, `fix/fx-light` 처럼.
- 커밋 메시지 앞에 태스크 ID나 종류: `[C-22] 이주 판정`, `[fix] ...`.
- 작업 시작 전과 PR 전에 `git pull --rebase origin main`. PR은 작게, 할 일 하나당 하나.
- PR 템플릿(`.github/pull_request_template.md`)을 채운다.
- 머지 전 `docs/dev/README.md`의 "머지 전 확인"을 돌린다(헤드리스 실행으로 스크립트 오류·테스트 확인).
- 커밋·푸시·PR 생성은 사용자가 요청했을 때만 한다.

### 기획과 수치

- 기획 원본은 Claude Docs 문서이고 `docs/design/`은 그 사본이다. 수치·규칙이 기획과 다르게 필요하면
  코드에 임의로 바꾸지 말고 사용자에게 알린다. `docs/design/`은 기획이 바뀌면 누구든 같이 갱신한다.
- 수치는 전부 가안이다. 코드에 하드코딩하지 말고 `.tres` 데이터나 상수 한곳에 모은다.
- 이 저장소는 공개 저장소다. 비밀 키(LLM API 키 등)는 절대 커밋하지 않는다(`ai/`는 프록시 경유).

## Repositories

| Path | Repo | Visibility | Contents |
|---|---|---|---|
| `/` | `KH32-7/A-walking-disaster` | public | code, scenes, project settings, Godot AI plugin |
| `assets/` | `KH32-7/A-walking-disaster-assets` | **private** | paid / licensed assets, Git LFS enabled |

`assets/` is a git submodule (`.gitmodules`, relative URL `../A-walking-disaster-assets.git`, branch `main`).
In Godot it is `res://assets/...`.

`assets/` 포인터(메인 저장소의 서브모듈 커밋)는 누구나 올릴 수 있다. 두 사람이 동시에 올리면 충돌이 나므로,
올리기 전에 `git pull`로 main의 포인터를 받고 그 위의 assets 커밋으로 올린다.

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
  Never extract a release zip over the existing folder.
- Godot AI cannot write `project.godot`, `override.cfg`, or `.godot/`; edit those by hand if needed.
