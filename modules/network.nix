# modules/network.nix
# Networking: NetworkManager, Avahi/mDNS, firewall baseline, systemd-resolved.
# BBR TCP sysctl tuning is co-located with other kernel tunables in performance.nix.
{ config, pkgs, lib, ... }:
{
  # NetworkManager (primary network management daemon)
  networking.networkmanager.enable = true;

  # ── mDNS / Avahi ─────────────────────────────────────────────────────────
  # Required for .local hostname resolution and AirPlay via PipeWire/Avahi.
  services.avahi = {
    enable       = true;
    nssmdns4     = true;     # enables mDNS resolution for .local in NSS
    openFirewall = true;     # opens UDP 5353 (mDNS)
  };

  # ── Firewall baseline ─────────────────────────────────────────────────────
  networking.firewall = {
    enable = true;
    # Steam Remote Play ports are handled by programs.steam.remotePlay.openFirewall in gaming.nix.
  };

  # ── DNS resolver ──────────────────────────────────────────────────────────
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
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
    samba       # smbclient — browse/test SMB shares; also provides nmblookup
  ];
}
