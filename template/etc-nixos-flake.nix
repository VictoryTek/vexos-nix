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
#   2. Edit the three variables in the let block below:
#        variant          — pick from the VARIANT OPTIONS list
#        hostname         — your machine's network name (anything you want)
#        bootloaderModule — EFI or BIOS (see options below)
#
#   3. Apply (the #variant target is always required on a fresh install because
#      the default NixOS hostname "nixos" does not match the config key):
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd
#
#      After this first build, /etc/nixos/vexos-variant is written automatically
#      by the system and kept in sync on every future rebuild.
#
# ── All future rebuilds / updates ───────────────────────────────────────────
#
#   Manually:
#     sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
#
#   Via vexos-updater app:
#     The app reads /etc/nixos/vexos-variant and builds the command for you.
#
# ── Switching to a different variant later (e.g. amd → htpc) ────────────────
#
#   1. Edit this file: update variant and variantModule (hostname stays the same).
#   2. Rebuild once with the new variant target:
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc
#      /etc/nixos/vexos-variant is updated automatically by the build.
#   3. Done — vexos-updater picks up the new variant automatically from then on.
#
{
  inputs = {
    vexos-nix.url = "github:VictoryTek/vexos-nix";

    # Pin nixpkgs to the same version used by the config
    nixpkgs.follows = "vexos-nix/nixpkgs";
  };

  outputs = { self, vexos-nix, nixpkgs }:
  # ════════════════════════════════════════════════════════════════════════════
  # VARIANT OPTIONS — pick one and assign both the variant string and the
  # matching variantModule in the let block below.
  #
  #   variant = "vexos-amd";    variantModule = vexos-nix.nixosModules.gpuAmd;
  #   variant = "vexos-nvidia"; variantModule = vexos-nix.nixosModules.gpuNvidia;
  #   variant = "vexos-intel";  variantModule = vexos-nix.nixosModules.gpuIntel;
  #   variant = "vexos-vm";     variantModule = vexos-nix.nixosModules.gpuVm;
  #
  #   Future variants (not yet released):
  #   variant = "vexos-htpc";   variantModule = vexos-nix.nixosModules.htpc;
  #   variant = "vexos-server"; variantModule = vexos-nix.nixosModules.server;
  # ════════════════════════════════════════════════════════════════════════════
  #
  # ════════════════════════════════════════════════════════════════════════════
  # BOOTLOADER OPTIONS — pick one, assign to bootloaderModule in the let block.
  #
  # ── Option A: EFI (most modern bare-metal installs) ─────────────────────────
  # bootloaderModule = {
  #   boot.loader.systemd-boot.enable      = true;
  #   boot.loader.efi.canTouchEfiVariables = true;
  # };
  #
  # ── Option B: BIOS / Legacy (VirtualBox without EFI, older hardware) ─────────
  # bootloaderModule = {
  #   boot.loader.systemd-boot.enable = false;
  #   boot.loader.grub = {
  #     enable     = true;
  #     efiSupport = false;
  #     device     = "/dev/sda";  # ← change to your disk (check: lsblk)
  #   };
  # };
  # ════════════════════════════════════════════════════════════════════════════
  let
    # ── Edit these three values, then only touch them again when switching variants ──

    # The vexos variant for this machine's hardware — see VARIANT OPTIONS above.
    # Must match the name written to /etc/nixos/vexos-variant (setup step 3).
    variant = "vexos-amd";

    # The corresponding nixos module for the chosen variant.
    variantModule = vexos-nix.nixosModules.gpuAmd;

    # Your machine's network hostname — completely independent of the variant.
    # Use anything that makes sense on your network ("media-den", "living-room", etc.).
    hostname = "vexos-amd";

    # Your bootloader — see BOOTLOADER OPTIONS above (EFI default).
    bootloaderModule = {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
    };

    # ── Nothing below this line should need to change ─────────────────────────

  in
  {
    # Config key is the variant name.
    # nixos-rebuild targets this via: --flake /etc/nixos#<variant>
    # vexos-updater reads /etc/nixos/vexos-variant to supply this automatically.
    nixosConfigurations.${variant} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { networking.hostName = hostname; }   # network name — independent of variant

        # Write the variant name to /etc/nixos/vexos-variant on every build.
        # vexos-updater reads this file to know which #target to pass.
        # No manual setup step required — it is always kept in sync automatically.
        { environment.etc."nixos/vexos-variant".text = "${variant}\n"; }

        bootloaderModule
        ./hardware-configuration.nix          # generated by nixos-generate-config, stays local
        vexos-nix.nixosModules.base           # full desktop + gaming + audio + performance stack
        variantModule
      ];
    };
  };
}
        bootloaderModule
        ./hardware-configuration.nix          # generated by nixos-generate-config, stays local
        vexos-nix.nixosModules.base           # full desktop + gaming + audio + performance stack
        gpuModule
      ];
    };
  };
}
{
  inputs = {
    vexos-nix.url = "github:VictoryTek/vexos-nix";

    # Pin nixpkgs to the same version used by the config
    nixpkgs.follows = "vexos-nix/nixpkgs";
  };

  outputs = { self, vexos-nix, nixpkgs }:
  # ════════════════════════════════════════════════════════════════════════════
  # GPU MODULE OPTIONS — pick one, assign to gpuModule in the let block below.
  #   vexos-nix.nixosModules.gpuAmd     → AMD GPU (RADV, ROCm, LACT)
  #   vexos-nix.nixosModules.gpuNvidia  → NVIDIA (proprietary drivers)
  #   vexos-nix.nixosModules.gpuIntel   → Intel iGPU or Arc dGPU
  #   vexos-nix.nixosModules.gpuVm      → VM guest (QEMU / VirtualBox)
  # ════════════════════════════════════════════════════════════════════════════
  #
  # ════════════════════════════════════════════════════════════════════════════
  # BOOTLOADER OPTIONS — pick one, assign to bootloaderModule in the let block.
  #
  # ── Option A: EFI (most modern bare-metal installs) ─────────────────────────
  # bootloaderModule = {
  #   boot.loader.systemd-boot.enable      = true;
  #   boot.loader.efi.canTouchEfiVariables = true;
  # };
  #
  # ── Option B: BIOS / Legacy (VirtualBox without EFI, older hardware) ─────────
  # bootloaderModule = {
  #   boot.loader.systemd-boot.enable = false;
  #   boot.loader.grub = {
  #     enable     = true;
  #     efiSupport = false;
  #     device     = "/dev/sda";  # ← change to your disk (check: lsblk)
  #   };
  # };
  # ════════════════════════════════════════════════════════════════════════════
  let
    # ── Edit these three values once, then never touch this file again ────────

    # Your machine's hostname — any name you want (check current name with: hostname).
    # nixos-rebuild uses this to auto-detect which config to apply.
    hostname = "vexos-amd";

    # Your GPU variant — see GPU MODULE OPTIONS above.
    gpuModule = vexos-nix.nixosModules.gpuAmd;

    # Your bootloader — see BOOTLOADER OPTIONS above (EFI default).
    bootloaderModule = {
      boot.loader.systemd-boot.enable      = true;
      boot.loader.efi.canTouchEfiVariables = true;
    };

    # ── Nothing below this line should need to change ─────────────────────────

  in
  {
    # Single config keyed by your hostname — nixos-rebuild auto-detects it.
    nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        { networking.hostName = hostname; }   # binds hostname to this config entry
        bootloaderModule
        ./hardware-configuration.nix          # generated by nixos-generate-config, stays local
        vexos-nix.nixosModules.base           # full desktop + gaming + audio + performance stack
        gpuModule
      ];
    };
  };
}
