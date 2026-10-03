# Prompt: rework vex-vpn into the GUI for vexos-vpn

> Paste everything below the line into Claude Code, started in `~/Projects/vex-vpn`.
> Prerequisite: the vexos-nix `vexos-vpn` backend (modules/vpn.nix, pkgs/vexos-vpn) is merged and
> installed on the machine you test on.

---

Rework vex-vpn from a "universal VPN client" into a thin GTK4/libadwaita front end for the **vexos-vpn** backend that now ships in vexos-nix. Follow this repo's CLAUDE.md workflow (spec → implement → review → preflight). Write the Phase 1 spec first and stop for my approval before deleting anything.

## Background

vex-vpn currently has its own VPN backends (`src/backend/{openvpn,wireguard}.rs`), config parsers (`src/parser/`), a profile model (`src/profile.rs`, `ui_profiles.rs`, `ui_import.rs`), a root helper (`src/bin/helper.rs`, `src/helper.rs`), an iptables kill switch (`nix/module-gui.nix`), and a vendored systemd-networkd PIA backend (`nix/module-vpn.nix`). All of that is now replaced by vexos-vpn. **vex-vpn must no longer touch the network, firewall, credentials files, or VPN configs itself.** It only displays state and asks systemd to act, so it needs no privileges.

## The backend contract (source of truth: vexos-nix `modules/vpn.nix` and `pkgs/vexos-vpn/vexos-vpn.sh`; read them)

**Read state.** Poll `vexos-vpn status --json` (unprivileged; about every 2 s while the window is visible, about every 10 s for the tray). Fields:
- `state`: `connected | connecting | disconnected | error`
- `protocol`, `region`, `region_name`, `server_cn`, `endpoint_ip`, `interface`, `since` (ISO 8601), `last_error`
- `rx_bytes`, `tx_bytes`
- `killswitch` (bool), `killswitch_mode`: `off | manual | always`
- `protocol_setting`, `region_setting` (the user's choice, e.g. `auto`)

No field contains secrets. Optionally watch `/run/vexos-vpn/status.json` with inotify instead of polling it.

**Region list.** `vexos-vpn regions --json` returns `[{id, name, country, port_forward, latency_s|null}]`. Latency is populated after an auto connect.

**Act, via systemd D-Bus** (`org.freedesktop.systemd1.Manager`, which the existing `src/dbus.rs` zbus proxies already use). Polkit allows these for the `users` group:
- Connect / disconnect / reconnect: `StartUnit` / `StopUnit` / `RestartUnit` on `vexos-vpn.service`.
- Choose a region (or `auto`): `StartUnit("vexos-vpn-region@<id>.service", "replace")`. It validates the id, persists the choice, and reconnects if connected.
- Choose a protocol: `StartUnit("vexos-vpn-protocol@wireguard.service" | "...@openvpn.service")`.
- Kill switch on / off: `StartUnit` / `StopUnit` on `vexos-killswitch.service`. In `always` mode (stateless) the stop prompts for an admin password through polkit. Handle "auth cancelled" gracefully. Hide the toggle entirely when `killswitch_mode == "off"`.

**Credentials.** Never read, store, or handle them in vex-vpn. Offer a "Sign in to PIA" button that opens a terminal running `pkexec vexos-vpn login`, or `sudo vexos-vpn login` if pkexec is unavailable. Also offer a "Test login" button running `pkexec vexos-vpn selftest`, which prints OK/FAILED only.

## UI to keep or build

- Main page:
  - large connect/disconnect switch
  - state with region name and protocol
  - "connected since"
  - rx/tx rates (diff the byte counters)
  - `last_error` banner when `state == "error"`
- Region picker: searchable list from `regions --json` with latency, plus an "Automatic (fastest)" entry at the top.
- Protocol: WireGuard (recommended) / OpenVPN (backup).
- Kill switch row:
  - state
  - mode explanation ("always on — turning it off lasts until reboot" for `always`)
  - toggle
- Tray (keep `src/tray.rs` / ksni): icon per state, connect/disconnect, current region.
- Keep the branding and history work if it still fits; drop anything that only made sense for multi-provider profiles.

## Remove

- `src/backend/`, `src/parser/`, `src/profile.rs`, `ui_profiles.rs`, `ui_import.rs`, `src/bin/helper.rs`, `src/helper.rs`
- NetworkManager D-Bus code in `src/dbus.rs`; keep only the systemd proxies
- `nix/module-vpn.nix`
- the iptables kill switch and helper/polkit bits in `nix/module-gui.nix` and `nix/polkit-vex-vpn.policy`

The NixOS module should shrink to: install the package, a `.desktop` file, and an optional autostart user service for the tray. **No polkit rules**; vexos-nix already ships them. It must not declare anything that collides with vexos-nix's units (`vexos-vpn*.service`, `vexos-killswitch.service`).

## Constraints

- No root, no direct netlink/nftables/iptables, no file writes outside `$XDG_CONFIG_HOME/vex-vpn` (UI preferences only).
- If `vexos-vpn` is not on `PATH`, show a clear "vexos-vpn backend not installed" page instead of crashing.
- Keep zbus/tokio/gtk4-rs versions as locked unless a change is required. Verify any API you touch with Context7.
- Update tests: replace `tests/config_integration.rs` with tests that parse captured `status --json` / `regions --json` fixtures, covering every `state` value and a `null` latency.
- Update README to describe vex-vpn as the vexos-vpn GUI. Drop the tadfisher/flake instructions.

## Done when

- `cargo build`, `cargo clippy -- -D warnings`, `cargo test` and `nix build` all pass.
- On a vexos desktop: connect, disconnect, switch region, switch protocol, and toggle the kill switch all work from the GUI and the tray without any sudo prompt.
- On stateless: the kill-switch off toggle shows the polkit password prompt.
- The GUI shows `last_error` when the backend is in `error` state (test by temporarily moving `/var/lib/vexos-vpn/credentials` aside).
