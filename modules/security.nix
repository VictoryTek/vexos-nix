# modules/security.nix
# Universal Mandatory Access Control baseline (AppArmor).
#
# This module is imported by every role (desktop, htpc, stateless, server,
# headless-server). It contains only settings that are safe and desirable on
# ALL roles. Per-role additions live in modules/security-<qualifier>.nix.
#
# Design notes:
#   - The NixOS apparmor module sets boot.kernelParams = [ "apparmor=1"
#     "security=apparmor" ] automatically when security.apparmor.enable = true,
#     so we deliberately do NOT add anything to modules/system.nix.
#   - killUnconfinedConfinables stays false: enabling it would terminate any
#     binary that has a profile shipped but is launched outside the profiled
#     path. Several upstream profiles in apparmor-profiles match common util
#     paths and would surprise-kill user processes (Wine launchers, dev tools).
#     Complain/enforce posture is controlled per-profile via security.apparmor.policies.
#   - apparmor-profiles is the upstream profile bundle (ntpd, dnsmasq,
#     libvirtd, tcpdump, identd, mdnsd, evince, etc.). Including the package
#     here registers all of its profiles with the AppArmor cache.
#   - apparmor-utils provides aa-status, aa-complain, aa-enforce, aa-logprof,
#     aa-genprof — required for any practical diagnosis.
{ pkgs, lib, ... }:
{
  security.apparmor = {
    enable = true;

    # Pre-compile profile cache at build time → faster boot, atomic updates.
    enableCache = true;

    # Do NOT kill processes that have a profile shipped but are running
    # unconfined. Critical for Steam/Proton/Wine/gamemode and for any
    # third-party tool whose path doesn't match an upstream profile glob.
    killUnconfinedConfinables = false;

    # Bring in the upstream nixpkgs profile bundle. Individual profiles can
    # be flipped to "complain" or "disable" below if a regression is found.
    packages = [ pkgs.apparmor-profiles ];

    # Default policy posture: every profile registered above runs in enforce
    # mode. Override on a per-profile basis here if a regression appears.
    # Example:
    #   policies."bin.ping" = "complain";
    policies = { };
  };

  # Diagnostic tooling — universal so any host can run aa-status and
  # aa-logprof during incident response.
  environment.systemPackages = [ pkgs.apparmor-utils ];
}
