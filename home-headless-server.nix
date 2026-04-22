# home-headless-server.nix
# Home Manager configuration for user "nimda" — Headless Server role.
# Shell environment and sysadmin utilities only.
# No GNOME, no Wayland, no GUI apps — accessed exclusively via SSH.
{ config, pkgs, lib, inputs, ... }:
{
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    # NOTE: just is installed system-wide via modules/packages.nix.

    # System utilities
    fastfetch
    # NOTE: btop and inxi are installed system-wide via modules/packages.nix.
  ];

  # ── Shell ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      ll   = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── Tmux terminal multiplexer ──────────────────────────────────────────────
  # Essential for persistent SSH sessions: detach and reattach without losing work.
  programs.tmux = {
    enable       = true;
    mouse        = true;
    terminal     = "tmux-256color";
    prefix       = "C-a";
    baseIndex    = 1;
    escapeTime   = 0;
    historyLimit = 10000;
    keyMode      = "vi";
  };

  # ── Justfile ───────────────────────────────────────────────────────────────
  home.file."justfile".source = ./justfile;
  home.file."template/server-services.nix".source = ./template/server-services.nix;

  home.stateVersion = "24.05";
}
