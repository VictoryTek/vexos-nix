# vexos-nix justfile

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    @just --list

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
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")
    if [ ! -f "$_jf_dir/flake.nix" ]; then
        for _d in /etc/nixos "$HOME/Projects/vexos-nix"; do
            if [ -f "$_d/flake.nix" ]; then _jf_dir="$_d"; break; fi
        done
    fi
    cd "$_jf_dir"
    nix flake update
    sudo nixos-rebuild switch --flake "$_jf_dir"#"${target}"

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
