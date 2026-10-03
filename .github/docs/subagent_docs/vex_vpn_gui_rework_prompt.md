# Prompt: rework vex-vpn into the GUI for vexos-vpn

> Paste everything below the line into Claude Code, started in `~/Projects/vex-vpn`.
> Prerequisite: the vexos-nix `vexos-vpn` backend (modules/vpn.nix, pkgs/vexos-vpn) is merged and
> installed on the machine you test on.
> After vex-vpn is done and pushed, vexos-nix adds it as a flake input and installs it from
> `modules/vpn.nix` (that integration is done in the vexos-nix repo, not by this prompt).

---

Rework vex-vpn from a "universal VPN client" into the GTK4/libadwaita GUI for the **vexos-vpn** backend that now ships in vexos-nix. The GUI must give the user **full control of the VPN and kill switch, including entering the PIA username and password**. The `vexos-vpn` CLI / `just vpn-*` recipes remain the backup. Follow this repo's CLAUDE.md workflow (spec → implement → review → preflight). Write the Phase 1 spec first and stop for my approval before deleting anything.

## Background

vex-vpn currently has its own VPN backends (`src/backend/{openvpn,wireguard}.rs`), config parsers (`src/parser/`), a profile model (`src/profile.rs`, `ui_profiles.rs`, `ui_import.rs`), a root helper (`src/bin/helper.rs`, `src/helper.rs`), an iptables kill switch (`nix/module-gui.nix`), and a vendored systemd-networkd PIA backend (`nix/module-vpn.nix`). All of that is now replaced by vexos-vpn.

vex-vpn must **never** touch the network, firewall, or VPN configs, and must never store credentials. The GUI runs as the normal user; every privileged action goes through systemd (polkit) or `pkexec vexos-vpn …`.

## Full-control checklist (every item must be reachable from the GUI)

| Action | How the GUI does it |
|---|---|
| Sign in (enter PIA username + password) | GUI dialog with username and password fields, then `pkexec vexos-vpn login --stdin`. Write `"<user>\n<pass>\n"` to the child's **stdin** (never argv, never env, never disk). Polkit shows the admin password prompt. Zero the buffers after writing. |
| Change credentials | Same dialog, pre-titled "Change PIA account". |
| Sign out | `pkexec vexos-vpn logout` (removes credentials, disconnects), behind a confirm dialog. |
| Test login | `pkexec vexos-vpn selftest`. Show its stdout; it prints OK/FAILED only, never secrets. |
| Connect / disconnect / reconnect | `StartUnit` / `StopUnit` / `RestartUnit` on `vexos-vpn.service` |
| Choose region or "Automatic (fastest)" | `StartUnit("vexos-vpn-region@<id>.service", "replace")`, with `auto` as the id for automatic |
| Choose protocol (WireGuard / OpenVPN backup) | `StartUnit("vexos-vpn-protocol@wireguard.service")` / `…@openvpn.service` |
| Kill switch on / off | `StartUnit` / `StopUnit` on `vexos-killswitch.service`. In `always` mode (stateless), off triggers a polkit password prompt and lasts until reboot. Handle "auth cancelled" gracefully. |
| Refresh PIA server list | `pkexec vexos-vpn refresh` |
| See everything | `vexos-vpn status --json` and `vexos-vpn regions --json` (below) |

Show these read-only, with a note "set in your vexos NixOS config":
- `autoconnect` (connect at boot)
- `killswitch_mode` (`off`, `manual` or `always`)

When `credentials_editable` is false, the credentials are managed by sops/NixOS. Disable Sign in / Sign out and say why.

When `logged_in` is false, the main page must lead with a prominent "Sign in to PIA" call to action.

## Backend contract (source of truth: vexos-nix `modules/vpn.nix` and `pkgs/vexos-vpn/vexos-vpn.sh`; read them)

**Read state.** Poll `vexos-vpn status --json` (unprivileged; about every 2 s while the window is visible, about every 10 s for the tray), or watch `/run/vexos-vpn/status.json` with inotify and still run `status --json` to read it. Fields:
- `state`: `connected | connecting | disconnected | error`
- `protocol`, `region`, `region_name`, `server_cn`, `endpoint_ip`, `interface`, `since` (ISO 8601), `last_error`
- `rx_bytes`, `tx_bytes`
- `killswitch` (bool), `killswitch_mode` (`off | manual | always`)
- `protocol_setting`, `region_setting` (the user's choice, e.g. `auto`)
- `logged_in` (bool), `credentials_editable` (bool), `autoconnect` (bool)

No field contains secrets.

**Regions.** `vexos-vpn regions --json` returns `[{id, name, country, port_forward, latency_s|null}]`. Latency is populated after an auto connect.

**Systemd** via `org.freedesktop.systemd1.Manager` (keep the zbus proxies in `src/dbus.rs`). Polkit already allows the unit actions above for the `users` group; vexos-nix ships those rules.

**pkexec** at `/run/wrappers/bin/pkexec`, running `/run/current-system/sw/bin/vexos-vpn`. Spawn it asynchronously (never block the GTK main loop), capture stdout and stderr, and show stderr on a non-zero exit. Exit code 126 or 127 from pkexec means the auth was dismissed or failed; treat it as cancelled, not as an error.

## UI

- **Main page:**
  - large connect switch
  - state with region name and protocol
  - "connected since"
  - live rx/tx rates (diff the byte counters)
  - kill-switch status chip
  - `last_error` banner when `state == "error"`, with a "Sign in" action if the error is missing credentials
- **Region page:** searchable list from `regions --json` with latency. "Automatic (fastest)" pinned at the top; the current choice is marked.
- **Settings / Account page:**
  - protocol selector
  - kill-switch row (state, mode explanation, toggle)
  - account section (signed in / out, Sign in, Change, Sign out, Test login)
  - Refresh server list
  - read-only autoconnect and mode
- **Tray** (keep `src/tray.rs` / ksni): icon per state, connect/disconnect, kill switch on/off, current region, "Open vex-vpn".
- Keep the branding and history work if it still fits. Drop anything that only made sense for multi-provider profiles.

## Remove

- `src/backend/`, `src/parser/`, `src/profile.rs`, `ui_profiles.rs`, `ui_import.rs`, `src/bin/helper.rs`, `src/helper.rs`
- NetworkManager D-Bus code in `src/dbus.rs`
- `nix/module-vpn.nix`
- the iptables kill switch, helper and polkit bits in `nix/module-gui.nix`
- `nix/polkit-vex-vpn.policy`

## Flake outputs (what vexos-nix will consume)

vexos-nix will add `vex-vpn.url = "github:victorytek/vex-vpn"` with `inputs.nixpkgs.follows = "nixpkgs"`, and install the GUI automatically on every role that imports its `modules/vpn.nix`. Provide exactly:

- `packages.x86_64-linux.default`: the GUI. Install the binary, a `.desktop` file (`Categories=Network;`), and the icon into the standard `share/` paths, so GNOME and Hyprland launchers find it with no extra config.
- `overlays.default`: adds `pkgs.vex-vpn`.
- `nixosModules.default`: **only** `programs.vex-vpn.enable` (installs the package) and `programs.vex-vpn.tray.autostart` (default `true`; an XDG autostart entry or a `systemd.user` service bound to `graphical-session.target` that starts the tray). **No polkit rules, no system services, no firewall.** It must not declare anything named `vexos-vpn*` or `vexos-killswitch*`.
- The flake must build against the vexos-nix nixpkgs (NixOS 26.05) via `follows`. Don't pin a different nixpkgs for the build output, and keep the crane/rust-overlay inputs following `nixpkgs` where possible.

## Constraints

- No root in-process, no netlink/nftables/iptables, no file writes outside `$XDG_CONFIG_HOME/vex-vpn` (UI preferences only). Never log credentials.
- If `vexos-vpn` is not on `PATH`, show a clear "vexos-vpn backend not installed" page instead of crashing.
- Keep zbus/tokio/gtk4-rs versions as locked unless a change is required. Verify any API you touch with Context7.
- Tests:
  - replace `tests/config_integration.rs` with tests that parse captured `status --json` / `regions --json` fixtures, covering every `state` value, `logged_in` true/false, `credentials_editable` false, and a `null` latency
  - unit-test that the login path writes credentials to stdin and never to argv or env
- Update README: vex-vpn is the GUI for vexos-vpn; the `just vpn-*` / `vexos-vpn` CLI is the backup. Drop the tadfisher/flake instructions.

## Done when

- `cargo build`, `cargo clippy -- -D warnings`, `cargo test` and `nix build` all pass.
- On a vexos desktop, with no sudo prompt:
  - connect, disconnect, switch region (including Automatic) and switch protocol from the GUI and the tray
  - kill switch on/off
- On a vexos desktop, with the polkit admin prompt:
  - sign in with username and password typed into the GUI
  - test login
  - sign out
- On stateless: the kill-switch off toggle shows the polkit password prompt.
- With credentials removed, the main page shows the "Sign in to PIA" call to action and the error banner. Signing in from the GUI connects without touching a terminal.
- `nix flake show` lists `packages.x86_64-linux.default`, `overlays.default` and `nixosModules.default`.
