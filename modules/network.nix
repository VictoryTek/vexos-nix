# modules/network.nix
# Networking: NetworkManager, Avahi/mDNS, firewall baseline, systemd-resolved.
# BBR TCP sysctl tuning is co-located with other kernel tunables in system.nix.
{ config, pkgs, lib, ... }:
{
  options.vexos.network.staticWired = lib.mkOption {
    type = lib.types.nullOr (lib.types.submodule {
      options = {
        address = lib.mkOption {
          type = lib.types.str;
          example = "192.168.1.10/24";
          description = "IPv4 address with prefix length (CIDR notation).";
        };
        gateway = lib.mkOption {
          type = lib.types.str;
          example = "192.168.1.1";
          description = "Default IPv4 gateway.";
        };
        dns = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "1.1.1.1" "9.9.9.9" ];
          description = "DNS server list. Joined with ';' in the NM keyfile.";
        };
      };
    });
    default = null;
    description = ''
      When non-null, writes a NetworkManager "wired-static" keyfile profile that
      assigns the given static IPv4 address to the first wired ethernet interface.
      The profile has no interface-name binding so it survives kernel-driven
      interface renames and nixos-rebuild switches.
      Priority is 10 — beats the wired-fallback DHCP profile (-999) and any
      ad-hoc manually-created profile (priority 0).
      Example (in hosts/<name>.nix):
        vexos.network.staticWired = {
          address = "192.168.1.10/24";
          gateway = "192.168.1.1";
          dns     = [ "192.168.1.1" "1.1.1.1" ];
        };
    '';
  };

  config = {
    # NetworkManager (primary network management daemon)
    networking.networkmanager.enable = true;

    # ── Prevent hardware-configuration.nix from stealing interfaces ───────────
    # NixOS has two networking backends: NetworkManager and the legacy scripted
    # backend (dhcpcd).  When both are active on the same interface, newer NM
    # versions mark the interface as "strictly unmanaged" — nmcli device set
    # managed yes is then blocked at the config level.
    #
    # Root cause: nixos-generate-config emits BOTH:
    #   networking.useDHCP = lib.mkDefault false;          ← global flag
    #   networking.interfaces.enp3s0.useDHCP = lib.mkDefault true;  ← per-iface
    #
    # The NixOS NM module correctly sets networking.useDHCP = false (plain),
    # but it DOES NOT touch per-interface useDHCP.  dhcpcd's enablement logic
    # (in dhcpcd.nix) is:
    #   enableDHCP = dhcpcd.enable && (useDHCP || any (i: i.useDHCP==true) ifaces)
    # So dhcpcd still starts for the specific NIC, conflicts with NM, and NM
    # marks it strictly unmanaged.
    #
    # Fix: force dhcpcd off entirely.  NM is the sole DHCP client; there is no
    # valid scenario where dhcpcd and NM should co-exist on this system.
    # lib.mkForce ensures hardware-configuration.nix cannot undo this.
    networking.useDHCP = lib.mkForce false;
    networking.dhcpcd.enable = lib.mkForce false;

    # ── Wired fallback profile ────────────────────────────────────────────────
    # A type-only profile with no interface-name binding.  NM activates it on
    # any wired ethernet interface that has no more-specific matching profile.
    #
    # Why this matters: linuxPackages_latest can rename interfaces between
    # kernel versions (e.g. eno1 → enp3s0).  Existing NM profiles bind by
    # interface name and stop matching after a rename; the NIC shows as
    # "unmanaged" in GNOME despite appearing in `ip a`.
    # hardware-configuration.nix's networking.interfaces.* entries are for the
    # legacy scripting backend — NetworkManager ignores them entirely.
    #
    # This profile is written to /etc/NetworkManager/system-connections/ via
    # the ensureProfiles activation service.  autoconnect-priority is set to
    # -999 so any host-specific or manually-created profile (priority 0) wins;
    # this profile only activates as a last resort.
    networking.networkmanager.ensureProfiles.profiles = lib.mkMerge [
      # Always-present DHCP fallback: activates on any wired interface with no
      # more-specific profile. Priority -999 ensures any manually-created or
      # host-specific profile wins.
      {
        "wired-fallback" = {
          connection = {
            id                   = "Wired Fallback";
            type                 = "ethernet";
            autoconnect          = "true";
            autoconnect-priority = "-999";
          };
          ipv4.method = "auto";
          ipv6 = {
            method        = "auto";
            addr-gen-mode = "stable-privacy";
          };
        };
      }
      # Optional static IP profile: activated when vexos.network.staticWired is set.
      # Survives nixos-rebuild switches and kernel-driven interface renames
      # (no interface-name binding). Priority 10 beats wired-fallback (-999)
      # and ad-hoc profiles (0).
      (lib.mkIf (config.vexos.network.staticWired != null) {
        "wired-static" = {
          connection = {
            id                   = "Wired Static";
            type                 = "ethernet";
            autoconnect          = "true";
            autoconnect-priority = "10";
          };
          ipv4 = {
            method   = "manual";
            address1 = "${config.vexos.network.staticWired.address},${config.vexos.network.staticWired.gateway}";
            dns      = lib.concatStringsSep ";" config.vexos.network.staticWired.dns;
          };
          ipv6 = {
            method        = "auto";
            addr-gen-mode = "stable-privacy";
          };
        };
      })
    ];

    # Default hostname — hosts/*.nix can override with a plain assignment.
    networking.hostName = lib.mkDefault "vexos";

    # ── mDNS / Avahi ─────────────────────────────────────────────────────────
    # Required for .local hostname resolution and AirPlay via PipeWire/Avahi.
    services.avahi = {
      enable       = true;
      nssmdns4     = true;     # enables mDNS resolution for .local in NSS
      openFirewall = true;     # opens UDP 5353 (mDNS)
      # Exclude the Tailscale VPN interface from mDNS.
      # mDNS is link-local (224.0.0.251); multicast sent on tailscale0
      # goes into the VPN tunnel, not the LAN.  When Avahi joins the
      # multicast group on tailscale0 it splits its socket attention
      # across eno1 + tailscale0, causing it to miss NAS advertisements
      # that arrive exclusively on the physical LAN interface.  Default
      # NixOS GNOME has no Tailscale interface — this is the exact delta
      # that broke auto-discovery in vexos.
      denyInterfaces = [ "tailscale0" ];
    };

    # ── Firewall baseline ─────────────────────────────────────────────────────
    networking.firewall = {
      enable = true;
      # Steam Remote Play ports are handled by programs.steam.remotePlay.openFirewall in gaming.nix.
    };

    # ── SSH server ───────────────────────────────────────────────────────────
    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin  = "no";
        PermitEmptyPasswords = "no";
        X11Forwarding    = false;
        MaxAuthTries     = lib.mkDefault "3";
        LoginGraceTime   = lib.mkDefault "30s";
        # PasswordAuthentication left at openssh default (enabled) so that
        # machines remain accessible without requiring key files in authorized_keys.
        # To harden a specific host: set PasswordAuthentication = false in hosts/<name>.nix
        # after confirming your public key is present and working.
      };
    };

    users.users.${config.vexos.user.name}.openssh.authorizedKeys.keyFiles =
      lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;

    # Redundant with services.openssh.openFirewall (default true), which
    # already opens port 22 whenever services.openssh.enable = true.

    # ── Tailscale ─────────────────────────────────────────────────────────────
    services.tailscale = {
      enable       = true;
      openFirewall = true;   # opens UDP 41641 (WireGuard/Tailscale data plane)
      # Do NOT accept subnet routes advertised by other nodes on the tailnet.
      # Without this, if any other Tailscale node advertises a subnet that
      # overlaps the local LAN (e.g. 192.168.100.0/24), the kernel installs a
      # policy route that sends all LAN traffic into the VPN — making every
      # LAN host unreachable even though the physical interface is up.
      extraUpFlags = [ "--accept-routes=false" ];
    };

    # The upstream NixOS tailscale module does not set a Restart policy;
    # systemd defaults to Restart=no.  Ensure the daemon auto-recovers from
    # transient failures (e.g. kernel WireGuard hiccups, DERP connectivity
    # drops) without operator intervention.
    systemd.services.tailscaled.serviceConfig.Restart = "on-failure";

    # ── DNS resolver ──────────────────────────────────────────────────────────
    services.resolved = {
      enable = true;
      # Disable resolved's built-in mDNS and LLMNR handlers so they don't
      # conflict with Avahi.  Without this, resolved and Avahi race on mDNS
      # multicast traffic (UDP 5353), causing Avahi's service browser to miss
      # NAS devices advertising _smb._tcp — the root cause of SMB shares not
      # appearing in Nautilus → Network.
      # Reference: https://wiki.archlinux.org/title/Avahi#Installation
      settings.Resolve = {
        DNSSEC       = "allow-downgrade";
        FallbackDNS  = "1.1.1.1 9.9.9.9";
        MulticastDNS = "no";
        LLMNR        = "no";
      };
    };

    # ── SMB / CIFS client ────────────────────────────────────────────────────
    # cifs-utils: provides mount.cifs — required to mount SMB/CIFS network shares
    #   Usage: sudo mount -t cifs //server/share /mnt/point -o username=user
    #   Or add to /etc/fstab with _netdev,credentials=/etc/samba/credentials
    # samba: provides smbclient CLI — browse and test SMB shares without mounting
    #   Usage: smbclient -L //server -U user
    # GNOME Files (Nautilus) browses SMB shares natively via GVfs (auto-enabled by GNOME).
    # No inbound firewall ports needed — client-only (outbound to TCP 445).
    environment.systemPackages = with pkgs; [
      cifs-utils  # mount.cifs — mount SMB/CIFS shares from CLI or fstab
    ];
  };
}