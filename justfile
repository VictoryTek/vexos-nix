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
        echo ""
    fi

# ── System Build & Deploy ────────────────────────────────────────────────────

# Print the active role and GPU variant (e.g. vexos-desktop-amd).
[group('System Build & Deploy')]
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

        # Check for the target by looking for its quoted name in flake.nix.
        # This covers both the repo's hostList format ({ name = "vexos-…"; })
        # and the template's explicit attrset format (vexos-… = mkVariant …).
        # Avoids a full `nix eval` which can fail on fresh template installs
        # before all flake inputs are cached.
        if grep -qF "\"${TARGET}\"" "$_d_real/flake.nix" 2>/dev/null; then
            echo "$_d_real"
            exit 0
        fi
    done

    echo "error: no flake found for target '${TARGET}'" >&2
    echo "attempted directories:" >&2
    for _t in "${TRIED[@]}"; do
        echo "  - $_t" >&2
    done
    echo "expected: nixosConfigurations.${TARGET}" >&2
    echo "" >&2
    echo "Hint: pass an explicit flake path: just switch <role> <gpu> /path/to/repo" >&2
    exit 1

# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                  — interactive prompt
#   just switch desktop amd      — direct switch
#   just switch desktop amd .    — explicit flake override
[group('System Build & Deploy')]
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
        echo "  6) vanilla"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-6] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop)         ROLE="desktop"         ;;
                2|stateless)       ROLE="stateless"       ;;
                3|htpc)            ROLE="htpc"            ;;
                4|server)          ROLE="server"          ;;
                5|headless-server) ROLE="headless-server" ;;
                6|vanilla)         ROLE="vanilla"         ;;
                *) echo "Invalid — enter 1-6 or desktop/stateless/htpc/server/headless-server/vanilla" ;;
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
            echo ""
            while true; do
                printf "Choice [1-2]: "
                read -r INPUT
                case "${INPUT}" in
                    1) break ;;
                    2) VARIANT="nvidia-legacy535"; break ;;
                    *) echo "Invalid — enter 1 or 2" ;;
                esac
            done
        fi
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    if ! sudo nixos-rebuild switch --impure --flake "path:${_flake_dir}#${TARGET}"; then
        _rc=$?
        if [ $_rc -eq 4 ]; then
            echo ""
            echo "Note: nixos-rebuild exited $_rc — one or more units could not be stopped or restarted."
            echo "      This is expected when switching between configs that differ in /tmp or other"
            echo "      always-mounted resources. The configuration has been applied."
            echo "      Reboot to complete the transition cleanly."
            echo ""
            echo "      If your shell prompt shows errors (e.g. 'starship: No such file or directory'),"
            echo "      they are from the current session's old profile. Open a new terminal."
        else
            exit $_rc
        fi
    fi

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
[group('System Build & Deploy')]
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

# Rebuild the system using the current variant.
[group('System Build & Deploy')]
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    echo ""
    echo "Rebuilding ${target}..."
    echo ""
    sudo nixos-rebuild switch --impure --flake "path:/etc/nixos#${target}"

# Update all flake inputs, then rebuild and switch using the current variant.
[group('System Build & Deploy')]
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
            echo ""
            while true; do
                printf "Choice [1-2]: "
                read -r INPUT
                case "${INPUT}" in
                    1) break ;;
                    2) VARIANT="nvidia-legacy535"; break ;;
                    *) echo "Invalid — enter 1 or 2" ;;
                esac
            done
        fi

        target="vexos-${ROLE}-${VARIANT}"
    fi

    echo ""
    echo "Updating to: ${target}"
    echo ""

    # vexos-update (installed by modules/nix.nix) uses a known-heavy block
    # engine before applying any update:
    #   Non-heavy — system glue, vexos scripts, Rust crates, binary wrappers;
    #               build locally in seconds-to-minutes; logged as VEXOS_LOCAL_BUILD,
    #               update proceeds normally.
    #   Heavy     — kernel modules, NVIDIA driver, OpenRazer DKMS; take hours;
    #               update paused, flake.lock restored, logged as VEXOS_CACHE_BLOCK.
    # The script also handles flake.lock backup/restore and nixos-rebuild switch.
    # Up uses the same script so behaviour is identical regardless of update path.
    sudo vexos-update

# Update all flake inputs and rebuild unconditionally — no cache-safety check.
#
# Use this when you explicitly want to force all updates through regardless of
# cache state and are willing to wait for a local source compile.
#
# WARNING: may compile large packages from source (Rust, LLVM, kernels, etc.)
# and take a long time.  For normal daily use, run 'just update' instead.
[group('System Build & Deploy')]
update-all:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [ -z "$target" ]; then
        echo "error: /etc/nixos/vexos-variant not found. Run 'just switch' first." >&2
        exit 1
    fi
    echo ""
    echo "Updating all flake inputs (no cache check)..."
    sudo nix --extra-experimental-features "nix-command flakes" \
        flake update --flake path:/etc/nixos
    echo ""
    echo "Rebuilding: ${target}"
    sudo nixos-rebuild switch --impure \
        --flake path:/etc/nixos#"${target}" \
        --print-build-logs

# Deploy config changes only — pulls the latest vexos-nix commit from GitHub
# WITHOUT updating nixpkgs or any other flake input.
#
# Run this when just update reports a VEXOS_CACHE_BLOCK (nixpkgs has packages
# not yet in the binary cache).  Your latest config changes land immediately
# while nixpkgs stays pinned.  Run just update again in 1-2 days once the
# cache has caught up.
#
# nixpkgs and all other inputs stay pinned at whatever version is
# currently in /etc/nixos/flake.lock — no source builds triggered.
[group('System Build & Deploy')]
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [ -z "$target" ]; then
        echo "error: /etc/nixos/vexos-variant not found. Run 'just switch' first." >&2
        exit 1
    fi
    echo ""
    echo "Pulling latest vexos-nix config (nixpkgs unchanged)..."
    sudo nix flake update vexos-nix --flake path:/etc/nixos
    echo ""
    echo "Switching to: ${target}"
    sudo nixos-rebuild switch --impure --flake path:/etc/nixos#"${target}"

# ── System Upgrades & Rollbacks ──────────────────────────────────────────────

# Analyse what would happen if you upgrade NixOS to a newer version.
# Tests your current config against the target nixpkgs WITHOUT modifying
# anything — no files changed, no lock file touched.
#
# Reports:
#   • Whether your config evaluates cleanly (option renames/removals)
#   • Which packages are not yet in the new nixpkgs binary cache
#   • A recommendation on whether it is safe to push the version upgrade
#
# Usage:
#   just upgrade-analysis 26.05    — analyse upgrade to 26.05
#   just upgrade-analysis 26.11    — analyse upgrade to 26.11
[group('System Upgrades & Rollbacks')]
upgrade-analysis target_version:
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET="{{target_version}}"
    VARIANT=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [ -z "$VARIANT" ]; then
        echo "error: /etc/nixos/vexos-variant not found. Run 'just switch' first." >&2
        exit 1
    fi

    # Detect current nixpkgs branch from flake.lock — match the exact key
    # "nixpkgs" so nixpkgs-unstable is not picked up first.
    CURRENT=$(jq -r '.nodes.nixpkgs.original.ref // "unknown" | ltrimstr("nixos-")' \
        /etc/nixos/flake.lock 2>/dev/null || echo "unknown")

    NIXPKGS_URL="github:NixOS/nixpkgs/nixos-${TARGET}"
    HM_URL="github:nix-community/home-manager/release-${TARGET}"

    # Same heavy-build regex as vexos-update — packages that take hours due to
    # kernel compilation (kernel modules, NVIDIA driver, OpenRazer DKMS module).
    HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'

    echo ""
    echo "================================================================"
    printf "  vexos-nix Upgrade Analysis: %s → %s\n" "${CURRENT}" "${TARGET}"
    echo "  $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================"
    echo ""
    echo "  Variant:      ${VARIANT}"
    echo "  nixpkgs:      nixos-${CURRENT} → nixos-${TARGET}"
    echo "  home-manager: release-${CURRENT} → release-${TARGET}"
    echo ""
    echo "  NOTE: This is read-only. Nothing on your system will be changed."
    echo "  First run may take a minute to fetch new nixpkgs metadata."
    echo ""

    # ── [1/3] Configuration Evaluation ──────────────────────────────────────
    echo "────────────────────────────────────────────────────────────────"
    echo "  [1/3] Configuration Evaluation"
    echo "────────────────────────────────────────────────────────────────"
    echo ""

    FLAKE_TARGET="git+file:///etc/nixos"
    FLAKE_TARGET="${FLAKE_TARGET}#${VARIANT}"

    DRY_OUTPUT=$(sudo nixos-rebuild dry-build \
        --flake "${FLAKE_TARGET}" \
        --override-input vexos-nix/nixpkgs  "${NIXPKGS_URL}" \
        --override-input vexos-nix/home-manager "${HM_URL}" \
        2>&1) && EVAL_EXIT=0 || EVAL_EXIT=$?

    if [ "$EVAL_EXIT" -ne 0 ]; then
        echo "  ✗ FAIL  Configuration evaluation failed against nixos-${TARGET}."
        echo ""
        echo "  ── Evaluation errors ──────────────────────────────────────────"
        echo ""
        # Print the full output — nix errors are multi-line and losing context
        # makes them impossible to act on.  Strip the sudo password prompt line.
        printf '%s\n' "$DRY_OUTPUT" \
            | grep -v '^\[sudo\]' \
            | sed 's/^/    /'
        echo ""
        echo "  ── What this means ────────────────────────────────────────────"
        echo "  These errors must be fixed in the vexos-nix config before you"
        echo "  can upgrade.  Common causes:"
        echo "    • A NixOS option was renamed or removed in ${TARGET}"
        echo "    • A package was removed from nixpkgs"
        echo "    • A module interface changed"
        echo ""
        echo "  Check the release notes:"
        echo "    https://nixos.org/manual/nixos/stable/release-notes"
        echo ""
    else
        echo "  ✓ PASS  Config evaluates cleanly against nixos-${TARGET}."
        echo "          No option errors, renames, or removals detected."
        echo ""
    fi

    # ── [2/3] Package Cache Analysis ────────────────────────────────────────
    echo "────────────────────────────────────────────────────────────────"
    echo "  [2/3] Package Cache Analysis"
    echo "────────────────────────────────────────────────────────────────"
    echo ""

    if [ "$EVAL_EXIT" -ne 0 ]; then
        echo "  ⚠ Skipped — fix evaluation errors first (see [1/3] above)."
        echo ""
    else
        ALL_BUILD=$(printf '%s\n' "$DRY_OUTPUT" \
            | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
            || true)
        ALL_FETCH=$(printf '%s\n' "$DRY_OUTPUT" \
            | awk '/will be fetched:/{p=1;next} /will be built:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
            || true)

        FETCH_COUNT=$(printf '%s\n' "$ALL_FETCH" | grep -c '[^[:space:]]' || true)
        HEAVY_BUILDS=$(printf '%s\n' "$ALL_BUILD" | grep -E  "$HEAVY_BUILD_REGEX" || true)
        HEAVY_COUNT=$(printf '%s\n' "$HEAVY_BUILDS" | grep -c '[^[:space:]]' || true)
        NON_HEAVY_BUILDS=$(printf '%s\n' "$ALL_BUILD" | grep -Ev "$HEAVY_BUILD_REGEX" || true)
        NON_HEAVY_COUNT=$(printf '%s\n' "$NON_HEAVY_BUILDS" | grep -c '[^[:space:]]' || true)

        printf "  %-48s %s\n" "Packages in binary cache (ready to fetch):"         "${FETCH_COUNT}"
        printf "  %-48s %s\n" "Non-heavy local builds (fast — system glue, scripts):" "${NON_HEAVY_COUNT}"
        printf "  %-48s %s\n" "Heavy kernel/NVIDIA builds (hours — will block update):" "${HEAVY_COUNT}"
        echo ""

        if [ -n "$NON_HEAVY_BUILDS" ] && [ "$NON_HEAVY_COUNT" -gt 0 ]; then
            echo "  ── Non-heavy local builds (fast — update will proceed) ─────────"
            printf '%s\n' "$NON_HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/    /'
            echo ""
        fi

        if [ -n "$HEAVY_BUILDS" ] && [ "$HEAVY_COUNT" -gt 0 ]; then
            echo "  ── Heavy builds — kernel/NVIDIA not yet in cache (will block) ──"
            printf '%s\n' "$HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/    /'
            echo ""
            echo "  These packages compile against the kernel and are not yet in the"
            echo "  nixos-${TARGET} binary cache. If you upgrade now, vexos-update"
            echo "  will block and restore flake.lock. The cache typically fills"
            echo "  within 1-3 days of a nixpkgs commit."
            echo ""
        else
            echo "  ✓ No heavy builds detected — update will proceed without blocking."
            echo ""
        fi
    fi

    # ── [3/3] Recommendation ────────────────────────────────────────────────
    echo "────────────────────────────────────────────────────────────────"
    echo "  [3/3] Recommendation"
    echo "────────────────────────────────────────────────────────────────"
    echo ""

    if [ "$EVAL_EXIT" -ne 0 ]; then
        echo "  ✗ NOT READY — config errors must be resolved first."
        echo ""
        echo "  Steps:"
        echo "  1. Review the evaluation errors in [1/3] above."
        echo "  2. Fix the affected modules/options in vexos-nix."
        echo "  3. Push the fix, then re-run:"
        echo "       just upgrade-analysis ${TARGET}"
        echo "  4. Once [1/3] shows PASS, update flake.nix in the repo and push — the upgrade applies on next 'just update'."
        echo ""
    elif [ "$HEAVY_COUNT" -gt 0 ] 2>/dev/null; then
        echo "  ⚠ CONFIG OK — but ${HEAVY_COUNT} heavy kernel/NVIDIA package(s) not yet in cache."
        echo ""
        echo "  Option A — Wait (recommended):"
        echo "    Re-run 'just upgrade-analysis ${TARGET}' in 1-3 days."
        echo "    When [2/3] shows 0 heavy builds, push the flake.nix upgrade and run:"
        echo "      just update"
        echo ""
        echo "  Option B — Upgrade now and compile locally:"
        echo "    Push the flake.nix upgrade, then accept the hours-long source build:"
        echo "      just update-all"
        echo ""
    else
        echo "  ✓ READY — config is clean and all packages are in cache."
        echo ""
        echo "  Push the flake.nix upgrade to the repo, then run:"
        echo "    just update"
        echo ""
    fi

    echo "  Release notes:  https://nixos.org/manual/nixos/stable/release-notes"
    echo "  Package search: https://search.nixos.org/packages?channel=${TARGET}"
    echo ""
    echo "================================================================"
    echo ""


# Roll back to the previous NixOS generation and set it as the boot default.
[group('System Upgrades & Rollbacks')]
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
[group('System Upgrades & Rollbacks')]
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

# ── System Administration ────────────────────────────────────────────────────

# Reboot the system immediately.
[group('System Administration')]
reboot:
    sudo systemctl reboot

# Shut down the system immediately.
[group('System Administration')]
shutdown:
    sudo systemctl poweroff

# Reset all GNOME settings to the flake defaults by clearing the user dconf
# database.  After this, every key falls back to the system dconf database
# written by modules/gnome.nix and the active gnome-<role>.nix module.
# The app-folder stamp file is also removed so the first-run service
# re-applies the folder layout on the next graphical login.
# Run in a terminal (NOT inside a GNOME session) or log out first for best
# results, since GNOME may re-write some keys while running.
[group('System Administration')]
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
    rm -f "$HOME/.local/share/vexos/.dconf-app-folders-initialized-v2"
    echo "Done. Log out and back in (or reboot) for all changes to take effect."
    echo "App folders will be restored on the next graphical login."

# Set up the Remote Desktop (RDP) password for this machine.
# Writes the password to /etc/nixos/secrets/rdp-password (root:root 0600).
# Not stored in the Nix store. After running this recipe, rebuild with
# 'just rebuild' to activate — RDP credentials will then be configured
# automatically on every GNOME session start.
# Only needed on desktop, server, and htpc roles.
[group('System Administration')]
setup-rdp:
    #!/usr/bin/env bash
    set -euo pipefail

    SECRET_DIR="/etc/nixos/secrets"
    SECRET_FILE="$SECRET_DIR/rdp-password"

    echo ""
    echo "VexOS Remote Desktop — Password Setup"
    echo "──────────────────────────────────────"
    echo "Password will be written to: $SECRET_FILE"
    echo "Permissions: root:root 0600 — not stored in the Nix store."
    echo ""

    while true; do
        IFS= read -rsp "RDP password: " password
        echo ""
        IFS= read -rsp "Confirm password: " password2
        echo ""
        if [ "$password" = "$password2" ]; then
            break
        fi
        echo "Passwords do not match — try again."
        echo ""
    done

    sudo mkdir -p "$SECRET_DIR"
    sudo chmod 700 "$SECRET_DIR"
    printf '%s' "$password" | sudo tee "$SECRET_FILE" > /dev/null
    sudo chmod 600 "$SECRET_FILE"
    sudo chown root:root "$SECRET_FILE"

    echo "✓ Password written to $SECRET_FILE"
    echo ""
    echo "Run 'just rebuild' to apply. After rebuild, RDP credentials are"
    echo "configured automatically on every login — no further action needed."
    echo ""

# Set the system hostname — applies immediately and persists across rebuilds.
# Usage:
#   just set-hostname mypc       — direct
#   just set-hostname            — interactive prompt
[group('System Administration')]
set-hostname name="":
    #!/usr/bin/env bash
    set -euo pipefail

    NAME="{{name}}"

    if [ -z "$NAME" ]; then
        printf "New hostname: "
        read -r NAME
    fi

    if [ -z "$NAME" ]; then
        echo "error: hostname cannot be empty." >&2
        exit 1
    fi

    # RFC 1123: labels are alphanumeric + hyphens, no leading/trailing hyphens, max 63 chars per label.
    if ! echo "$NAME" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'; then
        echo "error: '$NAME' is not a valid hostname." >&2
        echo "       Labels must be alphanumeric and may contain hyphens, but not at the start or end." >&2
        echo "       Examples: mypc, vexos-desktop, home-server" >&2
        exit 1
    fi

    CURRENT=$(hostname 2>/dev/null || echo "unknown")

    if [ "$NAME" = "$CURRENT" ]; then
        echo "Hostname is already '${NAME}'. Nothing to do."
        exit 0
    fi

    echo ""
    echo "Changing hostname: ${CURRENT} → ${NAME}"
    echo ""

    # Apply to the running kernel immediately.
    # --transient avoids writing /etc/hostname, which is read-only on NixOS
    # (it's a symlink into the Nix store). The static hostname is corrected
    # on the next rebuild via the flake.nix edit below.
    sudo hostnamectl set-hostname --transient "$NAME"
    echo "✓ Applied to running system (transient — persists after rebuild)"

    # Persist through NixOS rebuilds by updating /etc/nixos/flake.nix.
    # networking.hostName = lib.mkDefault "vexos" (in modules/network.nix) is
    # overridden by any plain assignment in hardwareModule or hostModule.
    FLAKE="/etc/nixos/flake.nix"
    PERSISTED=false

    if [ -f "$FLAKE" ]; then
        if grep -qP 'networking\.hostName\s*=' "$FLAKE"; then
            # Update existing networking.hostName value in-place.
            sudo sed -i -E "s|networking\.hostName\s*=\s*\"[^\"]*\"|networking.hostName = \"${NAME}\"|g" "$FLAKE"
            echo "✓ Updated networking.hostName in ${FLAKE}"
            PERSISTED=true
        elif grep -qF 'hardwareModule = { ... }: { };' "$FLAKE" 2>/dev/null; then
            # Empty hardwareModule — inject the hostname assignment.
            sudo sed -i "s|hardwareModule = { \.\.\. }: { };|hardwareModule = { ... }: { networking.hostName = \"${NAME}\"; };|" "$FLAKE"
            echo "✓ Set networking.hostName in hardwareModule in ${FLAKE}"
            PERSISTED=true
        fi
    fi

    if [ "$PERSISTED" = "false" ]; then
        echo ""
        echo "  Could not auto-update ${FLAKE}."
        echo "  To persist the hostname across rebuilds, add this line to your"
        echo "  hardwareModule (or hostModule for server roles) in ${FLAKE}:"
        echo ""
        echo "    networking.hostName = \"${NAME}\";"
        echo ""
    else
        echo "  Hostname will persist across rebuilds."
    fi

    echo ""
    printf "Rebuild now to apply fully via NixOS? [y/N]: "
    read -r REBUILD_ANSWER || true
    case "${REBUILD_ANSWER,,}" in
        y|yes) just rebuild ;;
        *) echo "Skipped — run 'just rebuild' when ready." ;;
    esac

# Copy your SSH key to a remote machine so future connections need no password.
# Usage:
#   just ssh                     — interactive prompts
#   just ssh nimda@10.35.1.50   — direct
[group('System Administration')]
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

# ── VPN ───────────────────────────────────────────────────────────────────────

# First-time Tailscale setup — grants operator rights to the current user, then connects.
# Run once after enabling services.tailscale.enable = true in your NixOS config and rebuilding.
# On first run, Tailscale will print a URL to authenticate — open it in a browser.
[group('VPN')]
setup-tailscale:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v tailscale >/dev/null 2>&1; then
        echo "error: tailscale not found." >&2
        echo "       Add 'services.tailscale.enable = true;' to your NixOS config and rebuild." >&2
        exit 1
    fi

    if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
        echo "error: tailscaled is not running." >&2
        echo "       Add 'services.tailscale.enable = true;' to your NixOS config and rebuild." >&2
        exit 1
    fi

    echo "Setting operator to ${USER} (allows tailscale CLI without sudo)..."
    sudo tailscale set --operator="$USER"
    echo "✓ Operator set."
    echo ""
    echo "Connecting to Tailscale..."
    tailscale up

# Enable the VPN kill switch — blocks all clearnet egress when no VPN tunnel is active.
# Desktop and HTPC roles only. On the stateless role the kill switch is always active.
[group('VPN')]
enable-kill-switch:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *stateless* ]]; then
        echo "Kill switch is always active on the stateless role — no toggle needed."
        exit 0
    fi
    systemctl start vpn-kill-switch.service
    echo "✓ VPN kill switch enabled — all clearnet egress blocked outside the VPN tunnel."
    echo "  Disable with: just disable-kill-switch"

# Disable the VPN kill switch — restores normal clearnet egress.
# Desktop and HTPC roles only. On the stateless role the kill switch cannot be disabled.
[group('VPN')]
disable-kill-switch:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *stateless* ]]; then
        echo "error: the kill switch cannot be disabled on the stateless role — always active by design." >&2
        exit 1
    fi
    systemctl stop vpn-kill-switch.service
    echo "✓ VPN kill switch disabled — clearnet egress restored."
    echo "  Re-enable with: just enable-kill-switch"

# ── Desktop Feature Toggles ──────────────────────────────────────────────────
# Run `just features` to see available features and their status.

# Patch /etc/nixos/flake.nix to load features.nix on every rebuild.
# Required once on systems where the thin wrapper predates feature toggle support.
# Safe to re-run — exits immediately if the wrapper is already up to date.
[group('Optional Feature Toggles')]
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
    printf "Rebuild now to apply? [y/N]: "
    read -r ANSWER || true
    case "${ANSWER,,}" in
        y|yes) just rebuild ;;
        *) echo "Run 'just rebuild' when ready." ;;
    esac


# Available optional feature names (desktop role).
_feature_names := "gaming development print3d virtualization"

# Guard: abort if the current host is stateless, headless-server, or vanilla (features not supported there).
[private]
_require-desktop-role:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *stateless* || "$variant" == *headless* || "$variant" == *vanilla* ]]; then
        echo "error: feature recipes are not available on stateless, headless-server, or vanilla roles."
        echo "       current variant: ${variant:-unknown}"
        exit 1
    fi

# List all optional features and their enabled/disabled status.
[group('Optional Feature Toggles')]
features: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEAT_FILE="/etc/nixos/features.nix"
    _check() {
        local feat="$1"
        if grep -qP "vexos\.features\.${feat//./\\.}\.enable\s*=\s*true" "$FEAT_FILE" 2>/dev/null; then
            printf "    \033[32m✓\033[0m %s\n" "$feat"
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
    echo ""
    echo "Use 'just enable-feature <feature>' / 'just disable-feature <feature>' to toggle."
    echo ""

# Enable an optional feature module.  Usage: just enable-feature gaming
[group('Optional Feature Toggles')]
enable-feature feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEAT_FILE="/etc/nixos/features.nix"
    FEATURE="{{feature}}"

    VALID_FEATURES="{{_feature_names}}"
    if ! echo "$VALID_FEATURES" | tr ' ' '\n' | grep -qx "$FEATURE"; then
        echo "error: unknown feature '$FEATURE'"
        echo "available: $VALID_FEATURES"
        exit 1
    fi

    if [ ! -f "$FEAT_FILE" ]; then
        echo "Creating $FEAT_FILE from template..."
        _jf_dir="{{justfile_directory()}}"
        TEMPLATE_SRC=""
        for _candidate in "$_jf_dir" "/etc/nixos" "$HOME/Projects/vexos-nix"; do
            if [ -f "$_candidate/template/features.nix" ]; then
                TEMPLATE_SRC="$_candidate/template/features.nix"
                break
            fi
        done
        if [ -z "$TEMPLATE_SRC" ]; then
            echo "error: cannot find template/features.nix in any known location" >&2
            echo "searched: $_jf_dir /etc/nixos $HOME/Projects/vexos-nix" >&2
            exit 1
        fi
        sudo cp "$TEMPLATE_SRC" "$FEAT_FILE"
        sudo sed -i 's/\r//' "$FEAT_FILE"
    fi

    OPTION="vexos.features.${FEATURE}.enable"

    if grep -q "${OPTION}\s*=\s*true" "$FEAT_FILE" 2>/dev/null; then
        echo "$FEATURE is already enabled."
        exit 0
    fi

    if grep -qP "^\s*#?\s*${OPTION//./\\.}" "$FEAT_FILE" 2>/dev/null; then
        sudo sed -i -E "s/^(\s*)#?\s*(${OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${OPTION} = true;/" "$FEAT_FILE"
    else
        sudo sed -i "s|}|  ${OPTION} = true;\n}|" "$FEAT_FILE"
    fi

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

# Disable an optional feature module.  Usage: just disable-feature gaming
[group('Optional Feature Toggles')]
disable-feature feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEAT_FILE="/etc/nixos/features.nix"
    FEATURE="{{feature}}"

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

# ── Server Services Management ───────────────────────────────────────────────
# Run `just services` to see available modules and their status.

# Available server service module names.
_server_service_names := "adguard arr attic audiobookshelf authelia caddy cockpit code-server docker dockhand dozzle forgejo grafana headscale home-assistant homepage immich jellyfin kavita kiji-proxy komga listmonk loki matrix-conduit mealie minio nas navidrome netdata nextcloud nginx nginx-proxy-manager node-red ntfy paperless papermc photoprism plex podman portainer portbook prometheus proxmox rustdesk scrutiny seerr stirling-pdf syncthing tautulli traefik unbound uptime-kuma vaultwarden vexboard zigbee2mqtt"

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
        _vexos_store=$(nix eval --raw --expr '(builtins.getFlake "git+file:///etc/nixos").inputs.vexos-nix.outPath' 2>/dev/null || true)
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
    _svc() { printf "    \033[36m%-22s\033[0m  %s\n" "$1" "$2"; }
    echo ""
    echo "Available server service modules:"
    _hdr "Books & Reading"
    _svc kavita              "Self-hosted manga, comics & book library"
    _svc komga               "Comic book & manga media server"
    _hdr "Communications"
    _svc matrix-conduit      "Lightweight Matrix homeserver (chat protocol)"
    _hdr "Files & Storage"
    _svc immich              "Self-hosted photo & video backup"
    _svc minio               "S3-compatible object storage server"
    _svc nextcloud           "File sync, sharing & collaboration suite"
    _svc photoprism          "AI-powered photo management & sharing"
    _svc syncthing           "Continuous peer-to-peer file synchronisation"
    _hdr "Gaming"
    _svc papermc             "High-performance Minecraft Java server"
    _hdr "Infrastructure"
    _svc attic               "Self-hosted Nix binary cache server"
    _svc caddy               "Automatic HTTPS web server & reverse proxy"
    _svc docker              "Container runtime (Docker Engine)"
    _svc dockhand            "Web UI for managing Podman containers"
    _svc nginx               "High-performance HTTP server & reverse proxy"
    _svc nginx-proxy-manager "Web UI for Nginx reverse proxy & SSL certs"
    _svc podman              "Rootless OCI container runtime"
    _svc portainer           "Web UI for managing Docker/Podman stacks"
    _svc traefik             "Cloud-native edge router & reverse proxy"
    _hdr "Media"
    _svc audiobookshelf      "Self-hosted audiobook & podcast server"
    _svc jellyfin            "Open-source media streaming server"
    _svc navidrome           "Music streaming server (Subsonic-compatible)"
    _svc plex                "Personal media library & streaming server"
    _svc tautulli            "Monitoring & analytics for Plex Media Server"
    _hdr "Media Requests & Automation"
    _svc arr                 "*arr suite — Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd"
    _svc seerr               "Media request manager (Jellyfin, Plex, Emby)"
    _hdr "Monitoring & Admin"
    _svc cockpit             "Web-based Linux server management console"
    _svc dozzle              "Real-time container log viewer"
    _svc grafana             "Metrics visualisation & dashboards"
    _svc loki                "Log aggregation system (pairs with Grafana)"
    _svc nas                 "Cockpit + NAS plugins (Samba, NFS, ZFS)"
    _svc netdata             "Real-time performance & health monitoring"
    _svc portbook            "Quick-access bookmark panel for services"
    _svc prometheus          "Metrics collection & alerting toolkit"
    _svc scrutiny            "S.M.A.R.T. disk health monitoring dashboard"
    _svc uptime-kuma         "Self-hosted uptime & status page monitoring"
    _svc vexboard            "VexOS Server dashboard (auto-enabled with first service)"
    _hdr "Networking & Security"
    _svc adguard             "DNS-based ad & tracker blocker"
    _svc authelia            "Single sign-on & two-factor auth gateway"
    _svc headscale           "Self-hosted Tailscale-compatible VPN (WireGuard)"
    _svc unbound             "Validating, recursive, caching DNS resolver"
    _svc vaultwarden         "Lightweight Bitwarden-compatible password manager"
    _hdr "Productivity"
    _svc code-server         "VS Code running in the browser"
    _svc forgejo             "Self-hosted Git & code collaboration (Gitea fork)"
    _svc homepage            "Customisable server dashboard & start page"
    _svc listmonk            "Self-hosted newsletter & mailing list manager"
    _svc mealie              "Self-hosted recipe manager & meal planner"
    _svc paperless           "Document scanning, OCR, tagging & archival"
    _svc stirling-pdf        "Web-based PDF editing & conversion tools"
    _hdr "Remote Access"
    _svc rustdesk            "Open-source self-hosted remote desktop server"
    _hdr "Smart Home & Notifications"
    _svc home-assistant      "Open-source home automation platform"
    _svc node-red            "Low-code flow-based automation editor"
    _svc ntfy                "Simple HTTP-based push notification server"
    _svc zigbee2mqtt         "Zigbee → MQTT bridge (no proprietary hub needed)"
    _hdr "AI & Privacy"
    _svc kiji-proxy          "Privacy-first OpenAI-compatible AI API proxy"
    _hdr "Experimental"
    _svc proxmox             "Proxmox VE integration (experimental)"
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
        attic)           printf "  %-18s  HTTP    http://<server-ip>:8400   (Nix binary cache)\n"                      "$1" ;;
        audiobookshelf)  printf "  %-18s  Web UI  http://<server-ip>:8234\n"                                           "$1" ;;
        caddy)           printf "  %-18s  Ports :8880, :8443\n"                                                           "$1" ;;
        nas)             printf "  %-18s  Web UI  http://<server-ip>:9090   (Cockpit + NAS plugins)\n"               "$1" ;;
        cockpit)         printf "  %-18s  Web UI  http://<server-ip>:9090\n"                                           "$1" ;;
        docker)          printf "  %-18s  No web UI — docker / docker compose CLI\n"                                   "$1" ;;
        dockhand)        printf "  %-18s  Web UI  http://<server-ip>:8073   (Podman container manager)\n"             "$1" ;;
        forgejo)         printf "  %-18s  Web UI  http://<server-ip>:3000\n"                                           "$1" ;;
        grafana)         printf "  %-18s  Web UI  http://<server-ip>:3030\n"                                           "$1" ;;
        headscale)       printf "  %-18s  Web UI  http://<server-ip>:8085\n"                                           "$1" ;;
        home-assistant)  printf "  %-18s  Web UI  http://<server-ip>:8123\n"                                           "$1" ;;
        homepage)        printf "  %-18s  Web UI  http://<server-ip>:3010   (requires docker)\n"                       "$1" ;;
        immich)          printf "  %-18s  Web UI  http://<server-ip>:2283\n"                                           "$1" ;;
        jellyfin)        printf "  %-18s  Web UI  http://<server-ip>:8096\n"                                           "$1" ;;
        kavita)          printf "  %-18s  Web UI  http://<server-ip>:5000\n"                                           "$1" ;;
        kiji-proxy)      printf "  %-18s  Proxy   http://127.0.0.1:8080   |  Health: http://localhost:8080/health\n"    "$1" ;;
        komga)           printf "  %-18s  Web UI  http://<server-ip>:8090\n"                                           "$1" ;;
        mealie)          printf "  %-18s  Web UI  http://<server-ip>:9010\n"                                           "$1" ;;
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
        rustdesk)        printf "  %-18s  Ports :21115-21117 / :21118-21119 (no web UI)\n"                             "$1" ;;
        scrutiny)        printf "  %-18s  Web UI  http://<server-ip>:8078\n"                                           "$1" ;;
        stirling-pdf)    printf "  %-18s  Web UI  http://<server-ip>:8077\n"                                           "$1" ;;
        syncthing)       printf "  %-18s  Web UI  http://<server-ip>:8384\n"                                           "$1" ;;
        tautulli)        printf "  %-18s  Web UI  http://<server-ip>:8181\n"                                           "$1" ;;
        traefik)         printf "  %-18s  Ports :8882, :8445  |  Dashboard http://<server-ip>:8079/dashboard/\n"       "$1" ;;
        uptime-kuma)     printf "  %-18s  Web UI  http://<server-ip>:3001\n"                                           "$1" ;;
        vaultwarden)     printf "  %-18s  Web UI  http://<server-ip>:8222   |  Admin .../admin\n"                      "$1" ;;
        vexboard)        printf "  %-18s  Web UI  http://<server-ip>:7280   (server dashboard — auto-enabled with first service)\n" "$1" ;;
        authelia)        printf "  %-18s  Web UI  http://<server-ip>:9091\n"                                                   "$1" ;;
        code-server)     printf "  %-18s  Web UI  http://<server-ip>:4444\n"                                                   "$1" ;;
        dozzle)          printf "  %-18s  Web UI  http://<server-ip>:8888   (requires docker)\n"                               "$1" ;;
        listmonk)        printf "  %-18s  Web UI  http://<server-ip>:9025\n"                                                   "$1" ;;
        loki)            printf "  %-18s  API     http://<server-ip>:3100   (no web UI — pair with Grafana)\n"                 "$1" ;;
        matrix-conduit)  printf "  %-18s  API     http://<server-ip>:6167   |  Federation :8448\n"                             "$1" ;;
        minio)           printf "  %-18s  API :9000  Console http://<server-ip>:9001\n"                                   "$1" ;;
        navidrome)       printf "  %-18s  Web UI  http://<server-ip>:4533\n"                                                   "$1" ;;
        netdata)         printf "  %-18s  Web UI  http://<server-ip>:19999\n"                                                  "$1" ;;
        nginx-proxy-manager) printf "  %-18s  Admin http://<server-ip>:81   |  Ports :8881, :8444\n"                         "$1" ;;
        node-red)        printf "  %-18s  Web UI  http://<server-ip>:1880\n"                                                   "$1" ;;
        paperless)       printf "  %-18s  Web UI  http://<server-ip>:28981\n"                                                  "$1" ;;
        photoprism)      printf "  %-18s  Web UI  http://<server-ip>:2342\n"                                                   "$1" ;;
        portainer)       printf "  %-18s  Web UI  https://<server-ip>:9443  (requires docker)\n"                               "$1" ;;
        portbook)        printf "  %-18s  Web UI  http://<server-ip>:7777   |  CLI: portbook ls / tui / watch\n"       "$1" ;;
        prometheus)      printf "  %-18s  Web UI  http://<server-ip>:9092\n"                                               "$1" ;;
        proxmox)         printf "  %-18s  Web UI  https://<server-ip>:8006  |  Ports :3128 (SPICE), :5900-5999 (VNC)\n"        "$1" ;;
        unbound)         printf "  %-18s  DNS on :5353\n"                                                                  "$1" ;;
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
      attic)          UNITS="atticd";               URLS="http://localhost:8400" ;;
      audiobookshelf) UNITS="audiobookshelf";       URLS="http://localhost:8234" ;;
      caddy)          UNITS="caddy";                URLS="http://localhost:8880" ;;
      nas)            UNITS="cockpit";              URLS="http://localhost:9090" ;;
      cockpit)        UNITS="cockpit";              URLS="http://localhost:9090" ;;
      docker)         UNITS="docker";               URLS="" ;;
      dockhand)       UNITS="podman-dockhand";       URLS="http://localhost:8073" ;;
      forgejo)        UNITS="forgejo";              URLS="http://localhost:3000" ;;
      grafana)        UNITS="grafana";              URLS="http://localhost:3030" ;;
      headscale)      UNITS="headscale";            URLS="http://localhost:8085" ;;
      home-assistant) UNITS="home-assistant";       URLS="http://localhost:8123" ;;
      homepage)       UNITS="docker-homepage";      URLS="http://localhost:3010" ;;
      immich)         UNITS="immich-server";        URLS="http://localhost:2283" ;;
      jellyfin)       UNITS="jellyfin";             URLS="http://localhost:8096" ;;
      kavita)         UNITS="kavita";               URLS="http://localhost:5000" ;;
      komga)          UNITS="komga";                URLS="http://localhost:8090" ;;
      kiji-proxy)     UNITS="kiji-proxy";           URLS="http://localhost:8080/health" ;;
      mealie)         UNITS="mealie";               URLS="http://localhost:9010" ;;
      nextcloud)      UNITS="phpfpm-nextcloud nginx"; URLS="http://localhost:80" ;;
      nginx)          UNITS="nginx";                URLS="http://localhost:80" ;;
      ntfy)           UNITS="ntfy";                 URLS="http://localhost:2586" ;;
      seerr)          UNITS="seerr";               URLS="http://localhost:5055" ;;
      papermc)        UNITS="minecraft-server";     URLS="" ;;
      plex)           UNITS="plex";                 URLS="http://localhost:32400/web" ;;
      podman)         UNITS="podman";               URLS="" ;;
      rustdesk)       UNITS="rustdesk-server hbbr hbbs"; URLS="" ;;
      scrutiny)       UNITS="scrutiny";             URLS="http://localhost:8078" ;;
      stirling-pdf)   UNITS="docker-stirling-pdf";   URLS="http://localhost:8077" ;;
      syncthing)      UNITS="syncthing";            URLS="http://localhost:8384" ;;
      tautulli)       UNITS="tautulli";             URLS="http://localhost:8181" ;;
      traefik)        UNITS="traefik";              URLS="http://localhost:8079/dashboard/" ;;
      uptime-kuma)    UNITS="docker-uptime-kuma";   URLS="http://localhost:3001" ;;
      vaultwarden)    UNITS="vaultwarden";          URLS="http://localhost:8222" ;;
      vexboard)       UNITS="vexboard";             URLS="http://localhost:7280" ;;
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
      portbook)       UNITS="portbook";             URLS="http://localhost:7777" ;;
      prometheus)     UNITS="prometheus";               URLS="http://localhost:9092" ;;
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
    _hdr "Infrastructure";             _check attic;          _check caddy;          _check docker;        _check dockhand;      _check podman;        _check nginx;         _check nginx-proxy-manager;  _check portainer;  _check traefik
    _hdr "Media";                      _check audiobookshelf; _check jellyfin;      _check navidrome;     _check plex;          _check tautulli
    _hdr "Media Requests & Automation";_check arr;            _check seerr
    _hdr "Monitoring & Admin";         _check nas;            _check cockpit;        _check dozzle;        _check grafana;       _check loki;          _check netdata;   _check prometheus;  _check scrutiny;  _check uptime-kuma;  _check portbook;  _check vexboard
    _hdr "Networking & Security";      _check adguard;        _check authelia;      _check headscale;     _check unbound;       _check vaultwarden
    _hdr "Productivity";               _check code-server;    _check forgejo;       _check homepage;      _check listmonk;      _check mealie;    _check paperless;   _check stirling-pdf
    _hdr "Remote Access";              _check rustdesk
    _hdr "Smart Home & Notifications"; _check home-assistant; _check node-red;      _check ntfy;          _check zigbee2mqtt
    _hdr "AI & Privacy";               _check kiji-proxy
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
        sudo sed -i -E "s/^(\s*)#?\s*(${OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${OPTION} = true;/" "$SVC_FILE"
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
                sudo sed -i -E "s/^(\s*)#?\s*(${PP_OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${PP_OPTION} = true;/" "$SVC_FILE"
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

    # Ensure VexBoard has a secretFile — required by the build assertion.
    # Runs when VexBoard is explicitly enabled or auto-enabled alongside a service.
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
            if grep -qP "^\s*#\s*vexos\.server\.vexboard\.secretFile" "$svc_file" 2>/dev/null; then
                sudo sed -i -E 's|^(\s*)#\s*(vexos\.server\.vexboard\.secretFile\s*=\s*"[^"]*")\s*;|\1\2;|' "$svc_file"
            else
                sudo sed -i "s|}|  vexos.server.vexboard.secretFile = \"${secret_path}\";\n}|" "$svc_file"
            fi
        fi
    }

    # Explicit `just enable vexboard` — ensure secret is generated.
    if [ "$SERVICE" = "vexboard" ]; then
        _ensure_vexboard_secret "$SVC_FILE"
    fi

    # Auto-enable VexBoard alongside the first service enabled on this host.
    if [ "$SERVICE" != "vexboard" ]; then
        VB_OPTION="vexos.server.vexboard.enable"
        if ! grep -qP "^\s*vexos\.server\.vexboard\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            if grep -qP "^\s*#?\s*${VB_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s/^(\s*)#?\s*(${VB_OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${VB_OPTION} = true;/" "$SVC_FILE"
            else
                sudo sed -i "s|}|  ${VB_OPTION} = true;\n}|" "$SVC_FILE"
            fi
            echo "  + VexBoard also enabled (server dashboard — http://<server-ip>:7280)"
        fi
        # Always ensure secretFile is set — runs even if VexBoard was already enabled
        # on a pre-existing VM where a prior session left enable=true but no secretFile.
        _ensure_vexboard_secret "$SVC_FILE"
    fi

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
      attic)
        echo "  Service:  atticd.service"
        echo "  HTTP:     http://<server-ip>:8400"
        echo "  About:    Modern, purpose-built Nix binary cache server. Push derivations from any machine; pull on rebuild."
        echo "  Note:     Create /etc/nixos/secrets/attic-credentials before first start:"
        echo "              ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>"
        echo "            Generate secret:  openssl rand -base64 32"
        echo "  Client:   attic login myserver http://<server-ip>:8400 <token>"
        echo "            attic cache create mycache"
        echo "            attic push mycache <store-path>"
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
        echo "  Container: dockhand (NixOS OCI container via Podman)"
        echo "  Web UI:    http://<server-ip>:8073"
        echo "  About:     Modern container management UI — browse containers, Compose stacks, logs, and terminals from a browser."
        echo "  Requires:  Podman must be enabled first (just enable podman)."
        echo "  Note:      Port remapped from upstream default 3000 — Forgejo also uses 3000."
        ;;
      forgejo)
        echo "  Service:  forgejo.service"
        echo "  Web UI:   http://<server-ip>:3000"
        echo "  About:    Lightweight self-hosted Git forge (Gitea fork) — issues, pull requests, CI. Registration is disabled by default."
        ;;
      grafana)
        echo "  Service:  grafana.service"
        echo "  Web UI:   http://<server-ip>:3030"
        echo "  About:    Metrics and observability dashboard. Pair with Prometheus to graph system and application metrics."
        echo "  Login:    Default admin / admin — change on first login."
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
        echo "  Web UI:   http://<server-ip>:9010"
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
        echo "  Web UI:   http://<server-ip>:8078"
        echo "  About:    Hard drive health dashboard powered by S.M.A.R.T. data with alerts on failing metrics."
        ;;
      stirling-pdf)
        echo "  Container: stirling-pdf (NixOS OCI container)"
        echo "  Web UI:    http://<server-ip>:8077"
        echo "  About:     Web-based PDF toolbox — merge, split, rotate, compress, OCR, watermark, and convert. All processing is local."
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
        echo "  Note:     Enable dockhand for a browser-based management UI (just enable dockhand)."
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
        echo "  Ports:    :8881 (HTTP proxy), :8444 (HTTPS proxy)"
        echo "  About:    Web UI for managing Nginx reverse proxy rules with automatic Let's Encrypt TLS."
        echo "  Login:    Default admin@example.com / changeme — change immediately after first login."
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
      portbook)
        # ── Auto-patch the package hash if still a placeholder ──────────────────
        _PB_PKG=""
        _jf_raw="{{justfile_directory()}}"
        _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
        _jf_dir=$(dirname "$_jf_real")
        _walk="$PWD"
        while [ "$_walk" != "/" ] && [ -z "$_PB_PKG" ]; do
          [ -f "$_walk/pkgs/portbook/default.nix" ] && _PB_PKG="$_walk/pkgs/portbook/default.nix"
          _walk=$(dirname "$_walk")
        done
        for _cand in "$_jf_raw" "$_jf_dir" "$HOME/Projects/vexos-nix"; do
          [ -n "$_PB_PKG" ] && break
          [ -f "$_cand/pkgs/portbook/default.nix" ] && _PB_PKG="$_cand/pkgs/portbook/default.nix"
        done
        if [ -n "$_PB_PKG" ] && grep -q 'lib\.fakeHash' "$_PB_PKG"; then
          echo ""
          echo "  Fetching portbook package hash (~5 MB download)..."
          _PB_URL="https://github.com/a-grasso/portbook/releases/download/v0.2.1/portbook-x86_64-unknown-linux-gnu.tar.xz"
          _PB_B32=$(nix-prefetch-url --unpack "$_PB_URL" 2>/dev/null) || _PB_B32=""
          _PB_SRI=""
          [ -n "$_PB_B32" ] && _PB_SRI=$(nix hash to-sri --type sha256 "$_PB_B32" 2>/dev/null) || true
          if [ -n "$_PB_SRI" ]; then
            sed -i "s|lib\.fakeHash|\"${_PB_SRI}\"|" "$_PB_PKG"
            echo "  ✓ Package hash set: ${_PB_SRI}"
          else
            echo "  ⚠ Could not fetch hash automatically. Run manually then rebuild:"
            echo "      HASH=\$(nix-prefetch-url --unpack $_PB_URL)"
            echo "      SRI=\$(nix hash to-sri --type sha256 \"\$HASH\")"
            echo "      sed -i \"s|lib\\.fakeHash|\\\"\$SRI\\\"|\" $_PB_PKG"
          fi
        elif [ -n "$_PB_PKG" ]; then
          echo "  ✓ Package hash already set."
        else
          echo "  ⚠ Could not find pkgs/portbook/default.nix — set the hash manually before rebuilding."
        fi
        echo ""
        echo "  Service:  portbook.service"
        echo "  Web UI:   http://<server-ip>:7777"
        echo "  About:    Auto-discovers HTTP servers on localhost ports. Classifies each as"
        echo "            live/error/dead and labels with project name and page title."
        echo "  CLI:      portbook ls                — one-shot grouped terminal list"
        echo "            portbook tui               — interactive TUI with live updates"
        echo "            portbook watch --json      — streaming JSON for scripts/agents"
        echo "            portbook explain <port>    — diagnostic block for a single port"
        ;;
      vexboard)
        echo "  Service:  vexboard.service"
        echo "  Web UI:   http://<server-ip>:7280"
        echo "  About:    VexOS Server dashboard — automatically enabled alongside the first service you enable."
        echo "  Note:     To disable: set 'vexos.server.vexboard.enable = false;' in server-services.nix."
        echo "  Secret:   Set VEXBOARD_AUTH__SECRET via vexos.server.vexboard.secretFile for production use."
        echo "            Generate a secret:  openssl rand -base64 48"
        ;;
      prometheus)
        echo "  Service:  prometheus.service"
        echo "  Web UI:   http://<server-ip>:9092"
        echo "  About:    Time-series metrics collection and alerting. Pair with Grafana for dashboards."
        echo "  Note:     Add scrape targets in the module. Node Exporter is not auto-enabled — add it separately."
        ;;
      unbound)
        echo "  Service:  unbound.service"
        echo "  DNS:      Port 5353 (UDP/TCP)"
        echo "  About:    Validating, recursive DNS resolver with DNS-over-TLS forwarding to Cloudflare (1.1.1.1)."
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
    if [ "$SERVICE" != "vexboard" ]; then
        echo "  VexBoard: http://<server-ip>:7280  — configure your server dashboard tiles"
    fi
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
        sudo sed -i -E "s/^(\s*)#?\s*(${PP_OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${PP_OPTION} = true;/" "$SVC_FILE"
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
