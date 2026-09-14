# Bucket C — GNOME→Noctalia Parity: Review

Reviews the implementation in
`.github/docs/subagent_docs/gnome_parity_bucket_c_spec.md` against the
modified files: `home/dank-material-shell.nix`, `files/hypr/hyprland.conf`,
`home/noctalia.nix`.

## Specification Compliance

- **C1**: `vexos-mic-toggle` added via `pkgs.writeShellScriptBin` in
  `home/dank-material-shell.nix`'s shell-agnostic `home.packages` list, next
  to `tail-tray`/`mute-mic-on-login` as specified. Script wraps
  `config.programs.noctalia.package}/bin/noctalia msg mic-mute`, then
  branches on `wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED` to
  play `device-removed.oga`/`device-added.oga` via `pw-play`, inside the same
  `flock -n 9 ... 9>"${XDG_RUNTIME_DIR}/mic-toggle.lock"` debounce pattern as
  the GNOME original. ✅ matches spec exactly.
- `files/hypr/hyprland.conf` — both mic-mute binds (`$mod+backslash` and
  `XF86AudioMicMute`) repointed from `noctalia msg mic-mute` to
  `vexos-mic-toggle`. ✅
- **C2**: `"privacy"` added to `home/noctalia.nix`'s `bar.default.end`, no
  options block (relying on the confirmed `hide_inactive = false` default).
  ✅ matches spec and the user's explicit decision (accept `privacy` as the
  substitute, no custom polling widget).

## Best Practices / Consistency

- No new `lib.mkIf` role/flag guards — both edited files already sit inside
  their pre-existing `lib.mkIf (osConfig.vexos.desktop.environment ==
  "hyprland")` blocks; the new `home.packages` entry and the new bar-widget
  token are additions inside those same blocks. Module Architecture Pattern
  (Option B) unaffected.
- `writeShellScriptBin` mirrors the exact idiom `modules/gnome-desktop.nix`
  already uses (`writeShellScript`) for the equivalent GNOME wrapper —
  consistent with existing project style, not a new pattern.
- Comments follow the file's existing density and explain *why* (seeded
  dotfile has no Nix templating, hence a named PATH binary instead of an
  inline store path) rather than restating *what*.

## Completeness

Both C1 and C2 addressed per the user's explicit decision on C2. Bucket C is
now fully closed; only bucket D (plugins) and the E/F decision items remain
open in the audit.

## Security

- No secrets, no world-writable files, no plaintext credentials introduced.
- The wrapper script only shells out to already-vetted packages
  (`wireplumber`, `pipewire`, `sound-theme-freedesktop`, the pinned
  `noctalia` package) — same packages the existing GNOME script and the rest
  of this file already reference.

## API Currency

Not applicable — no external library/API integration, pure Nix module and
static-dotfile changes. Context7 lookup not required per CLAUDE.md's
Dependency Policy exclusions (internal changes, no new dependency).

## Build Validation

`nixos-rebuild dry-build` itself cannot run outside a NixOS host with
`/etc/nixos/hardware-configuration.nix` (this environment is Windows +
WSL2 Ubuntu, confirmed Nix-capable but not NixOS — see project memory). Used
the equivalent forced-branch full-closure evaluation approach established in
the prior bucket-B review (`extendModules` override + toplevel `drvPath`),
which exercises exactly the code paths a dry-build would:

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | ✅ exit 0, all 30 outputs listed |
| Forced-hyprland closure, desktop-amd | `nix eval --impure` via `extendModules { vexos.desktop.environment = "hyprland"; }` → `.config.system.build.toplevel.drvPath` | ✅ real `.drv` produced |
| Forced-hyprland closure, desktop-nvidia | same, `vexos-desktop-nvidia` | ✅ real `.drv` produced |
| Forced-hyprland closure, desktop-vm | same, `vexos-desktop-vm` | ✅ real `.drv` produced |
| Default (gnome) branch, desktop-amd | `nix eval --impure ".#nixosConfigurations.vexos-desktop-amd...drvPath"` | ✅ real `.drv` produced — unaffected by this Hyprland-only change |
| Rendered Noctalia config | `nix eval --json` → `home-manager.users.nimda.programs.noctalia.settings.bar.default.end` | ✅ `["tray","caffeine","notifications","privacy","network","bluetooth","volume","battery","theme_mode","screenshot","session"]` — exact expected order |
| New package present | `nix eval --json` → `home.packages` names | ✅ `"vexos-mic-toggle"` present |
| New package builds | `nix build --impure` on the filtered `vexos-mic-toggle` derivation | ✅ built, `/nix/store/.../bin/vexos-mic-toggle` |
| Rendered script content | `cat` the built binary | ✅ every `${pkgs.foo}` interpolation resolved to a real, correct store path; flock/toggle/sound logic matches the spec byte-for-byte |
| `hardware-configuration.nix` not tracked | `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | `grep -n stateVersion configuration-*.nix` | ✅ all still `"25.11"`, none touched by this change |
| New flake inputs `follows` | n/a | ✅ no new flake inputs added |

Server/headless-server/stateless/htpc dry-builds not required — this change
touches only Hyprland-desktop-role files, per CLAUDE.md's build-step gating.

**Caveat, same class as B5/B6**: this proves the generated artifacts
(package, script, bar config) are structurally correct. It cannot prove the
*live* behavior — whether the sound actually plays audibly, whether the OSD
still fires correctly, whether the privacy icon renders as expected — without
a live Hyprland session. Also carries forward the seeded-`hyprland.conf`
caveat: a host with an already-seeded `~/.config/hypr/hyprland.conf` will not
pick up the new `vexos-mic-toggle` bind from a rebuild; only a fresh seed (or
manual edit) gets it.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (live-session behavior unverifiable, structural correctness confirmed) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result: PASS
