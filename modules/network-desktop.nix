# modules/network-desktop.nix
# Display-role networking additions: samba CLI tools for SMB/CIFS browsing.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  # samba: provides smbclient — browse and test SMB shares from the CLI.
  # GNOME Files (Nautilus) browses SMB shares natively via GVfs; smbclient
  # is the CLI companion tool. Client-only — no inbound firewall ports needed.
  environment.systemPackages = with pkgs; [
    samba  # smbclient — browse/test SMB shares; also provides nmblookup
  ];
}
