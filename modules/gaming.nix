# modules/gaming.nix
# Gaming stack: Steam, Proton, MangoHud, Gamescope, GameMode,
# Wine/Proton tooling, Distrobox, Lutris, ProtonPlus, PrismLauncher.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.gaming.enable = true;
# Bundled: gpu-gaming.nix (32-bit libs, shader cache) and system-gaming.nix
# (kernel params, SCX LAVD) are imported here and activate with the same option.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.features.gaming;

  # Force XWayland instead of native Wayland for these two Electron apps, on
  # this hybrid AMD+NVIDIA laptop. Pinning GPU selection (EGL vendor, Vulkan
  # device — see git history) fixed the immediate crash-on-launch dmabuf
  # error, but a second failure remained: GNOME Shell forcibly kills the
  # client's Wayland connection ~20-40s into a clean run ("WL: error in
  # client communication (pid ...)"), which crashes Discord and silently
  # breaks Vesktop screen-share. This is a widely-reported Chromium
  # Ozone/Wayland-vs-Mutter compatibility bug on hybrid-NVIDIA systems
  # (reported against Cursor, VS Code, Brave — not specific to these two
  # apps or this fix). Routing through XWayland (--ozone-platform=x11)
  # avoids Mutter's native-Wayland linux-dmabuf handling entirely, which is
  # the standard workaround across those projects. GPU-selection env vars
  # are kept alongside since XWayland's GLX/Vulkan paths still benefit from
  # them on this hybrid GPU.
  nvidiaVkSelect = pkg: attr: pkg.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/${attr} \
        --set __EGL_VENDOR_LIBRARY_FILENAMES /run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json \
        --set __GLX_VENDOR_LIBRARY_NAME nvidia \
        --set MESA_VK_DEVICE_SELECT "10de:2d58!" \
        --add-flags "--ozone-platform=x11"
    '';
  });
in
{
  imports = [
    ./gpu-gaming.nix
    ./system-gaming.nix
  ];

  options.vexos.features.gaming.enable = lib.mkEnableOption "gaming stack (Steam, Proton, GameMode, Wine, controllers, GPU gaming libs, gaming kernel params)";

  config = lib.mkMerge [
    # Declare ownership unconditionally so these apps are removed when gaming is
    # disabled (flatpak.nix uninstalls managed apps absent from appsToInstall).
    { vexos.flatpak.managedApps = [
        "net.lutris.Lutris"
        "com.vysp3r.ProtonPlus"
        "org.prismlauncher.PrismLauncher"
      ];
    }

    (lib.mkIf cfg.enable {
    # ── Steam ─────────────────────────────────────────────────────────────────
    # programs.steam.enable also enables hardware.steam-hardware.enable automatically.
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = false;
      gamescopeSession.enable = true; # Gamescope session for Steam gaming mode

      # Proton-GE as an additional compatibility tool (unfree)
      extraCompatPackages = [
        pkgs.proton-ge-bin
      ];
    };

    # ── Gamescope micro-compositor (HDR, VRR, frame limiting) ─────────────────
    programs.gamescope = {
      enable = true;
      capSysNice = true; # lets gamescope renice itself for lower latency
    };

    # ── GameMode — performance daemon (CPU/GPU boost on game start) ───────────
    programs.gamemode = {
      enable = true;
      settings = {
        general = {
          renice = 10;             # negated by gamemode → nice = -10 (higher priority)
          inhibit_screensaver = 1; # prevent GNOME screen-lock mid-game
        };
        cpu = {
          # Auto-pin game threads to preferred cores on Ryzen 3D V-Cache and
          # Intel P+E-core (12th gen+) CPUs; no-op on unsupported hardware.
          pin_cores = "yes";
        };
        # gpu section is GPU-vendor-specific — see modules/gpu/amd.nix (AMD)
      };
    };

    # ── Gaming utilities ──────────────────────────────────────────────────────
    environment.systemPackages = [
      # Proton / Wine tooling
      pkgs.protontricks    # winetricks wrapper for Steam games
      pkgs.umu-launcher    # Proton launcher for non-Steam games

      # Display / overlay
      pkgs.mangohud        # In-game performance overlay; use mangohud %command% in Steam launch options
      pkgs.vkbasalt        # Vulkan post-processing layer (CAS, FXAA, etc.)

      # Wine (Staging + Wow64 multilib)
      pkgs.wineWow64Packages.stagingFull

      # Disk / prefix maintenance
      pkgs.duperemove      # deduplicates Wine prefix content

      # Container tooling (Distrobox for running other distro environments)
      pkgs.distrobox

      # Emulation
      pkgs.ryubing         # Nintendo Switch emulator (Ryujinx fork)
      pkgs.retroarch       # multi-system emulator frontend

      # Communication
      # Use unstable: stable vesktop 1.6.5 vendors an exact pnpm-10.29.2 build
      # input flagged insecure (CVE-2026-48995 et al.); unstable's vesktop (same
      # version) builds with a non-flagged pnpm. pnpm is build-time only.
      (nvidiaVkSelect pkgs.unstable.vesktop "vesktop") # feature-rich Discord client (Vencord-based)
      (nvidiaVkSelect pkgs.discord "discord")          # official Discord client

      # GNOME Shell extension for GameMode status indicator (tray icon)
      pkgs.gnomeExtensions.gamemode-shell-extension
    ];

    # Activate GameMode GNOME Shell extension when gaming is enabled.
    vexos.gnome.extraExtensions = [ "gamemodeshellextension@trsnaqe.com" ];

    # ── Gaming Flatpak apps ───────────────────────────────────────────────────
    vexos.flatpak.extraApps = [
      "net.lutris.Lutris"                # Game manager / Wine frontend
      "com.vysp3r.ProtonPlus"            # Proton/Wine version manager
      "org.prismlauncher.PrismLauncher"  # Minecraft launcher
    ];

    # ── Controllers ───────────────────────────────────────────────────────────
    # Gamepad and controller support: Xbox (xone/xpadneo), Nintendo Switch,
    # Sony DualShock/DualSense, and generic HID udev rules.

    # Xbox One / Series S|X USB dongle and wired controllers
    hardware.xone.enable = true;
    # Xbox wireless controllers via Bluetooth
    hardware.xpadneo.enable = true;

    # Nintendo Switch Pro Controller / Joy-Cons; Sony controllers (kernel drivers)
    boot.kernelModules = [ "hid_nintendo" "hid_sony" ];

    services.udev.extraRules = ''
      # ── Sony DualShock 4 (USB) ──
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="input"
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="input"
      # ── Sony DualSense (USB) ──
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="input"
      # ── Sony DualSense Edge (USB) ──
      KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", GROUP="input"
      # ── Sony controllers via Bluetooth ──
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", MODE="0660", GROUP="input"
      # ── 8BitDo Ultimate Bluetooth ──
      SUBSYSTEM=="input", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3106", MODE="0660", GROUP="input"
      # ── Generic: allow all input devices for the input group ──
      SUBSYSTEM=="input", MODE="0660", GROUP="input"
    '';

    # Grant the primary user access to GameMode CPU governor and input devices.
    # (Controller/USB peripheral access is granted via the udev GROUP="input" rules
    # below, not a "plugdev" group — NixOS doesn't declare one, and nothing here
    # ever targets it.)
    users.users.${config.vexos.user.name}.extraGroups = [ "gamemode" "input" ];

    # ── bubblewrap setuid override ────────────────────────────────────────────
    # bubblewrap 0.11.x removed setuid priv mode. programs.steam.enable still
    # sets security.wrappers.bwrap with setuid = true, which causes bwrap to
    # abort on launch ("setuid use of bubblewrap is not supported in this build").
    # Override the wrapper to remove the setuid bit; bwrap uses unprivileged
    # user namespaces (CLONE_NEWUSER) instead, which the kernel supports.
    security.wrappers.bwrap = lib.mkForce {
      source      = "${pkgs.bubblewrap}/bin/bwrap";
      setuid      = false;
      setgid      = false;
      owner       = "root";
      group       = "root";
      permissions = "u+rx,g+x,o+x";
    };

    # ── AppArmor Wine baseline ─────────────────────────────────────────────────
    # wineWow64Packages.stagingFull installs setuid wrappers (wineserver, wine-preloader)
    # that could be misused by a compromised Wine prefix. Place wineserver in
    # AppArmor complain mode so that deviations from normal operation appear in
    # audit logs without blocking legitimate games.
    # Switch to "enforce" once a site-specific profile is tuned.
    security.apparmor.policies."usr.bin.wineserver".profile = ''
      #include <tunables/global>

      ${pkgs.wineWow64Packages.stagingFull}/bin/wineserver flags=(complain) {
        #include <abstractions/base>
        capability sys_ptrace,
        @{PROC}/@{pid}/mem rw,
        @{PROC}/@{pid}/task/*/mem rw,
        /tmp/** rwk,
        @{HOME}/.wine/** rwlk,
        @{HOME}/.local/share/Steam/** rwlk,
        owner @{HOME}/** rwlk,
      }
    '';
    }) # end lib.mkIf cfg.enable
  ]; # end lib.mkMerge
}
