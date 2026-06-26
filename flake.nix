{
  description = "vexos-nix — Personal NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # nixpkgs-unstable: supplies a small set of fast-moving packages via the
    # pkgs.unstable overlay (see unstableOverlayModule below). Current consumers:
    # home-desktop.nix (nodejs; vscode-fhs is present but disabled) and
    # modules/server/papermc.nix.
    # Do NOT add inputs.nixpkgs-unstable.follows = "nixpkgs" — that would
    # pin unstable to the stable revision, defeating its purpose.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager: optional, for user-level dotfiles (future use)
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-community/impermanence: declarative persistence for tmpfs-rooted systems.
    # Used exclusively by the stateless role (configuration-stateless.nix).
    # impermanence has no nixpkgs dependency — follows not required.
    impermanence.url = "github:nix-community/impermanence";

    # sops-nix: declarative encrypted secrets backend for server roles.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Up — GTK4 + libadwaita system update GUI (all roles and variants).
    up = {
      url = "github:VictoryTek/Up";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # proxmox-nixos: Proxmox VE hypervisor on NixOS. Used by modules/server/proxmox.nix.
    # Do NOT add inputs.proxmox-nixos.inputs.nixpkgs.follows = "nixpkgs" — the upstream
    # flake manages its own nixpkgs-stable pin; overriding it breaks package builds.
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";

    # vexboard: VexOS Server dashboard (Rust + WASM). Used by modules/server/vexboard.nix.
    # Follows nixpkgs-unstable so it updates in sync with the outer flake's unstable pin
    # (same pattern as `up` following `nixpkgs`). Do NOT change follows to "nixpkgs"
    # (stable) — vexboard builds against nixos-unstable with rust-overlay and the stable
    # toolchain breaks the Rust/WASM build.
    vexboard = {
      url = "github:VictoryTek/vexboard";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, impermanence, sops-nix, up, ... }@inputs:
  let
    inherit (nixpkgs) lib;

    system = "x86_64-linux";

    # Inline NixOS module: exposes pkgs.unstable.* sourced from nixpkgs-unstable.
    # Used to pin a small set of fast-moving packages to latest (nodejs, papermc;
    # vscode-fhs when enabled).
    unstableOverlayModule = {
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
            overlays = [ openblasNoCheckOverlay ];
          };
        })
      ];
    };

    # GUI update app — only for roles with a display (desktop, htpc, GUI server, stateless).
    upModule = { environment.systemPackages = [ up.packages.x86_64-linux.default ]; };

    # Proxmox VE overlay — exposes pkgs.proxmox-ve (and related Proxmox packages).
    # Required by services.proxmox-ve.package (lazy default in the proxmox NixOS module).
    # The proxmox NixOS module does NOT auto-apply its own overlay; this must be
    # done explicitly. Scoped to server / headless-server roles only.
    proxmoxOverlayModule = {
      nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.${system} ];
    };

    # Custom in-tree packages — exposes pkgs.vexos.* via pkgs/default.nix.
    # Applied to every role so any host can opt in to vexos.cockpit-navigator,
    # vexos.cockpit-zfs (Phase B), etc., simply by enabling the matching
    # vexos.server.cockpit.<plugin>.enable option.
    customPkgsOverlayModule = {
      nixpkgs.overlays = [ (import ./pkgs) ];
    };

    # Optional opt-in services module loaded from the host's /etc/nixos.
    # Empty list when the file is absent so server/headless-server outputs stay
    # buildable on machines that haven't deployed server-services.nix yet.
    serverServicesModule =
      let path = /etc/nixos/server-services.nix;
      in if builtins.pathExists path then [ path ] else [];

    # Optional per-machine user override for the stateless role.
    # Written by stateless-setup.sh / migrate-to-stateless.sh at install time.
    # Without this file the compiled-in default is a locked account
    # (hashedPassword = "!") — the setup scripts must run before first use.
    statelessUserOverrideModule =
      let path = /etc/nixos/stateless-user-override.nix;
      in if builtins.pathExists path then [ path ] else [];

    # Workaround: openblas test #30 (xzcblat3) deadlocks in the Nix sandbox on
    # certain hardware/kernel combinations. doCheck = false skips the test suite
    # without changing the compiled library. Applied to both stable and unstable
    # nixpkgs instances because pkgs.unstable is a separate import that does not
    # inherit nixpkgs.overlays.
    openblasNoCheckOverlay = _: prev: {
      openblas = prev.openblas.overrideAttrs (_: { checkPhase = ":"; });
    };

    openblasNoCheckModule = {
      nixpkgs.overlays = [ openblasNoCheckOverlay ];
    };

    # Overlay modules shared by every non-vanilla role (unstable channel + custom pkgs).
    commonBase = [ unstableOverlayModule customPkgsOverlayModule openblasNoCheckModule ];

    # Proxmox overlay + NixOS module shared by server and headless-server roles.
    proxmoxBase = [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];

    # VexBoard overlay + NixOS module — server and headless-server roles.
    # The overlay exposes pkgs.vexboard (required by the upstream NixOS module's
    # default package option). Both server and headless-server import
    # modules/server/default.nix which includes modules/server/vexboard.nix;
    # the NixOS module must be in scope for services.vexboard to be a valid option.
    vexboardBase = [
      { nixpkgs.overlays = [ inputs.vexboard.overlays.default ]; }
      inputs.vexboard.nixosModules.vexboard
    ];

    # sops-nix module shared by server and headless-server roles.
    sopsBase = [ sops-nix.nixosModules.sops ];

    # Single source of truth for per-role wiring. Consumed by `mkHost` (per-host
    # nixosConfigurations) AND by `mkBaseModule` (the nixosModules.*Base exports
    # that template/etc-nixos-flake.nix imports). Keeping both pathways derived
    # from this same table is what prevents the historical drift between
    # commonModules and nixosModules.base.
    roles = {
      desktop = {
        homeFile     = ./home-desktop.nix;
        baseModules  = commonBase ++ [ upModule ];
        extraModules = [];
      };
      htpc = {
        homeFile     = ./home-htpc.nix;
        baseModules  = commonBase ++ [ upModule ];
        extraModules = [];
      };
      stateless = {
        homeFile     = ./home-stateless.nix;
        baseModules  = commonBase ++ [ upModule ];
        extraModules = [ impermanence.nixosModules.impermanence ] ++ statelessUserOverrideModule;
      };
      server = {
        homeFile     = ./home-server.nix;
        # upModule: server has a display — GUI update app is included.
        # proxmoxBase: overlay + NixOS module imported here (not in
        # modules/server/proxmox.nix) to avoid infinite recursion — `imports`
        # cannot safely reference _module.args.
        # vexboardBase: overlay + NixOS module for the default server dashboard.
        baseModules  = commonBase ++ [ upModule ] ++ proxmoxBase ++ sopsBase ++ vexboardBase;
        extraModules = serverServicesModule;
      };
      headless-server = {
        homeFile     = ./home-headless-server.nix;
        # No upModule — headless servers have no display, so the GUI update
        # app is intentionally omitted.
        # proxmoxBase: overlay + NixOS module imported here to avoid infinite
        # recursion (same reason as server above).
        # vexboardBase: modules/server/vexboard.nix is imported by both server and
        # headless-server (via modules/server/default.nix). Including vexboardBase
        # here ensures services.vexboard option exists so the wrapper evaluates
        # cleanly even when disabled. Not enabled by default (no mkDefault in
        # configuration-headless-server.nix) — users can opt in via server-services.nix.
        baseModules  = commonBase ++ proxmoxBase ++ sopsBase ++ vexboardBase;
        extraModules = serverServicesModule;
      };
      vanilla = {
        homeFile     = ./home-vanilla.nix;
        baseModules  = [];
        extraModules = [];
      };
    };

    # Home Manager wiring shared by every role. The only thing that varies
    # between roles is which home-*.nix file feeds the primary user.
    mkHomeManagerModule = homeFile: { config, ... }: {
      imports = [ home-manager.nixosModules.home-manager ];
      home-manager = {
        useGlobalPkgs    = true;  # share nixpkgs instance (+ overlays) with the system
        useUserPackages  = true;  # install user packages into /etc/profiles instead of ~/.nix-profile
        extraSpecialArgs = { inherit inputs; userName = config.vexos.user.name; };
        users.${config.vexos.user.name} = import homeFile;
        # Prevents activation abort when managed files (e.g. ~/.bashrc) already
        # exist as regular files on the host. Conflicting files are renamed to
        # *.backup instead of causing checkLinkTargets to exit non-zero.
        backupFileExtension = "backup";
      };
    };

    # Build a complete NixOS system for a (role, gpu, optional nvidiaVariant)
    # tuple. Module list ordering is preserved exactly to match the legacy
    # hand-written nixosConfigurations entries:
    #   1. /etc/nixos/hardware-configuration.nix   (host-specific)
    #   2. role.baseModules                        (overlay, upModule, proxmox …)
    #   3. home-manager wiring                     (per-role homeFile)
    #   4. role.extraModules                       (impermanence / serverServicesModule)
    #   5. ./hosts/<role>-<gpu>.nix                (host file)
    #   6. legacyExtra                             (gpu/nvidia.nix + { vexos.gpu.nvidiaDriverVariant = …; })
    mkHost = { name, role, gpu, nvidiaVariant ? null }:
      let
        r           = roles.${role};
        hostFile    = ./hosts + "/${role}-${gpu}.nix";
        # legacyExtra imports gpu/nvidia.nix itself because hosts/vanilla-nvidia.nix
        # (nouveau baseline) does not — the legacy variant needs the module that
        # declares vexos.gpu.nvidiaDriverVariant and enables the proprietary driver.
        # For the other roles the host file already imports the same path; the
        # module system deduplicates path imports, so this is a no-op there.
        legacyExtra = lib.optional (nvidiaVariant != null) {
          imports = [ ./modules/gpu/nvidia.nix ];
          vexos.gpu.nvidiaDriverVariant = nvidiaVariant;
        };

        # Variant stamp: identifies the active build variant in /etc/nixos/vexos-variant.
        # Non-stateless: use standard environment.etc (file managed by NixOS etc activation).
        # Stateless: use vexos.variant option which feeds a persistent-aware activation
        # script in modules/impermanence.nix (bypasses tmpfs/bind-mount timing race).
        variantModule =
          if role == "stateless"
          then { vexos.variant = name; }
          else { environment.etc."nixos/vexos-variant".text = "${name}\n"; };
      in
      nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules =
          [ { nixpkgs.hostPlatform = system; } ]
          ++ [ /etc/nixos/hardware-configuration.nix ]
          ++ r.baseModules
          ++ [ (mkHomeManagerModule r.homeFile) ]
          ++ r.extraModules
          ++ [ hostFile ]
          ++ legacyExtra
          ++ [ variantModule ];
      };

    # ── Host descriptor table — single source of truth for which systems exist ──
    # 30 outputs total: 25 role/GPU variants + 5 vanilla role variants.
    # Output names use the no-underscore "legacy535" suffix; the option value
    # uses the underscored form "legacy_535".
    hostList = [
      # Desktop
      { name = "vexos-desktop-amd";              role = "desktop";         gpu = "amd"; }
      { name = "vexos-desktop-nvidia";           role = "desktop";         gpu = "nvidia"; }
      { name = "vexos-desktop-nvidia-legacy535"; role = "desktop";         gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-desktop-intel";            role = "desktop";         gpu = "intel"; }
      { name = "vexos-desktop-vm";               role = "desktop";         gpu = "vm"; }

      # Stateless
      { name = "vexos-stateless-amd";              role = "stateless";     gpu = "amd"; }
      { name = "vexos-stateless-nvidia";           role = "stateless";     gpu = "nvidia"; }
      { name = "vexos-stateless-nvidia-legacy535"; role = "stateless";     gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-stateless-intel";            role = "stateless";     gpu = "intel"; }
      { name = "vexos-stateless-vm";               role = "stateless";     gpu = "vm"; }

      # GUI Server
      { name = "vexos-server-amd";              role = "server";           gpu = "amd"; }
      { name = "vexos-server-nvidia";           role = "server";           gpu = "nvidia"; }
      { name = "vexos-server-nvidia-legacy535"; role = "server";           gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-server-intel";            role = "server";           gpu = "intel"; }
      { name = "vexos-server-vm";               role = "server";           gpu = "vm"; }

      # Headless Server
      { name = "vexos-headless-server-amd";              role = "headless-server"; gpu = "amd"; }
      { name = "vexos-headless-server-nvidia";           role = "headless-server"; gpu = "nvidia"; }
      { name = "vexos-headless-server-nvidia-legacy535"; role = "headless-server"; gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-headless-server-intel";            role = "headless-server"; gpu = "intel"; }
      { name = "vexos-headless-server-vm";               role = "headless-server"; gpu = "vm"; }

      # HTPC
      { name = "vexos-htpc-amd";              role = "htpc";               gpu = "amd"; }
      { name = "vexos-htpc-nvidia";           role = "htpc";               gpu = "nvidia"; }
      { name = "vexos-htpc-nvidia-legacy535"; role = "htpc";               gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-htpc-intel";            role = "htpc";               gpu = "intel"; }
      { name = "vexos-htpc-vm";               role = "htpc";               gpu = "vm"; }
      # Vanilla (stock NixOS baseline)
      { name = "vexos-vanilla-amd";              role = "vanilla"; gpu = "amd"; }
      { name = "vexos-vanilla-nvidia";           role = "vanilla"; gpu = "nvidia"; }
      { name = "vexos-vanilla-nvidia-legacy535"; role = "vanilla"; gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-vanilla-intel";            role = "vanilla"; gpu = "intel"; }
      { name = "vexos-vanilla-vm";               role = "vanilla"; gpu = "vm"; }
    ];

    # Build a nixosModules.*Base export from the same per-role wiring table.
    # The only divergences from `mkHost` are intentional:
    #   • imports the role's configuration-*.nix (not a ./hosts/<role>-<gpu>.nix
    #     host file) — these *Base modules are consumed by the thin wrapper at
    #     /etc/nixos/flake.nix on each host, which provides the per-host bits.
    #   • does NOT import /etc/nixos/hardware-configuration.nix — that's already
    #     handled by the consumer flake.
    #   • headless-server omits the `up` GUI app from environment.systemPackages.
    mkBaseModule = role: configFile: { config, ... }: {
      imports =
        [ home-manager.nixosModules.home-manager configFile ]
        ++ roles.${role}.extraModules
        ++ lib.optionals (role == "server" || role == "headless-server")
             [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve sops-nix.nixosModules.sops ]
        ++ lib.optionals (role == "server" || role == "headless-server")
             [ { nixpkgs.overlays = [ inputs.vexboard.overlays.default ]; }
               inputs.vexboard.nixosModules.vexboard ];
      home-manager = {
        useGlobalPkgs    = true;
        useUserPackages  = true;
        extraSpecialArgs = { inherit inputs; userName = config.vexos.user.name; };
        users.${config.vexos.user.name} = import roles.${role}.homeFile;
        # Drift fix: previously absent on `nixosModules.base` only. This is an
        # additive default — consumers of these *Base modules don't override it.
        backupFileExtension = "backup";
      };
      nixpkgs.overlays = [
        openblasNoCheckOverlay
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
            overlays = [ openblasNoCheckOverlay ];
          };
        })
        (import ./pkgs)
      ];
      environment.systemPackages =
        lib.optional (role != "headless-server" && role != "vanilla") up.packages.x86_64-linux.default;
    };
  in
  {
    # ── nixosConfigurations — generated from hostList via mkHost ─────────────
    # 34 outputs. To add/remove a system, edit `hostList` above; nothing else.
    nixosConfigurations = lib.listToAttrs (map (h: {
      name  = h.name;
      value = mkHost {
        inherit (h) name role gpu;
        nvidiaVariant = h.nvidiaVariant or null;
      };
    }) hostList);

    # ── NixOS modules (consumed by /etc/nixos/flake.nix on the host) ─────────
    # The thin wrapper at /etc/nixos/flake.nix imports these instead of
    # building directly from the repo, so hardware-configuration.nix never
    # needs to leave /etc/nixos.
    nixosModules = {
      # Full stack: desktop + gaming + audio + performance + controllers + network + flatpak
      base               = mkBaseModule "desktop"         ./configuration-desktop.nix;

      # HTPC stack: media-centre focused, no gaming/development/virtualization.
      htpcBase           = mkBaseModule "htpc"            ./configuration-htpc.nix;

      # Server stack: GUI server, no gaming/development/virtualization.
      serverBase         = mkBaseModule "server"          ./configuration-server.nix;

      # Headless server stack: no GUI, no audio, no Flatpak.
      # Suitable for production servers accessed via SSH.
      headlessServerBase = mkBaseModule "headless-server" ./configuration-headless-server.nix;

      # Vanilla stack: stock NixOS baseline. No desktop, no custom GPU,
      # no performance tuning. Suitable for system restore or fresh start.
      vanillaBase = mkBaseModule "vanilla" ./configuration-vanilla.nix;

      # Stateless stack: minimal, without gaming/development/virtualization/asus.
      # Suitable for a clean daily-driver focused on stateless and basic productivity.
      # Adds the disko module + default disk on top of the shared mkBaseModule output.
      statelessBase = { lib, ... }: {
        imports = [
          (mkBaseModule "stateless" ./configuration-stateless.nix)
          ./modules/stateless-disk.nix
        ];
        vexos.stateless.disk = {
          enable = true;
          device = lib.mkDefault "/dev/nvme0n1";
        };
      };

      # Guard: disable VirtualBox guest additions on all bare-metal variants.
      # hardware-configuration.nix generated inside a VirtualBox VM sets
      # virtualisation.virtualbox.guest.enable = true; lib.mkForce false here
      # ensures that value can never survive into a non-VM build, preventing
      # VirtualBox-GuestAdditions from attempting to compile against a kernel
      # that has removed the required DRM symbols (Linux 6.12+).
      gpuAmd = { ... }: {
        imports = [ ./modules/gpu/amd.nix ];
      };
      gpuNvidia = { ... }: {
        imports = [ ./modules/gpu/nvidia.nix ];
      };
      gpuIntel = { ... }: {
        imports = [ ./modules/gpu/intel.nix ];
      };

      # Headless server GPU modules: compute/VA-API without early KMS / display init.
      gpuAmdHeadless = { ... }: {
        imports = [ ./modules/gpu/amd-headless.nix ];
      };
      gpuNvidiaHeadless = { ... }: {
        imports = [ ./modules/gpu/nvidia-headless.nix ];
      };
      gpuIntelHeadless = { ... }: {
        imports = [ ./modules/gpu/intel-headless.nix ];
      };
      gpuVm = { ... }: {
        imports = [ ./modules/gpu/vm.nix ];
      };
      # Vanilla VM: same guest additions as gpuVm but without vexos.btrfs /
      # vexos.swap option references — those options are declared in
      # modules/system.nix which the vanilla role does not import.
      gpuVanillaVm = { ... }: {
        imports = [ ./modules/gpu/vanilla-vm.nix ];
      };
      statelessGpuVm = { lib, ... }: {
        imports = [ ./modules/gpu/vm.nix ];
        vexos.stateless.disk.device = lib.mkForce "/dev/vda";
      };
      asus = ./modules/asus-opt.nix;
    };
  };
}
