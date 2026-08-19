# pkgs/kernels/ogc/default.nix
# Open Gaming Collective kernel, packaged for NixOS.
#
# OGC (formed Jan 2026) unifies the kernel patch sets of Bazzite, ChimeraOS,
# Nobara, PikaOS, Playtron, ASUS Linux and others into one upstream-first tree.
# Members: https://opengamingcollective.org
#
# Packaging approach — follows nixpkgs' own third-party-kernel pattern
# (pkgs/os-specific/linux/kernel/xanmod-kernels.nix): define our own `version`
# and `src` and hand them to buildLinux, rather than layering onto whichever
# kernel nixpkgs currently ships.
#
# This matters: OGC publishes its releases as *tags on an already-patched
# stable tree* (github.com/OpenGamingCollective/linux), so there is nothing to
# apply — no patch step, and no need for the OGC base version to match
# nixpkgs' kernel version. The `monolithic.patch` published alongside each
# release is a review artifact for seeing what OGC changed; it is deliberately
# not consumed here.
#
# version.json is machine-written by
# .github/workflows/update-kernels-nightly.yml — do NOT hand-edit it. Clients
# and the builder must agree on the exact same derivation for the binary cache
# to be hit instead of the kernel being compiled locally.
{ lib
, buildLinux
, fetchFromGitHub
, ...
} @ args:

let
  pin = lib.importJSON ./version.json;
in
buildLinux (args // {
  inherit (pin) version modDirVersion;
  pname = "linux-ogc";

  src = fetchFromGitHub {
    owner = "OpenGamingCollective";
    repo = "linux";
    rev = pin.tag;
    inherit (pin) hash;
  };

  # Intentionally empty: pin.tag already points at the patched tree.
  kernelPatches = [ ];

  structuredExtraConfig = import ./config.nix { inherit lib; };

  extraMeta = {
    branch = lib.versions.majorMinor pin.version;
    description = "Open Gaming Collective kernel (${pin.tag})";
    homepage = "https://github.com/OpenGamingCollective/linux";
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
} // (args.argsOverride or { }))
