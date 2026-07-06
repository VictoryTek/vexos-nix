# L-08 — zfs-server.nix installs pkgs.zfs alongside the module-managed build — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-08_zfs_package_skew_spec.md`

## Modified Files

- `modules/zfs-server.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly:
   `environment.systemPackages` now references `config.boot.zfs.package`
   instead of the plain `pkgs.zfs` attribute, moved out of the
   `with pkgs; [...]` block (since it isn't a `pkgs.*` attribute) and
   concatenated via `++` with the remaining three `with pkgs;` entries
   (`gptfdisk`, `util-linux`, `pciutils`), which are untouched.

2. **Best Practices** — `config.boot.zfs.package` is the officially
   documented NixOS override point for the ZFS userland build
   (confirmed directly against the upstream module source at this
   repo's pinned nixpkgs rev); referencing it instead of a hardcoded
   `pkgs.zfs` is the standard way to stay correct under a future
   `boot.zfs.package` override, matching the same instinct this file
   already applies to `boot.kernelPackages` two blocks above.

3. **Consistency** — style matches the rest of the file: inline
   comments explaining *why*, not just what; `config`/`lib`/`pkgs` usage
   consistent with the module's existing `{ config, lib, pkgs, ... }:`
   argument list (already used for `config.networking.hostId` in the
   `assertions` block below).

4. **Maintainability** — comment explains the specific failure mode
   being avoided (divergent zfs userland/kernel-module pairing if
   `boot.zfs.package` is ever pinned), not just "use the option
   instead."

5. **Completeness** — the one cited line is the only place in the repo
   referencing `pkgs.zfs` (confirmed via grep) — no other module lists
   it.

6. **Performance** — no impact; same derivation is installed either
   way under current (unoverridden) configuration.

7. **Security** — no new vulnerabilities; removes a latent
   version-skew footgun (two different zfs userland builds coexisting
   in the closure with undefined PATH precedence) without introducing
   any new attack surface.

8. **API Currency** — verified `boot.zfs.package`'s definition and
   `environment.systemPackages` wiring directly against
   `nixos/modules/tasks/filesystems/zfs.nix` at this repo's pinned
   nixpkgs commit (`e4bae1bd10c9c57b2cf517953ab70060a828ee6f`, per
   `flake.lock`) rather than assuming from memory — option name,
   default, and semantics all current.

9. **Build Validation:**
   - Bracket/brace/paren balance check on the file: braces 5/5,
     brackets 6/6, parens 17/17 — consistent before/after the edit.
   - Manual read-through confirms valid Nix syntax: `[ config.boot.zfs.package ]
     ++ (with pkgs; [ ... ])` is a standard list-concatenation pattern,
     and `config` is already in scope and used elsewhere in this same
     file.
   - This session's environment has no `nix` binary (Windows host, no
     WSL2/Nix installed) — the vexos-nix-specific
     `nix flake show --impure` / `nixos-rebuild dry-build --flake
     .#vexos-server-amd` / `.#vexos-headless-server-amd` steps (required
     here since this change touches a server module) could not be
     executed in this session, consistent with the constraint noted in
     the L-06/L-07 reviews this session.
   - `git ls-files hardware-configuration.nix` → empty, unaffected.
   - No `system.stateVersion` change; no new flake inputs.
   - No FORBIDDEN COMMANDS used.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | Not run — Nix unavailable in this session's environment; syntax/bracket-balance verified instead | Pending |

**Overall Grade: A, pending real dry-build verification**

## Result

**PASS on all reviewable criteria.** Phase 6 (Preflight) — including the
mandatory `nixos-rebuild dry-build --flake .#vexos-server-amd` and
`.#vexos-headless-server-amd` this server-module change requires — could
not run in this session (no Nix on this Windows host). Per the pattern
established for L-06/L-07 this session, deferred to the user's NixOS
machine: please run
`sudo nixos-rebuild dry-build --flake .#vexos-server-amd` and
`.#vexos-headless-server-amd` (or `bash scripts/preflight.sh`, which
covers the desktop variants — the server-specific dry-builds are an
additional Phase 3 requirement for this change per CLAUDE.md) before
pushing.
