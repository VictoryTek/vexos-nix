# modules/sunshine.nix
# Self-hosted Moonlight game-stream host, alongside GNOME Remote Desktop
# (modules/remote-desktop.nix) — not a replacement.
#
# Imported by: configuration-desktop.nix, configuration-server.nix, configuration-htpc.nix
# NOT imported by: configuration-stateless.nix (tmpfs home — Sunshine's paired-client
# state does not persist across reboots without extra impermanence config, same
# rationale as remote-desktop.nix)
#
# Runs as a systemd --user service tied to graphical-session.target — starts
# automatically with the auto-login session. No keyring dependency, no root
# service, no credential file: pairing is a one-time PIN exchange via the WebUI
# (https://<host>:47990), which has no declarative/scriptable equivalent — see
# `just enable-sunshine`.
#
# capture = "kms": on GNOME/Mutter (non-wlroots) Wayland, KMS is the only
# reliably-working capture path — the portal-based path has multiple open
# upstream issues specific to GNOME (LizardByte/Sunshine#2838, #1631). Requires
# capSysAdmin (cap_sys_admin capability wrapper, applied by the NixOS module).
#
# GPU-specific `services.sunshine.settings.encoder` is set per-brand in
# modules/gpu/*.nix, not here — see those files.
{ config, lib, ... }:
{
  services.sunshine = {
    enable      = true;
    autoStart   = true;
    capSysAdmin = true;
    openFirewall = true;
    settings.capture = "kms";
  };

  # Required for Sunshine to inject mouse/keyboard input as the remote client;
  # the NixOS module enables hardware.uinput itself but does not grant any user
  # access to it.
  users.users.${config.vexos.user.name}.extraGroups = [ "uinput" ];
}
