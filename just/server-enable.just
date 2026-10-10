# just/server-enable.just — `just service enable <name>`: per-service prompts, secrets and setup notes.
# Imported by the root justfile; recipe names share one namespace.

# Enable a server service module.  Usage: just service enable docker
[private]
[arg('service', pattern='[a-z0-9][a-z0-9-]*')]
_service-enable service: _require-server-role (_require-known-service service)
    #!/usr/bin/env bash
    set -euo pipefail
    SVC_FILE="/etc/nixos/server-services.nix"
    SERVICE={{quote(service)}}
    source "{{justfile_directory()}}/just/lib.sh"


    # These services ask questions below. Without a terminal (VexPortal's
    # daemon runs recipes with stdin closed) `read` hits EOF and set -e aborts
    # AFTER the enable flag is already written, leaving server-services.nix
    # half-configured — so refuse before writing anything.
    if [ ! -t 0 ]; then
        case "$SERVICE" in
            arr|plex|proxmox|backup|zigbee2mqtt|mediamanager)
                echo "error: enabling '$SERVICE' asks questions — run 'just service enable $SERVICE' in a terminal." >&2
                exit 1
                ;;
        esac
    fi

    # ── Storage-tier advisory ────────────────────────────────────────────────
    # Some services want a specific storage tier. Tell the operator which pool
    # this service expects, detect whether one exists (local pool OR remote
    # mount), and offer to set one up. Never blocks enabling — informational.
    # Single source of truth for service → tier mapping (edit here to reclassify).
    _storage_tier=""
    case "$SERVICE" in
        proxmox)
            _storage_tier="zfs-vm" ;;
        nextcloud|immich|photoprism|paperless|syncthing|forgejo)
            _storage_tier="zfs-live" ;;
        jellyfin|plex|audiobookshelf|arr)
            _storage_tier="mergerfs-bulk" ;;
    esac
    if [ -n "$_storage_tier" ]; then
        case "$_storage_tier" in
            zfs-vm)        echo ""; echo "  Storage: $SERVICE stores VM disks — needs a local ZFS pool." ;;
            zfs-live)      echo ""; echo "  Storage: $SERVICE stores a database + many small files — best on a ZFS dataset (realtime redundancy)." ;;
            mergerfs-bulk) echo ""; echo "  Storage: $SERVICE stores a large media library — best on a mergerfs+SnapRAID pool (mixed-capacity drives)." ;;
        esac

        _local_ok=false; _remote_ok=false
        if [ "$_storage_tier" = "mergerfs-bulk" ]; then
            mountpoint -q /storage 2>/dev/null && _local_ok=true
        else
            [ -n "$(zpool list -H -o name 2>/dev/null | head -1)" ] && _local_ok=true
        fi
        if [ "$_storage_tier" != "zfs-vm" ]; then
            [ -n "$(findmnt -rn -t nfs,nfs4,cifs 2>/dev/null | head -1)" ] && _remote_ok=true
        fi

        if $_local_ok; then
            echo "  ✓ A local pool is present — OK."
        elif $_remote_ok; then
            echo "  ✓ Remote storage is mounted — OK."
        elif [ ! -t 0 ]; then
            echo "  ⚠ No local pool or remote storage detected — set one up before using $SERVICE."
        else
            echo "  ⚠ No local pool or remote storage detected."
            if [ "$_storage_tier" = "zfs-vm" ]; then
                read -r -p "  Create a local ZFS pool now? [y/N]: " _sp
                case "${_sp,,}" in
                    y|yes) {{_just}} zfs-pool create ;;
                    *)     echo "  Skipped — run 'just zfs-pool create' before starting VMs." ;;
                esac
            else
                echo "  Where should its storage live?"
                echo "    1) Local mergerfs+SnapRAID pool   (mixed-capacity drives)"
                echo "    2) Local ZFS pool                 (matched drives / realtime redundancy)"
                echo "    3) Attach a remote storage server (NFS/SMB from another host)"
                echo "    4) Skip — configure later"
                read -r -p "  Choice [1-4]: " _sp
                case "$_sp" in
                    1) {{_just}} mergerfs-pool create ;;
                    2) {{_just}} zfs-pool create ;;
                    3) {{_just}} remote-storage attach ;;
                    *) echo "  Skipped — run 'just mergerfs-pool create', 'just zfs-pool create', or 'just remote-storage attach' later." ;;
                esac
            fi
        fi
    fi

    if [ ! -f "$SVC_FILE" ]; then
        echo "Creating $SVC_FILE from template..."
        seed_from_template server-services.nix "$SVC_FILE"
    fi

    # The option uses dots as-is (e.g. uptime-kuma stays uptime-kuma),
    # except kernel-builder whose module declares camelCase kernelBuilder.
    OPT_NAME="$SERVICE"
    [ "$SERVICE" = "kernel-builder" ] && OPT_NAME="kernelBuilder"
    OPTION="vexos.server.${OPT_NAME}.enable"

    # Arr stack: full-stack or individual-component selection.
    if [ "$SERVICE" = "arr" ]; then
        ARR_COMPONENTS="sabnzbd sonarr radarr lidarr prowlarr qbittorrent bazarr maintainerr"
        if grep -qP '^\s*vexos\.server\.arr\.(enable|\w+\.enable)\s*=\s*true' "$SVC_FILE" 2>/dev/null; then
            echo "arr is already enabled (or has enabled components). Use 'just service disable arr' first to reconfigure."
            exit 0
        fi
        echo "  Enable the full *arr stack, or select individual components?"
        echo "    1. Full"
        echo "    2. Individual"
        read -r -p "  Select [1/2]: " _arr_mode
        if [ "$_arr_mode" = "2" ]; then
            echo "  Select components:"
            _i=0
            for _c in $ARR_COMPONENTS; do
                _i=$((_i + 1))
                printf "    %d. %s\n" "$_i" "$_c"
            done
            read -r -p "  Enter numbers (space or comma separated): " _arr_selected
            _arr_selected="${_arr_selected//,/ }"
            _arr_enabled=""
            for _n in $_arr_selected; do
                _c=$(echo "$ARR_COMPONENTS" | tr ' ' '\n' | sed -n "${_n}p")
                if [ -z "$_c" ]; then
                    echo "  error: invalid selection '$_n' — skipping"
                    continue
                fi
                nix_set "$SVC_FILE" "vexos.server.arr.${_c}.enable" true
                _arr_enabled="$_arr_enabled $_c"
            done
            if [ -z "$_arr_enabled" ]; then
                echo "error: no valid components selected" >&2
                exit 1
            fi
            echo "✓ Enabled arr components:$_arr_enabled"
        else
            nix_set "$SVC_FILE" "$OPTION" true
            _arr_enabled=" sabnzbd sonarr radarr lidarr prowlarr"
            echo "✓ Enabled: $SERVICE (full stack)"
        fi

        echo "  → Run 'just rebuild' to apply."
        echo ""
        echo "  Enabled components:"
        for _c in $_arr_enabled; do
            case "$_c" in
                sabnzbd)     echo "    SABnzbd     → http://<server-ip>:8080" ;;
                sonarr)      echo "    Sonarr      → http://<server-ip>:8989" ;;
                radarr)      echo "    Radarr      → http://<server-ip>:7878" ;;
                lidarr)      echo "    Lidarr      → http://<server-ip>:8686" ;;
                prowlarr)    echo "    Prowlarr    → http://<server-ip>:9696" ;;
                qbittorrent) echo "    qBittorrent → http://<server-ip>:8081" ;;
                bazarr)      echo "    Bazarr      → http://<server-ip>:6767" ;;
                maintainerr) echo "    Maintainerr → http://<server-ip>:6246" ;;
            esac
        done
        exit 0
    fi

    # `backup` is exempt from the "already enabled" early-exit: it may have been
    # auto-enabled with local defaults alongside another service (see the
    # auto-enable block below), and running `just service enable backup` explicitly must
    # still let the user re-point the repository / passwordFile via the
    # interactive prompt block rather than silently no-op.
    if [ "$SERVICE" != "backup" ] && nix_is_set "$SVC_FILE" "$OPTION" true; then
        echo "$SERVICE is already enabled."
        exit 0
    fi

    # If a commented-out or false line exists, replace it
    nix_set "$SVC_FILE" "${OPTION}" true

    # Plex Pass prompt — ask once at enable time
    PLEX_PASS_ENABLED=false
    if [ "$SERVICE" = "plex" ]; then
        PP_OPTION="vexos.server.plex.plexPass"
        read -r -p "  Do you have a Plex Pass subscription? (enables hardware transcoding) [y/N] " _pp
        if [[ "$_pp" =~ ^[Yy]$ ]]; then
            nix_set "$SVC_FILE" "${PP_OPTION}" true
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
        nix_set "$SVC_FILE" "${IP_OPTION}" "\"${_proxmox_ip}\""

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
        nix_set "$SVC_FILE" "${NIC_OPTION}" "\"${_proxmox_nic}\""
    fi

    # Backup repository + password file prompts — both required at enable time.
    if [ "$SERVICE" = "backup" ]; then
        REPO_OPTION="vexos.server.backup.repository"
        _backup_repo=""
        while [ -z "$_backup_repo" ]; do
            read -r -p "  Enter the restic repository (e.g. /mnt/backup/restic-repo or sftp:user@host:/path): " _backup_repo
        done
        nix_set "$SVC_FILE" "${REPO_OPTION}" "\"${_backup_repo}\""

        PW_OPTION="vexos.server.backup.passwordFile"
        _backup_pw_file=""
        echo "  The password file must contain only the restic repository password."
        while [ -z "$_backup_pw_file" ]; do
            read -r -p "  Enter the path to the restic password file (e.g. /etc/nixos/secrets/backup-password): " _backup_pw_file
        done
        if [ ! -f "$_backup_pw_file" ]; then
            sudo mkdir -p "$(dirname "$_backup_pw_file")"
            sudo nix shell nixpkgs#openssl -c openssl rand -base64 48 | sudo tee "$_backup_pw_file" > /dev/null
            sudo chmod 0600 "$_backup_pw_file"
            echo "  Generated a new random password at $_backup_pw_file"
        fi
        nix_set "$SVC_FILE" "${PW_OPTION}" "\"${_backup_pw_file}\""
    fi

    # MediaManager admin e-mail — required by the build assertion (registering
    # with one of these addresses is what makes an account admin).
    if [ "$SERVICE" = "mediamanager" ]; then
        MM_OPTION="vexos.server.mediamanager.adminEmails"
        _mm_email=""
        while [ -z "$_mm_email" ]; do
            read -r -p "  Admin e-mail (register with this address to become admin): " _mm_email
            if ! echo "$_mm_email" | grep -qP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
                echo "  Invalid e-mail address."
                _mm_email=""
            fi
        done
        nix_set "$SVC_FILE" "${MM_OPTION}" "[ \"${_mm_email}\" ]"
    fi

    echo "✓ Enabled: $SERVICE"

    # Ensure Arcane has environmentFile — required by the build assertion.
    # environmentFile (ENCRYPTION_KEY/JWT_SECRET) is auto-generated, mirroring
    # the SearXNG/VexBoard secret pattern below since there is no external
    # value for the user to supply. appUrl defaults to a working
    # http://localhost:<port> value in modules/server/arcane.nix, so no
    # prompt is needed for it — override vexos.server.arcane.appUrl directly
    # in server-services.nix if Arcane is later placed behind a reverse proxy.
    if [ "$SERVICE" = "arcane" ]; then
        ARCANE_ENV_OPTION="vexos.server.arcane.environmentFile"
        ARCANE_SECRET_PATH="/etc/nixos/secrets/arcane-env"

        if ! grep -qP "^\s*${ARCANE_ENV_OPTION//./\\.}\s*=" "$SVC_FILE" 2>/dev/null; then
            if [ ! -f "$ARCANE_SECRET_PATH" ]; then
                sudo mkdir -p /etc/nixos/secrets
                sudo chmod 700 /etc/nixos/secrets
                {
                    printf 'ENCRYPTION_KEY=%s\n' "$(sudo nix shell nixpkgs#openssl -c openssl rand -hex 32)"
                    printf 'JWT_SECRET=%s\n' "$(sudo nix shell nixpkgs#openssl -c openssl rand -hex 32)"
                } | sudo tee "$ARCANE_SECRET_PATH" > /dev/null
                sudo chmod 600 "$ARCANE_SECRET_PATH"
            fi
            nix_set "$SVC_FILE" "${ARCANE_ENV_OPTION}" "\"${ARCANE_SECRET_PATH}\""
        fi
    fi

    # Ensure SearXNG has an environmentFile — server.secret_key in settings.yml
    # is sourced from $SEARXNG_SECRET_KEY, so a working instance requires one.
    # Auto-generated (random value) rather than prompted, since there is no
    # external value for the user to supply — mirrors _ensure_vexboard_secret.
    if [ "$SERVICE" = "searxng" ]; then
        SEARXNG_ENV_OPTION="vexos.server.searxng.environmentFile"
        SEARXNG_SECRET_PATH="/etc/nixos/secrets/searxng.env"
        if ! grep -qP "^\s*${SEARXNG_ENV_OPTION//./\\.}\s*=" "$SVC_FILE" 2>/dev/null; then
            if [ ! -f "$SEARXNG_SECRET_PATH" ]; then
                sudo mkdir -p /etc/nixos/secrets
                sudo chmod 700 /etc/nixos/secrets
                printf 'SEARXNG_SECRET_KEY=%s\n' "$(head -c 48 /dev/urandom | base64)" | sudo tee "$SEARXNG_SECRET_PATH" > /dev/null
                sudo chmod 600 "$SEARXNG_SECRET_PATH"
            fi
            nix_set "$SVC_FILE" "${SEARXNG_ENV_OPTION}" "\"${SEARXNG_SECRET_PATH}\""
        fi
    fi

    # Ensure VexBoard has a secretFile — required by the build assertion.
    # Runs when VexBoard is explicitly enabled.
    _ensure_vexboard_secret() {
        local svc_file="$1"
        local secret_path="/etc/nixos/secrets/vexboard-secret"
        if ! grep -qP "^\s*vexos\.server\.vexboard\.secretFile\s*=" "$svc_file" 2>/dev/null; then
            if [ ! -f "$secret_path" ]; then
                sudo mkdir -p /etc/nixos/secrets
                sudo chmod 700 /etc/nixos/secrets
                printf 'VEXBOARD_AUTH__SECRET=%s\n' "$(head -c 48 /dev/urandom | base64)" | sudo tee "$secret_path" > /dev/null
                sudo chmod 600 "$secret_path"
            fi
            nix_set "$svc_file" vexos.server.vexboard.secretFile "\"${secret_path}\""
        fi
    }

    # Explicit `just service enable vexboard` — ensure secret is generated.
    if [ "$SERVICE" = "vexboard" ]; then
        _ensure_vexboard_secret "$SVC_FILE"
    fi

    # Ensure declarative backups have sane local defaults — repository and
    # passwordFile. Fully non-interactive, mirrors _ensure_vexboard_secret:
    # generates the restic password with the same command the interactive backup
    # block uses (openssl rand -base64 48), and every write is idempotent.
    _ensure_backup_defaults() {
        local svc_file="$1"
        local repo_default="/var/lib/vexos-backup/restic-repo"
        local pw_default="/etc/nixos/secrets/backup-password"
        local repo_opt="vexos.server.backup.repository"
        local pw_opt="vexos.server.backup.passwordFile"

        if ! grep -qP "^\s*${repo_opt//./\\.}\s*=\s*\"[^\"]+\"\s*;" "$svc_file" 2>/dev/null; then
            nix_set "$svc_file" "${repo_opt}" "\"${repo_default}\""
        fi

        if ! grep -qP "^\s*${pw_opt//./\\.}\s*=" "$svc_file" 2>/dev/null; then
            if [ ! -f "$pw_default" ]; then
                sudo mkdir -p /etc/nixos/secrets
                sudo chmod 700 /etc/nixos/secrets
                sudo nix shell nixpkgs#openssl -c openssl rand -base64 48 | sudo tee "$pw_default" > /dev/null
                sudo chmod 600 "$pw_default"
            fi
            nix_set "$svc_file" "${pw_opt}" "\"${pw_default}\""
        fi
    }

    # Auto-enable declarative backups alongside the first service enabled on this
    # host, with non-interactive local defaults. The interactive
    # `just service enable backup` path (above) still owns custom repository / passwordFile
    # configuration for anyone pointing backups at a NAS or remote target.
    if [ "$SERVICE" != "backup" ]; then
        BK_OPTION="vexos.server.backup.enable"
        if ! grep -qP "^\s*vexos\.server\.backup\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            nix_set "$SVC_FILE" "${BK_OPTION}" true
            _ensure_backup_defaults "$SVC_FILE"
            echo "  + Backups also enabled (restic → /var/lib/vexos-backup/restic-repo)"
        fi
    fi

    echo "  → Run 'just rebuild' to apply."
    echo ""
    case "$SERVICE" in
      adguard)
        echo "  Service:  adguardhome.service"
        echo "  Web UI:   http://<server-ip>:3080"
        echo "  DNS:      Listens on port 53 — point your router's DNS at this server after enabling."
        ;;
      arcane)
        echo "  Container: arcane (NixOS OCI container, Docker or Podman backend)"
        echo "  Web UI:    http://<server-ip>:3552"
        echo "  Login:     Default arcane / arcane-admin — you are prompted to change the password on first login."
        echo "  About:     Modern container management UI — browse containers, images, volumes, and networks from a browser."
        echo "  Backend:   vexos.server.arcane.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just service enable podman' first)."
        echo "  appUrl and environmentFile (ENCRYPTION_KEY/JWT_SECRET) were configured above."
        ;;
      attic)
        echo "  Service:  atticd.service"
        echo "  HTTP:     http://<server-ip>:8400"
        echo "  About:    Modern, purpose-built Nix binary cache server. Push derivations from any machine; pull on rebuild."
        echo "  Note:     Credentials and the 'attic' CLI are set up automatically on rebuild."
        echo "  Next:     Run 'just cache bootstrap' after rebuilding to create the cache and mint tokens."
        ;;
      backup)
        echo "  Service:  restic-backups-main.service"
        echo "  About:    Daily restic backup of every enabled service's data directory"
        echo "            (plus a PostgreSQL dump if services.postgresql is enabled)."
        echo "  Run now:  just backup-now"
        echo "  Restore:  just restore-service <name>   (per-service, in place)"
        echo "  Inspect:  restic-main snapshots --tag <service>"
        ;;
      audiobookshelf)
        echo "  Service:  audiobookshelf.service"
        echo "  Web UI:   http://<server-ip>:8234"
        echo "  About:    Self-hosted audiobook and podcast streaming server with progress sync and mobile app support."
        ;;
      caddy)
        echo "  Service:  caddy.service"
        echo "  Ports:    :8880 (redirects to HTTPS), :8443"
        echo "  About:    Reverse proxy with automatic HTTPS via Let's Encrypt. Configure virtual hosts in the module or a Caddyfile."
        ;;
      nas)
        echo "  About:    Umbrella option that enables the full NAS stack in one step:"
        echo "            Cockpit web UI  → http://<server-ip>:9090"
        echo "            + cockpit-navigator   (file browser)"
        echo "            + cockpit-file-sharing (Samba/NFS share manager)"
        echo "            + cockpit-identities   (user/group/password manager)"
        echo "  Note:     Individual sub-options can still be overridden after enabling:"
        echo "              vexos.server.cockpit.navigator.enable = false;"
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
      dockhand)
        echo "  Container: dockhand (NixOS OCI container, Docker or Podman backend)"
        echo "  Web UI:    http://<server-ip>:8073"
        echo "  About:     Modern container management UI — browse containers, Compose stacks, logs, and terminals from a browser."
        echo "  Backend:   vexos.server.dockhand.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just service enable podman' first)."
        echo "  Note:      Port remapped from upstream default 3000 — Forgejo also uses 3000."
        ;;
      forgejo)
        echo "  Service:  forgejo.service"
        echo "  Web UI:   http://<server-ip>:3000"
        echo "  About:    Lightweight self-hosted Git forge (Gitea fork) — issues, pull requests, CI. Registration is disabled by default."
        ;;
      harmonia)
        echo "  Service:  harmonia.service"
        echo "  HTTP:     http://<server-ip>:5000"
        echo "  About:    Serves THIS host's /nix/store as a binary cache. Read-only —"
        echo "            there is no upload API. Paths appear by being built here, or"
        echo "            copied in with: nix copy --to ssh-ng://<this-host> <path>"
        echo "  Note:     The signing key is generated automatically on rebuild."
        echo "  Next:     Run 'just cache harmonia' to verify it is live and print"
        echo "            the client settings for your other machines."
        echo "  Warning:  Serves every store path on this host. Keep it on the LAN."
        ;;
      kernel-builder)
        echo "  Service:  kernel-build-<name>.service (one per configured kernel)"
        echo "  Timer:    nightly at 01:00 by default"
        echo "  About:    Builds the custom kernels in pkgs/kernels/ so other machines"
        echo "            can download them from this host instead of compiling."
        echo "  Requires: Harmonia — building without serving accomplishes nothing."
        echo "  First run: just kernel now      (takes hours; safe to leave)"
        echo "  Watch:     just kernel log"
        echo "  Status:    just kernel status"
        ;;
      chaptarr)
        echo "  Service:  docker-chaptarr.service"
        echo "  Web UI:   http://<server-ip>:8789"
        echo "  About:    Audiobook & ebook collection manager (re-work of Readarr) — single container, SQLite under vexos.server.chaptarr.dataDir."
        echo "  Prowlarr: Add it as a Readarr-type application (the API is compatible)."
        echo "  Note:     Beta upstream. Put root folders and downloads under /data (vexos.server.chaptarr.libraryDir) so imports can hardlink."
        ;;
      grimmory)
        echo "  Services: docker-grimmory.service  docker-grimmory-db.service"
        echo "  Web UI:   http://<server-ip>:6060"
        echo "  About:    Self-hosted digital library for ebooks, comics, and audiobooks (two-container stack: app + dedicated MariaDB)."
        echo "  Login:    Create the admin account on first visit — no default credentials to change."
        echo "  Note:     Drop files in vexos.server.grimmory.bookdropDir for auto-import into vexos.server.grimmory.libraryDir."
        ;;
      headscale)
        echo "  Service:  headscale.service"
        echo "  Web UI:   http://<server-ip>:8085"
        echo "  About:    Self-hosted Tailscale control server for a WireGuard mesh VPN without Tailscale's coordination servers."
        echo "  CLI:      Manage nodes with 'headscale' on the server."
        ;;
      home-registry)
        echo "  Services: docker-home-registry.service  docker-home-registry-db.service"
        echo "  Web UI:   http://<server-ip>:8210"
        echo "  About:    Self-hosted home inventory tracker (two-container stack: app + dedicated Postgres)."
        echo "  Note:     No default admin credentials — create your account from the web UI on first visit."
        ;;
      homepage)
        echo "  Container: homepage (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:3010"
        echo "  About:     Customisable self-hosted service dashboard with status widgets and bookmarks. Requires Docker to be enabled."
        ;;
      humidor)
        echo "  Services: docker-humidor.service  docker-humidor-db.service"
        echo "  Web UI:   http://<server-ip>:9898"
        echo "  About:    Self-hosted cigar/humidor collection tracker (two-container stack: app + dedicated Postgres)."
        echo "  Note:     No default admin credentials — create your account from the web UI on first visit."
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
      joplin)
        echo "  Services: docker-joplin-server.service  docker-joplin-db.service"
        echo "  Web UI:   http://<tailnet-host>:22300   (also reachable from the LAN regardless of openFirewall; bind the port to 127.0.0.1 or the Tailscale IP to restrict it)"
        echo "  About:    Self-hosted sync server for Joplin desktop/mobile clients (two-container stack: app + dedicated Postgres)."
        echo "  Login:    admin@localhost / admin — change from the web UI after first boot."
        echo "  Note:     If clients get 'invalid origin' sync errors, set vexos.server.joplin.baseUrl to your tailnet's fully-qualified MagicDNS name."
        ;;
      mealie)
        echo "  Service:  docker-mealie.service"
        echo "  Web UI:   http://<server-ip>:9010"
        echo "  About:    Self-hosted recipe manager and meal planner with ingredient parsing and recipe import from URLs."
        echo "  Login:    Default changeme@example.com / MyPassword — change immediately after first login."
        ;;
      listenarr)
        echo "  Service:  docker-listenarr.service"
        echo "  Web UI:   http://<server-ip>:4545"
        echo "  About:    Audiobook collection manager (Sonarr/Radarr-style, for audiobooks) — single container."
        echo "  Note:     Upstream publishes only rolling canary builds."
        ;;
      mediamanager)
        echo "  Services: docker-mediamanager.service  docker-mediamanager-db.service"
        echo "  Web UI:   http://<server-ip>:8000"
        echo "  About:    TV/movie request and download manager (two-container stack: app + dedicated Postgres)."
        echo "  Login:    Register with the admin e-mail entered above — that account becomes admin."
        ;;
      sportarr)
        echo "  Service:  docker-sportarr.service"
        echo "  Web UI:   http://<server-ip>:1867"
        echo "  About:    Sonarr-style PVR for sports — events, leagues and fights."
        ;;
      tdarr)
        echo "  Services: tdarr-server.service  tdarr-node-local.service"
        echo "  Web UI:   http://<server-ip>:8265   (node API on :8266)"
        echo "  About:    Distributed transcode automation (FFmpeg/HandBrake), with a local worker node by default."
        echo "  Warning:  Tdarr rewrites files in place by default — test on a copy of a library first."
        ;;
      nextcloud)
        echo "  Service:  phpfpm-nextcloud.service (fronted by Nginx)"
        echo "  Web UI:   http://nextcloud.local"
        echo "  Login:    admin / the password stored in /etc/nixos/secrets/nextcloud-admin-pass (vexos.server.nextcloud.adminPassFile)."
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
      seerr)
        echo "  Service:  seerr.service"
        echo "  Web UI:   http://<server-ip>:5055"
        echo "  About:    Open-source media request manager for Jellyfin, Plex, and Emby — successor to Jellyseerr/Overseerr."
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
            echo "  Plex Pass: Disabled. Re-enable with: just plex-pass enable"
        fi
        ;;
      scrutiny)
        echo "  Service:  scrutiny.service"
        echo "  Web UI:   http://<server-ip>:8078"
        echo "  About:    Hard drive health dashboard powered by S.M.A.R.T. data with alerts on failing metrics."
        ;;
      searxng)
        echo "  Service:  uwsgi.service (SearXNG vassal)"
        echo "  Web UI:   http://<server-ip>:8888  (loopback-only by default — see Note below)"
        echo "  About:    Privacy-respecting metasearch engine — aggregates results from many search"
        echo "            engines without tracking. Hardened by default: uWSGI request logging disabled,"
        echo "            POST-based search submissions (queries never appear in URLs/logs/referrers)."
        echo "  Secret:   Auto-generated at /etc/nixos/secrets/searxng.env (SEARXNG_SECRET_KEY)."
        echo "  Note:     Closed to the network by default (openFirewall=false, binds to 127.0.0.1)."
        echo "            Front it with Caddy/Nginx/Traefik (already in this repo) to expose it, or"
        echo "            set vexos.server.searxng.openFirewall = true for direct LAN access."
        ;;
      syncthing)
        echo "  Service:  syncthing.service"
        echo "  Web UI:   http://<server-ip>:8384  (or http://localhost:8384 on the server)"
        echo "  About:    Continuous peer-to-peer file sync for the nimda user — no cloud intermediary required."
        echo "  Note:     Add remote devices by exchanging device IDs in the web UI."
        ;;
      tautulli)
        echo "  Service:  docker-tautulli.service"
        echo "  Web UI:   http://<server-ip>:8181"
        echo "  About:    Monitoring, statistics, and notification service for Plex — tracks play history and usage analytics."
        echo "  Note:     Connect to Plex by entering your Plex token in Settings → Plex Media Server."
        ;;
      traefik)
        echo "  Service:   traefik.service"
        echo "  Ports:     :8882 (HTTP), :8445 (HTTPS)"
        echo "  Dashboard: http://<server-ip>:8079/dashboard/"
        echo "  About:     Cloud-native reverse proxy with automatic Let's Encrypt TLS and Docker label-based route discovery."
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
      kiji-proxy)
        # ── Auto-patch the package hash if still a placeholder ────────────────
        _KIJI_PKG=""
        _jf_raw="{{justfile_directory()}}"
        _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
        _jf_dir=$(dirname "$_jf_real")
        _walk="$PWD"
        while [ "$_walk" != "/" ] && [ -z "$_KIJI_PKG" ]; do
          [ -f "$_walk/pkgs/kiji-proxy/default.nix" ] && _KIJI_PKG="$_walk/pkgs/kiji-proxy/default.nix"
          _walk=$(dirname "$_walk")
        done
        for _cand in "$_jf_raw" "$_jf_dir" "$HOME/Projects/vexos-nix"; do
          [ -n "$_KIJI_PKG" ] && break
          [ -f "$_cand/pkgs/kiji-proxy/default.nix" ] && _KIJI_PKG="$_cand/pkgs/kiji-proxy/default.nix"
        done
        if [ -n "$_KIJI_PKG" ] && grep -q 'lib\.fakeHash' "$_KIJI_PKG"; then
          echo ""
          echo "  Fetching kiji-proxy package hash (~150 MB download)..."
          _KIJI_URL="https://github.com/dataiku/kiji-proxy/releases/download/v1.0.0/kiji-privacy-proxy-1.0.0-linux-amd64.tar.gz"
          _KIJI_B32=$(nix-prefetch-url --unpack "$_KIJI_URL" 2>/dev/null) || _KIJI_B32=""
          _KIJI_SRI=""
          [ -n "$_KIJI_B32" ] && _KIJI_SRI=$(nix hash to-sri --type sha256 "$_KIJI_B32" 2>/dev/null) || true
          if [ -n "$_KIJI_SRI" ]; then
            sed -i "s|lib\.fakeHash|\"${_KIJI_SRI}\"|" "$_KIJI_PKG"
            echo "  ✓ Package hash set: ${_KIJI_SRI}"
          else
            echo "  ⚠ Could not fetch hash automatically. Run manually then rebuild:"
            echo "      HASH=\$(nix-prefetch-url --unpack $_KIJI_URL)"
            echo "      SRI=\$(nix hash to-sri --type sha256 \"\$HASH\")"
            echo "      sed -i \"s|lib\\.fakeHash|\\\"\$SRI\\\"|\" $_KIJI_PKG"
          fi
        elif [ -n "$_KIJI_PKG" ]; then
          echo "  ✓ Package hash already set."
        else
          echo "  ⚠ Could not find pkgs/kiji-proxy/default.nix — run from the repo root or"
          echo "    set it manually before rebuilding (see pkgs/kiji-proxy/default.nix)."
        fi
        echo ""
        echo "  Service:  kiji-proxy.service"
        echo "  Port:     :8080 (forward proxy + health API)"
        echo "  Health:   http://<server-ip>:8080/health"
        echo "  About:    Local PII-masking proxy for AI API requests (OpenAI, Anthropic, etc.)."
        echo "            Intercepts requests, masks PII with a local ONNX ML model, and restores"
        echo "            originals in responses — all inference runs on-device."
        echo "  Usage:    export HTTP_PROXY=http://localhost:8080"
        echo "            export HTTPS_PROXY=http://localhost:8080"
        echo "  Secrets:  Optional — create an env file and set:"
        echo "              vexos.server.kiji-proxy.environmentFile = \"/etc/nixos/secrets/kiji-proxy.env\";"
        echo "            File contents example: OPENAI_API_KEY=sk-...  LOG_PII_CHANGES=true"
        ;;
      podman)
        echo "  Service:  podman.socket"
        echo "  No web UI — manage containers via 'podman' / 'podman compose' on the CLI."
        echo "  About:    Daemonless OCI container engine with a Docker-compatible socket at /run/podman/podman.sock."
        echo "  Note:     Enable dockhand for a browser-based management UI (just service enable dockhand)."
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
        echo "  Service:  docker-code-server.service"
        echo "  Web UI:   http://<server-ip>:4444"
        echo "  About:    Visual Studio Code running in the browser — develop from any device without a local install."
        echo "  Note:     Set vexos.server.code-server.hashedPassword to your argon2 hash string."
        echo "            Generate hash: echo -n 'yourpassword' | nix run nixpkgs#libargon2 -- \"\$(head -c 20 /dev/random | base64)\" -e"
        ;;
      netdata)
        echo "  Service:  netdata.service"
        echo "  Web UI:   http://<server-ip>:19999"
        echo "  About:    Real-time system performance monitoring with per-second metrics and automatic anomaly detection."
        ;;
      nginx-proxy-manager)
        echo "  Container: nginx-proxy-manager (NixOS OCI container)"
        echo "  Admin UI: http://<server-ip>:81"
        echo "  Ports:    :8881 (HTTP proxy), :8444 (HTTPS proxy)"
        echo "  About:    Web UI for managing Nginx reverse proxy rules with automatic Let's Encrypt TLS."
        echo "  Login:    Default admin@example.com / changeme — change immediately after first login."
        ;;
      paperless)
        echo "  Services: paperless-web.service (+ paperless-scheduler, -consumer, -task-queue)"
        echo "  Web UI:   http://<server-ip>:28981"
        echo "  Login:    No default password — create the admin first: sudo paperless-manage createsuperuser"
        echo "  About:    Document management system with OCR, tagging, full-text search, and automatic consumption."
        echo "  Note:     Drop documents into the consume folder — Paperless OCRs and indexes them automatically."
        ;;
      photoprism)
        echo "  Service:  docker-photoprism.service"
        echo "  Web UI:   http://<server-ip>:2342"
        echo "  About:    AI-powered self-hosted photo library with face recognition, geo-tagging, and album organisation."
        echo "  Login:    Default admin / insecure — change immediately after first login."
        ;;
      portainer)
        echo "  Container: portainer (NixOS OCI container, Docker or Podman backend)"
        echo "  Web UI:   https://<server-ip>:9443"
        echo "  Login:    No default credentials — create the admin account on first visit (Portainer locks setup after ~5 minutes; restart the container if it does)."
        echo "  About:    Web UI for managing containers, images, volumes, and networks."
        echo "  Backend:  vexos.server.portainer.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just service enable podman' first)."
        ;;
      vexboard)
        echo "  Service:  vexboard.service"
        echo "  Web UI:   http://<server-ip>:7280"
        echo "  About:    VexOS Server dashboard — enable explicitly with 'just service enable vexboard'."
        echo "  Note:     To disable: just service disable vexboard"
        echo "  Secret:   Set VEXBOARD_AUTH__SECRET via vexos.server.vexboard.secretFile for production use."
        echo "            Generate a secret:  openssl rand -base64 48"
        ;;
      wishlist)
        echo "  Service:  docker-wishlist.service"
        echo "  Web UI:   http://<server-ip>:3280"
        echo "  About:    Self-hosted wishlist / gift registry (cmintey/wishlist) — single container, SQLite under vexos.server.wishlist.dataDir."
        echo "  Login:    Create the first account on first visit (it becomes the admin) — no default credentials."
        echo "  Note:     If sign-in or uploads fail, set vexos.server.wishlist.origin to the exact URL you browse to (ORIGIN is validated)."
        ;;
      prometheus)
        echo "  Service:  prometheus.service"
        echo "  Web UI:   http://<server-ip>:9092"
        echo "  About:    Time-series metrics collection and alerting."
        echo "  Note:     Add scrape targets in the module. Node Exporter is not auto-enabled — add it separately."
        ;;
      unbound)
        echo "  Service:  unbound.service"
        echo "  DNS:      Port 5335 (UDP/TCP)"
        echo "  About:    Validating, recursive DNS resolver with DNS-over-TLS forwarding to Cloudflare (1.1.1.1)."
        ;;
      zigbee2mqtt)
        Z2M_PORT=""
        Z2M_OPTION="vexos.server.zigbee2mqtt.serialPort"
        while [ -z "$Z2M_PORT" ]; do
          read -r -p "  Enter your Zigbee coordinator serial device [default: /dev/ttyUSB0]: " Z2M_PORT
          Z2M_PORT="${Z2M_PORT:-/dev/ttyUSB0}"
        done
        nix_set "$SVC_FILE" "${Z2M_OPTION}" "\"${Z2M_PORT}\""
        echo "  Service:  zigbee2mqtt.service"
        echo "  Serial:   ${Z2M_PORT}"
        echo "  Web UI:   http://<server-ip>:8088"
        echo "  About:    Bridges Zigbee devices to MQTT, enabling control without vendor clouds."
        echo "  Note:     Set vexos.server.zigbee2mqtt.serialPort to your coordinator device (default: /dev/ttyUSB0)."
        echo "            Requires an MQTT broker — consider enabling Mosquitto separately."
        ;;
    esac
    echo ""
