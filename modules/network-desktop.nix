# modules/network-desktop.nix
# Display-role networking additions: SMB/NFS network share discovery for
# GNOME Files (Nautilus).
#
# Generates /etc/samba/smb.conf (client-only — all server daemons disabled)
# so that GVfs gvfsd-smb-browse can use libsmbclient to discover SMB hosts.
# Also enables Avahi service publishing, WS-Discovery (WSDD), and NFS
# kernel support.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ lib, ... }:
{
  # ── Samba client configuration ───────────────────────────────────────────
  # Generates /etc/samba/smb.conf so that libsmbclient (used by GVfs
  # gvfsd-smb-browse) can initialise and enumerate SMB workgroups/hosts.
  # All server daemons are disabled — this is client-only.  The NixOS samba
  # module automatically adds the samba package (smbclient, nmblookup) to
  # environment.systemPackages.
  #
  # lib.mkDefault on daemon enables lets a server role override to true
  # without conflicts.
  services.samba = {
    enable              = true;
    nmbd.enable         = lib.mkDefault false;
    smbd.enable         = lib.mkDefault false;
    winbindd.enable     = lib.mkDefault false;
    settings = {
      global = {
        workgroup            = "WORKGROUP";
        "server string"      = "NixOS";
        "server role"        = "standalone";
        "client min protocol" = "SMB2";
        "client max protocol" = "SMB3";
        "load printers"       = "no";
      };
    };
  };

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

  # ── /etc/samba symlink safety net ────────────────────────────────────────
  # NixOS generates smb.conf at /etc/static/samba/smb.conf, but the
  # /etc/samba → /etc/static/samba symlink may not be created during etc
  # activation (observed after first samba enable).  This tmpfiles rule
  # guarantees the symlink exists on every boot so that libsmbclient
  # (and therefore GVfs gvfsd-smb-browse) can find smb.conf.
  # L+ (recreate) handles a stale /etc/samba directory left by a previous
  # activation — it removes the existing entry and replaces it with the
  # symlink unconditionally.
  systemd.tmpfiles.settings."10-samba-etc" = {
    "/etc/samba" = {
      "L+" = {
        argument = "/etc/static/samba";
      };
    };
  };

  # ── NFS client support ──────────────────────────────────────────────────
  # Loads the NFS kernel module and pulls in nfs-utils so that GVfs can
  # mount NFS shares discovered via Nautilus → Network → nfs://host/export.
  boot.supportedFilesystems = [ "nfs" ];
}
