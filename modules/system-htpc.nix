# modules/system-htpc.nix
# HTPC background-job tuning: keep maintenance work away from playback.
#   - nix-gc, nix-optimise and fstrim run early Monday morning (04:00–05:00),
#     Persistent so a run missed while the box was off catches up at boot.
#   - Those services run at idle CPU and I/O priority, like the Nix daemon
#     itself (modules/nix.nix sets nix.daemonCPUSchedPolicy / daemonIOSchedClass
#     to "idle" for every role). nix-gc acts on the store directly as root, not
#     through the daemon, so it needs its own setting.
#   - No LocalSearch file indexer, no GNOME Software background update
#     downloads, no CUPS.
#
# Imported only by configuration-htpc.nix.
{ lib, ... }:
let
  idle = {
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass   = "idle";
  };
in
{
  # ── Maintenance schedule ──────────────────────────────────────────────────
  # nix-desktop.nix sets dates = "weekly" (Monday 00:00); same cadence, later hour.
  nix.gc.dates       = lib.mkForce "Mon *-*-* 04:00:00";
  nix.gc.persistent  = true;

  nix.optimise = {
    automatic  = true;
    dates      = [ "Mon *-*-* 04:30:00" ];
    persistent = true;
  };

  services.fstrim.interval = "Mon *-*-* 05:00:00";
  # util-linux's fstrim.timer adds RandomizedDelaySec=100min; drop it so the
  # trim stays in the early-morning window.
  systemd.timers.fstrim.timerConfig = {
    Persistent         = true;
    RandomizedDelaySec = "0";
  };

  # nix-optimise already runs idle (NixOS sets it in the unit).
  systemd.services.nix-gc.serviceConfig = idle;
  systemd.services.fstrim.serviceConfig = idle;

  # ── Background services ───────────────────────────────────────────────────
  # HTPC has the single auto-login user, so turning the indexer off system-wide
  # is the same as turning it off for that user.
  services.gnome.localsearch.enable = false;

  # desktop-common.nix (via gnome.nix) enables printing for every GNOME role.
  services.printing.enable = lib.mkForce false;

  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/software".download-updates = false;
    }
  ];
}
