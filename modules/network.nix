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
}
