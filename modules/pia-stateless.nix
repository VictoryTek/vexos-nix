# modules/pia-stateless.nix
# Stateless-role addition for PIA VPN.
#
# Persists /opt/piavpn across reboots on tmpfs-rooted (impermanence) systems.
# PIA's installer writes to /opt/piavpn; without persistence, that path is
# wiped on every boot because / is a tmpfs on the stateless role.
#
# This file must only be imported by configuration-stateless.nix.
# modules/pia.nix provides the universal prerequisites for all roles.
{ ... }:
{
  vexos.impermanence.extraPersistDirs = [ "/opt/piavpn" ];
}
