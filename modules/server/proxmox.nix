# modules/server/proxmox.nix
# Proxmox VE — open-source virtualisation platform (KVM VMs + LXC containers).
# Source: https://github.com/SaumonNet/proxmox-nixos
#
# Binary cache (avoids rebuilding Proxmox packages from source):
#   nix.settings.substituters       = [ "https://cache.saumon.network/proxmox-nixos" ];
#   nix.settings.trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
#
# ⚠ Experimental — not recommended for production machines.
# ⚠ The proxmox-nixos overlay (`proxmoxOverlayModule`) and the proxmox-ve NixOS
#   module are both applied at the flake level (in `roles.server/headless-server
#   .baseModules`). The overlay makes `pkgs.proxmox-ve` available; the NixOS
#   module defines `services.proxmox-ve.*` options. Neither needs re-applying here.
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

    bridgeInterface = lib.mkOption {
      type        = lib.types.str;
      default     = "";
      example     = "enp2s0";
      description = ''
        Name of the physical NIC to enslave into the vmbr0 bridge.
        vmbr0 is the standard Proxmox bridge — VMs and LXC containers attach
        to it for network access. Must be set when enable = true.
        Find the name with: ip link show
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.ipAddress != "";
        message   = "vexos.server.proxmox.ipAddress must be set to this host's IP address when vexos.server.proxmox.enable = true.";
      }
      {
        assertion = cfg.bridgeInterface != "";
        message   = "vexos.server.proxmox.bridgeInterface must be set to the physical NIC name (e.g. \"enp2s0\") when vexos.server.proxmox.enable = true.";
      }
    ];

    services.proxmox-ve = {
      enable    = true;
      ipAddress = cfg.ipAddress;
    };

    # ── vmbr0 bridge ─────────────────────────────────────────────────────────
    # Proxmox VMs and LXC containers attach to vmbr0 for network access.
    # The physical NIC is enslaved into the bridge; the bridge itself gets the
    # DHCP lease. NetworkManager is told to leave both interfaces unmanaged so
    # it doesn't fight the kernel bridge stack.
    networking.bridges.vmbr0.interfaces = [ cfg.bridgeInterface ];

    networking.interfaces.vmbr0.useDHCP              = lib.mkDefault true;
    networking.interfaces.${cfg.bridgeInterface}.useDHCP = false;

    # NetworkManager must not manage the physical NIC or the bridge — if it
    # does it will race with the kernel bridge and drop the DHCP lease.
    networking.networkmanager.unmanaged = [ cfg.bridgeInterface "vmbr0" ];

    # Allow the kernel to forward packets between the bridge and VM tap interfaces.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward"          = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
