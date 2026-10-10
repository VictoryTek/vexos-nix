# just/vpn.just — Tailscale setup and the PIA VPN / kill switch menus (wrappers around vexos-vpn).
# Imported by the root justfile; recipe names share one namespace.

# First-time Tailscale setup — grants operator rights to the current user, then connects.
# Run once after enabling services.tailscale.enable = true in your NixOS config and rebuilding.
# On first run, Tailscale will print a URL to authenticate — open it in a browser.
[group('VPN')]
[doc('First-time Tailscale setup: operator rights, then connect')]
setup-tailscale:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v tailscale >/dev/null 2>&1; then
        echo "error: tailscale not found." >&2
        echo "       Add 'services.tailscale.enable = true;' to your NixOS config and rebuild." >&2
        exit 1
    fi

    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
        echo "error: tailscaled is not running." >&2
        echo "       Add 'services.tailscale.enable = true;' to your NixOS config and rebuild." >&2
        exit 1
    fi

    echo "Setting operator to ${USER} (allows tailscale CLI without sudo)..."
    sudo tailscale set --operator="$USER"
    echo "✓ Operator set."
    echo ""
    echo "Connecting to Tailscale..."
    tailscale up

# PIA VPN (desktop, htpc, stateless) — thin wrappers around the vexos-vpn CLI
# (modules/vpn.nix). On desktop/htpc: `just feature enable vpn` first; always on in stateless. Run `vexos-vpn help` for the full command list.

# Store PIA credentials (root-only file; prompts, never echoed). Run once.
[private]
_vpn-login:
    @command -v vexos-vpn >/dev/null || { echo "error: vexos-vpn is not installed — run 'just feature enable vpn' and rebuild." >&2; exit 1; }
    sudo vexos-vpn login

# Check the PIA login works — prints OK/FAILED only, never the credentials or token.
[private]
_vpn-selftest:
    @command -v vexos-vpn >/dev/null || { echo "error: vexos-vpn is not installed — run 'just feature enable vpn' and rebuild." >&2; exit 1; }
    sudo vexos-vpn selftest

# Connect the PIA VPN.
[private]
_vpn-up:
    vexos-vpn up && vexos-vpn status

# Disconnect the PIA VPN (with the kill switch on, this leaves you offline).
[private]
_vpn-down:
    vexos-vpn down && vexos-vpn status

# Show VPN and kill switch state.
[private]
_vpn-status:
    vexos-vpn status

# List PIA regions (latency shown after an auto connect).
[private]
_vpn-regions:
    vexos-vpn regions

# Choose a PIA region, or "auto" for the fastest. Reconnects if connected.
[private]
[arg('region', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
_vpn-region region:
    vexos-vpn region {{quote(region)}}

# Switch protocol: wireguard (default) or openvpn (backup). Reconnects if connected.
[private]
[arg('protocol', pattern='wireguard|openvpn')]
_vpn-protocol protocol:
    vexos-vpn protocol {{quote(protocol)}}

# Turn the kill switch on — blocks all internet traffic outside the PIA tunnel.
[private]
_kill-switch-on:
    vexos-vpn killswitch on
    @echo "✓ Kill switch on — internet only through the PIA tunnel. Disable with: just kill-switch off"

# Turn the kill switch off. On stateless this asks for your password and lasts until reboot.
[private]
_kill-switch-off:
    vexos-vpn killswitch off
    @echo "✓ Kill switch off — normal internet access restored. Re-enable with: just kill-switch on"

# PIA VPN (desktop, htpc, stateless): thin wrappers around the vexos-vpn CLI.
[group('VPN')]
[doc('PIA VPN: sign in, connect, choose region or protocol (menu)')]
vpn action="" *args:
    @{{_just}} _menu vpn "VPN (PIA)" {{quote(action)}} {{quote(args)}} \
        "login|Store PIA credentials (run once)" \
        "selftest|Check the PIA login works||stay" \
        "up|Connect the VPN" \
        "down|Disconnect the VPN" \
        "status|Show VPN and kill switch state||stay" \
        "regions|List PIA regions||stay" \
        "region|Choose a region, or auto for the fastest|Region (e.g. auto)" \
        "protocol|Switch protocol: wireguard or openvpn|Protocol (wireguard or openvpn)"

# VPN kill switch: block all traffic outside the PIA tunnel (on) or restore normal access (off).
[group('VPN')]
[doc('VPN kill switch: block traffic outside the tunnel, or restore it (menu)')]
kill-switch action="" *args:
    @{{_just}} _menu kill-switch "VPN kill switch" {{quote(action)}} {{quote(args)}} \
        "on|Block all internet traffic outside the PIA tunnel" \
        "off|Restore normal internet access"
