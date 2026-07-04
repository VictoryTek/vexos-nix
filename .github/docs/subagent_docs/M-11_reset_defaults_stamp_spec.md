# M-11 — `just reset-defaults` removes the wrong stamp name

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-11 · `justfile:640-653`

## Current State

`reset-defaults` only removes one specific stamp file:
`rm -f "$HOME/.local/share/vexos/.dconf-app-folders-initialized-v2"`.

Repo-wide grep across every `home-*.nix` file finds four distinct dconf-related stamp
names actually in use, not one:
- `.dconf-app-folders-initialized-v2` (stateless, htpc, server)
- `.dconf-app-folders-initialized-v3` (**desktop** — the primary role — uses `v3`, not
  `v2`, so `reset-defaults` doesn't even remove the right app-folders stamp there)
- `.dconf-extensions-initialized` (stateless, htpc, server)
- `.dconf-extensions-initialized-v3` (desktop)

The extensions-initialized stamp gates a first-run service that enables GNOME Shell
extensions once. `reset-defaults` clears the dconf database (including the
extension-enabled state) but never removes this stamp, so the first-run service sees
"already initialized" and never re-enables extensions — exactly the reported symptom
("leaves all GNOME extensions permanently disabled").

Three other stamp files exist (`.photogimp-orphan-cleanup-done`,
`.stateless-photogimp-cleanup-done`, `.dock-brave-origin-migration-v1`) but these are
one-time migration/cleanup markers unrelated to GNOME dconf settings — `reset-defaults`
should not touch them.

## Problem Definition

Remove every dconf-related init stamp, not just one hardcoded (and, on desktop, wrong)
filename — without also clearing unrelated one-time migration stamps.

## Proposed Solution

Replace the single hardcoded `rm -f` with a glob matching every current and future
`.dconf-*-initialized*` stamp, per the MASTER_PLAN's primary suggestion — more robust
than an explicit list, since it automatically covers a future `-v4` bump without
needing another justfile edit:

```bash
rm -f "$HOME"/.local/share/vexos/.dconf-*-initialized*
```

This matches all four stamps found above and none of the three unrelated ones (none of
which start with `.dconf-`).

## Implementation Steps

1. `justfile` — `reset-defaults` recipe: replace the single `rm -f` line with the glob
   above.

## Configuration Changes

None.

## Risks and Mitigations

- **Glob with no matches** — `rm -f` with a non-matching glob under `set -euo pipefail`
  without `nullglob` would normally pass the literal (unexpanded) glob pattern as an
  argument to `rm`, which then fails since no such literal file exists — `rm -f`
  specifically suppresses "no such file" errors, so this is safe even when zero stamp
  files exist yet (fresh install, never logged in graphically).
