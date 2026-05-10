# modules/network.nix
# Networking: NetworkManager, Avahi/mDNS, firewall baseline, systemd-resolved.
# BBR TCP sysctl tuning is co-located with other kernel tunables in performance.nix.
{ config, pkgs, lib, ... }:
{
  # NetworkManager (primary network management daemon)
  networking.networkmanager.enable = true;

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
