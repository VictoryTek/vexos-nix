# laundry_list — Research & Specification

**Date**: 2026-04-20  
**Scope**: Multi-role batch changes across desktop, htpc, server, and stateless roles.

---

## Table of Contents

1. [Current State Analysis](#current-state-analysis)
2. [Item-by-Item Problem Definitions & Solutions](#item-by-item)
3. [Files to Be Modified](#files-to-be-modified)
4. [Risks & Mitigations](#risks--mitigations)

---

## Current State Analysis

### Module Import Graph (relevant subset)

| Role | Configuration file | Home file | GPU variants |
|------|--------------------|-----------|--------------|
| Desktop | `configuration-desktop.nix` | `home-desktop.nix` | amd, nvidia, intel, vm |
| HTPC | `configuration-htpc.nix` | `home-htpc.nix` | amd, nvidia, intel, vm |
| Server | `configuration-server.nix` | `home-server.nix` | amd, nvidia, intel, vm |
| Stateless | `configuration-stateless.nix` | `home-stateless.nix` | amd, nvidia, intel, vm |

All roles import `modules/gnome.nix`, `modules/packages.nix`, `modules/branding.nix`, `modules/flatpak.nix`.

### Key architectural facts

- **System dconf** (`modules/gnome.nix` → `programs.dconf.profiles.user.databases`): written at `nixos-rebuild switch`; available before any session starts. Uses `config.vexos.branding.role` for role-conditional logic.
- **Home Manager dconf** (role-specific `home-*.nix` + `home/gnome-common.nix`): applied at HM activation; has _lower_ precedence than system dconf in the lookup chain (user-db:user → system-db). Home Manager dconf.settings for the same key path are **merged** at module level.
- **Flatpak defaults** (`modules/flatpak.nix` `defaultApps`): Installed on first boot. Roles exclude unwanted apps via `vexos.flatpak.excludeApps`.
- **Stateless impermanence**: `/` is a tmpfs. `/etc/nixos` is bind-mounted from `/persistent/etc/nixos`. NixOS `etc` activation creates symlinks; the activation may run before this bind mount is established (see Item 7).
- **Justfile deployment**: `home-*.nix` uses `home.file."justfile".source = ./justfile` — deploys a **symlink** at `~/justfile` → Nix store path. `{{justfile_directory()}}` in Just expands to `~`, not the repo root.

---

## Item-by-Item

---

### Item 1 — GNOME Extension Manager installed globally (ALL ROLES)

#### Current state

- `modules/flatpak.nix` `defaultApps` includes `"com.mattjakeman.ExtensionManager"`.
- `configuration-server.nix` `vexos.flatpak.excludeApps` contains `"com.mattjakeman.ExtensionManager"` → **not installed on server**.
- `configuration-htpc.nix` `vexos.flatpak.excludeApps` contains `"com.mattjakeman.ExtensionManager"` → **not installed on htpc**.
- `configuration-desktop.nix` has `unstable.gnome-extension-manager` as a Nix package (with comment "desktop only") AND the Flatpak is not excluded.
- `configuration-stateless.nix` has no `excludeApps` override → Flatpak installed.
- `home-htpc.nix` Utilities app-folder already lists `"com.mattjakeman.ExtensionManager.desktop"`.
- `home-server.nix` Utilities app-folder does **not** list `"com.mattjakeman.ExtensionManager.desktop"`.

#### Problem

Extension Manager is unavailable on server and htpc because both explicitly exclude it.

#### Solution

1. **`configuration-desktop.nix`**: Remove `unstable.gnome-extension-manager` from the desktop-only `environment.systemPackages` block (it will move to `modules/gnome.nix`).
2. **`modules/gnome.nix`**: Add `unstable.gnome-extension-manager` to `environment.systemPackages` so it is installed system-wide on all roles.
3. **`configuration-server.nix`**: Remove `"com.mattjakeman.ExtensionManager"` from `vexos.flatpak.excludeApps`.
4. **`configuration-htpc.nix`**: Remove `"com.mattjakeman.ExtensionManager"` from `vexos.flatpak.excludeApps`.
5. **`home-server.nix`**: Add `"com.mattjakeman.ExtensionManager.desktop"` to the Utilities app-folder list.

```nix
# modules/gnome.nix — add to existing environment.systemPackages block:
environment.systemPackages = with pkgs; [
  unstable.gnome-extension-manager
  bibata-cursors
  kora-icon-theme
];
```

```nix
# configuration-server.nix — remove this line from excludeApps:
# "com.mattjakeman.ExtensionManager"

# configuration-htpc.nix — remove this line from excludeApps:
# "com.mattjakeman.ExtensionManager"  # puzzle-piece icon; not needed on HTPC
```

```nix
# home-server.nix — add to Utilities folder apps list:
"org/gnome/desktop/app-folders/folders/Utilities" = {
  name = "Utilities";
  apps = [
    "com.mattjakeman.ExtensionManager.desktop"  # ADD
    "it.mijorus.gearlever.desktop"
    "org.gnome.tweaks.desktop"
    "io.github.flattool.Warehouse.desktop"
    "io.missioncenter.MissionCenter.desktop"
    "com.github.tchx84.Flatseal.desktop"
    "org.gnome.World.PikaBackup.desktop"
  ];
};
```

---

### Item 2 — xterm removed from packages (ALL ROLES)

#### Current state

`xterm` is part of NixOS `environment.defaultPackages` (installed automatically when `services.xserver.enable = true`). Its desktop entry is hidden via `xdg.desktopEntries."xterm"` / `"uxterm"` in `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix`, but the package itself remains installed.

`home-htpc.nix` does not even hide the desktop entry (HTPC home file only hides `org.gnome.Extensions`).

#### Problem

xterm remains installed and accessible (e.g., via terminal emulator fallback, Ctrl+Alt+T in some setups). The intent is to remove it entirely.

#### Solution

Add `services.xserver.excludePackages = lib.mkDefault [ pkgs.xterm ];` to `modules/gnome.nix`. This NixOS option removes packages from the default X11 installation set and is the idiomatic way to exclude xterm on GNOME/X11 NixOS systems. Since `modules/gnome.nix` is imported by all four roles, this is a single-location global change. `lib.mkDefault` allows a host file to override if xterm is ever explicitly required somewhere.

The `xdg.desktopEntries."xterm"` / `"uxterm"` entries in home files can be removed as cleanup (xterm will no longer be installed), but leave them as belt-and-suspenders if desired — they are harmless.

```nix
# modules/gnome.nix — add alongside services.desktopManager.gnome.enable:
services.xserver.excludePackages = lib.mkDefault [ pkgs.xterm ];
```

---

### Item 3 — Server GNOME dconf: color-scheme='prefer-dark', accent-color='yellow'

#### Current state

`modules/gnome.nix` system dconf `"org/gnome/desktop/interface"` key sets `cursor-theme`, `icon-theme`, `clock-format` — no `color-scheme` or `accent-color`.

`home/gnome-common.nix` sets the same three keys in the HM dconf layer — no `color-scheme` or `accent-color`.

`home-server.nix` has a `dconf.settings` block with `"org/gnome/shell"`, power, and app-folder keys — no `"org/gnome/desktop/interface"` override.

#### Solution

Three coordinated changes:

**A. `home/gnome-common.nix`** — add `color-scheme = "prefer-dark"` to the common interface block (all roles share dark mode):

```nix
"org/gnome/desktop/interface" = {
  clock-format = "12h";
  cursor-theme = "Bibata-Modern-Classic";
  icon-theme   = "kora";
  color-scheme = "prefer-dark";   # ADD
};
```

**B. `home-server.nix`** — add a `"org/gnome/desktop/interface"` key to the existing `dconf.settings` block (Home Manager merges same-path keys across modules):

```nix
dconf.settings = {
  # ... existing keys unchanged ...

  "org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    accent-color = "yellow";
  };
};
```

**C. `modules/gnome.nix`** system dconf — add `color-scheme` and role-mapped `accent-color` to the system database (ensures settings are available before HM activation, e.g. at autoLogin):

```nix
# In the let block, derive accentColor from the role:
accentColor = {
  desktop   = "blue";
  htpc      = "orange";
  server    = "yellow";
  stateless = "teal";
}.${role};

# In the settings block:
"org/gnome/desktop/interface" = {
  cursor-theme = "Bibata-Modern-Classic";
  icon-theme   = "kora";
  clock-format = "12h";
  color-scheme = "prefer-dark";   # ADD
  accent-color = accentColor;     # ADD
};
```

---

### Item 4 — `just enable` command cannot locate template

#### Current state

The `enable` recipe in `justfile` searches for `template/server-services.nix` using:

```bash
for _candidate in "{{justfile_directory()}}" "/etc/nixos" "$HOME/Projects/vexos-nix"; do
```

`{{justfile_directory()}}` is a Just built-in that expands at **parse time** to the directory containing the justfile **as it appears in the filesystem**. Because `home-*.nix` deploys the justfile as a symlink (`home.file."justfile".source = ./justfile` → symlink at `~/justfile`), Just sees the justfile at `~` and `{{justfile_directory()}}` therefore returns `~` (not the repo root). `~/template/server-services.nix` does not exist → error.

The `_resolve-flake-dir` recipe already works around this identically: it uses `readlink -f "{{justfile()}}"` to resolve the symlink chain to the real file path, then `dirname` to get the actual repo directory. The `enable` recipe is missing this same symlink resolution.

#### Solution

Replace the first candidate in the `for` loop with symlink-resolved `_jf_dir`, following the exact pattern from `_resolve-flake-dir`:

```bash
# BEFORE (broken):
if [ ! -f "$SVC_FILE" ]; then
    echo "Creating $SVC_FILE from template..."
    TEMPLATE_SRC=""
    for _candidate in "{{justfile_directory()}}" "/etc/nixos" "$HOME/Projects/vexos-nix"; do

# AFTER (fixed):
if [ ! -f "$SVC_FILE" ]; then
    echo "Creating $SVC_FILE from template..."
    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    _jf_dir=$(dirname "$_jf_real")
    TEMPLATE_SRC=""
    for _candidate in "$_jf_dir" "/etc/nixos" "$HOME/Projects/vexos-nix"; do
```

Only the `enable` recipe needs this change; the `disable` recipe does not do template lookup (it requires the file to already exist).

---

### Item 5 — Stateless GNOME dconf: color-scheme='prefer-dark', accent-color='teal'

#### Current state

`home-stateless.nix` has a `dconf.settings` block with `"org/gnome/shell"`, favorites, and app-folder keys — no `"org/gnome/desktop/interface"` override. The common block in `home/gnome-common.nix` sets interface keys without `color-scheme` or `accent-color`.

#### Solution

`color-scheme` is added globally via Item 3 (change A to `home/gnome-common.nix`). The stateless-specific accent-color is added in `home-stateless.nix`:

```nix
# home-stateless.nix — add to existing dconf.settings block:
"org/gnome/desktop/interface" = {
  color-scheme = "prefer-dark";
  accent-color = "teal";
};
```

The system-level dconf in `modules/gnome.nix` (Item 3, change C) also covers stateless since the `accentColor` map includes `stateless = "teal"`.

---

### Item 6 — tor-browser installed on stateless

#### Current state

`configuration-stateless.nix` and `home-stateless.nix` have no `tor-browser` reference. The stateless role is designed for ephemeral, privacy-aware use (Tails-like model), making Tor Browser a natural fit.

#### Solution

Add `tor-browser` to `home-stateless.nix`'s `home.packages`:

```nix
# home-stateless.nix — add to home.packages:
home.packages = with pkgs; [
  tor-browser   # ADD: Privacy browser routing traffic through Tor

  # Terminal emulator
  ghostty
  # ... existing packages unchanged ...
];
```

`pkgs.tor-browser` is the correct nixpkgs attribute name (replaces the deprecated `tor-browser-bundle-bin`).

---

### Item 7 — vexos-variant file not persisting between stateless boots

#### Root cause analysis

The `vexos-variant` file is written by `template/etc-nixos-flake.nix` (the thin wrapper deployed to `/etc/nixos` on production machines) via:

```nix
{ environment.etc."nixos/vexos-variant".text = "${variant}"; }
```

`environment.etc` creates a **symlink** at `/etc/nixos/vexos-variant` → `/etc/static/nixos/vexos-variant` (a path inside the current system's Nix store derivation) during the NixOS `etc` activation phase.

**The timing race**: NixOS `nixos-activation.service` (which runs the `etc` activation) has `After = sysinit.target local-fs-pre.target` in its systemd unit. The impermanence bind-mount unit for `/etc/nixos` (`persistent-etc-nixos.mount` or similar) is part of `local-fs.target`. Because `nixos-activation.service` does **not** explicitly declare `After = local-fs.target`, the `etc` activation can race ahead of the bind mounts and run while `/etc/nixos` is still the bare tmpfs directory (before impermanence bind-mounts `/persistent/etc/nixos` into it). The symlink lands in the ephemeral tmpfs `/etc/nixos`, is subsequently hidden by the bind mount, and never reaches persistent storage.

After any later `nixos-rebuild switch` from the running system (where the bind mount is already active), the `etc` activation correctly writes the symlink to persistent. But on the very next reboot the timing race occurs again and the file is gone.

**Secondary issue**: The repo's own `nixosConfigurations.vexos-stateless-*` outputs do **not** include `{ environment.etc."nixos/vexos-variant"... }` at all — that module is only in the thin wrapper template. So when building directly from the repo, `vexos-variant` is never created at all.

#### Solution

Replace the `environment.etc` approach (symlink into store) with a direct `system.activationScripts` write that targets the **raw persistent path** (`/persistent/etc/nixos/vexos-variant`) bypassing the bind mount entirely. The persistent Btrfs subvolume at `/persistent` is mounted during early initrd, long before systemd stage 2, making it reliably available when the activation script runs.

**Step 1** — Add a `vexos.variant` NixOS option to `modules/impermanence.nix`:

```nix
# modules/impermanence.nix — add to options block:
options.vexos.variant = lib.mkOption {
  type        = lib.types.str;
  default     = "";
  description = ''
    Active build variant name (e.g. "vexos-stateless-amd").
    When set and vexos.impermanence.enable = true, the value is written
    directly to /persistent/etc/nixos/vexos-variant at activation time,
    bypassing the timing race between the NixOS etc activation and the
    impermanence bind mount for /etc/nixos.
  '';
};
```

**Step 2** — Add an `activationScript` in `modules/impermanence.nix` (inside `config = lib.mkIf cfg.enable`):

```nix
# modules/impermanence.nix — add to the config = lib.mkIf cfg.enable block:
system.activationScripts.vexosVariant = lib.mkIf (config.vexos.variant != "") {
  deps = [ "etc" ];
  text = ''
    # Write the variant name directly to the Btrfs persistent subvolume,
    # not through the bind-mounted /etc/nixos path.  The /persistent
    # subvolume is mounted in initrd (before systemd stage 2), so this
    # write is guaranteed to land in persistent storage regardless of
    # bind-mount ordering.
    PERSIST_DIR="${cfg.persistentPath}/etc/nixos"
    ${pkgs.coreutils}/bin/mkdir -p "$PERSIST_DIR"
    ${pkgs.coreutils}/bin/printf '%s' '${config.vexos.variant}' \
      > "$PERSIST_DIR/vexos-variant"
  '';
};
```

**Step 3** — Set `vexos.variant` in each stateless host file:

```nix
# hosts/stateless-amd.nix
vexos.variant = "vexos-stateless-amd";

# hosts/stateless-nvidia.nix
vexos.variant = "vexos-stateless-nvidia";

# hosts/stateless-intel.nix
vexos.variant = "vexos-stateless-intel";

# hosts/stateless-vm.nix
vexos.variant = "vexos-stateless-vm";
```

**Step 4** — Update `template/etc-nixos-flake.nix`: change the thin-wrapper's `environment.etc` entry to also use the activationScript pattern so that production deployments use the same robust approach:

```nix
# template/etc-nixos-flake.nix — replace:
# { environment.etc."nixos/vexos-variant".text = "${variant}"; }

# with:
{
  system.activationScripts.vexosVariant = ''
    # Write variant directly to persistent subvolume, bypassing bind-mount timing
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

Note: the thin wrapper uses a plain string (no `${pkgs.coreutils}`) because `/persistent` is always mounted in the initrd and basic POSIX tools are available in the activation environment.

---

### Item 8 — PhotoGimp removed (STATELESS)

#### Current state

`home-stateless.nix` does **not** import `./home/photogimp.nix`. PhotoGimp is only imported in `home-desktop.nix` via `photogimp.enable = true`. `org.gimp.GIMP` is not present in `modules/flatpak.nix`'s `defaultApps` list and is not in `modules/gnome.nix`'s GNOME app install list.

#### Problem

**No action required.** PhotoGimp is already absent from the stateless role. `home-stateless.nix` does not import `photogimp.nix` and GIMP is not installed via Flatpak defaults for stateless.

As a defensive measure, `org.gimp.GIMP` can be added to `configuration-stateless.nix`'s `vexos.flatpak.excludeApps` to make intent explicit and guard against future defaultApps additions. This is optional.

---

### Item 9 — Desktop GNOME dconf: color-scheme='prefer-dark', accent-color='blue'

#### Current state

`home-desktop.nix` has a `dconf.settings` block with `"org/gnome/shell"`, app-folder keys, etc. — no `"org/gnome/desktop/interface"` override. `home/gnome-common.nix` provides the common interface keys.

#### Solution

`color-scheme` is covered by Item 3 (change A to `home/gnome-common.nix`). Add `accent-color` in `home-desktop.nix`:

```nix
# home-desktop.nix — add to existing dconf.settings block:
"org/gnome/desktop/interface" = {
  color-scheme = "prefer-dark";
  accent-color = "blue";
};
```

The system-level dconf in `modules/gnome.nix` (Item 3, change C) also covers desktop since the `accentColor` map includes `desktop = "blue"`.

---

### Item 10 — HTPC GNOME dconf: color-scheme='prefer-dark', accent-color='orange'

#### Current state

`home-htpc.nix` has a `dconf.settings` block. No `"org/gnome/desktop/interface"` override in the home file.

`configuration-htpc.nix` has an additional **system-level** dconf block (`programs.dconf.profiles.user.databases`) that sets `"org/gnome/desktop/interface"` with `cursor-theme`, `cursor-size`, `icon-theme`, `clock-format` — but no `color-scheme` or `accent-color`.

#### Solution

Two changes needed (HTPC is the only role with a system dconf block in its configuration file):

**A. `home-htpc.nix`** — add to `dconf.settings`:

```nix
"org/gnome/desktop/interface" = {
  color-scheme = "prefer-dark";
  accent-color = "orange";
};
```

**B. `configuration-htpc.nix`** — add to the system-level dconf `settings."org/gnome/desktop/interface"` block:

```nix
settings."org/gnome/desktop/interface" = {
  cursor-theme = "Bibata-Modern-Classic";
  cursor-size  = lib.gvariant.mkInt32 24;
  icon-theme   = "kora";
  clock-format = "12h";
  color-scheme = "prefer-dark";   # ADD
  accent-color = "orange";         # ADD
};
```

The `modules/gnome.nix` system dconf (Item 3, change C) also covers HTPC via `accentColor` map `htpc = "orange"`. The HTPC-specific database in `configuration-htpc.nix` takes precedence over the gnome.nix database entry since it is a separate database entry evaluated at a higher (config-file) scope — both entries together form belt-and-suspenders.

---

### Item 11 — only-office removed (HTPC)

#### Current state

`configuration-htpc.nix` `vexos.flatpak.excludeApps` does **not** include `"org.onlyoffice.desktopeditors"`, so the Flatpak is installed via the `defaultApps` list in `modules/flatpak.nix`.

`home-htpc.nix` Office app-folder lists:
```nix
"org/gnome/desktop/app-folders/folders/Office" = {
  name = "Office";
  apps = [
    "org.onlyoffice.desktopeditors.desktop"
    "org.gnome.TextEditor.desktop"
  ];
};
```

#### Solution

1. **`configuration-htpc.nix`** — add `"org.onlyoffice.desktopeditors"` to `vexos.flatpak.excludeApps`:

```nix
vexos.flatpak.excludeApps = [
  "org.gimp.GIMP"
  "com.ranfdev.DistroShelf"
  "com.mattjakeman.ExtensionManager"  # REMOVE — now global (Item 1)
  "com.vysp3r.ProtonPlus"
  "net.lutris.Lutris"
  "org.prismlauncher.PrismLauncher"
  "io.github.pol_rivero.github-desktop-plus"
  "org.onlyoffice.desktopeditors"    # ADD
];
```

Note: `"com.mattjakeman.ExtensionManager"` must also be removed per Item 1.

2. **`home-htpc.nix`** — remove `"org.onlyoffice.desktopeditors.desktop"` from the Office folder:

```nix
"org/gnome/desktop/app-folders/folders/Office" = {
  name = "Office";
  apps = [
    "org.gnome.TextEditor.desktop"
  ];
};
```

---

## Files to Be Modified

| File | Items | Type of change |
|------|-------|---------------|
| `modules/gnome.nix` | 1, 2, 3, 5, 9, 10 | Add Extension Manager pkg; add xterm exclusion; add color-scheme + accentColor map to system dconf |
| `modules/impermanence.nix` | 7 | Add `vexos.variant` option + `vexosVariant` activationScript |
| `modules/packages.nix` | — | No changes |
| `configuration-desktop.nix` | 1 | Remove `unstable.gnome-extension-manager` (moved to gnome.nix) |
| `configuration-htpc.nix` | 1, 10, 11 | Remove ExtensionManager from excludeApps; add onlyoffice to excludeApps; add color-scheme+accent-color to system dconf |
| `configuration-server.nix` | 1 | Remove ExtensionManager from excludeApps |
| `configuration-stateless.nix` | — | No changes required (Item 8 already satisfied) |
| `home/gnome-common.nix` | 3, 5, 9, 10 | Add `color-scheme = "prefer-dark"` to interface block |
| `home-desktop.nix` | 9 | Add `"org/gnome/desktop/interface"` override with accent-color='blue' |
| `home-htpc.nix` | 10, 11 | Add interface override with accent-color='orange'; remove onlyoffice from Office folder |
| `home-server.nix` | 1, 3 | Add ExtensionManager to Utilities folder; add interface override with accent-color='yellow' |
| `home-stateless.nix` | 5, 6 | Add interface override with accent-color='teal'; add `tor-browser` to packages |
| `hosts/stateless-amd.nix` | 7 | Set `vexos.variant = "vexos-stateless-amd"` |
| `hosts/stateless-nvidia.nix` | 7 | Set `vexos.variant = "vexos-stateless-nvidia"` |
| `hosts/stateless-intel.nix` | 7 | Set `vexos.variant = "vexos-stateless-intel"` |
| `hosts/stateless-vm.nix` | 7 | Set `vexos.variant = "vexos-stateless-vm"` |
| `justfile` | 4 | Add `readlink -f` / `dirname` symlink resolution to `enable` recipe |
| `template/etc-nixos-flake.nix` | 7 | Replace `environment.etc."nixos/vexos-variant"` with `system.activationScripts.vexosVariant` direct-write-to-persistent pattern |

---

## Risks & Mitigations

### Risk 1 — dconf key support (accent-color requires GNOME 47+)

`org.gnome.desktop.interface accent-color` was added in GNOME 47. The project pins GNOME stack to `nixpkgs-unstable` via overlay. As of NixOS 25.11 + current unstable, GNOME 48 is available, so the key is supported.

**Mitigation**: No action needed. The GNOME version from the unstable overlay supports both `color-scheme` (GNOME 42+) and `accent-color` (GNOME 47+).

### Risk 2 — Home Manager dconf key merging

Home Manager merges `dconf.settings` across imported modules at the attribute level. Adding `"org/gnome/desktop/interface"` in a role-specific home file alongside `home/gnome-common.nix` (which also defines this key) is safe — the keys within the set are unioned.

**Mitigation**: Verify there are no duplicate leaf keys (same key set in both common and role file). Currently gnome-common sets `clock-format`, `cursor-theme`, `icon-theme`; role files will add `color-scheme` and `accent-color`. No overlap.

### Risk 3 — xterm exclusion breaking terminal fallback

On NixOS GNOME, `services.xserver.excludePackages = [ pkgs.xterm ]` removes xterm from the default X11 package set. If any module or service declares xterm as a hard dependency via `environment.systemPackages`, it would still be installed (the exclusion only affects the X11 default set).

**Mitigation**: `modules/gnome.nix` and `modules/packages.nix` do not explicitly list xterm. The standard NixOS GNOME stack does not require xterm. The existing `xdg.desktopEntries."xterm"` / `"uxterm"` masking in home files can remain as belt-and-suspenders.

### Risk 4 — vexos-variant activationScript conflicts with environment.etc

If the thin wrapper at `/etc/nixos/flake.nix` still uses `environment.etc."nixos/vexos-variant"` while the impermanence module writes the real file to `/persistent/etc/nixos/vexos-variant`, the old thin wrapper would try to create a **symlink** at a path where a real file already exists.

NixOS `etc` activation handles this: if the target already exists and is a regular file (not a symlink), the activation would overwrite or rename it depending on mode. To avoid conflict, the thin wrapper template **must also be updated** to use the activationScript pattern (Item 7 Step 4). Until updated, the `etc` activation would overwrite the real file with a symlink — which still works as long as `/etc/static` is set up.

**Mitigation**: Update `template/etc-nixos-flake.nix` as part of this change set (included in files to be modified).

### Risk 5 — pkgs availability in activationScript (impermanence module)

`modules/impermanence.nix` receives `pkgs` as a module argument, so `${pkgs.coreutils}/bin/mkdir` and `${pkgs.coreutils}/bin/printf` are valid references. The Nix store path for coreutils is baked in at build time, ensuring the activation script works without relying on PATH.

**Mitigation**: Use explicit `${pkgs.coreutils}/bin/` prefixes in all activationScript commands.

### Risk 6 — HTPC has dual dconf layers (system + HM)

`configuration-htpc.nix` has a NixOS-level `programs.dconf.profiles.user.databases` entry that sets `"org/gnome/desktop/interface"`. The Home Manager `home-htpc.nix` dconf layer ALSO sets this key (via gnome-common + the new role override). Since the HM dconf profile lookup is `user-db:user → system-db`, HM dconf takes precedence for any key set in both layers.

**Mitigation**: Set both layers to the same values. This is belt-and-suspenders and avoids confusion about which layer wins.

### Risk 7 — statelessBase nixosModule uses home-desktop.nix (pre-existing bug)

In `flake.nix`, `nixosModules.statelessBase` (used by the thin wrapper template) declares `users.nimda = import ./home-desktop.nix` instead of `./home-stateless.nix`. This means thin-wrapper users get the **desktop** Home Manager profile (including PhotoGimp, rustup, gaming packages) on their stateless machine. This is a pre-existing bug not in this task's scope.

**Mitigation (out of scope)**: Note it for a future fix. The repo-direct builds (`nixosConfigurations.vexos-stateless-*`) are unaffected — they use `statelessHomeManagerModule` which correctly references `home-stateless.nix`.

### Risk 8 — tor-browser nixpkgs attribute name

`pkgs.tor-browser` is the current attribute in nixpkgs (replacing the deprecated `tor-browser-bundle-bin`). The nixpkgs-stable 25.11 attribute is confirmed.

**Mitigation**: Use `pkgs.tor-browser`. If the build fails, `pkgs.tor-browser-bundle-bin` is the fallback.

---

## Summary

| # | Description | File(s) | Complexity |
|---|-------------|---------|------------|
| 1 | Extension Manager globally | gnome.nix, config-desktop, config-htpc, config-server, home-server | Low |
| 2 | xterm removed globally | gnome.nix | Trivial |
| 3 | Server dark + yellow accent | gnome.nix, gnome-common.nix, home-server.nix | Low |
| 4 | just enable template fix | justfile | Trivial |
| 5 | Stateless dark + teal accent | home-stateless.nix (covered by 3 for gnome.nix + common) | Low |
| 6 | tor-browser on stateless | home-stateless.nix | Trivial |
| 7 | vexos-variant persistence | impermanence.nix, 4× hosts/stateless-*.nix, template | Medium |
| 8 | PhotoGimp removed (stateless) | Already satisfied — no changes | None |
| 9 | Desktop dark + blue accent | home-desktop.nix (covered by 3 for gnome.nix + common) | Low |
| 10 | HTPC dark + orange accent | configuration-htpc.nix, home-htpc.nix (+ 3 for common) | Low |
| 11 | only-office removed (HTPC) | configuration-htpc.nix, home-htpc.nix | Low |
