# vexos-nix justfile
# Run `just --list` to see all available recipes.

# Show current variant, or switch to a new one.
# Usage:
#   just variant                   – print active variant
#   just variant switch <name>     – rebuild and switch (amd | nvidia | intel | vm)
variant action="" name="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{action}}" in
        "")
            raw=$(grep '^NAME=' /etc/os-release 2>/dev/null | cut -d'"' -f2 | tr '[:upper:]' '[:lower:]')
            case "$raw" in
                *amd*)    echo "amd"    ;;
                *nvidia*) echo "nvidia" ;;
                *intel*)  echo "intel"  ;;
                *vm*)     echo "vm"     ;;
                *)        echo "unknown (NAME=${raw})" ;;
            esac
            ;;
        switch)
            case "{{name}}" in
                amd|nvidia|intel|vm)
                    echo "Switching to variant: {{name}}"
                    sudo nixos-rebuild switch --flake .#vexos-desktop-{{name}}
                    ;;
                "")
                    echo "error: variant name required"
                    echo "usage: just variant switch <amd|nvidia|intel|vm>"
                    exit 1
                    ;;
                *)
                    echo "error: unknown variant '{{name}}'"
                    echo "valid variants: amd  nvidia  intel  vm"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "error: unknown action '{{action}}'"
            echo "usage:"
            echo "  just variant                   print active variant"
            echo "  just variant switch <name>     rebuild and switch variant"
            exit 1
            ;;
    esac

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
