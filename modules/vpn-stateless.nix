# modules/vpn-stateless.nix
# Stateless-role addition to modules/vpn.nix: the VPN connects at boot and the
# kill switch is always on (loaded before any network interface comes up).
# Only imported by configuration-stateless.nix.
{ ... }:
{
  vexos.vpn.autoConnect = true;
  vexos.vpn.killSwitch.mode = "always";

  # Credentials (root-only), chosen region/protocol, cached PIA server list and
  # the 24 h API token survive reboots; / is tmpfs on this role.
  vexos.impermanence.extraPersistDirs = [ "/var/lib/vexos-vpn" ];
}
