# vexos-nix justfile

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    @just --list

# Print the active NixOS configuration name from /etc/os-release.
variant:
    @grep '^NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown"

# Rebuild and switch to a role + GPU variant.
# Roles:    desktop  privacy  htpc  server
# Variants: amd  nvidia  intel  vm
# Example:  just switch desktop amd
switch role variant:
    sudo nixos-rebuild switch --flake /etc/nixos#vexos-{{role}}-{{variant}}

# Dry-run build without switching — useful for testing config changes.
# Example: just build desktop amd
build role variant:
    sudo nixos-rebuild build --flake /etc/nixos#vexos-{{role}}-{{variant}}

# Update all flake inputs, then rebuild and switch.
# Example: just update desktop amd
update role variant:
    #!/usr/bin/env bash
    set -euo pipefail
    cd /etc/nixos
    sudo nix flake update
    sudo nixos-rebuild switch --flake /etc/nixos#vexos-{{role}}-{{variant}}

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
