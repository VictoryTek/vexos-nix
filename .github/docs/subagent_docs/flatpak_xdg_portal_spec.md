# flatpak_xdg_portal_spec

## Metadata
- Date: 2026-05-16
- Finding under review: [BUG] services.flatpak is enabled before xdg.portal is finalised; stateless only has xdg-desktop-portal-gnome.
- Primary local file: modules/gnome.nix
- Scope: Phase 1 research/spec only (no implementation in this document)

## Current State Analysis

### Local wiring in vexos-nix
1. All display roles in scope import both GNOME and Flatpak modules:
- configuration-desktop.nix imports modules/gnome.nix and modules/flatpak.nix
- configuration-stateless.nix imports modules/gnome.nix and modules/flatpak.nix
- configuration-server.nix imports modules/gnome.nix and modules/flatpak.nix
- configuration-htpc.nix imports modules/gnome.nix and modules/flatpak.nix

2. modules/flatpak.nix sets services.flatpak.enable = true behind vexos.flatpak.enable (default true).

3. modules/gnome.nix sets:
- services.desktopManager.gnome.enable = true
- xdg.portal.enable = true
- xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gnome ]
- xdg.portal.config.common.default = "gnome"

4. modules/gnome-flatpak-install.nix adds role app install service only when config.services.flatpak.enable && cfg.apps != [].

### Upstream behavior (nixpkgs / portals)
1. nixpkgs Flatpak module asserts xdg.portal.enable must be true when services.flatpak.enable is true.
- This means Flatpak cannot evaluate successfully without portals enabled in final merged config.

2. nixpkgs GNOME desktop module enables:
- xdg.portal.enable = true
- xdg.portal.extraPortals = [ xdg-desktop-portal-gnome xdg-desktop-portal-gtk ]
- xdg.portal.configPackages = [ gnome-session ] (mkDefault)

3. gnome-session default portal config (gnome-portals.conf) uses:
- default=gnome;gtk;
- org.freedesktop.impl.portal.Secret=gnome-keyring;

4. xdg portal module behavior documents that xdg.portal.config is preferred over xdg.portal.configPackages if set.

## Problem Definition

### Is the reported ordering bug real?
Verdict: No, not as stated.

Rationale:
- NixOS module evaluation is a merged lazy fixpoint; import order does not create imperative "start before finalised" behavior.
- Flatpak module assertion enforces xdg.portal.enable in final config.
- Therefore, this is not an ordering race between services.flatpak and xdg.portal.

### Is there still a functional risk in current config?
Verdict: Yes, likely.

Rationale:
- Local modules/gnome.nix forces xdg.portal.config.common.default = "gnome".
- Upstream GNOME integration expects gnome-session portal config (default=gnome;gtk; plus Secret mapping).
- Because xdg.portal.config is preferred over configPackages, local setting can effectively override GNOME's shipped fallback strategy.
- This can reduce backend fallback behavior (notably GTK fallback and interface-specific mapping such as Secret).

So the unresolved finding should be reframed from "ordering" to "backend preference override / fallback regression risk".

## Research Sources (Credible, >= 6)
1. nixpkgs xdg portal module source
- https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/nixos/modules/config/xdg/portal.nix
- Used for: extraPortals assertion, config vs configPackages precedence, portal package wiring.

2. nixpkgs Flatpak module source
- https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/nixos/modules/services/desktops/flatpak.nix
- Used for: assertion requiring xdg.portal.enable when Flatpak is enabled.

3. nixpkgs GNOME desktop manager module source
- https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-unstable/nixos/modules/services/desktop-managers/gnome.nix
- Used for: GNOME adds both gnome and gtk portals, and sets configPackages.

4. GNOME session portal configuration
- https://raw.githubusercontent.com/GNOME/gnome-session/main/data/gnome-portals.conf
- Used for: default backend chain (gnome;gtk) and Secret mapping.

5. XDG Desktop Portal docs main page
- https://flatpak.github.io/xdg-desktop-portal/docs/
- Used for: architecture and purpose of portal framework across sandboxed apps.

6. portals.conf specification
- https://flatpak.github.io/xdg-desktop-portal/docs/portals.conf.html
- Used for: backend selection semantics and default/interface mapping rules.

7. Flatpak desktop integration docs
- https://docs.flatpak.org/en/latest/desktop-integration.html
- Used for: Flatpak reliance on portals for file chooser, screenshots, URI open, etc.

8. NixOS manual (modularity and merge semantics)
- https://nixos.org/manual/nixos/stable/#sec-module-system
- Used for: module merge/fixpoint semantics and non-imperative configuration model.

9. NixOS manual Flatpak section (as surfaced in NixOS docs)
- https://nixos.org/manual/nixos/stable/
- Used for: GNOME handling of portal integration and Flatpak guidance.

## Proposed Solution (Minimal)

### Recommended minimal code change
Update modules/gnome.nix to stop overriding GNOME portal backend preference with a hard-coded single default.

Preferred implementation:
1. Remove line setting xdg.portal.config.common.default = "gnome".
2. Keep xdg.portal.enable and xdg.portal.extraPortals declarations as-is for now (minimal blast radius).

Why this is minimal and safe:
- Restores upstream GNOME backend selection policy via configPackages (gnome-session), including fallback and Secret mapping.
- Does not alter role/module topology or Flatpak service behavior.
- Avoids introducing broad refactors while resolving likely functionality gap.

### Alternative (not recommended for minimal patch)
Explicitly encode GNOME upstream semantics in repo config:
- xdg.portal.config.common.default = "gnome;gtk"
- xdg.portal.config.common."org.freedesktop.impl.portal.Secret" = "gnome-keyring"

This works but duplicates upstream policy and increases long-term drift risk.

## Exact Implementation Steps / Files
1. Edit modules/gnome.nix
- Remove the xdg.portal.config.common.default assignment.
- Optional: add a comment stating backend preference is intentionally delegated to GNOME's configPackages.

2. No changes required in:
- configuration-stateless.nix
- configuration-desktop.nix
- configuration-server.nix
- configuration-htpc.nix
- modules/flatpak.nix
- modules/gnome-flatpak-install.nix

## Risks and Mitigations

1. Risk: behavior change in portal backend selection.
- Mitigation: this is intentionally aligning with upstream GNOME defaults, not introducing novel policy.

2. Risk: hidden dependency on hardcoded default="gnome" in local workflows.
- Mitigation: validate common Flatpak portal paths (file chooser, screenshot, open URI) after switch.

3. Risk: duplicate portal entries from merged extraPortals lists.
- Mitigation: low impact; can be cleaned in a later non-blocking refactor.

## Validation Plan

### Build/evaluation checks
1. nix flake check --impure
2. sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
3. sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd

### Portal config checks (post-switch or eval)
1. Confirm xdg.portal.enable remains true in target config.
2. Confirm gnome-session config package is present in xdg.portal.configPackages.
3. Confirm xdg-desktop-portal and backend services are active in user session:
- systemctl --user status xdg-desktop-portal.service
- systemctl --user status xdg-desktop-portal-gnome.service

### Functional checks
1. Open a Flatpak app and trigger file chooser.
2. Verify screenshot/screencast portal access from a Flatpak app that uses it.
3. Verify URI open flow from Flatpak app (browser launch via portal).

## Expected Modified Files (Implementation Phase)
- modules/gnome.nix

(Phase 1 doc file produced now: .github/docs/subagent_docs/flatpak_xdg_portal_spec.md)
