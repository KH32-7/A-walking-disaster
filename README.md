# A walking disaster

Godot 4.7 (Forward+) project - "Walking disaster's project".

## Setup

1. Godot 4.7+ (Steam build works) - open `project.godot`.
2. AI tooling: [Godot AI](https://github.com/hi-godot/godot-ai) v4.4.1 is bundled in `addons/godot_ai/` and enabled.
   - Install [uv](https://docs.astral.sh/uv/getting-started/installation/) once (`irm https://astral.sh/uv/install.ps1 | iex` on Windows).
   - In the **Godot AI** dock, press **Configure** next to your MCP client (Claude Code, Codex, Cursor, ...).
   - Update the plugin with the dock's **Update** button, never by extracting over `addons/godot_ai/`.

## Team workflow

Each person works with their own Claude Code session. Up to M2 the work was split into 4 lanes with file
ownership; since M2 there are no lanes and anyone may change any file.
Start with [docs/dev/README.md](docs/dev/README.md); rules for agents are in [CLAUDE.md](CLAUDE.md).
Game design (Korean) is in [docs/design/](docs/design/).

## Paid assets (private submodule)

`assets/` is a git submodule pointing at the **private** repo `KH32-7/A-walking-disaster-assets`
(Git LFS enabled). Without access the folder stays empty; the rest of the project still clones.

```sh
git clone --recurse-submodules https://github.com/KH32-7/A-walking-disaster.git
# already cloned:
git submodule update --init
```

Working with assets:

1. Put licensed files only under `assets/` (`res://assets/...`). Never commit them anywhere else in this repo.
2. Commit inside the submodule first, then record the new pointer in the main repo:
   ```sh
   cd assets && git add -A && git commit -m "..." && git push && cd ..
   git add assets && git commit -m "Update assets" && git push
   ```
3. Pull both: `git pull && git submodule update --init`.
