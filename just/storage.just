# just/storage.just — Remote NFS/SMB shares and local ZFS / mergerfs pools (scripts/*.sh).
# Imported by the root justfile; recipe names share one namespace.

# Remote storage: attach, detach or list NFS/SMB shares from another host (apply with `just rebuild`).
[group('Storage')]
[doc('Attach, detach or list NFS/SMB shares from another host (menu)')]
remote-storage action="" *args: _require-remote-storage-role
    @{{_just}} _menu remote-storage "Remote storage (NFS / SMB)" {{quote(action)}} {{quote(args)}} \
        "attach|Mount a share exported by another host" \
        "detach|Remove a share attached earlier||warn" \
        "list|Show the shares already attached and their status||stay"

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

# Locate a script under scripts/ (walking up from $PWD, then known checkout
# locations, then the nix-store flake input) and run it as root. Shared by the
# storage-pool recipes below. Extra arguments are passed to the script.
# Arguments arrive positionally ($1 = script, the rest forwarded as-is) so a
# multi-word argument reaches the script intact rather than being re-split.
[positional-arguments]
[private]
_run-storage-script script *args:
    #!/usr/bin/env bash
    set -euo pipefail
    SCRIPT_NAME="$1"
    shift
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
    sudo bash "$SCRIPT" "$@"

# Menu for managing ZFS pools on a server role: show pool health, create a pool,
# destroy a pool (also removes its Proxmox storage entry and boot-time import),
# import an existing pool, replace a disk, add disks, attach/detach mirror disks,
# scrub, and clear errors. "Create" launches scripts/create-zfs-pool.sh.
# Requires modules/zfs-server.nix in the active build. Destructive actions require
# typing the pool name; safe to abort with Ctrl-C at any prompt.
# Usage: just zfs-pool            — menu
#        just zfs-pool status     — run one action (status, create, destroy, import,
#                                   replace, add, attach, detach, scrub, clear)
[group('Storage')]
[doc('ZFS pools: create, import, replace disks, scrub (menu)')]
[positional-arguments]
zfs-pool *args: _require-server-role
    @{{_just}} _run-storage-script zfs-pool.sh "$@"

# Menu for managing the mergerfs + SnapRAID "bulk" storage pool (media / general
# bulk storage on mixed-capacity drives). Server roles only: show pool status,
# create the pool, add or remove a disk, destroy the pool, and run the SnapRAID
# parity sync/scrub. "Create" launches scripts/create-mergerfs-pool.sh.
# Needs vexos.server.nas.backend = "mergerfs" (or vexos.server.storage.mergerfs.enable)
# so the mergerfs userland is present. Destructive actions require typed confirmation.
# Usage: just mergerfs-pool           — menu
#        just mergerfs-pool status    — run one action (status, create, add, remove,
#                                       destroy, sync, scrub)
[group('Storage')]
[doc('mergerfs + SnapRAID pool: create, add/remove disks, sync (menu)')]
[positional-arguments]
mergerfs-pool *args: _require-server-role
    @{{_just}} _run-storage-script mergerfs-pool.sh "$@"

# Attach a NAS share exported by ANOTHER host (NFS or CIFS/SMB) declaratively,
# without hand-editing /etc/fstab. Available on desktop, htpc, server and
# headless-server. Non-destructive — client mount only. Writes/updates a
# declarative /etc/nixos/storage-remote.nix; apply with `just rebuild`.
[private]
_remote-storage-attach: _require-remote-storage-role
    @{{_just}} _run-storage-script attach-remote-storage.sh

# Detach a NAS share attached earlier by `just remote-storage attach`. Interactive:
# lists the configured shares, removes the selected entry (or all) from the
# declarative /etc/nixos/storage-remote.nix, unmounts it, removes the empty
# mountpoint, and drops an orphaned CIFS credentials file. Applies nothing —
# apply with `just rebuild`.
[private]
_remote-storage-detach: _require-remote-storage-role
    @{{_just}} _run-storage-script detach-remote-storage.sh

# List the shares attached by `just remote-storage attach`: protocol, server:share,
# mountpoint, live mount status and write group. Read-only — never mounts anything.
[private]
_remote-storage-list: _require-remote-storage-role
    @{{_just}} _run-storage-script list-remote-storage.sh
