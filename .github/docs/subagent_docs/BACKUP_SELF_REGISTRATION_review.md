# Review — Decentralized, self-registering backup path registration (Part 1)

Spec: `.github/docs/subagent_docs/BACKUP_SELF_REGISTRATION_spec.md`

## Scope of change

48 files, +248 / −98. One rewritten module (`backup.nix`) and 47 service
modules each gaining a `vexos.server.backup.servicePaths.<name>` registration
inside their own `config = lib.mkIf cfg.enable` block.

No container definition, port, volume, environment variable, tmpfiles rule, or
systemd unit was modified in any module. Verified by diff inspection: every
changed hunk in a service module is a pure insertion of the registration
attribute (plus its explanatory comment where one was carried over from the old
central table).

## Validation performed

`nixos-rebuild dry-build` is **not runnable on this workstation** — it requires a
NixOS host with `/etc/nixos/hardware-configuration.nix`; this is Windows 11 with
Nix available only inside WSL. Validation was performed as follows.

### 1. Syntax — PASS

`nix-instantiate --parse` over all 67 files in `modules/server/`: 0 failures.

### 2. Mechanism evaluation — PASS

An isolated `nixosSystem` harness over a 13-module subset, pinned to the exact
`flake.lock` nixpkgs rev (`e4bae1bd`), with restic and 9 services enabled.

Resulting `services.restic.backups.main.paths`:

```
/var/lib/grimmory/dump
/var/lib/grimmory/books
/var/lib/homepage
/var/lib/joplin-server/dump
/var/lib/mealie
/var/lib/docker/volumes/npm-data/_data
/var/lib/docker/volumes/npm-letsencrypt/_data
/var/lib/traefik
/var/lib/docker/volumes/uptime-kuma-data/_data
/var/lib/vaultwarden
```

Cross-module `attrsOf` merging works; the enable-filter behaves as the old
central table did.

### 3. Assertion negative control — PASS

Re-evaluated the same config with `mealie`'s registration force-removed. The
assertion fired with the intended message, naming `mealie`. Without this control
a vacuously-true assertion would have looked identical to a working one.

`dozzle` was enabled throughout and correctly did **not** trip the assertion,
confirming the `noBackupNeeded` escape hatch works.

### 4. Preflight — PASS (exit 0)

`bash scripts/preflight.sh` under WSL: `Preflight PASSED — safe to push.`
Stage `[2/8]` (dry-build) self-skipped with a warning, as designed for non-NixOS
hosts. Stage `[3/8]` confirmed `hardware-configuration.nix` is untracked; stage
`[4/8]` confirmed `system.stateVersion` unchanged in all `configuration-*.nix`.

### 5. Git state — verified, not assumed

`git log origin/main..HEAD` returns empty: `main` is fully pushed. All changes
described here are working-tree only and uncommitted.

## Pre-existing issue found (NOT caused by this change)

`modules/server/harmonia.nix:98` sets `services.harmonia.cache.*`. At the
nixpkgs rev pinned in `flake.lock` (`e4bae1bd`), that option does not exist —
`services.harmonia` is still flat there:

```
{ hasCache = false; keys = [ "enable" "package" "settings" "signKeyPath" "signKeyPaths" ]; }
```

The `.cache` / `.daemon` split is a later nixpkgs change. Any config importing
`modules/server/default.nix` therefore fails to evaluate with
`The option 'services.harmonia.cache' does not exist`, before reaching anything
in this change. This is why validation used a targeted module subset rather than
the full `default.nix`. It is untouched by this work and needs its own fix
(either bump the pin or write against the flat option set).

## Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | INFO | `homepage`'s carried-over path `/var/lib/homepage` does not match its actual state location (named volume `homepage-config:/app/config`) | Left unchanged per spec §6; raised for user decision |
| 2 | INFO | `stirling-pdf` has named volumes `stirling-pdf-data`/`stirling-pdf-config` but is classified `noBackupNeeded` | Left as user-specified; raised for confirmation |
| 3 | INFO | `vexos.server.storage.{mergerfs,snapraid}` sit one level deeper than the assertion walks and are not covered | Raised; SnapRAID content files may warrant coverage |
| 4 | INFO | `harmonia.nix` pre-existing eval break (above) | Out of scope; reported |

No CRITICAL or RECOMMENDED findings. Line endings were preserved per-file
(CRLF files stayed CRLF), so no spurious whitespace churn was introduced.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A− |

Build Success is marked down only because full-config `dry-build` could not be
run here (no NixOS host, plus the pre-existing `harmonia` blocker). Mechanism
evaluation and preflight both passed.

**Overall Grade: A (97%)**

## Result

**PASS** — no refinement cycle required.
