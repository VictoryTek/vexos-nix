# modules/impermanence.nix
# Filesystem impermanence for the VexOS stateless role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behaviour (similar to Tails Linux / Deep Freeze).
#
# Disk layout (plain Btrfs with @nix and @persist subvolumes) is declared by
# modules/stateless-disk.nix. No LUKS encryption is used.
#
# Two setup paths are supported:
#   Fresh install from ISO: run scripts/stateless-setup.sh (formats disk, calls nixos-install).
#   Existing system migration: run scripts/migrate-to-stateless.sh (in-place Btrfs subvol setup).
# No LUKS — disk layout is plain Btrfs with @nix and @persist subvolumes.
{ config, lib, pkgs, ... }:

let
  cfg = config.vexos.impermanence;
in
{
  options.vexos.impermanence = {

    enable = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = ''
        Enable tmpfs-rooted impermanence for the stateless role.
        When true, / is declared as a tmpfs mount by this module and all
        state outside /nix is ephemeral unless explicitly declared under
        environment.persistence.
        Disk layout (Btrfs subvolumes @nix/@persist) is declared by
        modules/stateless-disk.nix. The tmpfs root is declared by this module
        automatically when enabled.
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

  options.vexos.variant = lib.mkOption {
    type        = lib.types.str;
    default     = "";
    description = ''
      Active build variant name (e.g. "vexos-stateless-amd").
      When set and vexos.impermanence.enable = true, the value is written
      directly to /persistent/etc/nixos/vexos-variant at activation time,
      bypassing the timing race between the NixOS etc activation and the
      impermanence bind mount for /etc/nixos.
    '';
  };

  config = lib.mkIf cfg.enable {

    # ── Ephemeral root (tmpfs) ──────────────────────────────────────────────
    # Declare / as a tmpfs mount. This is hardware-independent (no UUID).
    # Wiped on every reboot by design — this is the core of the stateless model.
    fileSystems."/" = {
      device  = lib.mkForce "none";
      fsType  = lib.mkForce "tmpfs";
      options = lib.mkForce [ "defaults" "size=25%" "mode=755" ];
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
          This is normally satisfied automatically by modules/stateless-disk.nix.
          For fresh installs: run scripts/stateless-setup.sh from the NixOS live ISO.
          For existing systems: run scripts/migrate-to-stateless.sh to migrate in-place.
        '';
      }
      {
        assertion =
          (config.fileSystems ? "/nix") &&
          (config.fileSystems."/nix".neededForBoot or false);
        message = ''
          vexos.impermanence.enable = true requires fileSystems."/nix" to be declared
          with neededForBoot = true.  This is normally satisfied automatically by
          modules/stateless-disk.nix when vexos.stateless.disk.enable = true.
          If this assertion fails, hardware-configuration.nix is defining
          fileSystems."/nix" without neededForBoot = true at a priority that
          overrides the stateless-disk.nix default.
          Fix: add `neededForBoot = true;` to fileSystems."/nix" in
          /etc/nixos/hardware-configuration.nix, or re-run
          scripts/migrate-to-stateless.sh to regenerate it correctly.
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

    # ── Declarative user management ─────────────────────────────────────────
    # With tmpfs /, /etc/shadow is recreated from the Nix configuration on
    # every boot.  Passwords changed at runtime will not survive a reboot.
    # All users must declare initialPassword or hashedPassword in config.
    users.mutableUsers = false;

    # ── Volatile systemd journal ────────────────────────────────────────────
    # Logs are stored in RAM only and discarded on poweroff/reboot.
    # This eliminates forensic log artefacts on the persistent volume and
    # reduces writes to the persistent Btrfs partition.
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
    # stateless system.  Everything else (home directories, logs, browser
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

          # Flatpak app/runtime store, Flathub remote registration, and install
          # stamps.  Without persistence, / is a tmpfs so flatpak has no real
          # disk space to write to, and every reboot triggers a full reinstall.
          "/var/lib/flatpak"

          # Thin flake wrapper + hardware-configuration.nix must survive reboots
          # so that `just rebuild`, `just update`, and `nixos-rebuild` work after
          # boot without re-downloading the config.  vexos-variant is written as a
          # plain file by system.activationScripts (in the /etc/nixos wrapper flake)
          # on every activation after impermanence bind-mounts this directory, so it
          # lands in persistent storage.  flake.nix and hardware-configuration are
          # NOT managed that way and would be lost on reboot without this entry.
          "/etc/nixos"

          # Everything below is intentionally OMITTED for the stateless role:
          #
          # NetworkManager connections — WiFi/VPN credentials are NOT saved.
          # Re-enter credentials each session for maximum stateless.
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
          # /etc/machine-id is intentionally NOT persisted (stateless default).
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

    # ── Variant file persistence (write directly to persistent subvolume) ─────
    # When vexos.variant is set, write the variant name to the persistent
    # subvolume path directly, bypassing the bind-mount timing race between
    # NixOS etc activation and the impermanence mount for /etc/nixos.
    # /persistent is mounted in initrd (before systemd stage 2) and is always
    # available when activationScripts run.
    system.activationScripts.vexosVariant = lib.mkIf (config.vexos.variant != "") {
      deps = [ "etc" ];
      text = ''
        PERSIST_DIR="${cfg.persistentPath}/etc/nixos"
        ${pkgs.coreutils}/bin/mkdir -p "$PERSIST_DIR"
        ${pkgs.coreutils}/bin/printf '%s' '${config.vexos.variant}' \
          > "$PERSIST_DIR/vexos-variant"
      '';
    };

  };
}
