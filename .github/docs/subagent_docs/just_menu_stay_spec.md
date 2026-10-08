# Spec — Keep grouped `just` menus open after read-only actions

## Current state analysis

`_menu` (justfile, "Shared menu + dispatcher") backs nine grouped recipes
(`bootloader`, `remote-storage`, `feature`, `vpn`, `kill-switch`, `cache`,
`kernel`, `service`, `plex-pass`). With no action it prints a numbered menu,
reads one choice, then ends with `exec just "_${group}-${action}" ...`. `exec`
replaces the menu process, so after any action — including pure listings such
as `service list` — the shell prompt returns and the menu is gone.

## Problem definition

Picking a read-only item (list / status / info) from the interactive menu should
return to the menu so several can be inspected in a row. Mutating items must keep
today's run-then-exit behaviour.

## Proposed solution architecture

Extend the `_menu` item spec with an optional 4th field:
`key|description|prompt|stay`. A non-empty 4th field marks the item "stay".

In `_menu`:
- parse a parallel `stays` array alongside `keys`/`descs`/`prompts`;
- wrap menu-display → resolve → dispatch in a `while true` loop;
- track whether the action was chosen from the interactive menu (`picked`);
- if `picked` and the item is `stay`: run `just "_${group}-${action}" "${args[@]}" || true`
  as a child (failure must not kill the menu), clear `action`, and `continue`
  to redraw the menu;
- otherwise `exec` exactly as before.

Not changed: direct invocation (`just service list`) still `exec`s and exits;
non-TTY behaviour; the "0) Quit" path; unknown-action error path; non-stay items.

A cancelled argument prompt on a stay item returns to the menu instead of
exiting; on non-stay items it still exits 1.

### Items marked `stay` (read-only)

| Recipe    | Items                          |
|-----------|--------------------------------|
| service   | list, available, info, status  |
| vpn       | selftest, status, regions      |
| feature   | list                           |
| kernel    | status                         |
| cache     | harmonia                       |

Excluded: `kernel log` (follows live; Ctrl-C would kill the menu anyway) and all
enable/disable/restart/switch/push/login-style actions.

## Implementation steps

1. Edit `_menu` in `justfile` per above; update its header comment to document the 4th field.
2. Append `|stay` markers (`"list|desc||stay"` when there is no prompt) to the items in the table.

## Dependencies

None; plain bash. No Context7 lookup needed (no external libraries).

## Risks and mitigations

- `|` in a description would shift fields — none of the existing descriptions contain one.
- `set -e` + failing child: guarded with `|| true`.
- Empty `args` under `set -u`: already relied on by the existing code (bash >= 4.4).
- Risk of regressions in direct calls: the `picked` flag gates the new path, so
  non-interactive and direct invocations take the unchanged `exec` path.
