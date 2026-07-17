# modules/server/storage-remote.nix
# Remote storage pool client — the "remote" NAS tier.
#
# For deployments where the storage pool lives on a SEPARATE host (a dedicated
# NAS / storage server) and this box is app-only. Declares NFS or CIFS/SMB
# client mounts of pools exported by another machine, so services here
# (Jellyfin, Nextcloud media, the *arr stack, etc.) can read/write a remote
# pool exactly as they would a local one.
#
# Orthogonal to the local backend: a host may use a local ZFS/mergerfs pool,
# attach one or more remote pools, or both. Populated by
# `just attach-remote-storage` into /etc/nixos/storage-pool.nix.
#
# Persistence via NixOS fileSystems (NixOS generates /etc/fstab). Mounts use
# _netdev + nofail + x-systemd.automount so a slow/absent storage server never
# blocks boot — the share mounts lazily on first access instead.
#
# Per the Option B module pattern: options + config, active only when at least
# one remote mount is declared. Inert (empty list) otherwise.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.storage.remote;

  remoteModule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "nfs" "cifs" ];
        description = "Remote protocol: nfs or cifs (SMB).";
      };
      server = lib.mkOption {
        type = lib.types.str;
        example = "192.168.1.10";
        description = "Host or IP of the storage server exporting the pool.";
      };
      export = lib.mkOption {
        type = lib.types.str;
        example = "/tank/media";
        description = ''
          NFS export path (e.g. "/tank/media") or CIFS share name (e.g. "media").
        '';
      };
      mountPoint = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/nas-media";
        description = "Local mountpoint for the remote pool.";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/etc/nixos/secrets/nas-credentials";
        description = ''
          CIFS only: absolute path (on the host, NOT a Nix path — kept out of
          the store) to a file containing `username=` / `password=` lines.
          Required for cifs; ignored for nfs.
        '';
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Override mount options. When empty, resilient per-protocol defaults
          are used (_netdev, nofail, x-systemd.automount, timeouts).
        '';
      };
    };
  };

  hasNfs  = lib.any (r: r.type == "nfs")  cfg;
  hasCifs = lib.any (r: r.type == "cifs") cfg;

  baseOpts = [ "_netdev" "nofail" "x-systemd.automount" "x-systemd.mount-timeout=30" "noatime" ];

  effectiveOptions = r:
    if r.options != [ ] then r.options
    else if r.type == "nfs" then [ "nfsvers=4.2" ] ++ baseOpts
    else [ "credentials=${toString r.credentialsFile}" "iocharset=utf8" ] ++ baseOpts;

  remoteFileSystems = builtins.listToAttrs (map (r: {
    name = r.mountPoint;
    value = {
      device = if r.type == "nfs" then "${r.server}:${r.export}" else "//${r.server}/${r.export}";
      fsType = if r.type == "nfs" then "nfs" else "cifs";
      options = effectiveOptions r;
    };
  }) cfg);
in
{
  options.vexos.server.storage.remote = lib.mkOption {
    type = lib.types.listOf remoteModule;
    default = [ ];
    description = ''
      Remote storage pools (NFS/CIFS) to mount from another host. Populated by
      `just attach-remote-storage`.
    '';
  };

  config = lib.mkIf (cfg != [ ]) {
    assertions = [
      {
        assertion = lib.all (r: r.type != "cifs" || r.credentialsFile != null) cfg;
        message = ''
          Every cifs entry in vexos.server.storage.remote must set
          credentialsFile (an absolute host path to a username=/password= file).
          Anonymous or inline-plaintext CIFS credentials are not allowed.
        '';
      }
    ];

    boot.supportedFilesystems =
      lib.optional hasNfs "nfs" ++ lib.optional hasCifs "cifs";

    environment.systemPackages =
      lib.optional hasNfs pkgs.nfs-utils ++ lib.optional hasCifs pkgs.cifs-utils;

    fileSystems = remoteFileSystems;
  };
}
