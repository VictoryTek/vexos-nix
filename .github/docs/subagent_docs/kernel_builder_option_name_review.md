# kernel-builder option name mismatch — review

## Specification Compliance
Matches spec exactly: `enable` and `disable` recipes now translate the
`kernel-builder` service id to the module's actual `kernelBuilder` option
attribute before constructing `OPTION`, mirroring the existing `arr`
special-case pattern already present in both recipes. No Nix module changes.

## Best Practices / Consistency / Maintainability
Two-line change per recipe, same shape in both places, comment explains why
the exception exists. No new abstraction, no unrelated refactor.

## Completeness
Verified via grep that `enable`/`disable` are the only two justfile recipes
that construct `vexos.server.<service>.enable` dynamically from `$SERVICE`
(all other `*_OPTION=` assignments in justfile are static, pre-known option
paths for sub-fields like `plexPass`, `appUrl`, etc. — unaffected). Verified
via grep across `modules/server/*.nix` that `kernelBuilder` is the only
camelCase exception among all `options.vexos.server.<name>` declarations —
no other service needs the same translation.

### Follow-up: `services` status display (found live, in production)

After the `enable`/`disable` fix landed and the user hand-repaired their
host's stale `/etc/nixos/server-services.nix` line, `just services` kept
showing `kernel-builder` as `✗` even though `just enable kernel-builder`
correctly reported "already enabled." Root cause: `services`'s own `_check`
helper ([justfile:1956-1967](justfile#L1956-L1967)) independently derives its
expected option name via `sed 's/-/_/g'` (kebab → snake_case), never
camelCase — a third, separate spot with the same class of bug, not covered
by the original spec. Fixed the same way: an explicit override for
`kernel-builder` → `kernelBuilder` before the `grep -qP` status check, one
line, mirroring the existing `arr` special-case already in the same
function. Purely cosmetic (status display only) — did not affect the actual
enable/disable state written to the file.

### Follow-up: `harmonia-info` false negative (unrelated root cause, found live)

Separately (not a `kernel-builder` name-mismatch case, but found in the same
debugging session): `just harmonia-info` reported "harmonia.service is not
running" even though the cache was verified live via direct
`curl http://localhost:5000/nix-cache-info` and `systemctl status
harmonia.socket` showing `Active: active (running)`. Root cause:
`services.harmonia.cache` (nixpkgs upstream module) is socket-activated —
`harmonia.socket` listens and only starts `harmonia.service` on demand, so
the `.service` unit is legitimately `inactive (dead)` while idle. The
recipe's guard at [justfile:3139](justfile#L3139) checked
`systemctl is-active harmonia` (the service), which is the wrong predicate
for a socket-activated unit and always fails when idle. Fixed by checking
`harmonia.socket` instead — that unit reflects whether the cache is
actually ready to accept connections, independent of whether the on-demand
service has been triggered yet.

## Security
No secrets, no permission changes.

## Build validation — performed via WSL

`nix` is not installed on the Windows host directly, but is available inside
WSL (Ubuntu 24.04), which has the repo checkout mounted at
`/mnt/c/Projects/vexos-nix`. Re-ran validation there:

- `nix flake show --impure` → PASS, flake structure valid, all
  `nixosConfigurations` outputs listed.
- WSL is a plain Ubuntu install (not NixOS) with no `/etc/nixos/vexos-variant`
  and no passwordless sudo, so `sudo nixos-rebuild dry-build` cannot run
  there either. Used the CI-equivalent substitute CLAUDE.md names for exactly
  this situation — `nix eval --impure
  ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"` —
  which forces full evaluation of the target's closure without building:
  - `vexos-desktop-amd` → evaluated to a `.drv` path ✓
  - `vexos-desktop-nvidia` → evaluated to a `.drv` path ✓
  - `vexos-desktop-vm` → evaluated to a `.drv` path ✓
  - `vexos-server-amd` → evaluated to a `.drv` path ✓ (server module in scope)
  - `vexos-headless-server-amd` → evaluated to a `.drv` path ✓ (server module
    in scope; same role as the host in the original error report)

  All five evaluated cleanly — the `vexos.server.kernel-builder` /
  `vexos.server.kernelBuilder` option-name mismatch that broke the user's
  rebuild does not reproduce for any of these closures using the fixed
  justfile logic (the module option name itself was never wrong; the
  fix is confirmed by these closures continuing to evaluate correctly
  now that the generator writing that option name is fixed).

- `bash scripts/preflight.sh` (full script, in WSL) → **PASSED, exit code 0.**
  - `[0/8]` nix 2.34.1 present ✓ (jq absent — WARN only)
  - `[1/8]` nix flake show ✓
  - `[2/8]` dry-build skipped — WARN, no `/etc/nixos/vexos-variant` on this
    WSL instance (expected on a non-VexOS host; not a failure)
  - `[3/8]` hardware-configuration.nix not tracked ✓
  - `[4/8]` system.stateVersion present in all 6 `configuration-*.nix` ✓
  - `[5/8]` flake.lock tracked ✓ (pinning/freshness sub-checks skipped, no jq)
  - `[6/8]` formatting check skipped, no nixpkgs-fmt (WARN only)
  - `[7/8]` secret/backend consistency — all HARD checks pass; one
    pre-existing WARN for a template placeholder string
    (`modules/server/vexboard.nix:90`, `"change-me-set-vexos.server.vexboard.secretFile"`)
    unrelated to this change
  - `[8/8]` `pkgs.vexos.vexos-update` builds, shellcheck passes ✓

## Recommendation
PASS. Both Phase 3 build validation and Phase 6 preflight were executed for
real (via WSL) and passed with exit code 0. No CRITICAL or unresolved issues.

Separately: anyone who already ran `just enable kernel-builder` before this
fix will have a stale `vexos.server.kernel-builder = { enable = true; };`
line in their host's `/etc/nixos/server-services.nix`. That file is not
tracked in this repo and must be corrected on the host directly, or via
`just disable kernel-builder && just enable kernel-builder` after pulling
this fix.
