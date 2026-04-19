# vexos-nix justfile

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    #!/usr/bin/env bash
    just --list
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *server* ]]; then
        echo ""
        echo "Available recipes (server role):"
        echo "    services             List server service modules and their status"
        echo "    enable <service>     Enable a server service module"
        echo "    disable <service>    Disable a server service module"
    fi

# Print the active role and GPU variant (e.g. vexos-desktop-amd).
variant:
    @cat /etc/nixos/vexos-variant 2>/dev/null || echo "unknown (run a build first)"

# Resolve a flake directory that contains the requested target.
# Usage: just _resolve-flake-dir vexos-desktop-amd [/path/to/flake]
[private]
_resolve-flake-dir target flake_override="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi

    TARGET="{{target}}"
    FLAKE_OVERRIDE="{{flake_override}}"

    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")

    CANDIDATES=()
    if [ -n "$FLAKE_OVERRIDE" ]; then
        CANDIDATES+=("$FLAKE_OVERRIDE")
    fi
    CANDIDATES+=("$_jf_dir" "/etc/nixos" "$HOME/Projects/vexos-nix")

    CHECK_ATTR="nixosConfigurations.${TARGET}.config.system.build.toplevel.drvPath"
    TRIED=()

    for _d in "${CANDIDATES[@]}"; do
        [ -n "$_d" ] || continue
        _d_real=$(readlink -f "$_d" 2>/dev/null || echo "$_d")

        _seen=0
        for _t in "${TRIED[@]}"; do
            if [ "$_t" = "$_d_real" ]; then
                _seen=1
                break
            fi
        done
        [ "$_seen" -eq 0 ] || continue
        TRIED+=("$_d_real")

        if [ ! -f "$_d_real/flake.nix" ]; then
            continue
        fi

        if nix eval --impure --raw "$_d_real#${CHECK_ATTR}" >/dev/null 2>&1; then
            echo "$_d_real"
            exit 0
        fi
    done

    echo "error: no flake provided target '${TARGET}'" >&2
    echo "attempted directories:" >&2
    for _t in "${TRIED[@]}"; do
        echo "  - $_t" >&2
    done
    echo "expected target: nixosConfigurations.${TARGET}" >&2
    echo "hint: run 'nix flake show /etc/nixos' and 'nix flake show $_jf_dir'" >&2
    exit 1

# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                  — interactive prompt
#   just switch desktop amd      — direct switch
#   just switch desktop amd .    — explicit flake override
switch role="" variant="" flake="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: 'sudo' command not found. Use a Linux host with sudo configured." >&2
        exit 127
    fi
    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just switch must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

    ROLE="{{role}}"
    VARIANT="{{variant}}"
    FLAKE_OVERRIDE="{{flake}}"

    if [ -z "$ROLE" ]; then
        echo ""
        echo "Select role:"
        echo "  1) desktop"
        echo "  2) stateless"
        echo "  3) htpc"
        echo "  4) server"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop) ROLE="desktop" ;;
                2|stateless) ROLE="stateless" ;;
                3|htpc)    ROLE="htpc"    ;;
                4|server)  ROLE="server"  ;;
                *) echo "Invalid — enter 1-4 or desktop/stateless/htpc/server" ;;
            esac
        done
    fi

    if [ -z "$VARIANT" ]; then
        echo ""
        echo "Select GPU variant:"
        echo "  1) amd"
        echo "  2) nvidia"
        echo "  3) intel"
        echo "  4) vm"
        echo ""
        while [ -z "$VARIANT" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|amd)    VARIANT="amd"    ;;
                2|nvidia) VARIANT="nvidia" ;;
                3|intel)  VARIANT="intel"  ;;
                4|vm)     VARIANT="vm"     ;;
                *) echo "Invalid — enter 1-4 or amd/nvidia/intel/vm" ;;
            esac
        done
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    sudo nixos-rebuild switch --flake "${_flake_dir}#${TARGET}"

    echo ""
    echo "Switch complete."
    echo ""
    printf "Reboot now? [y/N]: "
    read -r REBOOT_ANSWER || true
    case "${REBOOT_ANSWER,,}" in
        y|yes) echo "Rebooting..."; sudo systemctl reboot ;;
        *)     echo "Skipped — reboot manually when ready." ;;
    esac

# Dry-run build without switching — useful for testing config changes.
# Example: just build desktop amd
build role variant flake="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: 'sudo' command not found. Use a Linux host with sudo configured." >&2
        exit 127
    fi
    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just build must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

    TARGET="vexos-{{role}}-{{variant}}"
    FLAKE_OVERRIDE="{{flake}}"
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    sudo nixos-rebuild build --flake "${_flake_dir}#${TARGET}"

# Update all flake inputs, then rebuild and switch using the current variant.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    # Always update /etc/nixos/flake.lock — that is the thin wrapper whose
    # lock pins the vexos-nix GitHub commit.  The repo clone's own flake.lock
    # is irrelevant for end-user updates.
    sudo nix flake update --flake /etc/nixos
    sudo nixos-rebuild switch --flake /etc/nixos#"${target}"

# Roll back to the previous NixOS generation and set it as the boot default.
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(nix-env -p /nix/var/nix/profiles/system --list-generations \
                | awk '/current/{print $1}')
    echo "Current generation: ${current}"
    sudo nixos-rebuild switch --rollback
    new=$(nix-env -p /nix/var/nix/profiles/system --list-generations \
            | awk '/current/{print $1}')
    echo "Now on generation: ${new}"

# Roll forward to the next (newer) NixOS generation and set it as the boot default.
rollforward:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(nix-env -p /nix/var/nix/profiles/system --list-generations \
                | awk '/current/{print $1}')
    next=$(nix-env -p /nix/var/nix/profiles/system --list-generations \
             | awk -v cur="$current" '$1+0 > cur+0 {print $1+0; exit}')
    if [ -z "$next" ]; then
        echo "Already at the latest generation (${current}). Nothing to roll forward to."
        exit 0
    fi
    echo "Rolling forward: generation ${current} → ${next}"
    sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation "$next"
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
    echo "Now on generation: ${next}"

# ── Server Services Management ───────────────────────────────────────────────
# These recipes manage /etc/nixos/server-services.nix on the server role.
# Run `just services` to see available modules and their status.

# Available server service module names.
_server_service_names := "docker jellyfin plex papermc immich vaultwarden nextcloud forgejo syncthing cockpit uptime-kuma stirling-pdf audiobookshelf homepage caddy arr adguard home-assistant"

# Guard: abort if the current host is not running a server variant.
[private]
_require-server-role:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" != *server* ]]; then
        echo "error: server service recipes are only available on the server role."
        echo "       current variant: ${variant:-unknown}"
        exit 1
    fi

# List all server services and their enabled/disabled status.
[private]
services: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    if [ ! -f "$SVC_FILE" ]; then
        echo "No server-services.nix found at $SVC_FILE"
        echo "Copy the template: sudo cp template/server-services.nix /etc/nixos/"
        exit 1
    fi
    echo ""
    echo "Server services (/etc/nixos/server-services.nix):"
    echo ""
    for svc in {{_server_service_names}}; do
        nix_name=$(echo "$svc" | sed 's/-/_/g')
        # Handle both dash and underscore names in the file
        if grep -qP "vexos\.server\.(${svc}|${nix_name})\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            printf "  \033[32m✓\033[0m %s\n" "$svc"
        else
            printf "  \033[90m✗\033[0m %s\n" "$svc"
        fi
    done
    echo ""

# Enable a server service module.  Usage: just enable docker
[private]
enable service: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    SERVICE="{{service}}"

    VALID_SERVICES="{{_server_service_names}}"
    if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
        echo "error: unknown service '$SERVICE'"
        echo "available: $VALID_SERVICES"
        exit 1
    fi

    if [ ! -f "$SVC_FILE" ]; then
        echo "Creating $SVC_FILE from template..."
        _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
        _jf_dir=$(dirname "$_jf_real")
        sudo cp "$_jf_dir/template/server-services.nix" "$SVC_FILE"
    fi

    # The option uses dots as-is (e.g. uptime-kuma stays uptime-kuma)
    OPTION="vexos.server.${SERVICE}.enable"

    if grep -q "${OPTION}\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        echo "$SERVICE is already enabled."
        exit 0
    fi

    # If a commented-out or false line exists, replace it
    if grep -qP "^\s*#?\s*${OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
        sudo sed -i -E "s|^(\s*)#?\s*(${OPTION//./\\.})\s*=\s*(true\|false)\s*;|\1${OPTION} = true;|" "$SVC_FILE"
    else
        # Insert before the closing brace
        sudo sed -i "s|}|  ${OPTION} = true;\n}|" "$SVC_FILE"
    fi

    echo "✓ Enabled: $SERVICE"
    echo "  → Run 'just rebuild' or 'just switch server <gpu>' to apply."

# Disable a server service module.  Usage: just disable docker
[private]
disable service: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    SERVICE="{{service}}"

    VALID_SERVICES="{{_server_service_names}}"
    if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
        echo "error: unknown service '$SERVICE'"
        echo "available: $VALID_SERVICES"
        exit 1
    fi

    if [ ! -f "$SVC_FILE" ]; then
        echo "No server-services.nix found. Nothing to disable."
        exit 0
    fi

    OPTION="vexos.server.${SERVICE}.enable"

    if ! grep -qP "${OPTION//./\\.}\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        echo "$SERVICE is already disabled."
        exit 0
    fi

    sudo sed -i -E "s|(${OPTION//./\\.})\s*=\s*true;|\1 = false;|" "$SVC_FILE"

    echo "✗ Disabled: $SERVICE"
    echo "  → Run 'just rebuild' or 'just switch server <gpu>' to apply."

# Rebuild the system using the current variant.
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")
    _flake_dir=$(just _resolve-flake-dir "${target}" "")
    sudo nixos-rebuild switch --flake "${_flake_dir}#${target}"
