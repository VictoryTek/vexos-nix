# Phase 1 Spec: bash-common smbstatus alias scope

## Feature
Fix quality issue: `home/bash-common.nix` defines `smbstatus` globally even where Samba server daemon is not enabled.

## Current State Analysis

### 1) Alias definition and propagation
- `home/bash-common.nix` defines:
  - `smbstatus = "systemctl status smbd";`
- Every role home file imports `./home/bash-common.nix`:
  - `home-desktop.nix`
  - `home-htpc.nix`
  - `home-stateless.nix`
  - `home-server.nix`
  - `home-headless-server.nix`
  - `home-vanilla.nix`
- Result: `smbstatus` is present in all flake host outputs.

### 2) Samba role wiring in this repo
- Display roles (`desktop`, `htpc`, `stateless`, `server`) import `modules/network-desktop.nix`.
- `modules/network-desktop.nix` is explicitly client-oriented and sets:
  - `services.samba.enable = true`
  - `services.samba.smbd.enable = lib.mkDefault false`
  - `services.samba.nmbd.enable = lib.mkDefault false`
  - `services.samba.winbindd.enable = lib.mkDefault false`
- `headless-server` and `vanilla` do not import `modules/network-desktop.nix`.

### 3) Optional server-side Samba path
- `modules/server/cockpit.nix` can enable server-side Samba when:
  - `vexos.server.cockpit.fileSharing.enable = true`
- `modules/server/nas.nix` can mkDefault-enable `vexos.server.cockpit.fileSharing.enable` when NAS umbrella is enabled.
- This is optional, not default.

### 4) Evaluated behavior (representative role variants + full host sweep)
Representative (`*-amd`) results:
- `desktop`, `htpc`, `stateless`, `server`:
  - alias present
  - `services.samba.enable = true`
  - `services.samba.smbd.enable = false`
- `headless-server`, `vanilla`:
  - alias present
  - `services.samba.enable = false`
  - `services.samba.smbd.enable = true` (module default value, but Samba service itself disabled)

Whole flake check result:
- Alias exists on all host outputs.
- No host output has both `services.samba.enable = true` and `services.samba.smbd.enable = true` by default.

## Problem Definition
- `smbstatus` is currently treated as a universal shell alias, but it targets a server daemon state that is not enabled by default in any role output.
- This creates a misleading command surface and noisy/incorrect UX.
- It violates this repo's Option B intent for shared files: common/base files should only contain universally valid behavior.

## Proposed Solution Architecture (Minimal and Option B-aligned)

### Selected approach
Remove `smbstatus` from shared base alias file.

Why this is preferred:
- Minimal change with lowest regression risk.
- Fully eliminates the cross-role mismatch immediately.
- Aligns with Option B principle: shared base should only contain universal settings.
- Avoids adding conditional logic inside shared files.

### Non-goals in this change
- No new server-only alias module in this phase.
- No changes to Samba service wiring/modules.
- No dependency or flake input changes.

## Phase 2 Implementation Plan
1. Edit `home/bash-common.nix`.
2. Remove the `smbstatus` alias entry from `programs.bash.shellAliases`.
3. Keep all other aliases unchanged.
4. Run quick validation:
   - `rg -n "smbstatus" home/bash-common.nix home-*.nix`
   - `nix flake check`

## Configuration/Behavior Changes
- User-facing change:
  - `smbstatus` is no longer globally available in all roles.
- No changes to:
  - Samba service behavior
  - role module imports
  - system packages
  - flake inputs

## Risks and Mitigations
- Risk: users accustomed to `smbstatus` lose a convenience alias.
- Mitigation: this alias currently reports non-useful state for default role outputs; removal prevents incorrect operational assumptions.
- Follow-up option (separate change if desired): reintroduce Samba status helpers in a dedicated server feature-scoped module after deciding exact scope and daemon/unit expectations.

## Dependencies
- None.
- No new packages or flake inputs required.

## Research Sources (>= 6) and Relevance
1. GNU Bash Manual - Aliases
   - https://www.gnu.org/software/bash/manual/html_node/Aliases.html
   - Key point: aliases are textual substitutions; functions are generally preferable for non-trivial behavior.

2. Google Shell Style Guide - Aliases
   - https://google.github.io/styleguide/shellguide.html
   - Key point: aliases are discouraged for robust shell behavior; function-based semantics are preferred.

3. systemctl(1) Linux man page (man7)
   - https://man7.org/linux/man-pages/man1/systemctl.1.html
   - Key point: `status` is human-oriented runtime introspection and reflects actual active/inactive/failed unit states.

4. NixOS Manual - Samba section
   - https://nixos.org/manual/nixos/stable/#sec-writing-modules (manual index and Samba section context in fetched docs)
   - Key point: Samba enablement is explicit module configuration; daemon behavior is option-driven.

5. MyNixOS option docs - `services.samba.enable`
   - https://mynixos.com/nixpkgs/option/services.samba.enable
   - Key point: default is `false`.

6. MyNixOS option docs - `services.samba.smbd.enable`
   - https://mynixos.com/nixpkgs/option/services.samba.smbd.enable
   - Key point: default is `true` (daemon option default), which is distinct from the top-level Samba enable gate.

7. NixOS Wiki - Samba
   - https://wiki.nixos.org/wiki/Samba
   - Key point: distinguishes client/discovery and server setups; confirms Samba role complexity and optional daemon/service paths.

## Expected Files To Modify in Phase 2
- `home/bash-common.nix`
