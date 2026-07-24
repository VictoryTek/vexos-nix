# Migrate Discord/Vesktop from nixpkgs to Flatpak — Spec

## Current state analysis

`modules/gaming.nix` installs both apps as native nixpkgs derivations in
`environment.systemPackages` (`modules/gaming.nix:96-97`):

```nix
pkgs.unstable.vesktop # feature-rich Discord client (Vencord-based)
pkgs.discord         # official Discord client
```

`modules/gnome-desktop.nix:87-90` and `home-desktop.nix:222` reference their
`.desktop` file IDs (`vesktop.desktop`, `discord.desktop`) inside the "Game
Utilities" GNOME app-folder grouping.

## Problem definition

Extensive investigation this session (see
`.github/docs/subagent_docs/discord_vulkan_gpu_select_*.md`,
`nvidia_driver_590_rollback_spec.md`) found that native nixpkgs Vesktop
cannot screen-share on this hybrid AMD+NVIDIA laptop — the portal/PipeWire
screencast session dies (`WL: error in client communication`) regardless of
GPU-selection env vars, Vulkan/EGL vendor pinning, XWayland forcing, or
driver branch (reproduced on both 580.x and 595.x). Native Discord fails
even harder (crashes on launch).

**Resolved empirically, not theoretically:** the user performed a real
side-by-side test — full Bazzite install (not live-ISO, which turned out to
be read-only and unusable for testing) confirmed both Discord and Vesktop
Flatpak builds screen-share correctly on this exact hardware. The user then
installed Vesktop as a Flatpak directly on this system and confirmed
screen-share works. This is a verified fix, not a hypothesis.

Root cause is presumed to be Flatpak's bundled/pinned runtime graphics
stack (Freedesktop Platform GL/Mesa extensions matched to the Flatpak
runtime rather than the host's bleeding-edge NVIDIA 595 + `egl-wayland2`
1.0.1 + kernel 7.1.4 combination) sidestepping whatever incompatibility
exists in the native host stack — consistent with every other native-side
mitigation failing identically regardless of GPU config.

## Proposed solution

Replace the nixpkgs packages with their Flathub equivalents, installed via
this repo's existing Flatpak management system (`modules/flatpak.nix`,
already used for Lutris/ProtonPlus/PrismLauncher in this same file):

- Discord → `com.discordapp.Discord`
- Vesktop → `dev.vencord.Vesktop` (official Flathub listing, confirmed via
  Flathub/GitHub — bundles venmic for audio screenshare)

Both apps are removed from `environment.systemPackages` and added to
`vexos.flatpak.extraApps` (installed) and `vexos.flatpak.managedApps`
(so they're cleanly uninstalled if `vexos.features.gaming.enable` is later
set to false — matching the existing pattern for the other three gaming
Flatpak apps in this file).

The "Game Utilities" app-folder grouping in `modules/gnome-desktop.nix` and
`home-desktop.nix` needs its `.desktop` file references updated to match
Flatpak's ID-based desktop file naming convention
(`<app-id>.desktop` instead of the nixpkgs-derived `vesktop.desktop` /
`discord.desktop`).

## Implementation steps

1. `modules/gaming.nix`:
   - Remove `pkgs.unstable.vesktop` and `pkgs.discord` from
     `environment.systemPackages`
   - Add `"com.discordapp.Discord"` and `"dev.vencord.Vesktop"` to
     `vexos.flatpak.extraApps`
   - Add the same two IDs to `vexos.flatpak.managedApps` (matching the
     existing unconditional-ownership block at the top of the file's
     `config = lib.mkMerge [...]`)
2. `modules/gnome-desktop.nix`: update the "Game Utilities" folder's `apps`
   list — `"vesktop.desktop"` → `"dev.vencord.Vesktop.desktop"`,
   `"discord.desktop"` → `"com.discordapp.Discord.desktop"`
3. `home-desktop.nix`: same substitution in the dconf write for
   `"Game Utilities"/apps`

## Dependencies

No new flake inputs — both apps install through the existing Flatpak/
Flathub mechanism already wired up in `modules/flatpak.nix`. No Context7
lookup needed (not a library integration).

## Configuration changes

`modules/gaming.nix`, `modules/gnome-desktop.nix`, `home-desktop.nix`.
No `stateVersion` changes, no `hardware-configuration.nix` changes.

## Risks and mitigations

- **Risk:** removing `pkgs.unstable.vesktop`/`pkgs.discord` from
  `environment.systemPackages` doesn't automatically uninstall an
  already-switched-in native binary from the current generation until
  the next `nixos-rebuild switch`.
  **Mitigation:** expected/normal NixOS behavior; the user will run the
  rebuild themselves per this repo's workflow.
- **Risk:** Flatpak `.desktop` IDs might not exactly match
  `<app-id>.desktop` if the Flathub packaging uses a different launcher
  name.
  **Mitigation:** this is Flatpak's standard, universal convention
  (`<reverse-DNS-app-id>.desktop`) — confirmed pattern already in use by
  every other Flatpak entry in `modules/gnome-desktop.nix` /
  `home-desktop.nix` (e.g. `org.prismlauncher.PrismLauncher.desktop`,
  `com.vysp3r.ProtonPlus.desktop`).
- **Risk:** `pkgs.unstable.vesktop`'s CVE-flagged-pnpm comment
  (`modules/gaming.nix:93-95`) no longer applies once vesktop is a Flatpak
  build (Flathub controls its own build toolchain, not this flake).
  **Mitigation:** remove that comment along with the nixpkgs reference —
  it would be stale/misleading otherwise.
