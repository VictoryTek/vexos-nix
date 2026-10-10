# modules/storage-remote.nix
# Remote storage pool client — the "remote" NAS tier. Universal module: imported
# by every role that supports attaching a network share (desktop, htpc, server,
# headless-server). Inert until at least one mount is declared.
#
# Declares NFS or CIFS/SMB client mounts of shares exported by another machine
# (a NAS unit, another vexos host, ...) so local software — media services on a
# server, or just a file manager on a desktop — can read/write a remote share
# exactly as it would a local disk, without hand-editing /etc/fstab.
#
# Orthogonal to any local backend: a host may use a local ZFS/mergerfs pool,
# attach one or more remote shares, or both. Populated by
# `just remote-storage attach` into /etc/nixos/storage-remote.nix.
#
# Persistence via NixOS fileSystems (NixOS generates /etc/fstab). Mounts use
# _netdev + nofail + x-systemd.automount so a slow/absent storage server never
# blocks boot — the share mounts lazily on first access instead.
#
# Per the Option B module pattern: options + config, active only when at least
# one remote mount is declared. Inert (empty list) otherwise.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.storage.remote;

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
      gid = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 3000;
        description = ''
          Numeric group id on the NAS that has write access to this share. When
          set, a shared local `media` group with this gid is declared (all
          mounts must use the same gid) and the media service users join it.
          CIFS: also mounted with gid=/file_mode=0664/dir_mode=0775 so the
          group can write. NFS: ownership is decided by the server, so the
          export must grant this group write access (e.g. TrueNAS Mapall
          User/Group, or a dataset ACL).
        '';
      };
      uid = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          CIFS only, applied together with `gid`: mount with uid=<uid> so files
          appear owned by this local user id (default: root).
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
  gids    = lib.unique (lib.filter (g: g != null) (map (r: r.gid) cfg));

  baseOpts = [ "_netdev" "nofail" "x-systemd.automount" "x-systemd.mount-timeout=30" "noatime" ];

  # Group-write ownership for CIFS (the kernel client fakes ownership from
  # mount options). NFS has no such options — ownership comes from the server.
  cifsOwnership = r: lib.optionals (r.gid != null) (
    [ "gid=${toString r.gid}" "file_mode=0664" "dir_mode=0775" ]
    ++ lib.optional (r.uid != null) "uid=${toString r.uid}"
  );

  effectiveOptions = r:
    if r.options != [ ] then r.options
    else if r.type == "nfs" then [ "nfsvers=4.2" ] ++ baseOpts
    else [ "credentials=${toString r.credentialsFile}" "iocharset=utf8" ] ++ cifsOwnership r ++ baseOpts;

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
  # Back-compat: the option lived at vexos.server.storage.remote while this was
  # a server-only module. Any already-deployed /etc/nixos/storage-remote.nix
  # still using the old path keeps evaluating (with a deprecation warning) until
  # it is regenerated by `just remote-storage attach`.
  imports = [
    (lib.mkRenamedOptionModule
      [ "vexos" "server" "storage" "remote" ]
      [ "vexos" "storage" "remote" ])
  ];

  options.vexos.storage.remote = lib.mkOption {
    type = lib.types.listOf remoteModule;
    default = [ ];
    description = ''
      Remote storage shares (NFS/CIFS) to mount from another host. Populated by
      `just remote-storage attach`.
    '';
  };

  config = lib.mkIf (cfg != [ ]) {
    assertions = [
      {
        assertion = lib.all (r: r.type != "cifs" || r.credentialsFile != null) cfg;
        message = ''
          Every cifs entry in vexos.storage.remote must set
          credentialsFile (an absolute host path to a username=/password= file).
          Anonymous or inline-plaintext CIFS credentials are not allowed.
        '';
      }
      {
        assertion = lib.length gids <= 1;
        message = ''
          Every vexos.storage.remote entry that sets `gid` must use the same
          value (they share one local `media` group). Found: ${lib.concatMapStringsSep ", " toString gids}.
        '';
      }
    ];

    # One shared group for every media service user (see the extraGroups lines
    # in modules/server/{arr,plex,jellyfin,audiobookshelf}.nix).
    users.groups = lib.mkIf (gids != [ ]) {
      media.gid = lib.head gids;
    };

    boot.supportedFilesystems =
      lib.optional hasNfs "nfs" ++ lib.optional hasCifs "cifs";

    environment.systemPackages =
      lib.optional hasNfs pkgs.nfs-utils ++ lib.optional hasCifs pkgs.cifs-utils;

    fileSystems = remoteFileSystems;
  };
}
