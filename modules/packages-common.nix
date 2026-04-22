# modules/packages-common.nix
# CLI tools safe for all roles (desktop, server, htpc, headless-server, stateless).
# Desktop additionally imports modules/packages-desktop.nix for GUI tools.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    just    # Command runner (justfile)
    btop    # Terminal process viewer
    inxi    # System information tool
    git     # Version control
    curl    # HTTP / transfer CLI
    wget    # File downloader
  ];
}
