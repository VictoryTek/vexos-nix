# modules/server/proxmox.nix
# Proxmox VE — open-source virtualisation platform (KVM VMs + LXC containers).
# Source: https://github.com/SaumonNet/proxmox-nixos
#
# Binary cache (avoids rebuilding Proxmox packages from source):
#   nix.settings.substituters       = [ "https://cache.saumon.network/proxmox-nixos" ];
#   nix.settings.trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
#
# ⚠ Experimental — not recommended for production machines.
# ⚠ The proxmox-nixos overlay is applied by the proxmox-ve NixOS module imported
#   at the flake level (serverBase / headlessServerBase) — it does not need to be
#   re-applied here.
#
# Impermanence note: if running on the stateless role, add /var/lib/pve-cluster
# to your persistence directories to survive reboots with the cluster config intact.
{ config, lib, ... }:
let
  cfg = config.vexos.server.proxmox;
in
{
  # Note: inputs.proxmox-nixos.nixosModules.proxmox-ve is imported at the
  # flake level (serverBase / headlessServerBase) to avoid infinite recursion
  # — using `inputs` in `imports` here triggers _module.args evaluation before
  # config is available.

  options.vexos.server.proxmox = {
    enable = lib.mkEnableOption "Proxmox VE hypervisor";

    ipAddress = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      description = ''
        IP address of this host. Used by Proxmox VE for cluster communication
        and the web-UI TLS certificate. Must be set when enable = true.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ipAddress != "";
        message   = "vexos.server.proxmox.ipAddress must be set to this host's IP address when vexos.server.proxmox.enable = true.";
      }
    ];

    services.proxmox-ve = {
      enable    = true;
      ipAddress = cfg.ipAddress;
    };
  };
}
