# modules/gpu/amd-headless.nix
# AMD GPU for headless server roles: ROCm compute and Vulkan ICD without the
# early-KMS initrd load and LACT GUI tool from modules/gpu/amd.nix.
#
# amdgpu loads automatically during normal kernel boot — initrd early load is
# only beneficial on display roles where it ensures the correct framebuffer
# resolution from the moment the boot splash appears.  On a headless server
# there is no display manager to take over the framebuffer, so early KMS init
# leaves the console on a blank DRM surface (black screen + blinking cursor).
#
# VA-API hardware decode and ROCm compute work identically whether amdgpu was
# loaded in initrd or at the normal kernel module stage.
{ pkgs, lib, ... }:
{
  # Force RADV over AMDVLK (RADV is actively maintained and faster for compute)
  environment.variables.AMD_VULKAN_ICD = "RADV";

  # ROCm OpenCL runtime (GPU compute: Blender, AI inference, etc.)
  hardware.graphics.extraPackages = with pkgs; [
    rocmPackages.clr      # ROCm Common Language Runtime
    rocmPackages.clr.icd  # OpenCL ICD registration
  ];

  # ROCm device node symlink: many compute apps hard-code /opt/rocm
  systemd.tmpfiles.rules =
    let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [ rocblas hipblas clr ];
      };
    in [
      "L+  /opt/rocm  -  -  -  -  ${rocmEnv}"
    ];
}
