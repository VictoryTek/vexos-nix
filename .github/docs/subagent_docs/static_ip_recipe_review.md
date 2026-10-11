# static_ip_recipe — Review

Spec: `.github/docs/subagent_docs/static_ip_recipe_spec.md`
Modified: `just/admin.just` (new `static-ip` recipe). No `.nix` files changed.

## Verification performed

| Check | Result |
|-------|--------|
| `just --list` shows `static-ip` in *System Administration* | pass |
| Recipe body run against a scratch `/etc/nixos` (stubbed `sudo`, `upgrade-wrapper.sh`, `just _confirm`) | see below |
| Bad IPv4 / out-of-range prefix re-prompt | pass |
| First run creates `local.nix` and writes 3 dotted lines | pass |
| Re-run updates the 3 lines in place (no duplicates), secondary DNS added | pass |
| EOF on stdin mid-prompt → exit 1, no file written | pass |
| Declined confirmation → "Aborted", file unchanged | pass |
| Vanilla role refused | pass |
| Hand-written whole-attrset `staticWired` in `local.nix` → refused with hint | pass |
| Wrapper without `./local.nix` → warning, rebuild prompt skipped | pass |
| Dotted `vexos.network.staticWired.*` satisfies `nullOr (submodule …)` (evalModules replica of the option) | pass |
| `scripts/preflight.sh` | exit 0 (12/12 stages; justfile parses, 56 recipes shellchecked clean) |

## Not verified

- Run against the real `/etc/nixos` and a real `just rebuild` / NM activation
  (user-initiated only; the scratch test stubs `sudo`, the wrapper upgrade and
  the confirm helper).
- `scripts/upgrade-wrapper.sh` on this host's legacy wrapper was not executed —
  it rewrites `/etc/nixos/flake.nix`; the recipe calls it exactly as
  `set-hostname` does.

## Findings

- No CRITICAL issues.
- Pre-existing preflight WARNs (nixpkgs-fmt on existing `.nix` files, stale
  flake inputs, secret-pattern scan) are unrelated to this change.
- Dead code noted, not touched: `scripts/configure-network.py` (target block no
  longer exists in `modules/network.nix`).

## Revision 2 — menu + remove

| Check | Result |
|-------|--------|
| `just --list` shows `static-ip action="" *args` (menu) | pass |
| Non-TTY `just static-ip` prints usage, rc 1; unknown action rejected | pass |
| Menu renders on a pty with options 1 set / 2 remove / 0 quit | pass |
| `just static-ip remove` on this host (no `local.nix`) → "nothing to remove", rc 0 | pass |
| Remove (scratch `/etc/nixos`): only the three lines deleted, other config kept, live profile dropped, `nmcli connection reload` called, rebuild offered | pass |
| Remove declined → "Aborted", file unchanged | pass |
| Hand-written whole-attrset → refused | pass |
| Hand-written multi-line value → parse guard refuses, file untouched | pass |

Not verified: removal against the real NetworkManager (the `rm` + `nmcli connection
reload` were stubbed in the scratch run) and a real rebuild.

**Result: PASS**
