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
        workgroup             = "WORKGROUP";
        "server string"       = "NixOS";
        "server role"         = "standalone";
        "load printers"       = "no";
        # Explicitly allow SMB1 connections from this client.
        # Without this, Samba 4.13+ defaults to SMB2_02 minimum, which
        # prevents gvfsd-smb-browse and CLI tools from connecting to
        # NAS devices that only support SMBv1.
        "client min protocol" = "NT1";
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
  #
  # CRITICAL: gvfsd-wsdd (running as the desktop user) must connect to the
  # system wsdd socket at /run/wsdd/wsdd.sock to receive WSD responses from
  # NAS devices.  If it cannot connect it falls back to spawning its own wsdd
  # process, which competes with the system wsdd for the multicast socket on
  # UDP 3702.  Because the system wsdd already owns the socket, NAS responses
  # go to it and the user wsdd receives nothing — Nautilus "Network" stays
  # empty.  The system wsdd service runs as 'nobody' and systemd creates
  # /run/wsdd/ with mode 0700 (default RuntimeDirectoryMode), making it
  # inaccessible to the desktop user.  Setting 0755 makes the directory
  # traversable; wsdd itself sets the socket to 0666 via os.chmod().
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
    discovery    = true;
  };

  systemd.services.samba-wsdd.serviceConfig.RuntimeDirectoryMode = lib.mkForce "0755";

  # NOTE: /etc/samba/smb.conf is created by the NixOS samba module via
  # environment.etc."samba/smb.conf" (the standard NixOS etc.install
  # mechanism).  No manual symlink or tmpfiles rule is needed here; adding
  # one conflicts with etc.install and causes the entry to be marked
  # "obsolete" and removed on the next boot activation.

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
