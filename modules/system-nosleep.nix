# modules/system-nosleep.nix
# Permanently disable sleep, suspend, and hibernation.
# Import in configuration-desktop.nix, configuration-htpc.nix, and configuration-stateless.nix.
# Do NOT import in server or headless-server roles.
{ pkgs, lib, config, ... }:
{
  # ── Layer 4: mask all systemd sleep targets ───────────────────────────────
  # Creates /etc/systemd/system/<unit> -> /dev/null symlinks.
  # Prevents systemctl suspend/hibernate from ever activating.
  systemd.suppressedSystemUnits = [
    "sleep.target"
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];

  # ── Layer 3: systemd-sleep.conf ──────────────────────────────────────────
  # Placed in a drop-in directory so it doesn't replace /etc/systemd/sleep.conf.
  environment.etc."systemd/sleep.conf.d/no-sleep.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  # ── Layer 2: systemd-logind ──────────────────────────────────────────────
  # Prevents logind from initiating suspend on idle or on suspend/power key press.
  # HandleLidSwitch* included for completeness (harmless on desktops without a lid).
  # Note: services.logind.extraConfig was removed in NixOS 25.x; use settings.Login.
  # Note: lidSwitch/lidSwitchExternalPower/lidSwitchDocked are aliases for these same
  #       settings.Login keys; using both causes duplicate-definition conflicts, so we
  #       rely solely on settings.Login here.
  services.logind.settings.Login = {
    HandleSuspendKey             = "ignore";
    HandleHibernateKey           = "ignore";
    HandleLidSwitch              = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked        = "ignore";
    IdleAction                   = "ignore";
    IdleActionSec                = "0";
  };

  # ── Layer 1: GNOME power settings ────────────────────────────────────────
  # Set in the system dconf profile so they apply at session start (before
  # home-manager activation), which is critical on autoLogin systems.
  # These keys are NOT set anywhere else in this project, so no conflict arises.
  programs.dconf.profiles.user.databases = lib.mkBefore [
    {
      settings = {
        "org/gnome/settings-daemon/plugins/power" = {
          # Never sleep on AC or battery power regardless of idle time.
          sleep-inactive-ac-type         = "nothing";
          sleep-inactive-battery-type    = "nothing";
          sleep-inactive-ac-timeout      = lib.gvariant.mkInt32 0;
          sleep-inactive-battery-timeout = lib.gvariant.mkInt32 0;
          # Power button: do nothing (avoids accidental suspend on bare button press).
          power-button-action            = "nothing";
        };
      };
    }
  ];

  # ── Belt-and-suspenders: post-resume GNOME background reload ─────────────
  # Executes after resume IF sleep somehow gets through layers 1–4.
  # Toggles the wallpaper URI (picture-options zoom → stretch → zoom) to force
  # mutter's background actor to invalidate and repaint its texture cache.
  # Runs as the primary user; uses the stable systemd user D-Bus socket path.
  systemd.services."gnome-background-reload" = {
    description = "Reload GNOME background after resume (wallpaper corruption workaround)";
    after    = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nimda";
      Environment = [
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
        "HOME=/home/nimda"
      ];
      # Toggle picture-options to force a background repaint, then restore.
      ExecStart = pkgs.writeShellScript "gnome-bg-reload" ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options stretch
        sleep 1
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options zoom
      '';
    };
  };
}
