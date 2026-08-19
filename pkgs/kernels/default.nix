# pkgs/kernels/default.nix
# Registry of custom kernels built by this project.
#
# Adding a kernel is a directory plus one line here — nothing else changes.
# The builder service (modules/server/kernel-builder.nix), the client module
# (modules/system-custom-kernel.nix) and the nightly CI workflow all read this
# registry, so a new entry is picked up by all three automatically.
#
# Each entry must be a *kernel derivation* (not a package set); consumers wrap
# it with linuxPackagesFor. Exposed as pkgs.vexos.kernels.<name> via
# pkgs/default.nix.
{ callPackage }:
{
  ogc = callPackage ./ogc { };
}
