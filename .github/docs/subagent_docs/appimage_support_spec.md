# AppImage Support — Specification

## Current State Analysis

The vexos-nix flake defines 30 NixOS outputs across six roles × GPU variants. Desktop and HTPC
roles support native Nix packages, Flatpak, and Wine/Proton, but there is no AppImage support of
any kind:

- No `programs.appimage` configuration exists in any module
- No `boot.binfmt.registrations` for AppImage magic bytes
- No `appimage-run` wrapper installed anywhere

This means users who download a `.AppImage` file on a desktop or HTPC system cannot execute it
without manually invoking `appimage-run` or entering a dev shell — a friction point that is
trivially solved by the upstream NixOS module.

## Problem Definition

AppImage is a portable Linux application format (`.AppImage` files) widely used for distributing
pre-built Linux apps that are not yet packaged in nixpkgs or Flatpak. On a standard Linux distro
the file would be `chmod +x` and run directly; on NixOS without binfmt registration it silently
fails because the ELF interpreter path embedded in the AppImage does not exist on the NixOS FHS.

## Proposed Solution Architecture

NixOS ships `programs.appimage` (available since NixOS 23.11, stable in 25.11) which:

1. Installs `appimage-run` — a wrapper that creates a temporary FHS environment for the AppImage
2. Registers both AppImage magic-byte signatures with `binfmt_misc` via `boot.binfmt` so `.AppImage`
   files execute transparently when marked executable, without any user-visible wrapper invocation

### Option B Module Files

Per the project's Module Architecture Pattern (Common base + role additions):

| File | Role | Content |
|------|------|---------|
| `modules/appimage.nix` | Role-addition (desktop + htpc) | `programs.appimage.enable + binfmt = true` |

No universal base file is needed — AppImage is a display/interactive-desktop feature with no
applicability to server, headless-server, stateless, or vanilla roles.

### Roles receiving AppImage support

| Role | Gets AppImage? | Rationale |
|------|----------------|-----------|
| desktop | YES | Primary use case — power users, creative tools, niche apps |
| htpc | YES | Media apps, streaming clients sometimes distributed as AppImages |
| stateless | NO | Minimal ephemeral role; no persistent home for AppImages |
| server | NO | No interactive desktop |
| headless-server | NO | No desktop at all |
| vanilla | NO | Stock NixOS baseline — no extras |

## Implementation Steps

1. Create `modules/appimage.nix` with:
   ```nix
   { ... }:
   {
     programs.appimage = {
       enable = true;
       binfmt = true;
     };
   }
   ```
2. Add `./modules/appimage.nix` to the imports list in `configuration-desktop.nix`
3. Add `./modules/appimage.nix` to the imports list in `configuration-htpc.nix`

## Dependencies

- `programs.appimage` — NixOS built-in module, no new flake inputs required
- `appimage-run` package pulled transitively by the module from nixpkgs stable

Context7 check: not required — this is a pure NixOS built-in module with no new external
dependencies or flake inputs.

## Configuration Changes

| File | Change |
|------|--------|
| `modules/appimage.nix` | New file |
| `configuration-desktop.nix` | Add import |
| `configuration-htpc.nix` | Add import |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| binfmt conflicts with existing registrations | `programs.appimage` uses official nixpkgs magic bytes; no other binfmt registrations exist in this repo |
| AppImage execution requires FUSE | NixOS `appimage-run` handles FUSE mounting internally via `squashfuse`; no additional kernel module config needed |
| Security surface increase | AppImages run in an isolated FHS env created per-invocation; no persistent root-level changes; AppArmor baseline already in place via `security.nix` |
