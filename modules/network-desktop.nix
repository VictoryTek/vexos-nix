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
    addresses    = true;
    workstation  = true;
    userServices = true;
    domain       = true;   # publishes _browse._dns-sd._udp.local —
                           # parity with stock GNOME-on-NixOS, which
                           # publishes the browse domain via gvfs's
                           # own avahi calls.
  };

  # ── WS-Discovery (WSDD) — RESPONDER + DISCOVERY ─────────────────────────
  # Runs wsdd as a system-level responder+discoverer. Announces this host to
  # Windows/Samba clients and provides a discovery socket for gvfsd-wsdd.
  # GVFS also spawns its own per-user wsdd (--no-host --discovery) as a
  # fallback if the system socket isn't reachable at /run/wsdd.socket.
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
    discovery    = true;
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

  # ── NetBIOS conntrack helper ────────────────────────────────────────────
  # Traditional SMB browsing (gvfsd-smb-browse / libsmbclient) sends
  # broadcast queries on UDP 137.  Replies arrive from different source IPs
  # than the broadcast destination, so the firewall's conntrack doesn't
  # recognise them as RELATED — they're silently dropped.  This rule loads
  # the netbios-ns conntrack helper so replies are correctly tracked.
  # Reference: https://wiki.archlinux.org/title/Samba#%22Browsing%22_network_fails_with_%22Failed_to_retrieve_share_list_from_server%22
  networking.firewall.extraCommands = ''
    iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns
  '';
}
