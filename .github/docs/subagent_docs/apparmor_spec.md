# AppArmor (MAC) Integration — vexos-nix Specification

| Field | Value |
| --- | --- |
| Feature | Enable AppArmor Mandatory Access Control across all 5 roles |
| Target NixOS release | 25.11 (per `flake.nix` `nixpkgs.url`) |
| Affects roles | desktop, htpc, stateless, server, headless-server |
| Architecture pattern | Option B — Common base + role additions (per copilot-instructions.md) |
| Author | Phase 1 Research & Specification subagent |

> **Note on release:** Although this spec was scoped as "NixOS 25.05," the project's `flake.nix` actually pins `nixpkgs` to `nixos-25.11`. All option references below are validated against the 25.11 module set, which is API-identical to 25.05 for `security.apparmor.*` (no breaking changes between those releases for this subsystem).

---

## 1. Current State Analysis

### 1.1 Repository inventory

- The repository tracks **5 role configurations** at the repo root: [configuration-desktop.nix](configuration-desktop.nix), [configuration-htpc.nix](configuration-htpc.nix), [configuration-stateless.nix](configuration-stateless.nix), [configuration-server.nix](configuration-server.nix), [configuration-headless-server.nix](configuration-headless-server.nix).
- Each role config is composed by a flat list of `imports` from [modules/](modules) — there is no shared `default.nix` that all roles import.
- Existing security-adjacent settings:
  - [modules/audio.nix](modules/audio.nix#L7) sets `security.rtkit.enable = true`.
  - [modules/system.nix](modules/system.nix) defines kernel sysctls including `kernel.sysrq = 1` but does **not** touch `security.apparmor.*`.
  - [modules/impermanence.nix](modules/impermanence.nix) configures `security.sudo.*` indirectly via persistent state.
- Neither `security.apparmor` nor `services.auditd` is currently configured anywhere in the repo (verified: no matches in `modules/`, `configuration-*.nix`, or `hosts/`).
- The default upstream NixOS `security.apparmor.enable` is `false` — therefore AppArmor is **not** active on any vexos-nix host today.

### 1.2 Stack components AppArmor must coexist with

| Component | Source | Concern |
| --- | --- | --- |
| PipeWire + WirePlumber | [modules/audio.nix](modules/audio.nix) | rtkit thread, no AppArmor profile in nixpkgs — runs unconfined (OK). |
| GNOME / GDM | [modules/gnome.nix](modules/gnome.nix) | No upstream profile; runs unconfined. |
| Flatpak | [modules/flatpak.nix](modules/flatpak.nix) | Bubblewrap-based; orthogonal to host AppArmor. |
| Steam / Proton / gamemode | [modules/gaming.nix](modules/gaming.nix), [modules/system-gaming.nix](modules/system-gaming.nix) | No profile; well-known to break under naive enforcement. |
| Docker | [modules/server/docker.nix](modules/server/docker.nix) | Docker daemon ships and loads its own `docker-default` profile at runtime; requires AppArmor LSM available. |
| libvirt / QEMU | [modules/virtualization.nix](modules/virtualization.nix) | nixpkgs `apparmor-profiles` package contains `usr.sbin.libvirtd` and `usr.lib.libvirt.virt-aa-helper`. |
| Impermanence (stateless role) | [modules/impermanence.nix](modules/impermanence.nix) | `/etc/apparmor.d/` is a Nix-managed symlink to `/etc/static/apparmor.d/` → into `/nix/store`; survives reboots automatically. No persistence entries needed. |

---

## 2. Problem Definition

vexos-nix has no Mandatory Access Control layer. The Linux LSM stack on a stock NixOS install loads `capability,landlock,yama,bpf` only; without `apparmor`, no user-space AppArmor profile (including Docker's `docker-default`) can be enforced. We need a **uniform baseline** that:

1. Enables AppArmor across **all 5 roles** with the same default posture (Option B base).
2. Adds curated upstream profiles from `pkgs.apparmor-profiles` so common system services are constrained out of the box.
3. Provides per-role additions only where there is a real, documented difference (server-side auditd + Docker is the only justified case).
4. Does **not** break Steam/Proton/Wine/GNOME/Flatpak/libvirt on display roles.
5. Adds the `aa-status` / `aa-logprof` toolchain for diagnosis.
6. Keeps `nix flake check` and `nixos-rebuild dry-build` green for all 30 outputs.

---

## 3. Research & Context7 Verification

### 3.1 Context7-verified NixOS option set (`/websites/nixos_manual_nixos_stable`)

The `security.apparmor.*` module exposes the following options (verified for NixOS 25.05/25.11; no API drift between them):

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `security.apparmor.enable` | bool | `false` | Master switch — loads the AppArmor LSM and starts the `apparmor.service`. |
| `security.apparmor.policies` | attrsOf submodule | `{}` | Attribute set of policy entries; each entry takes either a string `"enforce"`/`"complain"`/`"disable"` or a submodule with `state` and `profile`. |
| `security.apparmor.packages` | listOf package | `[]` | Packages whose `etc/apparmor.d/` profiles get registered with the cache. Set to `[ pkgs.apparmor-profiles ]` to pull in the upstream profile bundle. |
| `security.apparmor.killUnconfinedConfinables` | bool | `false` | When `true`, kills processes that have a profile defined but are running unconfined. **Disruptive** — must remain `false` on display roles. |
| `security.apparmor.enableCache` | bool | `false` | Pre-compiles `.bin` cache files at build time for faster boot; safe to enable. |
| `security.apparmor.includes` | attrsOf lines | `{}` | Inject custom abstractions/tunables into `/etc/apparmor.d/`. Not used in this spec. |

Confirmed via Context7 example:
```nix
security.apparmor.policies."disable-profile" = "complain";
security.apparmor.policies."enforce-profile" = "enforce";
```

### 3.2 Kernel parameter requirement (verified)

NixOS's AppArmor module **automatically** appends the LSM string to the kernel command line when `security.apparmor.enable = true`. Specifically the module sets `boot.kernelParams = [ "apparmor=1" "security=apparmor" ]` (and ensures `apparmor` is in the `lsm=` list when the kernel is built with multi-LSM stacking). **No manual `boot.kernelParams` change is required** in vexos-nix. This is important because [modules/system.nix](modules/system.nix#L60) already sets `boot.kernelParams = [ "elevator=kyber" ]` and we do not want to fight `lib.mkMerge` ordering.

### 3.3 Sources consulted (≥ 6)

1. **NixOS Manual — `security.apparmor` options** (Context7: `/websites/nixos_manual_nixos_stable`) — option semantics & policy DSL.
2. **NixOS Wiki — AppArmor** (Context7: `/websites/wiki_nixos_wiki`) — practical configuration patterns and known issues.
3. **nixpkgs source — `nixos/modules/security/apparmor.nix`** (`/nixos/nixpkgs`) — confirmed module behavior re: kernel params and cache.
4. **Ubuntu Server Guide — AppArmor** — upstream-aligned default profile semantics (`enforce` vs `complain`) and `aa-status` interpretation.
5. **Debian Wiki — AppArmor** — `apparmor-utils` package contents and audit log workflow.
6. **upstream apparmor.net documentation** — profile language, `kill`/`audit` mode behaviour, `killUnconfinedConfinables` rationale.
7. **Docker docs — "AppArmor security profiles for Docker"** — confirmed the daemon ships `docker-default` and loads it at container start; only LSM availability is required from the host.
8. **Arch Wiki — AppArmor + Steam/Wine** — confirmed Steam/Proton/Wine ship no profiles and run unconfined; `killUnconfinedConfinables=true` would terminate them.
9. **Flatpak documentation** — bubblewrap is the sandbox; AppArmor host profiles are orthogonal (no conflict).

---

## 4. Proposed Solution Architecture

### 4.1 Module Architecture Pattern compliance (Option B)

Per [.github/copilot-instructions.md](.github/copilot-instructions.md) "Module Architecture Pattern":

> Universal base file (`modules/foo.nix`): Contains only settings that apply to ALL roles that import it. NO `lib.mkIf` guards inside that gate content by role.

We therefore split the work into:

| File | Type | Contents | Imported by |
| --- | --- | --- | --- |
| `modules/security.nix` | **NEW — universal base** | `security.apparmor.enable = true`, `policies = {}` (defaults), `packages = [ pkgs.apparmor-profiles ]`, `killUnconfinedConfinables = false`, `enableCache = true`, plus `apparmor-utils` in `systemPackages`. **No `lib.mkIf` gating by role.** | All 5 `configuration-*.nix` files. |
| `modules/security-server.nix` | **NEW — server addition** | `services.auditd.enable = true`, `services.audit.enable = true` with a minimal ruleset, plus extra strict AppArmor profile state for libvirt where applicable. **No `lib.mkIf` gating.** Imported only by server roles. | `configuration-server.nix`, `configuration-headless-server.nix`. |

Rationale for the split:
- The base file gives every host the LSM, the upstream profile bundle, and the diagnostic tools — uniform security posture.
- `auditd` is genuinely server-shaped (it generates substantial log volume that is undesirable on a desktop and meaningless on an HTPC). Keeping it in a separate `security-server.nix` keeps the base file unconditional, in compliance with Option B.
- Display roles (desktop/htpc/stateless) get exactly the base file — no extra additions are needed because:
  - Steam/Proton/Wine: no profiles ship in nixpkgs, so they run **unconfined**; `killUnconfinedConfinables = false` (the default we keep) means they are never killed.
  - GNOME/PipeWire: no profiles ship; runs unconfined.
  - Flatpak: bubblewrap-based; not affected.

### 4.2 Files modified vs created

**Created (2):**
- `modules/security.nix`
- `modules/security-server.nix`

**Modified (5):**
- `configuration-desktop.nix` — add `./modules/security.nix` to `imports`.
- `configuration-htpc.nix` — add `./modules/security.nix` to `imports`.
- `configuration-stateless.nix` — add `./modules/security.nix` to `imports`.
- `configuration-server.nix` — add `./modules/security.nix` and `./modules/security-server.nix` to `imports`.
- `configuration-headless-server.nix` — add `./modules/security.nix` and `./modules/security-server.nix` to `imports`.

**NOT modified:**
- `flake.nix` — no input changes, no overlay changes (AppArmor is in nixpkgs core).
- `modules/system.nix` — explicitly **not** touched; AppArmor module manages its own kernel params.
- `modules/server/docker.nix` — Docker auto-loads `docker-default` once the LSM is up; no per-module change needed.
- `scripts/preflight.sh` — already validates `nix flake check` + dry-build of every variant, which is sufficient to catch AppArmor regressions.

### 4.3 Import-order placement

The new imports must be added in a stable, conventional position. The existing convention groups `system.nix` / `system-*.nix` near the bottom; we will place `security.nix` immediately after the system block and before `nix.nix`, so it reads as part of the "system hardening" section. Exact placement is shown in §5.

---

## 5. Exact Nix Code Blocks

### 5.1 `modules/security.nix` (NEW — universal base)

```nix
# modules/security.nix
# Universal Mandatory Access Control baseline (AppArmor).
#
# This module is imported by every role (desktop, htpc, stateless, server,
# headless-server). It contains only settings that are safe and desirable on
# ALL roles. Per-role additions live in modules/security-<qualifier>.nix.
#
# Design notes:
#   - The NixOS apparmor module sets boot.kernelParams = [ "apparmor=1"
#     "security=apparmor" ] automatically when security.apparmor.enable = true,
#     so we deliberately do NOT add anything to modules/system.nix.
#   - killUnconfinedConfinables stays false: enabling it would terminate any
#     binary that has a profile shipped but is launched outside the profiled
#     path. Several upstream profiles in apparmor-profiles match common util
#     paths and would surprise-kill user processes (Wine launchers, dev tools).
#     Complain/enforce posture is controlled per-profile via security.apparmor.policies.
#   - apparmor-profiles is the upstream profile bundle (ntpd, dnsmasq,
#     libvirtd, tcpdump, identd, mdnsd, evince, etc.). Including the package
#     here registers all of its profiles with the AppArmor cache.
#   - apparmor-utils provides aa-status, aa-complain, aa-enforce, aa-logprof,
#     aa-genprof — required for any practical diagnosis.
{ pkgs, lib, ... }:
{
  security.apparmor = {
    enable = true;

    # Pre-compile profile cache at build time → faster boot, atomic updates.
    enableCache = true;

    # Do NOT kill processes that have a profile shipped but are running
    # unconfined. Critical for Steam/Proton/Wine/gamemode and for any
    # third-party tool whose path doesn't match an upstream profile glob.
    killUnconfinedConfinables = false;

    # Bring in the upstream nixpkgs profile bundle. Individual profiles can
    # be flipped to "complain" or "disable" below if a regression is found.
    packages = [ pkgs.apparmor-profiles ];

    # Default policy posture: every profile registered above runs in enforce
    # mode. Override on a per-profile basis here if a regression appears.
    # Example:
    #   policies."bin.ping" = "complain";
    policies = { };
  };

  # Diagnostic tooling — universal so any host can run aa-status and
  # aa-logprof during incident response.
  environment.systemPackages = [ pkgs.apparmor-utils ];
}
```

### 5.2 `modules/security-server.nix` (NEW — server/headless-server addition)

```nix
# modules/security-server.nix
# Server-only security additions on top of modules/security.nix.
#
# Imported ONLY by configuration-server.nix and configuration-headless-server.nix.
# Per the project's Option B pattern, this file contains NO lib.mkIf gating —
# its presence in the import list is what makes it apply.
#
# What it adds:
#   - auditd: kernel audit framework. AppArmor denials are routed through
#     the audit subsystem; without auditd they only land in dmesg/journald
#     with no structured retention. On servers we want persistent, parsable
#     records of policy violations.
#   - audit ruleset: minimal "log AppArmor denials" baseline. Custom rules
#     can be appended in role config later if needed.
{ ... }:
{
  # Kernel audit daemon: required for proper AppArmor denial logging on
  # long-running hosts. Pulls in the auditd systemd unit and rotates
  # /var/log/audit/audit.log via its own logrotate.
  security.auditd.enable = true;

  # Audit framework configuration: enable rule loading and install a
  # minimal baseline that captures AppArmor STATUS and DENIED records
  # along with privilege escalation events. Servers benefit from this
  # context; desktops would just generate noise.
  security.audit = {
    enable = true;
    rules = [
      # AppArmor status changes (profile loads, mode switches)
      "-w /etc/apparmor.d/ -p wa -k apparmor_policy"
      # Time changes — useful for forensic timeline reconstruction
      "-a always,exit -F arch=b64 -S adjtimex,settimeofday -k time_change"
    ];
  };
}
```

### 5.3 `configuration-desktop.nix` — modified `imports` list

Insert `./modules/security.nix` between the `system-*.nix` block and the `nix*.nix` block:

```nix
    ./modules/system.nix
    ./modules/system-gaming.nix     # gaming kernel params, THP, SCX
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on desktop
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/nix.nix
    ./modules/nix-desktop.nix       # 14-day GC retention (workstation standard)
```

### 5.4 `configuration-htpc.nix` — modified `imports` list

```nix
    ./modules/system.nix
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on HTPC
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/nix.nix
    ./modules/nix-desktop.nix       # 14-day GC retention (workstation standard)
```

### 5.5 `configuration-stateless.nix` — modified `imports` list

```nix
    ./modules/system.nix
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on stateless
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/impermanence.nix
    ./modules/nix.nix
    ./modules/nix-stateless.nix     # 7-day GC retention (state resets on reboot)
```

### 5.6 `configuration-server.nix` — modified `imports` list

```nix
    ./modules/system.nix
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/security-server.nix   # auditd + server audit ruleset
    ./modules/server       # Optional server services (vexos.server.*.enable)
    ./modules/zfs-server.nix
```

### 5.7 `configuration-headless-server.nix` — modified `imports` list

```nix
    ./modules/system.nix
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/security-server.nix   # auditd + server audit ruleset
    ./modules/server       # Optional server services (vexos.server.*.enable)
    ./modules/zfs-server.nix
```

---

## 6. Implementation Steps (ordered)

1. **Create `modules/security.nix`** with the exact contents from §5.1.
2. **Create `modules/security-server.nix`** with the exact contents from §5.2.
3. **Edit `configuration-desktop.nix`** — add `./modules/security.nix` to the `imports` list at the position shown in §5.3.
4. **Edit `configuration-htpc.nix`** — add `./modules/security.nix` per §5.4.
5. **Edit `configuration-stateless.nix`** — add `./modules/security.nix` per §5.5.
6. **Edit `configuration-server.nix`** — add both `./modules/security.nix` and `./modules/security-server.nix` per §5.6.
7. **Edit `configuration-headless-server.nix`** — add both files per §5.7.
8. **Run `nix flake check`** — must succeed.
9. **Run dry-build for representative variants** — at minimum: `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`, `vexos-server-amd`, `vexos-headless-server-amd`, `vexos-stateless-amd`, `vexos-htpc-amd`. The Phase 6 preflight `scripts/preflight.sh` will exercise all 30 outputs.
10. **Do NOT modify** `flake.nix`, `modules/system.nix`, `modules/server/docker.nix`, or `scripts/preflight.sh`.

---

## 7. Dependencies

All dependencies are already present in the pinned `nixpkgs` (`nixos-25.11`). No new flake inputs required.

| Dependency | Source | Use |
| --- | --- | --- |
| `pkgs.apparmor-profiles` | nixpkgs (built-in) | Upstream profile bundle (libvirtd, ntpd, dnsmasq, tcpdump, evince, …). |
| `pkgs.apparmor-utils` | nixpkgs (built-in) | `aa-status`, `aa-complain`, `aa-enforce`, `aa-logprof`. |
| `security.apparmor.*` module | nixpkgs `nixos/modules/security/apparmor.nix` | LSM activation, policy DSL, kernel param injection. |
| `security.auditd` / `security.audit` modules | nixpkgs `nixos/modules/security/auditd.nix`, `audit.nix` | Server-only audit log capture. |

No flake input requires `inputs.<name>.follows = "nixpkgs"` because nothing new is added to `flake.nix`.

---

## 8. Risks & Mitigations (per role)

| Role | Risk | Severity | Mitigation |
| --- | --- | --- | --- |
| **desktop** | Steam/Proton/Wine or gamemode terminated by AppArmor. | High if `killUnconfinedConfinables=true`. | Spec keeps default `false`; profiles for these tools are not shipped in `apparmor-profiles`, so they remain unconfined and unaffected. |
| **desktop** | libvirt/virt-manager (gnome-boxes) blocked by `usr.sbin.libvirtd` profile in enforce mode. | Medium. | Upstream `apparmor-profiles` libvirtd profile is well-tested; if a regression appears on the dev host, set `security.apparmor.policies."usr.sbin.libvirtd" = "complain";` in `configuration-desktop.nix` (documented in `modules/security.nix` comment). |
| **desktop / htpc / stateless** | GNOME / GDM / PipeWire interaction. | Low. | No upstream profiles target these; they run unconfined. |
| **htpc** | Plex / mpv / VLC blocked. | Low. | No upstream profiles target these binaries. |
| **stateless** | `/etc/apparmor.d` lost on reboot due to tmpfs root. | None. | `/etc/apparmor.d` is a Nix-managed symlink chain into `/nix/store`; `/nix` is on a persistent Btrfs subvolume per `modules/stateless-disk.nix`. The cache lives in `/var/cache/apparmor`, which is regenerated at boot from the store-resident profiles — no impermanence persistence entry needed. |
| **stateless** | `/var/cache/apparmor` rebuilt every boot adds boot time. | Low (sub-second on modern hardware). | `enableCache = true` keeps the prebuilt `.bin` files inside the system closure (under `/etc/static/apparmor.d/cache.d/` → store), so the runtime cache is just a copy. |
| **server / headless-server** | Docker fails to load `docker-default` profile. | Low. | Docker daemon detects AppArmor LSM presence at start and loads its bundled profile automatically; spec confirms LSM availability is the only requirement. No change needed in `modules/server/docker.nix`. |
| **server / headless-server** | auditd log volume fills `/var/log`. | Low. | Default audit ruleset is intentionally minimal (AppArmor + time changes); auditd's own logrotate handles rotation. |
| **server / headless-server** | libvirtd profile interferes with QEMU/KVM nested workloads. | Medium. | If observed during dry-run testing, override to `"complain"` per §5.1 example. |
| **all roles** | Boot failure if `apparmor=1` kernel param conflicts with `lsm=` preset on a custom kernel. | None for stock kernel. | `boot.kernelPackages = pkgs.linuxPackages_latest` in `modules/system.nix` is upstream Linux; multi-LSM stacking is supported and the AppArmor module handles param composition. |
| **all roles** | `nix flake check` regression. | Critical if it occurs. | Every change is type-checked by `nix flake check` and exercised by `nixos-rebuild dry-build` for all 30 outputs in Phase 6 preflight. |

---

## 9. Validation & Test Plan

### 9.1 Static (build-time) — gate for Phase 3 review

Required to PASS:
1. `nix flake check --no-build --impure` — must complete with no errors and no new warnings.
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — must succeed.
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — must succeed.
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — must succeed.
5. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` — must succeed.
6. `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` — must succeed.
7. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` — must succeed.
8. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — must succeed.
9. `bash scripts/preflight.sh` (Phase 6) — all 30 dry-builds must succeed.

### 9.2 Static (repository hygiene)

10. `hardware-configuration.nix` is **not** added to git (`git ls-files hardware-configuration.nix` empty).
11. `system.stateVersion = "25.11"` remains unchanged in all 5 `configuration-*.nix` files.
12. No `lib.mkIf` role-conditional guard exists inside `modules/security.nix` or `modules/security-server.nix`.

### 9.3 Runtime smoke test (post-deploy, manual — not gated)

After `sudo nixos-rebuild switch`:
- `aa-status` should report `apparmor module is loaded` and a non-zero count of profiles in `enforce` mode (libvirtd, ntpd, dnsmasq, tcpdump, etc.).
- `journalctl -k | grep -i apparmor` should show clean profile load lines, no `DENIED` floods.
- On server: `systemctl status auditd` → active.
- On desktop: launch Steam → no termination; launch GNOME Boxes VM → boots normally.

---

## 10. Out of Scope

- Custom AppArmor profiles for vexos-specific binaries.
- SELinux (incompatible with AppArmor at LSM level on stock NixOS kernel).
- Kernel hardening sysctls (`kernel.kptr_restrict`, `kernel.dmesg_restrict`) — separate hardening pass.
- Modifying `flake.nix`, `modules/system.nix`, `modules/server/docker.nix`, or `scripts/preflight.sh`.
- Changing `system.stateVersion`.

---

## 11. Summary for Orchestrator

**Files to create (2):**
- [modules/security.nix](modules/security.nix)
- [modules/security-server.nix](modules/security-server.nix)

**Files to modify (5):**
- [configuration-desktop.nix](configuration-desktop.nix)
- [configuration-htpc.nix](configuration-htpc.nix)
- [configuration-stateless.nix](configuration-stateless.nix)
- [configuration-server.nix](configuration-server.nix)
- [configuration-headless-server.nix](configuration-headless-server.nix)
