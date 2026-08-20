# VexPortal Integration — Specification

## Current state analysis

VexPortal (`github:VictoryTek/VexPortal`) is a GTK4/libadwaita GUI that drives this
repo's `justfile` through a root daemon. The daemon execs `just <recipe> <args...>` as
argv (never through a shell), with a scrubbed environment: `PATH`, `VEXOS_ASSUME_YES=1`,
`VEXPORTAL=1`, `HOME=/root`, `LANG=C.UTF-8`, `NO_COLOR=1`, `TERM=dumb`. stdin is
`/dev/null` except for one recipe (`setup-rdp`) which gets a single secret line then EOF.
There is no TTY.

Verified today: every recipe uses `set -euo pipefail`. `read ... || true` sites degrade
to the `[y/N]` default (no-op) on EOF; plain `read` sites hit `set -e` and the recipe
exits 1. Nothing hangs; nothing silently answers "yes" on the user's behalf currently —
but two recipes (`update`, `setup-rdp`) currently fail outright when driven headlessly,
which is the gap this spec closes.

## Problem definition

1. Six confirmation prompts across five recipes have no way to be pre-answered when
   driven non-interactively, even though VexPortal already gates the same actions with
   its own GUI confirmation dialog.
2. `update` cannot be given a role/variant up front (stateless-reboot case), so it fails
   under VexPortal when `/etc/nixos/vexos-variant` is absent.
3. `setup-rdp`'s two-read confirm loop cannot be satisfied by a single piped line.
4. `enable <service>` has 11 interactive reads; need to assess (not necessarily change)
   whether any should become parameters.
5. The flake doesn't yet install/enable VexPortal for display-bearing roles.

## Proposed solution

### Task 1 — `_confirm` helper

Add a private helper recipe near the other shared helpers (`_require-server-role` at
`justfile:1229`):

```just
# Prompt for a yes/no confirmation, auto-answering "yes" when VEXOS_ASSUME_YES=1.
# Usage: if $(just _confirm "Prompt text? [y/N]: "); then ... fi
[private]
_confirm prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        echo "true"
        exit 0
    fi
    printf '%s' "{{prompt}}" >&2
    read -r ANSWER || true
    case "${ANSWER,,}" in
        y|yes) echo "true" ;;
        *)     echo "false" ;;
    esac
```

`just` recipes can't easily share a bash function across `#!/usr/bin/env bash` script
blocks (each is a separate script invocation), so `_confirm` is implemented as its own
just recipe returning `true`/`false` on stdout, called via command substitution from the
calling recipe's script block. This keeps each call-site a two-line change and preserves
exact prompt text/echo ordering for the human path.

Call sites (all read the prompt text unchanged for the human path):

- `switch:225` reboot confirm
- `set-hostname:846` rebuild confirm
- `fix-flake:997` rebuild confirm
- `reset-defaults:710` continue confirm
- `restore-plex:1350` — typed-keyword ("yes") confirm. Decision: `VEXOS_ASSUME_YES=1`
  satisfies it too, since VexPortal already shows its own destructive-action dialog
  before invoking this recipe, and requiring the user to type "yes" a second time inside
  a scripted flow is exactly the kind of prompt VEXOS_ASSUME_YES exists to remove. This
  is a judgment call — flagged in-code with a one-line comment for future reference.

**Invariant:** with `VEXOS_ASSUME_YES` unset, every prompt call-site is byte-identical to
its current text and read behavior — `_confirm` calls `read -r` exactly the way today's
inline code does when the flag is absent.

### Task 2 — `update role="" variant=""`

Mirror `switch`'s existing parameter signature. When `role`/`variant` are supplied
(non-empty), skip straight to `ROLE="{{role}}"` / `VARIANT="{{variant}}"` instead of
prompting, reusing the same validation approach `switch` already has for direct
arguments (accept the six/five/`nvidia-legacy535` values listed in the spec). When both
are empty AND `/etc/nixos/vexos-variant` is present, behavior is unchanged (uses the
variant file). When both are empty AND the variant file is absent, existing interactive
prompts run exactly as today.

### Task 3 — `setup-rdp` stdin path

```bash
if [ -t 0 ]; then
    # existing two-read loop, verbatim
else
    IFS= read -r password
fi
```

No confirmation read when stdin is not a TTY — matches the daemon's single-line-then-EOF
contract exactly.

### Task 4 — `enable <service>` audit (no code change)

Assessed each of the 11 reads:

- Proxmox IP / bridge NIC (`justfile:2202,2220`) — plain strings with regex validation,
  no filesystem interaction. Could become parameters.
- Restic repository path / password file path (`justfile:2238,2250`) — plain strings.
  Could become parameters.
- Arcane public URL (`justfile:2281`) — plain string. Could become a parameter.
- Matrix server name (`justfile:2763`) — plain string with a default. Could become a
  parameter.
- Zigbee serial device (`justfile:2900`) — plain string with a default. Could become a
  parameter.
- ZFS pool creation prompt (`justfile:2043`) and arr full/individual selection
  (`justfile:2054,2113,2121`) — these branch into other interactive recipes
  (`create-zfs-pool`, `create-mergerfs-pool`, `attach-remote-storage`) or a numbered
  multi-select menu; not simple scalar values.
- Disk selection (inside `create-zfs-pool`/`create-mergerfs-pool`, not `enable` itself)
  — inherently needs live disk enumeration; not appropriate for a static form field.

Recommendation: leave `enable` as `terminal = true` in VexPortal's catalog. It's one
recipe with 11 branching, service-conditional reads plus two sub-flows that require live
system state (disk lists). Splitting the scalar-value services (proxmox, backup, arcane,
matrix, zigbee2mqtt) into their own parameterized recipes would be a larger, separate
redesign, not a surgical change — out of scope here. No justfile change for Task 4.

### Task 5 — flake wiring

Add `vexportal` input beside `up` (`flake.nix:~33`) and `vexportalModule` beside
`upModule` (`flake.nix:~83`), then add `vexportalModule` to `baseModules` for desktop,
htpc, stateless, and server — the same set `upModule` is already in — leaving
headless-server untouched (no display).

## Implementation steps (Module Architecture Pattern: N/A — this is justfile + flake.nix,
not a NixOS module; existing per-role wiring pattern in flake.nix's `roles` table is
followed as-is)

1. Add `_confirm` private recipe to `justfile`.
2. Update 5 call sites to use `_confirm`.
3. Add `role=""`, `variant=""` params to `update`; branch on them before the interactive
   prompt block.
4. Update `setup-rdp` to branch on `[ -t 0 ]`.
5. Add `vexportal` input + `vexportalModule` to `flake.nix`; add to `baseModules` for
   desktop/htpc/stateless/server.

## Dependencies

No new external libraries. `vexportal` flake input follows `nixpkgs` (per VexPortal's
handoff doc), matching the `up` input's pattern exactly. No Context7 lookup needed — pure
Nix flake/module wiring, no external library API surface.

## Configuration changes

`flake.nix`: new input, new module, new `baseModules` entries for 4 roles.
`justfile`: new private recipe, 5 call-site edits, 2 recipes gain non-interactive paths.

## Risks and mitigations

- Risk: `_confirm`'s command-substitution approach changes stdout/stderr framing for the
  prompt line. Mitigation: prompt is written to `>&2`, echo("true"/"false") to stdout
  only — the calling recipe captures only the verdict, human-visible prompt text is
  unchanged on stderr, matching `printf "...: "` which today also goes to the terminal
  (stdout in current code, but terminals don't distinguish — verified no test depends on
  stream separation).
- Risk: `update` param validation drifting from `switch`'s. Mitigation: reuse the same
  literal accepted-value sets, no new validation logic invented.
- Risk: breaking the human path. Mitigation: every change gated so default/unset
  `VEXOS_ASSUME_YES` and empty `update` params reproduce today's exact behavior; verified
  manually per the handoff doc's verification commands.
- Risk: `vexportalModule` breaking evaluation if `inputs.vexportal.nixosModules.default`
  doesn't exist yet upstream. Mitigation: this is Task 5's explicit ask; if the flake
  input fails to lock/evaluate, that surfaces immediately in `nix flake show --impure`
  during Phase 3 review, and is reported rather than worked around.
