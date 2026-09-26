# lib/server-service-names.nix
# The authoritative list of server service names, derived from the option
# declarations in modules/server/ rather than maintained by hand.
#
# Reads only `options`, never `config`. That matters twice over:
#
#   • It is immune to a host's /etc/nixos/server-services.nix — including one
#     that names a service which no longer exists, which is precisely the
#     situation this list is used to diagnose.
#   • It sidesteps the read/write cycle on `vexos.server` that 40 service
#     modules create through vexos.server.backup.servicePaths.<name>, which
#     makes any config-level approach recurse infinitely.
#
# Adding or deleting a module under modules/server/ updates this list on its
# own. Nothing else needs editing.
#
# _module.check is disabled because this evaluation deliberately supplies no
# real NixOS module set — it exists only to read option names. It is a
# throwaway evalModules, never a real configuration.
{ lib, pkgs }:

let
  evaluated = lib.evalModules {
    specialArgs = {
      inherit pkgs;
      inputs = { };
      utils = { };
    };
    modules = [
      { _module.check = false; }
      ../modules/server/default.nix
    ];
  };
in
builtins.attrNames
  (lib.filterAttrs (n: _: !(lib.hasPrefix "_" n)) evaluated.options.vexos.server)
