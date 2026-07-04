# modules/security-desktop.nix
# Desktop/HTPC/stateless security additions on top of modules/security.nix.
#
# Imported ONLY by configuration-desktop.nix, configuration-htpc.nix, and
# configuration-stateless.nix. Per the project's Option B pattern, this file
# contains NO lib.mkIf gating — its presence in the import list is what makes
# it apply.
#
# What it adds:
#   - fail2ban: brute-force mitigation for SSH. These roles run
#     services.openssh with password authentication left enabled
#     (modules/network.nix — a deliberate choice, not an oversight) on an
#     internet/LAN-reachable port 22, with no other protection against
#     repeated login attempts. Server and headless-server roles already get
#     this via modules/security-server.nix; this file closes the same gap
#     for the remaining roles that import modules/network.nix.
{ ... }:
{
  # NixOS automatically enables the sshd jail when both services.fail2ban
  # and services.openssh are enabled. Settings mirror
  # modules/security-server.nix exactly for consistency.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    # Recidive: escalating ban for repeat offenders across all jails.
    # Bans for 1 week after 3 bans in 1 day.
    jails.recidive = ''
      enabled   = true
      filter    = recidive
      maxretry  = 3
      findtime  = 86400
      bantime   = 604800
    '';
  };
}
