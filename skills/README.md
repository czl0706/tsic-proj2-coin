# Skill Patches

This folder contains one patch per skill. Each patch is meant to be applied on
top of the base game branch, then built as its own skill variant.

## Apply One Skill

Start from a clean working tree or a fresh branch:

```powershell
git status
git checkout -b skill-magnet
```

Apply one patch:

```powershell
git apply --ignore-whitespace .\skills\patches\magnet.patch
```

Build the project:

```powershell
.\.vscode\run.ps1
```

The generated bitstream is under:

```text
impl\pnr\*.fs
```

## Available Patches

```text
skills\patches\double_score.patch
skills\patches\gambler.patch
skills\patches\invincible_1.patch
skills\patches\invincible_2.patch
skills\patches\magnet.patch
skills\patches\speed_boost.patch
skills\patches\star_rain.patch
```

## Batch Build All Skills

To build every skill patch and place only the `.fs` files in `skills\fs\`:

```powershell
.\skills\run_all_patches.ps1
```

This script builds each patch in a temporary git worktree. It does not apply the
patches to your current working tree, and it does not upload to the board.

## Notes

- Apply only one skill patch at a time.
- The patches are not designed to be stacked together.
- If a patch no longer applies, first make sure the base skill hooks in
  `src\game\game_core.v`, `src\game\game_ctrl.v`, and `src\overlay\ui_layer.v`
  are present.
- Use `git apply --check --ignore-whitespace <patch>` to test a patch without
  changing files.
