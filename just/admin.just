# just/admin.just — Day-to-day administration: power, GNOME reset, hostname, SSH keys.
# Imported by the root justfile; recipe names share one namespace.

# Reboot the system immediately.
[group('System Administration')]
[doc('Reboot now')]
reboot:
    sudo systemctl reboot

# Shut down the system immediately.
[group('System Administration')]
[doc('Power off now')]
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
[doc('Reset all GNOME settings to the VexOS defaults')]
reset-defaults:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Resetting user dconf database — all GNOME customisations will be lost."
    if [ "$({{_just}} _confirm 'Continue? [y/N]: ')" != "true" ]; then
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
[doc('Change the hostname (applies now, persists across rebuilds)')]
[arg('name', pattern='|[A-Za-z0-9][A-Za-z0-9.-]*')]
set-hostname name="":
    #!/usr/bin/env bash
    set -euo pipefail

    NAME={{quote(name)}}

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
    # on the next rebuild via the side-file written below.
    sudo hostnamectl set-hostname --transient "$NAME"
    echo "✓ Applied to running system (transient — persists after rebuild)"

    # Persist through NixOS rebuilds.
    # networking.hostName = lib.mkDefault "vexos" (in modules/network.nix) is
    # overridden by any plain assignment in a file the wrapper imports.
    DIR="/etc/nixos"
    PERSISTED=false

    if [ -f "$DIR/flake.nix" ]; then
        # A wrapper from before the side-file layout never imports hostname.nix,
        # so upgrade it first (no-op for a current wrapper).
        bash "{{justfile_directory()}}/scripts/upgrade-wrapper.sh"

        # Update the value in place wherever it is already set — e.g. carried
        # into hardware-local.nix by the wrapper upgrade, or hand-set in flake.nix.
        for _f in flake.nix hardware-local.nix hostname.nix; do
            if [ -f "$DIR/$_f" ] && grep -qP 'networking\.hostName\s*=' "$DIR/$_f"; then
                sudo sed -i -E "s|networking\.hostName\s*=\s*\"[^\"]*\"|networking.hostName = \"${NAME}\"|g" "$DIR/$_f"
                echo "✓ Updated networking.hostName in ${DIR}/${_f}"
                PERSISTED=true
            fi
        done

        # Otherwise write it as its own side-file the wrapper imports.
        if [ "$PERSISTED" = "false" ]; then
            printf '%s\n' \
                '# /etc/nixos/hostname.nix' \
                '# Written by just set-hostname.' \
                '{' \
                "  networking.hostName = \"${NAME}\";" \
                '}' | sudo tee "$DIR/hostname.nix" >/dev/null
            echo "✓ Set networking.hostName in ${DIR}/hostname.nix"
            PERSISTED=true
        fi
    fi

    if [ "$PERSISTED" = "false" ]; then
        echo ""
        echo "  Could not auto-update ${DIR}/flake.nix (not found)."
        echo "  To persist the hostname across rebuilds, add this line to a"
        echo "  module your flake imports:"
        echo ""
        echo "    networking.hostName = \"${NAME}\";"
        echo ""
    else
        echo "  Hostname will persist across rebuilds."
    fi

    echo ""
    if [ "$({{_just}} _confirm 'Rebuild now to apply fully via NixOS? [y/N]: ')" = "true" ]; then
        {{_just}} rebuild
    else
        echo "Skipped — run 'just rebuild' when ready."
    fi

# Set a static IPv4 address on the wired connection — persists across rebuilds.
# Prompts for address, prefix length, gateway and DNS, writes them as
# vexos.network.staticWired.* into /etc/nixos/local.nix (see modules/network.nix),
# then offers a rebuild. Re-running updates the values in place. Not available on
# the vanilla role, which does not load modules/network.nix.
[group('System Administration')]
[doc('Set a static IPv4 address for the wired connection (prompts)')]
static-ip:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{justfile_directory()}}/just/lib.sh"

    variant=$(cat /etc/nixos/vexos-variant 2>/dev/null || echo "")
    if [[ "$variant" == *vanilla* ]]; then
        echo "error: static-ip is not available on the vanilla role." >&2
        exit 1
    fi

    # Dotted-quad IPv4 with every octet 0-255.
    _valid_ipv4() {
        local -a _o
        local _x
        [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
        IFS=. read -ra _o <<< "$1"
        for _x in "${_o[@]}"; do
            (( 10#$_x <= 255 )) || return 1
        done
    }

    # Prompt until a valid IPv4 address is entered; EOF on stdin aborts.
    _ask_ip() {
        local _v=""
        while true; do
            printf '%s' "$1" >&2
            read -r _v || { echo "" >&2; echo "Aborted." >&2; exit 1; }
            _valid_ipv4 "$_v" && break
            echo "  Invalid — enter a dotted IPv4 address." >&2
        done
        printf '%s' "$_v"
    }

    echo ""
    echo "Configure a static IPv4 address for the wired connection."
    echo ""

    _ip=$(_ask_ip "IP address (e.g. 192.168.1.10): ")

    while true; do
        printf "Prefix length (e.g. 24): "
        read -r _prefix || { echo ""; echo "Aborted."; exit 1; }
        if [[ "$_prefix" =~ ^[0-9]{1,2}$ ]] && (( 10#$_prefix >= 1 && 10#$_prefix <= 32 )); then
            _prefix=$(( 10#$_prefix ))
            break
        fi
        echo "  Invalid — enter a number between 1 and 32."
    done

    _gw=$(_ask_ip "Default gateway (e.g. 192.168.1.1): ")
    _dns1=$(_ask_ip "Primary DNS server (e.g. 1.1.1.1): ")

    printf "Secondary DNS server (leave blank to skip): "
    read -r _dns2 || _dns2=""
    if [ -n "$_dns2" ] && ! _valid_ipv4 "$_dns2"; then
        echo "  Invalid secondary DNS — ignoring it."
        _dns2=""
    fi

    ADDR="${_ip}/${_prefix}"
    DNS_LIST="\"${_dns1}\""
    if [ -n "$_dns2" ]; then
        DNS_LIST="${DNS_LIST} \"${_dns2}\""
    fi

    echo ""
    echo "Settings to apply:"
    echo "  Address : ${ADDR}"
    echo "  Gateway : ${_gw}"
    echo "  DNS     : ${_dns1}${_dns2:+, ${_dns2}}"
    echo ""
    if [ "$({{_just}} _confirm 'Write these to /etc/nixos/local.nix? [y/N]: ')" != "true" ]; then
        echo "Aborted — nothing was changed."
        exit 0
    fi

    LOCAL="/etc/nixos/local.nix"
    OPT="vexos.network.staticWired"

    # A wrapper from before the side-file layout never loads local.nix, so
    # upgrade it first (no-op for a current wrapper).
    bash "{{justfile_directory()}}/scripts/upgrade-wrapper.sh"

    # The dotted sub-attribute lines written below would conflict with a
    # hand-written whole-attrset definition.
    if [ -f "$LOCAL" ] && grep -qE '^\s*vexos\.network\.staticWired\s*=' "$LOCAL"; then
        echo "error: $LOCAL already defines ${OPT} as a single block." >&2
        echo "       Edit it by hand there, or remove it and re-run this recipe." >&2
        exit 1
    fi

    if [ ! -f "$LOCAL" ]; then
        printf '%s\n' \
            '# /etc/nixos/local.nix' \
            '# Free-form configuration for this machine only. Loaded by /etc/nixos/flake.nix' \
            '# when present; never overwritten by the installer or updater.' \
            '{' \
            '}' | sudo tee "$LOCAL" >/dev/null
    fi

    nix_set "$LOCAL" "${OPT}.address" "\"${ADDR}\""
    nix_set "$LOCAL" "${OPT}.gateway" "\"${_gw}\""
    nix_set "$LOCAL" "${OPT}.dns"     "[ ${DNS_LIST} ]"

    for _k in address gateway dns; do
        if ! grep -qP "^\s*vexos\.network\.staticWired\.${_k}\s*=" "$LOCAL"; then
            echo "error: could not write ${OPT}.${_k} into $LOCAL — add it by hand." >&2
            exit 1
        fi
    done
    echo "✓ Wrote ${OPT} to $LOCAL"

    if ! grep -q '\./local\.nix' /etc/nixos/flake.nix 2>/dev/null; then
        echo ""
        echo "warning: /etc/nixos/flake.nix does not load local.nix yet, so the setting will"
        echo "         not apply. Run 'just update' (it patches the wrapper), then 'just rebuild'."
        exit 0
    fi

    echo ""
    echo "Note: applying a new address over SSH will drop the session."
    echo "Undo: delete the three ${OPT} lines from $LOCAL and rebuild."
    if [ "$({{_just}} _confirm 'Rebuild now to apply? [y/N]: ')" = "true" ]; then
        {{_just}} rebuild
    else
        echo "Run 'just rebuild' when ready."
    fi

# Copy your SSH key to a remote machine so future connections need no password.
# Usage:
#   just ssh                     — interactive prompts
#   just ssh nimda@10.35.1.50   — direct
[group('System Administration')]
[doc('Copy your SSH key to another machine (user@host)')]
[arg('target', pattern='|([A-Za-z0-9._-]+@)?[A-Za-z0-9][A-Za-z0-9.:-]*', help='user@host')]
ssh target="":
    #!/usr/bin/env bash
    set -euo pipefail

    TARGET={{quote(target)}}

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
