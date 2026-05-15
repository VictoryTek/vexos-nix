{
  description = "vexos-nix — Personal NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # nixpkgs-unstable: used to supply latest GNOME application packages in
    # modules/gnome.nix via the pkgs.unstable overlay.
    # Do NOT add inputs.nixpkgs-unstable.follows = "nixpkgs" — that would
    # pin unstable to the stable revision, defeating its purpose.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # home-manager: optional, for user-level dotfiles (future use)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nix-community/impermanence: declarative persistence for tmpfs-rooted systems.
    # Used exclusively by the stateless role (configuration-stateless.nix).
    # impermanence has no nixpkgs dependency — follows not required.
    impermanence.url = "github:nix-community/impermanence";

    # Up — GTK4 + libadwaita system update GUI (all roles and variants).
    up = {
      url = "github:VictoryTek/Up";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # proxmox-nixos: Proxmox VE hypervisor on NixOS. Used by modules/server/proxmox.nix.
    # Do NOT add inputs.proxmox-nixos.inputs.nixpkgs.follows = "nixpkgs" — the upstream
    # flake manages its own nixpkgs-stable pin; overriding it breaks package builds.
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, impermanence, up, ... }@inputs:
  let
    inherit (nixpkgs) lib;

    system = "x86_64-linux";

    # Inline NixOS module: exposes pkgs.unstable.* sourced from nixpkgs-unstable.
    # Used in modules/gnome.nix to pin GNOME application tools to latest.
    unstableOverlayModule = {
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
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

    # Single source of truth for per-role wiring. Consumed by `mkHost` (per-host
    # nixosConfigurations) AND by `mkBaseModule` (the nixosModules.*Base exports
    # that template/etc-nixos-flake.nix imports). Keeping both pathways derived
    # from this same table is what prevents the historical drift between
    # commonModules and nixosModules.base.
    roles = {
      desktop = {
        homeFile     = ./home-desktop.nix;
        baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
        extraModules = [];
      };
      htpc = {
        homeFile     = ./home-htpc.nix;
        baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
        extraModules = [];
      };
      stateless = {
        homeFile     = ./home-stateless.nix;
        baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
        extraModules = [ impermanence.nixosModules.impermanence ];
      };
      server = {
        homeFile     = ./home-server.nix;
        # inputs.proxmox-nixos.nixosModules.proxmox-ve is imported here (not in
        # modules/server/proxmox.nix) to avoid infinite recursion — `imports`
        # cannot safely reference _module.args.
        # proxmoxOverlayModule must also be listed to make pkgs.proxmox-ve available.
        baseModules  = [ unstableOverlayModule upModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
        extraModules = serverServicesModule;
      };
      headless-server = {
        homeFile     = ./home-headless-server.nix;
        # No upModule — headless servers have no display, so the GUI update
        # app is intentionally omitted.
        # proxmoxOverlayModule must also be listed to make pkgs.proxmox-ve available.
        baseModules  = [ unstableOverlayModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
        extraModules = serverServicesModule;
      };
      vanilla = {
        homeFile     = ./home-vanilla.nix;
        baseModules  = [];
        extraModules = [];
      };
    };

    # Home Manager wiring shared by every role. The only thing that varies
    # between roles is which home-*.nix file feeds users.nimda.
    mkHomeManagerModule = homeFile: { config, ... }: {
      imports = [ home-manager.nixosModules.home-manager ];
      home-manager = {
        useGlobalPkgs    = true;  # share nixpkgs instance (+ overlays) with the system
        useUserPackages  = true;  # install user packages into /etc/profiles instead of ~/.nix-profile
        extraSpecialArgs = { inherit inputs; };
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
    #   6. legacyExtra                             ({ vexos.gpu.nvidiaDriverVariant = …; })
    mkHost = { name, role, gpu, nvidiaVariant ? null }:
      let
        r           = roles.${role};
        hostFile    = ./hosts + "/${role}-${gpu}.nix";
        legacyExtra = lib.optional (nvidiaVariant != null)
                        { vexos.gpu.nvidiaDriverVariant = nvidiaVariant; };

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
        inherit system;
        specialArgs = { inherit inputs; };
        modules =
          [ /etc/nixos/hardware-configuration.nix ]
          ++ r.baseModules
          ++ [ (mkHomeManagerModule r.homeFile) ]
          ++ r.extraModules
          ++ [ hostFile ]
          ++ legacyExtra
          ++ [ variantModule ];
      };

    # ── Host descriptor table — single source of truth for which systems exist ──
    # 34 outputs total: 30 historical + 4 vanilla role
    # variants (flagged below). Output names use the no-underscore "legacy535" /
    # "legacy470" suffix; the option value uses the underscored form "legacy_535".
    hostList = [
      # Desktop
      { name = "vexos-desktop-amd";              role = "desktop";         gpu = "amd"; }
      { name = "vexos-desktop-nvidia";           role = "desktop";         gpu = "nvidia"; }
      { name = "vexos-desktop-nvidia-legacy535"; role = "desktop";         gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-desktop-nvidia-legacy470"; role = "desktop";         gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
      { name = "vexos-desktop-intel";            role = "desktop";         gpu = "intel"; }
      { name = "vexos-desktop-vm";               role = "desktop";         gpu = "vm"; }

      # Stateless
      { name = "vexos-stateless-amd";              role = "stateless";     gpu = "amd"; }
      { name = "vexos-stateless-nvidia";           role = "stateless";     gpu = "nvidia"; }
      { name = "vexos-stateless-nvidia-legacy535"; role = "stateless";     gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-stateless-nvidia-legacy470"; role = "stateless";     gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
      { name = "vexos-stateless-intel";            role = "stateless";     gpu = "intel"; }
      { name = "vexos-stateless-vm";               role = "stateless";     gpu = "vm"; }

      # GUI Server
      { name = "vexos-server-amd";              role = "server";           gpu = "amd"; }
      { name = "vexos-server-nvidia";           role = "server";           gpu = "nvidia"; }
      { name = "vexos-server-nvidia-legacy535"; role = "server";           gpu = "nvidia"; nvidiaVariant = "legacy_535"; }  # NEW
      { name = "vexos-server-nvidia-legacy470"; role = "server";           gpu = "nvidia"; nvidiaVariant = "legacy_470"; }  # NEW
      { name = "vexos-server-intel";            role = "server";           gpu = "intel"; }
      { name = "vexos-server-vm";               role = "server";           gpu = "vm"; }

      # Headless Server
      { name = "vexos-headless-server-amd";              role = "headless-server"; gpu = "amd"; }
      { name = "vexos-headless-server-nvidia";           role = "headless-server"; gpu = "nvidia"; }
      { name = "vexos-headless-server-nvidia-legacy535"; role = "headless-server"; gpu = "nvidia"; nvidiaVariant = "legacy_535"; }  # NEW
      { name = "vexos-headless-server-nvidia-legacy470"; role = "headless-server"; gpu = "nvidia"; nvidiaVariant = "legacy_470"; }  # NEW
      { name = "vexos-headless-server-intel";            role = "headless-server"; gpu = "intel"; }
      { name = "vexos-headless-server-vm";               role = "headless-server"; gpu = "vm"; }

      # HTPC
      { name = "vexos-htpc-amd";              role = "htpc";               gpu = "amd"; }
      { name = "vexos-htpc-nvidia";           role = "htpc";               gpu = "nvidia"; }
      { name = "vexos-htpc-nvidia-legacy535"; role = "htpc";               gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
      { name = "vexos-htpc-nvidia-legacy470"; role = "htpc";               gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
      { name = "vexos-htpc-intel";            role = "htpc";               gpu = "intel"; }
      { name = "vexos-htpc-vm";               role = "htpc";               gpu = "vm"; }
      # Vanilla (stock NixOS baseline — no NVIDIA legacy variants, no proprietary GPU drivers)
      { name = "vexos-vanilla-amd";    role = "vanilla"; gpu = "amd"; }
      { name = "vexos-vanilla-nvidia"; role = "vanilla"; gpu = "nvidia"; }
      { name = "vexos-vanilla-intel";  role = "vanilla"; gpu = "intel"; }
      { name = "vexos-vanilla-vm";     role = "vanilla"; gpu = "vm"; }
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
             [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
      home-manager = {
        useGlobalPkgs    = true;
        useUserPackages  = true;
        extraSpecialArgs = { inherit inputs; };
        users.${config.vexos.user.name} = import roles.${role}.homeFile;
        # Drift fix: previously absent on `nixosModules.base` only. This is an
        # additive default — consumers of these *Base modules don't override it.
        backupFileExtension = "backup";
      };
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
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
      statelessGpuVm = { lib, ... }: {
        imports = [ ./modules/gpu/vm.nix ];
        vexos.stateless.disk.device = lib.mkForce "/dev/vda";
      };
      asus = ./modules/asus-opt.nix;
    };
  };
}
