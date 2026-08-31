# DETACH_REMOTE_STORAGE — Specification

## Phase 1: Research & Specification

### Current state analysis

`just attach-remote-storage` (justfile:1874) runs `scripts/attach-remote-storage.sh`
via the private `_run-storage-script` helper. That script:

- Prompts for protocol / server / export / mountpoint (default `/mnt/nas-<export>`).
- For CIFS, writes a credentials file to
  `/etc/nixos/secrets/remote-<basename(mnt)>-credentials` (0600 root:root).
- Optionally does a throwaway test mount under `/tmp` (self-cleaning).
- **Step [6/6]** writes/updates `/etc/nixos/storage-remote.nix`, preserving any
  existing entries between the markers:
  - `# >>> vexos-remote-entries >>>`
  - `# <<< vexos-remote-entries <<<`
  Each entry is a single line:
  `{ type = "nfs"; server = "..."; export = "..."; mountPoint = "..."; }` or
  `{ type = "cifs"; ...; mountPoint = "..."; credentialsFile = "..."; }`
  Before overwriting, it copies the file to `storage-remote.nix.bak`.

`flake.nix:175` imports that file only when it exists:
`let p = /etc/nixos/storage-remote.nix; in if builtins.pathExists p then [ p ] else []`

`modules/storage-remote.nix` turns each entry into a `fileSystems.<mountPoint>`
attribute with `_netdev,nofail,x-systemd.automount` options. `config` is guarded
by `lib.mkIf (cfg != [ ])` — an empty list is inert.

The role guard `_require-remote-storage-role` (justfile:1610) allows
`*desktop*|*htpc*|*server*` variants.

**There is currently no way to remove an attached share except hand-editing the
generated file.**

### Problem definition

Provide `just detach-remote-storage` — an interactive companion to
`attach-remote-storage` that removes one (or all) remote share entries from
`/etc/nixos/storage-remote.nix`, unmounts the live mount, removes the now-empty
mountpoint directory, and cleans up an orphaned CIFS credentials file. It must
not apply the configuration itself (prints `just rebuild` reminder, matching
attach).

### Proposed solution architecture

Two additions, no new dependencies:

1. **`scripts/detach-remote-storage.sh`** — new, executable, same house style as
   `attach-remote-storage.sh` (same color/`die`/`ok`/`warn`/`hdr` helpers,
   `set -uo pipefail`, root precondition).

2. **justfile recipe** `detach-remote-storage` under
   `[group('System Administration')]`, guarded by `_require-remote-storage-role`,
   body `@just _run-storage-script detach-remote-storage.sh` — exactly mirroring
   `attach-remote-storage` (justfile:1873-1875). Plus one help line in the
   server-role addendum block (justfile:23) mirroring the attach line.

#### Script behaviour (`scripts/detach-remote-storage.sh`)

```
[1/5] Preconditions
  - must be root (die otherwise, tell user to use `just detach-remote-storage`)
  - REMOTE_NIX=/etc/nixos/storage-remote.nix must exist; if not:
      ok "no remote shares configured — nothing to detach"; exit 0

[2/5] Parse entries
  - Extract the lines between BEGIN_MARK/END_MARK (same awk as attach).
  - If zero entries: report the file has no managed entries, offer to delete the
    now-pointless file, exit.
  - For each entry, parse mountPoint (and type, server, export, credentialsFile)
    with sed/grep field extraction — the entries are single-line and
    script-generated so a simple `grep -oP 'mountPoint = "\K[^"]+'` is safe.

[3/5] Selection (interactive menu)
  - Numbered list of entries: "<n>) <type>  <server>:<export>  →  <mountPoint>"
  - Extra option: "a) detach ALL"
  - Read choice; validate. (No argument form — matches attach's all-interactive
    style and the answers on file.)

[4/5] Confirmation + live cleanup (per selected entry)
  - Show what will happen, prompt [y/N].
  - If `mountpoint -q "$MNT"`: `umount "$MNT"` (try lazy `umount -l` as fallback
    on EBUSY, with a warning naming the mountpoint). Also stop the transient
    automount unit if present:
    `systemctl stop "$(systemd-escape -p --suffix=automount "$MNT")" 2>/dev/null || true`
  - If the mountpoint dir exists, is a directory, and is empty: `rmdir "$MNT"`
    (warn, don't fail, if non-empty or missing).
  - CIFS creds: if entry has credentialsFile AND no *remaining* entry references
    the same path, `rm -f "$CRED_FILE"` and report; otherwise keep it and say why.

[5/5] Rewrite storage-remote.nix
  - `cp -a` to storage-remote.nix.bak first (same as attach).
  - Rebuild the file with the same header/skeleton attach uses, writing back the
    entries NOT selected for removal.
  - If no entries remain: still write a valid file with an empty managed block
    (keeps `vexos.storage.remote = [ ];` — inert, evaluates cleanly on every
    supported role). Then additionally offer: "No shares remain. Remove
    /etc/nixos/storage-remote.nix entirely? [y/N]" — if yes, `rm -f` it and its
    `.bak`. (Removing the file is safe: flake.nix:175 pathExists guard.)
  - Print the same apply reminder attach uses:
      "Apply with:  just rebuild"
      note that NixOS regenerates /etc/fstab and drops the mount unit on rebuild.
  - ok "done"
```

#### Why interactive menu + full cleanup + prompt-only (not auto-rebuild)

Locked by the user's answers on file:
- Interactive menu — consistent with `attach-remote-storage`.
- Full cleanup — unmount, rmdir, orphaned-creds removal.
- Prompt only — never invoke `just rebuild` from the script; `nixos-rebuild
  switch` is a live-system op and is in FORBIDDEN COMMANDS as a
  Claude-initiated action. The recipe just edits declarative state.

### Implementation steps (Option B module pattern)

This change is **script + justfile only** — it does not touch
`modules/storage-remote.nix` or any `configuration-*.nix`, so the Module
Architecture Pattern (Option B) is not affected. No new `lib.mkIf`, no new
module files. The generated `/etc/nixos/storage-remote.nix` is host state, not
tracked config.

1. Create `scripts/detach-remote-storage.sh` per the behaviour spec above.
   `chmod +x`.
2. Add the `detach-remote-storage` recipe to `justfile` immediately after
   `attach-remote-storage` (justfile:1875), same group + guard.
3. Add one help line to the server-role addendum block (justfile:23):
   `echo "    detach-remote-storage      Remove a remote NFS/SMB storage pool attached earlier (interactive)"`
4. Update the doc comment above the recipe pair if needed (attach's comment at
   justfile:1869-1872 can gain a sibling sentence — keep surgical).

### Dependencies

None. Uses only coreutils, `mount`/`umount`/`mountpoint`, `systemctl`,
`systemd-escape`, `awk`, `grep`, `sed` — all already required by
`attach-remote-storage.sh` / present on every NixOS host. No Context7 lookup
required (no external library, no versioned API).

### Configuration changes

None to tracked files. Runtime effect: `/etc/nixos/storage-remote.nix` shrinks
or is deleted; `/etc/nixos/storage-remote.nix.bak` is refreshed;
possibly one file under `/etc/nixos/secrets/` is removed.

### Risks and mitigations

| Risk | Mitigation |
|------|------------|
| `umount` fails (share busy) | Warn, try `umount -l`, continue with config edit; user re-runs after closing consumers. Rebuild will drop the unit regardless. |
| `rmdir` removes a dir the user cared about | Only `rmdir` (never `rm -rf`), only when empty, only the exact `mountPoint` string from the entry. Non-empty ⇒ warn + skip. |
| Deleting a shared creds file still used by another entry | Check all *remaining* entries for the same `credentialsFile` path before `rm`. |
| Parsing malformed hand-edited entries | Entries are script-generated single lines; if `mountPoint` can't be parsed for a line, skip it with a warning and leave it in the file. |
| Removing `storage-remote.nix` while flake still references it | `flake.nix:175` already guards with `builtins.pathExists`; empty-list file also evaluates fine. |
| Role without the module (stateless/vanilla) | `_require-remote-storage-role` guard already blocks these. |
| Preflight shellcheck | Preflight does not shellcheck `scripts/*.sh` (only `pkgs/vexos-update`), but write clean, quoted, `set -uo pipefail` bash anyway. |

### Build validation plan (Phase 3)

- `nix flake show --impure` — structure unchanged (no new outputs).
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` (current variant),
  plus `.#vexos-desktop-amd`, `.#vexos-desktop-vm`.
- No server/stateless/htpc module files touched ⇒ extended dry-build matrix not
  required, but `.#vexos-htpc-amd` and `.#vexos-server-amd` are cheap sanity
  checks since those roles also expose the recipe.
- `git ls-files hardware-configuration.nix` empty.
- `system.stateVersion` unchanged (no `configuration-*.nix` touched).
- No new flake inputs.
- `bash -n scripts/detach-remote-storage.sh` (syntax) and a `shellcheck` pass if
  available.
- `bash scripts/preflight.sh` in Phase 6.
