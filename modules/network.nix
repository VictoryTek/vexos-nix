# modules/network.nix
# Networking: NetworkManager, Avahi/mDNS, firewall baseline, systemd-resolved.
# BBR TCP sysctl tuning is co-located with other kernel tunables in performance.nix.
{ config, pkgs, lib, ... }:
{
  # NetworkManager (primary network management daemon)
  networking.networkmanager.enable = true;

  # ── Prevent hardware-configuration.nix from stealing interfaces ───────────
  # NixOS has two networking backends: NetworkManager and the legacy scripted
  # backend (dhcpcd).  When both are active on the same interface, newer NM
  # versions mark the interface as "strictly unmanaged" — nmcli device set
  # managed yes is then blocked at the config level.
  #
  # Root cause: nixos-generate-config emits BOTH:
  #   networking.useDHCP = lib.mkDefault false;          ← global flag
  #   networking.interfaces.enp3s0.useDHCP = lib.mkDefault true;  ← per-iface
  #
  # The NixOS NM module correctly sets networking.useDHCP = false (plain),
  # but it DOES NOT touch per-interface useDHCP.  dhcpcd's enablement logic
  # (in dhcpcd.nix) is:
  #   enableDHCP = dhcpcd.enable && (useDHCP || any (i: i.useDHCP==true) ifaces)
  # So dhcpcd still starts for the specific NIC, conflicts with NM, and NM
  # marks it strictly unmanaged.
  #
  # Fix: force dhcpcd off entirely.  NM is the sole DHCP client; there is no
  # valid scenario where dhcpcd and NM should co-exist on this system.
  # lib.mkForce ensures hardware-configuration.nix cannot undo this.
  networking.useDHCP = lib.mkForce false;
  networking.dhcpcd.enable = lib.mkForce false;

  # ── Wired fallback profile ────────────────────────────────────────────────
  # A type-only profile with no interface-name binding.  NM activates it on
  # any wired ethernet interface that has no more-specific matching profile.
  #
  # Why this matters: linuxPackages_latest can rename interfaces between
  # kernel versions (e.g. eno1 → enp3s0).  Existing NM profiles bind by
  # interface name and stop matching after a rename; the NIC shows as
  # "unmanaged" in GNOME despite appearing in `ip a`.
  # hardware-configuration.nix's networking.interfaces.* entries are for the
  # legacy scripting backend — NetworkManager ignores them entirely.
  #
  # This profile is written to /etc/NetworkManager/system-connections/ via
  # the ensureProfiles activation service.  autoconnect-priority is set to
  # -999 so any host-specific or manually-created profile (priority 0) wins;
  # this profile only activates as a last resort.
  networking.networkmanager.ensureProfiles.profiles."wired-fallback" = {
    connection = {
      id                   = "Wired Fallback";
      type                 = "ethernet";
      autoconnect          = "true";
      autoconnect-priority = "-999";
    };
    ipv4.method = "auto";
    ipv6 = {
      method        = "auto";
      addr-gen-mode = "stable-privacy";
    };
  };

  # ── Wired static IP profile ───────────────────────────────────────────────
  # Declares the server's static IP configuration as a NM keyfile profile so
  # that it survives nixos-rebuild switches and kernel-driven interface renames.
  # Because the profile has no interface-name binding, NM matches it by
  # connection type (ethernet) and priority — it will activate on whatever the
  # physical NIC is called after a rename, so the static address is never lost
  # from mutable NM state.  Replace all PLACEHOLDER_* values with the actual
  # network settings for this host before enabling; leave commented out until
  # the values are filled in.
  #
  # networking.networkmanager.ensureProfiles.profiles."wired-static" = {
  #   connection = {
  #     id                   = "Wired Static";
  #     type                 = "ethernet";
  #     autoconnect          = "true";
  #     autoconnect-priority = "10";   # beats wired-fallback (-999) and ad-hoc (0)
  #   };
  #   ipv4 = {
  #     method    = "manual";
  #     addresses = "PLACEHOLDER_IP/PLACEHOLDER_PREFIX";  # e.g. "192.168.1.10/24"
  #     gateway   = "PLACEHOLDER_GATEWAY";                # e.g. "192.168.1.1"
  #     dns       = "PLACEHOLDER_DNS1;PLACEHOLDER_DNS2";  # e.g. "1.1.1.1;9.9.9.9"
  #   };
  #   ipv6 = {
  #     method        = "auto";
  #     addr-gen-mode = "stable-privacy";
  #   };
  # };

  # Default hostname — hosts/*.nix can override with a plain assignment.
  networking.hostName = lib.mkDefault "vexos";

  # ── mDNS / Avahi ─────────────────────────────────────────────────────────
  # Required for .local hostname resolution and AirPlay via PipeWire/Avahi.
  services.avahi = {
    enable       = true;
    nssmdns4     = true;     # enables mDNS resolution for .local in NSS
    openFirewall = true;     # opens UDP 5353 (mDNS)
    # Exclude the Tailscale VPN interface from mDNS.
    # mDNS is link-local (224.0.0.251); multicast sent on tailscale0
    # goes into the VPN tunnel, not the LAN.  When Avahi joins the
    # multicast group on tailscale0 it splits its socket attention
    # across eno1 + tailscale0, causing it to miss NAS advertisements
    # that arrive exclusively on the physical LAN interface.  Default
    # NixOS GNOME has no Tailscale interface — this is the exact delta
    # that broke auto-discovery in vexos.
    denyInterfaces = [ "tailscale0" ];
  };

  # ── Firewall baseline ─────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    # Steam Remote Play ports are handled by programs.steam.remotePlay.openFirewall in gaming.nix.
  };

  # ── SSH server ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Tailscale ─────────────────────────────────────────────────────────────
  services.tailscale = {
    enable = true;
    openFirewall = true;   # opens UDP 41641 (WireGuard/Tailscale data plane)
  };

  # ── DNS resolver ──────────────────────────────────────────────────────────
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
    # Disable resolved's built-in mDNS and LLMNR handlers so they don't
    # conflict with Avahi.  Without this, resolved and Avahi race on mDNS
    # multicast traffic (UDP 5353), causing Avahi's service browser to miss
    # NAS devices advertising _smb._tcp — the root cause of SMB shares not
    # appearing in Nautilus → Network.
    # Reference: https://wiki.archlinux.org/title/Avahi#Installation
    extraConfig = ''
      MulticastDNS=no
      LLMNR=no
    '';
  };

  # ── SMB / CIFS client ────────────────────────────────────────────────────
  # cifs-utils: provides mount.cifs — required to mount SMB/CIFS network shares
  #   Usage: sudo mount -t cifs //server/share /mnt/point -o username=user
  #   Or add to /etc/fstab with _netdev,credentials=/etc/samba/credentials
  # samba: provides smbclient CLI — browse and test SMB shares without mounting
  #   Usage: smbclient -L //server -U user
  # GNOME Files (Nautilus) browses SMB shares natively via GVfs (auto-enabled by GNOME).
  # No inbound firewall ports needed — client-only (outbound to TCP 445).
  environment.systemPackages = with pkgs; [
    cifs-utils  # mount.cifs — mount SMB/CIFS shares from CLI or fstab
  ];
}
