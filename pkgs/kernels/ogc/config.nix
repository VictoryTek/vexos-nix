# pkgs/kernels/ogc/config.nix
# Translation of the Open Gaming Collective kernel config fragments into
# nixpkgs' structuredExtraConfig form.
#
# Source of truth (verified 2026-08-19):
#   https://github.com/OpenGamingCollective/kernel-packages
#     config/ogc.config.set    — 135 lines
#     config/ogc.config.unset  —  31 lines
#
# Upstream ships these as fragments layered onto a distro base config
# (fedora/arch/ubuntu). There is no "nix" base, so they are layered onto
# nixpkgs' own base kernel config instead. This is deliberate: reproducing
# Fedora's full config would drag in Fedora-specific module/signing/initrd
# assumptions that NixOS does not want — the failure mode that sank this
# repo's earlier Bazzite kernel attempt (see kernel_replace_spec.md, which
# had to carry a `makeModulesClosure allowMissing` hack for exactly that).
#
# The OGC delta is purely additive device enablement, so it layers cleanly.
#
# Keep this file's section order and comments aligned with upstream so a
# future re-sync is a straight diff.
{ lib }:

with lib.kernel;

let
  # ── Keys also defined by nixpkgs' common-config.nix ───────────────────────
  # Verified by diffing this file's keys against
  # pkgs/os-specific/linux/kernel/common-config.nix (nixos-26.05): 23 of our
  # 128 keys overlap. Every one of them must be forced, because even where the
  # intent matches, nixpkgs frequently marks its definition `optional = true`
  # while ours is not — and the module system treats that as a conflict.
  #
  # OGC's config is authoritative for OGC's kernel, so its values win.
  #
  # Three of these are *genuine* divergences worth knowing about:
  #
  #   BPF_JIT_ALWAYS_ON  nixpkgs: no  → OGC: yes
  #       nixpkgs disables it citing NixOS/nixpkgs#79304. OGC enables it for
  #       BPF/sched_ext performance. If BPF-related breakage appears on this
  #       kernel, suspect this first.
  #   CROS_EC_ISHTP      nixpkgs: module → OGC: no  (explicitly unset upstream)
  #   U_SERIAL_CONSOLE   nixpkgs: yes    → OGC: no  (explicitly unset upstream)
  #
  # If a future nixpkgs bump adds or drops an overlapping key, evaluation fails
  # loudly with "conflicting definition values" naming the key — add it here.
  overriddenByOgc = [
    "ANDROID_BINDERFS"
    "ANDROID_BINDER_DEVICES"
    "ANDROID_BINDER_IPC"
    "BPF_JIT"
    "BPF_JIT_ALWAYS_ON"
    "BPF_SYSCALL"
    "CROS_EC"
    "CROS_EC_I2C"
    "CROS_EC_ISHTP"
    "CROS_EC_LPC"
    "CROS_EC_SPI"
    "CROS_KBD_LED_BACKLIGHT"
    "DEBUG_INFO"
    "DEBUG_INFO_BTF"
    "FUNCTION_TRACER"
    "HAVE_EBPF_JIT"
    "IKCONFIG"
    "IKCONFIG_PROC"
    "IMA"
    "SCHED_CLASS_EXT"
    "USB_DWC2_DUAL_ROLE"
    "USB_DWC3_DUAL_ROLE"
    "U_SERIAL_CONSOLE"
  ];

  settings = {
  # ── Gaming ────────────────────────────────────────────────────────────────
  NTSYNC = module;

  # ── ASUS Laptops ──────────────────────────────────────────────────────────
  # ASUS_ARMOURY is the newer ASUS platform driver. Note: on CachyOS this
  # driver was implicated in supergfxd bootloops (asus-linux/supergfxctl#177).
  # ASUS Linux is a founding OGC partner, so it is carried here as upstream
  # ships it — but this is the first thing to suspect if asusd/supergfxd
  # misbehave after a kernel bump (see modules/asus-opt.nix).
  ASUS_LAPTOP = module;
  ASUS_WIRELESS = module;
  ASUS_ARMOURY = module;
  ASUS_WMI = module;
  ASUS_NB_WMI = module;
  ASUS_TF103C_DOCK = module;

  # ── ASUS Ally ─────────────────────────────────────────────────────────────
  HID_ASUS = module;
  HID_ASUS_ALLY = module;

  # ── Legion GO ─────────────────────────────────────────────────────────────
  HID_LENOVO = module;
  HID_LENOVO_GO = module;
  HID_LENOVO_GO_S = module;
  LENOVO_WMI_CAPDATA = module;

  # ── MSI Claw ──────────────────────────────────────────────────────────────
  HID_MSI = module;
  MSI_WMI_PLATFORM = module;

  # ── Ayaneo ────────────────────────────────────────────────────────────────
  AYN_EC = module;
  AYANEO_EC = module;

  # ── OneXPlayer ────────────────────────────────────────────────────────────
  HID_OXP = module;

  # ── ASUS Ally & Legion GO Gyro ────────────────────────────────────────────
  IIO_SYSFS_TRIGGER = module;
  IIO_HRTIMER_TRIGGER = module;

  # ── GPD Win ───────────────────────────────────────────────────────────────
  HID_GPD = module;

  # ── Steam Deck ────────────────────────────────────────────────────────────
  MFD_STEAMDECK = module;
  SENSORS_STEAMDECK = module;
  LEDS_STEAMDECK = module;
  EXTCON_STEAMDECK = module;
  DRM_AMD_COLOR_STEAMDECK = yes;
  USB_DWC3 = module;
  USB_DWC3_ULPI = yes;
  USB_DWC3_DUAL_ROLE = yes;
  USB_DWC3_PCI = module;
  USB_DWC3_HAPS = module;
  USB_DWC2 = module;
  USB_DWC2_DUAL_ROLE = yes;
  USB_DWC2_PCI = module;
  USB_CHIPIDEA = module;
  USB_CHIPIDEA_UDC = yes;
  USB_CHIPIDEA_HOST = yes;
  USB_CHIPIDEA_PCI = module;
  USB_CHIPIDEA_MSM = module;
  USB_CHIPIDEA_GENERIC = module;
  USB_ISP1760 = module;
  USB_ISP1760_HCD = yes;
  USB_ISP1761_UDC = yes;
  USB_ISP1760_DUAL_ROLE = yes;
  USB_GADGET = module;
  USB_GADGET_VBUS_DRAW = freeform "2";
  USB_GADGET_STORAGE_NUM_BUFFERS = freeform "2";
  SND_SOC_AMD_ACP_COMMON = module;
  SND_SPI = yes;
  SND_SOC_AMD_SOF_MACH = module;
  SND_SOC_AMD_MACH_COMMON = module;
  SND_SOC_SOF = module;
  SND_SOC_SOF_PROBE_WORK_QUEUE = yes;
  SND_SOC_SOF_IPC3 = yes;
  SND_SOC_SOF_INTEL_IPC4 = yes;
  SND_SOC_SOF_AMD_COMMON = module;
  SND_SOC_SOF_AMD_ACP63 = module;
  SND_SOC_TOPOLOGY = yes;

  # ── Steam Machine ─────────────────────────────────────────────────────────
  LEDS_VALVE = module;

  # ── Framework Laptops/Desktop ─────────────────────────────────────────────
  CROS_EC = module;
  CROS_EC_CHARDEV = module;
  CROS_EC_I2C = module;
  CROS_EC_LIGHTBAR = module;
  CROS_EC_LPC = module;
  CROS_EC_MKBP_PROXIMITY = module;
  CROS_EC_PROTO = module;
  CROS_EC_RPMSG = module;
  CROS_EC_SENSORHUB = module;
  CROS_EC_SPI = module;
  CROS_EC_SYSFS = module;
  CROS_EC_TYPEC = module;
  CROS_EC_UART = module;
  CROS_EC_UCSI = module;
  CROS_EC_WATCHDOG = module;
  CROS_HPS_I2C = module;
  CROS_KBD_LED_BACKLIGHT = module;
  CROS_KUNIT = module;
  CROS_KUNIT_EC_PROTO_TEST = module;
  CROS_TYPEC_SWITCH = module;
  CROS_USBPD_LOGGER = module;
  CROS_USBPD_NOTIFY = module;
  CROSS_MEMORY_ATTACH = yes;

  # ── Waydroid ──────────────────────────────────────────────────────────────
  ANDROID_BINDER_IPC = yes;
  ANDROID_BINDERFS = yes;
  # freeform values are emitted verbatim — nixpkgs adds the surrounding quotes.
  ANDROID_BINDER_DEVICES = freeform "binder,hwbinder,vndbinder";

  # ── Allow signed kernel modules ───────────────────────────────────────────
  IMA = yes;
  IMA_ARCH_POLICY = yes;
  IMA_APPRAISE_MODSIG = yes;
  IMA_SECURE_AND_OR_TRUSTED_BOOT = yes;

  # ── Enable sched_ext schedulers ───────────────────────────────────────────
  # modules/system-gaming.nix sets services.scx.scheduler = "scx_lavd", which
  # requires SCHED_CLASS_EXT plus BPF + BTF debug info below.
  BPF = yes;
  HAVE_EBPF_JIT = yes;
  ARCH_WANT_DEFAULT_BPF_JIT = yes;
  BPF_SYSCALL = yes;
  BPF_JIT = yes;
  DEBUG_INFO = yes;
  DEBUG_INFO_BTF = yes;
  BPF_JIT_ALWAYS_ON = yes;
  BPF_JIT_DEFAULT_ON = yes;
  SCHED_CLASS_EXT = yes;
  KALLSYMS_ALL = yes;
  FUNCTION_TRACER = yes;
  IKHEADERS = module;
  IKCONFIG_PROC = yes;
  IKCONFIG = yes;

  # ══ ogc.config.unset — options upstream explicitly disables ═══════════════

  # ── Steam Deck ────────────────────────────────────────────────────────────
  USB_DWC3_HOST = no;
  USB_DWC2_DEBUG = no;
  USB_DWC2_TRACK_MISSED_SOFS = no;
  USB_GADGET_DEBUG = no;
  USB_GADGET_DEBUG_FILES = no;
  USB_GADGET_DEBUG_FS = no;
  U_SERIAL_CONSOLE = no;
  USB_R8A66597 = no;
  USB_PXA27X = no;
  USB_MV_UDC = no;
  USB_MV_U3D = no;
  USB_M66592 = no;
  USB_BDC_UDC = no;
  USB_AMD5536UDC = no;
  USB_NET2272 = no;
  USB_NET2280 = no;
  USB_GOKU = no;
  USB_EG20T = no;
  USB_DUMMY_HCD = no;
  USB_CONFIGFS = no;
  PHY_SAMSUNG_USB2 = no;

  # ── Framework Laptops/Desktop ─────────────────────────────────────────────
  CROS_EC_DEBUGFS = no;
  CROS_EC_ISHTP = no;

  # ── Allow signed kernel modules ───────────────────────────────────────────
  INTEGRITY_CA_MACHINE_KEYRING = no;
  };
in
lib.mapAttrs (k: v: if lib.elem k overriddenByOgc then lib.mkForce v else v) settings
