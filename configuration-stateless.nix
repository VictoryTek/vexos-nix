{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gnome-stateless.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/packages-common.nix
    ./modules/packages-desktop.nix
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/system.nix
    ./modules/system-lts-kernel.nix  # Linux 6.12 LTS (hold until latest kernel supports NVIDIA)
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on stateless
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/impermanence.nix
    ./modules/nix.nix
    ./modules/nix-stateless.nix     # 7-day GC retention (state resets on reboot)
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/asus-opt.nix
  ];

  # ---------- Branding ----------
  vexos.branding.role  = "stateless";
  boot.plymouth.enable = true;   # graphical boot splash

  # ---------- Users ----------
  # Fallback password — only used when no stateless-user-override.nix exists in
  # /etc/nixos.  migrate-to-stateless.sh reads the pre-migration hash from
  # /etc/shadow and writes it to that override file so the original password
  # carries forward.  stateless-setup.sh prompts for one.  "vexos" is only
  # seen on a completely unconfigured first run where neither script ran.
  users.users.${config.vexos.user.name}.initialPassword = "vexos";

  # ---------- Impermanence ----------
  # Enable tmpfs-rooted ephemeral filesystem for the stateless role.
  # / is wiped on every reboot; only /nix and /persistent survive.
  # Filesystem impermanence: / is mounted as tmpfs by this module.
  # Run scripts/stateless-setup.sh to format the disk before first deploy.
  vexos.impermanence.enable = true;

  # ---------- System packages ----------
  # tor-browser: installed system-wide (not via Home Manager) so torbrowser.desktop
  # lands in /run/current-system/sw/share/applications/ and is always visible to
  # GNOME regardless of Home Manager activation timing on the fresh tmpfs home.
  environment.systemPackages = [
    pkgs.tor-browser
  ];

  # ---------- Flatpak ----------
  # Prevent GIMP from being installed on stateless. It is never in
  # defaultApps but may be present from a manual install or prior session.
  # Desktop-role extras are also excluded so they are actively uninstalled
  # if this machine was previously running the desktop configuration and
  # /var/lib/flatpak (persisted by impermanence) carries stale installs.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    # Desktop-role gaming / utility flatpaks
    "org.prismlauncher.PrismLauncher"
    "com.vysp3r.ProtonPlus"
    "net.lutris.Lutris"
    # Desktop-role dev / misc flatpaks
    "io.github.pol_rivero.github-desktop-plus"
    "com.ranfdev.DistroShelf"
  ];

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "25.11";
}
