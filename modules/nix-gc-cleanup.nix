# modules/nix-gc-cleanup.nix
# Extra cleanup that runs right after the weekly nix-gc job finishes:
#   - journalctl --vacuum-time=14d
#   - docker image prune of unused images older than 14 days (only on hosts
#     where virtualisation.docker.enable is true; never touches containers,
#     volumes or networks, and `-a` only removes images no container uses).
#
# Runs as ExecStartPost with a "-" prefix, so a failure here never marks
# nix-gc.service as failed. Each step logs what it freed to the nix-gc journal.
{ config, lib, pkgs, ... }:
let
  docker = config.virtualisation.docker;
  cleanup = pkgs.writeShellScript "nix-gc-cleanup" (''
    echo "Vacuuming journal entries older than 14 days"
    ${config.systemd.package}/bin/journalctl --vacuum-time=14d \
      || echo "journal vacuum failed (exit $?)"
  '' + lib.optionalString docker.enable ''
    echo "Pruning unused Docker images older than 14 days"
    ${docker.package}/bin/docker image prune -af --filter "until=336h" \
      || echo "docker image prune failed (exit $?)"
  '');
in
{
  systemd.services.nix-gc.serviceConfig.ExecStartPost = "-${cleanup}";
}
