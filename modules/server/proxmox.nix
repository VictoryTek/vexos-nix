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

    # ── vmbr0 bridge — managed by NetworkManager ────────────────────────────
    # NetworkManager creates vmbr0 as a bridge, slaves the physical NIC into
    # it, and obtains the DHCP lease on vmbr0 via NM's internal DHCP client.
    #
    # Why NM profiles (not scripted networking / dhcpcd):
    #   network.nix forces networking.dhcpcd.enable = lib.mkForce false to
    #   prevent dhcpcd/NM conflicts on every role.  networking.interfaces.*.useDHCP
    #   is a dhcpcd directive — it is completely inert when dhcpcd is off.
    #   NM is the sole DHCP client on this system; vmbr0 must be managed by NM.
    #
    # Why no networking.networkmanager.unmanaged entry:
    #   The previous code marked both interfaces unmanaged to prevent NM from
    #   racing with dhcpcd.  With NM as the only client, unmanaged is wrong —
    #   it would leave vmbr0 with no IP address.
    #
    # Why no networking.bridges.vmbr0:
    #   networking.bridges uses scripted networking (ip link) to create the
    #   bridge.  Having both scripted networking and NM create the same bridge
    #   races at boot.  NM creates the bridge when it activates the master
    #   profile; scripted networking is not needed.
    networking.networkmanager.ensureProfiles.profiles = {
      # Bridge master: NM creates vmbr0 and obtains a DHCP lease on it.
      "vmbr0-bridge" = {
        connection = {
          id             = "vmbr0 Bridge";
          type           = "bridge";
          interface-name = "vmbr0";
          autoconnect    = "true";
        };
        ipv4 = {
          method = "auto";
        };
        ipv6 = {
          method        = "auto";
          addr-gen-mode = "stable-privacy";
        };
      };

      # Bridge slave: NM enslaves the physical NIC into vmbr0.
      # The physical NIC carries no IP address; all traffic goes through the bridge.
      "vmbr0-slave" = {
        connection = {
          id             = "vmbr0 Port ${cfg.bridgeInterface}";
          type           = "ethernet";
          interface-name = cfg.bridgeInterface;
          controller     = "vmbr0";
          port-type      = "bridge";
          autoconnect    = "true";
        };
      };
    };

    # ── Firewall ────────────────────────────────────────────────────────────
    # 8006 = Proxmox web UI / API
    # 8007 = VNC/SPICE websocket proxy (noVNC console)
    networking.firewall.allowedTCPPorts = [ 8006 8007 ];

    # Allow the kernel to forward packets between the bridge and VM tap interfaces.
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward"          = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };
  };
}
