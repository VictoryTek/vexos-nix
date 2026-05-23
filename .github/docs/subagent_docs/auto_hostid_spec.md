# Spec: Fix `networking.hostId` — Revert Impure `builtins.readFile` to Static Placeholder

**Feature:** `auto_hostid` (revision 2 — fixes broken impure implementation)
**Date:** 2026-05-23
**Status:** Ready for implementation

---

## 1. Root Cause

`template/etc-nixos-flake.nix` (line 125) currently contains:

```nix
    hostModule = { ... }: {
      networking.hostId = builtins.substring 0 8 (builtins.readFile /etc/machine-id);
    };
```

`nixos-rebuild` evaluates flakes in **pure evaluation mode by default** (introduced in
Nix 2.4+). In pure mode, absolute path reads outside the Nix store are forbidden:

```
error: access to absolute path '/etc' is forbidden in pure evaluation mode
```

This error is thrown at evaluation time — before any build begins — which means
`nixos-rebuild switch` completely fails for all users of this template.

### Why it was believed to work

The previous spec (revision 1) incorrectly stated:
> `nixos-rebuild` does not pass `--pure-eval`. Impure file reads from absolute paths
> outside the store are permitted by default.

This was wrong. Nix 2.4+ made pure eval the default for flakes. `nixos-rebuild switch`
does not pass `--impure`, so the `builtins.readFile /etc/machine-id` call is always
rejected at eval time on any modern NixOS installation.

---

## 2. Solution

Two-part fix:

1. **Revert `template/etc-nixos-flake.nix`** — restore the static `"XXXXXXXX"`
   placeholder that was present before revision 1.

2. **Extend `scripts/install.sh`** — insert a `sed` substitution immediately
   **after** the ASUS hardware patch block and **before** the `nixos-rebuild` call.
   The substitution replaces `"XXXXXXXX"` with the first 8 hex characters of
   `/etc/machine-id` at install time, in the shell (not in Nix), where file reads are
   always valid.

This approach:
- Keeps Nix evaluation 100% pure (no impure file reads in `.nix` files)
- Requires zero manual steps from the user (the installer handles it)
- Is safe for all roles — the substitution is a no-op if the placeholder is absent
  or already replaced

---

## 3. Files Changed

| File | Change |
|------|--------|
| `template/etc-nixos-flake.nix` | Revert line 125: replace impure expression with `"XXXXXXXX"` literal |
| `scripts/install.sh` | Insert hostId substitution block between ASUS patch and build call |

---

## 4. Exact Changes

### 4.1 `template/etc-nixos-flake.nix`

**Location:** Lines 118–128 (the `hostModule` block and its preceding comment)

**Current (broken):**
```nix
    # ── ZFS host identity (required for server and headless-server roles) ────
    # ZFS bakes this ID into every pool's vdev label at creation time.
    # It must be unique per machine and must not change after pools are created.
    #
    hostModule = { ... }: {
      networking.hostId = builtins.substring 0 8 (builtins.readFile /etc/machine-id);
    };
```

**New (fixed):**
```nix
    # ── ZFS host identity (required for server and headless-server roles) ────
    # ZFS bakes this ID into every pool's vdev label at creation time.
    # It must be unique per machine and must not change after pools are created.
    #
    # Substituted automatically by scripts/install.sh at install time.
    # To set manually: replace XXXXXXXX with: head -c 8 /etc/machine-id
    hostModule = { ... }: {
      networking.hostId = "XXXXXXXX";
    };
```

**Key change:** `builtins.substring 0 8 (builtins.readFile /etc/machine-id)`
→ `"XXXXXXXX"`

The comment is also updated to document that install.sh handles the substitution,
and to retain the manual fallback instruction.

---

### 4.2 `scripts/install.sh`

**Insertion point:** After line 321 (closing `fi` of the ASUS hardware patch block),
before line 322 (`# ---------- Build & switch`).

**Lines for context (current):**

```bash
  fi
fi

# ---------- Build & switch ---------------------------------------------------
if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "/etc/nixos#${FLAKE_TARGET}"; then
```

**New block to insert** (between the ASUS `fi` and the build comment):

```bash
# ---------- hostId substitution ----------------------------------------------
# Replace the XXXXXXXX placeholder in /etc/nixos/flake.nix with the first 8 hex
# characters of /etc/machine-id. Required for ZFS pool identity on server and
# headless-server roles. Safe no-op for all other roles.
if [ -f /etc/nixos/flake.nix ] && grep -qF '"XXXXXXXX"' /etc/nixos/flake.nix 2>/dev/null; then
  HOST_ID="$(head -c 8 /etc/machine-id)"
  sed -i "s/networking\\.hostId = \"XXXXXXXX\"/networking.hostId = \"${HOST_ID}\"/" /etc/nixos/flake.nix
  echo -e "  ${GREEN}✓ hostId set to ${HOST_ID}.${RESET}"
fi

```

**After insertion, the surrounding code reads:**

```bash
  fi
fi

# ---------- hostId substitution ----------------------------------------------
# Replace the XXXXXXXX placeholder in /etc/nixos/flake.nix with the first 8 hex
# characters of /etc/machine-id. Required for ZFS pool identity on server and
# headless-server roles. Safe no-op for all other roles.
if [ -f /etc/nixos/flake.nix ] && grep -qF '"XXXXXXXX"' /etc/nixos/flake.nix 2>/dev/null; then
  HOST_ID="$(head -c 8 /etc/machine-id)"
  sed -i "s/networking\\.hostId = \"XXXXXXXX\"/networking.hostId = \"${HOST_ID}\"/" /etc/nixos/flake.nix
  echo -e "  ${GREEN}✓ hostId set to ${HOST_ID}.${RESET}"
fi

# ---------- Build & switch ---------------------------------------------------
if sudo nixos-rebuild "${REBUILD_ACTION}" --flake "/etc/nixos#${FLAKE_TARGET}"; then
```

#### Bash snippet details

| Element | Value | Rationale |
|---------|-------|-----------|
| Guard: file exists | `[ -f /etc/nixos/flake.nix ]` | Defensive check; skips if not present |
| Guard: placeholder present | `grep -qF '"XXXXXXXX"'` | Idempotent — skips if already substituted |
| Machine-id extraction | `head -c 8 /etc/machine-id` | Reads exactly 8 bytes (no trailing newline issue) |
| sed pattern | `networking\\.hostId = \"XXXXXXXX\"` | Escapes `.` and `"` for ERE safety in double-quoted sed |
| sed replacement | `networking.hostId = \"${HOST_ID}\"` | Injects the real 8-char hex value |
| Scope | All roles | `hostModule` is included in server/headless-server modules list; harmless for others |

---

## 5. Implementation Steps

1. Edit `template/etc-nixos-flake.nix` line 125:
   - Replace the entire `networking.hostId = builtins.substring ...` expression with
     `networking.hostId = "XXXXXXXX";`
   - Update the comment block above `hostModule` as shown in §4.1

2. Edit `scripts/install.sh`:
   - Locate the closing `fi` of the ASUS hardware patch block (line 321)
   - Insert the 8-line hostId substitution block immediately after it (before line 322)
   - Exact insertion shown in §4.2

3. Validate:
   - `nix flake show` — must pass (pure eval, no builtins.readFile errors)
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — must pass
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — must pass
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — must pass

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Installer run without `/etc/nixos/flake.nix` present | Low | Guard `[ -f /etc/nixos/flake.nix ]` makes it a silent no-op |
| Placeholder already replaced by manual user edit | Possible | `grep -qF '"XXXXXXXX"'` guard makes substitution idempotent |
| `sed` escaping issue in pattern | Minimal | `\\.` escapes the dot; double-quote escaping verified for bash |
| `head -c 8` produces fewer than 8 bytes | Cannot happen | `/etc/machine-id` is always a 32-char hex string per systemd spec |
| hostId not needed for non-ZFS roles | N/A | Setting hostId for desktop/htpc/stateless is harmless; it's a valid NixOS option |

---

## 7. Sources Consulted

1. `template/etc-nixos-flake.nix` — full read, confirmed line 125 has impure expression
2. `scripts/install.sh` — full read, identified ASUS patch block (lines 305–321) as insertion point; confirmed build call at line 323
3. NixOS manual — Pure evaluation mode default for flakes (Nix 2.4+ behaviour)
4. `builtins.readFile` NixOS/Nix documentation — absolute paths outside store are blocked in pure mode
5. systemd `machine-id` specification — always 32 lowercase hex chars + newline
6. `modules/zfs-server.nix` — `networking.hostId` assertion and comment context
7. Bash `sed -i` manual — escaping rules for in-place substitution
