# Specification: Rootless Podman UID/GID Namespace Mapping for `nimda`

**Feature:** `subUidRanges` / `subGidRanges` for the `nimda` user  
**Status:** ALREADY IMPLEMENTED — commit `56a7ec6` on `main` (pushed)  
**Date:** 2026-05-28  

---

## 1. Current State Analysis

### 1.1 Podman Configuration

Podman is configured in `modules/development.nix`:

```nix
virtualisation.podman = {
  enable       = true;
  dockerCompat = true;
  defaultNetwork.settings.dns_enabled = true;
};
```

Related container tooling also in `modules/development.nix`:
- `pkgs.podman-compose` — docker-compose compatible CLI
- `pkgs.buildah` — OCI image builder (rootless)
- `pkgs.skopeo` — image inspection and transfer

**Scope:** `modules/development.nix` is imported **only** by `configuration-desktop.nix`.  
All other roles (server, headless-server, htpc, stateless, vanilla) do NOT import it.

### 1.2 User Module State (`modules/users.nix`)

`modules/users.nix` is the **universal user base module**. It is imported by ALL six
role configuration files:

| Role configuration file          | Imports `modules/users.nix` |
|----------------------------------|------------------------------|
| `configuration-desktop.nix`      | ✔ Yes                        |
| `configuration-stateless.nix`    | ✔ Yes                        |
| `configuration-server.nix`       | ✔ Yes                        |
| `configuration-headless-server.nix` | ✔ Yes                     |
| `configuration-htpc.nix`         | ✔ Yes                        |
| `configuration-vanilla.nix`      | ✔ Yes                        |

Current content of `modules/users.nix` (as of commit `56a7ec6`):

```nix
users.users.nimda = {
  isNormalUser = true;
  description  = cfg.name;
  uid          = 1000;
  extraGroups  = [
    "wheel"
    "networkmanager"
  ];
  subUidRanges = [{ startUid = 100000; count = 65536; }];
  subGidRanges = [{ startGid = 100000; count = 65536; }];
};
```

The `subUidRanges` and `subGidRanges` entries **are already present and committed**.

### 1.3 `configuration-desktop.nix` Import List

```
modules/gnome.nix
modules/gnome-desktop.nix
modules/gaming.nix
modules/audio.nix
modules/gpu.nix
modules/gpu-gaming.nix
modules/flatpak.nix
modules/flatpak-desktop.nix
modules/network.nix
modules/network-desktop.nix
modules/packages-common.nix
modules/packages-desktop.nix
modules/development.nix          ← Podman lives here
modules/virtualization.nix
modules/branding.nix
modules/branding-display.nix
modules/system.nix
modules/system-desktop-kernel.nix
modules/system-gaming.nix
modules/system-nosleep.nix
modules/security.nix
modules/nix.nix
modules/nix-desktop.nix
modules/locale.nix
modules/users.nix                ← subUidRanges lives here
modules/razer.nix
modules/asus-opt.nix
```

### 1.4 Flake Structure

`flake.nix` uses a `mkHost` function that composes modules in this order:
1. `/etc/nixos/hardware-configuration.nix` (per-host, untracked)
2. `role.baseModules` (overlay modules, upModule, proxmox, sops)
3. Home Manager module (per-role `home-*.nix`)
4. `role.extraModules` (impermanence, serverServicesModule)
5. `./hosts/<role>-<gpu>.nix` (host file)
6. `legacyExtra` (nvidiaVariant stamp)
7. `variantModule` (variant identifier stamp)

The project already includes two tracked optional host-local override
mechanisms:
- `/etc/nixos/server-services.nix` — server role service declarations
- `/etc/nixos/stateless-user-override.nix` — stateless user password override

These are the only sanctioned host-local escape hatches. A `/etc/nixos/local.nix`
is NOT a pattern used in this project.

---

## 2. Problem Definition

The user wants rootless Podman to work for the `nimda` user — specifically the
ability to build container images without root privileges. Rootless Podman
requires the kernel's user namespace subordinate UID/GID mapping to be
configured for the user account:

```nix
users.users.nimda.subUidRanges = [{ startUid = 100000; count = 65536; }];
users.users.nimda.subGidRanges = [{ startGid = 100000; count = 65536; }];
```

These entries cause NixOS to write the appropriate entries to `/etc/subuid`
and `/etc/subgid`, which the kernel reads when a rootless process requests
UID/GID namespace mapping.

---

## 3. Architectural Decision

### Chosen Option: A — Add to `modules/users.nix` (universal base)

**Rationale:**

- `subUidRanges` and `subGidRanges` are **user account properties**, not
  role-specific service or package configuration.
- The NixOS `users.users.<name>.subUidRanges` option is harmless on roles
  that do not run Podman — the `/etc/subuid` entries are written but unused.
- Adding them to the universal `modules/users.nix` is consistent with the
  project's **Option B: Common base + role additions** architecture:
  - Universal attributes belong in the base module.
  - No `lib.mkIf` guard is required or appropriate here.
- Any future role that gains Podman support (e.g., server, stateless) will
  automatically have the namespace mapping available without any module
  changes.

### Rejected Options

| Option | Rejected Because |
|--------|-----------------|
| B — `modules/users-desktop.nix` | Sub-UID/GID ranges are a user account property, not a display/role property. Scoping them to desktop would break future server/stateless Podman use. |
| C — Add to an existing desktop module | Same reasoning as B; also forces a `lib.mkIf` guard or a dedicated module with one attribute, both worse than Option A. |
| D — `modules/podman.nix` or `modules/containers.nix` | User namespace mapping is not Podman-specific; it belongs with user account definitions, not with service enablement. Cross-concern coupling is an antipattern. |
| E — `/etc/nixos/local.nix` host-local override | The project architecture explicitly avoids this pattern except for the two already-sanctioned escape hatches. No `local.nix` precedent exists. |

---

## 4. Implementation

### Status: COMPLETE — No action required.

The implementation was applied in commit `56a7ec6 Update users.nix` which is
already an ancestor of `HEAD` on `main` and has been pushed to `origin/main`.

### What was changed

**File:** `modules/users.nix`

Two lines were added to the `users.users.nimda` attribute set:

```nix
subUidRanges = [{ startUid = 100000; count = 65536; }];
subGidRanges = [{ startGid = 100000; count = 65536; }];
```

### Exact diff

```diff
--- a/modules/users.nix
+++ b/modules/users.nix
@@ -30,6 +30,8 @@ in
         "wheel"
         "networkmanager"
       ];
+      subUidRanges = [{ startUid = 100000; count = 65536; }];
+      subGidRanges = [{ startGid = 100000; count = 65536; }];
     };
   };
```

### Verification

After a `nixos-rebuild switch`, the following files will be populated:

```
/etc/subuid:  nimda:100000:65536
/etc/subgid:  nimda:100000:65536
```

To confirm at runtime:
```bash
cat /etc/subuid   # nimda:100000:65536
cat /etc/subgid   # nimda:100000:65536
podman run --rm hello-world   # should succeed without sudo
```

---

## 5. Risks and Notes

| Item | Assessment |
|------|-----------|
| Sub-UID/GID ranges on roles without Podman | Harmless — kernel ignores unused mappings. No performance or security impact. |
| Range conflict with other users | UID 100000–165535 is the conventional rootless range; no other user on this system uses it. |
| `nixos-rebuild` required to apply | Yes — changes to `users.users` require a rebuild to regenerate `/etc/subuid` and `/etc/subgid`. Already applied if the system was rebuilt after commit `56a7ec6`. |
| `flake.nix` modification not needed | Confirmed — no `./local.nix` import is needed or appropriate. |
| `hardware-configuration.nix` unaffected | Confirmed — this change has no interaction with per-host hardware config. |
| `system.stateVersion` unaffected | Confirmed — this change does not touch `system.stateVersion`. |

---

## 6. Files Affected

| File | Change |
|------|--------|
| `modules/users.nix` | Added `subUidRanges` and `subGidRanges` to `users.users.nimda` |

No other files require modification.
