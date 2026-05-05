# vexos-nix justfile

# List all available recipes (default when running `just` with no arguments).
[private]
default:
    #!/usr/bin/env bash
    just --list
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *server* ]]; then
        echo ""
        echo "Available recipes (GUI Server / Headless Server roles):"
        echo "    available-services         List all available server service modules"
        echo "    service-info [service]     Show ports and URLs for enabled (or specified) services"
        echo "    services                   List enabled/disabled status of server service modules"
        echo "    status <service>           Show systemctl status and HTTP reachability for a service"
        echo "    enable <service>           Enable a server service module"
        echo "    disable <service>          Disable a server service module"
        echo "    enable-plex-pass           Enable Plex Pass hardware transcoding"
        echo "    disable-plex-pass          Disable Plex Pass hardware transcoding"
        echo "    create-zfs-pool            Create a ZFS pool for Proxmox VM storage (interactive)"
    elif [[ "$variant" == *stateless* ]]; then
        echo ""
        echo "Active role: stateless (ephemeral / tmpfs root)"
        echo ""
        echo "Reminder:"
        echo "    Login password resets to 'vexos' on every reboot (by design)."
        echo "    To change permanently, update initialPassword in"
        echo "    configuration-stateless.nix and rebuild."
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
        echo "  5) headless-server"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-5] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop)         ROLE="desktop"         ;;
                2|stateless)       ROLE="stateless"       ;;
                3|htpc)            ROLE="htpc"            ;;
                4|server)          ROLE="server"          ;;
                5|headless-server) ROLE="headless-server" ;;
                *) echo "Invalid — enter 1-5 or desktop/stateless/htpc/server/headless-server" ;;
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

        # NVIDIA driver branch sub-selection
        if [ "$VARIANT" = "nvidia" ]; then
            echo ""
            echo "Select NVIDIA driver branch:"
            echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
            echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
            echo "  3) Legacy 470 — Kepler, GeForce 600/700 (470.x)"
            echo ""
            while true; do
                printf "Choice [1-3]: "
                read -r INPUT
                case "${INPUT}" in
                    1) break ;;
                    2) VARIANT="nvidia-legacy535"; break ;;
                    3) VARIANT="nvidia-legacy470"; break ;;
                    *) echo "Invalid — enter 1, 2, or 3" ;;
                esac
            done
        fi
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    sudo nixos-rebuild switch --flake "path:${_flake_dir}#${TARGET}"

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
    sudo nixos-rebuild build --flake "path:${_flake_dir}#${TARGET}"

# Update all flake inputs, then rebuild and switch using the current variant.
update:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")

    if [ -z "$target" ]; then
        ROLE=""
        VARIANT=""

        echo ""
        echo "vexos-variant not found (stateless reboot?) — select target manually."
        echo ""
        echo "Select role:"
        echo "  1) desktop"
        echo "  2) stateless"
        echo "  3) htpc"
        echo "  4) server"
        echo "  5) headless-server"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-5] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop)          ROLE="desktop"          ;;
                2|stateless)        ROLE="stateless"        ;;
                3|htpc)             ROLE="htpc"             ;;
                4|server)           ROLE="server"           ;;
                5|headless-server)  ROLE="headless-server"  ;;
                *) echo "Invalid — enter 1-5 or desktop/stateless/htpc/server/headless-server" ;;
            esac
        done

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

        # NVIDIA driver branch sub-selection
        if [ "$VARIANT" = "nvidia" ]; then
            echo ""
            echo "Select NVIDIA driver branch:"
            echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
            echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
            echo "  3) Legacy 470 — Kepler, GeForce 600/700 (470.x)"
            echo ""
            while true; do
                printf "Choice [1-3]: "
                read -r INPUT
                case "${INPUT}" in
                    1) break ;;
                    2) VARIANT="nvidia-legacy535"; break ;;
                    3) VARIANT="nvidia-legacy470"; break ;;
                    *) echo "Invalid — enter 1, 2, or 3" ;;
                esac
            done
        fi

        target="vexos-${ROLE}-${VARIANT}"
    fi

    echo ""
    echo "Updating flake inputs and switching to: ${target}"
    echo ""
    # Always update /etc/nixos/flake.lock — that is the thin wrapper whose
    # lock pins the vexos-nix GitHub commit.  The repo clone's own flake.lock
    # is irrelevant for end-user updates.
    sudo nix flake update --flake path:/etc/nixos
    sudo nixos-rebuild switch --flake path:/etc/nixos#"${target}"

# Roll back to the previous NixOS generation and set it as the boot default.
rollback:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
                | awk '/current/{print $1}')
    echo "Current generation: ${current}"
    sudo nixos-rebuild switch --rollback
    new=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
            | awk '/current/{print $1}')
    echo "Now on generation: ${new}"

# Roll forward to the next (newer) NixOS generation and set it as the boot default.
rollforward:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
                | awk '/current/{print $1}')
    next=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations \
             | awk -v cur="$current" '$1+0 > cur+0 {print $1+0; exit}')
    if [ -z "$next" ]; then
        echo "Already at the latest generation (${current}). Nothing to roll forward to."
        exit 0
    fi
    echo "Rolling forward: generation ${current} → ${next}"
    sudo nix-env --profile /nix/var/nix/profiles/system --switch-generation "$next"
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
    echo "Now on generation: ${next}"

# Reboot the system immediately.
reboot:
    sudo systemctl reboot

# Shut down the system immediately.
shutdown:
    sudo systemctl poweroff

# Reset all GNOME settings to the flake defaults by clearing the user dconf
# database.  After this, every key falls back to the system dconf database
# written by modules/gnome.nix and the active gnome-<role>.nix module.
# The app-folder stamp file is also removed so the first-run service
# re-applies the folder layout on the next graphical login.
# Run in a terminal (NOT inside a GNOME session) or log out first for best
# results, since GNOME may re-write some keys while running.
reset-defaults:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Resetting user dconf database — all GNOME customisations will be lost."
    printf "Continue? [y/N]: "
    read -r ANSWER
    case "${ANSWER,,}" in
        y|yes) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
    dconf reset -f /
    rm -f "$HOME/.local/share/vexos/.dconf-app-folders-initialized"
    echo "Done. Log out and back in (or reboot) for all changes to take effect."
    echo "App folders will be restored on the next graphical login."

# Copy your SSH key to a remote machine so future connections need no password.
# Usage:
#   just ssh                     — interactive prompts
#   just ssh nimda@10.35.1.50   — direct
ssh target="":
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET="{{target}}"

    if [ -z "$TARGET" ]; then
        printf "Username: "
        read -r _user
        printf "Server IP: "
        read -r _ip
        TARGET="${_user}@${_ip}"
    fi

    # Generate a local key pair if one doesn't exist yet.
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "No SSH key found — generating one now..."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "${USER}@$(hostname)"
    fi

    echo "Copying key to ${TARGET} — you will be prompted for the remote password once."
    ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" "${TARGET}"

    echo ""
    echo "Done. Connect with: ssh ${TARGET}"
    echo ""

# ── Server Services Management ───────────────────────────────────────────────
# Run `just services` to see available modules and their status.

# Available server service module names.
_server_service_names := "adguard arr audiobookshelf authelia caddy cockpit code-server docker dozzle forgejo grafana headscale home-assistant homepage immich jellyfin jellyseerr kavita komga listmonk loki matrix-conduit mealie minio navidrome netdata nextcloud nginx nginx-proxy-manager node-red ntfy overseerr paperless papermc photoprism plex portainer prometheus proxmox rustdesk scrutiny stirling-pdf syncthing tautulli traefik unbound uptime-kuma vaultwarden zigbee2mqtt"

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

# Interactively create a ZFS pool for use as Proxmox VM/container backing storage.
# Server roles only.  Requires modules/zfs-server.nix in the active build.
# All work runs as root via sudo. The recipe:
#   • lists block devices by /dev/disk/by-id/ path,
#   • prompts for pool name, topology, and disks,
#   • requires typed confirmation (the pool name) before destroying data,
#   • runs wipefs + sgdisk --zap-all + zpool create with VM-tuned defaults
#     (ashift=12, compression=lz4, atime=off, xattr=sa, acltype=posixacl),
#   • prints the `pvesm add zfspool` command to register the pool with Proxmox.
#
# Safe to abort with Ctrl-C at any prompt — destructive actions only run after
# the typed-name confirmation step.
[private]
create-zfs-pool: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v zpool >/dev/null 2>&1 || ! command -v zfs >/dev/null 2>&1; then
        echo "error: zpool/zfs not found — ZFS userland is not installed in this build." >&2
        echo "       Ensure modules/zfs-server.nix is imported by your active configuration-*.nix" >&2
        echo "       and rebuild:  just switch <role> <gpu>" >&2
        exit 1
    fi

    # Locate scripts/create-zfs-pool.sh.
    # justfile_directory() / justfile() can resolve into the read-only nix store
    # when the justfile is a nix-store symlink.  Walk up from $PWD first.
    _jf_raw="{{justfile_directory()}}"
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")

    SCRIPT=""
    _walk="$PWD"
    while [ "$_walk" != "/" ] && [ -z "$SCRIPT" ]; do
        if [ -f "$_walk/scripts/create-zfs-pool.sh" ]; then
            SCRIPT="$_walk/scripts/create-zfs-pool.sh"
        fi
        _walk=$(dirname "$_walk")
    done
    for _candidate in "$_jf_raw/scripts" "$_jf_dir/scripts" "/etc/nixos/scripts" "$HOME/Projects/vexos-nix/scripts"; do
        [ -n "$SCRIPT" ] && break
        if [ -f "$_candidate/create-zfs-pool.sh" ]; then
            SCRIPT="$_candidate/create-zfs-pool.sh"
        fi
    done
    # Last resort: find the vexos-nix source in the nix store via /etc/nixos flake input.
    if [ -z "$SCRIPT" ] && [ -f /etc/nixos/flake.nix ]; then
        _vexos_store=$(nix eval --raw --expr '(builtins.getFlake "path:/etc/nixos").inputs.vexos-nix.outPath' 2>/dev/null || true)
        if [ -n "$_vexos_store" ] && [ -f "$_vexos_store/scripts/create-zfs-pool.sh" ]; then
            SCRIPT="$_vexos_store/scripts/create-zfs-pool.sh"
        fi
    fi
    if [ -z "$SCRIPT" ]; then
        echo "error: scripts/create-zfs-pool.sh not found in any known location." >&2
        echo "       searched up from: $PWD" >&2
        echo "       also checked: $_jf_raw/scripts $_jf_dir/scripts /etc/nixos/scripts $HOME/Projects/vexos-nix/scripts" >&2
        echo "       also tried: nix store path via /etc/nixos flake input" >&2
        exit 1
    fi

    sudo bash "$SCRIPT"

# List all available server service modules (catalog view, no role required).
[private]
available-services:
    #!/usr/bin/env bash
    _hdr() { printf "\n  \033[1m%s\033[0m\n" "$1"; }
    _svc() { printf "    %s\n" "$1"; }
    echo ""
    echo "Available server service modules:"
    _hdr "Books & Reading";            _svc kavita;           _svc komga
    _hdr "Communications";             _svc matrix-conduit
    _hdr "Files & Storage";            _svc immich;           _svc nextcloud;       _svc syncthing;       _svc minio;           _svc photoprism
    _hdr "Gaming";                     _svc papermc
    _hdr "Infrastructure";             _svc caddy;            _svc docker;          _svc nginx;           _svc nginx-proxy-manager;  _svc portainer;  _svc traefik
    _hdr "Media";                      _svc audiobookshelf;   _svc jellyfin;        _svc navidrome;       _svc plex;            _svc tautulli
    _hdr "Media Requests & Automation";_svc arr;              _svc jellyseerr;      _svc overseerr
    _hdr "Monitoring & Admin";         _svc cockpit;          _svc dozzle;          _svc grafana;         _svc loki;            _svc netdata;     _svc prometheus;  _svc scrutiny;  _svc uptime-kuma
    _hdr "Networking & Security";      _svc adguard;          _svc authelia;        _svc headscale;       _svc unbound;         _svc vaultwarden
    _hdr "Productivity";               _svc code-server;      _svc forgejo;         _svc homepage;        _svc listmonk;        _svc mealie;      _svc paperless;   _svc stirling-pdf
    _hdr "Remote Access";              _svc rustdesk
    _hdr "Smart Home & Notifications"; _svc home-assistant;   _svc node-red;        _svc ntfy;            _svc zigbee2mqtt
    _hdr "Experimental";               _svc proxmox
    echo ""
    echo "Use 'just enable <service>' to enable a module on a server host."
    echo ""

# Show access info for server services — ports, URLs, and key notes.
# With no argument shows all currently enabled services; with a name shows that service.
# Usage:  just service-info            — all enabled services
#         just service-info jellyfin   — specific service
[private]
service-info service="":
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"

    _info() {
      case "$1" in
        adguard)         printf "  %-18s  Web UI  http://<server-ip>:3080   |  DNS on :53\n"                           "$1" ;;
        arr)             printf "  %-18s  SABnzbd :8080  Sonarr :8989  Radarr :7878  Lidarr :8686  Prowlarr :9696\n"   "$1" ;;
        audiobookshelf)  printf "  %-18s  Web UI  http://<server-ip>:8234\n"                                           "$1" ;;
        caddy)           printf "  %-18s  Ports :80, :443\n"                                                           "$1" ;;
        cockpit)         printf "  %-18s  Web UI  http://<server-ip>:9090\n"                                           "$1" ;;
        docker)          printf "  %-18s  No web UI — docker / docker compose CLI\n"                                   "$1" ;;
        forgejo)         printf "  %-18s  Web UI  http://<server-ip>:3000   ⚠ conflicts with grafana\n"                "$1" ;;
        grafana)         printf "  %-18s  Web UI  http://<server-ip>:3000   ⚠ conflicts with forgejo\n"                "$1" ;;
        headscale)       printf "  %-18s  Web UI  http://<server-ip>:8085\n"                                           "$1" ;;
        home-assistant)  printf "  %-18s  Web UI  http://<server-ip>:8123\n"                                           "$1" ;;
        homepage)        printf "  %-18s  Web UI  http://<server-ip>:3010   (requires docker)\n"                       "$1" ;;
        immich)          printf "  %-18s  Web UI  http://<server-ip>:2283\n"                                           "$1" ;;
        jellyfin)        printf "  %-18s  Web UI  http://<server-ip>:8096\n"                                           "$1" ;;
        jellyseerr)      printf "  %-18s  Web UI  http://<server-ip>:5055   ⚠ conflicts with overseerr\n"              "$1" ;;
        kavita)          printf "  %-18s  Web UI  http://<server-ip>:5000\n"                                           "$1" ;;
        komga)           printf "  %-18s  Web UI  http://<server-ip>:8090\n"                                           "$1" ;;
        mealie)          printf "  %-18s  Web UI  http://<server-ip>:9000\n"                                           "$1" ;;
        nextcloud)       printf "  %-18s  Web UI  http://nextcloud.local     (Nginx frontend)\n"                       "$1" ;;
        nginx)           printf "  %-18s  Ports :80, :443\n"                                                           "$1" ;;
        ntfy)            printf "  %-18s  Web UI  http://<server-ip>:2586\n"                                           "$1" ;;
        overseerr)       printf "  %-18s  Web UI  http://<server-ip>:5055   ⚠ conflicts with jellyseerr\n"             "$1" ;;
        papermc)
            _mc_ver=$(nix eval --raw nixpkgs#papermc.version 2>/dev/null) || true
            [ -z "$_mc_ver" ] && _mc_ver="unknown"
            _java_ver=$(nix show-derivation nixpkgs#papermc 2>/dev/null \
                | grep -oP 'openjdk-\K\d+' | head -1) || true
            [ -z "$_java_ver" ] && _java_ver="unknown"
            printf "  %-18s  Version: Minecraft Java Edition %s\n"                                       "$1" "$_mc_ver"
            printf "  %-18s  Java:    Server running Java %s  |  Clients: Java %s required\n"           "" "$_java_ver" "$_java_ver"
            printf "  %-18s           (official Minecraft launcher bundles Java automatically)\n"        ""
            printf "  %-18s  Port :25565 (Minecraft Java TCP/UDP)\n"                                    ""
            printf "  %-18s  Connect: Minecraft Java → Multiplayer → <server-ip>:25565\n"              ""
            printf "  %-18s  Files:   /var/lib/minecraft/  (server.properties, plugins/, world/)\n"   ""
            printf "  %-18s  Memory:  set vexos.server.papermc.memory in server-services.nix\n"       ""
            printf "  %-18s  Console: enable-rcon=true in server.properties, then mcrcon\n"           ""
            printf "  %-18s  Monitor: journalctl -fu minecraft-server\n"                              ""
            ;;
        plex)            printf "  %-18s  Web UI  http://<server-ip>:32400/web\n"                                      "$1" ;;
        rustdesk)        printf "  %-18s  Ports :21115-21117 / :21118-21119 (no web UI)\n"                             "$1" ;;
        scrutiny)        printf "  %-18s  Web UI  http://<server-ip>:8080   ⚠ conflicts with arr/traefik dashboard\n" "$1" ;;
        stirling-pdf)    printf "  %-18s  Web UI  http://<server-ip>:8080   ⚠ conflicts with arr/scrutiny\n"           "$1" ;;
        syncthing)       printf "  %-18s  Web UI  http://<server-ip>:8384\n"                                           "$1" ;;
        tautulli)        printf "  %-18s  Web UI  http://<server-ip>:8181\n"                                           "$1" ;;
        traefik)         printf "  %-18s  Ports :80, :443  |  Dashboard http://<server-ip>:8080/dashboard/\n"         "$1" ;;
        uptime-kuma)     printf "  %-18s  Web UI  http://<server-ip>:3001\n"                                           "$1" ;;
        vaultwarden)     printf "  %-18s  Web UI  http://<server-ip>:8222   |  Admin .../admin\n"                      "$1" ;;
        authelia)        printf "  %-18s  Web UI  http://<server-ip>:9091\n"                                                   "$1" ;;
        code-server)     printf "  %-18s  Web UI  http://<server-ip>:4444\n"                                                   "$1" ;;
        dozzle)          printf "  %-18s  Web UI  http://<server-ip>:8888   (requires docker)\n"                               "$1" ;;
        listmonk)        printf "  %-18s  Web UI  http://<server-ip>:9025   ⚠ check port — may conflict with mealie/minio\n"  "$1" ;;
        loki)            printf "  %-18s  API     http://<server-ip>:3100   (no web UI — pair with Grafana)\n"                 "$1" ;;
        matrix-conduit)  printf "  %-18s  API     http://<server-ip>:6167   |  Federation :8448\n"                             "$1" ;;
        minio)           printf "  %-18s  API :9000  Console http://<server-ip>:9001   ⚠ conflicts with mealie\n"             "$1" ;;
        navidrome)       printf "  %-18s  Web UI  http://<server-ip>:4533\n"                                                   "$1" ;;
        netdata)         printf "  %-18s  Web UI  http://<server-ip>:19999\n"                                                  "$1" ;;
        nginx-proxy-manager) printf "  %-18s  Admin http://<server-ip>:81   |  Ports :80, :443\n"                             "$1" ;;
        node-red)        printf "  %-18s  Web UI  http://<server-ip>:1880\n"                                                   "$1" ;;
        paperless)       printf "  %-18s  Web UI  http://<server-ip>:28981\n"                                                  "$1" ;;
        photoprism)      printf "  %-18s  Web UI  http://<server-ip>:2342\n"                                                   "$1" ;;
        portainer)       printf "  %-18s  Web UI  https://<server-ip>:9443  (requires docker)\n"                               "$1" ;;
        prometheus)      printf "  %-18s  Web UI  http://<server-ip>:9090   ⚠ conflicts with cockpit\n"                        "$1" ;;
        proxmox)         printf "  %-18s  Web UI  https://<server-ip>:8006  |  Ports :3128 (SPICE), :5900-5999 (VNC)\n"        "$1" ;;
        unbound)         printf "  %-18s  DNS on :53   ⚠ conflicts with adguard\n"                                             "$1" ;;
        zigbee2mqtt)     printf "  %-18s  Web UI  http://<server-ip>:8088\n"                                                   "$1" ;;
        *)               printf "  %-18s  (no info available)\n"                                                       "$1" ;;
      esac
    }

    if [ -n "$SERVICE" ]; then
        VALID_SERVICES="{{_server_service_names}}"
        if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
            echo "error: unknown service '$SERVICE'"
            echo "available: $VALID_SERVICES"
            exit 1
        fi
        echo ""
        _info "$SERVICE"
        echo ""
    else
        SVC_FILE="/etc/nixos/server-services.nix"
        if [ ! -f "$SVC_FILE" ]; then
            echo ""
            echo "No services enabled yet — run 'just enable <service>' to get started."
            echo ""
            exit 0
        fi
        echo ""
        echo "Enabled services:"
        echo ""
        FOUND=0
        for svc in {{_server_service_names}}; do
            if grep -qF "vexos.server.${svc}.enable = true;" "$SVC_FILE" 2>/dev/null; then
                _info "$svc"
                FOUND=1
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "  (none enabled)"
        fi
        echo ""
    fi

# Show systemctl status and HTTP reachability for a server service.
# Usage: just status jellyfin
[private]
status service: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"

    VALID_SERVICES="{{_server_service_names}}"
    if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
        echo "error: unknown service '$SERVICE'"
        echo "available: $VALID_SERVICES"
        exit 1
    fi

    # Map service → systemd unit(s) and HTTP check URL(s)
    # Format for UNITS: space-separated unit names (without .service)
    # Format for URLS:  space-separated http://localhost:<port> entries (empty = no HTTP check)
    case "$SERVICE" in
      adguard)        UNITS="adguardhome";          URLS="http://localhost:3080" ;;
      arr)            UNITS="sabnzbd sonarr radarr lidarr prowlarr";
                      URLS="http://localhost:8080 http://localhost:8989 http://localhost:7878 http://localhost:8686 http://localhost:9696" ;;
      audiobookshelf) UNITS="audiobookshelf";       URLS="http://localhost:8234" ;;
      caddy)          UNITS="caddy";                URLS="http://localhost:80" ;;
      cockpit)        UNITS="cockpit";              URLS="http://localhost:9090" ;;
      docker)         UNITS="docker";               URLS="" ;;
      forgejo)        UNITS="forgejo";              URLS="http://localhost:3000" ;;
      grafana)        UNITS="grafana";              URLS="http://localhost:3000" ;;
      headscale)      UNITS="headscale";            URLS="http://localhost:8085" ;;
      home-assistant) UNITS="home-assistant";       URLS="http://localhost:8123" ;;
      homepage)       UNITS="docker-homepage";      URLS="http://localhost:3010" ;;
      immich)         UNITS="immich-server";        URLS="http://localhost:2283" ;;
      jellyfin)       UNITS="jellyfin";             URLS="http://localhost:8096" ;;
      jellyseerr)     UNITS="jellyseerr";           URLS="http://localhost:5055" ;;
      kavita)         UNITS="kavita";               URLS="http://localhost:5000" ;;
      komga)          UNITS="komga";                URLS="http://localhost:8090" ;;
      mealie)         UNITS="mealie";               URLS="http://localhost:9000" ;;
      nextcloud)      UNITS="phpfpm-nextcloud nginx"; URLS="http://localhost:80" ;;
      nginx)          UNITS="nginx";                URLS="http://localhost:80" ;;
      ntfy)           UNITS="ntfy";                 URLS="http://localhost:2586" ;;
      overseerr)      UNITS="overseerr";            URLS="http://localhost:5055" ;;
      papermc)        UNITS="minecraft-server";     URLS="" ;;
      plex)           UNITS="plex";                 URLS="http://localhost:32400/web" ;;
      rustdesk)       UNITS="rustdesk-server hbbr hbbs"; URLS="" ;;
      scrutiny)       UNITS="scrutiny";             URLS="http://localhost:8080" ;;
      stirling-pdf)   UNITS="docker-stirling-pdf";   URLS="http://localhost:8080" ;;
      syncthing)      UNITS="syncthing";            URLS="http://localhost:8384" ;;
      tautulli)       UNITS="tautulli";             URLS="http://localhost:8181" ;;
      traefik)        UNITS="traefik";              URLS="http://localhost:8080/dashboard/" ;;
      uptime-kuma)    UNITS="docker-uptime-kuma";   URLS="http://localhost:3001" ;;
      vaultwarden)    UNITS="vaultwarden";          URLS="http://localhost:8222" ;;
      authelia)       UNITS="docker-authelia";          URLS="http://localhost:9091" ;;
      code-server)    UNITS="code-server";              URLS="http://localhost:4444" ;;
      dozzle)         UNITS="docker-dozzle";            URLS="http://localhost:8888" ;;
      listmonk)       UNITS="listmonk";                 URLS="http://localhost:9025" ;;
      loki)           UNITS="loki";                     URLS="http://localhost:3100/ready" ;;
      matrix-conduit) UNITS="conduit";                  URLS="http://localhost:6167/_matrix/client/versions" ;;
      minio)          UNITS="minio";                    URLS="http://localhost:9001 http://localhost:9000" ;;
      navidrome)      UNITS="navidrome";                URLS="http://localhost:4533" ;;
      netdata)        UNITS="netdata";                  URLS="http://localhost:19999" ;;
      nginx-proxy-manager) UNITS="docker-nginx-proxy-manager"; URLS="http://localhost:81" ;;
      node-red)       UNITS="node-red";                 URLS="http://localhost:1880" ;;
      paperless)      UNITS="paperless";                URLS="http://localhost:28981" ;;
      photoprism)     UNITS="photoprism";               URLS="http://localhost:2342" ;;
      portainer)      UNITS="docker-portainer";         URLS="https://localhost:9443" ;;
      prometheus)     UNITS="prometheus";               URLS="http://localhost:9090" ;;
      proxmox)        UNITS="pve-cluster pvedaemon pveproxy pvestatd pvescheduler"; URLS="https://localhost:8006" ;;
      unbound)        UNITS="unbound";                  URLS="" ;;
      zigbee2mqtt)    UNITS="zigbee2mqtt";              URLS="http://localhost:8088" ;;
      *)              UNITS="$SERVICE";             URLS="" ;;
    esac

    # systemctl status for each unit
    for unit in $UNITS; do
        echo ""
        echo "── systemctl status ${unit}.service ──────────────────────────"
        systemctl status "${unit}.service" --no-pager --lines=10 || true
    done

    # HTTP reachability check for each URL
    if [ -n "$URLS" ]; then
        echo ""
        echo "── HTTP reachability ─────────────────────────────────────────"
        for url in $URLS; do
            printf "  %-45s  " "$url"
            http_code=$(curl -o /dev/null -s -k -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "unreachable")
            if [[ "$http_code" =~ ^[0-9]+$ ]]; then
                if [[ "$http_code" -lt 400 ]]; then
                    printf "\033[32m%s\033[0m\n" "$http_code OK"
                else
                    printf "\033[33m%s\033[0m\n" "$http_code"
                fi
            else
                printf "\033[31m%s\033[0m\n" "$http_code"
            fi
        done
    fi
    echo ""

# List all server services and their enabled/disabled status.
[private]
services: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    if [ ! -f "$SVC_FILE" ]; then
        echo "No services have been enabled yet. Run 'just enable <service>' to get started."
        exit 0
    fi
    _check() {
        local svc="$1"
        local nix_name
        nix_name=$(echo "$svc" | sed 's/-/_/g')
        if grep -qP "vexos\.server\.(${svc}|${nix_name})\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            printf "    \033[32m✓\033[0m %s\n" "$svc"
        else
            printf "    \033[90m✗\033[0m %s\n" "$svc"
        fi
    }
    _hdr() { printf "\n  \033[1m%s\033[0m\n" "$1"; }
    echo ""
    echo "Server services (/etc/nixos/server-services.nix):"
    _hdr "Books & Reading";            _check kavita;         _check komga
    _hdr "Communications";             _check matrix-conduit
    _hdr "Files & Storage";            _check immich;         _check nextcloud;     _check syncthing;     _check minio;         _check photoprism
    _hdr "Gaming";                     _check papermc
    _hdr "Infrastructure";             _check caddy;          _check docker;        _check nginx;         _check nginx-proxy-manager;  _check portainer;  _check traefik
    _hdr "Media";                      _check audiobookshelf; _check jellyfin;      _check navidrome;     _check plex;          _check tautulli
    _hdr "Media Requests & Automation";_check arr;            _check jellyseerr;    _check overseerr
    _hdr "Monitoring & Admin";         _check cockpit;        _check dozzle;        _check grafana;       _check loki;          _check netdata;   _check prometheus;  _check scrutiny;  _check uptime-kuma
    _hdr "Networking & Security";      _check adguard;        _check authelia;      _check headscale;     _check unbound;       _check vaultwarden
    _hdr "Productivity";               _check code-server;    _check forgejo;       _check homepage;      _check listmonk;      _check mealie;    _check paperless;   _check stirling-pdf
    _hdr "Remote Access";              _check rustdesk
    _hdr "Smart Home & Notifications"; _check home-assistant; _check node-red;      _check ntfy;          _check zigbee2mqtt
    _hdr "Experimental";               _check proxmox
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
        # {{justfile_directory()}} is the unresolved symlink dir (~), so
        # ~/template/server-services.nix is deployed by home-server.nix.
        # Fall back to the repo checkout locations for dev machines.
        _jf_dir="{{justfile_directory()}}"
        TEMPLATE_SRC=""
        for _candidate in "$_jf_dir" "/etc/nixos" "$HOME/Projects/vexos-nix"; do
            if [ -f "$_candidate/template/server-services.nix" ]; then
                TEMPLATE_SRC="$_candidate/template/server-services.nix"
                break
            fi
        done
        if [ -z "$TEMPLATE_SRC" ]; then
            echo "error: cannot find template/server-services.nix in any known location" >&2
            echo "searched: $_jf_dir /etc/nixos $HOME/Projects/vexos-nix" >&2
            exit 1
        fi
        sudo cp "$TEMPLATE_SRC" "$SVC_FILE"
        sudo sed -i 's/\r//' "$SVC_FILE"  # strip CRLF if template was checked out on Windows
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

    # Plex Pass prompt — ask once at enable time
    PLEX_PASS_ENABLED=false
    if [ "$SERVICE" = "plex" ]; then
        PP_OPTION="vexos.server.plex.plexPass"
        read -r -p "  Do you have a Plex Pass subscription? (enables hardware transcoding) [y/N] " _pp
        if [[ "$_pp" =~ ^[Yy]$ ]]; then
            if grep -qP "^\s*#?\s*${PP_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#?\s*(${PP_OPTION//./\\.})\s*=\s*(true|false)\s*;|\1${PP_OPTION} = true;|" "$SVC_FILE"
            else
                sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${PP_OPTION} = true;|" "$SVC_FILE"
            fi
            PLEX_PASS_ENABLED=true
        fi
    fi

    # Proxmox IP + bridge NIC prompts — both are required at enable time
    if [ "$SERVICE" = "proxmox" ]; then
        IP_OPTION="vexos.server.proxmox.ipAddress"
        _proxmox_ip=""
        while [ -z "$_proxmox_ip" ]; do
            read -r -p "  Enter this server's IP address (required by Proxmox VE): " _proxmox_ip
            # Basic validation: must look like an IP
            if ! echo "$_proxmox_ip" | grep -qP '^\d{1,3}(\.\d{1,3}){3}$'; then
                echo "  Invalid IP address. Please enter a valid IPv4 address (e.g. 192.168.1.100)."
                _proxmox_ip=""
            fi
        done
        if grep -qP "^\s*#?\s*${IP_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${IP_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${IP_OPTION} = \"${_proxmox_ip}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${IP_OPTION} = \"${_proxmox_ip}\";|" "$SVC_FILE"
        fi

        NIC_OPTION="vexos.server.proxmox.bridgeInterface"
        _proxmox_nic=""
        echo "  The bridge NIC is the physical ethernet interface that vmbr0 will use."
        echo "  Find it with: ip link show   (look for enp*, eno*, eth*, etc.)"
        while [ -z "$_proxmox_nic" ]; do
            read -r -p "  Enter the physical NIC name (e.g. enp2s0): " _proxmox_nic
            if ! echo "$_proxmox_nic" | grep -qP '^[a-zA-Z][a-zA-Z0-9@._-]+$'; then
                echo "  Invalid interface name. Examples: enp2s0, eno1, eth0, bond0"
                _proxmox_nic=""
            fi
        done
        if grep -qP "^\s*#?\s*${NIC_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${NIC_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${NIC_OPTION} = \"${_proxmox_nic}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${IP_OPTION} = \"${_proxmox_ip}\";|${IP_OPTION} = \"${_proxmox_ip}\";\n  ${NIC_OPTION} = \"${_proxmox_nic}\";|" "$SVC_FILE"
        fi
    fi

    echo "✓ Enabled: $SERVICE"
    echo "  → Run 'just rebuild' to apply."
    echo ""
    case "$SERVICE" in
      adguard)
        echo "  Service:  adguardhome.service"
        echo "  Web UI:   http://<server-ip>:3080"
        echo "  DNS:      Listens on port 53 — point your router's DNS at this server after enabling."
        ;;
      arr)
        echo "  Services: sabnzbd.service  sonarr.service  radarr.service  lidarr.service  prowlarr.service"
        echo "  Web UIs:"
        echo "    SABnzbd  → http://<server-ip>:8080"
        echo "    Sonarr   → http://<server-ip>:8989"
        echo "    Radarr   → http://<server-ip>:7878"
        echo "    Lidarr   → http://<server-ip>:8686"
        echo "    Prowlarr → http://<server-ip>:9696"
        echo "  About:    Full *arr media automation stack — SABnzbd downloads, Sonarr/Radarr/Lidarr manage libraries, Prowlarr proxies indexers."
        ;;
      audiobookshelf)
        echo "  Service:  audiobookshelf.service"
        echo "  Web UI:   http://<server-ip>:8234"
        echo "  About:    Self-hosted audiobook and podcast streaming server with progress sync and mobile app support."
        ;;
      caddy)
        echo "  Service:  caddy.service"
        echo "  Ports:    :80 (redirects to HTTPS), :443"
        echo "  About:    Reverse proxy with automatic HTTPS via Let's Encrypt. Configure virtual hosts in the module or a Caddyfile."
        ;;
      cockpit)
        echo "  Service:  cockpit.service"
        echo "  Web UI:   http://<server-ip>:9090"
        echo "  About:    Web-based Linux server admin console — manage services, storage, networking, and terminal sessions from a browser."
        echo "  Login:    Use your normal Linux user credentials."
        ;;
      docker)
        echo "  Service:  docker.service"
        echo "  No web UI — manage containers via 'docker' / 'docker compose' on the CLI."
        echo "  About:    Docker container runtime with Compose. Includes a weekly 'docker system prune' timer."
        echo "  Note:     The nimda user is added to the docker group automatically."
        ;;
      forgejo)
        echo "  Service:  forgejo.service"
        echo "  Web UI:   http://<server-ip>:3000"
        echo "  About:    Lightweight self-hosted Git forge (Gitea fork) — issues, pull requests, CI. Registration is disabled by default."
        echo "  Warning:  Port 3000 conflicts with Grafana — enable only one."
        ;;
      grafana)
        echo "  Service:  grafana.service"
        echo "  Web UI:   http://<server-ip>:3000"
        echo "  About:    Metrics and observability dashboard. Pair with Prometheus to graph system and application metrics."
        echo "  Login:    Default admin / admin — change on first login."
        echo "  Warning:  Port 3000 conflicts with Forgejo — enable only one."
        ;;
      headscale)
        echo "  Service:  headscale.service"
        echo "  Web UI:   http://<server-ip>:8085"
        echo "  About:    Self-hosted Tailscale control server for a WireGuard mesh VPN without Tailscale's coordination servers."
        echo "  CLI:      Manage nodes with 'headscale' on the server."
        ;;
      home-assistant)
        echo "  Service:  home-assistant.service"
        echo "  Web UI:   http://<server-ip>:8123"
        echo "  About:    Home automation platform with Zigbee (ZHA), ESPHome, weather, and thousands of smart home integrations."
        echo "  Note:     First run launches an onboarding wizard to create the admin account."
        ;;
      homepage)
        echo "  Container: homepage (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:3010"
        echo "  About:     Customisable self-hosted service dashboard with status widgets and bookmarks. Requires Docker to be enabled."
        ;;
      immich)
        echo "  Service:  immich-server.service"
        echo "  Web UI:   http://<server-ip>:2283"
        echo "  About:    Self-hosted photo and video backup (Google Photos alternative) with mobile apps and face recognition."
        echo "  Note:     Install the Immich mobile app and point it at http://<server-ip>:2283."
        ;;
      jellyfin)
        echo "  Service:  jellyfin.service"
        echo "  Web UI:   http://<server-ip>:8096"
        echo "  About:    Free, open-source media server for streaming movies, TV, music, and photos to any device."
        echo "  Note:     First run launches a setup wizard to add media libraries and create the admin account."
        ;;
      jellyseerr)
        echo "  Service:  jellyseerr.service"
        echo "  Web UI:   http://<server-ip>:5055"
        echo "  About:    Media request and discovery manager for Jellyfin. Routes requests to Radarr/Sonarr."
        echo "  Warning:  Port 5055 conflicts with Overseerr — enable only one."
        ;;
      kavita)
        echo "  Service:  kavita.service"
        echo "  Web UI:   http://<server-ip>:5000"
        echo "  About:    Self-hosted digital reading server for ebooks (EPUB/PDF), comics (CBZ/CBR), and manga with OPDS feed support."
        echo "  Note:     Create the admin account on first visit, then add library folders."
        ;;
      komga)
        echo "  Service:  komga.service"
        echo "  Web UI:   http://<server-ip>:8090"
        echo "  About:    Self-hosted comics and manga server with a built-in web reader and OPDS feed."
        echo "  Note:     Create the admin account on first visit, then add library folders."
        ;;
      mealie)
        echo "  Service:  mealie.service"
        echo "  Web UI:   http://<server-ip>:9000"
        echo "  About:    Self-hosted recipe manager and meal planner with ingredient parsing and recipe import from URLs."
        echo "  Login:    Default changeme@example.com / MyPassword — change immediately after first login."
        ;;
      nextcloud)
        echo "  Service:  phpfpm-nextcloud.service (fronted by Nginx)"
        echo "  Web UI:   http://nextcloud.local"
        echo "  About:    Self-hosted file sync, calendar (CalDAV), and contacts (CardDAV) — Google Drive / OneDrive alternative."
        echo "  Note:     Add a DNS entry or /etc/hosts record pointing 'nextcloud.local' to this server's IP."
        echo "  CLI:      sudo -u nextcloud nextcloud-occ"
        ;;
      nginx)
        echo "  Service:  nginx.service"
        echo "  Ports:    :80, :443"
        echo "  About:    High-performance web server and reverse proxy with HSTS, TLS 1.2+, and recommended cipher suite hardening."
        ;;
      ntfy)
        echo "  Service:  ntfy-sh.service"
        echo "  Web UI:   http://<server-ip>:2586"
        echo "  About:    Self-hosted push notification server. Send alerts to phones or scripts via simple HTTP PUT/POST."
        echo "  Example:  curl -d 'message' http://<server-ip>:2586/mytopic"
        ;;
      overseerr)
        echo "  Service:  overseerr.service"
        echo "  Web UI:   http://<server-ip>:5055"
        echo "  About:    Media request management frontend for Plex — routes requests to Radarr and Sonarr."
        echo "  Warning:  Port 5055 conflicts with Jellyseerr — enable only one."
        ;;
      papermc)
        _mc_ver=$(grep -m1 'Starting minecraft server version\|server version' /var/lib/minecraft/logs/latest.log 2>/dev/null \
            | grep -oP '(?<=version )\S+' | head -1) || true
        [ -z "$_mc_ver" ] && _mc_ver=$(ls /nix/store/*papermc*/share/papermc/paper-*.jar 2>/dev/null \
            | head -1 | grep -oP '(?<=paper-)\S+(?=\.jar)') || true
        [ -z "$_mc_ver" ] && _mc_ver="unknown (start the server once to detect)"
        _java_bin=$(systemctl show minecraft-server.service -p ExecStart --value 2>/dev/null \
            | grep -oP '/nix/store/\S+/bin/java' | head -1) || true
        [ -z "$_java_bin" ] && _java_bin=$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null) || true
        _java_ver=$("$_java_bin" -version 2>&1 | grep -oP '(?<=version ")\d+' | head -1 2>/dev/null) || true
        [ -z "$_java_ver" ] && _java_ver="unknown"
        echo "  Service:  minecraft-server.service"
        echo "  Version:  Minecraft Java Edition $_mc_ver"
        echo "  Java:     Server running Java $_java_ver  |  Clients: Java $_java_ver required (official launcher bundles it automatically)"
        echo "  Port:     25565 (TCP/UDP) — open in your firewall/router for external access."
        echo "  About:    High-performance PaperMC Minecraft Java Edition server (Spigot fork with plugin support)."
        echo ""
        echo "  Connect:  Minecraft Java Edition → Multiplayer → Add Server → <server-ip>:25565"
        echo ""
        echo "  Files:    /var/lib/minecraft/"
        echo "    server.properties  — edit with: sudo nano /var/lib/minecraft/server.properties"
        echo "    world/             — world data"
        echo "    plugins/           — drop .jar plugin files here (Spigot/Bukkit compatible)"
        echo "    logs/              — server logs"
        echo ""
        echo "  Memory:   Default 2G. To change, add to /etc/nixos/server-services.nix:"
        echo "              vexos.server.papermc.memory = \"4G\";"
        echo "            Then run 'just rebuild'."
        echo ""
        echo "  Console:  Enable RCON in server.properties:"
        echo "              enable-rcon=true"
        echo "              rcon.port=25575"
        echo "              rcon.password=<yourpassword>"
        echo "            Then connect: nix run nixpkgs#mcrcon -- -H localhost -P 25575 -p <yourpassword>"
        echo ""
        echo "  Restart:  sudo systemctl restart minecraft-server"
        echo "  Monitor:  journalctl -fu minecraft-server"
        ;;
      plex)
        echo "  Service:  plex.service"
        echo "  Web UI:   http://<server-ip>:32400/web"
        echo "  About:    Proprietary media server with apps on virtually every platform. Supports hardware transcoding with Plex Pass."
        echo "  Note:     Claim your server at plex.tv/claim on first setup (requires a free Plex account)."
        if [ "$PLEX_PASS_ENABLED" = "true" ]; then
            echo "  Plex Pass: Hardware transcoding enabled (vexos.server.plex.plexPass = true)."
        else
            echo "  Plex Pass: Disabled. Re-enable with: just enable-plex-pass"
        fi
        ;;
      rustdesk)
        echo "  Service:  rustdesk-server.service"
        echo "  No web UI — configure RustDesk clients to use this server's IP as the custom relay/ID server."
        echo "  Ports:    TCP 21115–21117 (signal + relay), WebSocket 21118–21119"
        echo "  About:    Self-hosted relay and signal server for RustDesk remote desktop — no dependency on RustDesk's public servers."
        ;;
      scrutiny)
        echo "  Service:  scrutiny.service"
        echo "  Web UI:   http://<server-ip>:8080"
        echo "  About:    Hard drive health dashboard powered by S.M.A.R.T. data with alerts on failing metrics."
        echo "  Warning:  Port 8080 conflicts with SABnzbd (arr) and the Traefik dashboard — check for conflicts."
        ;;
      stirling-pdf)
        echo "  Container: stirling-pdf (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:8080"
        echo "  About:     Web-based PDF toolbox — merge, split, rotate, compress, OCR, watermark, and convert. All processing is local."
        echo "  Warning:   Port 8080 conflicts with SABnzbd (arr) and Scrutiny — check for conflicts."
        ;;
      syncthing)
        echo "  Service:  syncthing.service"
        echo "  Web UI:   http://<server-ip>:8384  (or http://localhost:8384 on the server)"
        echo "  About:    Continuous peer-to-peer file sync for the nimda user — no cloud intermediary required."
        echo "  Note:     Add remote devices by exchanging device IDs in the web UI."
        ;;
      tautulli)
        echo "  Service:  tautulli.service"
        echo "  Web UI:   http://<server-ip>:8181"
        echo "  About:    Monitoring, statistics, and notification service for Plex — tracks play history and usage analytics."
        echo "  Note:     Connect to Plex by entering your Plex token in Settings → Plex Media Server."
        ;;
      traefik)
        echo "  Service:   traefik.service"
        echo "  Ports:     :80 (HTTP), :443 (HTTPS)"
        echo "  Dashboard: http://<server-ip>:8080/dashboard/"
        echo "  About:     Cloud-native reverse proxy with automatic Let's Encrypt TLS and Docker label-based route discovery."
        echo "  Warning:   Dashboard port 8080 conflicts with SABnzbd (arr) and Scrutiny — adjust if running alongside them."
        ;;
      uptime-kuma)
        echo "  Container: uptime-kuma (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:3001"
        echo "  About:     Self-hosted uptime monitoring with a public status page — monitors HTTP, TCP, DNS, and more."
        echo "  Note:      Create the admin account on first visit, then add monitors."
        ;;
      vaultwarden)
        echo "  Service:  vaultwarden.service"
        echo "  Web UI:   http://<server-ip>:8222"
        echo "  Admin:    http://<server-ip>:8222/admin  (set ADMIN_TOKEN in the environment file to enable)"
        echo "  About:    Lightweight Bitwarden-compatible password manager. Use any official Bitwarden client — point it at this server."
        echo "  Warning:  Put Vaultwarden behind a TLS reverse proxy (Caddy/Nginx/Traefik) before exposing outside your local network."
        ;;
      proxmox)
        echo "  Service:  pve-manager.service (+ pvedaemon, pveproxy, pvestatd)"
        echo "  Web UI:   https://<server-ip>:8006"
        echo "  About:    Proxmox VE open-source hypervisor — manage KVM virtual machines and LXC containers from a web UI."
        echo "  Source:   https://github.com/SaumonNet/proxmox-nixos"
        echo "  ⚠  Experimental. Not recommended for production machines."
        echo "  ⚠  You must also set vexos.server.proxmox.ipAddress to this host's IP in server-services.nix."
        echo "  Cache:    nix.settings.substituters = [ \"https://cache.saumon.network/proxmox-nixos\" ]"
        echo "            nix.settings.trusted-public-keys = [ \"proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=\" ]"
        ;;
      authelia)
        echo "  Container: authelia (NixOS OCI container)"
        echo "  Web UI:   http://<server-ip>:9091"
        echo "  About:    Self-hosted SSO and two-factor authentication proxy. Protects apps behind a login portal."
        echo "  Note:     Create /var/lib/authelia/config/configuration.yml before first start."
        echo "            See https://www.authelia.com/configuration/prologue/introduction/ for config reference."
        ;;
      code-server)
        echo "  Service:  code-server.service"
        echo "  Web UI:   http://<server-ip>:4444"
        echo "  About:    Visual Studio Code running in the browser — develop from any device without a local install."
        echo "  Note:     Set vexos.server.code-server.hashedPassword to your argon2 hash string."
        echo "            Generate hash: echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- \"\$(head -c 20 /dev/random | base64)\" -e"
        ;;
      dozzle)
        echo "  Container: dozzle (NixOS OCI container)"
        echo "  Web UI:   http://<server-ip>:8888"
        echo "  About:    Real-time Docker log viewer in the browser. No persistent storage — live tailing only."
        echo "  Note:     Requires Docker to be enabled (just enable docker)."
        ;;
      listmonk)
        echo "  Service:  listmonk.service"
        echo "  Web UI:   http://<server-ip>:9025"
        echo "  About:    Self-hosted newsletter and mailing list manager with campaign analytics."
        echo "  Login:    Default admin / listmonk — change immediately after first login."
        echo "  Warning:  Default port 9000 remapped to 9025 to avoid conflict with Mealie and Minio."
        ;;
      loki)
        echo "  Service:  loki.service"
        echo "  API:      http://<server-ip>:3100"
        echo "  About:    Log aggregation system designed to work with Grafana and Promtail. No standalone web UI."
        echo "  Note:     Add Loki as a data source in Grafana (http://<server-ip>:3100). Use Promtail to ship logs."
        ;;
      matrix-conduit)
        MC_SERVER_NAME=""
        MC_OPTION="vexos.server.matrix-conduit.serverName"
        while [ -z "$MC_SERVER_NAME" ]; do
          read -r -p "  Enter your Matrix server name (e.g. yourdomain.com) [default: localhost]: " MC_SERVER_NAME
          MC_SERVER_NAME="${MC_SERVER_NAME:-localhost}"
        done
        if grep -qP "^\s*#?\s*${MC_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
          sudo sed -i -E "s|^(\s*)#?\s*(${MC_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${MC_OPTION} = \"${MC_SERVER_NAME}\";|" "$SVC_FILE"
        else
          sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${MC_OPTION} = \"${MC_SERVER_NAME}\";|" "$SVC_FILE"
        fi
        echo "✓ Enabled: matrix-conduit (server name: ${MC_SERVER_NAME})"
        echo "  → Run 'just rebuild' to apply."
        echo ""
        echo "  Service:  conduit.service"
        echo "  API:      http://<server-ip>:6167"
        echo "  About:    Lightweight Matrix homeserver (Conduit). Supports encrypted messaging and federation."
        echo "  Note:     Set vexos.server.matrix-conduit.serverName to your domain name before first run."
        echo "            Federation requires a public domain with port 8448 forwarded or a .well-known delegate."
        ;;
      minio)
        echo "  Service:  minio.service"
        echo "  API:      http://<server-ip>:9000"
        echo "  Console:  http://<server-ip>:9001"
        echo "  About:    S3-compatible object storage server. Use as a backend for Nextcloud, Immich, or S3 clients."
        echo "  Warning:  Port 9000 conflicts with Mealie — enable only one."
        echo "  Note:     Create /etc/nixos/minio-credentials with:"
        echo "              MINIO_ROOT_USER=yourusername"
        echo "              MINIO_ROOT_PASSWORD=yourpassword"
        ;;
      navidrome)
        echo "  Service:  navidrome.service"
        echo "  Web UI:   http://<server-ip>:4533"
        echo "  About:    Self-hosted music streaming server with Subsonic API — compatible with DSub, Symfonium, and others."
        echo "  Note:     Set vexos.server.navidrome.musicFolder to your music library path (default: /var/lib/navidrome/music)."
        ;;
      netdata)
        echo "  Service:  netdata.service"
        echo "  Web UI:   http://<server-ip>:19999"
        echo "  About:    Real-time system performance monitoring with per-second metrics and automatic anomaly detection."
        ;;
      nginx-proxy-manager)
        echo "  Container: nginx-proxy-manager (NixOS OCI container)"
        echo "  Admin UI: http://<server-ip>:81"
        echo "  Ports:    :80 (HTTP proxy), :443 (HTTPS proxy)"
        echo "  About:    Web UI for managing Nginx reverse proxy rules with automatic Let's Encrypt TLS."
        echo "  Login:    Default admin@example.com / changeme — change immediately after first login."
        echo "  Warning:  Ports 80 and 443 conflict with Caddy, Nginx, and Traefik — enable only one reverse proxy."
        ;;
      node-red)
        echo "  Service:  node-red.service"
        echo "  Web UI:   http://<server-ip>:1880"
        echo "  About:    Flow-based visual programming tool for wiring together devices, APIs, and online services."
        echo "  Note:     Pairs well with Home Assistant and MQTT for home automation flows."
        ;;
      paperless)
        echo "  Service:  paperless.service"
        echo "  Web UI:   http://<server-ip>:28981"
        echo "  About:    Document management system with OCR, tagging, full-text search, and automatic consumption."
        echo "  Note:     Drop documents into the consume folder — Paperless OCRs and indexes them automatically."
        ;;
      photoprism)
        echo "  Service:  photoprism.service"
        echo "  Web UI:   http://<server-ip>:2342"
        echo "  About:    AI-powered self-hosted photo library with face recognition, geo-tagging, and album organisation."
        echo "  Login:    Default admin / insecure — change immediately after first login."
        ;;
      portainer)
        echo "  Container: portainer (NixOS OCI container)"
        echo "  Web UI:   https://<server-ip>:9443"
        echo "  About:    Web UI for managing Docker containers, images, volumes, and networks."
        echo "  Note:     Requires Docker to be enabled (just enable docker)."
        ;;
      prometheus)
        echo "  Service:  prometheus.service"
        echo "  Web UI:   http://<server-ip>:9090"
        echo "  About:    Time-series metrics collection and alerting. Pair with Grafana for dashboards."
        echo "  Warning:  Port 9090 conflicts with Cockpit — enable only one."
        echo "  Note:     Add scrape targets in the module. Node Exporter is not auto-enabled — add it separately."
        ;;
      unbound)
        echo "  Service:  unbound.service"
        echo "  DNS:      Port 53 (UDP/TCP)"
        echo "  About:    Validating, recursive DNS resolver with DNS-over-TLS forwarding to Cloudflare (1.1.1.1)."
        echo "  Warning:  Port 53 conflicts with AdGuard Home — enable only one DNS service."
        ;;
      zigbee2mqtt)
        Z2M_PORT=""
        Z2M_OPTION="vexos.server.zigbee2mqtt.serialPort"
        while [ -z "$Z2M_PORT" ]; do
          read -r -p "  Enter your Zigbee coordinator serial device [default: /dev/ttyUSB0]: " Z2M_PORT
          Z2M_PORT="${Z2M_PORT:-/dev/ttyUSB0}"
        done
        if grep -qP "^\s*#?\s*${Z2M_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
          sudo sed -i -E "s|^(\s*)#?\s*(${Z2M_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${Z2M_OPTION} = \"${Z2M_PORT}\";|" "$SVC_FILE"
        else
          sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${Z2M_OPTION} = \"${Z2M_PORT}\";|" "$SVC_FILE"
        fi
        echo "✓ Enabled: zigbee2mqtt (serial port: ${Z2M_PORT})"
        echo "  → Run 'just rebuild' to apply."
        echo ""
        echo "  Service:  zigbee2mqtt.service"
        echo "  Web UI:   http://<server-ip>:8088"
        echo "  About:    Bridges Zigbee devices to MQTT, enabling control without vendor clouds."
        echo "  Note:     Set vexos.server.zigbee2mqtt.serialPort to your coordinator device (default: /dev/ttyUSB0)."
        echo "            Requires an MQTT broker — consider enabling Mosquitto separately."
        ;;
    esac
    echo ""

# Toggle Plex Pass hardware transcoding on/off for an already-enabled Plex installation.
# Usage: just enable-plex-pass   /   just disable-plex-pass
[private]
enable-plex-pass: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    PP_OPTION="vexos.server.plex.plexPass"
    if ! grep -q "vexos.server.plex.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        echo "error: Plex is not enabled. Run 'just enable plex' first." >&2
        exit 1
    fi
    if grep -qP "^\s*#?\s*${PP_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
        sudo sed -i -E "s|^(\s*)#?\s*(${PP_OPTION//./\\.})\s*=\s*(true|false)\s*;|\1${PP_OPTION} = true;|" "$SVC_FILE"
    else
        sudo sed -i "s|vexos.server.plex.enable = true;|vexos.server.plex.enable = true;\n  ${PP_OPTION} = true;|" "$SVC_FILE"
    fi
    echo "✓ Plex Pass hardware transcoding enabled."
    echo "  → Run 'just rebuild' to apply."
    echo ""

[private]
disable-plex-pass: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    PP_OPTION="vexos.server.plex.plexPass"
    if grep -qP "^\s*${PP_OPTION//./\\.}\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        sudo sed -i -E "s|^(\s*)(${PP_OPTION//./\\.})\s*=\s*true\s*;|\1${PP_OPTION} = false;|" "$SVC_FILE"
        echo "✓ Plex Pass hardware transcoding disabled."
        echo "  → Run 'just rebuild' to apply."
    else
        echo "Plex Pass is already disabled (or was never set)."
    fi
    echo ""

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

    if ! grep -qF "${OPTION} = true;" "$SVC_FILE" 2>/dev/null; then
        echo "$SERVICE is already disabled."
        exit 0
    fi

    sudo sed -i "s/${OPTION//./\\.} = true;/${OPTION//./\\.} = false;/" "$SVC_FILE"

    echo "✗ Disabled: $SERVICE"
    echo "  → Run 'just rebuild' to apply."

# Rebuild the system using the current variant.
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    echo ""
    echo "Rebuilding ${target}..."
    echo ""
    sudo nixos-rebuild switch --flake "path:/etc/nixos#${target}"
