# just/server.just — Server services: catalog, status, restart, disable, backups and restores.
# Imported by the root justfile; recipe names share one namespace.

# Run `just service list` to see available modules and their status.

# Available server service module names.
# Keep in sync with _service_catalog below, modules/server/default.nix, and
# template/server-services.nix.
_server_service_names := "adguard arcane arr attic audiobookshelf authelia backup caddy chaptarr cockpit code-server docker dockhand forgejo grimmory harmonia headscale kernel-builder home-registry homepage humidor immich jellyfin joplin kiji-proxy listenarr mealie mediamanager nas netdata nextcloud nginx nginx-proxy-manager ntfy paperless papermc photoprism plex podman portainer prometheus proxmox scrutiny searxng seerr sportarr syncthing tautulli tdarr traefik unbound uptime-kuma vaultwarden vexboard wishlist zigbee2mqtt"

# Server service catalog — the source for `just service available` (catalog view).
# One line per module: group|name|description. Groups and order are rendered
# verbatim. Descriptions must not contain a '|'.
# Keep in sync with _server_service_names above, modules/server/default.nix,
# and template/server-services.nix.
_service_catalog := '''
    Books & Reading|chaptarr|Audiobook & ebook collection manager (Readarr successor)
    Books & Reading|grimmory|Self-hosted ebook/comic/audiobook library
    Books & Reading|listenarr|Audiobook collection manager (Sonarr/Radarr-style)
    Files & Storage|immich|Self-hosted photo & video backup
    Files & Storage|nextcloud|File sync, sharing & collaboration suite
    Files & Storage|photoprism|AI-powered photo management & sharing
    Files & Storage|syncthing|Continuous peer-to-peer file synchronisation
    Gaming|papermc|High-performance Minecraft Java server
    Infrastructure|arcane|Web UI for managing Docker/Podman containers
    Infrastructure|attic|Self-hosted Nix binary cache server
    Infrastructure|backup|Declarative restic backups of enabled services
    Infrastructure|caddy|Automatic HTTPS web server & reverse proxy
    Infrastructure|docker|Container runtime (Docker Engine)
    Infrastructure|dockhand|Web UI for managing Docker/Podman containers
    Infrastructure|harmonia|Nix binary cache serving this host's store
    Infrastructure|kernel-builder|Builds custom kernels for Harmonia to serve
    Infrastructure|nginx|High-performance HTTP server & reverse proxy
    Infrastructure|nginx-proxy-manager|Web UI for Nginx reverse proxy & SSL certs
    Infrastructure|podman|Rootless OCI container runtime
    Infrastructure|portainer|Web UI for managing Docker/Podman stacks
    Infrastructure|traefik|Cloud-native edge router & reverse proxy
    Inventory|home-registry|Self-hosted home inventory tracker
    Inventory|humidor|Self-hosted cigar collection inventory tracker
    Media|audiobookshelf|Self-hosted audiobook & podcast server
    Media|jellyfin|Open-source media streaming server
    Media|plex|Personal media library & streaming server
    Media|tautulli|Monitoring & analytics for Plex Media Server
    Media|tdarr|Distributed transcode automation (FFmpeg/HandBrake)
    Media Requests & Automation|arr|*arr suite — Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd, Maintainerr
    Media Requests & Automation|mediamanager|TV/movie request & download manager
    Media Requests & Automation|seerr|Media request manager (Jellyfin, Plex, Emby)
    Media Requests & Automation|sportarr|Sonarr-style PVR for sports events
    Monitoring & Admin|cockpit|Web-based Linux server management console
    Monitoring & Admin|nas|Cockpit + NAS plugins (Samba, NFS, ZFS)
    Monitoring & Admin|netdata|Real-time performance & health monitoring
    Monitoring & Admin|prometheus|Metrics collection & alerting toolkit
    Monitoring & Admin|scrutiny|S.M.A.R.T. disk health monitoring dashboard
    Monitoring & Admin|uptime-kuma|Self-hosted uptime & status page monitoring
    Monitoring & Admin|vexboard|VexOS Server dashboard
    Networking & Security|adguard|DNS-based ad & tracker blocker
    Networking & Security|authelia|Single sign-on & two-factor auth gateway
    Networking & Security|headscale|Self-hosted Tailscale-compatible VPN (WireGuard)
    Networking & Security|unbound|Validating, recursive, caching DNS resolver
    Networking & Security|vaultwarden|Lightweight Bitwarden-compatible password manager
    Productivity|code-server|VS Code running in the browser
    Productivity|forgejo|Self-hosted Git & code collaboration (Gitea fork)
    Productivity|homepage|Customisable server dashboard & start page
    Productivity|joplin|Self-hosted Joplin Server note sync backend
    Productivity|mealie|Self-hosted recipe manager & meal planner
    Productivity|paperless|Document scanning, OCR, tagging & archival
    Productivity|wishlist|Self-hosted wishlist & gift registry
    Smart Home & Notifications|ntfy|Simple HTTP-based push notification server
    Smart Home & Notifications|zigbee2mqtt|Zigbee → MQTT bridge (no proprietary hub needed)
    AI & Privacy|kiji-proxy|Privacy-first OpenAI-compatible AI API proxy
    AI & Privacy|searxng|Privacy-respecting metasearch engine (no tracking, no query logging)
    Experimental|proxmox|Proxmox VE integration (experimental)
'''

# Per-service runtime facts behind `just service status` and `service restart`:
# name|systemd units (space-separated, no .service)|health-check URLs. Units
# that do not exist on a host are skipped at run time, so a docker-/podman-
# pair or an optional unit (tdarr's local node) can both be listed. One line
# for every name in _server_service_names (preflight checks this).
_service_runtime := '''
    adguard|adguardhome|http://localhost:3080
    arcane|docker-arcane podman-arcane|http://localhost:3552
    arr|sabnzbd sonarr radarr lidarr prowlarr docker-maintainerr|http://localhost:8080 http://localhost:8989 http://localhost:7878 http://localhost:8686 http://localhost:9696 http://localhost:6246
    attic|atticd|http://localhost:8400
    audiobookshelf|audiobookshelf|http://localhost:8234
    authelia|docker-authelia|http://localhost:9091
    backup|restic-backups-main|
    caddy|caddy|http://localhost:8880
    chaptarr|docker-chaptarr|http://localhost:8789
    cockpit|cockpit|http://localhost:9090
    code-server|docker-code-server|http://localhost:4444
    docker|docker|
    dockhand|docker-dockhand podman-dockhand|http://localhost:8073
    forgejo|forgejo|http://localhost:3000
    grimmory|docker-grimmory docker-grimmory-db|http://localhost:6060
    harmonia|harmonia|http://localhost:5000
    headscale|headscale|http://localhost:8085
    kernel-builder|kernel-build-ogc|
    home-registry|docker-home-registry docker-home-registry-db|http://localhost:8210
    homepage|docker-homepage|http://localhost:3010
    humidor|docker-humidor docker-humidor-db|http://localhost:9898
    immich|immich-server|http://localhost:2283
    jellyfin|jellyfin|http://localhost:8096
    joplin|docker-joplin-server docker-joplin-db|http://localhost:22300
    kiji-proxy|kiji-proxy|http://localhost:8080/health
    listenarr|docker-listenarr|http://localhost:4545
    mealie|docker-mealie|http://localhost:9010
    mediamanager|docker-mediamanager docker-mediamanager-db|http://localhost:8000
    nas|cockpit|http://localhost:9090
    netdata|netdata|http://localhost:19999
    nextcloud|phpfpm-nextcloud nginx|http://localhost:80
    nginx|nginx|http://localhost:80
    nginx-proxy-manager|docker-nginx-proxy-manager|http://localhost:81
    ntfy|ntfy-sh|http://localhost:2586
    paperless|paperless-web paperless-scheduler paperless-task-queue paperless-consumer|http://localhost:28981
    papermc|minecraft-server|
    photoprism|docker-photoprism|http://localhost:2342
    plex|plex|http://localhost:32400/web
    podman|podman|
    portainer|docker-portainer podman-portainer|https://localhost:9443
    prometheus|prometheus|http://localhost:9092
    proxmox|pve-cluster pvedaemon pveproxy pvestatd pvescheduler|https://localhost:8006
    scrutiny|scrutiny|http://localhost:8078
    searxng|uwsgi|http://localhost:8888
    seerr|seerr|http://localhost:5055
    sportarr|docker-sportarr|http://localhost:1867
    syncthing|syncthing|http://localhost:8384
    tautulli|docker-tautulli|http://localhost:8181
    tdarr|tdarr-server tdarr-node-local|http://localhost:8265
    traefik|traefik|http://localhost:8079/dashboard/
    unbound|unbound|
    uptime-kuma|docker-uptime-kuma|http://localhost:3001
    vaultwarden|vaultwarden|http://localhost:8222
    vexboard|vexboard|http://localhost:7280
    wishlist|docker-wishlist|http://localhost:3280
    zigbee2mqtt|zigbee2mqtt|http://localhost:8088
'''

# Server services (server roles): list, catalog, info, status, restart, enable, disable.
[group('Server')]
[doc('Server services: list, catalog, status, enable, disable (menu)')]
service action="" *args:
    @{{_just}} _menu service "Server services" {{quote(action)}} {{quote(args)}} \
        "list|List enabled services and how to access them||stay" \
        "available|Show the catalog of available service modules||stay" \
        "info|Ports, URLs and notes for all enabled services, or one (optional: service)||stay" \
        "status|systemd status and HTTP reachability of a service|Service name|stay" \
        "restart|Restart a service, clearing any start-limit failure|Service name" \
        "enable|Enable a service module|Service name" \
        "disable|Disable a service module|Service name"

# Plex Pass hardware transcoding (server): enable or disable.
[group('Server')]
[doc('Plex Pass hardware transcoding: enable or disable (menu)')]
plex-pass action="" *args: _require-server-role
    @{{_just}} _menu plex-pass "Plex Pass" {{quote(action)}} {{quote(args)}} \
        "enable|Turn on hardware transcoding for an enabled Plex" \
        "disable|Turn hardware transcoding off"

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

# Guided one-time setup for the sops-nix encrypted secrets backend
# (vexos.secrets.backend = "sops"). Generates the local age key used to
# decrypt secrets on this host, then prints the public key and a .sops.yaml
# snippet to add to the repo. Does not create or encrypt the secrets file
# itself — use the `sops <file>.yaml` edit workflow for that, it's already
# the right tool for the job.
[group('Server')]
[doc("One-time sops-nix setup: create this host's age key")]
secrets-init: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    KEY_FILE="/var/lib/sops-nix/key.txt"

    if [ -f "$KEY_FILE" ]; then
        echo "age key already exists at $KEY_FILE"
    else
        echo "Generating age key at $KEY_FILE ..."
        sudo mkdir -p "$(dirname "$KEY_FILE")"
        sudo nix shell nixpkgs#age -c age-keygen -o "$KEY_FILE"
        sudo chmod 0600 "$KEY_FILE"
    fi

    PUBLIC_KEY=$(sudo nix shell nixpkgs#age -c age-keygen -y "$KEY_FILE" 2>/dev/null || true)
    if [ -z "$PUBLIC_KEY" ]; then
        PUBLIC_KEY=$(sudo grep '^# public key:' "$KEY_FILE" | cut -d' ' -f4)
    fi

    echo ""
    echo "Public key: $PUBLIC_KEY"
    echo ""
    echo "Add this to .sops.yaml in the repo root:"
    echo ""
    echo "creation_rules:"
    echo "  - path_regex: secrets/.*\\.yaml\$"
    echo "    key_groups:"
    echo "      - age:"
    echo "          - $PUBLIC_KEY"
    echo ""
    echo "Then create/edit the secrets file with:  sops secrets/server/secrets.yaml"
    echo "Required keys (see modules/secrets-sops.nix):"
    echo "  nextcloud-admin-pass, photoprism-password,"
    echo "  attic-server-token-rs256-secret-base64,"
    echo "  vexboard-auth-secret, kiji-proxy-openai-key, vaultwarden-admin-token,"
    echo "  authelia-jwt-secret, authelia-session-secret,"
    echo "  authelia-storage-encryption-key"
    echo ""
    echo "Finally, set in your host config:"
    echo "  vexos.secrets.backend = \"sops\";"
    echo "  vexos.secrets.sopsFile = ./secrets/server/secrets.yaml;"

# Manually trigger a restic backup run outside the daily timer.
# Requires vexos.server.backup.enable = true.
[group('Server')]
[doc('Run the restic backup now instead of waiting for the timer')]
backup-now: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl list-unit-files restic-backups-main.service &>/dev/null; then
        echo "error: restic-backups-main.service not found — enable it first with 'just service enable backup && just rebuild'."
        exit 1
    fi
    sudo systemctl start restic-backups-main.service --wait
    echo "✓ Backup run complete. Check status with: systemctl status restic-backups-main.service"

# Show timer schedule and last-run status for every configured nas-sync job
# (vexos.server.nasSync.jobs.<name>). Job names are host-specific (set in
# server-services.nix), so this discovers them from systemd rather than a
# fixed list.
[group('Server')]
[doc('Show the schedule and last result of every nas-sync job')]
nas-sync-status: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    UNITS=$(systemctl list-unit-files 'nas-sync-*.service' --no-legend 2>/dev/null | awk '{print $1}' | sed 's/\.service$//')
    if [ -z "$UNITS" ]; then
        echo "No nas-sync jobs configured — set vexos.server.nasSync.enable = true and at least"
        echo "one vexos.server.nasSync.jobs.<name> entry in server-services.nix, then 'just rebuild'."
        exit 0
    fi
    echo "── Timers ──────────────────────────────────────────"
    systemctl list-timers 'nas-sync-*.timer' --all --no-pager
    for unit in $UNITS; do
        echo ""
        echo "── systemctl status ${unit}.service ──────────────────────────"
        systemctl status "${unit}.service" --no-pager --lines=10 || true
    done

# Manually trigger one nas-sync job outside its scheduled timer.
# Usage: just nas-sync-now tv
[group('Server')]
[doc('Run one nas-sync job now')]
[arg('name', pattern='[A-Za-z0-9][A-Za-z0-9._-]*')]
nas-sync-now name: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    NAME={{quote(name)}}
    UNIT="nas-sync-${NAME}.service"
    if ! systemctl list-unit-files "$UNIT" &>/dev/null; then
        echo "error: $UNIT not found — add vexos.server.nasSync.jobs.${NAME} in server-services.nix"
        echo "       (with vexos.server.nasSync.enable = true), then 'just rebuild'."
        exit 1
    fi
    sudo systemctl start "$UNIT" --wait
    echo "✓ Sync '${NAME}' complete. Check status with: systemctl status $UNIT"
    echo "  Full log: journalctl -u $UNIT"

# Snapshot Plex's data directory (/var/lib/plex) to a single portable tar.gz,
# suitable for moving to a new server. Usage: just backup-plex [dest.tar.gz]
[group('Server')]
[doc("Archive Plex's data to a portable .tar.gz (for moving servers)")]
backup-plex dest="": _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    if ! systemctl list-unit-files plex.service &>/dev/null; then
        echo "error: plex.service not found — enable it first with 'just service enable plex'." >&2
        exit 1
    fi

    DEST={{quote(dest)}}
    if [ -z "$DEST" ]; then
        DEST="plex-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi
    # Recipes run in /etc/nixos (the `just` alias's --working-directory), so
    # resolve a relative path against the directory the command was typed in.
    case "$DEST" in /*) ;; *) DEST="{{invocation_directory()}}/$DEST" ;; esac

    echo "Stopping plex.service..."
    sudo systemctl stop plex.service
    trap 'echo "Restarting plex.service..."; sudo systemctl start plex.service' EXIT

    echo "Archiving /var/lib/plex -> $DEST ..."
    sudo tar czf "$DEST" -C /var/lib plex
    sudo chown "$(id -u):$(id -g)" "$DEST"

    echo ""
    echo "✓ Backup complete: $DEST ($(du -h "$DEST" | cut -f1))"
    echo "  Move this file to the new server, then run: just restore-plex $DEST"

# Restore a Plex data directory backup created by `just backup-plex` onto a
# freshly enabled Plex install (run 'just service enable plex && just rebuild' on the
# new server first). Destructive — overwrites /var/lib/plex after a typed
# confirmation; the previous contents are preserved as a timestamped .bak
# directory rather than deleted. Usage: just restore-plex <tarball>
[group('Server')]
[doc('Restore a backup-plex archive over this Plex install')]
restore-plex tarball: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    TARBALL={{quote(tarball)}}
    # Relative to where the command was typed, not /etc/nixos (see backup-plex).
    case "$TARBALL" in /*) ;; *) TARBALL="{{invocation_directory()}}/$TARBALL" ;; esac
    if [ ! -f "$TARBALL" ]; then
        echo "error: '$TARBALL' not found." >&2
        exit 1
    fi

    if ! systemctl list-unit-files plex.service &>/dev/null; then
        echo "error: plex.service not found — enable it first with 'just service enable plex && just rebuild'." >&2
        exit 1
    fi

    echo "This will stop Plex and replace /var/lib/plex with the contents of:"
    echo "  $TARBALL"
    if [ "$({{_just}} _confirm-typed)" != "true" ]; then
        echo "Aborted — no changes made."
        exit 1
    fi

    echo "Stopping plex.service..."
    sudo systemctl stop plex.service
    trap 'echo "Restarting plex.service..."; sudo systemctl start plex.service' EXIT

    if [ -d /var/lib/plex ]; then
        BAK="/var/lib/plex.bak-$(date +%Y%m%d-%H%M%S)"
        echo "Preserving existing data at $BAK ..."
        sudo mv /var/lib/plex "$BAK"
    fi

    echo "Extracting $TARBALL -> /var/lib/plex ..."
    sudo mkdir -p /var/lib/plex
    sudo tar xzf "$TARBALL" -C /var/lib plex
    sudo chown -R plex:plex /var/lib/plex

    echo ""
    echo "✓ Restore complete."
    echo "  Restarting Plex now — check status with: systemctl status plex"
    echo "  Web UI: http://<server-ip>:32400/web"

# Restore a single service's data from the declarative restic backup repository.
# Requires vexos.server.backup.enable = true. Reads the service's data paths from
# /etc/vexos/backup-paths.json and restores them in place from the newest snapshot
# tagged with the service name (or an explicit snapshot ID passed as the second
# argument — see `restic-main snapshots`). Destructive: files are overwritten in
# place after a typed confirmation. Usage: just restore-service <name> [snapshot]
[group('Server')]
[doc("Restore one service's data from the restic backups")]
[arg('name', pattern='[a-z0-9][a-z0-9-]*')]
[arg('snapshot', pattern='[A-Za-z0-9][A-Za-z0-9._-]*', help='a snapshot ID, or latest')]
restore-service name snapshot="latest": _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    NAME={{quote(name)}}
    SNAP={{quote(snapshot)}}
    MANIFEST=/etc/vexos/backup-paths.json

    RESTIC="$(command -v restic-main || true)"
    if [ -z "$RESTIC" ]; then
        echo "error: restic-main wrapper not found — enable backups with 'just service enable backup && just rebuild'." >&2
        exit 1
    fi
    if [ ! -f "$MANIFEST" ]; then
        echo "error: $MANIFEST not found — rebuild after enabling backups." >&2
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "error: jq not found — rebuild after enabling backups." >&2
        exit 1
    fi

    mapfile -t PATHS < <(jq -r --arg n "$NAME" '.[$n][]?' "$MANIFEST")
    if [ "${#PATHS[@]}" -eq 0 ]; then
        echo "error: '$NAME' has no backup paths registered. Known services:" >&2
        jq -r 'keys[]' "$MANIFEST" | sed 's/^/  /' >&2
        exit 1
    fi

    echo "Restore '$NAME' from snapshot '$SNAP' (tag: $NAME) into:"
    printf '  %s\n' "${PATHS[@]}"
    echo "Existing files at those paths will be overwritten in place."
    if [ "$({{_just}} _confirm-typed)" != "true" ]; then
        echo "Aborted — no changes made."
        exit 1
    fi

    # The managing unit is <name>.service for native services, or
    # docker-/podman-<name>.service for oci-containers services.
    UNIT=""
    for candidate in "${NAME}.service" "docker-${NAME}.service" "podman-${NAME}.service"; do
        if systemctl list-unit-files "$candidate" &>/dev/null && systemctl is-active --quiet "$candidate"; then
            UNIT="$candidate"
            break
        fi
    done
    if [ -n "$UNIT" ]; then
        echo "Stopping $UNIT ..."
        sudo systemctl stop "$UNIT"
        trap 'echo "Restarting $UNIT ..."; sudo systemctl start "$UNIT"' EXIT
    else
        echo "warning: no active unit found for '$NAME' — restoring without stopping it." >&2
    fi

    INCLUDES=()
    for p in "${PATHS[@]}"; do
        INCLUDES+=(--include "$p")
    done

    echo "Restoring ..."
    sudo "$RESTIC" restore "$SNAP" --tag "$NAME" --target / "${INCLUDES[@]}"

    echo ""
    echo "✓ Restore complete for '$NAME'."
    if [ -n "$UNIT" ]; then
        echo "  Check status with: systemctl status $UNIT"
    fi

# List all available server service modules (catalog view, no role required).
[private]
_service-available:
    #!/usr/bin/env bash
    echo ""
    echo "Available server service modules:"
    prev_group=""
    while IFS='|' read -r group name desc; do
        [ -z "$group" ] && continue
        if [ "$group" != "$prev_group" ]; then
            printf "\n  \033[1m%s\033[0m\n" "$group"
            prev_group="$group"
        fi
        printf "    \033[36m%-22s\033[0m  %s\n" "$name" "$desc"
    done <<< '{{ replace(_service_catalog, "'", "'\\''") }}'
    echo ""
    echo "Use 'just service enable <service>' to enable a module on a server host."
    echo ""

# Show access info for server services — ports, URLs, and key notes.
# With no argument shows all currently enabled services; with a name shows that service.
# Usage:  just service info            — all enabled services
#         just service info jellyfin   — specific service
[private]
[arg('service', pattern='|[a-z0-9][a-z0-9-]*')]
_service-info service="":
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE={{quote(service)}}
    SVC_FILE="/etc/nixos/server-services.nix"

    _info() {
      case "$1" in
        adguard)         printf "  %-18s  Web UI  http://<server-ip>:3080   |  DNS on :53\n"                           "$1" ;;
        arr)
            _arr_full=false
            grep -qP '^\s*vexos\.server\.arr\.enable\s*=\s*true' "$SVC_FILE" 2>/dev/null && _arr_full=true
            _arr_parts=""
            _arr_want() {
                if $_arr_full || grep -qP "^\s*vexos\.server\.arr\.$1\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
                    _arr_parts="$_arr_parts $2"
                fi
            }
            _arr_want sabnzbd     "SABnzbd :8080"
            _arr_want sonarr      "Sonarr :8989"
            _arr_want radarr      "Radarr :7878"
            _arr_want lidarr      "Lidarr :8686"
            _arr_want prowlarr    "Prowlarr :9696"
            _arr_want qbittorrent "qBittorrent :8081"
            _arr_want bazarr      "Bazarr :6767"
            _arr_want maintainerr "Maintainerr :6246"
            if [ -z "$_arr_parts" ]; then
                printf "  %-18s  (no arr components enabled)\n" "$1"
            else
                printf "  %-18s %s\n" "$1" "$_arr_parts"
            fi
            ;;
        arcane)          printf "  %-18s  Web UI  http://<server-ip>:3552   (Docker/Podman container manager)\n"       "$1" ;;
        attic)           printf "  %-18s  HTTP    http://<server-ip>:8400   (Nix binary cache)\n"                      "$1" ;;
        audiobookshelf)  printf "  %-18s  Web UI  http://<server-ip>:8234\n"                                           "$1" ;;
        caddy)           printf "  %-18s  Ports :8880, :8443\n"                                                           "$1" ;;
        nas)             printf "  %-18s  Web UI  http://<server-ip>:9090   (Cockpit + NAS plugins)\n"               "$1" ;;
        cockpit)         printf "  %-18s  Web UI  http://<server-ip>:9090\n"                                           "$1" ;;
        docker)          printf "  %-18s  No web UI — docker / docker compose CLI\n"                                   "$1" ;;
        dockhand)        printf "  %-18s  Web UI  http://<server-ip>:8073   (Docker/Podman container manager)\n"      "$1" ;;
        forgejo)         printf "  %-18s  Web UI  http://<server-ip>:3000\n"                                           "$1" ;;
        harmonia)        printf "  %-18s  HTTP    http://<server-ip>:5000   (Nix binary cache)\n"                      "$1" ;;
        kernel-builder)  printf "  %-18s  No web UI — nightly timer; see 'just kernel status'\n"            "$1" ;;
        chaptarr)        printf "  %-18s  Web UI  http://<server-ip>:8789\n"                                           "$1" ;;
        grimmory)        printf "  %-18s  Web UI  http://<server-ip>:6060\n"                                           "$1" ;;
        headscale)       printf "  %-18s  Web UI  http://<server-ip>:8085\n"                                           "$1" ;;
        home-registry)   printf "  %-18s  Web UI  http://<server-ip>:8210\n"                                           "$1" ;;
        homepage)        printf "  %-18s  Web UI  http://<server-ip>:3010   (requires docker)\n"                       "$1" ;;
        humidor)         printf "  %-18s  Web UI  http://<server-ip>:9898\n"                                           "$1" ;;
        immich)          printf "  %-18s  Web UI  http://<server-ip>:2283\n"                                           "$1" ;;
        jellyfin)        printf "  %-18s  Web UI  http://<server-ip>:8096\n"                                           "$1" ;;
        joplin)          printf "  %-18s  Web UI  http://<tailnet-host>:22300   (also reachable from the LAN)\n"                     "$1" ;;
        kiji-proxy)      printf "  %-18s  Proxy   http://127.0.0.1:8080   |  Health: http://localhost:8080/health\n"    "$1" ;;
        mealie)          printf "  %-18s  Web UI  http://<server-ip>:9010\n"                                           "$1" ;;
        listenarr)       printf "  %-18s  Web UI  http://<server-ip>:4545\n"                                           "$1" ;;
        mediamanager)    printf "  %-18s  Web UI  http://<server-ip>:8000\n"                                           "$1" ;;
        sportarr)        printf "  %-18s  Web UI  http://<server-ip>:1867\n"                                           "$1" ;;
        tdarr)           printf "  %-18s  Web UI  http://<server-ip>:8265\n"                                           "$1" ;;
        nextcloud)       printf "  %-18s  Web UI  http://nextcloud.local     (Nginx frontend)\n"                       "$1" ;;
        nginx)           printf "  %-18s  Ports :80, :443\n"                                                           "$1" ;;
        ntfy)            printf "  %-18s  Web UI  http://<server-ip>:2586\n"                                           "$1" ;;
        seerr)           printf "  %-18s  Web UI  http://<server-ip>:5055\n"                                           "$1" ;;
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
        podman)          printf "  %-18s  No web UI — podman / podman compose CLI\n"                                   "$1" ;;
        scrutiny)        printf "  %-18s  Web UI  http://<server-ip>:8078\n"                                           "$1" ;;
        searxng)         printf "  %-18s  Web UI  http://<server-ip>:8888   (loopback-only by default)\n"              "$1" ;;
        syncthing)       printf "  %-18s  Web UI  http://<server-ip>:8384\n"                                           "$1" ;;
        tautulli)        printf "  %-18s  Web UI  http://<server-ip>:8181\n"                                           "$1" ;;
        traefik)         printf "  %-18s  Ports :8882, :8445  |  Dashboard http://<server-ip>:8079/dashboard/\n"       "$1" ;;
        uptime-kuma)     printf "  %-18s  Web UI  http://<server-ip>:3001\n"                                           "$1" ;;
        vaultwarden)     printf "  %-18s  Web UI  http://<server-ip>:8222   |  Admin .../admin\n"                      "$1" ;;
        vexboard)        printf "  %-18s  Web UI  http://<server-ip>:7280   (server dashboard)\n" "$1" ;;
        wishlist)        printf "  %-18s  Web UI  http://<server-ip>:3280\n"                                          "$1" ;;
        authelia)        printf "  %-18s  Web UI  http://<server-ip>:9091\n"                                                   "$1" ;;
        code-server)     printf "  %-18s  Web UI  http://<server-ip>:4444\n"                                                   "$1" ;;
        netdata)         printf "  %-18s  Web UI  http://<server-ip>:19999\n"                                                  "$1" ;;
        nginx-proxy-manager) printf "  %-18s  Admin http://<server-ip>:81   |  Ports :8881, :8444\n"                         "$1" ;;
        paperless)       printf "  %-18s  Web UI  http://<server-ip>:28981\n"                                                  "$1" ;;
        photoprism)      printf "  %-18s  Web UI  http://<server-ip>:2342\n"                                                   "$1" ;;
        portainer)       printf "  %-18s  Web UI  https://<server-ip>:9443  (Docker/Podman container manager)\n"               "$1" ;;
        prometheus)      printf "  %-18s  Web UI  http://<server-ip>:9092\n"                                               "$1" ;;
        proxmox)         printf "  %-18s  Web UI  https://<server-ip>:8006  |  Ports :3128 (SPICE), :5900-5999 (VNC)\n"        "$1" ;;
        unbound)         printf "  %-18s  DNS on :5335\n"                                                                  "$1" ;;
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
        if [ ! -f "$SVC_FILE" ]; then
            echo ""
            echo "No services enabled yet — run 'just service enable <service>' to get started."
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
            elif [ "$svc" = "arr" ] && grep -qP '^\s*vexos\.server\.arr\.\w+\.enable\s*=\s*true' "$SVC_FILE" 2>/dev/null; then
                _info "$svc"
                FOUND=1
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "  (none enabled)"
        fi
        echo ""
    fi

# Guard: abort unless `service` is one of _server_service_names.
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
[private]
_require-known-service service:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE={{quote(service)}}
    VALID_SERVICES="{{_server_service_names}}"
    if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
        echo "error: unknown service '$SERVICE'"
        echo "available: $VALID_SERVICES"
        exit 1
    fi

# Map a service name to its systemd unit(s) — shared by status and restart.
# Only units that exist on this host are printed: some services list both a
# docker- and a podman- unit, or an optional one (tdarr's local node), and
# `systemctl restart` fails outright if any unit it is given does not exist.
# Prints space-separated unit names (without .service) to stdout.
[private]
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
_service-units service:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE={{quote(service)}}
    _candidates() {
        local units
        units=$(printf '%s\n' {{quote(_service_runtime)}} \
            | awk -F'|' -v s="$SERVICE" '{ sub(/^[ \t]+/, "", $1) } $1 == s { print $2; exit }')
        echo "${units:-$SERVICE}"
    }
    _found=""
    for unit in $(_candidates); do
        systemctl list-unit-files "${unit}.service" &>/dev/null && _found="${_found:+$_found }$unit"
    done
    echo "$_found"

# Show systemctl status and HTTP reachability for a server service.
# Usage: just service status jellyfin
[private]
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
_service-status service: _require-server-role (_require-known-service service)
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE={{quote(service)}}


    UNITS=$({{_just}} _service-units "$SERVICE")
    if [ -z "$UNITS" ]; then
        echo ""
        echo "No systemd units for '$SERVICE' exist on this host — is it enabled and rebuilt?"
    fi

    # Health-check URL(s) for this service, from _service_runtime.
    URLS=$(printf '%s\n' {{quote(_service_runtime)}} \
        | awk -F'|' -v s="$SERVICE" '{ sub(/^[ \t]+/, "", $1) } $1 == s { print $3; exit }')

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

# Restart a server service (all its systemd units), clearing any prior
# start-limit-hit failure first. Usage: just service restart joplin
[private]
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
_service-restart service: _require-server-role (_require-known-service service)
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE={{quote(service)}}


    UNITS=$({{_just}} _service-units "$SERVICE")
    if [ -z "$UNITS" ]; then
        echo "error: no systemd units for '$SERVICE' exist on this host — is it enabled and rebuilt?" >&2
        exit 1
    fi
    UNIT_SERVICES=""
    for unit in $UNITS; do
        UNIT_SERVICES="$UNIT_SERVICES ${unit}.service"
    done

    echo "Restarting: $SERVICE ($UNIT_SERVICES )"
    echo ""

    # Clear any prior start-limit-hit failures so the units can actually restart.
    sudo systemctl reset-failed $UNIT_SERVICES || true

    # Restart all units in one transaction so systemd honors After=/Requires=
    # ordering between them (e.g. a db unit before the app unit that depends on it).
    sudo systemctl restart $UNIT_SERVICES

    for unit in $UNITS; do
        echo ""
        echo "── systemctl status ${unit}.service ──────────────────────────"
        systemctl status "${unit}.service" --no-pager --lines=5 || true
    done
    echo ""

# List enabled server services and how to access them.
[private]
_service-list: _require-server-role
    @{{_just}} service info

# Toggle Plex Pass hardware transcoding on/off for an already-enabled Plex installation.
# Usage: just plex-pass enable   /   just plex-pass disable
[private]
_plex-pass-enable: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{justfile_directory()}}/just/lib.sh"
    SVC_FILE="/etc/nixos/server-services.nix"
    PP_OPTION="vexos.server.plex.plexPass"
    if ! grep -q "vexos.server.plex.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        echo "error: Plex is not enabled. Run 'just service enable plex' first." >&2
        exit 1
    fi
    nix_set "$SVC_FILE" "${PP_OPTION}" true
    echo "✓ Plex Pass hardware transcoding enabled."
    echo "  → Run 'just rebuild' to apply."
    echo ""

[private]
_plex-pass-disable: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{justfile_directory()}}/just/lib.sh"
    SVC_FILE="/etc/nixos/server-services.nix"
    PP_OPTION="vexos.server.plex.plexPass"
    if grep -qP "^\s*${PP_OPTION//./\\.}\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        nix_set "$SVC_FILE" "$PP_OPTION" false
        echo "✓ Plex Pass hardware transcoding disabled."
        echo "  → Run 'just rebuild' to apply."
    else
        echo "Plex Pass is already disabled (or was never set)."
    fi
    echo ""

# Remove entries for services that no longer exist from server-services.nix.
# The valid-name list is derived from the repo's option declarations, so this
# needs no maintenance when a service is added or removed. Run straight from
# GitHub so it works even before a rebuild has installed the current tooling.
#
# Deliberately main, not the host's locked revision: `just update` restores
# flake.lock when it stops, so the locked revision is the OLD one that still
# declares the removed service. Pruning against that would find nothing and
# leave the next update failing exactly as before.
[private]
prune-services: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    sudo nix --extra-experimental-features "nix-command flakes" \
        run "github:VictoryTek/vexos-nix#prune-services" -- --apply

# Disable a server service module.  Usage: just service disable docker
[private]
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
_service-disable service: _require-server-role (_require-known-service service)
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    SERVICE={{quote(service)}}


    if [ ! -f "$SVC_FILE" ]; then
        echo "No server-services.nix found. Nothing to disable."
        exit 0
    fi

    OPT_NAME="$SERVICE"
    [ "$SERVICE" = "kernel-builder" ] && OPT_NAME="kernelBuilder"
    OPTION="vexos.server.${OPT_NAME}.enable"

    # Arr stack may have been enabled as a whole (top-level flag) or as
    # individual components (per-component flags) — sweep both.
    if [ "$SERVICE" = "arr" ]; then
        ARR_FOUND=0
        for _opt in vexos.server.arr.enable \
                    vexos.server.arr.sabnzbd.enable vexos.server.arr.sonarr.enable \
                    vexos.server.arr.radarr.enable vexos.server.arr.lidarr.enable \
                    vexos.server.arr.prowlarr.enable vexos.server.arr.qbittorrent.enable \
                    vexos.server.arr.bazarr.enable vexos.server.arr.maintainerr.enable; do
            if grep -qF "${_opt} = true;" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i "s/${_opt//./\\.} = true;/${_opt//./\\.} = false;/" "$SVC_FILE"
                ARR_FOUND=1
            fi
        done
        if [ "$ARR_FOUND" -eq 0 ]; then
            echo "$SERVICE is already disabled."
            exit 0
        fi
        echo "✗ Disabled: $SERVICE"
        echo "  → Run 'just rebuild' to apply."
        exit 0
    fi

    if ! grep -qF "${OPTION} = true;" "$SVC_FILE" 2>/dev/null; then
        echo "$SERVICE is already disabled."
        exit 0
    fi

    sudo sed -i "s/${OPTION//./\\.} = true;/${OPTION//./\\.} = false;/" "$SVC_FILE"

    echo "✗ Disabled: $SERVICE"
    echo "  → Run 'just rebuild' to apply."
