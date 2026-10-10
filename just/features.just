# just/features.just — Optional feature modules (/etc/nixos/features.nix).
# Imported by the root justfile; recipe names share one namespace.

# Run `just feature list` to see available features and their status.

# Patch /etc/nixos/flake.nix to load features.nix on every rebuild.
# Required once on systems where the thin wrapper predates feature toggle support.
# Safe to re-run — exits immediately if the wrapper is already up to date.
[group('Optional Feature Toggles')]
[doc('Make an older /etc/nixos/flake.nix load features.nix (run once)')]
fix-flake:
    #!/usr/bin/env bash
    set -euo pipefail
    WRAPPER="/etc/nixos/flake.nix"

    if [ ! -f "$WRAPPER" ]; then
        echo "error: $WRAPPER not found." >&2
        exit 1
    fi

    if grep -q "features\.nix" "$WRAPPER" 2>/dev/null; then
        echo "✓ $WRAPPER already loads features.nix — nothing to do."
        exit 0
    fi

    PATCHED=false

    # Old-style wrapper: _mkVariantWith ends with ] ++ modules;
    if grep -q '] ++ modules;' "$WRAPPER"; then
        sudo sed -i \
          's|] ++ modules;|] ++ modules\n          ++ (if builtins.pathExists ./features.nix then [ ./features.nix ] else []);|' \
          "$WRAPPER"
        echo "✓ $WRAPPER patched."
        PATCHED=true
    fi

    # Newer-style wrapper: uses lib.optional hasKernelOverride — insert features line before it
    # (0, addr limits to first match so only _mkVariantWith is patched, not htpc/server builders)
    if [ "$PATCHED" = "false" ] && grep -q 'lib\.optional hasKernelOverride' "$WRAPPER"; then
        sudo sed -i \
          '0,/lib\.optional hasKernelOverride/s|++ lib\.optional hasKernelOverride|++ (if builtins.pathExists ./features.nix then [ ./features.nix ] else [])\n          ++ lib.optional hasKernelOverride|' \
          "$WRAPPER"
        echo "✓ $WRAPPER patched."
        PATCHED=true
    fi

    if [ "$PATCHED" = "false" ]; then
        echo "error: could not identify wrapper version — patch manually." >&2
        echo "  Add this to the modules list in _mkVariantWith in $WRAPPER:" >&2
        echo "    ++ (if builtins.pathExists ./features.nix then [ ./features.nix ] else [])" >&2
        exit 1
    fi

    echo ""
    if [ "$({{_just}} _confirm 'Rebuild now to apply? [y/N]: ')" = "true" ]; then
        {{_just}} rebuild
    else
        echo "Run 'just rebuild' when ready."
    fi

# Available optional feature names (desktop, server, htpc, and vanilla roles;
# ai is desktop, server and htpc only).
_feature_names := "gaming development print3d virtualization sunshine vpn kernel ai"

# Guard: abort if the current host is stateless or headless-server (features not
# supported there — neither role wires /etc/nixos/features.nix into its module set).
[private]
_require-desktop-role:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *stateless* || "$variant" == *headless* ]]; then
        echo "error: feature recipes are not available on stateless or headless-server roles."
        echo "       current variant: ${variant:-unknown}"
        exit 1
    fi

# List all optional features and their enabled/disabled status.
[private]
_feature-list: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEAT_FILE="/etc/nixos/features.nix"
    # $2 ("on"/"off", default "off") is the module's own default when the option is
    # absent/commented out in features.nix — sunshine defaults to true in
    # modules/sunshine.nix, the rest default to false.
    _check() {
        local feat="$1"
        local default="${2:-off}"
        if grep -qP "vexos\.features\.${feat//./\\.}\.enable\s*=\s*true" "$FEAT_FILE" 2>/dev/null; then
            printf "    \033[32m✓\033[0m %s\n" "$feat"
        elif grep -qP "vexos\.features\.${feat//./\\.}\.enable\s*=\s*false" "$FEAT_FILE" 2>/dev/null; then
            printf "    \033[90m✗\033[0m %s\n" "$feat"
        elif [ "$default" = "on" ]; then
            printf "    \033[32m✓\033[0m %s (default)\n" "$feat"
        else
            printf "    \033[90m✗\033[0m %s\n" "$feat"
        fi
    }
    echo ""
    echo "Optional features (/etc/nixos/features.nix):"
    echo ""
    _check gaming
    _check development
    _check print3d
    _check virtualization
    _check sunshine on
    _check vpn
    _check ai
    echo ""
    echo "Use 'just feature enable <feature>' / 'just feature disable <feature>' to toggle."
    echo ""

# Enable an optional feature module.  Usage: just feature enable gaming
# Use 'just feature enable all' to enable every feature.
[private]
[arg('feature', pattern='[a-z0-9]+')]
_feature-enable feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEATURE={{quote(feature)}}

    if [ "$FEATURE" = "all" ]; then
        for f in {{_feature_names}}; do
            {{_just}} feature enable "$f"
        done
        exit 0
    fi

    FEAT_FILE="/etc/nixos/features.nix"

    VALID_FEATURES="{{_feature_names}}"
    if ! echo "$VALID_FEATURES" | tr ' ' '\n' | grep -qx "$FEATURE"; then
        echo "error: unknown feature '$FEATURE'"
        echo "available: $VALID_FEATURES"
        exit 1
    fi

    # modules/ai.nix is imported by desktop, htpc and server only; on vanilla
    # the option does not exist and setting it would fail evaluation. Exit 0
    # so `just feature enable all` carries on past it.
    if [ "$FEATURE" = "ai" ] && [[ "$(cat /etc/nixos/vexos-variant 2>/dev/null)" == *vanilla* ]]; then
        echo "ai: not available on the vanilla role — skipped."
        exit 0
    fi

    source "{{justfile_directory()}}/just/lib.sh"

    if [ ! -f "$FEAT_FILE" ]; then
        echo "Creating $FEAT_FILE from template..."
        seed_from_template features.nix "$FEAT_FILE"
    fi

    OPTION="vexos.features.${FEATURE}.enable"

    if nix_is_set "$FEAT_FILE" "$OPTION" true; then
        echo "$FEATURE is already enabled."
        exit 0
    fi

    nix_set "$FEAT_FILE" "$OPTION" true

    echo "✓ $FEATURE enabled in $FEAT_FILE"
    echo ""
    case "$FEATURE" in
        gaming)
            echo "  What this adds:"
            echo "    Packages   Steam, Proton-GE, GameMode, Gamescope, MangoHud, Wine (Wow64 Staging),"
            echo "               protontricks, umu-launcher, vkbasalt, distrobox, Ryujinx (Switch emulator),"
            echo "               RetroArch, vesktop, Discord"
            echo "    Flatpak    Lutris (game manager), ProtonPlus (Proton/Wine version manager),"
            echo "               PrismLauncher (Minecraft)"
            echo "    Hardware   Xbox controllers (xone/xpadneo), Switch Pro, DualShock 4, DualSense"
            echo "    GPU        32-bit libs, shader cache tuning, SCX LAVD gaming scheduler"
            ;;
        development)
            echo "  What this adds:"
            echo "    Services   Docker 29 (with weekly auto-prune)"
            echo "    Editor     VSCodium (telemetry-free VS Code fork)"
            echo "    Languages  Python 3 + uv + ruff, TypeScript, Node (pnpm + bun), Rust (rustc + cargo + clippy + rust-analyzer), Go"
            echo "    Tools      GitHub CLI, git-lfs, jq, yq, pre-commit, sqlite, httpie, mkcert, gcc"
            echo "    AI         Claude Code (Anthropic Claude CLI)"
            echo "    Nix        nil (LSP), nixpkgs-fmt, nix-output-monitor"
            ;;
        print3d)
            echo "  What this adds:"
            echo "    Flatpak    Blender — 3D modelling, sculpting, rendering, animation"
            echo "               OrcaSlicer — FDM slicer with multi-material and plate support"
            ;;
        virtualization)
            echo "  What this adds:"
            echo "    Services   libvirtd + QEMU/KVM hypervisor (hardware-accelerated VMs)"
            echo "    Apps       GNOME Boxes (VM management UI)"
            echo "    Features   Virtual TPM 2.0 — required for Windows 11 guests"
            echo "    Groups     User added to libvirtd (manage VMs without sudo)"
            ;;
        sunshine)
            echo "  What this adds:"
            echo "    Services   Sunshine — self-hosted Moonlight game-stream host (KMS capture)"
            echo "    Firewall   Sunshine's TCP/UDP port range opened automatically"
            echo "    Groups     User added to uinput (remote mouse/keyboard input)"
            echo ""
            echo "  Two one-time manual steps remain after rebuild (cannot be scripted):"
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "<run 'tailscale ip -4' to find it>")
            echo "    1. Create the WebUI admin account (first run only): https://$TS_IP:47990"
            echo "    2. In Moonlight, add this host by IP ($TS_IP), then enter the PIN"
            echo "       shown under the WebUI's PIN tab to pair the client."
            ;;
        vpn)
            echo "  What this adds:"
            echo "    Services   PIA VPN tunnel (WireGuard, OpenVPN backup) + nftables kill switch"
            echo "    Apps       vexos-vpn CLI, vex-vpn GUI + tray (autostarts with the session)"
            echo ""
            echo "  Off until you connect: sign in with 'just vpn login' (or the GUI), then"
            echo "  'just vpn up'. The kill switch is available but stopped by default."
            ;;
        kernel)
            echo "  What this adds:"
            echo "    Kernel     Custom kernel from pkgs/kernels/ (default: ogc)"
            echo "               OGC = Open Gaming Collective — the unified kernel behind"
            echo "               Bazzite, ChimeraOS, Nobara, PikaOS and ASUS Linux."
            echo "               Ships NTSYNC, sched_ext, and handheld/ASUS enablement."
            echo ""
            echo "  Pick a different kernel by editing /etc/nixos/features.nix:"
            echo "    vexos.features.kernel.name = \"ogc\";"
            echo ""
            echo "  IMPORTANT: these kernels are not on cache.nixos.org. They are built"
            echo "  by a host running 'vexos.server.kernelBuilder' and served over"
            echo "  Harmonia. If that host has not built the current pin yet, this"
            echo "  machine would compile the kernel locally (hours) — 'just update'"
            echo "  checks the cache first and stops you before that happens."
            ;;
        ai)
            echo "  What this adds:"
            echo "    Apps       Claude Code + OpenCode, and 'VexOS Assistant' in the app menu"
            echo "               (Super+Shift+A; 'just agent' from a terminal)"
            echo "    Skills     Teaches the assistant how VexOS is configured: it edits"
            echo "               /etc/nixos side-files and dry-builds; you apply with 'just rebuild'"
            echo "    Diagnose   'just diagnose [unit|rebuild]', plus a 'Diagnose with AI'"
            echo "               notification when a program crashes"
            echo "    Accounts   Several Claude accounts, usage warnings near a limit, optional"
            echo "               auto-switch ('vexos-ai panel')"
            echo ""
            echo "  On first launch you choose Claude Code or OpenCode and sign in"
            echo "  through the tool's own browser login."
            ;;
    esac
    echo ""
    echo "  Run 'just rebuild' to apply."

    # Warn if the thin wrapper at /etc/nixos/flake.nix won't load features.nix —
    # without this the feature toggle resets to false on every rebuild.
    if [ -f /etc/nixos/flake.nix ] && ! grep -q "features\.nix" /etc/nixos/flake.nix 2>/dev/null; then
        echo ""
        echo "  ⚠ Warning: /etc/nixos/flake.nix does not load features.nix."
        echo "    Features will not persist across reboots until fixed."
        echo "    Run 'just fix-flake' then 'just rebuild' to resolve."
    fi

    # The AI assistant's launcher, keybinding and crash-notification hooks load
    # at login, so a rebuild alone isn't enough — offer rebuild + reboot.
    if [ "$FEATURE" = "ai" ]; then
        echo ""
        if [ "$({{_just}} _confirm 'Rebuild and reboot now to finish enabling the AI assistant? [y/N]: ')" = "true" ]; then
            {{_just}} rebuild
            echo "Rebooting..."; sudo systemctl reboot
        else
            echo "Skipped — run 'just rebuild', then reboot, when ready."
        fi
    fi

# Disable an optional feature module.  Usage: just feature disable gaming
# Use 'just feature disable all' to disable every feature.
[private]
[arg('feature', pattern='[a-z0-9]+')]
_feature-disable feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEATURE={{quote(feature)}}

    if [ "$FEATURE" = "all" ]; then
        for f in {{_feature_names}}; do
            {{_just}} feature disable "$f"
        done
        exit 0
    fi

    FEAT_FILE="/etc/nixos/features.nix"

    VALID_FEATURES="{{_feature_names}}"
    if ! echo "$VALID_FEATURES" | tr ' ' '\n' | grep -qx "$FEATURE"; then
        echo "error: unknown feature '$FEATURE'"
        echo "available: $VALID_FEATURES"
        exit 1
    fi

    OPTION="vexos.features.${FEATURE}.enable"

    if [ ! -f "$FEAT_FILE" ]; then
        echo "$FEATURE is already disabled (features.nix does not exist)."
        exit 0
    fi

    if grep -q "${OPTION}\s*=\s*false" "$FEAT_FILE" 2>/dev/null; then
        echo "$FEATURE is already disabled."
        exit 0
    fi

    if grep -qP "^\s*${OPTION//./\\.}\s*=\s*true" "$FEAT_FILE" 2>/dev/null; then
        sudo sed -i -E "s/^(\s*)(${OPTION//./\\.})\s*=\s*true\s*;/\1# \2 = false;/" "$FEAT_FILE"
        echo "✓ $FEATURE disabled in $FEAT_FILE"
        echo "  Run 'just rebuild' to apply."
    else
        echo "$FEATURE is already disabled."
    fi

# Optional feature modules (desktop roles): list, enable, disable.
[group('Optional Feature Toggles')]
[doc('Optional features: list, enable, disable (menu)')]
feature action="" *args: _require-desktop-role
    @{{_just}} _menu feature "Optional features" {{quote(action)}} {{quote(args)}} \
        "list|Show every feature and whether it is enabled||stay" \
        "enable|Enable a feature, or 'all'|Feature to enable (or all)" \
        "disable|Disable a feature, or 'all'|Feature to disable (or all)"
