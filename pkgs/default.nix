# pkgs/default.nix
# vexos-nix custom package overlay.
# All custom packages are exposed under the `vexos` namespace
# (pkgs.vexos.<name>) to avoid future collisions with upstream nixpkgs.
# Wired into every nixosConfiguration via the `customPkgsOverlayModule`
# helper in flake.nix.
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
    portbook             = final.callPackage ./portbook { };
    # ── Packages requiring manual setup before use ───────────────────────────
    optional = {
      kiji-proxy         = final.callPackage ./kiji-proxy { };
    };
  };
}
