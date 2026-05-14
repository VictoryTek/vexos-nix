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
  # Runs wsdd as a system-level responder+discoverer that gvfsd-wsdd connects
  # to for NAS discovery in Nautilus → Network.
  #
  # CRITICAL — socket path: gvfsd-wsdd looks for the socket at the hardcoded
  # path /run/wsdd.socket (confirmed by strings on the gvfsd-wsdd binary).
  # The NixOS samba-wsdd module's default --listen path is /run/wsdd/wsdd.sock.
  # When gvfsd-wsdd cannot find /run/wsdd.socket it spawns its own wsdd with
  # --listen /run/user/<uid>/gvfsd/wsdd.  That user wsdd never receives WSD
  # responses because the system wsdd already owns the UDP 3702 multicast
  # socket.  Nautilus → Network stays empty as a result.
  # Fix: pass --listen /run/wsdd.socket to the system wsdd via extraOptions,
  # and make the socket world-readable/writable (UMask 0111, dir mode 0755)
  # so the desktop user can connect without group membership.
  services.samba-wsdd = {
    enable       = true;
    openFirewall = true;
    discovery    = true;
    # socket is created at /run/wsdd/wsdd.sock (default listen path)
  };

  systemd.services.samba-wsdd.serviceConfig = {
    RuntimeDirectoryMode = lib.mkForce "0755";
    UMask                = lib.mkOverride 0 "0111";
  };

  # gvfsd-wsdd hardcodes /run/wsdd.socket as the path to connect to.
  # The system wsdd daemon writes its socket to /run/wsdd/wsdd.sock.
  # Create a symlink so gvfsd-wsdd finds the socket without spawning
  # its own wsdd fallback (which can't receive responses because the
  # system wsdd already owns the UDP 3702 multicast socket).
  # /run/ is a tmpfs so this rule is re-applied every boot.
  systemd.tmpfiles.rules = [
    "L+ /run/wsdd.socket - - - - /run/wsdd/wsdd.sock"
  ];

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
