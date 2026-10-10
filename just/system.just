# just/system.just — Build, switch, update and roll back the system; bootloader migration.
# Imported by the root justfile; recipe names share one namespace.

# Print the active role and GPU variant (e.g. vexos-desktop-amd).
[group('System Build & Deploy')]
[doc('Show the active role and GPU variant (e.g. vexos-desktop-amd)')]
variant:
    @cat /etc/nixos/vexos-variant 2>/dev/null || echo "unknown (run a build first)"

# Guard: build/switch recipes need nix and sudo on a Linux (NixOS) host.
[private]
_require-nixos:
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
        echo "error: this recipe must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

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

    TARGET={{quote(target)}}
    FLAKE_OVERRIDE={{quote(flake_override)}}

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

# Interactive role / GPU picker shared by switch and update. Prompts for
# whichever of role and variant is empty, then prints "<role> <variant>" on
# stdout — role becomes headless-server for a headless server, and variant
# nvidia-legacy580 for the legacy NVIDIA branch. Menus go to stderr so the
# caller can capture the answer with $(...).
[arg('role', pattern='|desktop|stateless|htpc|server|headless-server|vanilla')]
[arg('variant', pattern='|amd|nvidia|nvidia-legacy580|intel|vm')]
[private]
_pick-target role="" variant="":
    #!/usr/bin/env bash
    set -euo pipefail
    ROLE={{quote(role)}}
    VARIANT={{quote(variant)}}
    exec 3>&1 1>&2

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

    echo "$ROLE $VARIANT" >&3

# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                        — interactive prompt
#   just switch desktop amd            — direct switch
#   just switch desktop amd . cosmic   — explicit flake override + desktop environment
#   just switch desktop amd "" hyprland — desktop environment, default flake
#   just switch desktop vm "" "" virtualbox — VM hypervisor (qemu / virtualbox)
[group('System Build & Deploy')]
[doc('Switch role, GPU, desktop or hypervisor — prompts for anything not given')]
[arg('role', pattern='|desktop|stateless|htpc|server|headless-server|vanilla', help='desktop, stateless, htpc, server, headless-server, vanilla')]
[arg('variant', pattern='|amd|nvidia|nvidia-legacy580|intel|vm', help='amd, nvidia, nvidia-legacy580, intel, vm')]
[arg('de', pattern='|gnome|cosmic|hyprland', help='gnome, cosmic or hyprland (desktop role)')]
[arg('vmp', pattern='|qemu|virtualbox', help='qemu or virtualbox (vm variant)')]
switch role="" variant="" flake="" de="" vmp="": _require-nixos
    #!/usr/bin/env bash
    set -euo pipefail


    ROLE={{quote(role)}}
    VARIANT={{quote(variant)}}
    FLAKE_OVERRIDE={{quote(flake)}}
    DESKTOP_ENV={{quote(de)}}
    VM_PLATFORM={{quote(vmp)}}

    source "{{justfile_directory()}}/just/lib.sh"

    # _features_set <nix.option.path> <string-value>
    # Ensures /etc/nixos/features.nix exists (seeded from template/features.nix),
    # then sets the option in it — the same edit `just feature enable` makes, so
    # the file stays editable by both paths. Shared by the desktop-environment
    # and VM-platform blocks below.
    _features_set() {
        local FEAT_FILE="/etc/nixos/features.nix"
        [ -f "$FEAT_FILE" ] || seed_from_template features.nix "$FEAT_FILE" || true
        if [ -f "$FEAT_FILE" ]; then
            nix_set "$FEAT_FILE" "$1" "\"$2\""
            echo "✓ $1 set to $2 in $FEAT_FILE"
        fi
    }

    if [ -z "$ROLE" ] || [ -z "$VARIANT" ]; then
        picked=$({{_just}} _pick-target "$ROLE" "$VARIANT")
        read -r ROLE VARIANT <<< "$picked"
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
    _flake_dir=$({{_just}} _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")

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

    # `cmd || _rc=$?`, not `if ! cmd; then _rc=$?` — inside that `if`, $? is
    # the status of the negation (always 0), which made a failed switch exit 0.
    _rc=0
    sudo nixos-rebuild switch --impure --flake "path:${_flake_dir}#${TARGET}" || _rc=$?
    if [ $_rc -ne 0 ]; then
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
    if [ "$({{_just}} _confirm 'Reboot now? [y/N]: ')" = "true" ]; then
        echo "Rebooting..."; sudo systemctl reboot
    else
        echo "Skipped — reboot manually when ready."
    fi

# Migrate an already-installed host to Limine (opt-in, UEFI only).
# Non-destructive: patches /etc/nixos/flake.nix, rebuilds, and reorders
# BootOrder, but leaves the existing systemd-boot NVRAM entry and ESP files
# in place as a fallback. Reboot and confirm Limine actually boots, THEN run
# `just bootloader cleanup` to remove the old entry and files.
# Example: just bootloader switch limine
[private]
_bootloader-switch target="limine":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just bootloader switch must be run on the target NixOS host." >&2
        exit 1
    fi
    if ! command -v efibootmgr >/dev/null 2>&1; then
        echo "error: efibootmgr not found — is this a UEFI system?" >&2
        exit 1
    fi

    TARGET_LOADER={{quote(target)}}
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
    # bootloader.nix on a current wrapper; flake.nix on a legacy one (not yet
    # upgraded). Anchored so a commented-out example in the old header doesn't match.
    if grep -qsE '^\s*vexos\.bootloader\s*=\s*"limine"' /etc/nixos/bootloader.nix /etc/nixos/flake.nix; then
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
    echo "  1. Write /etc/nixos/bootloader.nix to use Limine (vexos.bootloader = \"limine\")"
    echo "  2. Rebuild and switch live — Limine installs ALONGSIDE the current"
    echo "     systemd-boot entry, which is left in place as a fallback"
    echo "  3. Reorder the UEFI BootOrder to put Limine first"
    echo ""
    echo "Nothing is removed by this step. Once you've rebooted and confirmed"
    echo "Limine boots correctly, run: just bootloader cleanup"
    echo ""
    if [ "$({{_just}} _confirm 'Continue? [y/N]: ')" != "true" ]; then
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

    echo "Writing /etc/nixos/bootloader.nix..."
    # A wrapper from before the side-file layout never imports bootloader.nix,
    # so upgrade it first (no-op for a current wrapper).
    bash "{{justfile_directory()}}/scripts/upgrade-wrapper.sh"
    printf '%s\n' \
        '# /etc/nixos/bootloader.nix' \
        '# Written by just bootloader switch — Limine instead of systemd-boot.' \
        '{' \
        '  vexos.bootloader = "limine";' \
        '}' | sudo tee /etc/nixos/bootloader.nix >/dev/null
    echo "✓ bootloader.nix written for Limine."
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
    echo "  correctly, THEN run: just bootloader cleanup"

# Finish a Limine migration started with `just bootloader switch limine`.
# Destructive: removes the old systemd-boot NVRAM entry and orphaned ESP
# files. Refuses to run unless the CURRENT boot session actually used the
# Limine NVRAM entry — proof the machine really did boot into it — so it
# cannot be run before a successful reboot has actually happened.
[private]
_bootloader-cleanup:
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

# Build a target without activating it — useful for testing config changes.
# Example: just build desktop amd
[group('System Build & Deploy')]
[doc('Build a role/GPU target without activating it')]
[arg('role', pattern='desktop|stateless|htpc|server|headless-server|vanilla', help='desktop, stateless, htpc, server, headless-server, vanilla')]
[arg('variant', pattern='amd|nvidia|nvidia-legacy580|intel|vm', help='amd, nvidia, nvidia-legacy580, intel, vm')]
build role variant flake="": _require-nixos
    #!/usr/bin/env bash
    set -euo pipefail


    TARGET={{quote("vexos-" + role + "-" + variant)}}
    FLAKE_OVERRIDE={{quote(flake)}}
    _flake_dir=$({{_just}} _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
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
    echo "    - run 'just kernel now' on the build host, or" >&2
    echo "    - disable the custom kernel: just feature disable kernel" >&2
    echo "" >&2
    echo "  To compile locally anyway, run nixos-rebuild directly." >&2
    echo "" >&2
    exit 1

# Rebuild the system using the current variant.
[group('System Build & Deploy')]
[doc('Rebuild and switch using the current variant')]
rebuild: _kernel-cache-guard
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null) || { echo "error: /etc/nixos/vexos-variant not found — run a build first"; exit 1; }
    echo ""
    echo "Rebuilding ${target}..."
    echo ""
    sudo nixos-rebuild switch --impure --flake "path:/etc/nixos#${target}" || {
        _rc=$?
        if command -v vexos-ai >/dev/null; then
            echo ""
            echo "Tip: run 'just diagnose rebuild' to have your AI assistant explain this failure."
        fi
        exit $_rc
    }

# Update all flake inputs, then rebuild and switch using the current variant.
# role/variant: only consulted when /etc/nixos/vexos-variant is absent (stateless
# reboot case) — same accepted values as `switch`. Ignored otherwise.
#
# On a VEXOS_CACHE_BLOCK (heavy kernel build), only nixpkgs is held back to
# its previous revision — up, vexportal, and vexboard (first-party GUI apps)
# still advance to whatever revision the update resolved, since they are
# never the cause of the block. See pkgs/vexos-update/default.nix.
[group('System Build & Deploy')]
[doc('Update flake inputs and rebuild (stops before a long kernel compile)')]
[arg('role', pattern='|desktop|stateless|htpc|server|headless-server|vanilla', help='only used when /etc/nixos/vexos-variant is missing')]
[arg('variant', pattern='|amd|nvidia|nvidia-legacy580|intel|vm', help='only used when /etc/nixos/vexos-variant is missing')]
update role="" variant="": _kernel-cache-guard
    #!/usr/bin/env bash
    set -euo pipefail
    target=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")

    if [ -z "$target" ]; then
        ROLE={{quote(role)}}
        VARIANT={{quote(variant)}}

        if [ -z "$ROLE" ] || [ -z "$VARIANT" ]; then
            echo ""
            echo "vexos-variant not found (stateless reboot?) — select target manually."
            picked=$({{_just}} _pick-target "$ROLE" "$VARIANT")
            read -r ROLE VARIANT <<< "$picked"
        fi

        target="vexos-${ROLE}-${VARIANT}"

        # vexos-update takes no target argument — it reads this stamp and stops
        # if it is missing. Restore it so the update can run; the next
        # activation rewrites it with its own copy.
        printf '%s\n' "$target" | sudo tee /etc/nixos/vexos-variant >/dev/null
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
[doc('Update and rebuild with no cache check (may compile for hours)')]
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
[doc('Pull the latest vexos-nix config without moving nixpkgs')]
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    # vexos-deploy (installed by modules/nix.nix) does the work.  A bare
    # `nix flake update vexos-nix` is NOT sufficient: /etc/nixos/flake.nix has
    # nixpkgs.follows = "vexos-nix/nixpkgs", so nixpkgs is a transitive node and
    # updating vexos-nix re-locks it from the new upstream flake.lock — which,
    # given the daily lock-bump bot, moves nixpkgs on every deploy.  The script
    # updates vexos-nix and then holds every other node at its current revision.
    # Implementation lives in pkgs/vexos-deploy/ (it is linted at build time
    # by writeShellApplication, which also guarantees jq — not present on
    # every role).
    sudo vexos-deploy

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
[doc('Check whether this config is ready for a new NixOS release (read-only)')]
[arg('target_version', pattern='[0-9]{2}\.[0-9]{2}', help='a NixOS release, e.g. 26.11')]
upgrade-analysis target_version:
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET={{quote(target_version)}}
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
[doc('Roll back to the previous generation and make it the boot default')]
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
[doc('Roll forward to the next generation and make it the boot default')]
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

# Each recipe below shows a numbered menu when run with no action, or runs an
# action directly:  `just vpn`  /  `just vpn up`  /  `just vpn region auto`.
# The actions themselves are the hidden _<group>-<action> recipes.

# Bootloader: migrate to Limine (UEFI, opt-in), then clean up the old entries.
[group('System Build & Deploy')]
[doc('Migrate to the Limine bootloader (UEFI), then clean up (menu)')]
bootloader action="" *args:
    @{{_just}} _menu bootloader "Bootloader" {{quote(action)}} {{quote(args)}} \
        "switch|Migrate to Limine, keeping the old entry as a fallback (optional: target)" \
        "cleanup|Remove the old boot entries once you have booted into Limine||warn"
