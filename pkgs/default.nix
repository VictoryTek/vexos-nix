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
    # ── Browsers ────────────────────────────────────────────────────────────
    brave-origin         = final.callPackage ./brave-origin { };
    # ── AI & Privacy ────────────────────────────────────────────────────────
    kiji-proxy           = final.callPackage ./kiji-proxy { };
    # ── System ──────────────────────────────────────────────────────────────
    vexos-update         = final.callPackage ./vexos-update { };
    vexos-vpn            = final.callPackage ./vexos-vpn { };     # PIA WireGuard/OpenVPN + kill switch CLI
    # ── Utilities ───────────────────────────────────────────────────────────
    tmog                 = final.callPackage ./tmog { };
    # ── Development ─────────────────────────────────────────────────────────
    t3code               = final.callPackage ./t3code { };
    # ── Flatpak bundles (release assets, not on Flathub) ────────────────────
    # pkgs.vexos.craft-apps.<name>.{appId,version,bundle}; installed by
    # modules/flatpak-bundles.nix. Plain import (not callPackage) so the set is
    # exactly the apps in pins.json — callPackage would add override attrs that
    # break iteration (the update workflow maps over it).
    craft-apps           = import ./craft-apps { inherit (final) lib fetchurl; };
    # ── Kernels ─────────────────────────────────────────────────────────────
    # Registry of custom kernels (pkgs.vexos.kernels.<name>). Built by the
    # opt-in kernel-builder service and served over Harmonia; see
    # pkgs/kernels/default.nix for how to add another.
    kernels              = final.callPackage ./kernels { };
  };
}
