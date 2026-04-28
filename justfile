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
        echo "    list-services              List all available server service modules"
        echo "    service-info [service]     Show ports and URLs for enabled (or specified) services"
        echo "    services                   List enabled/disabled status of server service modules"
        echo "    status <service>           Show systemctl status and HTTP reachability for a service"
        echo "    enable <service>           Enable a server service module"
        echo "    disable <service>          Disable a server service module"
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
_server_service_names := "adguard arr audiobookshelf caddy cockpit docker forgejo grafana headscale home-assistant homepage immich jellyfin jellyseerr kavita komga mealie nextcloud nginx ntfy overseerr papermc plex proxmox rustdesk scrutiny stirling-pdf syncthing tautulli traefik uptime-kuma vaultwarden"

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

# List all available server service modules (catalog view, no role required).
[private]
list-services:
    #!/usr/bin/env bash
    _hdr() { printf "\n  \033[1m%s\033[0m\n" "$1"; }
    _svc() { printf "    %s\n" "$1"; }
    echo ""
    echo "Available server service modules:"
    _hdr "Books & Reading";            _svc kavita;           _svc komga
    _hdr "Files & Storage";            _svc immich;           _svc nextcloud;       _svc syncthing
    _hdr "Gaming";                     _svc papermc
    _hdr "Infrastructure";             _svc caddy;            _svc docker;          _svc nginx;           _svc traefik
    _hdr "Media";                      _svc audiobookshelf;   _svc jellyfin;        _svc plex;            _svc tautulli
    _hdr "Media Requests & Automation";_svc arr;              _svc jellyseerr;      _svc overseerr
    _hdr "Monitoring & Admin";         _svc cockpit;          _svc grafana;         _svc scrutiny;        _svc uptime-kuma
    _hdr "Networking & Security";      _svc adguard;          _svc headscale;       _svc vaultwarden
    _hdr "Productivity";               _svc forgejo;          _svc homepage;        _svc mealie;          _svc stirling-pdf
    _hdr "Remote Access";              _svc rustdesk
    _hdr "Smart Home & Notifications"; _svc home-assistant;   _svc ntfy
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
            _mc_ver=$(grep -m1 'Starting minecraft server version\|server version' /var/lib/minecraft/logs/latest.log 2>/dev/null \
                | grep -oP '(?<=version )\S+' | head -1)
            [ -z "$_mc_ver" ] && _mc_ver=$(ls /nix/store/*papermc*/share/papermc/paper-*.jar 2>/dev/null \
                | head -1 | grep -oP '(?<=paper-)\S+(?=\.jar)')
            [ -z "$_mc_ver" ] && _mc_ver="unknown"
            _java_bin=$(systemctl show minecraft-server.service -p ExecStart --value 2>/dev/null \
                | grep -oP '/nix/store/\S+/bin/java' | head -1)
            [ -z "$_java_bin" ] && _java_bin=$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)
            _java_ver=$("$_java_bin" -version 2>&1 | grep -oP '(?<=version ")\d+' | head -1 2>/dev/null)
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
            http_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || echo "unreachable")
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
    _hdr "Files & Storage";            _check immich;         _check nextcloud;     _check syncthing
    _hdr "Gaming";                     _check papermc
    _hdr "Infrastructure";             _check caddy;          _check docker;        _check nginx;         _check traefik
    _hdr "Media";                      _check audiobookshelf; _check jellyfin;      _check plex;          _check tautulli
    _hdr "Media Requests & Automation";_check arr;            _check jellyseerr;    _check overseerr
    _hdr "Monitoring & Admin";         _check cockpit;        _check grafana;       _check scrutiny;      _check uptime-kuma
    _hdr "Networking & Security";      _check adguard;        _check headscale;     _check vaultwarden
    _hdr "Productivity";               _check forgejo;        _check homepage;      _check mealie;        _check stirling-pdf
    _hdr "Remote Access";              _check rustdesk
    _hdr "Smart Home & Notifications"; _check home-assistant; _check ntfy
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

    # Proxmox IP prompt — ipAddress is required, ask at enable time
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
            | grep -oP '(?<=version )\S+' | head -1)
        [ -z "$_mc_ver" ] && _mc_ver=$(ls /nix/store/*papermc*/share/papermc/paper-*.jar 2>/dev/null \
            | head -1 | grep -oP '(?<=paper-)\S+(?=\.jar)')
        [ -z "$_mc_ver" ] && _mc_ver="unknown (start the server once to detect)"
        _java_bin=$(systemctl show minecraft-server.service -p ExecStart --value 2>/dev/null \
            | grep -oP '/nix/store/\S+/bin/java' | head -1)
        [ -z "$_java_bin" ] && _java_bin=$(readlink -f "$(command -v java 2>/dev/null)" 2>/dev/null)
        _java_ver=$("$_java_bin" -version 2>&1 | grep -oP '(?<=version ")\d+' | head -1 2>/dev/null)
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
    esac
    echo ""

# Toggle Plex Pass hardware transcoding on/off for an already-enabled Plex installation.
# Usage: just enable-plex-pass   /   just disable-plex-pass
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
