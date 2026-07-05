# modules/server/cockpit.nix
# Cockpit — web-based Linux server management UI, plus optional
# 45Drives plugin sub-options.
#
# Plugin discovery: Cockpit at the pinned nixpkgs rev does NOT expose a
# services.cockpit.plugins option (that machinery post-dates this pin).
# Plugins are surfaced via XDG_DATA_DIRS — any package on
# environment.systemPackages whose $out/share/cockpit/<name>/manifest.json
# exists is auto-discovered, because the cockpit module itself sets
# environment.pathsToLink = [ "/share/cockpit" ]. See:
#   .github/docs/subagent_docs/nas_phase_a_cockpit_navigator_spec.md
#
# NOTE: cockpit-zfs (Phase B) is deferred. Re-checked at this repo's pinned
# nixpkgs rev (2026-07): pkgs.cockpit-zfs now exists (1.2.27-3, not marked
# meta.broken) — the original Yarn Berry v4 workspace: deps blocker is gone.
# But `nix build` against it still fails: a Tailwind/PostCSS error in the
# shared @45drives/houston-common-ui workspace
# ("[vite:css] [postcss] Cannot convert undefined or null to object" in
# ToggleSwitchGroup.vue's scoped style compilation) aborts the whole
# workspace build before cockpit-zfs itself builds. Revisit when this
# upstream CSS build bug is fixed. Phase C (cockpit-file-sharing) is next.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;

  defaultAllowedCidrs = [
    "127.0.0.1/32"
    "::1/128"
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "fc00::/7"
  ];

  firewalldEnabled = lib.attrByPath [ "services" "firewalld" "enable" ] false config;
  hasInterfaceScopes = cfg.firewall.interfaces != [ ];
  useInterfaceScopedRules = hasInterfaceScopes && !firewalldEnabled;

  cockpitTcpPorts = lib.optional cfg.enable cfg.port;

  sambaTcpPorts =
    if cfg.fileSharing.enable
    then [ 445 ] ++ lib.optional cfg.fileSharing.samba.enableNetbios 139
    else [ ];

  sambaUdpPorts =
    if cfg.fileSharing.enable && cfg.fileSharing.samba.enableNetbios
    then [ 137 138 ]
    else [ ];

  nfsV3TcpPorts = [
    111
    2049
    cfg.fileSharing.nfs.mountdPort
    cfg.fileSharing.nfs.lockdPort
    cfg.fileSharing.nfs.statdPort
  ];

  nfsV3UdpPorts = nfsV3TcpPorts;

  nfsTcpPorts =
    if !cfg.fileSharing.enable then [ ]
    else if cfg.fileSharing.nfs.profile == "v3-compatible" then nfsV3TcpPorts
    else [ 2049 ];

  nfsUdpPorts =
    if !cfg.fileSharing.enable then [ ]
    else if cfg.fileSharing.nfs.profile == "v3-compatible" then nfsV3UdpPorts
    else [ ];

  serviceFirewallTcpPorts = lib.unique (cockpitTcpPorts ++ sambaTcpPorts ++ nfsTcpPorts);
  serviceFirewallUdpPorts = lib.unique (sambaUdpPorts ++ nfsUdpPorts);

  scopedFirewallRules = lib.genAttrs cfg.firewall.interfaces (_: {
    allowedTCPPorts = serviceFirewallTcpPorts;
    allowedUDPPorts = serviceFirewallUdpPorts;
  });

  sambaAllowedHosts = lib.concatStringsSep " " cfg.firewall.allowedCidrs;
  sambaInterfaces = lib.concatStringsSep " " cfg.firewall.interfaces;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Cockpit web interface.";
    };

    firewall.interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "eno1" ];
      description = ''
        Interface names to scope Cockpit file-sharing firewall rules to.
        When empty, rules are applied globally and a warning is emitted.
      '';
    };

    firewall.allowedCidrs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultAllowedCidrs;
      example = [ "192.168.1.0/24" "fd00:1234::/64" ];
      description = ''
        CIDR allowlist used for Samba "hosts allow". Defaults to
        localhost, RFC1918 IPv4 private ranges, and IPv6 ULA.
      '';
    };

    navigator.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the 45Drives cockpit-navigator file-browser plugin.
        Defaults to false. When vexos.server.cockpit.enable = true,
        this option is set to lib.mkDefault true so enabling Cockpit
        also installs Navigator by default. Set to false to opt out,
        or to true on its own to stage the package (no runtime effect
        until Cockpit itself is enabled).
      '';
    };

    fileSharing.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the 45Drives cockpit-file-sharing plugin and configure
        Samba (registry mode) + NFS server for GUI-managed file sharing.
        Defaults to false. When vexos.server.cockpit.enable = true,
        this option is set to lib.mkDefault true.
        Requires vexos.server.cockpit.enable = true (enforced by assertion).
      '';
    };

    fileSharing.samba.enableNetbios = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable legacy NetBIOS ports for Samba (TCP 139, UDP 137/138).
        Disabled by default to reduce exposed surface.
      '';
    };

    fileSharing.samba.bindInterfacesOnly = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Set Samba "bind interfaces only" to yes when true.
        Keep enabled unless you intentionally need broad bind behavior.
      '';
    };

    fileSharing.nfs.profile = lib.mkOption {
      type = lib.types.enum [ "v4-minimal" "v3-compatible" ];
      default = "v4-minimal";
      description = ''
        NFS exposure profile. "v4-minimal" only opens TCP 2049.
        "v3-compatible" opens rpcbind and fixed auxiliary ports.
      '';
    };

    fileSharing.nfs.mountdPort = lib.mkOption {
      type = lib.types.port;
      default = 20048;
      description = "Fixed mountd port used when nfs.profile = \"v3-compatible\".";
    };

    fileSharing.nfs.lockdPort = lib.mkOption {
      type = lib.types.port;
      default = 4001;
      description = "Fixed lockd port used when nfs.profile = \"v3-compatible\".";
    };

    fileSharing.nfs.statdPort = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Fixed statd port used when nfs.profile = \"v3-compatible\".";
    };

    identities.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the 45Drives cockpit-identities plugin (user and group
        management GUI — Linux users, Samba passwords, groups, SSH keys,
        login history). Defaults to false. When
        vexos.server.cockpit.enable = true, this option is set to
        lib.mkDefault true so enabling Cockpit also installs Identities
        by default. Set to false to opt out, or to true on its own to
        stage the package (no runtime effect until Cockpit is enabled).
      '';
    };

  };

  config = lib.mkMerge [

    # ── Parent-enabled sub-plugin defaults ───────────────────────────────
    (lib.mkIf cfg.enable {
      vexos.server.cockpit.navigator.enable = lib.mkDefault true;
      vexos.server.cockpit.fileSharing.enable = lib.mkDefault true;
      vexos.server.cockpit.identities.enable = lib.mkDefault true;
    })

    # ── Base Cockpit daemon ────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable = true;
        port = cfg.port;
        openFirewall = false;
      };
    })

    # ── Firewall surface controls ─────────────────────────────────────────
    (lib.mkIf (cfg.enable && !hasInterfaceScopes) {
      warnings = [
        ''
          vexos.server.cockpit.firewall.interfaces is empty, so Cockpit/
          file-sharing firewall rules are applied globally. Set explicit
          interface names to reduce exposure on multi-network hosts.
        ''
      ];
    })

    (lib.mkIf (cfg.enable && hasInterfaceScopes && firewalldEnabled) {
      warnings = [
        ''
          vexos.server.cockpit.firewall.interfaces is set while firewalld is
          enabled. networking.firewall.interfaces scoping is not applied with
          firewalld backend; falling back to global allowed ports.
        ''
      ];
    })

    (lib.mkIf (cfg.enable && useInterfaceScopedRules) {
      networking.firewall.interfaces = scopedFirewallRules;
    })

    (lib.mkIf (cfg.enable && !useInterfaceScopedRules) {
      networking.firewall.allowedTCPPorts = serviceFirewallTcpPorts;
      networking.firewall.allowedUDPPorts = serviceFirewallUdpPorts;
    })

    # ── Navigator plugin ───────────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.navigator.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-navigator ];
    })

    # ── File-sharing plugin (Samba + NFS) ──────────────────────────────────
    (lib.mkIf cfg.fileSharing.enable {

      assertions = [
        {
          assertion = cfg.fileSharing.enable -> cfg.enable;
          message = ''
            vexos.server.cockpit.fileSharing.enable = true requires
            vexos.server.cockpit.enable = true.
          '';
        }
      ];

      # Plugin package — provides /share/cockpit/file-sharing/manifest.json
      # which Cockpit auto-discovers via environment.pathsToLink.
      environment.systemPackages = [
        pkgs.vexos.cockpit-file-sharing
        # samba package needed for 'net' (registry management) and 'smbpasswd'
        # on $PATH. services.samba.enable does not add these to systemPackages.
        pkgs.samba
      ];

      # ── Samba — registry mode ─────────────────────────────────────────────
      # The file-sharing plugin manages shares via 'net conf' commands, which
      # write to Samba's TDB registry (not to smb.conf). The 'include =
      # registry' line in [global] tells smbd to load share definitions from
      # the registry at startup — the NixOS-generated smb.conf (immutable
      # store symlink) and the mutable TDB registry coexist without conflict.
      #
      # configText and extraConfig are removed at the pinned rev; use settings.
      services.samba = {
        enable = true;
        openFirewall = false;
        settings.global =
          {
            "include" = "registry";
            "bind interfaces only" = if cfg.fileSharing.samba.bindInterfacesOnly then "yes" else "no";
            "hosts allow" = sambaAllowedHosts;
          }
          // lib.optionalAttrs hasInterfaceScopes {
            "interfaces" = sambaInterfaces;
          };
      };

      # ── NFS — server enabled, exports managed by plugin ───────────────────
      # The plugin writes to /etc/exports.d/cockpit-file-sharing.exports.
      # NixOS manages /etc/exports (symlink); /etc/exports.d/ is separate.
      # nfsd reads both locations when exportfs -r is invoked by the plugin.
      services.nfs.server =
        {
          enable = true;
        }
        // lib.optionalAttrs (cfg.fileSharing.nfs.profile == "v3-compatible") {
          mountdPort = cfg.fileSharing.nfs.mountdPort;
          lockdPort = cfg.fileSharing.nfs.lockdPort;
          statdPort = cfg.fileSharing.nfs.statdPort;
        };

      # /etc/exports.d/ may not exist by default; create it as a writable dir.
      systemd.tmpfiles.rules = [
        "d /etc/exports.d 0755 root root -"
      ];

    })

    # ── Identities plugin ─────────────────────────────────────────────────
    (lib.mkIf (cfg.enable && cfg.identities.enable) {
      environment.systemPackages = [ pkgs.vexos.cockpit-identities ];
    })

  ];
}

