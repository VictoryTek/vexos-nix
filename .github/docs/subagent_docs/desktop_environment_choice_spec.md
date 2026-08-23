# Desktop Environment Choice (GNOME / COSMIC / Hyprland) — Spec

## Current state analysis

The `desktop` role has exactly one desktop environment baked in, imported
unconditionally by `configuration-desktop.nix`:

- `modules/gnome.nix` — universal GNOME base: GDM, dconf, xdg-portal-gnome,
  fonts, printing, Bluetooth, Ozone env vars, GNOME Shell extensions.
- `modules/gnome-desktop.nix` — desktop-role GNOME additions: accent colour,
  dash-to-dock, favourite apps, app folders, VRR toggle, Flatpak app install.
- `modules/remote-desktop.nix` — GNOME Remote Desktop (RDP) automated
  credential/keyring setup via `grdctl`. GNOME-Shell/mutter-specific;
  imported by desktop, server, htpc.
- `modules/branding-display.nix` — wallpaper deployment + GDM login-screen
  logo via `programs.dconf.profiles.gdm`. GDM/dconf-specific.
- `modules/branding.nix` — Plymouth boot theme, os-release, pixmaps/icons.
  DE-agnostic, stays as-is.
- `modules/security-desktop.nix`, `modules/network-desktop.nix`,
  `modules/packages-desktop.nix` — fail2ban, Samba/Avahi/wsdd discovery,
  GUI packages. All DE-agnostic, stay as-is.

Selection today is not a variant axis at all — every `vexos-desktop-<gpu>`
output gets GNOME, unconditionally.

## Problem definition

Add COSMIC and Hyprland as selectable alternatives to GNOME for the desktop
role, without multiplying flake outputs and without breaking the existing
GNOME experience (which remains the default).

## Amendment: RDP removed entirely

Mid-implementation the user asked to remove GNOME Remote Desktop (RDP) from
the project completely — the project now uses Sunshine/Moonlight
(`modules/sunshine.nix`) as its sole remote-access mechanism, uniformly
across all three desktop environments. As a result:

- `modules/remote-desktop.nix` (grdctl RDP credential automation) was
  deleted, along with its imports in `configuration-desktop.nix`,
  `configuration-server.nix`, `configuration-htpc.nix`.
- `services.gnome.gnome-remote-desktop.enable` is now forced `false` in
  `modules/gnome.nix` (the upstream GNOME module defaults it to `mkDefault
  true`), and the `allowlockedremotedesktop@kamens.us` GNOME Shell extension
  (RDP-into-locked-screen) was dropped from `commonExtensions`.
- `configuration-vanilla.nix`'s standalone RDP enable block was removed.
- The `just setup-rdp` recipe was removed from `justfile`.
- COSMIC and Hyprland modules below no longer need a remote-desktop story of
  their own (no wayvnc, no "documented limitation" for COSMIC) — Sunshine
  already covers remote access for every DE.

## Decisions (confirmed with user)

1. **Selection mechanism:** a per-host NixOS option,
   `vexos.desktop.environment = "gnome" | "cosmic" | "hyprland"` (default
   `"gnome"`), following the same idiom already used for
   `vexos.features.gaming.enable` etc. `configuration-desktop.nix` imports
   modules for all three DEs unconditionally; each module's content is gated
   internally by this option (the module-declares-its-own-option carve-out
   in the Module Architecture Pattern — this is not role-smuggling since all
   three modules belong to the same role and the same subsystem).
   No new flake outputs. The option is set per-host, most naturally in the
   optional `/etc/nixos/features.nix` overlay already loaded by
   `configuration-desktop.nix`'s `featuresModule`, or directly in a host's
   `hosts/desktop-<gpu>.nix`.
2. **Feature scope:** full parity — each DE gets an equivalent login
   greeter/session, autologin, wallpaper/branding, and best-available remote
   desktop, not just "compositor turned on." Known upstream maturity gaps are
   called out explicitly below rather than silently worked around.
3. **Hyprland shell/greeter:** Quickshell-based, matching the Omarchy
   reference stack — `programs.hyprland` (compositor) +
   `programs.dms-shell` (DankMaterialShell, the Quickshell-based in-session
   bar/launcher/notifications/lock) + `services.displayManager.dms-greeter`
   with `compositor.name = "hyprland"` (the matching Quickshell-based
   greetd greeter, themed to match the in-session shell).

All four modules referenced above (`services.desktopManager.cosmic`,
`services.displayManager.cosmic-greeter`, `programs.hyprland`,
`programs.dms-shell`, `services.displayManager.dms-greeter`) were verified
present on the project's actual pinned nixpkgs branch,
`github:NixOS/nixpkgs/nixos-26.05` (confirmed via the GitHub contents API
against that exact ref, not just a channel that resembles it):
`nixos/modules/services/display-managers/{cosmic-greeter,dms-greeter,greetd}.nix`,
`nixos/modules/services/desktop-managers/cosmic.nix`,
`nixos/modules/programs/wayland/{hyprland,dms-shell}.nix`, and
`pkgs/by-name/dm/dms-shell/package.nix`. No `nixpkgs-unstable` overlay is
needed for any of this.

## Proposed architecture

### New option-declaring module: `modules/desktop-environment.nix`

Declares:

```nix
options.vexos.desktop.environment = lib.mkOption {
  type = lib.types.enum [ "gnome" "cosmic" "hyprland" ];
  default = "gnome";
  description = "Desktop environment/compositor used by the desktop role.";
};
```

Imported by `configuration-desktop.nix` first, before the three DE modules,
so the option exists when they read it.

### GNOME (existing, made conditional)

- `modules/gnome.nix` / `modules/gnome-desktop.nix`: wrap the
  GNOME-activating settings (`services.desktopManager.gnome.enable`,
  `services.displayManager.gdm.enable`, GNOME dconf profile,
  `services.gnome.gnome-remote-desktop.enable`, autologin block, GNOME
  package lists, GNOME Shell extensions, fonts/printing/Bluetooth stay
  shared — see below) in
  `lib.mkIf (config.vexos.desktop.environment == "gnome")`.
- Genuinely DE-agnostic content currently living in `gnome.nix` (fonts,
  printing, Bluetooth, NetworkManager OpenVPN plugin) moves to a small new
  shared module, `modules/desktop-common.nix`, imported unconditionally by
  `configuration-desktop.nix` — so COSMIC/Hyprland hosts still get printing,
  Bluetooth, fonts, VPN import support. This is a **surgical extraction**,
  not a rewrite: those blocks move verbatim.

### COSMIC: new `modules/cosmic-desktop.nix`

Gated by `lib.mkIf (config.vexos.desktop.environment == "cosmic")`:

- `services.desktopManager.cosmic.enable = true;`
  `services.desktopManager.cosmic.xwayland.enable = true;`
- `services.displayManager.cosmic-greeter.enable = true;`
- Autologin: reuse `services.displayManager.autoLogin` (DE-agnostic NixOS
  option; already used by GNOME today) — set unconditionally in
  `desktop-common.nix` instead of duplicating it in each DE module, since all
  three DEs want the same "auto-login as `vexos.user.name`" behaviour.
- Wallpaper/branding: COSMIC has no dconf-equivalent system profile; its
  settings live per-user under `~/.config/cosmic/*` (RON files) written by
  `cosmic-settings`/`cosmic-bg`. Branding is applied by deploying a default
  `com.system76.CosmicBackground` RON config to the user's config dir via a
  one-shot systemd user service on first login (same self-heal pattern
  already used by `modules/remote-desktop.nix` for RDP credentials), pointed
  at the same `vexos-wallpapers` store path `branding-display.nix` already
  builds.
- Remote desktop: **documented limitation.** COSMIC's own remote-desktop
  portal support is not yet mature/stable enough in this nixpkgs revision to
  match GNOME Remote Desktop's automated RDP setup, and `wayvnc` (used for
  Hyprland below) is wlroots-specific — `cosmic-comp` is Smithay-based, not
  wlroots, so `wayvnc` does not apply either. Ship without an automated
  remote-desktop path for COSMIC in this pass; call this out plainly to the
  user in the summary and revisit once upstream COSMIC remote-desktop
  support lands in nixpkgs.

### Hyprland: new `modules/hyprland-desktop.nix`

Gated by `lib.mkIf (config.vexos.desktop.environment == "hyprland")`:

- `programs.hyprland.enable = true;` (+ `xwayland.enable = true;`,
  `withUWSM = true;` for proper `graphical-session.target` integration, which
  other modules like `services.gnome.gnome-remote-desktop`-equivalents and
  autologin/session targets depend on).
- `programs.dms-shell.enable = true;` — Quickshell-based bar/launcher/
  notifications/lock, the Omarchy-equivalent shell.
- `services.displayManager.dms-greeter.enable = true;`
  `services.displayManager.dms-greeter.compositor.name = "hyprland";` —
  matching Quickshell greeter.
- `xdg.portal` with the Hyprland portal package (exact attr to be confirmed
  against this nixpkgs revision during implementation — likely bundled with
  `hyprland` rather than a separate `xdg-desktop-portal-hyprland` attr, per
  the 404 observed at the expected `pkgs/by-name` path).
- Wallpaper/branding: deployed via a default `hyprpaper`/`dms-shell`
  settings file pointing at the same `vexos-wallpapers` store path, written
  to `/etc/skel`-equivalent or copied on first login (mirrors the COSMIC
  approach above).
- Remote desktop: `programs.wayvnc.enable = true;` (Hyprland is
  wlroots-based, so wayvnc applies here unlike COSMIC). This is a VNC
  server, not RDP — a real capability difference from GNOME's RDP-based
  `remote-desktop.nix`; call this out to the user rather than presenting it
  as equivalent.

### `configuration-desktop.nix` changes

```nix
imports = [
  ./modules/desktop-environment.nix   # NEW — declares vexos.desktop.environment
  ./modules/desktop-common.nix        # NEW — fonts/printing/BT/VPN extracted from gnome.nix
  ./modules/gnome.nix
  ./modules/gnome-desktop.nix
  ./modules/cosmic-desktop.nix        # NEW
  ./modules/hyprland-desktop.nix      # NEW
  ./modules/remote-desktop.nix        # GNOME-only content now gated internally
  ...
  ./modules/branding-display.nix      # GDM-specific dconf block gated internally
  ...
];
```

`modules/remote-desktop.nix` and `modules/branding-display.nix` get their
existing bodies wrapped in
`lib.mkIf (config.vexos.desktop.environment == "gnome")` rather than being
conditionally imported, keeping the import list static per Option B.

### Packages

- COSMIC and Hyprland pull their own package sets via their NixOS modules
  (`environment.cosmic.excludePackages` mirrors
  `environment.gnome.excludePackages` for trimming COSMIC bloat; Hyprland
  has no equivalent bloat list to trim).
- `modules/packages-desktop.nix` (browser, gparted, mpv, etc.) stays
  imported unconditionally — none of it is GNOME-specific.

## Dependencies

No new flake inputs. All packages/modules referenced
(`services.desktopManager.cosmic`, `services.displayManager.cosmic-greeter`,
`programs.hyprland`, `programs.dms-shell`,
`services.displayManager.dms-greeter`, `programs.wayvnc`) come from the
already-pinned `nixpkgs` input (`nixos-26.05`) — verified present at that
exact ref (see above). No `pkgs.unstable` overlay involvement needed.

## Configuration changes

New option: `vexos.desktop.environment` (default `"gnome"`, so every
existing host's build output is unchanged unless the host opts in via its
`/etc/nixos/features.nix` or host file).

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| COSMIC has no automated remote-desktop equivalent to GNOME's RDP setup | Documented limitation, not silently skipped; revisit when upstream matures |
| Hyprland's wayvnc is VNC, not RDP — different protocol/client expectations than GNOME | Documented explicitly, not presented as drop-in parity |
| `xdg-desktop-portal-hyprland` attr path unconfirmed at exact pinned rev | Confirm exact attribute during Phase 2 implementation before writing the import; fall back to whatever attr `programs.hyprland.portalPackage` defaults to if a standalone attr doesn't exist |
| dconf-free branding (COSMIC/Hyprland) requires a new "deploy default config on first login" mechanism instead of the existing system dconf profile pattern | Reuse the proven self-heal systemd-service pattern from `modules/remote-desktop.nix` rather than inventing a new mechanism |
| Extracting fonts/printing/Bluetooth/VPN out of `gnome.nix` into `desktop-common.nix` touches a shared file broadly | Pure move, no behavior change — verified by `nixos-rebuild dry-build` on all three `vexos.desktop.environment` values for `vexos-desktop-amd` in Phase 3 |
| New `lib.mkIf` gating inside `gnome.nix`/`gnome-desktop.nix`, `remote-desktop.nix`, `branding-display.nix` on `vexos.desktop.environment` | Falls under the Module Architecture Pattern's explicit carve-out (gating by an option the same subsystem declares), not the role-smuggling anti-pattern the rule targets |

## Implementation steps (for Phase 2)

1. Add `modules/desktop-environment.nix` (option declaration).
2. Add `modules/desktop-common.nix`; move fonts/printing/Bluetooth/VPN-plugin
   blocks out of `modules/gnome.nix` into it verbatim; add
   `services.displayManager.autoLogin` there too (currently only inside
   `gnome.nix`).
3. Wrap GNOME-activating config in `gnome.nix` / `gnome-desktop.nix` in
   `lib.mkIf (cfg.environment == "gnome")` (or equivalent — GNOME's own
   options already default appropriately; only the parts that would conflict
   with COSMIC/Hyprland need gating, e.g. `services.xserver.enable`,
   `services.desktopManager.gnome.enable`, `services.displayManager.gdm.enable`,
   the dconf profile, GNOME package lists, GNOME Shell extensions,
   `services.gnome.gnome-remote-desktop.enable`).
4. Add `modules/cosmic-desktop.nix` per the design above.
5. Add `modules/hyprland-desktop.nix` per the design above; confirm the
   Hyprland XDG portal attribute against the pinned nixpkgs rev before
   writing it.
6. Gate `modules/remote-desktop.nix` and `modules/branding-display.nix`
   bodies behind `vexos.desktop.environment == "gnome"`.
7. Update `configuration-desktop.nix` imports.
8. Verify: `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` with
   `vexos.desktop.environment` set to each of `"gnome"`, `"cosmic"`,
   `"hyprland"` in turn (via a temporary `/etc/nixos/features.nix` override
   on the dev machine, reverted after).

## Returns

Spec file: `.github/docs/subagent_docs/desktop_environment_choice_spec.md`
