# L-09 — gnome-flatpak-install installs all apps in one transaction — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-09_gnome_flatpak_install_transaction_spec.md`

## Modified Files

- `modules/gnome-flatpak-install.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly: the single
   `flatpak install ... ${lib.concatStringsSep ...}` transaction was
   replaced with a `FAILED=0` / per-app `for app in ...; do ...; done`
   loop mirroring `modules/flatpak.nix:148-160`, and the stamp
   write/cleanup is now gated on `[ "$FAILED" -eq 0 ]`, writing
   `/var/lib/flatpak/.gnome-last-failed-install` on the failure branch
   (distinct from `flatpak.nix`'s own `.last-failed-install` marker, as
   planned, since both services coexist on the same GNOME-role hosts).

2. **Best Practices** — mirrors the sibling module's already-accepted
   pattern (skip-if-installed check, per-app try/warn, failure flag)
   rather than inventing a new shape; keeps the pre-existing
   `extraRemoves` block untouched since it was already per-app-isolated
   and not part of this bug.

3. **Consistency** — identical loop/flag idiom and comment style to
   `flatpak.nix`; variable naming (`FAILED`, `$app`) matches exactly.

4. **Maintainability** — the failure path is now self-documenting via
   the same explanatory comment `flatpak.nix` uses (why exit 0 instead
   of 1), so a future reader doesn't have to cross-reference the other
   file to understand the design.

5. **Completeness** — verified via `git diff` that no other
   `flatpak install` call in this file was affected (there is only the
   one), and that `unitConfig`/`serviceConfig` were left untouched per
   the spec (they were noted as out of scope — `Restart=on-failure`
   remains inert either way, matching the sibling module's own already-
   shipped behavior, not a regression from this change).

6. **Performance** — no meaningful impact; installing N apps
   sequentially rather than as one multi-arg invocation was already
   `flatpak.nix`'s accepted tradeoff for per-app failure isolation.

7. **Security** — no new vulnerabilities; no change to trust boundaries
   (still Flathub-only, `--noninteractive --assumeyes`, unchanged).

8. **API Currency** — n/a, no external dependency change; `flatpak`
   CLI usage (`list`, `install`, `uninstall`) is identical to the
   already-working sibling module.

9. **Build Validation** — via WSL2 Ubuntu (Nix 2.34.1, mounted repo at
   `/mnt/c/Projects/vexos-nix`), same approach used for L-08:
   - Bracket/brace/paren balance on the file: braces 17/17,
     brackets 12/12, parens 12/12.
   - `nix flake show --impure` → PASS, no errors.
   - `nix eval --impure ...toplevel.drvPath` for every
     `nixosConfigurations.*` that actually imports this module
     (confirmed via grep: `gnome.nix` imports
     `gnome-flatpak-install.nix`, consumed by `gnome-desktop.nix`,
     `gnome-htpc.nix`, `gnome-server.nix`, `gnome-stateless.nix`):
     - `vexos-desktop-amd` → PASS
     - `vexos-desktop-nvidia` → PASS
     - `vexos-desktop-vm` → PASS
     - `vexos-htpc-amd` → PASS
     - `vexos-stateless-amd` → PASS
     - `vexos-server-amd` (GUI server variant; required the same
       `extendModules`-injected throwaway `hostId` as L-08, since
       `zfs-server.nix`'s placeholder-rejection assertion applies here
       too — no on-disk changes) → PASS
   - Ran the full `bash scripts/preflight.sh` → **exit 0, "Preflight
     PASSED — safe to push."** Same pre-existing, expected WARNs as
     every prior review this session (missing optional `jq`/
     `nixpkgs-fmt`/`gitleaks`; the known `vexboard.nix` placeholder
     WARN). Stage `[8/8]` (`vexos-update` build/shellcheck) passed.
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
| Build Success | 100% — `nix flake show`, 6 target evaluations, and full `preflight.sh` all passed via WSL2 | A |

**Overall Grade: A (100%)**

## Result

**PASS.** Phase 6 (Preflight) has genuinely run and passed for this
change, including every role that actually consumes this module. Safe
to commit and push.
