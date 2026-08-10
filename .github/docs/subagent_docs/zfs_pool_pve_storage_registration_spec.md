# Specification — Fix Proxmox storage.cfg registration detection in create-zfs-pool.sh

## Current State Analysis

`scripts/create-zfs-pool.sh` (lines 310-336) gates whether it registers the newly
created ZFS pool as Proxmox VM storage on:
```bash
PVE_STOR_CFG="/etc/pve/storage.cfg"
if [ -f "$PVE_STOR_CFG" ]; then
    ... write zfspool stanza via tee -a ...
else
    warn "$PVE_STOR_CFG not found — not running on a Proxmox VE host"
    echo "  Register manually in the Proxmox web UI: ..."
fi
```

Reproduced live on host `vexmox` (`vexos-server-*`, `proxmox-nixos` / `services.proxmox-ve`):
- `pve-cluster.service` was active and healthy the whole time.
- `mount | grep pve` confirms `/dev/fuse on /etc/pve type fuse ...` — pmxcfs correctly
  mounted.
- `ls -la /etc/pve` shows a fully populated cluster filesystem (`authkey.pub`, `nodes/`,
  `priv/`, `.version`, etc.) — but **no `storage.cfg`**.
- `sudo pvesm status` works fine and shows only the implicit default `local` storage.

On real Debian-based Proxmox VE, `/etc/pve/storage.cfg` is created by the `.deb`
package's postinstall script at install time (seeded with `local`/`local-lvm` stanzas).
`proxmox-nixos` (the NixOS packaging used by this project, per
`modules/server/proxmox.nix`) does not replicate that postinstall step, so
`storage.cfg` simply never exists as a file until something explicitly creates it —
even though Proxmox itself is fully functional and `/etc/pve` is writable.

Because the script's detection condition tests file *existence* rather than whether
Proxmox is actually running, it always takes the "not running on a Proxmox VE host"
branch on this project's proxmox-nixos-based hosts, even though it's the intended,
primary target platform for this exact script. `tee -a` would have created the file
fine had the script attempted the write — the bug is purely in the gate, not the write
logic.

## Problem Definition

The registration step never fires on the primary supported platform
(`proxmox-nixos`/NixOS-based Proxmox VE), silently downgrading every pool creation to
"print manual instructions" instead of actually registering the storage — with no
functional difference from running on a genuinely non-Proxmox host, misleading the
operator about the true cause via the "not running on a Proxmox VE host" message.

## Proposed Solution

Replace the file-existence check with a check for a live, mounted Proxmox cluster
filesystem plus the `pvesm` binary — the actual precondition the write step needs —
using `mountpoint -q /etc/pve` (util-linux, already an implicit dependency of this
script via `wipefs`) combined with `command -v pvesm`. `tee -a` already creates
`storage.cfg` if it doesn't exist, so no other change to the write path is needed.

```bash
if command -v pvesm >/dev/null 2>&1 && mountpoint -q /etc/pve; then
    printf "Proxmox storage ID [vm-store]: "
    read -r STOR_ID
    STOR_ID="${STOR_ID:-vm-store}"
    if grep -qE "^zfspool:[[:space:]]*${STOR_ID}[[:space:]]*$" "$PVE_STOR_CFG" 2>/dev/null; then
        warn "storage ID '$STOR_ID' already exists in $PVE_STOR_CFG — skipping"
    else
        printf '\nzfspool: %s\n\tpool %s\n\tcontent images,rootdir\n\tsparse 1\n' \
            "$STOR_ID" "$PVE_TARGET" | tee -a "$PVE_STOR_CFG" >/dev/null
        ok "storage '$STOR_ID' added to $PVE_STOR_CFG (pool: $PVE_TARGET)"
        pvesm status >/dev/null 2>&1 && ok "pvesm reloaded" || true
    fi
else
    warn "pvesm not found or /etc/pve is not a mounted Proxmox cluster filesystem"
    echo "  Register manually in the Proxmox web UI:"
    echo "    Datacenter → Storage → Add → ZFS"
    echo "      ID:      vm-store"
    echo "      Pool:    $PVE_TARGET"
    echo "      Content: Disk image, Container"
    echo "      Thin provision: enabled"
fi
```
(The `grep -qE ... "$PVE_STOR_CFG" 2>/dev/null` already tolerates a not-yet-existing
file — it simply finds no match and falls through to the write branch, which is the
desired behavior on first run.)

## Implementation Steps

1. Edit `scripts/create-zfs-pool.sh`: replace the `[ -f "$PVE_STOR_CFG" ]` condition
   with `command -v pvesm >/dev/null 2>&1 && mountpoint -q /etc/pve`, and update the
   `else` branch's warning message to reflect the new, more accurate detection
   criterion. No other lines in this block change.

## Dependencies

None. `mountpoint` ships in `util-linux`, already present in `environment.systemPackages`
via `modules/zfs-server.nix` (`util-linux` — wipefs, lsblk).

## Configuration Changes

None — this is a detection-logic fix within an existing script, no module/option
surface changes.

## Risks and Mitigations

- **Risk:** `mountpoint -q /etc/pve` could return true in some edge case where `/etc/pve`
  is mounted but `pve-cluster` is unhealthy/read-only.
  **Mitigation:** Combined with `command -v pvesm` and the existing `tee -a` write,
  which will simply fail loudly (non-fatal under `set -uo pipefail`, no `-e`) if the
  filesystem truly isn't writable — no worse than today's behavior, and strictly better
  than today's guaranteed-skip on the primary supported platform.
- **Risk:** On a genuinely non-Proxmox host (no `pve-cluster`, no `/etc/pve` mount), the
  new condition correctly still falls to the manual-instructions branch — behavior
  preserved for that case.
- **Risk:** This does not retroactively fix `vexmox`'s already-existing `tank` pool.
  **Mitigation:** Out of scope for this code change — the user already has the manual
  `pvesm add zfspool` command to run once; only future pool creations benefit
  automatically.
