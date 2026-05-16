# Branding Headless AssetRole Clarity Spec

## Feature
- Finding: [QUALITY] `wallpapers/headless-server` directory does not exist; `branding.nix` re-uses `server` via `assetRole`
- Spec file: `.github/docs/subagent_docs/branding_headless_assetrole_clarity_spec.md`
- Requested phase: Phase 1 (Research and Specification)

## 1. Current State Analysis

### Repository observations
- `modules/branding.nix` defines:
  - `role = config.vexos.branding.role;`
  - `assetRole = if role == "headless-server" then "server" else role;`
  - Asset directories (`files/pixmaps`, `files/background_logos`, `files/plymouth`) are resolved via `assetRole`.
- `configuration-headless-server.nix`:
  - sets `vexos.branding.role = "headless-server"`;
  - imports `./modules/branding.nix`;
  - forces `services.xserver.enable = lib.mkForce false`;
  - does not import `modules/branding-display.nix`.
- `modules/branding-display.nix`:
  - explicitly documents that it should not be imported for headless roles;
  - resolves wallpapers by `wallpapersDir = ../wallpapers + "/${role}"`.

### Filesystem observations
- Present role directories in branding assets:
  - `files/pixmaps/{desktop,htpc,server,stateless}`
  - `files/background_logos/{desktop,htpc,server,stateless}`
  - `files/plymouth/{desktop,htpc,server,stateless}`
  - `wallpapers/{desktop,htpc,server,stateless}`
- `headless-server` directories are intentionally absent in these roots.
- `server` asset directories contain expected files consumed by branding module logic.

## 2. Problem Definition

The quality finding flags a missing `wallpapers/headless-server` directory while also noting `branding.nix` intentionally maps `headless-server` to `server` for branding assets. The key question is whether this is:
- a functional defect requiring a fix,
- a non-issue (N/A), or
- a documentation clarity issue only.

## 3. External Research (Credible Sources)

The following sources were reviewed to validate architecture and expected behavior:

1. NixOS Manual - Configuration Syntax (Modularity)
   - URL: https://nixos.org/manual/nixos/stable/#sec-configuration-syntax
   - Relevant points: NixOS configuration is modular; `imports` is the primary composition mechanism; splitting role behavior across modules is idiomatic.

2. NixOS Manual - Writing NixOS Modules
   - URL: https://nixos.org/manual/nixos/stable/#sec-writing-modules
   - Relevant points: modules should represent logical concerns; module `imports` define composition; role-specific behavior through module boundaries is expected.

3. NixOS Manual - Profiles / Headless
   - URL: https://nixos.org/manual/nixos/stable/#sec-profiles-headless
   - Relevant points: headless configurations are expected to disable visual/graphical boot and display-oriented behavior.

4. NixOS Manual - X Window System
   - URL: https://nixos.org/manual/nixos/stable/#sec-x11
   - Relevant points: graphical UI stack is explicitly enabled via `services.xserver.enable`; when disabled, display stack functionality should not be assumed.

5. NixOS Manual - GNOME Desktop
   - URL: https://nixos.org/manual/nixos/stable/#module-gnome
   - Relevant points: GNOME and display manager functionality are explicit opt-ins and are part of graphical-role composition.

6. NixOS Manual - tpm2-totp with Plymouth
   - URL: https://nixos.org/manual/nixos/stable/#module-tpm2-totp
   - Relevant points: Plymouth behavior is tied to explicit `boot.plymouth.enable` usage and boot-screen visuals.

7. NixOS Wiki - Plymouth
   - URL: https://wiki.nixos.org/wiki/Plymouth
   - Relevant points: Plymouth is a graphical early-boot animation system; visual assets are relevant only when graphical boot path is active.

## 4. Assessment and Disposition

### Functional assessment
- The absence of `wallpapers/headless-server` is **not** currently a functional defect.
- For `headless-server` role:
  - `branding-display.nix` (the only module that consumes `wallpapers/${role}`) is intentionally not imported.
  - X server is forced off.
- Core branding in `branding.nix` deliberately maps `headless-server` to `server` via `assetRole`, so required non-wallpaper assets resolve correctly.

### Disposition
- **Status: N/A / WONTFIX (functional)**
- Rationale: behavior is intentional, coherent with role composition, and aligned with documented headless conventions.

## 5. Proposed Solution Architecture

### Primary recommendation
- No functional code changes required.

### Optional clarity improvement (documentation-only)
- Add or refine inline comments to make intent obvious for future maintainers:
  - `modules/branding.nix` near `assetRole` mapping.
  - `modules/branding-display.nix` note that headless roles should not import this module.

This optional step reduces future false-positive quality findings without changing runtime behavior.

## 6. Implementation Steps (Phase 2)

### Preferred path (strict N/A/WONTFIX)
1. Do not modify functional code.
2. Record this finding as resolved-by-design with this spec as evidence.

### Optional docs-only path (if maintainer requests extra clarity)
1. Add one short explanatory comment near `assetRole` in `modules/branding.nix`.
2. Add one short explanatory comment in `modules/branding-display.nix` confirming headless exclusion.
3. Run validation:
   - `nix flake check`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`

## 7. Dependencies
- No new dependencies.
- No flake input changes.

## 8. Configuration Changes
- None required.

## 9. Risks and Mitigations

- Risk: Future refactor accidentally imports `branding-display.nix` in headless role.
  - Mitigation: Keep explicit comment in `configuration-headless-server.nix` and/or optional assertion in future hardening pass.

- Risk: Repeated confusion about missing `headless-server` wallpaper directory.
  - Mitigation: Keep this spec in project docs and optionally add comments in branding modules.

## 10. Expected Phase 2 Modified Files

- **Required for disposition N/A/WONTFIX:** none.
- **If optional docs-only clarity is approved:**
  - `modules/branding.nix`
  - `modules/branding-display.nix`

## Summary
This finding is a quality/documentation clarity concern, not a functional defect. Current behavior is intentional and consistent with headless role architecture: headless avoids display module imports, while `assetRole` safely reuses `server` non-display branding assets.