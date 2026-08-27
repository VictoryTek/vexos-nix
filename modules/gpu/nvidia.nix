# modules/gpu/nvidia.nix
# NVIDIA proprietary drivers with multi-generation support.
# Import this in hosts/nvidia.nix — do NOT use alongside gpu/amd.nix or gpu/vm.nix.
#
# Set vexos.gpu.nvidiaDriverVariant in your host config to select a driver branch:
#   "latest"     — Production (595.x) branch; open kernel modules; Turing (RTX 20xx /
#                  GTX 16xx) through Ada/Hopper/Blackwell.
#   "legacy_580" — 580.x branch; proprietary modules; open = false.
#                  REQUIRED for Maxwell (GTX 750+), Pascal (GTX 10xx, Quadro P-series)
#                  and Volta — 580 is the last NVIDIA branch supporting them, and the
#                  open modules need Turing+, so those GPUs cannot use "latest" at all.
#   (legacy_535 / 535.x was removed — it does not build on any kernel this project
#    ships (verified against 6.12, 7.1 and 7.2), and legacy_580 supersedes it for the
#    same hardware)
#   (legacy_470 / Kepler is no longer offered — dropped upstream by NVIDIA and Bazzite)
#   (legacy_390 / Fermi is broken in current nixpkgs and has been removed)
{ config, pkgs, lib, ... }:

let
  variant = config.vexos.gpu.nvidiaDriverVariant;

  # Kernel 7.2 compatibility patch for the open kernel modules.
  #
  # 7.2 removed strncpy() from the kernel-space string API (strscpy replaces it)
  # and renamed the DRM atomic types (drm_atomic_state* -> drm_atomic_commit*).
  # NVIDIA 595.71.05 predates both, so its open modules fail to compile on 7.2.
  # CachyOS maintains the compat patch; nixpkgs already vendors CachyOS patches
  # exactly this way for 6.15 and 6.19 (see gpl_symbols_linux_615_patch and
  # kernel_6_19_patch in pkgs/os-specific/linux/nvidia-x11/default.nix) but has
  # not picked up the 7.2 one yet.
  #
  # Pinned to a commit, not a branch, so the build stays reproducible.
  #
  # Safe on older kernels: the DRM half is guarded by LINUX_VERSION_CODE >= 7.2,
  # and strscpy has existed since 4.3 — verified building on 6.12 and 7.2.
  #
  # REMOVE THIS once nixpkgs ships a driver that builds on 7.2 — either a version
  # newer than 595.71.05 (upstream NVIDIA is already at 610.x) or its own
  # kernel-7.x entry in patchesOpen. It fails loudly at patch time if the driver
  # moves underneath it, never silently.
  kernel_7_2_patch = pkgs.fetchpatch {
    url = "https://github.com/CachyOS/kernel-patches/raw/93c48e8161fedeff9fd640cf7ebb54d07b22937d/7.2/misc/nvidia/0001-make-Add-support-for-7.2-Kernel.patch";
    hash = "sha256-K5T7xBWxl2I5Pw/GyHumi4Iq/i6M2jcshI80nSXf/AE=";
  };

  stable = config.boot.kernelPackages.nvidiaPackages.stable;

  # Map variant string to the correct driver package.
  #
  # The patch is attached by overriding the `.open` derivation directly rather
  # than via `.override { patchesOpen = ...; }` — patchesOpen is an argument to
  # nvidia-x11's generic.nix, consumed before callPackage, so it is not an
  # overridable argument on the finished package.
  driverPackage =
    if variant == "latest" then
      stable // {
        open = stable.open.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [ kernel_7_2_patch ];
        });
      }
    else
      config.boot.kernelPackages.nvidiaPackages.legacy_580;

  # Open kernel modules require Turing (RTX 20xx / GTX 16xx) or newer.
  # legacy_580 targets Maxwell/Pascal/Volta and must use proprietary closed modules.
  useOpen = variant == "latest";

in
{
  options.vexos.gpu.nvidiaDriverVariant = lib.mkOption {
    type = lib.types.enum [ "latest" "legacy_580" ];
    default = "latest";
    description = ''
      NVIDIA driver branch to use. Choose based on your GPU generation:

        "latest"     — production (595.x) branch; open kernel modules.
                       Turing (RTX 20xx / GTX 16xx) and newer only.
                       Correct choice for all RTX 20/30/40/50 series and GTX 16xx cards.
        "legacy_580" — 580.x branch; proprietary modules; open = false.
                       REQUIRED for Maxwell (GTX 750+), Pascal (GTX 10xx,
                       Quadro P-series) and Volta (Titan V). NVIDIA's 580 branch
                       is the last to support these architectures — 590 and newer
                       dropped them — and the open kernel modules used by "latest"
                       require Turing or newer, so these GPUs cannot run "latest".
                       Hosts on this variant are pinned to Linux 7.1 by
                       modules/gpu/nvidia-legacy-kernel.nix; 580 does not build
                       against 7.2.
    '';
  };

  config = {
    # NVIDIA proprietary drivers require explicit license acceptance.
    nixpkgs.config.nvidia.acceptLicense = true;

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Open kernel modules: supported only on Turing (RTX 20xx / GTX 16xx) and newer.
      # legacy_580 must use proprietary closed modules (open = false).
      open = useOpen;

      # KMS: required for Wayland and reliable suspend/resume on all variants.
      modesetting.enable = true;

      powerManagement = {
        enable = false;       # set true if suspend/resume causes GPU lockups
        finegrained = false;  # set true for PRIME Turing+ discrete laptops only
      };

      package = driverPackage;
    };

    # nvidia-vaapi-driver provides VA-API via NVDEC (Turing/RTX 20xx and newer).
    # Installed unconditionally: on Maxwell/Pascal/Volta hardware (legacy_580),
    # which genuinely lacks NVDEC, the driver falls back to software decode
    # rather than breaking.
    hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver ];

    # Prevent hardware-configuration.nix (generated inside a VM) from enabling
    # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
    # build against linuxPackages_latest (kernel 6.12+).
    virtualisation.virtualbox.guest.enable = lib.mkForce false;

    # Sunshine (modules/sunshine.nix) hardware encoder for NVIDIA — covers both
    # the "latest" and "legacy_580" driver variants (NVENC is available on both).
    services.sunshine.settings.encoder = "nvenc";
  };
}
