# Spec: install.sh sudo Wrapper Fix

**Feature:** `install_sudo_fix`  
**Date:** 2026-04-08  
**File:** `scripts/install.sh`  
**Status:** Ready for Implementation

---

## 1. Current State Analysis

`scripts/install.sh` is the first-boot interactive installer for vexos-nix.  
It currently has 136 lines total.

A previous fix added these two lines immediately before the `nixos-rebuild switch`
call (lines 105–108):

```
L105: # Ensure standard tools are resolvable inside the systemd-run transient unit
L106: # that nixos-rebuild switch uses for switch-to-configuration.
L107: export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
L108: sudo systemctl set-environment PATH="$PATH"
```

All subsequent `sudo` calls in the file:

| Line | Content | Kind |
|------|---------|------|
| 108  | `sudo systemctl set-environment PATH="$PATH"` | real sudo call |
| 110  | `if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then` | real sudo call |
| 119  | `      sudo reboot` | real sudo call |
| 131  | `  echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"` | **echo only — not a real call** |
| 136  | `sudo systemctl unset-environment PATH` | real sudo call |

---

## 2. Problem Definition

### Error Observed

```
sudo: /run/current-system/sw/bin/sudo must be owned by uid 0 and have the setuid bit set
sudo: /run/current-system/sw/bin/sudo must be owned by uid 0 and have the setuid bit set
✗ nixos-rebuild failed. Reboot skipped.
```

### Root Cause

NixOS implements two distinct `sudo` binaries:

| Path | Description | setuid? |
|------|-------------|---------|
| `/run/wrappers/bin/sudo` | Security wrapper — the real, working sudo | **YES** |
| `/run/current-system/sw/bin/sudo` | Symlink into the Nix store | **NO** |

The Nix store is mounted `nosuid`, so any binary resolved from it that requires
the setuid bit will immediately fail with the "must be owned by uid 0 and have
the setuid bit set" error.

Normal `$PATH` on a running NixOS system starts with `/run/wrappers/bin`, so
`command -v sudo` correctly resolves to `/run/wrappers/bin/sudo`.

However, the PATH export at line 107 **prepends** `/run/current-system/sw/bin`
before anything else — including before `/run/wrappers/bin`. After that export
takes effect, every subsequent `sudo` in the same shell resolves to the
non-setuid store copy, which fails immediately.

The `sudo systemctl set-environment` call on line 108 is the **first** call
after the PATH mutation, so it is the first to fail (explaining the two
identical error lines — systemd itself may retry the environment-set once).

---

## 3. Why the PATH Export Must Be Kept

The PATH export and the `sudo systemctl set-environment` call are correct in
purpose: they ensure that `switch-to-configuration`, which runs inside a
systemd transient unit with a minimal environment, can locate standard system
tools during `nixos-rebuild switch`. Removing the PATH export would reintroduce
the original problem it fixed. The PATH value is correct; the only issue is that
the PATH changes the shell's sudo resolution.

---

## 4. Proposed Fix

### Strategy

Capture the correct, pre-mutation sudo path into `_SUDO` **before** the PATH is
modified. Replace all real `sudo` invocations that follow the PATH export with
`"$_SUDO"`.

The `_SUDO` variable must be declared the line immediately before the comment
block (line 105), so that at capture time, `$PATH` still contains
`/run/wrappers/bin` ahead of `/run/current-system/sw/bin`.

### Exact Changes

#### Change 1 — Add `_SUDO` capture (insert before line 105)

**Insert after line 104 (the blank line), before the comment on line 105:**

```bash
_SUDO="$(command -v sudo)"
```

The surrounding context after the insertion will be:

```bash
echo ""                                                      # L103 (unchanged)
                                                             # L104 blank (unchanged)
_SUDO="$(command -v sudo)"                                   # NEW LINE
# Ensure standard tools are resolvable inside the systemd-run transient unit
# that nixos-rebuild switch uses for switch-to-configuration.
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
"$_SUDO" systemctl set-environment PATH="$PATH"
```

#### Change 2 — Line 108: replace `sudo` with `"$_SUDO"`

```diff
-sudo systemctl set-environment PATH="$PATH"
+"$_SUDO" systemctl set-environment PATH="$PATH"
```

#### Change 3 — Line 110: replace `sudo` with `"$_SUDO"`

```diff
-if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
+if "$_SUDO" nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
```

#### Change 4 — Line 119: replace `sudo reboot` with `"$_SUDO" reboot`

```diff
-      sudo reboot
+      "$_SUDO" reboot
```

#### Change 5 — Line 136: replace `sudo` with `"$_SUDO"`

```diff
-sudo systemctl unset-environment PATH
+"$_SUDO" systemctl unset-environment PATH
```

#### No change needed — Line 131

```bash
  echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"
```

This line is a plain `echo` that prints a hint string. The word `sudo` appears
only inside the quoted string; it is never executed. No change required.

---

## 5. Final State of the Affected Block (lines 103–136 after fix)

```bash
echo ""

_SUDO="$(command -v sudo)"
# Ensure standard tools are resolvable inside the systemd-run transient unit
# that nixos-rebuild switch uses for switch-to-configuration.
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
"$_SUDO" systemctl set-environment PATH="$PATH"

if "$_SUDO" nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
  echo ""
  printf "Reboot now? [y/N] "
  read -r REBOOT_CHOICE
  case "${REBOOT_CHOICE,,}" in
    y|yes)
      echo "Rebooting..."
      "$_SUDO" reboot
      ;;
    *)
      echo ""
      echo -e "${YELLOW}Skipping reboot. Log out and back in to apply session changes.${RESET}"
      echo ""
      ;;
  esac
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi

"$_SUDO" systemctl unset-environment PATH
```

---

## 6. sudo Calls Outside the PATH-Manipulation Block

There are **no** `sudo` calls before line 107 in `install.sh`. The entire sudo
usage in the file is confined to lines 108–136. All real invocations are covered
by Changes 2–5 above. No other part of the script is affected.

---

## 7. Implementation Steps

1. Open `scripts/install.sh`.
2. Insert `_SUDO="$(command -v sudo)"` on a new line immediately after the blank
   line 104 (before the `# Ensure standard tools` comment).
3. On the line `sudo systemctl set-environment PATH="$PATH"`, change `sudo` to
   `"$_SUDO"`.
4. On the line `if sudo nixos-rebuild switch`, change `sudo` to `"$_SUDO"`.
5. On the line `      sudo reboot`, change `sudo` to `"$_SUDO"`.
6. On the final line `sudo systemctl unset-environment PATH`, change `sudo` to
   `"$_SUDO"`.
7. Leave line 131 (`echo "    sudo nixos-rebuild..."`) unchanged.

---

## 8. Dependencies

No new packages, flake inputs, or NixOS options are required. This is a pure
shell-script fix.

---

## 9. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `command -v sudo` returns empty if sudo is not in PATH at all | Very Low | On any NixOS install that reached this script, sudo is always present in `/run/wrappers/bin` before PATH is altered. Script will error immediately with a clear empty-variable message rather than silently continuing. |
| Future callers add sudo calls before the capture line | Low | The `_SUDO` variable is defined at the block entrypoint; any new sudo call below it automatically benefits from the fix. |
| The PATH export might need updating in future | Possible | The `export PATH` and `systemctl set-environment` lines are unchanged; only the invocation mode for sudo changes. |

---

## 10. Verification

After implementation, a dry-run test procedure:

1. On a NixOS system, run `bash scripts/install.sh` and select a valid GPU variant.
2. Verify the script does not emit the "must have the setuid bit set" error.
3. Verify `nixos-rebuild switch` proceeds normally.
4. Optionally, add `echo "_SUDO=$_SUDO"` temporarily after the capture line to
   confirm it resolves to `/run/wrappers/bin/sudo`.
