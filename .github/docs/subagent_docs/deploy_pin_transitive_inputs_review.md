# Review — `deploy_pin_transitive_inputs`

Spec: `.github/docs/subagent_docs/deploy_pin_transitive_inputs_spec.md`
Date: 2026-08-05
Result: **PASS**

## Files reviewed

- `pkgs/vexos-deploy/default.nix` (new)
- `modules/nix.nix` (modified)
- `justfile` (modified)

## 1. Specification compliance

| Spec item | Status |
|---|---|
| §4.1.1 variant guard | Implemented, message identical to the previous recipe's |
| §4.1.2 lock backup | `cp "$LOCK" "$BAK"` before any mutation |
| §4.1.3 update only `vexos-nix` | `nix flake update vexos-nix --flake "path:$FLAKE_DIR"` |
| §4.1.4 resolve vexos-nix node | Guarded — refuses to touch a lock with no `vexos-nix` input |
| §4.1.5 restore `locked`, pair by `original` | Implemented with canonicalisation + ambiguity skip |
| §4.1.6 verify nixpkgs rev unchanged | Implemented; restores and exits 1 on mismatch |
| §4.1.7 switch | `nixos-rebuild switch --impure` — flags unchanged from prior recipe |
| §4.1.8 remove backup on success | `rm -f "$BAK"` after switch |
| §4.1 restore on every failure path | `restore_lock` on update failure, rewrite failure, and pin-verification failure |
| §5.4 `pkgs/default.nix` untouched | Confirmed — no diff |

## 2. Behavioural verification

The jq rewrite was exercised against synthetic locks before packaging.

| Case | Expected | Observed |
|---|---|---|
| Normal deploy: upstream moved all four inputs | `vexos-nix` moves; nixpkgs / home-manager / nixpkgs-unstable held | PASS |
| Node-key renumbering (`nixpkgs` → `nixpkgs_2`) plus a new upstream input | live nixpkgs held at old rev; new input keeps new rev | PASS (this case **failed** under the initially implemented key-based pairing and drove the redesign) |
| `original` key order differs between the two locks | held | PASS — canonicalisation works |
| Ambiguous `original` in old lock (two different revs) | decline to pin, then step 6 aborts | PASS — left at new rev, so verification fails closed |
| No-op deploy (nothing moved upstream) | lock byte-identical | PASS |

Real-lock sanity check against `/etc/nixos/flake.lock` on the developer host: the
`vexos-nix` guard resolves, and the active-nixpkgs traversal returns
`04607e1165ac22c5fde6dcc54c9e0b3c0487c555`. That lock contains both `nixpkgs` and
`nixpkgs_2` and both `home-manager` and `home-manager_2`, confirming the renumbering
hazard is present in production and not merely theoretical.

## 3. Build validation

`nix flake check` was **not** used (FORBIDDEN COMMANDS). `sudo nixos-rebuild dry-build`
was unavailable in this session (no-new-privileges is set, so `sudo` cannot run), so
per-target evaluation used `nix eval --impure … .config.system.build.toplevel.drvPath`,
which CLAUDE.md documents as the CI-equivalent single-target check.

Because the new files are untracked, the git flake source cannot see them
(`error: path '…/pkgs/vexos-deploy' does not exist` under `.#`). Evaluation therefore used
`path:/home/nimda/Projects/vexos-nix`, which copies the working tree. **The files must be
staged before push** — see delivery notes.

| Check | Result |
|---|---|
| `nix flake show --impure` | PASS (exit 0) |
| `nix build` of `pkgs/vexos-deploy` standalone | PASS — `writeShellApplication` runs shellcheck at build time, so this clears the script |
| eval `vexos-desktop-amd` | PASS |
| eval `vexos-desktop-nvidia` | PASS |
| eval `vexos-desktop-vm` | PASS |
| eval `vexos-stateless-amd` | PASS |
| eval `vexos-htpc-amd` | PASS |
| eval `vexos-vanilla-amd` | PASS |
| eval `vexos-server-amd` | PASS (with CI's `networking.hostId = "cafebabe"` stub) |
| eval `vexos-server-intel` | PASS (same stub) |
| eval `vexos-headless-server-amd` | PASS (same stub) |

`modules/nix.nix` is a universal module, so all six roles were evaluated rather than only
the three desktop targets Phase 3 mandates. The server/headless-server roles assert against
the committed placeholder `networking.hostId` (`modules/zfs-server.nix:91`); `.github/workflows/ci.yml:153-172`
stubs it the same way, so the stub reproduces CI rather than bypassing a real check.
`modules/zfs-server.nix` is unmodified.

| Invariant | Result |
|---|---|
| `git ls-files hardware-configuration.nix` | empty — PASS |
| `system.stateVersion` unchanged | PASS — no diff in any `configuration-*.nix`; all six still declare it |
| New flake inputs declare `follows` | N/A — `flake.nix` unmodified, no inputs added |

## 4. Consistency (Module Architecture Pattern — Option B)

- No new `lib.mkIf` guards. The change adds one entry to an existing universal base
  module's `environment.systemPackages`, unconditional for every role that imports it.
- `pkgs.callPackage ../pkgs/vexos-deploy { }` matches the existing `vexos-update` call
  convention, deliberately bypassing the `pkgs.vexos` overlay namespace so `modules/nix.nix`
  stays overlay-independent for the vanilla role. Verified by the passing `vexos-vanilla-amd`
  evaluation.
- Naming and file layout mirror `pkgs/vexos-update/`.

## 5. Security

- No secrets, credentials, or network endpoints introduced.
- `mktemp` is created inside `/etc/nixos` (root-owned, mode 0755) rather than a
  world-writable directory, then `chmod 0644` and `mv` — same-filesystem, atomic, no
  symlink-swap window in `/tmp`.
- No new world-writable paths, no `curl | sh`, no privilege changes. The script runs under
  the same `sudo` the previous recipe used.
- Pre-existing divergence, unchanged and out of scope (spec §9): `deploy` uses
  `path:/etc/nixos` while `vexos-update` uses `git+file:///etc/nixos`, the latter chosen so
  untracked `secrets/` never enters the world-readable Nix store.

## 6. Performance

Adds two `jq` passes over a ~40-node JSON file — microseconds. The change removes an
unintended multi-hour kernel source build from the common path, which is the point.

## 7. Maintainability

The non-obvious parts each carry a comment explaining *why*: why a script is needed at all
(the `follows` chain), why only `locked` is restored (stickiness), why pairing is by
`original` (renumbering), and why `runtimeInputs` exists (`jq` absent on non-desktop roles).
The justfile recipe carries the same rationale so a reader does not have to open the package
to know why it is not a one-liner.

## 8. Findings

No CRITICAL issues. No RECOMMENDED changes outstanding.

One defect was found and fixed **during** implementation rather than being carried into
review: the first implementation paired lock nodes by node key and silently failed to hold
nixpkgs under key renumbering. It was caught by the synthetic test in §2, not by inspection.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 98% | A |
| Code Quality | 95% | A |
| Security | 97% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%)**

## Verdict

**PASS** — proceed to Phase 6 (Preflight).
