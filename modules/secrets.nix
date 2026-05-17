# modules/secrets.nix
# Permissions enforcement for /etc/nixos/secrets.
#
# Project services that need credentials read a secret file from this directory
# at runtime (e.g. nextcloud-admin-pass, minio-credentials, attic-credentials,
# photoprism-password).  Without explicit enforcement the directory is
# world-readable, exposing secrets to any process running as an unprivileged user.
#
# This module uses systemd-tmpfiles to:
#   • create /etc/nixos/secrets (0700 root:root) on first boot if absent
#   • re-apply the permissions on every activation (so an operator `chmod` won't
#     silently downgrade security)
#
# Individual secret files must be created manually before enabling the relevant
# service.  Use:
#   sudo install -m 0600 -o root -g root /dev/stdin /etc/nixos/secrets/<name>
#   <paste secret, then Ctrl-D>
#
# Future: replace this with sops-nix or agenix for declarative secrets at rest.

{ lib, ... }:

{
  # Ensure the secrets directory exists and is only accessible by root.
  systemd.tmpfiles.rules = [
    # d: create directory if absent; always apply the listed mode + owner.
    "d /etc/nixos/secrets 0700 root root -"
    # z: adjust permissions of any existing files directly inside the directory.
    #    This re-locks files an operator may have chmod'd to a wider mode.
    #    (Does not recurse into subdirectories.)
    "z /etc/nixos/secrets/* 0600 root root -"
  ];
}
