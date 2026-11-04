# A walking disaster - agent guide

Godot 4.7 (Forward+) project, config name "Walking disaster's project". Main scene: `res://main.tscn`.
This repo is **public**. Paid assets live in a separate **private** repo mounted as a submodule.

## Repositories

| Path | Repo | Visibility | Contents |
|---|---|---|---|
| `/` | `KH32-7/A-walking-disaster` | public | code, scenes, project settings, Godot AI plugin |
| `assets/` | `KH32-7/A-walking-disaster-assets` | **private** | paid / licensed assets, Git LFS enabled |

`assets/` is a git submodule (`.gitmodules`, relative URL `../A-walking-disaster-assets.git`, branch `main`).
In Godot it is `res://assets/...`.

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
