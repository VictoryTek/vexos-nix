# L-13 — flatpak-install-apps exits 0 on failure — Review

Status: Phase 3 (Review & Quality Assurance)
Spec: `.github/docs/subagent_docs/L-13_flatpak_failure_visibility_spec.md`

## Modified Files

- `modules/flatpak.nix`
- `modules/gnome-flatpak-install.nix`

## Review Against Spec

1. **Specification Compliance** — matches the spec exactly: a single
   `vexos-notify "..." "VexOS Flatpak"` call added to each file's
   `FAILED`-branch, after the existing `.last-failed-install` marker
   write, with no change to exit-code behavior or `serviceConfig`/
   `unitConfig`.

2. **Best Practices** — reused this repo's own already-shipped
   `vexos-notify`/ntfy infrastructure (H-17) rather than the plan's more
   generic literal suggestions (`systemd-cat`, a marker unit) — this is
   the same mechanism already wired for backup failures, so failures
   across the system now surface through one consistent channel instead
   of introducing a second, different observability mechanism.

3. **Consistency** — matches the exact call shape already used at
   `pkgs/vexos-update/default.nix:249`
   (`vexos-notify "message" ["title"]` as a bare command); distinct,
   descriptive messages per file so an operator can tell the base app
   stream from the GNOME-specific one apart.

4. **Maintainability** — no new options, no new systemd unit shape;
   a future reader sees the same `vexos-notify` idiom already used
   elsewhere in the repo rather than a one-off mechanism.

5. **Completeness** — applied to both `flatpak.nix` (the file the plan
   cited) and `gnome-flatpak-install.nix` (the sibling this session's
   own L-09 work made structurally identical, with the same "exit 0 on
   failure" gap) — confirmed via grep no third `FAILED`-branch flatpak
   install pattern exists elsewhere in the repo.

6. **Performance** — negligible; one additional `curl` (or no-op, if
   `vexos.notify.ntfyUrl` is unset) only on the already-rare failure
   path.

7. **Security** — no new vulnerabilities; reuses the existing
   `vexos-notify` script and its existing auth (`tokenFile`) handling
   unchanged.

8. **API Currency** — n/a, no external dependency; confirmed directly
   (rather than assumed) that `vexos-notify` is reachable as a bare
   command from these systemd-executed scripts by checking the actual
   evaluated `environment.systemPackages` closure for
   `vexos-desktop-amd`, which includes `vexos-notify` — matching how
   `pkgs/vexos-update/default.nix` already relies on ambient
   `/run/current-system/sw/bin` PATH for the same call, without adding
   it to either unit's own `path = [...]`.

9. **Build Validation** — via WSL2 Ubuntu (Nix 2.34.1, mounted repo at
   `/mnt/c/Projects/vexos-nix`):
   - Bracket/brace balance: `flatpak.nix` 19/19, `gnome-flatpak-install.nix`
     17/17.
   - `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm` →
     all PASS.
   - Directly evaluated
     `nixosConfigurations.vexos-desktop-amd.config.systemd.services.flatpak-install-apps.script`
     and confirmed the exact `vexos-notify "..."` call appears verbatim
     in the real generated unit script (not just inferred from the
     Nix source diff).
   - Directly evaluated `environment.systemPackages` for the same
     config and confirmed `vexos-notify` is present in the resulting
     closure, confirming the ambient-PATH assumption the fix depends
     on is correct, not just assumed.
   - Ran the full `bash scripts/preflight.sh` → **exit 0, "Preflight
     PASSED — safe to push."** Same pre-existing, expected WARNs as
     every prior review this session. Stage `[8/8]` passed.
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
| Build Success | 100% — evaluations, generated-script inspection, closure check, and full `preflight.sh` all passed via WSL2 | A |

**Overall Grade: A (100%)**

## Result

**PASS.** Phase 6 (Preflight) has genuinely run and passed for this
change, and both the generated script content and the PATH-resolution
assumption it depends on were directly confirmed against a real
evaluated closure. Safe to commit and push.
