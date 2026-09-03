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
        echo "    restart <service>          Restart a service's systemd unit(s), clearing any start-limit-hit"
        echo "    enable <service>           Enable a server service module"
        echo "    disable <service>          Disable a server service module"
        echo "    enable-plex-pass           Enable Plex Pass hardware transcoding"
        echo "    disable-plex-pass          Disable Plex Pass hardware transcoding"
        echo "    create-zfs-pool            Create a ZFS pool for Proxmox VM storage (interactive)"
        echo "    create-mergerfs-pool       Create a mergerfs+SnapRAID bulk pool from mixed drives (interactive)"
        echo "    attach-remote-storage      Attach a remote NFS/SMB storage pool from another host (interactive)"
        echo "    detach-remote-storage      Remove a remote NFS/SMB storage pool attached earlier (interactive)"
    elif [[ "$variant" == *stateless* ]]; then
        echo ""
        echo "Active role: stateless (ephemeral / tmpfs root)"
        echo ""
        echo "Reminder:"
        echo "    The primary user account starts LOCKED (no password) until you"
        echo "    set one. Run 'sudo bash scripts/stateless-setup.sh', or manually"
        echo "    create /etc/nixos/stateless-user-override.nix with a hash from"
        echo "    'mkpasswd -m sha-512'. Once set, the password persists across"
        echo "    reboots — it lives in that file, not on the wiped tmpfs root."
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
#   just switch                        — interactive prompt
#   just switch desktop amd            — direct switch
#   just switch desktop amd . cosmic   — explicit flake override + desktop environment
#   just switch desktop amd "" hyprland — desktop environment, default flake
#   just switch desktop vm "" "" virtualbox — VM hypervisor (qemu / virtualbox)
[group('System Build & Deploy')]
switch role="" variant="" flake="" de="" vmp="":
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
    DESKTOP_ENV="{{de}}"
    VM_PLATFORM="{{vmp}}"

    # _features_set <nix.option.path> <string-value>
    # Ensures /etc/nixos/features.nix exists (seeded from template/features.nix),
    # then replaces the option if already present (commented or not) or appends
    # it before the closing brace. Mirrors the replace-or-append sed pattern
    # `just enable-feature` uses, so the file stays editable by both paths.
    # Shared by the desktop-environment and VM-platform blocks below.
    _features_set() {
        local _key="$1" _val="$2" _key_re
        local FEAT_FILE="/etc/nixos/features.nix"
        _key_re="$(printf '%s' "$_key" | sed 's/\./\\./g')"

        if [ ! -f "$FEAT_FILE" ]; then
            local _jf_dir="{{justfile_directory()}}"
            local TEMPLATE_SRC=""
            for _candidate in "$_jf_dir" "/etc/nixos" "$HOME/Projects/vexos-nix"; do
                if [ -f "$_candidate/template/features.nix" ]; then
                    TEMPLATE_SRC="$_candidate/template/features.nix"
                    break
                fi
            done
            if [ -n "$TEMPLATE_SRC" ]; then
                sudo cp "$TEMPLATE_SRC" "$FEAT_FILE"
                sudo sed -i 's/\r//' "$FEAT_FILE"
            fi
        fi

        if [ -f "$FEAT_FILE" ]; then
            if grep -qP "^\s*#?\s*${_key_re}\s*=" "$FEAT_FILE" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#?\s*${_key_re}\s*=\s*\"[a-z-]+\"\s*;|\1${_key} = \"${_val}\";|" "$FEAT_FILE"
            else
                sudo sed -i "\$ s|^}|  ${_key} = \"${_val}\";\n}|" "$FEAT_FILE"
            fi
            echo "✓ ${_key} set to ${_val} in $FEAT_FILE"
        fi
    }

    if [ -z "$ROLE" ]; then
        echo ""
        echo "Select role:"
        echo "  1) desktop"
        echo "  2) stateless"
        echo "  3) htpc"
        echo "  4) server  (GUI or Headless)"
        echo "  5) vanilla"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-5] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop)   ROLE="desktop"   ;;
                2|stateless) ROLE="stateless" ;;
                3|htpc)      ROLE="htpc"      ;;
                4|server)    ROLE="server"    ;;
                5|vanilla)   ROLE="vanilla"   ;;
                *) echo "Invalid — enter 1-5 or desktop/stateless/htpc/server/vanilla" ;;
            esac
        done

        if [ "$ROLE" = "server" ]; then
            echo ""
            echo "Select server type:"
            echo "  1) Headless Server — CLI only, no desktop environment"
            echo "  2) GUI Server      — GNOME desktop environment"
            echo ""
            SERVER_TYPE=""
            while [ -z "$SERVER_TYPE" ]; do
                printf "Choice [1-2] or name (headless / gui): "
                read -r INPUT
                case "${INPUT,,}" in
                    1|headless) SERVER_TYPE="headless" ;;
                    2|gui)      SERVER_TYPE="gui"       ;;
                    *) echo "Invalid — enter 1-2 or headless/gui" ;;
                esac
            done
            if [ "$SERVER_TYPE" = "headless" ]; then
                ROLE="headless-server"
            fi
        fi
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
            echo "  2) Legacy 580 — Maxwell/Pascal/Volta (580.x, required)"
            echo ""
            while true; do
                printf "Choice [1-2]: "
                read -r INPUT
                case "${INPUT}" in
                    1) break ;;
                    2) VARIANT="nvidia-legacy580"; break ;;
                    *) echo "Invalid — enter 1 or 2" ;;
                esac
            done
        fi
    fi

    # VM hypervisor selection (vm variant only).
    # QEMU/KVM and VirtualBox need different guest packages, and VirtualBox pins
    # the kernel to 6.18 LTS to keep its guest additions building — so a
    # Proxmox/QEMU guest keeps its role's own kernel instead of inheriting that
    # pin. Without this block, `just switch <role> vm` would silently leave an
    # existing VirtualBox host on the "qemu" default and drop its guest
    # additions on the next rebuild.
    VM_PLATFORM_CHANGED="false"
    if [ "$VARIANT" = "vm" ]; then
        # Capture the currently active platform before rewriting features.nix.
        # Only an uncommented line counts — a commented line has no effect on
        # the running system, so the true active value is the NixOS default.
        OLD_VM_PLATFORM="qemu"
        if [ -f /etc/nixos/features.nix ]; then
            _oldvm="$(grep -oP '^\s*vexos\.vm\.platform\s*=\s*"\K[a-z]+' /etc/nixos/features.nix 2>/dev/null || true)"
            [ -n "$_oldvm" ] && OLD_VM_PLATFORM="$_oldvm"
        fi

        if [ -z "$VM_PLATFORM" ]; then
            echo ""
            echo "Select hypervisor:"
            echo "  1) qemu       — QEMU/KVM, Proxmox, libvirt (guest agent + SPICE)"
            echo "  2) virtualbox — VirtualBox Guest Additions (pins kernel 6.18 LTS)"
            echo ""
            while [ -z "$VM_PLATFORM" ]; do
                printf "Choice [1-2] or name (default: qemu): "
                read -r INPUT
                case "${INPUT,,}" in
                    ""|1|qemu|kvm|proxmox) VM_PLATFORM="qemu"       ;;
                    2|virtualbox|vbox)     VM_PLATFORM="virtualbox" ;;
                    *) echo "Invalid — enter 1-2 or qemu/virtualbox" ;;
                esac
            done
        fi

        case "$VM_PLATFORM" in
            qemu|virtualbox) ;;
            *) echo "error: invalid VM platform '${VM_PLATFORM}' — must be qemu or virtualbox" >&2; exit 1 ;;
        esac

        if [ "$VM_PLATFORM" != "$OLD_VM_PLATFORM" ]; then
            VM_PLATFORM_CHANGED="true"
        fi

        # As with the DE, "qemu" is the option's own NixOS default, so a
        # QEMU/Proxmox guest needs no features.nix entry unless the file
        # already exists.
        if [ "$VM_PLATFORM" != "qemu" ] || [ -f /etc/nixos/features.nix ]; then
            _features_set "vexos.vm.platform" "$VM_PLATFORM"
        fi
    fi

    # Desktop environment selection (desktop role only).
    DE_CHANGED="false"
    if [ "$ROLE" = "desktop" ]; then
        # Capture the CURRENTLY ACTIVE desktop environment before anything
        # below rewrites features.nix, so we can tell whether this switch is
        # actually changing the DE. Only an uncommented line counts — a
        # commented line has no effect on the running system, so the true
        # active value in that case is still the NixOS default, "gnome".
        OLD_DESKTOP_ENV="gnome"
        if [ -f /etc/nixos/features.nix ]; then
            _old="$(grep -oP '^\s*vexos\.desktop\.environment\s*=\s*"\K[a-z]+' /etc/nixos/features.nix 2>/dev/null || true)"
            [ -n "$_old" ] && OLD_DESKTOP_ENV="$_old"
        fi

        if [ -z "$DESKTOP_ENV" ]; then
            echo ""
            echo "Select desktop environment:"
            echo "  1) gnome    — Full-featured, most tested (default)"
            echo "  2) cosmic   — System76's new Rust-based desktop"
            echo "  3) hyprland — Tiling Wayland compositor + DankMaterialShell"
            echo ""
            while [ -z "$DESKTOP_ENV" ]; do
                printf "Choice [1-3] or name (default: gnome): "
                read -r INPUT
                case "${INPUT,,}" in
                    ""|1|gnome) DESKTOP_ENV="gnome"    ;;
                    2|cosmic)   DESKTOP_ENV="cosmic"   ;;
                    3|hyprland) DESKTOP_ENV="hyprland" ;;
                    *) echo "Invalid — enter 1-3 or gnome/cosmic/hyprland" ;;
                esac
            done
        fi

        case "$DESKTOP_ENV" in
            gnome|cosmic|hyprland) ;;
            *) echo "error: invalid desktop environment '${DESKTOP_ENV}' — must be gnome, cosmic, or hyprland" >&2; exit 1 ;;
        esac

        if [ "$DESKTOP_ENV" != "$OLD_DESKTOP_ENV" ]; then
            DE_CHANGED="true"
        fi

        # Only touches features.nix for a non-default DE — gnome stays the
        # implicit default with no file needed, matching
        # vexos.desktop.environment's own NixOS default.
        if [ "$DESKTOP_ENV" != "gnome" ] || [ -f /etc/nixos/features.nix ]; then
            _features_set "vexos.desktop.environment" "$DESKTOP_ENV"
        fi
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")

    # A desktop-environment change is never applied live. nixos-rebuild switch
    # restarts changed systemd units in the running session — for a DE change
    # that means restarting the display manager (GDM <-> greetd) underneath
    # the session you're currently sitting in. Confirmed on real hardware:
    # the old display manager can survive under the newly-aliased unit name
    # and crash, leaving a black screen with no way back in short of a reboot
    # anyway. So for a DE change, build it, queue it for next boot via
    # `nixos-rebuild boot` (which never restarts running services), and
    # reboot straight into it — no live activation attempt, no [y/N] prompt,
    # since the current session can't reach the new DE without a reboot
    # regardless of the answer.
    #
    # A VM-platform change is queued the same way, for a different reason: it
    # swaps boot.kernelPackages (VirtualBox pins 6.18 LTS, QEMU follows the
    # role's own kernel) and swaps the guest-additions services. A live switch
    # would leave the running kernel mismatched against the new generation's
    # modules, so it needs a reboot regardless — queue it rather than half-apply.
    if [ "$DE_CHANGED" = "true" ] || [ "$VM_PLATFORM_CHANGED" = "true" ]; then
        if [ "$DE_CHANGED" = "true" ]; then
            echo "Desktop environment is changing: ${OLD_DESKTOP_ENV} -> ${DESKTOP_ENV}"
        fi
        if [ "$VM_PLATFORM_CHANGED" = "true" ]; then
            echo "VM platform is changing: ${OLD_VM_PLATFORM} -> ${VM_PLATFORM} (kernel change)"
        fi
        echo "This is not safe to apply live, so it will be built"
        echo "and queued for the next boot instead of applied to this session."
        echo ""
        sudo nixos-rebuild boot --impure --flake "path:${_flake_dir}#${TARGET}"
        echo ""
        echo "✓ All set — ${TARGET} is queued as the next boot entry. Rebooting now..."
        sleep 2
        sudo systemctl reboot
        exit 0
    fi

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
    if [ "$(just _confirm 'Reboot now? [y/N]: ')" = "true" ]; then
        echo "Rebooting..."; sudo systemctl reboot
    else
        echo "Skipped — reboot manually when ready."
    fi

# Migrate an already-installed host to Limine (opt-in, UEFI only).
# Non-destructive: patches /etc/nixos/flake.nix, rebuilds, and reorders
# BootOrder, but leaves the existing systemd-boot NVRAM entry and ESP files
# in place as a fallback. Reboot and confirm Limine actually boots, THEN run
# `just switch-bootloader-cleanup` to remove the old entry and files.
# Example: just switch-bootloader limine
[group('System Build & Deploy')]
switch-bootloader target="limine":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just switch-bootloader must be run on the target NixOS host." >&2
        exit 1
    fi
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "error: efibootmgr not found — is this a UEFI system?" >&2
        exit 1
    fi

    TARGET_LOADER="{{target}}"
    if [ "$TARGET_LOADER" != "limine" ]; then
        echo "error: unsupported target '${TARGET_LOADER}' — only 'limine' is supported." >&2
        exit 1
    fi

    if [ ! -f /etc/nixos/flake.nix ]; then
        echo "error: /etc/nixos/flake.nix not found — run this on an installed vexos-nix host." >&2
        exit 1
    fi
    if [ ! -d /sys/firmware/efi ]; then
        echo "error: Limine migration is only supported on UEFI systems." >&2
        exit 1
    fi
    if grep -qE 'vexos\.bootloader\s*=\s*"limine"' /etc/nixos/flake.nix; then
        echo "Already configured for Limine — nothing to do."
        exit 0
    fi
    if [ ! -f /etc/nixos/vexos-variant ]; then
        echo "error: /etc/nixos/vexos-variant not found — cannot determine the active flake target." >&2
        exit 1
    fi
    VARIANT="$(cat /etc/nixos/vexos-variant)"
    case "$VARIANT" in
        vexos-vanilla-*)
            echo "error: the vanilla role does not support vexos.bootloader —" >&2
            echo "       configuration-vanilla.nix sets boot.loader.systemd-boot" >&2
            echo "       directly and never imports modules/system.nix, so this" >&2
            echo "       patch would break evaluation. Not supported for vanilla." >&2
            exit 1
            ;;
    esac

    echo "This will:"
    echo "  1. Patch /etc/nixos/flake.nix to use Limine (vexos.bootloader = \"limine\")"
    echo "  2. Rebuild and switch live — Limine installs ALONGSIDE the current"
    echo "     systemd-boot entry, which is left in place as a fallback"
    echo "  3. Reorder the UEFI BootOrder to put Limine first"
    echo ""
    echo "Nothing is removed by this step. Once you've rebooted and confirmed"
    echo "Limine boots correctly, run: just switch-bootloader-cleanup"
    echo ""
    if [ "$(just _confirm 'Continue? [y/N]: ')" != "true" ]; then
        echo "Aborted."
        exit 0
    fi

    # Record the pre-existing systemd-boot NVRAM entry number(s) now, before
    # Limine's installer runs — once both entries exist side by side, "which
    # one is old" is no longer obvious. switch-bootloader-cleanup reads this
    # back rather than guessing by label.
    #
    # Match ONLY "Linux Boot Manager" — the exact label NixOS's systemd-boot
    # installer registers for itself. Deliberately NOT a broader
    # "systemd-boot" substring match: modules/boot-discovery.nix registers
    # entries like "NixOS/systemd-boot [tag]" for OTHER disks it finds — a
    # looser match here would capture and later delete those too, destroying
    # the exact cross-disk dual-boot entries this feature exists to keep.
    OLD_ENTRIES_FILE="/etc/nixos/.vexos-bootloader-migration-old-entries"
    efibootmgr | grep -iP '^Boot[0-9A-Fa-f]{4}\*?\s+Linux Boot Manager\s*$' | grep -oP '^Boot\K[0-9A-Fa-f]{4}' \
        | sudo tee "$OLD_ENTRIES_FILE" >/dev/null || true

    echo "Patching /etc/nixos/flake.nix..."
    sudo awk '
      /^    bootloaderModule = \{ \.\.\. \}: \{/ {
        print "    bootloaderModule = { ... }: {"
        print "      vexos.bootloader = \"limine\";"
        print "    };"
        in_block = 1
        depth = 1
        next
      }
      in_block {
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == "{") depth++
          else if (c == "}") depth--
        }
        if (depth <= 0) in_block = 0
        next
      }
      { print }
    ' /etc/nixos/flake.nix | sudo tee /tmp/vexos-flake-limine.tmp >/dev/null
    if ! grep -q 'limine' /tmp/vexos-flake-limine.tmp; then
        echo "error: patch failed — bootloaderModule block not found in flake.nix." >&2
        sudo rm -f /tmp/vexos-flake-limine.tmp
        exit 1
    fi
    sudo mv /tmp/vexos-flake-limine.tmp /etc/nixos/flake.nix
    echo "✓ flake.nix updated for Limine."
    echo ""

    echo "Rebuilding and switching to Limine..."
    sudo nixos-rebuild switch --impure --flake "path:/etc/nixos#${VARIANT}"

    NEW_LIMINE_LINE="$(efibootmgr | grep -i limine || true)"
    if [ -z "$NEW_LIMINE_LINE" ]; then
        echo ""
        echo "warning: config applied, but no Limine NVRAM entry was found." >&2
        echo "         The old systemd-boot entry was NOT touched — do not run" >&2
        echo "         switch-bootloader-cleanup. Investigate before rebooting." >&2
        exit 1
    fi
    LIMINE_NUM="$(echo "$NEW_LIMINE_LINE" | grep -oP '^Boot\K[0-9A-Fa-f]{4}' | head -n1)"

    # Put Limine first in BootOrder without dropping any other entry.
    CURRENT_ORDER="$(efibootmgr | grep -oP '^BootOrder:\s*\K.*' || true)"
    if [ -n "$CURRENT_ORDER" ] && [ -n "$LIMINE_NUM" ]; then
        REST="$(echo "$CURRENT_ORDER" | tr ',' '\n' | grep -vi "^${LIMINE_NUM}$" | paste -sd, -)"
        if [ -n "$REST" ]; then
            sudo efibootmgr -o "${LIMINE_NUM},${REST}" >/dev/null
        else
            sudo efibootmgr -o "${LIMINE_NUM}" >/dev/null
        fi
        echo "✓ BootOrder updated — Limine (Boot${LIMINE_NUM}) is now first."
    fi

    echo ""
    echo "✓ Limine installed. The old systemd-boot entry and /boot files are"
    echo "  still in place as a fallback. Reboot now and confirm Limine boots"
    echo "  correctly, THEN run: just switch-bootloader-cleanup"

# Finish a Limine migration started with `just switch-bootloader limine`.
# Destructive: removes the old systemd-boot NVRAM entry and orphaned ESP
# files. Refuses to run unless the CURRENT boot session actually used the
# Limine NVRAM entry — proof the machine really did boot into it — so it
# cannot be run before a successful reboot has actually happened.
[group('System Build & Deploy')]
switch-bootloader-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "error: efibootmgr not found — is this a UEFI system?" >&2
        exit 1
    fi

    EFIBOOTMGR_OUT="$(efibootmgr)"
    LIMINE_LINE="$(echo "$EFIBOOTMGR_OUT" | grep -i limine || true)"
    if [ -z "$LIMINE_LINE" ]; then
        echo "error: no Limine NVRAM entry found — nothing to clean up." >&2
        exit 1
    fi
    LIMINE_NUM="$(echo "$LIMINE_LINE" | grep -oP '^Boot\K[0-9A-Fa-f]{4}' | head -n1)"
    BOOT_CURRENT="$(echo "$EFIBOOTMGR_OUT" | grep -oP '^BootCurrent:\s*\K[0-9A-Fa-f]{4}' || true)"

    if [ -z "$BOOT_CURRENT" ] || [ "${BOOT_CURRENT^^}" != "${LIMINE_NUM^^}" ]; then
        echo "error: this session did not boot via the Limine NVRAM entry" >&2
        echo "       (BootCurrent=${BOOT_CURRENT:-unknown}, Limine=${LIMINE_NUM:-unknown})." >&2
        echo "       Reboot, pick Limine, and re-run this recipe once you've" >&2
        echo "       confirmed it actually boots. Refusing to remove the" >&2
        echo "       systemd-boot fallback until that's proven." >&2
        exit 1
    fi

    echo "Confirmed: this session booted via Limine (Boot${LIMINE_NUM})."
    echo ""
    OLD_ENTRIES_FILE="/etc/nixos/.vexos-bootloader-migration-old-entries"
    if [ -f "$OLD_ENTRIES_FILE" ]; then
        echo "Removing old systemd-boot NVRAM entries:"
        while read -r NUM; do
            [ -n "$NUM" ] || continue
            if efibootmgr | grep -qP "^Boot${NUM}\b"; then
                echo "  - Boot${NUM}"
                sudo efibootmgr -b "$NUM" -B >/dev/null
            fi
        done < "$OLD_ENTRIES_FILE"
        sudo rm -f "$OLD_ENTRIES_FILE"
    else
        echo "note: no recorded old-entry list found (${OLD_ENTRIES_FILE})"
        echo "      falling back to removing any 'Linux Boot Manager' entry."
        # Same exact-label match as switch-bootloader's capture step — never
        # broaden this to a bare "systemd-boot" substring match, or it will
        # also delete boot-discovery.nix's cross-disk entries for other OSes.
        efibootmgr | grep -iP '^Boot[0-9A-Fa-f]{4}\*?\s+Linux Boot Manager\s*$' | grep -oP '^Boot\K[0-9A-Fa-f]{4}' | while read -r NUM; do
            echo "  - Boot${NUM}"
            sudo efibootmgr -b "$NUM" -B >/dev/null
        done
    fi

    echo ""
    echo "Removing orphaned systemd-boot files from /boot..."
    sudo rm -rf /boot/EFI/systemd /boot/loader
    echo "✓ Cleanup complete."

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

# Guard: refuse to rebuild when a custom kernel is enabled but the pinned
# version is not yet in the binary cache.
#
# Without this, Nix silently falls back to compiling the kernel locally when
# the builder host has not caught up with a pin bump — hours of CPU on a
# machine that was only supposed to download it. Checking the cache first turns
# a silent multi-hour surprise into an immediate, explanatory stop.
#
# Non-fatal by design in ambiguous cases: if the kernel feature is off, or the
# cache URL/key are unset, or the store path cannot be evaluated, this exits 0
# and lets the rebuild proceed normally.
[private]
_kernel-cache-guard:
    #!/usr/bin/env bash
    set -uo pipefail

    FEAT="/etc/nixos/features.nix"
    grep -qP '^\s*vexos\.features\.kernel\.enable\s*=\s*true' "$FEAT" 2>/dev/null || exit 0

    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || exit 0

    OUT=$(nix eval --impure --raw \
        "path:/etc/nixos#nixosConfigurations.${target}.config.boot.kernelPackages.kernel.outPath" \
        2>/dev/null) || exit 0
    [ -n "$OUT" ] || exit 0

    # Already in this machine's store — nothing to download.
    [ -e "$OUT" ] && exit 0

    URL=$(nix eval --impure --raw \
        "path:/etc/nixos#nixosConfigurations.${target}.config.vexos.harmonia.cacheUrl" \
        2>/dev/null) || exit 0
    [ -n "$URL" ] && [ "$URL" != "null" ] || exit 0

    HASH=$(basename "$OUT" | cut -c1-32)

    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${URL}/${HASH}.narinfo" 2>/dev/null) || exit 0
    [ "$code" = "200" ] && exit 0

    KVER=$(nix eval --impure --raw \
        "path:/etc/nixos#nixosConfigurations.${target}.config.boot.kernelPackages.kernel.version" \
        2>/dev/null || echo "?")

    echo "" >&2
    echo "  ✗ Custom kernel ${KVER} is NOT in the cache at ${URL}" >&2
    echo "" >&2
    echo "  Rebuilding now would COMPILE THE KERNEL ON THIS MACHINE (hours)." >&2
    echo "" >&2
    echo "  The build host has not produced this version yet. Either:" >&2
    echo "    - wait for its nightly build, or" >&2
    echo "    - run 'just kernel-build-now' on the build host, or" >&2
    echo "    - disable the custom kernel: just disable-feature kernel" >&2
    echo "" >&2
    echo "  To compile locally anyway, run nixos-rebuild directly." >&2
    echo "" >&2
    exit 1

# Rebuild the system using the current variant.
[group('System Build & Deploy')]
rebuild: _kernel-cache-guard
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    echo ""
    echo "Rebuilding ${target}..."
    echo ""
    sudo nixos-rebuild switch --impure --flake "path:/etc/nixos#${target}"

# Update all flake inputs, then rebuild and switch using the current variant.
# role/variant: only consulted when /etc/nixos/vexos-variant is absent (stateless
# reboot case) — same accepted values as `switch`. Ignored otherwise.
#
# On a VEXOS_CACHE_BLOCK (heavy kernel build), only nixpkgs is held back to
# its previous revision — up, vexportal, and vexboard (first-party GUI apps)
# still advance to whatever revision the update resolved, since they are
# never the cause of the block. See pkgs/vexos-update/default.nix.
[group('System Build & Deploy')]
update role="" variant="": _kernel-cache-guard
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")

    if [ -z "$target" ]; then
        ROLE="{{role}}"
        VARIANT="{{variant}}"

        if [ -z "$ROLE" ]; then
            echo ""
            echo "vexos-variant not found (stateless reboot?) — select target manually."
            echo ""
            echo "Select role:"
            echo "  1) desktop"
            echo "  2) stateless"
            echo "  3) htpc"
            echo "  4) server  (GUI or Headless)"
            echo ""
            while [ -z "$ROLE" ]; do
                printf "Choice [1-4] or name: "
                read -r INPUT
                case "${INPUT,,}" in
                    1|desktop)   ROLE="desktop"   ;;
                    2|stateless) ROLE="stateless" ;;
                    3|htpc)      ROLE="htpc"      ;;
                    4|server)    ROLE="server"    ;;
                    *) echo "Invalid — enter 1-4 or desktop/stateless/htpc/server" ;;
                esac
            done

            if [ "$ROLE" = "server" ]; then
                echo ""
                echo "Select server type:"
                echo "  1) Headless Server — CLI only, no desktop environment"
                echo "  2) GUI Server      — GNOME desktop environment"
                echo ""
                SERVER_TYPE=""
                while [ -z "$SERVER_TYPE" ]; do
                    printf "Choice [1-2] or name (headless / gui): "
                    read -r INPUT
                    case "${INPUT,,}" in
                        1|headless) SERVER_TYPE="headless" ;;
                        2|gui)      SERVER_TYPE="gui"       ;;
                        *) echo "Invalid — enter 1-2 or headless/gui" ;;
                    esac
                done
                if [ "$SERVER_TYPE" = "headless" ]; then
                    ROLE="headless-server"
                fi
            fi
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
                echo "  2) Legacy 580 — Maxwell/Pascal/Volta (580.x, required)"
                echo ""
                while true; do
                    printf "Choice [1-2]: "
                    read -r INPUT
                    case "${INPUT}" in
                        1) break ;;
                        2) VARIANT="nvidia-legacy580"; break ;;
                        *) echo "Invalid — enter 1 or 2" ;;
                    esac
                done
            fi
        fi

        target="vexos-${ROLE}-${VARIANT}"
    fi

    echo ""
    echo "Updating to: ${target}"
    echo ""

    # vexos-update (installed by modules/nix.nix) uses a known-heavy block
    # engine before applying any update:
    #   Non-heavy — system glue, vexos scripts, Rust crates, binary wrappers,
    #               NVIDIA driver, OpenRazer DKMS, kernel module aggregate;
    #               build locally in seconds-to-minutes; logged as VEXOS_LOCAL_BUILD,
    #               update proceeds normally.
    #   Heavy     — the kernel source build; takes hours;
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
# WITHOUT updating nixpkgs.
#
# Run this when just update reports a VEXOS_CACHE_BLOCK (nixpkgs has packages
# not yet in the binary cache).  Your latest config changes land immediately
# while nixpkgs stays pinned.  Run just update again in 1-2 days once the
# cache has caught up.
#
# nixpkgs stays pinned at whatever version is currently in
# /etc/nixos/flake.lock — no source builds triggered. up, vexportal, and
# vexboard (first-party GUI apps) are the exception: they still advance to
# whatever revision the new vexos-nix commit resolves, since they build in
# seconds and are never the cause of a cache block.
[group('System Build & Deploy')]
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    # vexos-deploy (installed by modules/nix.nix) does the work.  A bare
    # `nix flake update vexos-nix` is NOT sufficient: /etc/nixos/flake.nix has
    # nixpkgs.follows = "vexos-nix/nixpkgs", so nixpkgs is a transitive node and
    # updating vexos-nix re-locks it from the new upstream flake.lock — which,
    # given the daily lock-bump bot, moves nixpkgs on every deploy.  The script
    # updates vexos-nix and then holds every other node at its current revision.
    # Implementation lives in pkgs/vexos-deploy/ (writeShellApplication
    # shellchecks it at build time, and guarantees jq, which is not present on
    # every role).
    sudo vexos-deploy

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

    # Same heavy-build regex as vexos-update (pkgs/vexos-update/default.nix —
    # kept in sync manually): the kernel source build, which takes hours to
    # compile. Excludes the kernel module aggregates and NVIDIA/OpenRazer
    # userspace, which are local builds of minutes, not hours.
    HEAVY_BUILD_REGEX='^linux-[0-9][0-9.]*(-rc[0-9]+)?$'

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
        printf "  %-48s %s\n" "Other local builds (minutes — update proceeds):" "${NON_HEAVY_COUNT}"
        printf "  %-48s %s\n" "Heavy kernel source builds (hours — will block update):" "${HEAVY_COUNT}"
        echo ""

        if [ -n "$NON_HEAVY_BUILDS" ] && [ "$NON_HEAVY_COUNT" -gt 0 ]; then
            echo "  ── Other local builds (minutes — update will proceed) ──────────"
            printf '%s\n' "$NON_HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/    /'
            echo ""
        fi

        if [ -n "$HEAVY_BUILDS" ] && [ "$HEAVY_COUNT" -gt 0 ]; then
            echo "  ── Heavy builds — kernel not yet in cache (will block) ─────────"
            printf '%s\n' "$HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/    /'
            echo ""
            echo "  The kernel source build is not yet in the"
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
        echo "  ⚠ CONFIG OK — but ${HEAVY_COUNT} heavy kernel package(s) not yet in cache."
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
# All dconf first-run stamp files (app-folders, extensions — across every
# stamp version in use) are also removed so those first-run services
# re-apply on the next graphical login instead of seeing "already done".
# Run in a terminal (NOT inside a GNOME session) or log out first for best
# results, since GNOME may re-write some keys while running.
[group('System Administration')]
reset-defaults:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Resetting user dconf database — all GNOME customisations will be lost."
    if [ "$(just _confirm 'Continue? [y/N]: ')" != "true" ]; then
        echo "Aborted."
        exit 0
    fi
    dconf reset -f /
    rm -f "$HOME"/.local/share/vexos/.dconf-*-initialized*
    echo "Done. Log out and back in (or reboot) for all changes to take effect."
    echo "App folders will be restored on the next graphical login."

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
    if [ "$(just _confirm 'Rebuild now to apply fully via NixOS? [y/N]: ')" = "true" ]; then
        just rebuild
    else
        echo "Skipped — run 'just rebuild' when ready."
    fi

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
    if [ "$(just _confirm 'Rebuild now to apply? [y/N]: ')" = "true" ]; then
        just rebuild
    else
        echo "Run 'just rebuild' when ready."
    fi


# Available optional feature names (desktop, server, htpc, and vanilla roles).
_feature_names := "gaming development print3d virtualization sunshine kernel"

# Guard: abort if the current host is stateless or headless-server (features not
# supported there — neither role wires /etc/nixos/features.nix into its module set).
[private]
_require-desktop-role:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *stateless* || "$variant" == *headless* ]]; then
        echo "error: feature recipes are not available on stateless or headless-server roles."
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
    _check sunshine
    echo ""
    echo "Use 'just enable-feature <feature>' / 'just disable-feature <feature>' to toggle."
    echo ""

# Enable an optional feature module.  Usage: just enable-feature gaming
# Use 'just enable-feature all' to enable every feature.
[group('Optional Feature Toggles')]
enable-feature feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEATURE="{{feature}}"

    if [ "$FEATURE" = "all" ]; then
        for f in {{_feature_names}}; do
            just enable-feature "$f"
        done
        exit 0
    fi

    FEAT_FILE="/etc/nixos/features.nix"

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
        sudo sed -i "\$ s|^}|  ${OPTION} = true;\n}|" "$FEAT_FILE"
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
        sunshine)
            echo "  What this adds:"
            echo "    Services   Sunshine — self-hosted Moonlight game-stream host (KMS capture)"
            echo "    Firewall   Sunshine's TCP/UDP port range opened automatically"
            echo "    Groups     User added to uinput (remote mouse/keyboard input)"
            echo ""
            echo "  Two one-time manual steps remain after rebuild (cannot be scripted):"
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "<run 'tailscale ip -4' to find it>")
            echo "    1. Create the WebUI admin account (first run only): https://$TS_IP:47990"
            echo "    2. In Moonlight, add this host by IP ($TS_IP), then enter the PIN"
            echo "       shown under the WebUI's PIN tab to pair the client."
            ;;
        kernel)
            echo "  What this adds:"
            echo "    Kernel     Custom kernel from pkgs/kernels/ (default: ogc)"
            echo "               OGC = Open Gaming Collective — the unified kernel behind"
            echo "               Bazzite, ChimeraOS, Nobara, PikaOS and ASUS Linux."
            echo "               Ships NTSYNC, sched_ext, and handheld/ASUS enablement."
            echo ""
            echo "  Pick a different kernel by editing /etc/nixos/features.nix:"
            echo "    vexos.features.kernel.name = \"ogc\";"
            echo ""
            echo "  IMPORTANT: these kernels are not on cache.nixos.org. They are built"
            echo "  by a host running 'vexos.server.kernelBuilder' and served over"
            echo "  Harmonia. If that host has not built the current pin yet, this"
            echo "  machine would compile the kernel locally (hours) — 'just update'"
            echo "  checks the cache first and stops you before that happens."
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
# Use 'just disable-feature all' to disable every feature.
[group('Optional Feature Toggles')]
disable-feature feature: _require-desktop-role
    #!/usr/bin/env bash
    set -euo pipefail
    FEATURE="{{feature}}"

    if [ "$FEATURE" = "all" ]; then
        for f in {{_feature_names}}; do
            just disable-feature "$f"
        done
        exit 0
    fi

    FEAT_FILE="/etc/nixos/features.nix"

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
# Keep in sync with _service_catalog below, modules/server/default.nix, and
# template/server-services.nix.
_server_service_names := "adguard arcane arr attic audiobookshelf authelia backup caddy cockpit code-server docker dockhand dozzle forgejo grafana grimmory harmonia headscale kernel-builder home-assistant homepage immich jellyfin joplin kavita kiji-proxy komga listmonk loki matrix-conduit mealie minio nas navidrome netdata nextcloud nginx nginx-proxy-manager node-red ntfy paperless papermc photoprism plex podman portainer portbook prometheus proxmox rustdesk scrutiny searxng seerr stirling-pdf syncthing tautulli traefik unbound uptime-kuma vaultwarden vexboard zigbee2mqtt"

# Server service catalog — single source of truth for both `just
# available-services` (catalog view) and `just services` (per-host status).
# One line per module: group|name|description. Groups and order are rendered
# verbatim by both recipes. Descriptions must not contain a '|'.
# Keep in sync with _server_service_names above, modules/server/default.nix,
# and template/server-services.nix.
_service_catalog := '''
    Books & Reading|grimmory|Self-hosted ebook/comic/audiobook library
    Books & Reading|kavita|Self-hosted manga, comics & book library
    Books & Reading|komga|Comic book & manga media server
    Communications|matrix-conduit|Lightweight Matrix homeserver (chat protocol)
    Files & Storage|immich|Self-hosted photo & video backup
    Files & Storage|minio|S3-compatible object storage server
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
    Media|audiobookshelf|Self-hosted audiobook & podcast server
    Media|jellyfin|Open-source media streaming server
    Media|navidrome|Music streaming server (Subsonic-compatible)
    Media|plex|Personal media library & streaming server
    Media|tautulli|Monitoring & analytics for Plex Media Server
    Media Requests & Automation|arr|*arr suite — Sonarr, Radarr, Lidarr, Prowlarr, SABnzbd, Maintainerr
    Media Requests & Automation|seerr|Media request manager (Jellyfin, Plex, Emby)
    Monitoring & Admin|cockpit|Web-based Linux server management console
    Monitoring & Admin|dozzle|Real-time container log viewer
    Monitoring & Admin|grafana|Metrics visualisation & dashboards
    Monitoring & Admin|loki|Log aggregation system (pairs with Grafana)
    Monitoring & Admin|nas|Cockpit + NAS plugins (Samba, NFS, ZFS)
    Monitoring & Admin|netdata|Real-time performance & health monitoring
    Monitoring & Admin|portbook|Quick-access bookmark panel for services
    Monitoring & Admin|prometheus|Metrics collection & alerting toolkit
    Monitoring & Admin|scrutiny|S.M.A.R.T. disk health monitoring dashboard
    Monitoring & Admin|uptime-kuma|Self-hosted uptime & status page monitoring
    Monitoring & Admin|vexboard|VexOS Server dashboard (auto-enabled with first service)
    Networking & Security|adguard|DNS-based ad & tracker blocker
    Networking & Security|authelia|Single sign-on & two-factor auth gateway
    Networking & Security|headscale|Self-hosted Tailscale-compatible VPN (WireGuard)
    Networking & Security|unbound|Validating, recursive, caching DNS resolver
    Networking & Security|vaultwarden|Lightweight Bitwarden-compatible password manager
    Productivity|code-server|VS Code running in the browser
    Productivity|forgejo|Self-hosted Git & code collaboration (Gitea fork)
    Productivity|homepage|Customisable server dashboard & start page
    Productivity|joplin|Self-hosted Joplin Server note sync backend
    Productivity|listmonk|Self-hosted newsletter & mailing list manager
    Productivity|mealie|Self-hosted recipe manager & meal planner
    Productivity|paperless|Document scanning, OCR, tagging & archival
    Productivity|stirling-pdf|Web-based PDF editing & conversion tools
    Remote Access|rustdesk|Open-source self-hosted remote desktop server
    Smart Home & Notifications|home-assistant|Open-source home automation platform
    Smart Home & Notifications|node-red|Low-code flow-based automation editor
    Smart Home & Notifications|ntfy|Simple HTTP-based push notification server
    Smart Home & Notifications|zigbee2mqtt|Zigbee → MQTT bridge (no proprietary hub needed)
    AI & Privacy|kiji-proxy|Privacy-first OpenAI-compatible AI API proxy
    AI & Privacy|searxng|Privacy-respecting metasearch engine (no tracking, no query logging)
    Experimental|proxmox|Proxmox VE integration (experimental)
'''

# Prompt for a yes/no confirmation, printing `prompt` verbatim and reading a
# response exactly as the inline call sites did before this helper existed.
# When VEXOS_ASSUME_YES=1 (set by the VexPortal daemon, never by a human
# session), skips the prompt and answers yes immediately.
# Usage: if [ "$(just _confirm 'Continue? [y/N]: ')" = "true" ]; then ... fi
[private]
_confirm prompt:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        echo "true"
        exit 0
    fi
    printf '%s' "{{prompt}}" >&2
    read -r ANSWER || true
    case "${ANSWER,,}" in
        y|yes) echo "true" ;;
        *)     echo "false" ;;
    esac

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

# Guard: abort on roles that don't import modules/storage-remote.nix. The
# remote-mount module is wired on desktop, htpc, server and headless-server;
# stateless and vanilla are not covered yet (writing the config there would
# fail evaluation).
[private]
_require-remote-storage-role:
    #!/usr/bin/env bash
    set -euo pipefail
    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    case "$variant" in
        *desktop*|*htpc*|*server*) ;;
        *)
            echo "error: attach-remote-storage is not available on this role yet."
            echo "       current variant: ${variant:-unknown}"
            echo "       supported: desktop, htpc, server, headless-server."
            exit 1
            ;;
    esac

# Guided one-time setup for the sops-nix encrypted secrets backend
# (vexos.secrets.backend = "sops"). Generates the local age key used to
# decrypt secrets on this host, then prints the public key and a .sops.yaml
# snippet to add to the repo. Does not create or encrypt the secrets file
# itself — use the `sops <file>.yaml` edit workflow for that, it's already
# the right tool for the job.
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
    echo "  nextcloud-admin-pass, photoprism-password, minio-root-user,"
    echo "  minio-root-password, attic-server-token-rs256-secret-base64,"
    echo "  vexboard-auth-secret, kiji-proxy-openai-key, listmonk-admin-user,"
    echo "  listmonk-admin-password, vaultwarden-admin-token,"
    echo "  authelia-jwt-secret, authelia-session-secret,"
    echo "  authelia-storage-encryption-key"
    echo ""
    echo "Finally, set in your host config:"
    echo "  vexos.secrets.backend = \"sops\";"
    echo "  vexos.secrets.sopsFile = ./secrets/server/secrets.yaml;"

# Manually trigger a restic backup run outside the daily timer.
# Requires vexos.server.backup.enable = true.
backup-now: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    if ! systemctl list-unit-files restic-backups-main.service &>/dev/null; then
        echo "error: restic-backups-main.service not found — enable it first with 'just enable backup'."
        exit 1
    fi
    sudo systemctl start restic-backups-main.service --wait
    echo "✓ Backup run complete. Check status with: systemctl status restic-backups-main.service"

# Snapshot Plex's data directory (/var/lib/plex) to a single portable tar.gz,
# suitable for moving to a new server. Usage: just backup-plex [dest.tar.gz]
backup-plex dest="": _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    if ! systemctl list-unit-files plex.service &>/dev/null; then
        echo "error: plex.service not found — enable it first with 'just enable plex'." >&2
        exit 1
    fi

    DEST="{{dest}}"
    if [ -z "$DEST" ]; then
        DEST="./plex-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi

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
# freshly enabled Plex install (run 'just enable plex && just rebuild' on the
# new server first). Destructive — overwrites /var/lib/plex after a typed
# confirmation; the previous contents are preserved as a timestamped .bak
# directory rather than deleted. Usage: just restore-plex <tarball>
restore-plex tarball: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    TARBALL="{{tarball}}"
    if [ ! -f "$TARBALL" ]; then
        echo "error: '$TARBALL' not found." >&2
        exit 1
    fi

    if ! systemctl list-unit-files plex.service &>/dev/null; then
        echo "error: plex.service not found — enable it first with 'just enable plex && just rebuild'." >&2
        exit 1
    fi

    echo "This will stop Plex and replace /var/lib/plex with the contents of:"
    echo "  $TARBALL"
    # Typed-keyword confirm, not the [y/N] shape _confirm handles. Treated as
    # satisfied by VEXOS_ASSUME_YES=1 anyway: the VexPortal daemon only sets it
    # after its own destructive-action confirmation dialog has already run.
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        CONFIRM="yes"
    else
        read -r -p "Type 'yes' to continue: " CONFIRM
    fi
    if [ "$CONFIRM" != "yes" ]; then
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
restore-service name snapshot="latest": _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail

    NAME="{{name}}"
    SNAP="{{snapshot}}"
    MANIFEST=/etc/vexos/backup-paths.json

    RESTIC="$(command -v restic-main || true)"
    if [ -z "$RESTIC" ]; then
        echo "error: restic-main wrapper not found — enable backups with 'just enable backup && just rebuild'." >&2
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
    if [ "${VEXOS_ASSUME_YES:-}" = "1" ]; then
        CONFIRM="yes"
    else
        read -r -p "Type 'yes' to continue: " CONFIRM
    fi
    if [ "$CONFIRM" != "yes" ]; then
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

# Locate a script under scripts/ (walking up from $PWD, then known checkout
# locations, then the nix-store flake input) and run it as root. Shared by the
# storage-pool recipes below.
[private]
_run-storage-script script:
    #!/usr/bin/env bash
    set -euo pipefail
    SCRIPT_NAME="{{script}}"
    _jf_raw="{{justfile_directory()}}"
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")
    SCRIPT=""
    _walk="$PWD"
    while [ "$_walk" != "/" ] && [ -z "$SCRIPT" ]; do
        [ -f "$_walk/scripts/$SCRIPT_NAME" ] && SCRIPT="$_walk/scripts/$SCRIPT_NAME"
        _walk=$(dirname "$_walk")
    done
    for _candidate in "$_jf_raw/scripts" "$_jf_dir/scripts" "/etc/nixos/scripts" "$HOME/Projects/vexos-nix/scripts"; do
        [ -n "$SCRIPT" ] && break
        [ -f "$_candidate/$SCRIPT_NAME" ] && SCRIPT="$_candidate/$SCRIPT_NAME"
    done
    if [ -z "$SCRIPT" ] && [ -f /etc/nixos/flake.nix ]; then
        _vexos_store=$(nix eval --raw --expr '(builtins.getFlake "git+file:///etc/nixos").inputs.vexos-nix.outPath' 2>/dev/null || true)
        [ -n "$_vexos_store" ] && [ -f "$_vexos_store/scripts/$SCRIPT_NAME" ] && SCRIPT="$_vexos_store/scripts/$SCRIPT_NAME"
    fi
    [ -n "$SCRIPT" ] || { echo "error: scripts/$SCRIPT_NAME not found in any known location." >&2; exit 1; }
    sudo bash "$SCRIPT"

# Interactively build a mergerfs + SnapRAID "bulk" storage pool from mixed-
# capacity drives (media / general bulk storage). Server roles only.
# Formats the selected disks, mounts them, and writes a declarative
# /etc/nixos/storage-pool.nix. Requires vexos.server.nas.backend = "mergerfs"
# (or vexos.server.storage.mergerfs.enable) so the mergerfs userland is present.
# Destructive actions only run after a typed-keyword confirmation.
[private]
create-mergerfs-pool: _require-server-role
    @just _run-storage-script create-mergerfs-pool.sh

# Attach a NAS share exported by ANOTHER host (NFS or CIFS/SMB) declaratively,
# without hand-editing /etc/fstab. Available on desktop, htpc, server and
# headless-server. Non-destructive — client mount only. Writes/updates a
# declarative /etc/nixos/storage-remote.nix; apply with `just rebuild`.
[group('System Administration')]
attach-remote-storage: _require-remote-storage-role
    @just _run-storage-script attach-remote-storage.sh

# Detach a NAS share attached earlier by `just attach-remote-storage`. Interactive:
# lists the configured shares, removes the selected entry (or all) from the
# declarative /etc/nixos/storage-remote.nix, unmounts it, removes the empty
# mountpoint, and drops an orphaned CIFS credentials file. Applies nothing —
# apply with `just rebuild`.
[group('System Administration')]
detach-remote-storage: _require-remote-storage-role
    @just _run-storage-script detach-remote-storage.sh

# List all available server service modules (catalog view, no role required).
[private]
available-services:
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
        grafana)         printf "  %-18s  Web UI  http://<server-ip>:3030\n"                                           "$1" ;;
        harmonia)        printf "  %-18s  HTTP    http://<server-ip>:5000   (Nix binary cache)\n"                      "$1" ;;
        kernel-builder)  printf "  %-18s  No web UI — nightly timer; see 'just kernel-build-status'\n"            "$1" ;;
        grimmory)        printf "  %-18s  Web UI  http://<server-ip>:6060\n"                                           "$1" ;;
        headscale)       printf "  %-18s  Web UI  http://<server-ip>:8085\n"                                           "$1" ;;
        home-assistant)  printf "  %-18s  Web UI  http://<server-ip>:8123\n"                                           "$1" ;;
        homepage)        printf "  %-18s  Web UI  http://<server-ip>:3010   (requires docker)\n"                       "$1" ;;
        immich)          printf "  %-18s  Web UI  http://<server-ip>:2283\n"                                           "$1" ;;
        jellyfin)        printf "  %-18s  Web UI  http://<server-ip>:8096\n"                                           "$1" ;;
        joplin)          printf "  %-18s  Web UI  http://<tailnet-host>:22300   (Tailscale-only)\n"                     "$1" ;;
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
        searxng)         printf "  %-18s  Web UI  http://<server-ip>:8888   (loopback-only by default)\n"              "$1" ;;
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
        portainer)       printf "  %-18s  Web UI  https://<server-ip>:9443  (Docker/Podman container manager)\n"               "$1" ;;
        portbook)        printf "  %-18s  Web UI  http://<server-ip>:7777   |  CLI: portbook ls / tui / watch\n"       "$1" ;;
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

# Map a service name to its systemd unit(s) — shared by status and restart.
# Prints space-separated unit names (without .service) to stdout.
[private]
_service-units service:
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"
    case "$SERVICE" in
      adguard)        echo "adguardhome" ;;
      arcane)         echo "docker-arcane podman-arcane" ;;
      arr)            echo "sabnzbd sonarr radarr lidarr prowlarr docker-maintainerr"
                      ;;
      attic)          echo "atticd" ;;
      audiobookshelf) echo "audiobookshelf" ;;
      backup)         echo "restic-backups-main" ;;
      caddy)          echo "caddy" ;;
      nas)            echo "cockpit" ;;
      cockpit)        echo "cockpit" ;;
      docker)         echo "docker" ;;
      dockhand)       echo "docker-dockhand podman-dockhand" ;;
      forgejo)        echo "forgejo" ;;
      grafana)        echo "grafana" ;;
      harmonia)       echo "harmonia" ;;
      kernel-builder) echo "kernel-build-ogc" ;;
      grimmory)       echo "docker-grimmory docker-grimmory-db" ;;
      headscale)      echo "headscale" ;;
      home-assistant) echo "home-assistant" ;;
      homepage)       echo "docker-homepage" ;;
      immich)         echo "immich-server" ;;
      jellyfin)       echo "jellyfin" ;;
      joplin)         echo "docker-joplin-server docker-joplin-db" ;;
      kavita)         echo "kavita" ;;
      komga)          echo "komga" ;;
      kiji-proxy)     echo "kiji-proxy" ;;
      mealie)         echo "mealie" ;;
      nextcloud)      echo "phpfpm-nextcloud nginx" ;;
      nginx)          echo "nginx" ;;
      ntfy)           echo "ntfy" ;;
      seerr)          echo "seerr" ;;
      papermc)        echo "minecraft-server" ;;
      plex)           echo "plex" ;;
      podman)         echo "podman" ;;
      rustdesk)       echo "rustdesk-server hbbr hbbs" ;;
      scrutiny)       echo "scrutiny" ;;
      searxng)        echo "uwsgi" ;;
      stirling-pdf)   echo "docker-stirling-pdf" ;;
      syncthing)      echo "syncthing" ;;
      tautulli)       echo "tautulli" ;;
      traefik)        echo "traefik" ;;
      uptime-kuma)    echo "docker-uptime-kuma" ;;
      vaultwarden)    echo "vaultwarden" ;;
      vexboard)       echo "vexboard" ;;
      authelia)       echo "docker-authelia" ;;
      code-server)    echo "code-server" ;;
      dozzle)         echo "docker-dozzle" ;;
      listmonk)       echo "listmonk" ;;
      loki)           echo "loki" ;;
      matrix-conduit) echo "conduit" ;;
      minio)          echo "minio" ;;
      navidrome)      echo "navidrome" ;;
      netdata)        echo "netdata" ;;
      nginx-proxy-manager) echo "docker-nginx-proxy-manager" ;;
      node-red)       echo "node-red" ;;
      paperless)      echo "paperless" ;;
      photoprism)     echo "photoprism" ;;
      portainer)      echo "docker-portainer podman-portainer" ;;
      portbook)       echo "portbook" ;;
      prometheus)     echo "prometheus" ;;
      proxmox)        echo "pve-cluster pvedaemon pveproxy pvestatd pvescheduler" ;;
      unbound)        echo "unbound" ;;
      zigbee2mqtt)    echo "zigbee2mqtt" ;;
      *)              echo "$SERVICE" ;;
    esac

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

    UNITS=$(just _service-units "$SERVICE")

    # Map service → HTTP check URL(s)
    # Format for URLS: space-separated http://localhost:<port> entries (empty = no HTTP check)
    case "$SERVICE" in
      adguard)        URLS="http://localhost:3080" ;;
      arcane)         URLS="http://localhost:3552" ;;
      arr)            URLS="http://localhost:8080 http://localhost:8989 http://localhost:7878 http://localhost:8686 http://localhost:9696 http://localhost:6246" ;;
      attic)          URLS="http://localhost:8400" ;;
      audiobookshelf) URLS="http://localhost:8234" ;;
      backup)         URLS="" ;;
      caddy)          URLS="http://localhost:8880" ;;
      nas)            URLS="http://localhost:9090" ;;
      cockpit)        URLS="http://localhost:9090" ;;
      docker)         URLS="" ;;
      dockhand)       URLS="http://localhost:8073" ;;
      forgejo)        URLS="http://localhost:3000" ;;
      grafana)        URLS="http://localhost:3030" ;;
      harmonia)       URLS="http://localhost:5000" ;;
      kernel-builder) URLS="" ;;
      grimmory)       URLS="http://localhost:6060" ;;
      headscale)      URLS="http://localhost:8085" ;;
      home-assistant) URLS="http://localhost:8123" ;;
      homepage)       URLS="http://localhost:3010" ;;
      immich)         URLS="http://localhost:2283" ;;
      jellyfin)       URLS="http://localhost:8096" ;;
      joplin)         URLS="http://localhost:22300" ;;
      kavita)         URLS="http://localhost:5000" ;;
      komga)          URLS="http://localhost:8090" ;;
      kiji-proxy)     URLS="http://localhost:8080/health" ;;
      mealie)         URLS="http://localhost:9010" ;;
      nextcloud)      URLS="http://localhost:80" ;;
      nginx)          URLS="http://localhost:80" ;;
      ntfy)           URLS="http://localhost:2586" ;;
      seerr)          URLS="http://localhost:5055" ;;
      papermc)        URLS="" ;;
      plex)           URLS="http://localhost:32400/web" ;;
      podman)         URLS="" ;;
      rustdesk)       URLS="" ;;
      scrutiny)       URLS="http://localhost:8078" ;;
      searxng)        URLS="http://localhost:8888" ;;
      stirling-pdf)   URLS="http://localhost:8077" ;;
      syncthing)      URLS="http://localhost:8384" ;;
      tautulli)       URLS="http://localhost:8181" ;;
      traefik)        URLS="http://localhost:8079/dashboard/" ;;
      uptime-kuma)    URLS="http://localhost:3001" ;;
      vaultwarden)    URLS="http://localhost:8222" ;;
      vexboard)       URLS="http://localhost:7280" ;;
      authelia)       URLS="http://localhost:9091" ;;
      code-server)    URLS="http://localhost:4444" ;;
      dozzle)         URLS="http://localhost:8888" ;;
      listmonk)       URLS="http://localhost:9025" ;;
      loki)           URLS="http://localhost:3100/ready" ;;
      matrix-conduit) URLS="http://localhost:6167/_matrix/client/versions" ;;
      minio)          URLS="http://localhost:9001 http://localhost:9000" ;;
      navidrome)      URLS="http://localhost:4533" ;;
      netdata)        URLS="http://localhost:19999" ;;
      nginx-proxy-manager) URLS="http://localhost:81" ;;
      node-red)       URLS="http://localhost:1880" ;;
      paperless)      URLS="http://localhost:28981" ;;
      photoprism)     URLS="http://localhost:2342" ;;
      portainer)      URLS="https://localhost:9443" ;;
      portbook)       URLS="http://localhost:7777" ;;
      prometheus)     URLS="http://localhost:9092" ;;
      proxmox)        URLS="https://localhost:8006" ;;
      unbound)        URLS="" ;;
      zigbee2mqtt)    URLS="http://localhost:8088" ;;
      *)              URLS="" ;;
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

# Restart a server service (all its systemd units), clearing any prior
# start-limit-hit failure first. Usage: just restart joplin
[private]
restart service: _require-server-role
    #!/usr/bin/env bash
    set -euo pipefail
    SERVICE="{{service}}"

    VALID_SERVICES="{{_server_service_names}}"
    if ! echo "$VALID_SERVICES" | tr ' ' '\n' | grep -qx "$SERVICE"; then
        echo "error: unknown service '$SERVICE'"
        echo "available: $VALID_SERVICES"
        exit 1
    fi

    UNITS=$(just _service-units "$SERVICE")
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
        [ "$svc" = "kernel-builder" ] && nix_name="kernelBuilder"
        if grep -qP "vexos\.server\.(${svc}|${nix_name})\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            printf "    \033[32m✓\033[0m %s\n" "$svc"
        elif [ "$svc" = "arr" ] && grep -qP '^\s*vexos\.server\.arr\.\w+\.enable\s*=\s*true' "$SVC_FILE" 2>/dev/null; then
            printf "    \033[32m✓\033[0m %s\n" "$svc"
        else
            printf "    \033[90m✗\033[0m %s\n" "$svc"
        fi
    }
    echo ""
    echo "Server services (/etc/nixos/server-services.nix):"
    prev_group=""
    while IFS='|' read -r group name desc; do
        [ -z "$group" ] && continue
        if [ "$group" != "$prev_group" ]; then
            printf "\n  \033[1m%s\033[0m\n" "$group"
            prev_group="$group"
        fi
        _check "$name"
    done <<< '{{ replace(_service_catalog, "'", "'\\''") }}'
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

    # ── Storage-tier advisory ────────────────────────────────────────────────
    # Some services want a specific storage tier. Tell the operator which pool
    # this service expects, detect whether one exists (local pool OR remote
    # mount), and offer to set one up. Never blocks enabling — informational.
    # Single source of truth for service → tier mapping (edit here to reclassify).
    _storage_tier=""
    case "$SERVICE" in
        proxmox)
            _storage_tier="zfs-vm" ;;
        nextcloud|immich|photoprism|paperless|minio|syncthing|forgejo)
            _storage_tier="zfs-live" ;;
        jellyfin|plex|navidrome|audiobookshelf|kavita|komga|arr)
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
                    y|yes) just create-zfs-pool ;;
                    *)     echo "  Skipped — run 'just create-zfs-pool' before starting VMs." ;;
                esac
            else
                echo "  Where should its storage live?"
                echo "    1) Local mergerfs+SnapRAID pool   (mixed-capacity drives)"
                echo "    2) Local ZFS pool                 (matched drives / realtime redundancy)"
                echo "    3) Attach a remote storage server (NFS/SMB from another host)"
                echo "    4) Skip — configure later"
                read -r -p "  Choice [1-4]: " _sp
                case "$_sp" in
                    1) just create-mergerfs-pool ;;
                    2) just create-zfs-pool ;;
                    3) just attach-remote-storage ;;
                    *) echo "  Skipped — run 'just create-mergerfs-pool', 'just create-zfs-pool', or 'just attach-remote-storage' later." ;;
                esac
            fi
        fi
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

    # The option uses dots as-is (e.g. uptime-kuma stays uptime-kuma),
    # except kernel-builder whose module declares camelCase kernelBuilder.
    OPT_NAME="$SERVICE"
    [ "$SERVICE" = "kernel-builder" ] && OPT_NAME="kernelBuilder"
    OPTION="vexos.server.${OPT_NAME}.enable"

    # Insert-or-replace a "key = value;" line in $SVC_FILE.
    _set_flag() {
        local opt="$1" val="$2" esc="${1//./\\.}"
        if grep -qP "^\s*#?\s*${esc}\s*=\s*(true|false)\s*;" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s/^(\s*)#?\s*(${esc})\s*=\s*(true|false)\s*;/\1${opt} = ${val};/" "$SVC_FILE"
        else
            sudo sed -i "\$ s|^}|  ${opt} = ${val};\n}|" "$SVC_FILE"
        fi
    }

    # Arr stack: full-stack or individual-component selection.
    if [ "$SERVICE" = "arr" ]; then
        ARR_COMPONENTS="sabnzbd sonarr radarr lidarr prowlarr qbittorrent bazarr maintainerr"
        if grep -qP '^\s*vexos\.server\.arr\.(enable|\w+\.enable)\s*=\s*true' "$SVC_FILE" 2>/dev/null; then
            echo "arr is already enabled (or has enabled components). Use 'just disable arr' first to reconfigure."
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
                _set_flag "vexos.server.arr.${_c}.enable" true
                _arr_enabled="$_arr_enabled $_c"
            done
            if [ -z "$_arr_enabled" ]; then
                echo "error: no valid components selected" >&2
                exit 1
            fi
            echo "✓ Enabled arr components:$_arr_enabled"
        else
            _set_flag "$OPTION" true
            _arr_enabled=" sabnzbd sonarr radarr lidarr prowlarr"
            echo "✓ Enabled: $SERVICE (full stack)"
        fi

        VB_OPTION="vexos.server.vexboard.enable"
        if ! grep -qP "^\s*vexos\.server\.vexboard\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            _set_flag "$VB_OPTION" true
            echo "  + VexBoard also enabled (server dashboard — http://<server-ip>:7280)"
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
    # auto-enable block below), and running `just enable backup` explicitly must
    # still let the user re-point the repository / passwordFile via the
    # interactive prompt block rather than silently no-op.
    if [ "$SERVICE" != "backup" ] && grep -q "${OPTION}\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
        echo "$SERVICE is already enabled."
        exit 0
    fi

    # If a commented-out or false line exists, replace it
    if grep -qP "^\s*#?\s*${OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
        sudo sed -i -E "s/^(\s*)#?\s*(${OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${OPTION} = true;/" "$SVC_FILE"
    else
        # Insert before the closing brace (anchored to the last line so a
        # nested "}" earlier in the file can never be mistaken for it)
        sudo sed -i "\$ s|^}|  ${OPTION} = true;\n}|" "$SVC_FILE"
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

    # Backup repository + password file prompts — both required at enable time.
    if [ "$SERVICE" = "backup" ]; then
        REPO_OPTION="vexos.server.backup.repository"
        _backup_repo=""
        while [ -z "$_backup_repo" ]; do
            read -r -p "  Enter the restic repository (e.g. /mnt/backup/restic-repo or sftp:user@host:/path): " _backup_repo
        done
        if grep -qP "^\s*#?\s*${REPO_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${REPO_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${REPO_OPTION} = \"${_backup_repo}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${OPTION} = true;|${OPTION} = true;\n  ${REPO_OPTION} = \"${_backup_repo}\";|" "$SVC_FILE"
        fi

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
        if grep -qP "^\s*#?\s*${PW_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
            sudo sed -i -E "s|^(\s*)#?\s*(${PW_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${PW_OPTION} = \"${_backup_pw_file}\";|" "$SVC_FILE"
        else
            sudo sed -i "s|${REPO_OPTION} = \"${_backup_repo}\";|${REPO_OPTION} = \"${_backup_repo}\";\n  ${PW_OPTION} = \"${_backup_pw_file}\";|" "$SVC_FILE"
        fi
    fi

    echo "✓ Enabled: $SERVICE"

    # Ensure Arcane has appUrl and environmentFile — required by the build
    # assertion. appUrl is host-specific and must be supplied by the user;
    # environmentFile (ENCRYPTION_KEY/JWT_SECRET) is auto-generated, mirroring
    # the SearXNG/VexBoard secret pattern below since there is no external
    # value for the user to supply for those.
    if [ "$SERVICE" = "arcane" ]; then
        ARCANE_URL_OPTION="vexos.server.arcane.appUrl"
        ARCANE_ENV_OPTION="vexos.server.arcane.environmentFile"
        ARCANE_SECRET_PATH="/etc/nixos/secrets/arcane-env"

        _arcane_url_set="$(grep -oP "^\s*${ARCANE_URL_OPTION//./\\.}\s*=\s*\"\K[^\"]*" "$SVC_FILE" 2>/dev/null || true)"
        if [ -z "$_arcane_url_set" ] || [ "$_arcane_url_set" = "http://arcane.example.com" ]; then
            _arcane_url=""
            while [ -z "$_arcane_url" ]; do
                read -r -p "  Enter the public URL for this Arcane instance (e.g. https://arcane.example.com): " _arcane_url
            done
            if grep -qP "^\s*#?\s*${ARCANE_URL_OPTION//./\\.}\s*=" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#?\s*(${ARCANE_URL_OPTION//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${ARCANE_URL_OPTION} = \"${_arcane_url}\";|" "$SVC_FILE"
            else
                sudo sed -i "\$ s|^}|  ${ARCANE_URL_OPTION} = \"${_arcane_url}\";\n}|" "$SVC_FILE"
            fi
        fi

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
            if grep -qP "^\s*#\s*${ARCANE_ENV_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#\s*(${ARCANE_ENV_OPTION//./\\.}\s*=\s*\"[^\"]*\")\s*;|\1\2;|" "$SVC_FILE"
            else
                sudo sed -i "\$ s|^}|  ${ARCANE_ENV_OPTION} = \"${ARCANE_SECRET_PATH}\";\n}|" "$SVC_FILE"
            fi
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
            if grep -qP "^\s*#\s*${SEARXNG_ENV_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#\s*(${SEARXNG_ENV_OPTION//./\\.}\s*=\s*\"[^\"]*\")\s*;|\1\2;|" "$SVC_FILE"
            else
                sudo sed -i "\$ s|^}|  ${SEARXNG_ENV_OPTION} = \"${SEARXNG_SECRET_PATH}\";\n}|" "$SVC_FILE"
            fi
        fi
    fi

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
                sudo sed -i "\$ s|^}|  vexos.server.vexboard.secretFile = \"${secret_path}\";\n}|" "$svc_file"
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
                sudo sed -i "\$ s|^}|  ${VB_OPTION} = true;\n}|" "$SVC_FILE"
            fi
            echo "  + VexBoard also enabled (server dashboard — http://<server-ip>:7280)"
        fi
        # Always ensure secretFile is set — runs even if VexBoard was already enabled
        # on a pre-existing VM where a prior session left enable=true but no secretFile.
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
            if grep -qP "^\s*#?\s*${repo_opt//./\\.}\s*=" "$svc_file" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#?\s*(${repo_opt//./\\.})\s*=\s*\"[^\"]*\"\s*;|\1${repo_opt} = \"${repo_default}\";|" "$svc_file"
            else
                sudo sed -i "\$ s|^}|  ${repo_opt} = \"${repo_default}\";\n}|" "$svc_file"
            fi
        fi

        if ! grep -qP "^\s*${pw_opt//./\\.}\s*=" "$svc_file" 2>/dev/null; then
            if [ ! -f "$pw_default" ]; then
                sudo mkdir -p /etc/nixos/secrets
                sudo chmod 700 /etc/nixos/secrets
                sudo nix shell nixpkgs#openssl -c openssl rand -base64 48 | sudo tee "$pw_default" > /dev/null
                sudo chmod 600 "$pw_default"
            fi
            if grep -qP "^\s*#\s*${pw_opt//./\\.}" "$svc_file" 2>/dev/null; then
                sudo sed -i -E "s|^(\s*)#\s*(${pw_opt//./\\.}\s*=\s*\"[^\"]*\")\s*;|\1\2;|" "$svc_file"
            else
                sudo sed -i "\$ s|^}|  ${pw_opt} = \"${pw_default}\";\n}|" "$svc_file"
            fi
        fi
    }

    # Auto-enable declarative backups alongside the first service enabled on this
    # host, with non-interactive local defaults. The interactive
    # `just enable backup` path (above) still owns custom repository / passwordFile
    # configuration for anyone pointing backups at a NAS or remote target.
    if [ "$SERVICE" != "backup" ]; then
        BK_OPTION="vexos.server.backup.enable"
        if ! grep -qP "^\s*vexos\.server\.backup\.enable\s*=\s*true" "$SVC_FILE" 2>/dev/null; then
            if grep -qP "^\s*#?\s*${BK_OPTION//./\\.}" "$SVC_FILE" 2>/dev/null; then
                sudo sed -i -E "s/^(\s*)#?\s*(${BK_OPTION//./\\.})\s*=\s*(true|false)\s*;/\1${BK_OPTION} = true;/" "$SVC_FILE"
            else
                sudo sed -i "\$ s|^}|  ${BK_OPTION} = true;\n}|" "$SVC_FILE"
            fi
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
        echo "  About:     Modern container management UI — browse containers, images, volumes, and networks from a browser."
        echo "  Backend:   vexos.server.arcane.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just enable podman' first)."
        echo "  appUrl and environmentFile (ENCRYPTION_KEY/JWT_SECRET) were configured above."
        ;;
      attic)
        echo "  Service:  atticd.service"
        echo "  HTTP:     http://<server-ip>:8400"
        echo "  About:    Modern, purpose-built Nix binary cache server. Push derivations from any machine; pull on rebuild."
        echo "  Note:     Credentials and the 'attic' CLI are set up automatically on rebuild."
        echo "  Next:     Run 'just attic-bootstrap' after rebuilding to create the cache and mint tokens."
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
        echo "  Backend:   vexos.server.dockhand.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just enable podman' first)."
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
      harmonia)
        echo "  Service:  harmonia.service"
        echo "  HTTP:     http://<server-ip>:5000"
        echo "  About:    Serves THIS host's /nix/store as a binary cache. Read-only —"
        echo "            there is no upload API. Paths appear by being built here, or"
        echo "            copied in with: nix copy --to ssh-ng://<this-host> <path>"
        echo "  Note:     The signing key is generated automatically on rebuild."
        echo "  Next:     Run 'just harmonia-info' to verify it is live and print"
        echo "            the client settings for your other machines."
        echo "  Warning:  Serves every store path on this host. Keep it on the LAN."
        ;;
      kernel-builder)
        echo "  Service:  kernel-build-<name>.service (one per configured kernel)"
        echo "  Timer:    nightly at 01:00 by default"
        echo "  About:    Builds the custom kernels in pkgs/kernels/ so other machines"
        echo "            can download them from this host instead of compiling."
        echo "  Requires: Harmonia — building without serving accomplishes nothing."
        echo "  First run: just kernel-build-now      (takes hours; safe to leave)"
        echo "  Watch:     just kernel-build-log"
        echo "  Status:    just kernel-build-status"
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
      joplin)
        echo "  Services: docker-joplin-server.service  docker-joplin-db.service"
        echo "  Web UI:   http://<tailnet-host>:22300   (Tailscale-only — see networking.firewall.interfaces.tailscale0)"
        echo "  About:    Self-hosted sync server for Joplin desktop/mobile clients (two-container stack: app + dedicated Postgres)."
        echo "  Login:    admin@localhost / admin — change from the web UI after first boot."
        echo "  Note:     If clients get 'invalid origin' sync errors, set vexos.server.joplin.baseUrl to your tailnet's fully-qualified MagicDNS name."
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
        echo "  Container: portainer (NixOS OCI container, Docker or Podman backend)"
        echo "  Web UI:   https://<server-ip>:9443"
        echo "  About:    Web UI for managing containers, images, volumes, and networks."
        echo "  Backend:  vexos.server.portainer.backend = \"docker\" (default, auto-enables Docker) or \"podman\" (requires 'just enable podman' first)."
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

# ── Binary Cache ──────────────────────────────────────────────────────────────

# Build this repo's custom pkgs/* packages and push them to a configured Attic
# cache. Requires `attic login <cache> <url> <token>` to have already been run
# once (see `just enable attic`'s setup guidance). Usage: just attic-push [cache]
[group('Binary Cache')]
attic-push cache="vexos":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v attic &>/dev/null; then
        echo "error: 'attic' CLI not found on PATH." >&2
        echo "  Install it, then run: attic login {{cache}} <url> <token>" >&2
        echo "  See 'just enable attic' for setup guidance." >&2
        exit 1
    fi

    PACKAGES="cockpit-navigator cockpit-file-sharing cockpit-identities brave-origin kiji-proxy portbook vexos-update"

    # Some packages (kiji-proxy) use a placeholder hash until `just enable
    # kiji-proxy` patches it in locally, so a single package failing to build
    # shouldn't abort the whole push — build/push each independently and
    # report a summary at the end.
    FAILED=""
    BUILD_LOG=$(mktemp)
    trap 'rm -f "$BUILD_LOG"' EXIT
    echo "Building and pushing custom packages..."
    for pkg in $PACKAGES; do
        echo "  building vexos.${pkg}..."
        if out_path=$(nix build --impure --no-link --print-out-paths \
            ".#nixosConfigurations.vexos-desktop-amd.pkgs.vexos.${pkg}" 2>"$BUILD_LOG"); then
            echo "  pushing ${pkg} -> {{cache}}..."
            if ! attic push "{{cache}}" "$out_path"; then
                echo "  ✗ push failed: ${pkg}" >&2
                FAILED="$FAILED $pkg"
            fi
        else
            echo "  ✗ build failed: ${pkg} (skipping — run 'just enable ${pkg}' first if it needs a one-time setup step)" >&2
            tail -5 "$BUILD_LOG" >&2
            FAILED="$FAILED $pkg"
        fi
    done

    echo ""
    if [ -n "$FAILED" ]; then
        echo "✗ Pushed with failures. Skipped/failed:${FAILED}" >&2
        exit 1
    fi
    echo "✓ Pushed all custom packages to Attic cache '{{cache}}'."

# One-time Attic cache bootstrap: mint an admin token, create the cache if it
# doesn't exist, print the public key for client substituter config, and mint
# a push-only token for CI (e.g. GitHub Actions). Run once after `just enable
# attic && just rebuild`. Safe to re-run — cache creation is idempotent.
# Usage: just attic-bootstrap [cache]
[group('Binary Cache')]
attic-bootstrap cache="vexos":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! systemctl is-active --quiet atticd; then
        echo "error: atticd.service is not running." >&2
        echo "  Run 'just enable attic && just rebuild' first." >&2
        exit 1
    fi

    if ! command -v attic &>/dev/null; then
        echo "error: 'attic' CLI not found on PATH." >&2
        echo "  It's installed automatically when Attic is enabled — run 'just rebuild' first." >&2
        exit 1
    fi

    echo "Minting a local admin token..."
    ADMIN_TOKEN=$(sudo atticd-atticadm make-token --sub "admin" \
        --pull "*" --push "*" --delete "*" \
        --create-cache "*" --configure-cache "*" --configure-cache-retention "*" \
        --validity "10 years")

    attic login local http://localhost:8400 "$ADMIN_TOKEN" >/dev/null

    if attic cache info "{{cache}}" &>/dev/null; then
        echo "Cache '{{cache}}' already exists — skipping creation."
    else
        echo "Creating cache '{{cache}}'..."
        attic cache create "{{cache}}"
    fi

    PUBLIC_KEY=$(attic cache info "{{cache}}" | grep -oP '(?<=Public Key: ).*')

    echo "Minting a push-only token for CI..."
    PUSH_TOKEN=$(sudo atticd-atticadm make-token --sub "github-actions" \
        --push "{{cache}}" --validity "1 year")

    echo ""
    echo "=========================================================="
    echo " Attic bootstrap complete"
    echo "=========================================================="
    echo ""
    echo "Admin token (private — keep for your own future cache administration):"
    echo "  $ADMIN_TOKEN"
    echo ""
    echo "Client substituter config (safe to commit — paste into e.g."
    echo "configuration-desktop.nix or a host-specific file):"
    echo "  vexos.attic.cacheUrl  = \"http://<server-ip>:8400/{{cache}}\";"
    echo "  vexos.attic.publicKey = \"$PUBLIC_KEY\";"
    echo ""
    echo "CI push token (secret — add as a GitHub Actions repo secret,"
    echo "e.g. ATTIC_PUSH_TOKEN):"
    echo "  $PUSH_TOKEN"
    echo ""

# Verify the Harmonia binary cache is live and print client configuration.
# Harmonia has no bootstrap step — the signing key is generated automatically
# on rebuild and there are no tokens or logins — so this recipe exists purely
# to answer "is it ready?" and "what do I paste on the other machines?".
# Usage: just harmonia-info
harmonia-info:
    #!/usr/bin/env bash
    set -euo pipefail

    PORT=5000

    # The signing key path is configurable, and the sops backend forces it into
    # /run/secrets (modules/secrets-sops.nix) — so resolve it from the running
    # configuration rather than assuming the default location.
    KEY="/var/lib/harmonia/cache-priv-key.pem"
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || true)
    if [ -n "$target" ]; then
        RESOLVED=$(nix eval --impure --raw \
            "path:/etc/nixos#nixosConfigurations.${target}.config.vexos.server.harmonia.signKeyPath" \
            2>/dev/null || true)
        if [ -n "$RESOLVED" ]; then
            KEY="$RESOLVED"
        fi
    fi

    # harmonia.service is socket-activated (harmonia.socket) — it is
    # legitimately "inactive (dead)" whenever idle. Check the socket, since
    # that's what determines whether the cache is actually ready to serve.
    if ! systemctl is-active --quiet harmonia.socket; then
        echo "error: harmonia.socket is not running." >&2
        echo "  Run 'just enable harmonia && just rebuild' first." >&2
        echo "  Then check: systemctl status harmonia.socket" >&2
        exit 1
    fi

    # /nix-cache-info is the first document any Nix client fetches. If this
    # returns, the cache is genuinely serving — not merely "the unit started".
    echo "Probing http://localhost:${PORT}/nix-cache-info ..."
    if ! CACHE_INFO=$(curl -fsS --max-time 5 "http://localhost:${PORT}/nix-cache-info"); then
        echo "error: harmonia.service is active but not answering on port ${PORT}." >&2
        echo "  Check: journalctl -u harmonia -n 50" >&2
        exit 1
    fi

    # Prefer the .pub written next to the key by the activation script. Under
    # the sops backend no .pub exists (the secret is the private half only, 0400
    # root), so fall back to deriving the public half from the private key —
    # which needs root, hence sudo.
    if [ -r "${KEY}.pub" ]; then
        PUBLIC_KEY=$(cat "${KEY}.pub")
    else
        # `sudo nix ... < "$KEY"` would not work: the redirect is opened by the
        # calling (unprivileged) shell. Read the key as root, convert as user.
        echo "No readable ${KEY}.pub — deriving the public key from $KEY (needs sudo)."
        if ! PUBLIC_KEY=$(sudo cat "$KEY" | nix --extra-experimental-features nix-command \
                key convert-secret-to-public); then
            echo "error: could not read or convert the signing key at $KEY." >&2
            echo "  Confirm it exists:  sudo ls -l $KEY" >&2
            echo "  If it is missing, it is generated on activation — try 'just rebuild'." >&2
            exit 1
        fi
    fi
    HOST=$(hostname)

    echo ""
    echo "=========================================================="
    echo " Harmonia is live"
    echo "=========================================================="
    echo ""
    echo "$CACHE_INFO" | sed 's/^/  /'
    echo ""
    echo "Client config (safe to commit — paste into /etc/nixos/features.nix,"
    echo "a host file, or configuration-desktop.nix on your other machines):"
    echo "  vexos.harmonia.cacheUrl  = \"http://${HOST}:${PORT}\";"
    echo "  vexos.harmonia.publicKey = \"${PUBLIC_KEY}\";"
    echo ""
    echo "Note: Harmonia serves only what is currently in THIS host's"
    echo "      /nix/store, and nix.settings min-free/max-free will garbage-"
    echo "      collect unreferenced paths. Pin anything that must stay served:"
    echo "        nix-store --add-root /var/lib/harmonia/roots/<name> -r <store-path>"
    echo ""

# ── Custom kernel pipeline ───────────────────────────────────────────────────
# These recipes drive modules/server/kernel-builder.nix. Run them on the host
# that builds kernels (the one running Harmonia), not on a desktop.

# Build a custom kernel now instead of waiting for the nightly timer.
# Takes hours and runs in the background — safe to disconnect.
# Usage: just kernel-build-now [name]
kernel-build-now name="ogc":
    #!/usr/bin/env bash
    set -euo pipefail
    UNIT="kernel-build-{{name}}"

    if ! systemctl list-unit-files "${UNIT}.service" &>/dev/null \
       || ! systemctl cat "${UNIT}.service" &>/dev/null; then
        echo "error: ${UNIT}.service does not exist." >&2
        echo "  Enable the builder first: just enable kernel-builder && just rebuild" >&2
        exit 1
    fi

    if systemctl is-active --quiet "$UNIT"; then
        echo "A build is already running. Watch it with: just kernel-build-log {{name}}"
        exit 0
    fi

    echo "Starting ${UNIT}..."
    sudo systemctl start --no-block "$UNIT"
    echo ""
    echo "Build started in the background. It takes hours on modest hardware."
    echo "  Watch:  just kernel-build-log {{name}}"
    echo "  Status: just kernel-build-status"

# Show custom kernel build status: running or not, how long, last result,
# and which version is currently pinned and served.
kernel-build-status:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob

    found=0
    for unit in /etc/systemd/system/kernel-build-*.service \
                /run/systemd/system/kernel-build-*.service \
                /etc/systemd/system/*.wants/kernel-build-*.service; do
        name=$(basename "$unit" .service)
        [ -n "$name" ] || continue
        found=1
        printf "\n\033[1m%s\033[0m\n" "$name"

        if systemctl is-active --quiet "$name"; then
            since=$(systemctl show -p ActiveEnterTimestamp --value "$name" 2>/dev/null || echo "")
            printf "  State:    \033[33mBUILDING\033[0m (since %s)\n" "${since:-unknown}"
        else
            result=$(systemctl show -p Result --value "$name" 2>/dev/null || echo "unknown")
            last=$(systemctl show -p ExecMainExitTimestamp --value "$name" 2>/dev/null || echo "")
            if [ "$result" = "success" ]; then
                printf "  State:    \033[32midle\033[0m (last run: success%s)\n" \
                    "${last:+, $last}"
            else
                printf "  State:    \033[31midle (last run: %s)\033[0m\n" "$result"
                echo   "  Logs:     just kernel-build-log ${name#kernel-build-}"
            fi
        fi

        next=$(systemctl show -p NextElapseUSecRealtime --value "${name}.timer" 2>/dev/null || echo "")
        [ -n "$next" ] && [ "$next" != "0" ] && printf "  Next run: %s\n" "$next"
    done

    if [ "$found" = "0" ]; then
        echo "No kernel build units found."
        echo "  Enable the builder: just enable kernel-builder && just rebuild"
        exit 0
    fi

    echo ""
    echo "Pinned kernel versions (pkgs/kernels/*/version.json):"
    for f in {{justfile_directory()}}/pkgs/kernels/*/version.json; do
        k=$(basename "$(dirname "$f")")
        printf "  %-10s %s\n" "$k" "$(grep -oP '\"tag\"\s*:\s*\"\K[^\"]+' "$f" 2>/dev/null || echo '?')"
    done

# Follow a custom kernel build's log output live.
# Usage: just kernel-build-log [name]
kernel-build-log name="ogc":
    journalctl -fu kernel-build-{{name}}
