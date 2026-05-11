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
# NOTE: cockpit-zfs (Phase B) is deferred — upstream v1.2.26 uses a
# Yarn Berry v4 monorepo with unresolved workspace: deps in the zfs/
# package-lock.json, making sandbox builds infeasible without upstream
# changes. Revisit when cockpit-zfs lands in nixpkgs or upstream ships
# a self-contained lockfile. Phase C (cockpit-file-sharing) is next.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.cockpit;
in
{
  options.vexos.server.cockpit = {
    enable = lib.mkEnableOption "Cockpit web management console";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for the Cockpit web interface.";
    };

    navigator.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-navigator file-browser plugin.
        Defaults to the value of vexos.server.cockpit.enable so that
        enabling Cockpit also installs Navigator (the simplest plugin)
        — set to false to opt out, or to true on its own to stage the
        package without enabling Cockpit (no effect at runtime).
      '';
    };

    fileSharing.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      description = ''
        Install the 45Drives cockpit-file-sharing plugin and configure
        Samba (registry mode) + NFS server for GUI-managed file sharing.
        Defaults to the value of vexos.server.cockpit.enable.
        Requires vexos.server.cockpit.enable = true (enforced by assertion).
      '';
    };

  };

  config = lib.mkMerge [

    # ── Base Cockpit daemon ────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      services.cockpit = {
        enable = true;
        port = cfg.port;
        openFirewall = true;
      };
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
        openFirewall = true;  # TCP 139, 445; UDP 137, 138
        settings.global = {
          "include" = "registry";
        };
      };

      # ── NFS — server enabled, exports managed by plugin ───────────────────
      # The plugin writes to /etc/exports.d/cockpit-file-sharing.exports.
      # NixOS manages /etc/exports (symlink); /etc/exports.d/ is separate.
      # nfsd reads both locations when exportfs -r is invoked by the plugin.
      services.nfs.server.enable = true;

      # /etc/exports.d/ may not exist by default; create it as a writable dir.
      systemd.tmpfiles.rules = [
        "d /etc/exports.d 0755 root root -"
      ];

      # NFS firewall ports: 2049 (nfsd), 111 (rpcbind/portmapper).
      # lockd/mountd/statd use ephemeral ports by default; pin them if the
      # host firewall is restrictive (operator concern, not defaulted here).
      networking.firewall = {
        allowedTCPPorts = [ 2049 111 ];
        allowedUDPPorts = [ 2049 111 ];
      };

    })

  ];
}

