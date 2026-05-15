# Spec: Introduce `options.vexos.user.name` as Single Source of Truth

**Feature name:** `user_name_refactor`
**Date:** 2026-05-15
**Status:** Draft

---

## 1. Current State

The primary user account `nimda` is hardcoded as a string literal in **48 locations** across
the codebase (33 functional references + 15 comment-only references).  Any rename of the
primary user requires a global search-and-replace with no compile-time verification.

### 1.1 Complete inventory of `nimda` occurrences

> Legend: **FUNCTIONAL** = must be replaced | **COMMENT** = informational only, update for accuracy but not required | **COMMENTED-OUT** = dead code, update for accuracy

#### `flake.nix`

| Line | Type | Full line |
|------|------|-----------|
| 127 | COMMENT | `# between roles is which home-*.nix file feeds users.nimda.` |
| 134 | **FUNCTIONAL** | `users.nimda      = import homeFile;` |
| 249 | **FUNCTIONAL** | `users.nimda      = import roles.${role}.homeFile;` |

#### `home-desktop.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda".` |
| 4 | COMMENT | `# Consumed by the homeManagerModule in flake.nix via home-manager.users.nimda.` |
| 15 | **FUNCTIONAL** | `home.username    = "nimda";` |
| 16 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |

#### `home-headless-server.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda" — Headless Server role.` |
| 9 | **FUNCTIONAL** | `home.username    = "nimda";` |
| 10 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |

#### `home-htpc.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda" — HTPC role.` |
| 8 | **FUNCTIONAL** | `home.username    = "nimda";` |
| 9 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |

#### `home-server.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda" — GUI Server role.` |
| 9 | **FUNCTIONAL** | `home.username    = "nimda";` |
| 10 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |

#### `home-stateless.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda" — Stateless role.` |
| 11 | **FUNCTIONAL** | `home.username    = "nimda";` |
| 12 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |
| 78 | **FUNCTIONAL** | `STAMP="/persistent/home/nimda/.local/share/vexos/.stateless-photogimp-cleanup-done"` |
| 116 | **FUNCTIONAL** | `$DRY_RUN_CMD mkdir -p "/persistent/home/nimda/.local/share/vexos"` |

#### `home-vanilla.nix`

| Line | Type | Full line |
|------|------|-----------|
| 2 | COMMENT | `# Home Manager configuration for user "nimda" — Vanilla role.` |
| 8 | **FUNCTIONAL** | `home.username      = "nimda";` |
| 9 | **FUNCTIONAL** | `home.homeDirectory = "/home/nimda";` |

#### `configuration-stateless.nix`

| Line | Type | Full line |
|------|------|-----------|
| 37 | **FUNCTIONAL** | `users.users.nimda.initialPassword = "vexos";` |

#### `modules/users.nix`

| Line | Type | Full line |
|------|------|-----------|
| 7 | **FUNCTIONAL** | `users.users.nimda = {` |
| 9 | **FUNCTIONAL** | `description  = "nimda";` |

#### `modules/audio.nix`

| Line | Type | Full line |
|------|------|-----------|
| 46 | COMMENT | `# Grant nimda raw ALSA access (optional alongside PipeWire).` |
| 47 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "audio" ];` |

#### `modules/gaming.nix`

| Line | Type | Full line |
|------|------|-----------|
| 102 | COMMENT | `# Grant nimda access to GameMode CPU governor, input devices, and USB peripherals.` |
| 103 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "gamemode" "input" "plugdev" ];` |

#### `modules/gnome.nix`

| Line | Type | Full line |
|------|------|-----------|
| 165 | **FUNCTIONAL** | `user   = "nimda";` (under `services.displayManager.autoLogin`) |

#### `modules/impermanence.nix`

| Line | Type | Full line |
|------|------|-----------|
| 224 | COMMENTED-OUT | `#   users.nimda.directories = [` |
| 228 | COMMENTED-OUT | `#   users.nimda.files = [ ".config/monitors.xml" ];` |

#### `modules/network.nix`

| Line | Type | Full line |
|------|------|-----------|
| 132 | **FUNCTIONAL** | `users.users.nimda.openssh.authorizedKeys.keyFiles =` |

#### `modules/razer.nix`

| Line | Type | Full line |
|------|------|-----------|
| 12 | **FUNCTIONAL** | `users                   = [ "nimda" ];` |

#### `modules/system-nosleep.nix`

| Line | Type | Full line |
|------|------|-----------|
| 75 | **FUNCTIONAL** | `User = "nimda";` |
| 77 | **FUNCTIONAL** | `"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"` ← UID hardcode |
| 78 | **FUNCTIONAL** | `"HOME=/home/nimda"` |

#### `modules/virtualization.nix`

| Line | Type | Full line |
|------|------|-----------|
| 27 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "libvirtd" ];` |

#### `modules/server/arr.nix`

| Line | Type | Full line |
|------|------|-----------|
| 39 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "sabnzbd" "sonarr" "radarr" "lidarr" ];` |

#### `modules/server/docker.nix`

| Line | Type | Full line |
|------|------|-----------|
| 21 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "docker" ];` |

#### `modules/server/jellyfin.nix`

| Line | Type | Full line |
|------|------|-----------|
| 18 | COMMENT | `# Allow nimda to manage media directories alongside the jellyfin user.` |
| 19 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "jellyfin" ];` |

#### `modules/server/komga.nix`

| Line | Type | Full line |
|------|------|-----------|
| 20 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "komga" ];` |

#### `modules/server/plex.nix`

| Line | Type | Full line |
|------|------|-----------|
| 34 | **FUNCTIONAL** | `users.users.nimda.extraGroups = [ "plex" ];` |

#### `modules/server/syncthing.nix`

| Line | Type | Full line |
|------|------|-----------|
| 15 | **FUNCTIONAL** | `user = "nimda";` |
| 16 | **FUNCTIONAL** | `dataDir = "/home/nimda";` |
| 17 | **FUNCTIONAL** | `configDir = "/home/nimda/.config/syncthing";` |

---

## 2. Problem Definition

Every hardcoded `"nimda"` string is a potential inconsistency point.  There is no
compile-time check that all references agree.  Adding a declarative option gives:

- A single place to rename the primary user
- Type checking (Nix evaluates the `lib.types.str` assertion)
- `--show-trace` errors that point directly at an invalid assignment
- Zero runtime cost (option value is substituted at evaluation time)

---

## 3. Proposed Solution Architecture

### 3.1 New option: `options.vexos.user.name`

Defined in `modules/users.nix`.  All other modules consume it via
`config.vexos.user.name`.  Home Manager modules consume it via `osConfig.vexos.user.name`
(the standard HM accessor for the parent NixOS config).

```nix
options.vexos.user = {
  name = lib.mkOption {
    type        = lib.types.str;
    default     = "nimda";
    description = "Primary user account name for this system.";
  };
};
```

### 3.2 Accessor by context

| Context | Accessor |
|---------|----------|
| NixOS module (`modules/*.nix`, `configuration-*.nix`) | `config.vexos.user.name` |
| `modules/users.nix` internal (within its own `config` block) | `cfg.name` where `cfg = config.vexos.user` |
| Home Manager module (`home-*.nix`) | `osConfig.vexos.user.name` |
| `flake.nix` `mkHomeManagerModule` lambda body | `config.vexos.user.name` (the lambda arg `config` is the NixOS config) |
| `flake.nix` `mkBaseModule` lambda body | `config.vexos.user.name` (same — the outer lambda receives NixOS `config`) |

**Important nuance for `flake.nix`:** Both `mkHomeManagerModule` and `mkBaseModule` return
NixOS module attrsets.  The returned module is `{ config, ... }: { ... }`.  The `config`
argument inside that lambda is the fully-evaluated NixOS system config.  Accessing
`config.vexos.user.name` there is correct.

### 3.3 UID pinning decision

`modules/system-nosleep.nix` line 77 hardcodes UID `1000`:

```
"DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
```

**Analysis:**
- NixOS assigns UIDs starting at 1000, incrementing for each normal user in declaration order.
- `modules/users.nix` currently declares exactly one normal user (`nimda`).
- As long as only one normal user is declared, NixOS will consistently assign UID 1000.
- However, this is implicit and could silently break if a second normal user is added above
  `nimda` in the declaration list.

**Recommendation: pin `uid = 1000` explicitly in `modules/users.nix`.**

Explicit pinning is safer because:
1. The UID is then a guaranteed constant — no dependency on declaration order.
2. The `system-nosleep.nix` service can then reference it as
   `${toString config.users.users.${config.vexos.user.name}.uid}` rather than a magic number.
3. The NixOS evaluator will error at build time if two users share a UID.

The pinned value `1000` is the correct value for this installation (the system is already
deployed; changing it would break systemd's XDG_RUNTIME_DIR and persistent login data).

---

## 4. Proposed Changes — File by File

Changes are listed in **required order** (users.nix first; all others after).

---

### 4.1 `modules/users.nix` — MUST BE FIRST

**Current state:**
```nix
{ ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };
}
```

**Proposed state:**
```nix
{ config, lib, ... }:
let
  cfg = config.vexos.user;
in
{
  options.vexos.user = {
    name = lib.mkOption {
      type        = lib.types.str;
      default     = "nimda";
      description = "Primary user account name for this system.";
    };
  };

  config = {
    users.users.${cfg.name} = {
      isNormalUser = true;
      description  = cfg.name;
      uid          = 1000;
      extraGroups  = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
```

**Notes:**
- `uid = 1000` is added here (see UID pinning decision, §3.3).
- The `config = { ... };` wrapper is required when `options` and `config` coexist in the
  same module file; without it NixOS conflates them.
- `description = cfg.name` makes the GECOS description track the username automatically.

---

### 4.2 `flake.nix` — `mkHomeManagerModule` (line 134)

**Current:**
```nix
mkHomeManagerModule = homeFile: {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.nimda      = import homeFile;
    backupFileExtension = "backup";
  };
};
```

**Proposed:**
```nix
mkHomeManagerModule = homeFile: { config, ... }: {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.${config.vexos.user.name} = import homeFile;
    backupFileExtension = "backup";
  };
};
```

**Change:** Added `{ config, ... }:` to the returned module lambda so `config` is in scope;
replaced `users.nimda` attribute key with `users.${config.vexos.user.name}`.

---

### 4.3 `flake.nix` — `mkBaseModule` (line 249)

**Current:**
```nix
mkBaseModule = role: configFile: { ... }: {
  ...
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.nimda      = import roles.${role}.homeFile;
    backupFileExtension = "backup";
  };
  ...
};
```

**Proposed:**
```nix
mkBaseModule = role: configFile: { config, ... }: {
  ...
  home-manager = {
    useGlobalPkgs    = true;
    useUserPackages  = true;
    extraSpecialArgs = { inherit inputs; };
    users.${config.vexos.user.name} = import roles.${role}.homeFile;
    backupFileExtension = "backup";
  };
  ...
};
```

**Change:** The existing `{ ... }:` lambda must be widened to `{ config, ... }:`;
`users.nimda` replaced with `users.${config.vexos.user.name}`.

---

### 4.4 Home Manager modules (`home-*.nix`) — all six files

Each `home-*.nix` file must:
1. Add `osConfig` to its argument set.
2. Replace `home.username = "nimda"` with `home.username = osConfig.vexos.user.name`.
3. Replace `home.homeDirectory = "/home/nimda"` with
   `home.homeDirectory = "/home/${osConfig.vexos.user.name}"`.

`osConfig` is the NixOS system `config` passed by Home Manager's NixOS module into every
HM submodule.  It is available in all NixOS-integrated HM setups (Home Manager ≥ 23.05).

#### `home-desktop.nix` (lines 15–16)

```nix
# Before
{ config, pkgs, lib, inputs, ... }:
...
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

# After
{ config, pkgs, lib, inputs, osConfig, ... }:
...
  home.username    = osConfig.vexos.user.name;
  home.homeDirectory = "/home/${osConfig.vexos.user.name}";
```

#### `home-headless-server.nix` (lines 9–10)

Same pattern as `home-desktop.nix`.

#### `home-htpc.nix` (lines 8–9)

Same pattern.

#### `home-server.nix` (lines 9–10)

Same pattern.

#### `home-vanilla.nix` (lines 8–9)

Same pattern.

#### `home-stateless.nix` (lines 11–12, 78, 116)

In addition to lines 11–12 (same as above), two shell script literals inside
`home.activation.cleanupPhotogimpOrphans` reference the persistent path:

```nix
# Before (line 78)
STAMP="/persistent/home/nimda/.local/share/vexos/.stateless-photogimp-cleanup-done"

# After
STAMP="/persistent/home/${osConfig.vexos.user.name}/.local/share/vexos/.stateless-photogimp-cleanup-done"
```

```nix
# Before (line 116)
$DRY_RUN_CMD mkdir -p "/persistent/home/nimda/.local/share/vexos"

# After
$DRY_RUN_CMD mkdir -p "/persistent/home/${osConfig.vexos.user.name}/.local/share/vexos"
```

> **Why this works:** Both strings are Nix `''...''` multiline string literals.  The
> `${osConfig.vexos.user.name}` is Nix string interpolation evaluated at build time —
> there is no runtime shell variable conflict.  The shell variable references like
> `$DRY_RUN_CMD` and `$STAMP` remain as-is; only the Nix-evaluated path changes.

---

### 4.5 `configuration-stateless.nix` (line 37)

**Current:**
```nix
users.users.nimda.initialPassword = "vexos";
```

**Proposed:**
```nix
users.users.${config.vexos.user.name}.initialPassword = "vexos";
```

**Prerequisite:** `configuration-stateless.nix` must already receive `config` in scope.
Verify its module header includes `config` in the argument set; add it if missing.

---

### 4.6 `modules/audio.nix` (line 47)

```nix
# Before
users.users.nimda.extraGroups = [ "audio" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "audio" ];
```

Module header already includes `config`. No header change required.

---

### 4.7 `modules/gaming.nix` (line 103)

```nix
# Before
users.users.nimda.extraGroups = [ "gamemode" "input" "plugdev" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "gamemode" "input" "plugdev" ];
```

Module header already includes `config`. No header change required.

---

### 4.8 `modules/gnome.nix` (line 165)

```nix
# Before
services.displayManager.autoLogin = {
  enable = true;
  user   = "nimda";
};

# After
services.displayManager.autoLogin = {
  enable = true;
  user   = config.vexos.user.name;
};
```

Module header already includes `config`. No header change required.

---

### 4.9 `modules/network.nix` (line 132)

```nix
# Before
users.users.nimda.openssh.authorizedKeys.keyFiles =
  lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;

# After
users.users.${config.vexos.user.name}.openssh.authorizedKeys.keyFiles =
  lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
```

Module header already includes `config`. No header change required.

---

### 4.10 `modules/razer.nix` (line 12)

```nix
# Before
hardware.openrazer = {
  enable = true;
  users                   = [ "nimda" ];
  ...
};

# After
hardware.openrazer = {
  enable = true;
  users                   = [ config.vexos.user.name ];
  ...
};
```

Module header already includes `config`. No header change required.

---

### 4.11 `modules/system-nosleep.nix` (lines 75, 77, 78)

This file also contains the UID hardcode on line 77.

```nix
# Before
serviceConfig = {
  Type = "oneshot";
  User = "nimda";
  Environment = [
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
    "HOME=/home/nimda"
  ];
  ...
};

# After
serviceConfig = {
  Type = "oneshot";
  User = config.vexos.user.name;
  Environment = [
    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${toString config.users.users.${config.vexos.user.name}.uid}/bus"
    "HOME=/home/${config.vexos.user.name}"
  ];
  ...
};
```

> **UID note:** `config.users.users.${config.vexos.user.name}.uid` evaluates to `1000`
> because `modules/users.nix` pins `uid = 1000` (§4.1).  `toString` converts the integer
> to the string `"1000"` for interpolation.  This removes the magic number entirely.

Module header already includes `config`. No header change required.

---

### 4.12 `modules/virtualization.nix` (line 27)

**Current header:** `{ pkgs, ... }:` — `config` is NOT in scope.

```nix
# Before header
{ pkgs, ... }:

# After header
{ pkgs, config, ... }:
```

```nix
# Before
users.users.nimda.extraGroups = [ "libvirtd" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "libvirtd" ];
```

---

### 4.13 `modules/server/arr.nix` (line 39)

```nix
# Before
users.users.nimda.extraGroups = [ "sabnzbd" "sonarr" "radarr" "lidarr" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "sabnzbd" "sonarr" "radarr" "lidarr" ];
```

Module header already includes `config`. No header change required.

---

### 4.14 `modules/server/docker.nix` (line 21)

```nix
# Before
users.users.nimda.extraGroups = [ "docker" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "docker" ];
```

Module header already includes `config`. No header change required.

---

### 4.15 `modules/server/jellyfin.nix` (line 19)

```nix
# Before
users.users.nimda.extraGroups = [ "jellyfin" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "jellyfin" ];
```

Module header already includes `config`. No header change required.

---

### 4.16 `modules/server/komga.nix` (line 20)

```nix
# Before
users.users.nimda.extraGroups = [ "komga" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "komga" ];
```

Module header already includes `config`. No header change required.

---

### 4.17 `modules/server/plex.nix` (line 34)

```nix
# Before
users.users.nimda.extraGroups = [ "plex" ];

# After
users.users.${config.vexos.user.name}.extraGroups = [ "plex" ];
```

Module header already includes `config`. No header change required.

---

### 4.18 `modules/server/syncthing.nix` (lines 15–17)

```nix
# Before
services.syncthing = {
  enable = true;
  user = "nimda";
  dataDir = "/home/nimda";
  configDir = "/home/nimda/.config/syncthing";
  ...
};

# After
services.syncthing = {
  enable = true;
  user    = config.vexos.user.name;
  dataDir = "/home/${config.vexos.user.name}";
  configDir = "/home/${config.vexos.user.name}/.config/syncthing";
  ...
};
```

Module header already includes `config`. No header change required.

---

## 5. Order of Changes

```
1. modules/users.nix                   ← defines the option; MUST be first
2. (any order after step 1)
   - modules/audio.nix
   - modules/gaming.nix
   - modules/gnome.nix
   - modules/network.nix
   - modules/razer.nix
   - modules/system-nosleep.nix
   - modules/virtualization.nix        ← also requires header change
   - modules/server/arr.nix
   - modules/server/docker.nix
   - modules/server/jellyfin.nix
   - modules/server/komga.nix
   - modules/server/plex.nix
   - modules/server/syncthing.nix
   - configuration-stateless.nix
   - home-desktop.nix
   - home-headless-server.nix
   - home-htpc.nix
   - home-server.nix
   - home-stateless.nix
   - home-vanilla.nix
   - flake.nix
```

> All consumer changes are independent of each other.  They can be applied in any order
> after step 1.  The Nix evaluator evaluates the entire module system atomically — partial
> refactors will not build until all consumers have been updated.

---

## 6. Files NOT to Change (Data vs. Reference)

The following occurrences are purely informational and carry no runtime effect:

| File | Lines | Reason |
|------|-------|--------|
| `flake.nix` | 127 | Comment describing behaviour |
| `home-desktop.nix` | 2, 4 | File-level comment header |
| `home-headless-server.nix` | 2 | Comment |
| `home-htpc.nix` | 2 | Comment |
| `home-server.nix` | 2 | Comment |
| `home-stateless.nix` | 2 | Comment |
| `home-vanilla.nix` | 2 | Comment |
| `modules/audio.nix` | 46 | Comment |
| `modules/gaming.nix` | 102 | Comment |
| `modules/server/jellyfin.nix` | 18 | Comment |
| `modules/impermanence.nix` | 224, 228 | Commented-out example code (dead) |

**Recommendation:** Update the comments in the same commit for accuracy, but they are not
required for functional correctness.

---

## 7. Risk Assessment

### 7.1 No functional change for existing installs

The option default is `"nimda"`.  Any host that does not explicitly set
`vexos.user.name` will evaluate identically to the current hardcoded behaviour.
`nix flake check` and `nixos-rebuild dry-build` will confirm this before any rebuild.

### 7.2 What breaks if the option is not set

Nothing.  The default value `"nimda"` is semantically identical to the current literals.
Existing hosts do not need to set this option unless they want to rename the user.

### 7.3 What breaks if only some files are updated

The build will fail at evaluation time with an attribute resolution error (e.g.
`users.users` would have two separate user declarations — the old `nimda` key and the new
interpolated key).  This is a safe failure: it is caught before any activation.

The only dangerous partial state would be updating `flake.nix` before `modules/users.nix`,
which would reference a nonexistent option.  The required ordering (§5) prevents this.

### 7.4 UID stability

Pinning `uid = 1000` in `modules/users.nix` (§4.1) eliminates the implicit ordering
dependency.  Any future addition of a second normal user will not shift `nimda`'s UID.
If the UID is changed post-deployment, systemd's `/run/user/<uid>` socket will be
recreated on next login — this is transient and self-healing.

### 7.5 `osConfig` availability

`osConfig` was introduced in Home Manager 23.05.  This project targets NixOS 25.05, which
uses a Home Manager version well above that baseline.  No compatibility risk.

### 7.6 `modules/impermanence.nix` commented-out code

Lines 224 and 228 reference `users.nimda` in commented-out example snippets.  These have
no runtime effect.  They should be updated to `users.${config.vexos.user.name}` in the
same commit to avoid misleading future readers, but no build gate depends on them.

---

## 8. Summary of Changes Required

| File | Nature of change | Header change required? |
|------|-----------------|------------------------|
| `modules/users.nix` | Add option definition; switch to `config` block pattern; pin UID | Yes (`{ config, lib, ... }:`) |
| `flake.nix` | Widen two module lambdas to `{ config, ... }:`; replace two `users.nimda` keys | Yes (two lambda sites) |
| `home-desktop.nix` | Add `osConfig` to args; replace two literals | Yes |
| `home-headless-server.nix` | Add `osConfig` to args; replace two literals | Yes |
| `home-htpc.nix` | Add `osConfig` to args; replace two literals | Yes |
| `home-server.nix` | Add `osConfig` to args; replace two literals | Yes |
| `home-stateless.nix` | Add `osConfig` to args; replace four literals | Yes |
| `home-vanilla.nix` | Add `osConfig` to args; replace two literals | Yes |
| `configuration-stateless.nix` | Replace one literal | Verify `config` in header |
| `modules/audio.nix` | Replace one literal | No |
| `modules/gaming.nix` | Replace one literal | No |
| `modules/gnome.nix` | Replace one literal | No |
| `modules/network.nix` | Replace one literal | No |
| `modules/razer.nix` | Replace one literal | No |
| `modules/system-nosleep.nix` | Replace three literals (User, HOME, UID) | No |
| `modules/virtualization.nix` | Replace one literal | Yes (add `config`) |
| `modules/server/arr.nix` | Replace one literal | No |
| `modules/server/docker.nix` | Replace one literal | No |
| `modules/server/jellyfin.nix` | Replace one literal | No |
| `modules/server/komga.nix` | Replace one literal | No |
| `modules/server/plex.nix` | Replace one literal | No |
| `modules/server/syncthing.nix` | Replace three literals | No |

**Total files:** 22 files modified (21 functional + 1 confirmation for configuration-stateless.nix header)
**Total functional `nimda` literals replaced:** 33

---

*Spec written by Research Phase subagent — 2026-05-15*
