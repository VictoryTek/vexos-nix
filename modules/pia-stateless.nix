# modules/pia-stateless.nix
# Stateless-role addition for PIA VPN.
#
# Migration note: PIA is now managed declaratively via pkgs.vexos.pia-client-bin.
# The Nix store path is read-only and does not require persistence.
#
# This directory entry persists the legacy /opt/piavpn path only for hosts that
# still have PIA installed via the old installer (pre-nixified migration window).
# Once all stateless hosts have been rebuilt with the nixified package and the
# legacy /opt/piavpn directory has been removed, this file can be deleted and
# its import removed from configuration-stateless.nix.
#
# This file must only be imported by configuration-stateless.nix.
# modules/pia.nix provides the universal prerequisites for all roles.
{ ... }:
{
  vexos.impermanence.extraPersistDirs = [ "/opt/piavpn" ];
}
