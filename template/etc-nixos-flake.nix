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
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy535    (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia-legacy470    (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm
#
#      Stateless role (minimal stack, no gaming/dev/virt/ASUS modules):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia-legacy535  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia-legacy470  (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-vm
#
#      GUI Server role (GNOME desktop + service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia-legacy535     (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia-legacy470     (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-vm
#
#      Headless Server role (CLI only service stack):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia-legacy535  (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-nvidia-legacy470  (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-headless-server-vm
#
#      HTPC role (media centre build):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia-legacy535       (Maxwell/Pascal/Volta — LTS alt.)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia-legacy470       (Kepler — GTX 600/700)
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-intel
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-vm
#
#      Vanilla role (stock NixOS baseline — no desktop, no gaming, no branding):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-amd
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-nvidia
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
# ── Bootloader ──────────────────────────────────────────────────────────────
#
#   Default: systemd-boot (EFI) — works on all modern hardware and VMs.
#
#   For BIOS/Legacy only: replace the bootloaderModule block below with:
#     bootloaderModule = {
#       boot.loader.systemd-boot.enable = false;
#       boot.loader.grub = {
#         enable     = true;
#         efiSupport = false;
#         device     = "/dev/sda";  # ← verify with: lsblk
#       };
#     };
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
    # EFI / systemd-boot (default — suitable for all modern bare-metal and VM installs).
    # Replace with the BIOS/GRUB stanza from the header comment if needed.
    bootloaderModule = { ... }: {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
      # Boot entry title cleanup (strip kernel version, codename, date) is
      # handled automatically by modules/branding.nix in the upstream config.
    };

    # ── Variant builder ─────────────────────────────────────────────────────
    # Constructs a complete NixOS configuration for a given variant.
    # • hostname   → the variant name, also written to /etc/nixos/vexos-variant
    # • gpuModule  → GPU-specific drivers for this variant (single module or list)
    #
    # Normalises gpuModule to accept either a single module or a list of modules.
    # Shared builder helper — used by both mkVariant and mkStatelessVariant.
    _mkVariantWith = baseModule: variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          # Convert to list if necessary, preserving backward compatibility
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }

          bootloaderModule

          # hardware-configuration.nix is generated by nixos-generate-config and
          # lives in /etc/nixos — it is never committed to the vexos-nix repo.
          ./hardware-configuration.nix

          # System stack from the upstream vexos-nix flake.
          baseModule

          # GPU-specific drivers and settings for this variant.
        ] ++ modules;
    };

    # Desktop role: full gaming/workstation stack.
    mkVariant = _mkVariantWith vexos-nix.nixosModules.base;

    # Stateless role: minimal stack (no gaming/dev/virt/ASUS modules).
    # Uses an explicit builder (rather than _mkVariantWith) so it can
    # conditionally include a machine-local stateless-user-override.nix when
    # present.  Generated by stateless-setup.sh / migrate-to-stateless.sh at
    # install time; when absent the upstream initialPassword = "vexos" applies.
    mkStatelessVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          # Optional per-machine user override (password, etc.).
          # Generated by stateless-setup.sh / migrate-to-stateless.sh at install
          # time.  When absent the upstream initialPassword = "vexos" applies.
          userOverrideFile = ./stateless-user-override.nix;
          hasUserOverride  = builtins.pathExists userOverrideFile;
        in
        [
          { vexos.variant = variant; }
          bootloaderModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.statelessBase
        ]
        ++ modules
        ++ lib.optional hasUserOverride userOverrideFile;
    };

    # HTPC role: media-centre stack.
    # HTPC does not use impermanence, so environment.etc is correct here
    # (same pattern as mkServerVariant — NOT the /persistent activationScript path).
    mkHtpcVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.htpcBase
        ] ++ modules;
    };

    # Vanilla role: stock NixOS baseline — no desktop, no gaming, no branding.
    # Suitable for system restore or a clean starting point.
    mkVanillaVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules =
        let
          modules = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
        in
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.vanillaBase
        ] ++ modules;
    };

    # Headless server role: CLI only, no desktop environment.
    # See the mkServerVariant comment above for the ZFS hostId requirement.
    mkHeadlessServerVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules     = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          servicesFile = ./server-services.nix;
          hasServices  = builtins.pathExists servicesFile;
        in
        [
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.headlessServerBase
        ]
        ++ modules
        ++ lib.optional hasServices servicesFile;
    };

    # Server role: GUI server stack.
    #
    # ── ZFS hostId — required before creating ZFS pools ─────────────────────
    # ZFS bakes the host's hostId into every pool's vdev label at creation time.
    # If the hostId changes later (e.g. rebuilding from a workstation), ZFS will
    # refuse to import the pool on next boot.
    #
    # Before running `just create-zfs-pool`, add to your
    # /etc/nixos/hardware-configuration.nix (or a local override module):
    #
    #   networking.hostId = "deadbeef";  # ← replace: head -c 8 /etc/machine-id
    #
    # Fresh installs without any ZFS pools will see a build warning until this is
    # set — the warning is informational and does not block the build.
    mkServerVariant = variant: gpuModule: nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = vexos-nix.inputs; };
      modules =
        let
          modules     = if builtins.isList gpuModule then gpuModule else [ gpuModule ];
          # Optional per-machine service toggles — written by `just enable <service>`.
          servicesFile = ./server-services.nix;
          hasServices  = builtins.pathExists servicesFile;
        in
        [
          # Persist the active variant name so vexos-updater and `just rebuild` can read it.
          # The server role does not use impermanence, so environment.etc is correct here.
          { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }
          bootloaderModule
          ./hardware-configuration.nix
          vexos-nix.nixosModules.serverBase
        ]
        ++ modules
        ++ lib.optional hasServices servicesFile;
    };

  in
  {
    nixosConfigurations = {
      # ── Desktop role — full gaming/workstation stack ─────────────────────
      vexos-desktop-amd    = mkVariant "vexos-desktop-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-desktop-nvidia = mkVariant "vexos-desktop-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-desktop-intel  = mkVariant "vexos-desktop-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-desktop-vm     = mkVariant "vexos-desktop-vm"     vexos-nix.nixosModules.gpuVm;

      # ── Stateless role — minimal, no gaming/dev/virt/ASUS modules ──────────
      vexos-stateless-amd    = mkStatelessVariant "vexos-stateless-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-stateless-nvidia = mkStatelessVariant "vexos-stateless-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-stateless-intel  = mkStatelessVariant "vexos-stateless-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-stateless-vm     = mkStatelessVariant "vexos-stateless-vm"    vexos-nix.nixosModules.statelessGpuVm;

      # ── HTPC role — media-centre stack ──────────────────────────────────
      vexos-htpc-amd    = mkHtpcVariant "vexos-htpc-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-htpc-nvidia = mkHtpcVariant "vexos-htpc-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-htpc-intel  = mkHtpcVariant "vexos-htpc-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-htpc-vm     = mkHtpcVariant "vexos-htpc-vm"     vexos-nix.nixosModules.gpuVm;

      # ── Server role — GUI server stack ────────────────────────────────────
      vexos-server-amd    = mkServerVariant "vexos-server-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-server-nvidia = mkServerVariant "vexos-server-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-server-intel  = mkServerVariant "vexos-server-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-server-vm     = mkServerVariant "vexos-server-vm"     vexos-nix.nixosModules.gpuVm;

      # ── Headless Server role — CLI only service stack ─────────────────────
      # Uses headless GPU modules (no early KMS / display init, no LACT GUI tool).
      vexos-headless-server-amd    = mkHeadlessServerVariant "vexos-headless-server-amd"    vexos-nix.nixosModules.gpuAmdHeadless;
      vexos-headless-server-nvidia = mkHeadlessServerVariant "vexos-headless-server-nvidia" vexos-nix.nixosModules.gpuNvidiaHeadless;
      vexos-headless-server-intel  = mkHeadlessServerVariant "vexos-headless-server-intel"  vexos-nix.nixosModules.gpuIntelHeadless;
      vexos-headless-server-vm     = mkHeadlessServerVariant "vexos-headless-server-vm"     vexos-nix.nixosModules.gpuVm;

      # ── Vanilla role — stock NixOS baseline ──────────────────────────────
      vexos-vanilla-amd    = mkVanillaVariant "vexos-vanilla-amd"    vexos-nix.nixosModules.gpuAmd;
      vexos-vanilla-nvidia = mkVanillaVariant "vexos-vanilla-nvidia" vexos-nix.nixosModules.gpuNvidia;
      vexos-vanilla-intel  = mkVanillaVariant "vexos-vanilla-intel"  vexos-nix.nixosModules.gpuIntel;
      vexos-vanilla-vm     = mkVanillaVariant "vexos-vanilla-vm"     vexos-nix.nixosModules.gpuVm;
    };
  };
}