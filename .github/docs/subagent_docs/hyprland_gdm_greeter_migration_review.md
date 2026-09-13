# Hyprland Greeter: ReGreet → GDM — Review

## Summary

Reviewed against the Phase 1 spec
(`hyprland_gdm_greeter_migration_spec.md`). All 7 implementation steps
completed as specified.

## Specification Compliance

All steps from the spec were implemented:
1. `modules/hyprland-greeter.nix` rewritten to GDM, ReGreet CSS/palette/SVG
   derivation removed.
2. `modules/branding-display.nix` GDM-logo gate extended to `["gnome"
   "hyprland"]`.
3. `modules/hyprland-desktop.nix` PAM service renamed `greetd` →
   `gdm-autologin`; stale comments rewritten.
4. `modules/gpu/vm.nix` render-node check ordering changed `greetd.service` →
   `display-manager.service`.
5. Stale "greetd ignores autoLogin" comments fixed in
   `modules/desktop-common.nix`, `modules/cosmic-desktop.nix`,
   `modules/gnome.nix`.
6. `flake.nix` comment updated (ReGreet → GDM).
7. `files/regreet/background.svg` deleted (orphaned; directory now removed).

`configuration-desktop.nix` inline comments (2 lines) also updated for
consistency — a natural extension of step 1/2, not a separate spec step, but
in scope (directly describes the files being changed).

## Best Practices / Consistency

- Matches `modules/gnome.nix`'s existing GDM pattern exactly
  (`services.displayManager.gdm.enable`, `systemd.services.display-manager.
  restartIfChanged = false`, `security.pam.services.gdm-autologin.
  enableGnomeKeyring`).
- No new `lib.mkIf` role/display/gaming guards added to a shared module —
  `modules/hyprland-greeter.nix` keeps its existing carve-out gate
  (`vexos.desktop.environment` — an option declared in this module tree, the
  standard toggleable-subsystem carve-out). `modules/branding-display.nix`'s
  gate changed from an equality check to `builtins.elem`, still the same
  single carve-out condition, not a new guard.
- Module Architecture Pattern (Option B) unaffected — no new files, no new
  role wiring.

## Completeness

All greetd/ReGreet references in `.nix` files are gone except two historical
mentions inside `modules/hyprland-greeter.nix`'s own header comment (recording
*why* GDM was chosen over the prior greeters) and one in `modules/gpu/vm.nix`'s
comment explaining the rename — both intentional, not functional. The
superseded `.github/docs/subagent_docs/regreet_greeter_migration_{spec,
review}.md` docs and `.github/docs/subagent_docs/hyprland_traditional_session_
spec.md` (an unrelated prior decision record) were left untouched — they are
historical records of past phases, not live configuration.

## Security

No secrets, no world-writable files, no plaintext credentials. Pure
display-manager/PAM/dconf wiring, identical in kind to the existing GNOME
role's GDM setup.

## Performance

No regression — GDM was already built and running for the GNOME role on every
desktop host; this reuses that same package/closure rather than adding a
second greeter stack. Net closure size for Hyprland hosts should shrink
slightly (ReGreet + cage + resvg-built asset dropped).

## Build Validation

`sudo nixos-rebuild dry-build` is unavailable in this execution environment
(`sudo: the "no new privileges" flag is set, which prevents sudo from running
as root` — a sandbox/container restriction, not a repo issue). Substituted
with the CI-equivalent safe command from the Test Commands list:

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | ✅ all outputs list, no eval errors |
| Full closure eval, default (gnome) branch | `nix eval --impure` toplevel drvPath — `vexos-desktop-amd` | ✅ `nixos-system-vexos-26.05.drv` |
| Full closure eval, default (gnome) branch | same — `vexos-desktop-nvidia` | ✅ produced |
| Full closure eval, default (gnome) branch | same — `vexos-desktop-vm` | ✅ produced |
| Full closure eval, **forced hyprland branch** (exercises the actual changed code — GDM greeter, hyprland-desktop PAM, branding-display gate) | `nix eval --impure` via `flake.nixosConfigurations.vexos-desktop-amd.extendModules { modules = [{ vexos.desktop.environment = "hyprland"; }]; }` toplevel drvPath | ✅ `nixos-system-vexos-26.05.drv` |
| Full closure eval, forced hyprland branch, **vm GPU variant** (exercises the `gpu/vm.nix` render-node ordering change) | same pattern on `vexos-desktop-vm`, plus direct inspection of `config.systemd.services.vexos-vm-render-node-check.before`, `config.services.displayManager.gdm.enable`, `config.security.pam.services.gdm-autologin.enableGnomeKeyring` | ✅ toplevel produced; `before = ["display-manager.service"]`; `gdmEnabled = true`; `pamGdmAutologin = true` |
| `hardware-configuration.nix` not committed | `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | `git diff -- configuration-*.nix \| grep stateVersion` | ✅ no changes |
| No new/changed flake inputs | `git diff -- flake.nix` | ✅ comment-only diff |

This is the same "forced-branch `nix eval`" substitution technique the prior
ReGreet migration used when `sudo nixos-rebuild dry-build` was unavailable
(see `regreet_greeter_migration_review.md`), and it directly proves the
changed Nix code (module option names, PAM service reference, `builtins.elem`
gate, systemd unit ordering) evaluates correctly — including forcing the
branch that a default-`gnome` dry-build would otherwise leave as an unforced
`mkIf` thunk.

**Caveat:** full evaluation is not the same guarantee as an actual build or a
live login-screen render (GDM autologin behavior, GDM's dconf gdm-profile
merge order, and the visual result can only be confirmed by rebooting a real
`vexos.desktop.environment = "hyprland"` host). This is a structural
limitation of the sandboxed execution environment, not a gap in the review.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (eval-verified; live-boot unverified — sandbox limitation) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (eval substitute used in place of unavailable `sudo dry-build`) |

**Overall Grade: A (99%)**

## Result

**PASS.** No CRITICAL issues. No refinement cycle needed.
