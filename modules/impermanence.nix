# modules/impermanence.nix
# Filesystem impermanence for the VexOS privacy role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behaviour (similar to Tails Linux / Deep Freeze).
#
# Disk layout (LUKS2 + Btrfs subvolumes) is handled declaratively by
# modules/privacy-disk.nix using disko. No manual hardware-configuration.nix
# edits are required. See .github/docs/subagent_docs/privacy_disk_spec.md.
#
# Run scripts/privacy-setup.sh on the NixOS ISO to format the disk before
# deploying any privacy host configuration.  The script sets up the required
# LUKS-encrypted Btrfs layout and calls nixos-install automatically.
{ config, lib, inputs, ... }:

let
  cfg = config.vexos.impermanence;
in
{
  # Conditionally pull in the upstream impermanence NixOS module.
  # Evaluated lazily: when cfg.enable = false (default) the upstream module
  # is never imported, leaving non-privacy builds entirely unaffected.
  imports = lib.optionals cfg.enable [
    inputs.impermanence.nixosModules.impermanence
  ];

  options.vexos.impermanence = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable tmpfs-rooted impermanence for the privacy role.
        When true, / is declared as a tmpfs mount by this module and all
        state outside /nix is ephemeral unless explicitly declared under
        environment.persistence.
        Disk layout is handled by modules/privacy-disk.nix (disko). The
        tmpfs root is declared by this module automatically when enabled.
      '';
    };

    persistentPath = lib.mkOption {
      type        = lib.types.str;
      default     = "/persistent";
      description = ''
        Mount point of the persistent storage volume.
        Must be declared with neededForBoot = true in
        hardware-configuration.nix so that impermanence bind mounts
        are available during early userspace initialisation.
      '';
    };

    extraPersistDirs = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = ''
        Additional system directories to bind-mount from persistent
        storage on each boot.  Appended to the base set managed by
        this module.  Example: [ "/var/lib/bluetooth" ]
      '';
    };

    extraPersistFiles = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = ''
        Additional system files to bind-mount from persistent storage
        on each boot.  Appended to the base set managed by this module.
        Example: [ "/etc/machine-id" ]
      '';
    };

  };

  config = lib.mkIf cfg.enable {

    # ── Ephemeral root (tmpfs) ──────────────────────────────────────────────
    # Declare / as a tmpfs mount. This is hardware-independent (no UUID).
    # Wiped on every reboot by design — this is the core of the privacy model.
    fileSystems."/" = {
      device  = lib.mkForce "none";
      fsType  = lib.mkForce "tmpfs";
      options = [ "defaults" "size=25%" "mode=755" ];
    };

    # ── Assertions ──────────────────────────────────────────────────────────
    assertions = [
      {
        assertion =
          (config.fileSystems ? "${cfg.persistentPath}") &&
          (config.fileSystems."${cfg.persistentPath}".neededForBoot or false);
        message = ''
          vexos.impermanence.enable = true requires
          fileSystems."${cfg.persistentPath}" to be declared with neededForBoot = true.
          This is normally satisfied automatically by modules/privacy-disk.nix.
          Check that privacy-disk.nix is imported in your privacy host file.
        '';
      }
      {
        assertion =
          (config.fileSystems ? "/") &&
          (config.fileSystems."/".fsType == "tmpfs");
        message = ''
          vexos.impermanence.enable = true requires fileSystems."/" to have
          fsType = "tmpfs". This is declared automatically by this module.
          If this assertion fails, another module is overriding fileSystems."/".
        '';
      }
    ];

    # ── Disable disk-backed swap (incompatible with tmpfs root) ────────────
    # /var/lib/swapfile lives on the ephemeral / and cannot survive a reboot.
    # ZRAM provides in-RAM compressed swap instead (see zramSwap below).
    vexos.swap.enable = lib.mkForce false;

    # ── Clean /tmp on boot ──────────────────────────────────────────────────
    # Belt-and-suspenders: / is already a fresh tmpfs on each boot, but
    # setting cleanOnBoot makes the ephemeral intent explicit.
    boot.tmp.cleanOnBoot = true;

    # ── Declarative user management ─────────────────────────────────────────
    # With tmpfs /, /etc/shadow is recreated from the Nix configuration on
    # every boot.  Passwords changed at runtime will not survive a reboot.
    # All users must declare initialPassword or hashedPassword in config.
    users.mutableUsers = false;

    # ── Volatile systemd journal ────────────────────────────────────────────
    # Logs are stored in RAM only and discarded on poweroff/reboot.
    # This eliminates forensic log artefacts on the persistent volume and
    # reduces writes to the LUKS-encrypted Btrfs partition.
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=64M
    '';

    # ── Suppress sudo lecture (resets on every reboot otherwise) ───────────
    security.sudo.extraConfig = ''
      Defaults lecture = never
    '';

    # ── Declarative persistence ─────────────────────────────────────────────
    # MINIMAL set — only what is strictly required for a functional NixOS
    # privacy system.  Everything else (home directories, logs, browser
    # history, caches, crash dumps, Bluetooth pairings, NetworkManager
    # connections) is ephemeral and discarded on every reboot.
    environment.persistence."${cfg.persistentPath}" = {

      # Hide bind mounts from GNOME Files and other file managers.
      hideMounts = true;

      directories =
        [
          # NixOS UID/GID tracking database.
          # Required for stable user identities when users.mutableUsers = false.
          # Without this, NixOS cannot reliably verify UIDs across activations.
          "/var/lib/nixos"

          # Everything below is intentionally OMITTED for the privacy role:
          #
          # NetworkManager connections — WiFi/VPN credentials are NOT saved.
          # Re-enter credentials each session for maximum privacy.
          # Uncomment to persist:
          # "/etc/NetworkManager/system-connections"
          #
          # Bluetooth pairings — devices must be re-paired each session.
          # Uncomment to persist:
          # "/var/lib/bluetooth"
        ]
        ++ cfg.extraPersistDirs;

      files =
        [
          # /etc/machine-id is intentionally NOT persisted (privacy default).
          # Persisting it would allow an adversary to correlate boots via
          # systemd journal, D-Bus, and other machine-id consumers.
          # Uncomment only if stable SSH known_hosts identity is required:
          # "/etc/machine-id"
        ]
        ++ cfg.extraPersistFiles;

      # User home directories are fully ephemeral by design.
      # GNOME settings, browser profiles, downloaded files, shell history,
      # and all application data are discarded on every reboot.
      #
      # To selectively persist user data, add entries such as:
      #   users.nimda.directories = [
      #     { directory = ".gnupg"; mode = "0700"; }
      #     { directory = ".ssh";   mode = "0700"; }
      #   ];
      #   users.nimda.files = [ ".config/monitors.xml" ];
    };

  };
}
