# modules/packages-common.nix
# CLI tools safe for all roles (desktop, server, htpc, headless-server, stateless).
# Desktop additionally imports modules/packages-desktop.nix for GUI tools.
{ pkgs, ... }:
{
  # Expose the justfile at /etc/nixos/justfile so the `just` alias in
  # bash-common.nix works on all roles regardless of working directory.
  environment.etc."nixos/justfile".source = ../justfile;
  environment.etc."nixos/template/server-services.nix".source = ../template/server-services.nix;

  environment.systemPackages = with pkgs; [
    just    # Command runner (justfile)
    btop    # Terminal process viewer
    inxi      # System information tool
    pciutils  # lspci — PCI device inspection
    git     # Version control
    curl    # HTTP / transfer CLI
    wget    # File downloader
  ];
}
