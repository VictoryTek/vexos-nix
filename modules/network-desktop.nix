# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS/WSD network share discovery for
# GNOME Files (Nautilus).
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ lib, ... }:
{
  # ── Samba client configuration ───────────────────────────────────────────
  # Generates /etc/samba/smb.conf so that libsmbclient (used by GVfs
  # gvfsd-smb-browse) can initialise and enumerate SMB workgroups/hosts.
  # All server daemons are disabled — this is client-only.
  # lib.mkDefault on daemon enables lets a server role override to true
  # without conflicts.
  services.samba = {
    enable          = true;
    nmbd.enable     = lib.mkDefault false;
    smbd.enable     = lib.mkDefault false;
    winbindd.enable = lib.mkDefault false;
    settings.global = {
      workgroup             = "WORKGROUP";
      "server string"       = "NixOS";
      "server role"         = "standalone";
      "load printers"       = "no";
      # Allow SMB1 so gvfsd-smb-browse can reach NAS devices that
      # only support SMBv1 (Samba 4.13+ otherwise refuses NT1).
      "client min protocol" = "NT1";
    };
  };

  # ── Avahi service publishing ─────────────────────────────────────────────
  # publish.enable + publish.userServices lets Avahi advertise this machine
  # and enables GVfs to discover remote hosts advertising _smb._tcp /
  # _nfs._tcp services in Nautilus → Network.
  services.avahi.publish = {
    enable       = true;
    addresses    = true;
    workstation  = true;
    userServices = true;
    domain       = true;
  };

  # ── WS-Discovery (wsdd) ──────────────────────────────────────────────────
  # Discovers NAS / Windows hosts that advertise via WS-Discovery (WSD) in
  # addition to Avahi/mDNS.  gvfsd-wsdd connects to the system wsdd socket
  # and surfaces discovered hosts in Nautilus → Network.
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
    discovery    = true;
  };

  # ── NFS client support ──────────────────────────────────────────────────
  boot.supportedFilesystems = [ "nfs" ];

  # ── NetBIOS conntrack helper ────────────────────────────────────────────
  # gvfsd-smb-browse / libsmbclient sends broadcast queries on UDP 137.
  # Replies come from different source IPs so conntrack drops them as
  # unrelated.  Loading the netbios-ns helper tracks them correctly.
  networking.firewall.extraCommands = ''
    iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns
  '';
}
