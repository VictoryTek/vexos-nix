# Review: rdp_keyring_selfheal

## Change Summary

- `modules/remote-desktop.nix`: insert a `gnome-keyring-daemon --unlock --replace`
  step (empty stdin password, same session-bus env as the existing `grdctl` calls)
  immediately before the `grdctl` calls. Adds `pkgs.gnome-keyring` to the service
  `path`. Updated header comment to describe the self-heal mechanism, removing the
  now-obsolete "delete login.keyring once, reboot" prerequisite.
- `modules/gnome.nix`: updated the comment above
  `security.pam.services.gdm-autologin.enableGnomeKeyring = true` to stop claiming
  the manual keyring-reset step is required for RDP — it isn't anymore.

## Specification Compliance

Matches `rdp_keyring_selfheal_spec.md` exactly: unlock step placed after the
session-bus wait loop, before the three existing `grdctl` calls, using the same
`bus`/`runtime`/`home` variables. No `set -e` added (script already omits it; `|| true`
added explicitly on the new line for clarity even though the script has no `set -e`
to trip). No PAM changes. No `lib.mkIf` guards added — Option B pattern preserved,
module still imported unconditionally by the three roles that need it.

## Best Practices

- `gnome-keyring-daemon --unlock` is the documented, standard mechanism for
  non-interactive keyring unlock/create (verified via ArchWiki and the Debian
  manpage) — not a hack against internal file format.
- `--replace` correctly targets the already-running autologin session's daemon via
  the same `DBUS_SESSION_BUS_ADDRESS` used for the `grdctl` calls, so the live
  session's keyring references get repointed rather than leaving a divergent second
  daemon instance.
- Idempotent: safe on every `graphical.target` start, not just first-boot.
- Failure mode (real non-empty keyring password) is non-destructive and non-fatal.

## Consistency

- No new `lib.mkIf` role/display/gaming guards introduced.
- Naming and style match the rest of the file (same `escapeShellArg` usage, same
  comment density).

## Security

- No new secret exposure. The empty-password unlock attempt sends `printf ''` over
  stdin to a `runuser`-scoped process — no plaintext RDP password involved in this
  step (that's a separate, pre-existing `grdctl set-credentials` call).
- Does not weaken any existing protection: a keyring that already has a real
  password is left untouched on failed unlock.

## Build Validation

Environment note: this review was performed on the Windows dev checkout, where the
`nix` CLI is not installed — same limitation noted in the prior
`rdp_unified_system_service_review.md`. The following were run here:

- `git ls-files hardware-configuration.nix` → empty. ✔ Not tracked.
- `git diff -- configuration-*.nix | grep -i stateVersion` → empty. ✔ Untouched.
- No new flake inputs added. ✔ `follows` check N/A.

**Not run here (require a NixOS host) — must be run before pushing:**
- `nix flake show --impure`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (touches server role)
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — N/A, this
  module is not imported by headless-server (no display/GNOME session there).

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | — | Not build-verified in this environment |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | Not run (no `nix` on this host) | Pending |

## Verdict

**NEEDS_REFINEMENT — blocked only on build validation, which requires a NixOS host.**
Code changes are complete and self-consistent. Cannot declare PASS per CLAUDE.md
Phase 3 until `nix flake show --impure` and the required `nixos-rebuild dry-build`
targets are run and confirmed passing. This must be done on the actual VexOS machine
before push.
