# Specification: Deduplicate `commonExtensions` GNOME Shell Extension List

**Feature name:** `common_extensions`
**Spec file:** `.github/docs/subagent_docs/common_extensions_spec.md`
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

### 1.1 Duplicated list — exact content

All four role files contain an **identical** `let` binding. The list below is
byte-for-byte the same in every file (verified by reading each file):

```nix
commonExtensions = [
  "appindicatorsupport@rgcjonas.gmail.com"
  "dash-to-dock@micxgx.gmail.com"
  "AlphabeticalAppGrid@stuarthayhurst"
  "gnome-ui-tune@itstime.tech"
  "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
  "steal-my-focus-window@steal-my-focus-window"
  "tailscale-status@maxgallup.github.com"
  "caffeine@patapon.info"
  "restartto@tiagoporsch.github.io"
  "blur-my-shell@aunetx"
  "background-logo@fedorahosted.org"
  "tiling-assistant@leleat-on-github"
];
```

**12 entries. Identical across all four files. No per-role differences.**

### 1.2 How `enabled-extensions` is built in each role file

| File | `enabled-extensions` expression | Location |
|------|--------------------------------|----------|
| `modules/gnome-desktop.nix` | `commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ]` | line ~48 |
| `modules/gnome-htpc.nix` | `commonExtensions` (bare) | line ~33 |
| `modules/gnome-server.nix` | `commonExtensions` (bare) | line ~32 |
| `modules/gnome-stateless.nix` | `commonExtensions` (bare) | line ~32 |

`gnome-desktop.nix` is the **only** role that appends a role-specific extension
(`gamemodeshellextension@trsnaqe.com`) on top of the common list.

### 1.3 Import chain (all four role files → gnome.nix)

Every role file contains `imports = [ ./gnome.nix ]` at the top of its module
body. Therefore any option declared in `gnome.nix` is unconditionally visible to
all four role files via `config.vexos.gnome.*`.

### 1.4 Current `gnome.nix` structure

`modules/gnome.nix` is currently a **flat config-only module** — it contains no
`options.*` declarations of its own. It does contain:

```nix
imports = [ ./gnome-flatpak-install.nix ];
```

`gnome-flatpak-install.nix` (imported by `gnome.nix`) already declares:

```nix
options.vexos.gnome.flatpakInstall = {
  apps        = lib.mkOption { ... };
  extraRemoves = lib.mkOption { ... };
};
```

The `options.vexos.gnome` namespace therefore already exists in the module
evaluation tree for every role that imports `gnome.nix`. Adding
`options.vexos.gnome.commonExtensions` to `gnome.nix` itself introduces a new
sibling attribute under the same namespace — no conflict.

### 1.5 Existing `options.vexos.*` conventions in the project

The codebase uses `options.vexos.<subsystem>.<optionName>` throughout. Relevant
precedents:

- `options.vexos.gnome.flatpakInstall.apps` — `lib.types.listOf lib.types.str`,
  `default = []`, no `internal` flag (it is user-facing per-role config).
- `options.vexos.user.name` — scalar string option.
- `options.vexos.branding.role` — scalar string option.

`internal = true` is used in NixOS for options that are part of the module
system's internal plumbing and should not appear in user-facing NixOS option
documentation (`nixos-option`, `man configuration.nix`). The
`commonExtensions` list is shared infrastructure, not something end users
configure directly, so `internal = true` is appropriate.

---

## 2. Problem Statement

The 12-entry `commonExtensions` list is copy-pasted verbatim into four separate
files. There is no single source of truth. Any future addition, removal, or
rename of a shared extension requires four identical edits, and the risk of
the four copies diverging silently is permanently present. The project's own
architecture rules (Option B: Common base + role additions) require shared
content to live in the base module, not in role files.

---

## 3. Proposed Solution

### 3.1 Architecture decision

Per the project's **Option B** rule:

- Shared content that applies to every role importing `gnome.nix` belongs in
  `gnome.nix`.
- Role files express their role through their import list; no `lib.mkIf`
  guards by role are permitted inside the base file.

The `commonExtensions` list is unconditionally shared across all four roles.
It belongs in `gnome.nix` as a NixOS option whose **default value** is the
canonical list. Role files then reference `config.vexos.gnome.commonExtensions`
instead of maintaining a private copy.

### 3.2 Option declaration to add to `gnome.nix`

Add the following option declaration **at the top level** of the `gnome.nix`
attribute set (i.e., as a sibling of `imports`, `services`, `environment`,
etc.):

```nix
options.vexos.gnome.commonExtensions = lib.mkOption {
  type        = lib.types.listOf lib.types.str;
  default     = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
    "tiling-assistant@leleat-on-github"
  ];
  internal    = true;
  description = "GNOME Shell extensions enabled on every vexos role that imports gnome.nix.";
};
```

**Why flat placement works:** The NixOS module system treats any attribute in a
module's return set that is not `imports`, `options`, `config`, or `meta` as an
implicit config assignment. An `options.*` key at the top level is always
processed as an option declaration regardless of whether a `config = { ... }`
wrapper is present. Adding `options.vexos.gnome.commonExtensions` alongside
the existing flat config attributes in `gnome.nix` requires no structural
refactor of the file.

**Where to insert:** Place the `options.vexos.gnome.commonExtensions` declaration
immediately after the closing `]` of `imports = [ ./gnome-flatpak-install.nix ];`
and before the first `nixpkgs.overlays` assignment. This groups it with the
module's interface declarations at the top.

### 3.3 Changes required in each role file

#### `modules/gnome-desktop.nix`

**Remove** the entire `let … in` block (lines 8–23 approximately):

```nix
# REMOVE THIS ENTIRE BLOCK:
let
  # Common shell extensions enabled on every role.
  commonExtensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
    "tiling-assistant@leleat-on-github"
  ];
in
```

**Change** the `enabled-extensions` line:

```nix
# BEFORE:
enabled-extensions =
  commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ];

# AFTER:
enabled-extensions =
  config.vexos.gnome.commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ];
```

The `{ config, pkgs, lib, ... }:` function signature already binds `config`;
no header change needed.

#### `modules/gnome-htpc.nix`

**Remove** the entire `let … in` block (lines 6–21 approximately):

```nix
# REMOVE THIS ENTIRE BLOCK:
let
  # Common shell extensions enabled on every role.
  commonExtensions = [
    "appindicatorsupport@rgcjonas.gmail.com"
    "dash-to-dock@micxgx.gmail.com"
    "AlphabeticalAppGrid@stuarthayhurst"
    "gnome-ui-tune@itstime.tech"
    "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
    "steal-my-focus-window@steal-my-focus-window"
    "tailscale-status@maxgallup.github.com"
    "caffeine@patapon.info"
    "restartto@tiagoporsch.github.io"
    "blur-my-shell@aunetx"
    "background-logo@fedorahosted.org"
    "tiling-assistant@leleat-on-github"
  ];
in
```

**Change** the `enabled-extensions` line:

```nix
# BEFORE:
enabled-extensions = commonExtensions;

# AFTER:
enabled-extensions = config.vexos.gnome.commonExtensions;
```

#### `modules/gnome-server.nix`

**Remove** the entire `let … in` block (identical to the htpc block above).

**Change** the `enabled-extensions` line:

```nix
# BEFORE:
enabled-extensions = commonExtensions;

# AFTER:
enabled-extensions = config.vexos.gnome.commonExtensions;
```

#### `modules/gnome-stateless.nix`

**Remove** the entire `let … in` block (identical to the htpc block above).

**Change** the `enabled-extensions` line:

```nix
# BEFORE:
enabled-extensions = commonExtensions;

# AFTER:
enabled-extensions = config.vexos.gnome.commonExtensions;
```

---

## 4. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Lists actually differ between roles (silent divergence already occurred) | **Critical** | Verified by reading all four files — lists are byte-for-byte identical. No divergence. |
| `options.vexos.gnome.*` namespace collision with `gnome-flatpak-install.nix` | Low | `flatpakInstall` and `commonExtensions` are different sub-attributes; no collision. |
| `gnome.nix` structural refactor breaks evaluation | Low | The NixOS module system allows `options.*` at the top level alongside flat config attributes. No structural refactor required. |
| Role file references `config.vexos.gnome.commonExtensions` before `gnome.nix` is evaluated | None | NixOS module evaluation is lazy and order-independent; all modules in the import closure are merged before any `config.*` value is resolved. |
| `nix flake check` fails due to option type mismatch | Low | `programs.dconf.profiles.user.databases` settings accept Nix lists for GVariant array keys; the type `listOf str` matches the existing usage. |

---

## 5. Implementation Steps (in order)

1. **Edit `modules/gnome.nix`**
   - Insert the `options.vexos.gnome.commonExtensions` declaration immediately
     after the closing `]` of `imports = [ ./gnome-flatpak-install.nix ];`.

2. **Edit `modules/gnome-desktop.nix`**
   - Remove the `let commonExtensions = [...]; in` block.
   - Change `enabled-extensions = commonExtensions ++ [...]` to
     `config.vexos.gnome.commonExtensions ++ [...]`.

3. **Edit `modules/gnome-htpc.nix`**
   - Remove the `let commonExtensions = [...]; in` block.
   - Change `enabled-extensions = commonExtensions` to
     `config.vexos.gnome.commonExtensions`.

4. **Edit `modules/gnome-server.nix`**
   - Remove the `let commonExtensions = [...]; in` block.
   - Change `enabled-extensions = commonExtensions` to
     `config.vexos.gnome.commonExtensions`.

5. **Edit `modules/gnome-stateless.nix`**
   - Remove the `let commonExtensions = [...]; in` block.
   - Change `enabled-extensions = commonExtensions` to
     `config.vexos.gnome.commonExtensions`.

6. **Validate**
   - Run `nix flake check` to confirm the flake evaluates cleanly.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to confirm
     the desktop closure builds.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` and
     `.#vexos-desktop-vm` as additional sanity checks.

---

## 6. Files Modified

| File | Change |
|------|--------|
| `modules/gnome.nix` | Add `options.vexos.gnome.commonExtensions` option declaration |
| `modules/gnome-desktop.nix` | Remove `let` block; update `enabled-extensions` |
| `modules/gnome-htpc.nix` | Remove `let` block; update `enabled-extensions` |
| `modules/gnome-server.nix` | Remove `let` block; update `enabled-extensions` |
| `modules/gnome-stateless.nix` | Remove `let` block; update `enabled-extensions` |

**No other files are affected.** The `hosts/` files, `flake.nix`,
`configuration-*.nix` files, and all other modules are unchanged.
