# vexos-nix justfile

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    @just --list

# Print the active role and GPU variant (e.g. vexos-desktop-amd).
variant:
    @cat /etc/nixos/vexos-variant 2>/dev/null || echo "unknown (run a build first)"

# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                  — interactive prompt
#   just switch desktop amd      — direct switch
switch role="" variant="":
    #!/usr/bin/env bash
    set -euo pipefail

    ROLE="{{role}}"
    VARIANT="{{variant}}"

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
    sudo nixos-rebuild switch --flake "{{justfile_directory()}}"#"${TARGET}"

# Dry-run build without switching — useful for testing config changes.
# Example: just build desktop amd
build role variant:
    sudo nixos-rebuild build --flake "{{justfile_directory()}}"#vexos-{{role}}-{{variant}}

# Update all flake inputs, then rebuild and switch using the current variant.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    cd "{{justfile_directory()}}"
    nix flake update
    sudo nixos-rebuild switch --flake "{{justfile_directory()}}"#"${target}"

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
