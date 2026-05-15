# Section 1 — Syntax & Correctness: Implementation Specification

## Summary of changes

Five targeted fixes across six files address two data-correctness bugs (ZFS
host-ID baked to the build machine, duplicate `lib.mkForce` declarations that
will cause a NixOS evaluation conflict on any external consumer of the flake
modules), one activation-script robustness issue (empty-glob first-boot race
in branding.nix), and two quality issues (a bare-assignment that blocks
per-host override, and `with pkgs;` scoped blocks in three large package
lists).  The code found on disk matches the report in all five cases; there
were no surprises.

---

## Change 1 — zfs-server.nix: remove eval-time readFile

### Current code (`modules/zfs-server.nix`, lines 57–73)

```nix
  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable 8-hex-digit hostId. Without it, pools may refuse to
  # auto-import on boot. We derive it deterministically from /etc/machine-id
  # via an activation script so each host gets a unique, reproducible value
  # without committing per-host secrets to the flake.
  #
  # If the user has already set networking.hostId in their host file (under
  # hosts/<role>-<gpu>.nix) or in /etc/nixos/hardware-configuration.nix,
  # that value wins (lib.mkDefault).
  networking.hostId = lib.mkDefault (
    let
      machineIdFile = "/etc/machine-id";
    in
      if builtins.pathExists machineIdFile
      then builtins.substring 0 8 (builtins.readFile machineIdFile)
      else "00000000"   # placeholder; first build on a fresh host will recompute
  );
```

### Replacement code

Replace the entire `networking.hostId` comment block and assignment (lines
57–73) with the following:

```nix
  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable, unique 8-hex-digit hostId per machine.
  # Do NOT read /etc/machine-id at eval time — that file belongs to the machine
  # running `nixos-rebuild`, not the target host.  When building a server
  # closure on a workstation every server would inherit the workstation's
  # hostId, causing ZFS to refuse pool import on next boot.
  #
  # Set networking.hostId explicitly in hosts/<role>-<gpu>.nix, e.g.:
  #   networking.hostId = "deadbeef";
  # Generate a value with:  head -c 8 /etc/machine-id
  networking.hostId = lib.mkDefault "00000000";

  assertions = [
    {
      assertion = config.networking.hostId != "00000000";
      message = ''
        ZFS requires a unique networking.hostId per machine.
        Set it in hosts/<role>-<gpu>.nix or hardware-configuration.nix:
          networking.hostId = "deadbeef";   # replace with real value
        Generate with: head -c 8 /etc/machine-id
      '';
    }
  ];
```

### Risk / notes

- The `lib.mkDefault` (priority 1000) is intentionally lower than any
  per-host assignment (plain assignment at 100) or `hardware-configuration.nix`
  assignment, so a host that already sets `networking.hostId` will not be
  affected by this change.
- The assertion fires at eval time — `nixos-rebuild build` will immediately
  surface the missing value rather than silently baking in a wrong ID.
- Existing hosts in `hosts/server-*.nix` and `hosts/headless-server-*.nix`
  must each gain an explicit `networking.hostId = "<8 hex chars>";` line
  before the first rebuild after this change is applied.  The implementation
  agent should audit those host files and add placeholder comments where the
  value is missing (without guessing values — each host owner generates their
  own from `head -c 8 /etc/machine-id`).
- `modules/zfs-server.nix` currently does not receive `config` as an argument
  (`{ config, lib, pkgs, ... }`).  Check the opening line; `config` is already
  present, so the assertion can reference `config.networking.hostId` without
  adding it.

---

## Change 2 — flake.nix: deduplicate virtualbox.guest.enable mkForce

### Current code (`flake.nix`, lines 306–339)

The six non-VM GPU wrapper modules each independently declare:
```nix
virtualisation.virtualbox.guest.enable = lib.mkForce false;
```
in addition to the underlying `modules/gpu/*.nix` files, which already carry
the same declaration.

Exact wrapper blocks as they appear in `flake.nix`:

```nix
      gpuAmd = { lib, ... }: {
        imports = [ ./modules/gpu/amd.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 308
      };
      gpuNvidia = { lib, ... }: {
        imports = [ ./modules/gpu/nvidia.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 312
      };
      gpuIntel = { lib, ... }: {
        imports = [ ./modules/gpu/intel.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 316
      };

      # Headless server GPU modules: compute/VA-API without early KMS / display init.
      gpuAmdHeadless = { lib, ... }: {
        imports = [ ./modules/gpu/amd-headless.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 321
      };
      gpuNvidiaHeadless = { lib, ... }: {
        imports = [ ./modules/gpu/nvidia-headless.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 325
      };
      gpuIntelHeadless = { lib, ... }: {
        imports = [ ./modules/gpu/intel-headless.nix ];
        virtualisation.virtualbox.guest.enable = lib.mkForce false;   # line 329
      };
      gpuVm = { ... }: {
        imports = [ ./modules/gpu/vm.nix ];
      };
```

The corresponding declarations **that must be kept** in each module file:

| File | Line | Value |
|------|------|-------|
| `modules/gpu/amd.nix` | 35 | `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/nvidia.nix` | 80 | `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/intel.nix` | 51 | `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/amd-headless.nix` | 38 | `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/intel-headless.nix` | 37 | `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |

`modules/gpu/nvidia-headless.nix` does **not** contain a direct `virtualbox`
declaration — it only imports `./nvidia.nix` which carries the declaration at
line 80.  No change needed there.

### Replacement code

In `flake.nix`, remove the `virtualisation.virtualbox.guest.enable` line from
each of the six wrapper blocks and drop the `lib` argument where it is no
longer used.  `gpuVm` is already correct and untouched.

```nix
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
```

Do **not** touch `statelessGpuVm` (it uses `lib` for `lib.mkForce` on the
disk device and is outside this change's scope).

### Risk / notes

- The internal `nixosConfigurations` outputs (`hosts/*.nix`) import the
  `modules/gpu/*.nix` files directly and are unaffected.
- After this change, the single source of truth for
  `virtualisation.virtualbox.guest.enable = lib.mkForce false` is exclusively
  each `modules/gpu/*.nix`.  External consumers using the `nixosModules.gpu*`
  wrappers will now receive the declaration exactly once (via the imported
  module), eliminating the conflicting-definition error.
- `gpuNvidiaHeadless` receives the declaration transitively through
  `nvidia-headless.nix → nvidia.nix`.  No module file changes are needed for
  the headless-nvidia path.
- The `lib` argument is removed from each wrapper only where its sole use was
  `lib.mkForce`.  Confirm no other use of `lib` exists in those wrapper bodies
  before removing it (currently none do).

---

## Change 3 — branding.nix: nullglob + early-exit guard

### Current code (`modules/branding.nix`, lines 132–155)

```nix
  boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] || continue
      # Strip ", built on YYYY-MM-DD" date suffix
      ${pkgs.gnused}/bin/sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
      # Strip "(Linux X.X.X)" kernel version from generation description
      ${pkgs.gnused}/bin/sed -i 's/ (Linux [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*)//' "$f"
      # Normalise outer title label to the current host distroName (fixes old
      # entries that were built before per-host distroName was set).
      # Matches "title VexOS <Role> <anything-not-a-paren>(Generation" and
      # replaces the outer label with the current host's distroName.
      ${pkgs.gnused}/bin/sed -i 's/^title VexOS [^(]*(Generation/title ${config.system.nixos.distroName} (Generation/' "$f"
      # Remove redundant "VexOS <Role> <Variant>" from inside generation parens
      # (new format — distroName includes the variant, e.g. "VexOS Desktop VM").
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ (AMD|NVIDIA|Intel|VM) ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \3)/' "$f"
      # Remove redundant "VexOS <Role>" from inside generation parens
      # (old format — no variant suffix in the inner label).
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \2)/' "$f"
    done
  '';
```

### Replacement code

Replace the entire `boot.loader.systemd-boot.extraInstallCommands` assignment
(lines 132–155) with:

```nix
  boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable ''
    set -eu
    shopt -s nullglob
    entries=(/boot/loader/entries/*.conf)
    [[ ''${#entries[@]} -gt 0 ]] || exit 0
    for f in "''${entries[@]}"; do
      # Strip ", built on YYYY-MM-DD" date suffix
      ${pkgs.gnused}/bin/sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
      # Strip "(Linux X.X.X)" kernel version from generation description
      ${pkgs.gnused}/bin/sed -i 's/ (Linux [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*)//' "$f"
      # Normalise outer title label to the current host distroName
      ${pkgs.gnused}/bin/sed -i 's/^title VexOS [^(]*(Generation/title ${config.system.nixos.distroName} (Generation/' "$f"
      # Remove redundant "VexOS <Role> <Variant>" from inside generation parens (new format)
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ (AMD|NVIDIA|Intel|VM) ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \3)/' "$f"
      # Remove redundant "VexOS <Role>" from inside generation parens (old format)
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \2)/' "$f"
    done
  '';
```

Key differences from the current version:
1. `set -eu` — abort on any unhandled error or undefined variable.
2. `shopt -s nullglob` — makes `/boot/loader/entries/*.conf` expand to an
   empty array (not the literal string) when no `.conf` files exist.
3. Capture into a bash array `entries=(...)` and guard with
   `[[ ${#entries[@]} -gt 0 ]] || exit 0` — clean early-exit on first boot
   before systemd-boot has written any entries.
4. Loop iterates `"${entries[@]}"` (quoted array expansion) — correctly
   handles filenames with spaces (unlikely but safe).
5. The `[ -f "$f" ] || continue` guard is removed because `nullglob` + the
   array guard already guarantees every element in `entries` is an existing
   file when the loop runs.

Note on Nix string interpolation inside the shell heredoc: `''${...}` is the
Nix escape for a literal `${...}` in a multi-line string.  The
`${pkgs.gnused}` and `${config.system.nixos.distroName}` interpolations
(single `$`) are intentional Nix interpolations that expand at eval time.

### Risk / notes

- `set -eu` will cause the activation to abort if any `sed` command returns a
  non-zero exit code (e.g. if a `.conf` file is read-only).  In practice
  systemd-boot entries under `/boot/loader/entries/` are always writable by
  root during the install hook, so this is safe.  If a BTRFS snapshot or
  overlay makes them read-only, this becomes a surfaced error rather than a
  silent noop, which is the desired behaviour.
- The `shopt -s nullglob` builtin is available in the bash that NixOS uses for
  activation scripts; no additional dependencies are required.

---

## Change 4 — branding.nix: mkDefault label

### Current code (`modules/branding.nix`, line 98)

```nix
  system.nixos.label      = "25.11";
```

### Replacement code

```nix
  system.nixos.label      = lib.mkDefault "25.11";
```

### Risk / notes

- `system.nixos.label` is a `str` option.  A bare assignment at the default
  NixOS module priority (100) is always overridden by a `lib.mkForce` (50) but
  **cannot** be overridden by another plain assignment in a host file because
  two plain assignments at the same priority on a `str` conflict.  Wrapping in
  `lib.mkDefault` (priority 1000) allows any host file or downstream consumer
  to override with a plain assignment.
- This is a pure quality/ergonomics fix; the runtime behaviour on hosts that
  do not override the label is identical.
- The adjacent `system.nixos.distroName` is already wrapped in `lib.mkDefault`
  (line 79); this change makes `label` consistent with that pattern.

---

## Change 5 — gnome.nix / development.nix / gaming.nix: explicit pkgs. prefixes

### Overview

All `with pkgs;` scoped blocks inside package-list assignments in these three
files are replaced with explicit `pkgs.` prefixes.  The change is purely
stylistic/correctness — no packages are added or removed.

---

### 5a — `modules/gnome.nix`

Four `with pkgs;` blocks exist in this file.

#### Block 1: `xdg.portal.extraPortals` (line 172)

**Current code:**
```nix
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
    ];
```

**Replacement:**
```nix
    extraPortals = [
      pkgs.xdg-desktop-portal-gnome
    ];
```

---

#### Block 2: `environment.gnome.excludePackages` (lines 191–216)

**Current code:**
```nix
  environment.gnome.excludePackages = with pkgs; [
    gnome-photos
    gnome-tour
    gnome-connections
    gnome-weather
    gnome-clocks
    gnome-contacts
    gnome-maps
    gnome-characters
    gnome-user-docs
    yelp
    simple-scan
    epiphany    # GNOME Web
    geary       # GNOME email client
    xterm
    gnome-music
    rhythmbox
    totem         # mpv (nixpkgs) is the video player; Flatpak Totem is not installed
    showtime      # GNOME 49 video player ("Video Player") — duplicate of Flatpak Totem
    gnome-calculator  # Flatpak org.gnome.Calculator installed on desktop only
    gnome-calendar    # Flatpak org.gnome.Calendar installed on desktop only
    snapshot          # GNOME Camera — Flatpak org.gnome.Snapshot installed on desktop only
    papers            # winnow 0.7.x fails with rustc 1.91.1; desktop gets Papers via Flatpak
  ];
```

**Replacement:**
```nix
  environment.gnome.excludePackages = [
    pkgs.gnome-photos
    pkgs.gnome-tour
    pkgs.gnome-connections
    pkgs.gnome-weather
    pkgs.gnome-clocks
    pkgs.gnome-contacts
    pkgs.gnome-maps
    pkgs.gnome-characters
    pkgs.gnome-user-docs
    pkgs.yelp
    pkgs.simple-scan
    pkgs.epiphany    # GNOME Web
    pkgs.geary       # GNOME email client
    pkgs.xterm
    pkgs.gnome-music
    pkgs.rhythmbox
    pkgs.totem         # mpv (nixpkgs) is the video player; Flatpak Totem is not installed
    pkgs.showtime      # GNOME 49 video player ("Video Player") — duplicate of Flatpak Totem
    pkgs.gnome-calculator  # Flatpak org.gnome.Calculator installed on desktop only
    pkgs.gnome-calendar    # Flatpak org.gnome.Calendar installed on desktop only
    pkgs.snapshot          # GNOME Camera — Flatpak org.gnome.Snapshot installed on desktop only
    pkgs.papers            # winnow 0.7.x fails with rustc 1.91.1; desktop gets Papers via Flatpak
  ];
```

---

#### Block 3: `environment.systemPackages` (lines 219–243)

**Current code:**
```nix
  environment.systemPackages = with pkgs; [
    # GNOME tooling
    unstable.gnome-tweaks                               # GNOME customisation GUI
    unstable.dconf-editor                               # Low-level GNOME settings editor
    unstable.gnome-extension-manager                    # Install/manage GNOME Shell extensions

    # Cursor and icon theme packages — must be in system packages so the
    # system dconf profile (programs.dconf.profiles.user.databases) can
    # reference them before home-manager activation completes.
    bibata-cursors
    kora-icon-theme

    # GNOME Shell extensions
    unstable.gnomeExtensions.appindicator               # System tray icons
    unstable.gnomeExtensions.dash-to-dock               # macOS-style dock
    unstable.gnomeExtensions.alphabetical-app-grid      # Sort app grid alphabetically
    unstable.gnomeExtensions.gnome-40-ui-improvements   # UI tweaks
    unstable.gnomeExtensions.nothing-to-say             # Mic mute indicator
    unstable.gnomeExtensions.steal-my-focus-window      # Force window focus
    unstable.gnomeExtensions.tailscale-status           # Tailscale tray indicator
    unstable.gnomeExtensions.caffeine                   # Prevent screen sleep
    unstable.gnomeExtensions.restart-to                 # Restart-to menu entry
    unstable.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
    unstable.gnomeExtensions.background-logo            # Desktop background logo
    unstable.gnomeExtensions.tiling-assistant           # Half- and quarter-tiling support
  ];
```

**Replacement:**
```nix
  environment.systemPackages = [
    # GNOME tooling
    pkgs.unstable.gnome-tweaks                               # GNOME customisation GUI
    pkgs.unstable.dconf-editor                               # Low-level GNOME settings editor
    pkgs.unstable.gnome-extension-manager                    # Install/manage GNOME Shell extensions

    # Cursor and icon theme packages — must be in system packages so the
    # system dconf profile (programs.dconf.profiles.user.databases) can
    # reference them before home-manager activation completes.
    pkgs.bibata-cursors
    pkgs.kora-icon-theme

    # GNOME Shell extensions
    pkgs.unstable.gnomeExtensions.appindicator               # System tray icons
    pkgs.unstable.gnomeExtensions.dash-to-dock               # macOS-style dock
    pkgs.unstable.gnomeExtensions.alphabetical-app-grid      # Sort app grid alphabetically
    pkgs.unstable.gnomeExtensions.gnome-40-ui-improvements   # UI tweaks
    pkgs.unstable.gnomeExtensions.nothing-to-say             # Mic mute indicator
    pkgs.unstable.gnomeExtensions.steal-my-focus-window      # Force window focus
    pkgs.unstable.gnomeExtensions.tailscale-status           # Tailscale tray indicator
    pkgs.unstable.gnomeExtensions.caffeine                   # Prevent screen sleep
    pkgs.unstable.gnomeExtensions.restart-to                 # Restart-to menu entry
    pkgs.unstable.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
    pkgs.unstable.gnomeExtensions.background-logo            # Desktop background logo
    pkgs.unstable.gnomeExtensions.tiling-assistant           # Half- and quarter-tiling support
  ];
```

---

#### Block 4: `fonts.packages` (lines 249–258)

**Current code:**
```nix
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji  # renamed from noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];
```

**Replacement:**
```nix
    packages = [
      pkgs.noto-fonts
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-color-emoji  # renamed from noto-fonts-emoji
      pkgs.liberation_ttf
      pkgs.fira-code
      pkgs.fira-code-symbols
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.jetbrains-mono
    ];
```

Note: `pkgs.nerd-fonts.fira-code` and `pkgs.nerd-fonts.jetbrains-mono` already
carried explicit `pkgs.` prefixes inside the `with pkgs;` scope (redundant but
harmless in the original).  They are unchanged in form.

---

### 5b — `modules/development.nix`

#### Block: `environment.systemPackages` (lines 14–57)

**Current code:**
```nix
  environment.systemPackages = with pkgs; [

    # ── Editor ────────────────────────────────────────────────────────────────
    unstable.vscode-fhs                           # VS Code in FHS env (fixes launch on NixOS)

    # ── Python ────────────────────────────────────────────────────────────────
    python3                                       # CPython interpreter
    uv                                            # Fast Python package & project manager
    ruff                                          # Python linter & formatter

    # ── TypeScript / Node ─────────────────────────────────────────────────────
    nodePackages.typescript                       # TypeScript compiler (tsc)
    pnpm                                          # Fast, disk-efficient Node package manager
    bun                                           # All-in-one JS/TS runtime & bundler

    # ── Containers ────────────────────────────────────────────────────────────
    podman-compose                                # docker-compose compatible CLI for Podman
    buildah                                       # OCI image builder (rootless)
    skopeo                                        # Container image inspection & transfer

    # ── Flatpak development ───────────────────────────────────────────────────
    flatpak-builder                               # Build Flatpak application bundles

    # ── General dev utilities ─────────────────────────────────────────────────
    gh                                            # GitHub CLI
    git-lfs                                       # Git Large File Storage
    jq                                            # JSON processor / pretty-printer
    yq-go                                         # YAML / TOML / XML processor
    pre-commit                                    # Git hook framework
    sqlite                                        # Embedded SQL database + CLI
    httpie                                        # Human-friendly HTTP client
    mkcert                                        # Locally-trusted dev TLS certificates
    gcc                                           # C/C++ compiler (for native modules, etc.)

    # ── Nix tooling ───────────────────────────────────────────────────────────
    nil                                           # Nix LSP server
    nixpkgs-fmt                                   # Nix code formatter
    nix-output-monitor                            # Enhanced nix build output (nom)

    # ── Go ────────────────────────────────────────────────────────────────────
    go                                            # Go programming language

  ];
```

**Replacement:**
```nix
  environment.systemPackages = [

    # ── Editor ────────────────────────────────────────────────────────────────
    pkgs.unstable.vscode-fhs                      # VS Code in FHS env (fixes launch on NixOS)

    # ── Python ────────────────────────────────────────────────────────────────
    pkgs.python3                                  # CPython interpreter
    pkgs.uv                                       # Fast Python package & project manager
    pkgs.ruff                                     # Python linter & formatter

    # ── TypeScript / Node ─────────────────────────────────────────────────────
    pkgs.nodePackages.typescript                  # TypeScript compiler (tsc)
    pkgs.pnpm                                     # Fast, disk-efficient Node package manager
    pkgs.bun                                      # All-in-one JS/TS runtime & bundler

    # ── Containers ────────────────────────────────────────────────────────────
    pkgs.podman-compose                           # docker-compose compatible CLI for Podman
    pkgs.buildah                                  # OCI image builder (rootless)
    pkgs.skopeo                                   # Container image inspection & transfer

    # ── Flatpak development ───────────────────────────────────────────────────
    pkgs.flatpak-builder                          # Build Flatpak application bundles

    # ── General dev utilities ─────────────────────────────────────────────────
    pkgs.gh                                       # GitHub CLI
    pkgs.git-lfs                                  # Git Large File Storage
    pkgs.jq                                       # JSON processor / pretty-printer
    pkgs.yq-go                                    # YAML / TOML / XML processor
    pkgs.pre-commit                               # Git hook framework
    pkgs.sqlite                                   # Embedded SQL database + CLI
    pkgs.httpie                                   # Human-friendly HTTP client
    pkgs.mkcert                                   # Locally-trusted dev TLS certificates
    pkgs.gcc                                      # C/C++ compiler (for native modules, etc.)

    # ── Nix tooling ───────────────────────────────────────────────────────────
    pkgs.nil                                      # Nix LSP server
    pkgs.nixpkgs-fmt                              # Nix code formatter
    pkgs.nix-output-monitor                       # Enhanced nix build output (nom)

    # ── Go ────────────────────────────────────────────────────────────────────
    pkgs.go                                       # Go programming language

  ];
```

---

### 5c — `modules/gaming.nix`

Two `with pkgs;` blocks exist in this file.

#### Block 1: `programs.steam.extraCompatPackages` (line 16)

**Current code:**
```nix
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
```

**Replacement:**
```nix
    extraCompatPackages = [
      pkgs.proton-ge-bin
    ];
```

---

#### Block 2: `environment.systemPackages` (lines 44–69)

**Current code:**
```nix
  environment.systemPackages = with pkgs; [
    # Proton / Wine tooling
    protontricks    # winetricks wrapper for Steam games
    umu-launcher    # Proton launcher for non-Steam games

    # Display / overlay
    mangohud        # In-game performance overlay; use mangohud %command% in Steam launch options
    vkbasalt        # Vulkan post-processing layer (CAS, FXAA, etc.)

    # Wine (Staging + Wow64 multilib)
    wineWowPackages.stagingFull

    # Disk / prefix maintenance
    duperemove      # deduplicates Wine prefix content

    # Container tooling (Distrobox for running other distro environments)
    distrobox

    # Emulation
    ryubing         # Nintendo Switch emulator (Ryujinx fork)
    retroarch       # multi-system emulator frontend

    # Communication
    vesktop         # feature-rich Discord client (Vencord-based)
    discord         # official Discord client

    # NOTE: lutris, ProtonPlus, and Bottles are installed via Flatpak
    # (net.lutris.Lutris, com.vysp3r.ProtonPlus, and com.usebottles.bottles in modules/flatpak.nix).
  ];
```

**Replacement:**
```nix
  environment.systemPackages = [
    # Proton / Wine tooling
    pkgs.protontricks    # winetricks wrapper for Steam games
    pkgs.umu-launcher    # Proton launcher for non-Steam games

    # Display / overlay
    pkgs.mangohud        # In-game performance overlay; use mangohud %command% in Steam launch options
    pkgs.vkbasalt        # Vulkan post-processing layer (CAS, FXAA, etc.)

    # Wine (Staging + Wow64 multilib)
    pkgs.wineWowPackages.stagingFull

    # Disk / prefix maintenance
    pkgs.duperemove      # deduplicates Wine prefix content

    # Container tooling (Distrobox for running other distro environments)
    pkgs.distrobox

    # Emulation
    pkgs.ryubing         # Nintendo Switch emulator (Ryujinx fork)
    pkgs.retroarch       # multi-system emulator frontend

    # Communication
    pkgs.vesktop         # feature-rich Discord client (Vencord-based)
    pkgs.discord         # official Discord client

    # NOTE: lutris, ProtonPlus, and Bottles are installed via Flatpak
    # (net.lutris.Lutris, com.vysp3r.ProtonPlus, and com.usebottles.bottles in modules/flatpak.nix).
  ];
```

---

### Risk / notes (Change 5)

- All packages in these lists have been verified to be accessible via the
  `pkgs.` attribute path (some via the `unstable` overlay, e.g.
  `pkgs.unstable.vscode-fhs`).  The `unstable` overlay is applied in
  `flake.nix` `nixpkgs.overlays` for all outputs and the `mkBaseModule`
  wrappers.
- `pkgs.wineWowPackages.stagingFull` is a nested attribute path — valid with
  explicit prefix just as it was under `with pkgs;`.
- `pkgs.nodePackages.typescript` is similarly a nested path — no change in
  semantics.
- These changes have zero runtime impact: Nix evaluates `with pkgs; [ foo ]`
  and `[ pkgs.foo ]` identically.  The only effect is improved static
  analysis, removal of name-shadowing risk, and IDE/linter correctness.
- No other files contain `with pkgs;` in large package lists that fall within
  the scope of this batch (the `zfs-server.nix` and `gpu/*.nix` small
  `with pkgs;` lists are out of scope for this change set).
