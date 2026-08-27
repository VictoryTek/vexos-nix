# modules/gpu/vm.nix
# Virtual machine guest: QEMU/KVM guest agent, SPICE clipboard/auto-resize,
# virtio-gpu + QXL driver. Import this in hosts/vm.nix.
#
# VirtualBox-specific content (guest additions and the kernel pin they need)
# lives in ./vm-guest-additions.nix, gated on vexos.vm.platform — which that
# file also declares. Default is "qemu".
{ config, lib, pkgs, ... }:
let
  isQemu = config.vexos.vm.platform == "qemu";
  # Real "will this compositor actually start" signal — not
  # vexos.desktop.environment, which is declared even on roles that never
  # import hyprland-desktop.nix/cosmic-desktop.nix and could produce a false
  # positive. programs.hyprland.enable and services.desktopManager.cosmic.enable
  # are core NixOS options (always declared, default false) that only flip
  # true once the matching DE module has actually wired the compositor up.
  needsRenderNode = config.programs.hyprland.enable || config.services.desktopManager.cosmic.enable;
in
{
  # Declares vexos.vm.platform; carries the VirtualBox guest additions and the
  # 6.18 kernel pin they require, both gated on platform == "virtualbox".
  imports = [ ./vm-guest-additions.nix ];

  # QEMU/KVM guest agent — graceful shutdown, memory ballooning, clock sync, file copy
  services.qemuGuest.enable = isQemu;

  # SPICE vdagent — clipboard sync and automatic display resize in SPICE sessions
  services.spice-vdagentd.enable = isQemu;

  # Load virtio-gpu, QXL display drivers, and VirtIO block device driver early.
  # virtio_blk must be forced into the initrd: the NixOS live ISO has it built-in
  # (not modular), so nixos-generate-config omits it from availableKernelModules.
  # Without it, /dev/vda never appears in the initrd and neededForBoot mounts fail.
  boot.initrd.kernelModules = [ "virtio_gpu" "virtio_blk" ];
  boot.kernelModules        = [ "qxl" ];

  # In a VM the hypervisor manages power — override to performance governor
  powerManagement.cpuFreqGovernor = lib.mkForce "performance";

  # VM btrfs layout is not snapper-compatible — disable btrfs/snapper integration.
  vexos.btrfs.enable = false;

  # SCX schedulers tune for physical CPU topology, which a guest does not see
  # accurately — the hypervisor owns scheduling. Disabled on every VM guest
  # regardless of kernel. (This previously read as a kernel-version constraint;
  # with vexos.vm.platform = "qemu" the guest now follows its role's kernel, so
  # the version is no longer the reason.)
  services.scx.enable = lib.mkForce false;

  # VMs rely on hypervisor memory management — no disk swap file needed.
  vexos.swap.enable = false;

  # Disable ZFS in VM builds. zfs-server.nix sets boot.supportedFilesystems.zfs = true
  # which causes NixOS to create zfs-import.target and make display-manager.service
  # wait for it. On VM guests with no ZFS pools the import target can fail or hang,
  # preventing GDM from ever starting (black screen on boot).
  boot.supportedFilesystems.zfs = lib.mkForce false;
  services.zfs.autoScrub.enable = lib.mkForce false;
  services.zfs.trim.enable      = lib.mkForce false;

  # Sunshine (modules/sunshine.nix) deliberately has no encoder override here —
  # unlike modules/gpu/{nvidia,amd,intel}.nix. KMS capture on virtio-gpu/QXL is
  # not reliably supported upstream (some setups need a dummy HDMI plug just to
  # have a capturable display surface); forcing a hardware encoder that may not
  # exist would hard-fail instead of falling back. Leave encoder unset so
  # Sunshine auto-detects, falling back to software encoding. Live-test on
  # actual VM hardware before relying on this for unattended access.

  # ── Runtime GPU render-node check (Hyprland/COSMIC only) ─────────────────
  # Hyprland (wlroots) and COSMIC (Smithay/cosmic-comp) both require a working
  # DRM render node for GBM/EGL buffer allocation; GNOME/Mutter is the outlier
  # that tolerates its absence via a more permissive software fallback. On a
  # VM display device with no render node (e.g. Proxmox's default Standard
  # VGA / bochs-drm — /dev/dri/ shows only cardN, no renderD128), both
  # compositors fail with a silent black screen and blinking cursor —
  # confirmed directly via cosmic-session's own EGL errors on real hardware:
  #   libEGL warning: failed to get driver name for fd -1
  #   MESA: error: ZINK: failed to choose pdev
  # This can't be caught at Nix eval time — render-node availability is a
  # property of the hypervisor's runtime virtual hardware, not of anything
  # declared in this config — so it's a systemd runtime check rather than a
  # build-time assertion. It only fires when the render node is genuinely
  # missing (ConditionPathExists) and the active compositor actually needs
  # one; it warns rather than blocking, so it cannot make an otherwise-working
  # boot worse.
  systemd.services.vexos-vm-render-node-check = lib.mkIf needsRenderNode {
    description = "Warn on console if no DRM render node is available for the active compositor";
    wantedBy    = [ "graphical.target" ];
    before      = [ "greetd.service" ];
    unitConfig.ConditionPathExists = "!/dev/dri/renderD128";
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      MSG="No GPU render node (/dev/dri/renderD128) found. The active desktop environment requires one and will fail to start (black screen, blinking cursor). On Proxmox: VM -> Hardware -> Display -> set to VirtIO-GPU (3D acceleration / VirGL), then reboot."
      echo "vexos: $MSG" >&2
      if ${pkgs.plymouth}/bin/plymouth --ping 2>/dev/null; then
        ${pkgs.plymouth}/bin/plymouth display-message --text="$MSG"
        ${pkgs.coreutils}/bin/sleep 15
      fi
    '';
  };
}
