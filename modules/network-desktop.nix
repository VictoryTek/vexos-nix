# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS network share discovery for GNOME
# Files (Nautilus) and samba CLI tools.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  # ── Avahi service publishing ─────────────────────────────────────────────
  # Extends the base Avahi configuration in network.nix with service
  # publishing.  publish.enable + publish.userServices allow Avahi to
  # advertise this machine's services via mDNS/DNS-SD and enable GVfs to
  # discover remote hosts advertising _smb._tcp / _nfs._tcp services in
  # the Nautilus "Network" view.
  services.avahi.publish = {
    enable       = true;
    userServices = true;
  };

  # ── WS-Discovery (WSDD) ─────────────────────────────────────────────────
  # Web Service Discovery responder — required for discovering Windows 10+
  # machines and Samba servers that use WSD instead of legacy NetBIOS
  # browsing.  Also makes this machine visible to Windows "Network".
  # Opens TCP 5357 and UDP 3702 via openFirewall.
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
  };

  # ── NFS client support ──────────────────────────────────────────────────
  # Loads the NFS kernel module and pulls in nfs-utils so that GVfs can
  # mount NFS shares discovered via Nautilus → Network → nfs://host/export.
  boot.supportedFilesystems = [ "nfs" ];

  # ── SMB/CIFS client tools ────────────────────────────────────────────────
  # samba: provides smbclient CLI and libsmbclient (used by GVfs SMB
  # backend).  GNOME Files browses SMB shares via GVfs; smbclient is the
  # CLI companion.  Client-only — no inbound firewall ports needed.
  environment.systemPackages = with pkgs; [
    samba  # smbclient — browse/test SMB shares; also provides nmblookup
  ];
}
