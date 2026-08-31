# Hyprland / DMS — double top bar + start-hyprland warning

## Phase 1 — Research & Specification

### Current state analysis

The Hyprland desktop was switched to DankMaterialShell (DMS) in commit `6b9543c`.
On a live boot two defects appear:

1. **Two identical DMS top bars** stacked at the top of the screen.
2. A red notification on every boot:
   `Hyprland was started without start-hyprland. This is highly not recommended
   unless you are in a debugging environment.`

#### Defect 1 — double bar

The DMS shell is being launched twice:

* `home/dank-material-shell.nix` sets
  `programs.dank-material-shell.systemd.enable = true`. The upstream Home-Manager
  module (`distro/nix/home.nix`, rev `069ddab`) creates
  `systemd.user.services.dms` with
  `ExecStart = "<dms> run --session"` and `Install.WantedBy = graphical-session.target`.
  Under UWSM (enabled in `modules/hyprland-desktop.nix`) `graphical-session.target`
  is activated, so this service starts one shell instance.
* `files/hypr/hyprland.conf` (seeded once to `~/.config/hypr/hyprland.conf` on
  first boot) additionally has `exec-once = dms run`, which starts a **second**
  instance.

Result: two `dms` processes, two bars. Upstream ships a dedicated test
(`distro/nix/tests/nixos-service-start-module.nix`) for the systemd-service start
path — it is the supported mechanism. The `exec-once` line is the duplicate.

#### Defect 2 — start-hyprland warning

Hyprland (0.52.2 in nixos-26.05) shows this warning whenever the `Hyprland`
binary is executed directly rather than through the `start-hyprland` wrapper
introduced upstream. With `programs.hyprland.withUWSM = true` the session is
launched by UWSM, which execs the compositor binary directly
(`programs.uwsm.waylandCompositors.hyprland.binPath` →
`${hyprland.package}/bin/Hyprland`). This is a known, still-open nixpkgs issue
(NixOS/nixpkgs#476375, hyprwm/Hyprland discussion #12661): UWSM and
`start-hyprland` are alternative session managers, not complementary. Pointing
`binPath` at `start-hyprland` causes UWSM to mis-set `XDG_CURRENT_DESKTOP` to
`start-hyprland`, which breaks portals — so that is *not* the fix.

The warning is purely advisory. Hyprland provides a config option to silence it:
`misc:disable_watchdog_warning` (bool, default `false`) —
"Disables the warning about not using start-hyprland"
(hyprland-wiki `content/configuring/core/config-options.md`).

### Problem definition

`files/hypr/hyprland.conf` (the once-seeded user config) must:
* not start a second DMS instance;
* silence the advisory start-hyprland warning that UWSM triggers by design.

### Proposed solution

Edit `files/hypr/hyprland.conf` only. No Nix module changes — the duplication and
the warning both originate in this seed file's contents, not in evaluation.

1. Remove the line `exec-once = dms run`. The systemd user service
   (`programs.dank-material-shell.systemd.enable = true`, already set) is the
   single supported launcher. Keep the `cliphist` `exec-once` line.
2. Add a `misc { disable_watchdog_warning = true }` block, with a comment
   explaining it is the expected state under UWSM.

### Why not the alternatives

* *Disable the systemd service, keep `exec-once`* — rejected: the systemd path is
  upstream-recommended (bound to `graphical-session.target`, `restartIfChanged`
  handling, dedicated upstream test). `exec-once` has none of that.
* *Point UWSM `binPath` at `start-hyprland`* — rejected: breaks
  `XDG_CURRENT_DESKTOP` / portals per nixpkgs#476375.
* *`misc:disable_xdg_env_checks`* — not needed; only the watchdog warning is shown.

### Scope of effect / migration

`files/hypr/hyprland.conf` is copied to `~/.config/hypr/hyprland.conf` **only if
that file does not already exist** (`home.activation.seedHyprlandConf`). On the
already-installed machine the user must either:
* edit `~/.config/hypr/hyprland.conf` directly (delete the `dms run` line, add the
  `misc` block), or
* delete `~/.config/hypr/hyprland.conf` and rebuild to re-seed the corrected copy.

New installs pick up the fix automatically.

### Dependencies

None. No new flake inputs, no new packages. No Context7 libraries involved
(static dotfile edit).

### Risks and mitigations

| Risk | Mitigation |
|------|------------|
| systemd `dms.service` fails to start on a non-UWSM session, leaving no bar | Non-UWSM Hyprland session already yields no shell (documented in `modules/hyprland-desktop.nix`); users are instructed to pick the UWSM session. No regression. |
| User already edited their seeded config | Seed file is never re-copied over an existing file; their live edits are untouched. Migration note covers the manual path. |
| Future Hyprland renames `disable_watchdog_warning` | Unknown key in `hyprland.conf` is a non-fatal parse warning, not a boot failure. |
