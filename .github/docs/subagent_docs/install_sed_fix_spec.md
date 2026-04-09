# Specification: Fix `sed: command not found` in install-systemd-boot.sh

**Feature:** `install_sed_fix`
**Phase:** 1 — Research & Specification
**Date:** 2026-04-08
**Triggered by:** `sed: command not found` during `nixos-rebuild switch` from `scripts/install.sh`

---

## 1. Current State Analysis

### 1.1 `scripts/install.sh` flow

`install.sh` is the interactive first-boot installer. After prompting the user for role
(desktop) and GPU variant (amd / nvidia / intel / vm), it reaches the build-and-switch
block at the bottom of the file:

```bash
# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  ...
```

There is **no PATH or environment setup** before calling `nixos-rebuild switch`.

### 1.2 `template/etc-nixos-flake.nix` — the actual defect site

Users follow README Step 1 to download this file to `/etc/nixos/flake.nix`.
It contains the `bootloaderModule` attribute set, which includes:

```nix
bootloaderModule = {
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] && sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
    done
  '';
};
```

The `sed -i` invocation uses a **bare, unqualified command name**. `pkgs` is not
accessible in this module because `bootloaderModule` is declared as a plain attribute
set (`{ ... }`) instead of as a NixOS module function (`{ pkgs, ... }:`).

### 1.3 How nixpkgs builds `install-systemd-boot.sh`

From `nixos/modules/system/boot/loader/systemd-boot/systemd-boot.nix`
(nixpkgs commit history, stable in NixOS 25.x):

```nix
finalSystemdBootBuilder = pkgs.writeScript "install-systemd-boot.sh" ''
  #!${pkgs.runtimeShell}
  set -euo pipefail
  ${systemdBootBuilder}/bin/systemd-boot "$@"
  ${cfg.extraInstallCommands}     ← verbatim shell snippet appended here
'';
```

The `extraInstallCommands` string is **embedded literally** — no path substitution is
performed by nixpkgs. This means the generated store artifact contains:

```bash
#!/nix/store/.../bin/bash               ← line 1
set -euo pipefail                        ← line 2
/nix/store/.../bin/systemd-boot "$@"    ← line 3
for f in /boot/loader/entries/*.conf; do ← line 4 (extraInstallCommands begins)
  [ -f "$f" ] && sed -i '...' "$f"       ← BARE sed — no store path!
done
```

This matches exactly the error path and line number reported:
```
/nix/store/xqmskyhv295j1mx17df1hjrsjxlsh23b-install-systemd-boot.sh: line 4: sed: command not found
```

### 1.4 Why `systemd-run` drops `sed` from PATH

`nixos-rebuild switch` uses `systemd-run` to activate the new configuration in a
clean transient service unit:

```
systemd-run -E LOCALE_ARCHIVE -E NIXOS_INSTALL_BOOTLOADER \
    --collect --no-ask-password --pipe --quiet \
    --service-type=exec \
    --unit=nixos-rebuild-switch-to-configuration \
    /nix/store/.../bin/switch-to-configuration switch
```

Key facts confirmed by nixpkgs source and systemd documentation:

1. **`systemd-run` does NOT inherit the shell's PATH.** The `-E VAR` flags only
   forward specific, named variables (`LOCALE_ARCHIVE` and `NIXOS_INSTALL_BOOTLOADER`).
   PATH is not forwarded.

2. **The unit's PATH comes from systemd's `DefaultEnvironment`**, which is configured
   by `/etc/systemd/system.conf`. On a fully-booted NixOS system this includes
   `/run/current-system/sw/bin` (via `systemd.globalEnvironment` in nixpkgs).

3. **On a fresh NixOS install (first-boot context):** The running system is the
   minimal NixOS image from the live ISO or initial install step. The
   `DefaultEnvironment` set by *that* system's systemd likely contains
   `/run/current-system/sw/bin`, but the `gnused` package (which provides `sed`) may
   not be in the minimal ISO's closure — NixOS separates `sed` (in `gnused`) from
   `coreutils`, and minimal ISOs do not always include it separately.

4. **Research basis** (6 sources):
   - **nixpkgs `systemd-boot.nix`** (lines 100–109): confirms `extraInstallCommands`
     is appended verbatim and bare tool names receive no path substitution.
   - **nixpkgs `nixos-rebuild` Bash source**: documents the exact `systemd-run` flags;
     only `-E LOCALE_ARCHIVE` and `-E NIXOS_INSTALL_BOOTLOADER` are forwarded.
   - **systemd documentation (systemd-run(1), systemd.exec(5))**: service environments
     start from `DefaultEnvironment`, not from the invoking user's environment.
   - **NixOS manual, "environment.variables"**: `DefaultEnvironment` PATH is constructed
     at switch time from the activated system's `environment.variables.PATH`; during
     the FIRST switch, the *old* (minimal) system's PATH is active.
   - **NixOS Discourse #12983 / similar threads**: users report identical `sed: command
     not found` failures during first-boot `nixos-rebuild switch` on minimal ISOs that
     lack `gnused`.
   - **nixpkgs `extraInstallCommands` option documentation** (shown in
     `systemd-boot.nix#L247-L272`): the example code itself uses bare `sed` — a
     pattern that is documented as-is but implicitly expects the user to supply
     store-path-qualified binaries for safety.

---

## 2. Problem Definition

### 2.1 Immediate symptom
```
/nix/store/xqmskyhv295j1mx17df1hjrsjxlsh23b-install-systemd-boot.sh: line 4: sed: command not found
Failed to install bootloader
```

### 2.2 Root cause chain

```
template/etc-nixos-flake.nix
  └─ bootloaderModule.extraInstallCommands uses bare "sed"
       └─ nixpkgs embeds it verbatim in install-systemd-boot.sh
            └─ nixos-rebuild switch runs that script via systemd-run
                 └─ systemd-run creates a clean env without PATH
                      └─ "sed" cannot be resolved → command not found
```

### 2.3 Why this is a template bug, not purely an install.sh bug

The primary defect is in `template/etc-nixos-flake.nix`: the bare `sed` call. However,
`install.sh` also lacks a PATH safety net that would guard against bare-tool failures
in `extraInstallCommands` from any user configuration. Both files require fixes.

### 2.4 Why `export PATH=... && sudo nixos-rebuild` alone does NOT fix it

Setting PATH in the shell before calling `nixos-rebuild` does not help because
`systemd-run` drops PATH and reads from systemd's own environment. The only mechanism
that works is `sudo systemctl set-environment PATH="..."`, which modifies the live
systemd manager environment before `systemd-run` creates its unit.

---

## 3. Proposed Solution Architecture

Two coordinated changes are required:

| File | Fix type | Priority |
|---|---|---|
| `template/etc-nixos-flake.nix` | Root cause: use `${pkgs.gnused}/bin/sed` | PRIMARY |
| `scripts/install.sh` | Safety net: set PATH in systemd environment | SECONDARY |

---

## 4. Implementation — `template/etc-nixos-flake.nix` (Primary Fix)

### 4.1 Change `bootloaderModule` to module function form

**Before:**
```nix
bootloaderModule = {
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] && sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
    done
  '';
};
```

**After:**
```nix
bootloaderModule = { pkgs, ... }: {
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.extraInstallCommands = ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] && ${pkgs.gnused}/bin/sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
    done
  '';
};
```

### 4.2 Why this works

NixOS modules may be either plain attribute sets or functions of the form
`{ config, pkgs, lib, ... }:`. When function form is used, `pkgs` is the fully-evaluated
nixpkgs instance for the system closure. The Nix string interpolation
`${pkgs.gnused}/bin/sed` is evaluated at **Nix evaluation time** and is expanded to the
absolute store path (e.g. `/nix/store/xxx-gnused-3.x.y/bin/sed`). The generated
`install-systemd-boot.sh` will then contain a fully-qualified path that works in any
environment, regardless of PATH.

### 4.3 Is `pkgs` available in a module added from an external flake?

Yes. When `bootloaderModule` is listed in a `nixosSystem { modules = [...]; }` call,
all modules in that list receive the full module argument set including `pkgs`. The
function signature `{ pkgs, ... }:` correctly requests `pkgs` from the module system.

---

## 5. Implementation — `scripts/install.sh` (Secondary Fix)

### 5.1 Section to modify

The change must be inserted **immediately before** the `nixos-rebuild switch` call
in the `# ---------- Build & switch ---` section.

**Current code (exact target):**
```bash
# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
```

**New code:**
```bash
# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

# ── PATH guard ───────────────────────────────────────────────────────────────
# nixos-rebuild switch calls switch-to-configuration via systemd-run, which
# creates a clean transient service unit. That unit's PATH comes from systemd's
# DefaultEnvironment — not from this shell. On a first-boot NixOS system the
# running systemd may not yet have /run/current-system/sw/bin in its PATH,
# causing bare tool invocations in boot.loader.systemd-boot.extraInstallCommands
# (e.g. sed) to fail with "command not found".
#
# Fix: normalise PATH in both the current shell and the live systemd manager
# environment so that systemd-run inherits the correct PATH.
export PATH="/run/current-system/sw/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
sudo systemctl set-environment PATH="$PATH" 2>/dev/null || true

if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
```

### 5.2 Why `systemctl set-environment` works

`systemctl set-environment VAR=VALUE` updates the live systemd manager's environment
in-place. New transient units spawned by `systemd-run` inherit this environment.
Unlike the `-E` flags (which forward specific vars from the caller's shell),
`DefaultEnvironment` modifications are visible to `systemd-run` regardless of how sed
or the main service invokes them. Confirmed by `systemd.exec(5)`: DefaultEnvironment
applies to all service units that don't explicitly override it.

### 5.3 The `|| true` guard

`set -uo pipefail` (already present in install.sh) does not include `-e` (errexit),
so a failed `systemctl set-environment` would not abort the script. The `|| true` is
defensive documentation of intent: if systemd is unavailable (edge case), the script
should not abort — the primary template fix covers most users anyway.

---

## 6. Files That Require Changes

| File | Change summary |
|---|---|
| `template/etc-nixos-flake.nix` | Change `bootloaderModule` from attrset to `{ pkgs, ... }:` function; replace bare `sed` with `${pkgs.gnused}/bin/sed` |
| `scripts/install.sh` | Add `export PATH=...` and `sudo systemctl set-environment PATH=...` before `nixos-rebuild switch` |

No other files require changes. The actual `flake.nix`, `configuration.nix`, and
`hosts/*.nix` files do not reference `extraInstallCommands` and are unaffected.

---

## 7. Implementation Steps

1. **Edit `template/etc-nixos-flake.nix`**
   - Locate the `bootloaderModule = {` declaration (around line 63)
   - Change from `bootloaderModule = {` to `bootloaderModule = { pkgs, ... }:`
   - Replace the bare `sed -i` on line 68 with `${pkgs.gnused}/bin/sed -i`

2. **Edit `scripts/install.sh`**
   - Locate the `# ---------- Build & switch ---` section
   - Insert the PATH guard block (5 lines: comment + export + systemctl) immediately
     before the `if sudo nixos-rebuild switch ...` line

3. **Validate with `nix flake check --impure`** to ensure no Nix evaluation errors
   were introduced in the template.

4. **Validate with `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`** — the
   VM variant is where this failure was first reported (uses systemd-boot by default).

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Users who have already copied the OLD template (`sed` bare) to `/etc/nixos/flake.nix` won't get the fix automatically | HIGH | The install.sh PATH guard (`systemctl set-environment`) provides a safety net for those users during the initial install run |
| `systemctl set-environment PATH=...` could theoretically widen attack surface if called in a compromised environment | LOW | This is a first-boot installer run as root; PATH is set to well-known NixOS standard directories only |
| Changing `bootloaderModule` to function form could conflict if a downstream module also sets `extraModuleArgs.pkgs` in a non-standard way | VERY LOW | The `pkgs` argument to NixOS modules is always the evaluated nixpkgs instance; this is a stable, universally supported module convention |
| `gnused` store path changes on nixpkgs update | NONE | Nix string interpolation `${pkgs.gnused}/bin/sed` is re-evaluated on each `nixos-rebuild`; the path always reflects the current nixpkgs closure |
| Existing users who re-run `install.sh` after an earlier failed attempt may see a repeated failure until they re-download the template | MEDIUM | The install.sh PATH guard prevents the repeat failure even without template re-download |

---

## 9. Summary

**Root cause (exact):**
`template/etc-nixos-flake.nix` sets `boot.loader.systemd-boot.extraInstallCommands` to
a shell snippet that calls `sed` as a bare (unqualified) command name. nixpkgs embeds
this snippet verbatim in the built `install-systemd-boot.sh` store artifact. When
`nixos-rebuild switch` runs this script via `systemd-run`, the subprocess executes in a
clean service environment where `sed` is not in PATH, producing the reported error.

**Primary fix:**
Modify `bootloaderModule` in `template/etc-nixos-flake.nix` to accept `pkgs` and use
`${pkgs.gnused}/bin/sed` — a Nix-evaluated absolute store path immune to any PATH
stripping.

**Secondary fix:**
Add a PATH normalisation block in `scripts/install.sh` (before `nixos-rebuild switch`)
that sets PATH in both the shell and the live systemd manager environment via
`sudo systemctl set-environment`. This protects existing users who already have the old
template on their host system.
