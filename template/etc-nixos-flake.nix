# /etc/nixos/flake.nix
# Thin wrapper — hardware-configuration.nix stays here; full system config
# is pulled automatically from GitHub on every rebuild.
#
# ── One-time setup (per machine) ────────────────────────────────────────────
#
#   1. Download this file:
#        sudo curl -fsSL -o /etc/nixos/flake.nix \
#          https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/template/etc-nixos-flake.nix
#
#   2. Apply using the variant that matches your hardware:
#
#      Desktop role (full gaming/workstation stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy580    (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm
#
#      Stateless role (minimal stack, no gaming/dev/virt/ASUS modules):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia-legacy580  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-vm
#
#      GUI Server role (GNOME desktop + service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia-legacy580     (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-vm
#
#      Headless Server role (CLI only service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia-legacy580  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-vm
#
#      HTPC role (media centre build):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia-legacy580       (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-vm
#
#      Vanilla role (stock NixOS baseline — no desktop, no gaming, no branding):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-nvidia-legacy580  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-vm
#
#      No editing required — all variants are exposed automatically.
#      The chosen variant is written to /etc/nixos/vexos-variant on every
#      build so vexos-updater always knows which target to use.
#
# ── All future rebuilds / updates ───────────────────────────────────────────
#
#   Manually:
#     sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
#
#   Via vexos-updater app:
#     The app reads /etc/nixos/vexos-variant and builds the command for you.
#
# ── Switching to a different variant later (e.g. vm → amd) ──────────────────
#
#   Just rebuild with the new variant target:
#     sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd
#   /etc/nixos/vexos-variant is updated automatically — vexos-updater picks
#   up the new variant from then on.
#
# ── Per-machine settings live in side-files, not in this file ───────────────
#
#   This wrapper is never edited by the installer or by `just` recipes. Each
#   optional file below is imported only when it exists next to this flake:
#
#     bootloader.nix     BIOS/GRUB or Limine (default: systemd-boot, from
#                        modules/system.nix — no file needed)
#                          { vexos.bootloader = "grub"; vexos.grub.device = "/dev/sda"; }
#                          { vexos.bootloader = "limine"; }
#                        Do not switch an installed machine to Limine by hand —
#                        use `just switch-bootloader limine`, which also handles
#                        the systemd-boot NVRAM entry and ESP file cleanup.
#     hardware-local.nix ASUS ROG/TUF options (or OpenRGB for ASUS desktops)
#                          { vexos.hardware.asus.enable = true; }
#     host.nix           networking.hostId — server and headless-server only
#     hostname.nix       networking.hostName, written by `just set-hostname`
#     vm-platform.nix    vexos.vm.platform = "virtualbox" (default: "qemu" —
#                        no file needed)
#     user-override.nix  nimda's initial login password, written by a fresh
#                        bare-metal install (scripts/bare-metal-install.sh) —
#                        not used by the stateless role, which has its own
#                        stateless-user-override.nix instead
#
{
  inputs = {
    vexos-nix.url = "github:VictoryTek/vexos-nix";

    # Pin nixpkgs to the same version used by the upstream config.
    nixpkgs.follows = "vexos-nix/nixpkgs";
  };

  outputs = { self, vexos-nix, nixpkgs }:
  let
    lib = nixpkgs.lib;

    # ── Bootloader ──────────────────────────────────────────────────────────
    # Default is systemd-boot, set by modules/system.nix (vanilla: its own
    # mkDefault), so nothing is declared here. Written by install.sh for
    # BIOS/GRUB or opt-in Limine, and by `just switch-bootloader`.
    # Boot entry title cleanup (strip kernel version, codename, date) is
    # handled automatically by modules/branding.nix in the upstream config.
    bootloaderFile = ./bootloader.nix;
    hasBootloader  = builtins.pathExists bootloaderFile;

    # ── Per-machine hardware overrides ──────────────────────────────────────
    # Written by the installer for hardware-specific features (ASUS ROG/TUF).
    hardwareLocalFile = ./hardware-local.nix;
    hasHardwareLocal  = builtins.pathExists hardwareLocalFile;

    # ── ZFS host identity (required for server and headless-server roles) ────
    # ZFS bakes this ID into every pool's vdev label at creation time.
    # It must be unique per machine and must not change after pools are created,
    # so install.sh writes host.nix once and never overwrites it. Without it the
    # build aborts on the assertion in modules/zfs-server.nix.
    hostFile = ./host.nix;
    hasHost  = builtins.pathExists hostFile;

    # ── Persisted hostname ──────────────────────────────────────────────────
    # Written by `just set-hostname` so the name survives rebuilds.
    hostnameFile = ./hostname.nix;
    hasHostname  = builtins.pathExists hostnameFile;

    # ── Optional VM guest platform selector ────────────────────────────────────
    # Written by bare-metal-install.sh / migrate-to-stateless.sh for VirtualBox
    # guests (QEMU is the vexos.vm.platform default and needs no file). Declared
    # by modules/gpu/vm-guest-additions.nix, reachable from any role's `vm`
    # variant, so this is a universal side-file (localFiles below) rather than
    # bundled with features.nix — features.nix isn't imported by
    # headless-server/vanilla, which have `vm` variants too.
    vmPlatformFile = ./vm-platform.nix;
    hasVmPlatform  = builtins.pathExists vmPlatformFile;

    # ── Optional initial login password (non-stateless roles) ─────────────────
    # Written once by a fresh bare-metal install (scripts/bare-metal-install.sh)
    # for the roles that don't already have their own mechanism. The stateless
    # role keeps its separate, pre-existing stateless-user-override.nix instead
    # (see mkStatelessVariant) — modules/users.nix declares nimda with no
    # password at all, so every other role needs this too for a fresh install to
    # actually be usable; an already-installed host re-running install.sh never
    # touches this file.
    userOverrideFile = ./user-override.nix;
    hasUserOverride  = builtins.pathExists userOverrideFile;

    # Side-files every role loads when present. host.nix is added separately by
    # the two server builders — ZFS hostId is meaningless elsewhere.
    localFiles =
      lib.optional hasBootloader    bootloaderFile
      ++ lib.optional hasHardwareLocal hardwareLocalFile
      ++ lib.optional hasHostname   hostnameFile
      ++ lib.optional hasVmPlatform vmPlatformFile
      ++ lib.optional hasUserOverride userOverrideFile;

    # ── Kernel install override (written by installer for cache-miss fallback) ──
    # When the installer detects that target-kernel packages are not in cache,
    # it writes kernel-install-override.nix to fall back to linuxPackages
    # (channel default, always fully cached).  vexos-update removes the file
    # automatically once the target kernel packages land in cache.
    # To upgrade manually: delete the file and run: just update
    kernelOverrideFile = ./kernel-install-override.nix;
    hasKernelOverride  = builtins.pathExists kernelOverrideFile;

    # ── Optional per-host feature toggles ──────────────────────────────────────
    # Written by `just enable-feature <feature>` / `just disable-feature <feature>`.
    # Covers gaming, development, print3d, and virtualization opt-in toggles.
    # Not applicable to stateless, headless-server, or vanilla roles.
    featuresFile = ./features.nix;
    hasFeatures  = builtins.pathExists featuresFile;

    # ── Optional generated storage config ─────────────────────────────────────
    # storage-pool.nix — mergerfs branches + SnapRAID parity, server roles only,
    #   written by `just create-mergerfs-pool`.
    # storage-remote.nix — remote NFS/CIFS mounts, written by
    #   `just attach-remote-storage`; wired on desktop, htpc, server and
    #   headless-server (the remote-mount module is universal).
    storagePoolFile = ./storage-pool.nix;
    hasStoragePool  = builtins.pathExists storagePoolFile;
    storageRemoteFile = ./storage-remote.nix;
    hasStorageRemote  = builtins.pathExists storageRemoteFile;

    # ── Optional generated ZFS pool registration (server roles) ────────────────
    # Written by `just create-zfs-pool`: declares boot.zfs.extraPools so NixOS
    # generates a zfs-import-<pool>.service unit and the pool auto-imports on boot.
    zfsPoolsFile = ./zfs-pools.nix;
    hasZfsPools  = builtins.pathExists zfsPoolsFile;

    # ── Variant builder ─────────────────────────────────────────────────────
    # Constructs a complete NixOS configuration for a given variant.
    # • hostname   → the variant name, also written to /etc/nixos/vexos-variant
    # • gpuModule  → GPU-specific drivers for this variant (single module or list)
    #
    # Normalises gpuModule to accept either a single module or a list of modules.
    # Shared builder helper — used by both mkVariant and mkStatelessVariant.
    _mkVariantWith = baseModule: variant: gpuModule: nixpkgs.lib.nixosSystem {
      modules =
        let
          # Convert to list if necessary, preserving backward compatibility
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }

          # hardware-configuration.nix is generated by nixos-generate-config and
          # lives in /etc/nixos — it is never committed to the vexos-nix repo.
          ./hardware-configuration.nix

          # System stack from the upstream vexos-nix flake.
          baseModule

          # GPU-specific drivers and settings for this variant.
        ] ++ modules
          ++ localFiles
          ++ lib.optional hasFeatures       featuresFile
          ++ lib.optional hasStorageRemote  storageRemoteFile
          ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

    # Desktop role: full gaming/workstation stack.
    mkVariant = _mkVariantWith vexos-nix.nixosModules.base;

    # Stateless role: minimal stack (no gaming/dev/virt/ASUS modules).
    # Uses an explicit builder (rather than _mkVariantWith) so it can
    # conditionally include a machine-local stateless-user-override.nix when
    # present — its own separate mechanism, not the generic user-override.nix
    # every other role uses (localFiles above). Generated by
    # bare-metal-install.sh / migrate-to-stateless.sh at install time. Without
    # that file the account is locked (hashedPassword = "!") — the setup
    # scripts MUST be run before the first boot.
    mkStatelessVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          # Optional per-machine user override (password, etc.). Deliberately
          # named/pathed differently from the outer userOverrideFile: this one
          # is stateless-specific (see comment above).
          # Generated by bare-metal-install.sh / migrate-to-stateless.sh at
          # install time.  Without that file the compiled-in default is a
          # locked account (hashedPassword = "!") — the setup scripts must run
          # before first use.
          statelessUserOverrideFile = ./stateless-user-override.nix;
          hasStatelessUserOverride  = builtins.pathExists statelessUserOverrideFile;
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          { vexos.variant = variant; }
          ./hardware-configuration.nix
          vexos-nix.nixosModules.statelessBase
        ]
        ++ modules
        ++ localFiles
        ++ lib.optional hasStatelessUserOverride statelessUserOverrideFile
        ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

    # HTPC role: media-centre stack.
    # HTPC does not use impermanence, so environment.etc is correct here
    # (same pattern as mkServerVariant — NOT the /persistent activationScript path).
    mkHtpcVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          ./hardware-configuration.nix
          vexos-nix.nixosModules.htpcBase
        ] ++ modules
          ++ localFiles
          ++ lib.optional hasFeatures       featuresFile
          ++ lib.optional hasStorageRemote  storageRemoteFile
          ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

    # Vanilla role: stock NixOS baseline — no desktop, no gaming, no branding.
    # Suitable for system restore or a clean starting point.
    mkVanillaVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          ./hardware-configuration.nix
          vexos-nix.nixosModules.vanillaBase
        ] ++ modules
          ++ localFiles
          ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

    # Headless server role: CLI only, no desktop environment.
    # See the mkServerVariant comment below for the ZFS hostId requirement.
    mkHeadlessServerVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules     = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          servicesFile = ./server-services.nix;
          hasServices  = builtins.pathExists servicesFile;
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          ./hardware-configuration.nix
          vexos-nix.nixosModules.headlessServerBase
        ]
        ++ modules
        ++ localFiles
        ++ lib.optional hasHost hostFile
        ++ lib.optional hasServices servicesFile
        ++ lib.optional hasStoragePool storagePoolFile
        ++ lib.optional hasStorageRemote storageRemoteFile
        ++ lib.optional hasZfsPools zfsPoolsFile
        ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

    # Server role: GUI server stack.
    #
    # ── ZFS hostId ───────────────────────────────────────────────────────────
    # ZFS bakes the host's hostId into every pool's vdev label at creation time.
    # If the hostId changes after pools are created, ZFS will refuse to import
    # the pool on next boot.
    #
    # networking.hostId is set in host.nix (written by install.sh from
    # `head -c 8 /etc/machine-id`). A missing host.nix leaves the placeholder
    # in place, which causes an assertion failure that aborts the build — it
    # is NOT a warning.
    mkServerVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules     = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          # Optional per-machine service toggles — written by `just enable <service>`.
          servicesFile = ./server-services.nix;
          hasServices  = builtins.pathExists servicesFile;
        in
        [
          { nixpkgs.hostPlatform = "x86_64-linux"; }
          # Persist the active variant name so vexos-updater and `just rebuild` can read it.
          # The server role does not use impermanence, so environment.etc is correct here.
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
        ]
        ++ modules
        ++ localFiles
        ++ lib.optional hasHost      hostFile
        ++ lib.optional hasServices  servicesFile
        ++ lib.optional hasFeatures  featuresFile
        ++ lib.optional hasStoragePool storagePoolFile
        ++ lib.optional hasStorageRemote storageRemoteFile
        ++ lib.optional hasZfsPools zfsPoolsFile
        ++ lib.optional hasKernelOverride kernelOverrideFile;
    };

  in
  {
    nixosConfigurations = {
      # ── Desktop role — full gaming/workstation stack ─────────────────────
      vexos-desktop-amd                  = mkVariant "vexos-desktop-amd"                  vexos-nix.nixosModules.gpuAmd;
      vexos-desktop-nvidia               = mkVariant "vexos-desktop-nvidia"               vexos-nix.nixosModules.gpuNvidia;
      vexos-desktop-nvidia-legacy580     = mkVariant "vexos-desktop-nvidia-legacy580"     [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-desktop-intel                = mkVariant "vexos-desktop-intel"                vexos-nix.nixosModules.gpuIntel;
      vexos-desktop-vm                   = mkVariant "vexos-desktop-vm"                   vexos-nix.nixosModules.gpuVm;

      # ── Stateless role — minimal, no gaming/dev/virt/ASUS modules ──────────
      vexos-stateless-amd                = mkStatelessVariant "vexos-stateless-amd"                vexos-nix.nixosModules.gpuAmd;
      vexos-stateless-nvidia             = mkStatelessVariant "vexos-stateless-nvidia"             vexos-nix.nixosModules.gpuNvidia;
      vexos-stateless-nvidia-legacy580   = mkStatelessVariant "vexos-stateless-nvidia-legacy580"   [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-stateless-intel              = mkStatelessVariant "vexos-stateless-intel"              vexos-nix.nixosModules.gpuIntel;
      vexos-stateless-vm                 = mkStatelessVariant "vexos-stateless-vm"                vexos-nix.nixosModules.statelessGpuVm;

      # ── HTPC role — media-centre stack ──────────────────────────────────
      vexos-htpc-amd                     = mkHtpcVariant "vexos-htpc-amd"                     vexos-nix.nixosModules.gpuAmd;
      vexos-htpc-nvidia                  = mkHtpcVariant "vexos-htpc-nvidia"                  vexos-nix.nixosModules.gpuNvidia;
      vexos-htpc-nvidia-legacy580        = mkHtpcVariant "vexos-htpc-nvidia-legacy580"        [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-htpc-intel                   = mkHtpcVariant "vexos-htpc-intel"                   vexos-nix.nixosModules.gpuIntel;
      vexos-htpc-vm                      = mkHtpcVariant "vexos-htpc-vm"                      vexos-nix.nixosModules.gpuVm;

      # ── Server role — GUI server stack ────────────────────────────────────
      vexos-server-amd                   = mkServerVariant "vexos-server-amd"                   vexos-nix.nixosModules.gpuAmd;
      vexos-server-nvidia                = mkServerVariant "vexos-server-nvidia"                vexos-nix.nixosModules.gpuNvidia;
      vexos-server-nvidia-legacy580      = mkServerVariant "vexos-server-nvidia-legacy580"      [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-server-intel                 = mkServerVariant "vexos-server-intel"                 vexos-nix.nixosModules.gpuIntel;
      vexos-server-vm                    = mkServerVariant "vexos-server-vm"                    vexos-nix.nixosModules.gpuVm;

      # ── Headless Server role — CLI only service stack ─────────────────────
      # Uses headless GPU modules (no early KMS / display init, no LACT GUI tool).
      vexos-headless-server-amd                  = mkHeadlessServerVariant "vexos-headless-server-amd"                  vexos-nix.nixosModules.gpuAmdHeadless;
      vexos-headless-server-nvidia               = mkHeadlessServerVariant "vexos-headless-server-nvidia"               vexos-nix.nixosModules.gpuNvidiaHeadless;
      vexos-headless-server-nvidia-legacy580     = mkHeadlessServerVariant "vexos-headless-server-nvidia-legacy580"     [ vexos-nix.nixosModules.gpuNvidiaHeadless { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-headless-server-intel                = mkHeadlessServerVariant "vexos-headless-server-intel"                vexos-nix.nixosModules.gpuIntelHeadless;
      vexos-headless-server-vm                   = mkHeadlessServerVariant "vexos-headless-server-vm"                   vexos-nix.nixosModules.gpuVm;

      # ── Vanilla role — stock NixOS baseline ──────────────────────────────
      vexos-vanilla-amd                  = mkVanillaVariant "vexos-vanilla-amd"                  vexos-nix.nixosModules.gpuAmd;
      vexos-vanilla-nvidia               = mkVanillaVariant "vexos-vanilla-nvidia"               vexos-nix.nixosModules.gpuNvidia;
      vexos-vanilla-nvidia-legacy580     = mkVanillaVariant "vexos-vanilla-nvidia-legacy580"     [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_580"; } ];
      vexos-vanilla-intel                = mkVanillaVariant "vexos-vanilla-intel"                vexos-nix.nixosModules.gpuIntel;
      # gpuVanillaVm instead of gpuVm: vanilla does not import modules/system.nix,
      # so vexos.btrfs.enable (declared there) is not available in this
      # evaluation context.
      vexos-vanilla-vm     = mkVanillaVariant "vexos-vanilla-vm"     vexos-nix.nixosModules.gpuVanillaVm;
    };
  };
}