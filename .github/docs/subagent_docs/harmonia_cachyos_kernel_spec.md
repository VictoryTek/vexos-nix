# Harmonia Cache + CachyOS Desktop Kernel — Specification

**Feature:** `harmonia_cachyos_kernel`
**Date:** 2026-08-18
**Status:** Draft — Phase 1 complete

Two independent deliverables in one change:

- **Part A** — add Harmonia as a fully-wired optional server service (dormant until enabled).
- **Part B** — make the desktop role able to accept the best available CachyOS gaming kernel.

They share no code. Part B does not depend on Part A.

---

## 0. Environment Constraint (read first)

The Windows dev host has **no `nix`**:

```
$ command -v nix nixos-rebuild
NO NIX ON THIS MACHINE
```

**WSL does** — Ubuntu 24.04 with the Nix package manager (`/nix/var/nix/profiles/default/bin/nix`),
and the repo is reachable at `/mnt/c/Projects/vexos-nix`. WSL is **not NixOS**, so:

| Command | Available | Notes |
|---------|-----------|-------|
| `nix flake show --impure` | ✅ WSL | structure validation |
| `nix eval --impure .#nixosConfigurations.<x>.config.system.build.toplevel.drvPath` | ✅ WSL | requires a stub `/etc/nixos/hardware-configuration.nix`, exactly as CI creates |
| `sudo nixos-rebuild dry-build` | ❌ | needs a real NixOS host |
| `bash scripts/preflight.sh` | ⚠️ partial | shells out to `nix`; `nixos-rebuild` stages will fail on non-NixOS |

Phase 3 therefore combines **real flake evaluation in WSL** with static review of
the parts evaluation cannot reach. Full `dry-build` + `preflight.sh` remain the
user's gate on a NixOS host (§7). This change is **not** complete until those pass.

Context7 MCP (`resolve-library-id` / `get-library-docs`) is **not available** in
this session. The Dependency Policy's intent — verify external APIs against
current official sources — was satisfied by reading the pinned nixpkgs module
source and upstream READMEs directly (§3.1, §4.1).

---

## 1. Current State Analysis

### 1.1 Binary cache support today

| File | Content |
|------|---------|
| `modules/server/attic.nix` | `services.atticd`, local storage, SQLite, chunking. Port 8400. |
| `modules/nix.nix:25-56` | `vexos.attic.cacheUrl` / `vexos.attic.publicKey` client options, appended to `nix.settings.substituters` / `trusted-public-keys`. |
| `modules/nix.nix:75-80` | Substituter list — `cache.nixos.org` + optional Attic. No third-party caches. |
| `modules/secrets-sops.nix:94,160,213` | Attic RS256 key + credentials template. |
| `modules/server/backup.nix:24` | `attic = [ config.vexos.server.attic.dataDir ];` |
| `modules/server/proxy.nix:51` | Attic Caddy vhost registry entry. |
| `justfile` | `_server_service_names`, `_svc`, port table, unit map, health URL, `_check`, `just enable attic` guidance, `attic-bootstrap`, `attic-push`. |

Attic works but requires three distinct secrets (RS256 server key, admin token,
per-cache push token) plus a post-rebuild `just attic-bootstrap` run **on the
server**, and offers no way to confirm readiness. That verification gap is the
motivating complaint behind Part A.

`flake.nix` has **no `nixConfig` block** — a previous migration removed all
third-party caches (see `garnix_cache_migration_spec.md`).

### 1.2 Kernel selection today

| File | Content |
|------|---------|
| `modules/system-latest-kernel.nix:10` | `boot.kernelPackages = pkgs.linuxPackages_latest;` — **normal priority (100), unconditional**. |
| `configuration-desktop.nix:24` | imports `./modules/system-latest-kernel.nix`. |
| `configuration-stateless.nix:17` | imports the same. |
| `modules/gpu/vm-guest-additions.nix:60` | `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;` — priority **50**. |
| `modules/system-gaming.nix` | gated on `vexos.features.gaming.enable`; sets `services.scx.enable = true; scheduler = "scx_lavd"` (needs sched_ext). |
| `modules/gpu/nvidia.nix:19-20` | driver derived from `config.boot.kernelPackages.nvidiaPackages.*`. |

There is **no CachyOS kernel support of any kind** — no flake input, no overlay,
no module, no option. `boot.kernelPackages` at normal priority in
`system-latest-kernel.nix` means any second unconditional assignment is a
**module-system conflict error**, not an override.

### 1.3 Role wiring mechanics (`flake.nix:180-234`)

`roles.<role>` exposes `baseModules` / `extraModules` / `hostLocalModules`.
`extraModules` is documented as *"shared, pure modules included by BOTH mkHost
and mkBaseModule"* — the correct slot for an overlay that must apply to the
desktop role in both the `nixosConfigurations` and `nixosModules.*Base`
pathways. `roles.desktop.extraModules` is currently `[]`.

Desktop per-host toggles land in `/etc/nixos/features.nix`
(`roles.desktop.hostLocalModules = featuresModule`).

---

## 2. Problem Definition

**A.** No Harmonia support exists. If the user chooses the
build-on-vexos-vmc + serve-with-Harmonia architecture, nothing is in place. It
must be wired to the same standard as every other server service so enabling it
is a one-line change, and it must be **verifiable** — the specific failure mode
that made Attic unusable.

**B.** The desktop role hardcodes `linuxPackages_latest` at a priority that
makes any alternative kernel a hard evaluation error. There is no supported way
to select a gaming kernel.

---

## 3. Part A — Harmonia Server Service

### 3.1 Upstream API (verified against pinned nixpkgs `nixos-26.05`)

Source: `nixos/modules/services/networking/harmonia.nix`

| Option | Type | Default |
|--------|------|---------|
| `services.harmonia.package` | package | `harmonia` |
| `services.harmonia.cache.enable` | bool | `false` |
| `services.harmonia.cache.signKeyPaths` | listOf path | `[ ]` |
| `services.harmonia.cache.signKeyPath` | nullOr path | `null` — **deprecated** |
| `services.harmonia.cache.settings` | TOML attrs | `{ }` |

Defaults merged when `cache.enable`: `bind = "[::]:5000"`, `workers = 4`,
`max_connection_rate = 256`, `priority = 50`.

Systemd: unit `harmonia.service`, requires `harmonia.socket`.
`DynamicUser = true`, `RuntimeDirectory = "harmonia"`, **no `StateDirectory`**.

Sign keys are passed via systemd credentials, not direct file reads:

```
LoadCredential = map (credential: "${credential.id}:${credential.path}") credentials;
SIGN_KEY_PATHS = lib.strings.concatMapStringsSep " " (credential: "%d/${credential.id}") credentials;
```

**Design consequence:** because `LoadCredential` is processed by systemd as root
*before* the `DynamicUser` transition, the signing key may be a root-owned
`0600` file. No group, ACL, or world-readable workaround is needed. This is the
single most important API detail in this spec — getting it wrong yields a
service that starts and then fails to sign.

Note the nesting: `services.harmonia.cache.enable`, **not**
`services.harmonia.enable`. The flat form is from an older release and will
fail evaluation on 26.05.

### 3.2 New file — `modules/server/harmonia.nix`

Options under `vexos.server.harmonia`:

| Option | Type | Default | Notes |
|--------|------|---------|-------|
| `enable` | `mkEnableOption` | false | |
| `port` | port | `5000` | upstream default; no collision in the vexos port table |
| `signKeyPath` | path | `/var/lib/harmonia/cache-priv-key.pem` | |
| `openFirewall` | bool | `true` | matches every other server module |

Config body (all inside `lib.mkIf cfg.enable` — permitted carve-out: the guard
is on an option **this module declares**, the standard toggleable-subsystem
pattern, not role-smuggling):

1. **`system.activationScripts.harmoniaKey`** — generate the keypair on first
   activation if absent, mirroring the existing `atticSecret` pattern in
   `modules/server/attic.nix:57-70`:
   - `mkdir -p /var/lib/harmonia`, mode `0700`
   - `nix-store --generate-binary-cache-key "${hostName}-1" <priv> <pub>`
   - key name derived from `config.networking.hostName` so multiple vexos cache
     hosts never collide in a client's `trusted-public-keys`
   - `chmod 0600` private key; public key `0644` for `just harmonia-info`
   - **idempotent** — guarded on `[ ! -e ]`, same as Attic's

2. `services.harmonia.cache = { enable = true; signKeyPaths = [ cfg.signKeyPath ]; settings.bind = "[::]:${toString cfg.port}"; }`

3. `networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;`

No secrets-backend integration. Unlike Attic, the key is generated locally,
never transported, and has no sops representation — adding one would be
speculative complexity for a file that never leaves the host.

### 3.3 Client-side substituter options — `modules/nix.nix`

Add a `vexos.harmonia` option pair mirroring the existing `vexos.attic` block:

```nix
vexos.harmonia.cacheUrl  = "http://vexos-vmc:5000";
vexos.harmonia.publicKey = "vexos-vmc-1:AbCd...=";
```

with the same `assertion` requiring `publicKey` when `cacheUrl` is set, and the
same `lib.optional` append into `substituters` / `trusted-public-keys`.

**Rejected alternative:** generalising both into a single
`vexos.binaryCache.extraSubstituters` list. Tidier end state, but it renames
working options already referenced by deployed `/etc/nixos` files — a breaking
change well outside this request. Parallel blocks are the surgical choice; a
follow-up may unify them.

Note Harmonia's URL has **no cache-name path segment** (Attic's does) — it
serves the host store at the root.

### 3.4 Registry wiring

| File | Change |
|------|--------|
| `modules/server/default.nix` | `./harmonia.nix` under the Development heading, beside `./attic.nix` |
| `modules/server/proxy.nix` | registry row: `{ name = "harmonia"; enable = …; port = …; }` |
| `modules/server/backup.nix` | `harmonia = [ "/var/lib/harmonia" ];` — the signing key is the only state, and losing it invalidates every client's `trusted-public-keys`. Small and high-value. |
| `template/server-services.nix` | commented toggle beside Attic's |
| `justfile` | `_server_service_names`; `_svc harmonia` (Infrastructure); port-table row; unit map → `harmonia`; health URL → `http://localhost:5000`; `_check harmonia` (Infrastructure); `just enable harmonia` guidance |

### 3.5 New recipe — `just harmonia-info`

The deliberate answer to *"I couldn't tell whether it was ready."* Attic has
`attic-bootstrap`, which mints tokens but never confirms health.
`harmonia-info` verifies instead:

1. `systemctl is-active harmonia` → hard fail with remediation text if inactive
2. `curl -fsS http://localhost:<port>/nix-cache-info` → print the live response
   (the definitive readiness check — the exact document a Nix client fetches first)
3. print the public key from `<signKeyPath>.pub`
4. print the two client lines ready to paste into a host file or
   `/etc/nixos/features.nix`:
   ```
   vexos.harmonia.cacheUrl  = "http://<this-host>:5000";
   vexos.harmonia.publicKey = "<hostname>-1:....=";
   ```

No tokens, no login, no cache-creation step — nothing to bootstrap, only
something to confirm.

---

## 4. Part B — CachyOS Kernel for the Desktop Role

### 4.1 Upstream selection

| Candidate | Assessment |
|-----------|------------|
| **`xddxdd/nix-cachyos-kernel`** | **Selected.** Narrow scope (kernels only). Applies CachyOS patches + tunings to nixpkgs kernels, version-synced to nixpkgs. Exposes `overlays.pinned` → `pkgs.cachyosKernels.*`. Hydra-built, served from `https://attic.xuyh0120.win/lantian`. |
| `chaotic-cx/nyx` | Rejected. Broader than needed. Verified via GitHub API on 2026-08-18: `archived: false`, `pushed_at: 2026-08-18` — archived Dec 2025, since revived. A project that archived once without warning is a poor foundation for a kernel. |

The cache URL and key below are already documented in this repo's own
`garnix_cache_migration_spec.md:29-35`, i.e. previously in use here:

```
https://attic.xuyh0120.win/lantian
lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=
```

### 4.2 Flake input — `flake.nix`

```nix
# nix-cachyos-kernel: CachyOS-patched kernels for the desktop role.
# Consumed via overlays.pinned (see cachyosOverlayModule) and gated behind
# vexos.kernel.cachyos.enable in modules/system-cachyos-kernel.nix.
#
# Do NOT add inputs.nixpkgs.follows = "nixpkgs" — the `pinned` overlay must
# resolve against the exact nixpkgs revision upstream's binary cache was built
# against. Overriding it produces a cache miss and forces a full local kernel
# compile (hours). Deliberate exception to the follows convention, same class
# of reason as proxmox-nixos and vexboard above.
nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel";
```

This is the third documented exception to the `follows` rule in `CLAUDE.md`.
The comment is mandatory; Phase 3 must confirm it is present.

### 4.3 Overlay module + role wiring — `flake.nix`

```nix
cachyosOverlayModule = {
  nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
};
```

Attach to `roles.desktop.extraModules` (currently `[]`) — the documented slot
for shared pure modules included by **both** `mkHost` and `mkBaseModule`, so the
option behaves identically for real hosts and for
`template/etc-nixos-flake.nix` consumers.

Applying the overlay unconditionally is correct and costs nothing: an overlay
only *defines* `pkgs.cachyosKernels.*`. Nothing builds unless
`boot.kernelPackages` references it, which happens only when §4.4 is enabled.

**Scope:** desktop role only, as requested. `stateless` also imports
`system-latest-kernel.nix` and could be extended later by the same two lines.

### 4.4 New file — `modules/system-cachyos-kernel.nix`

```nix
options.vexos.kernel.cachyos = {
  enable  = lib.mkEnableOption "CachyOS gaming kernel (patched + tuned)";
  variant = lib.mkOption {
    type    = lib.types.enum [ "latest" "lts" ];
    default = "latest";
  };
};

config = lib.mkIf cfg.enable {
  boot.kernelPackages = pkgs.cachyosKernels."linuxPackages-cachyos-${cfg.variant}";
  nix.settings.substituters        = [ "https://attic.xuyh0120.win/lantian" ];
  nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
};
```

`lib.mkIf` on an option **this module declares** — the explicit CLAUDE.md
carve-out. Imported unconditionally by the desktop role, inert until switched on.

The substituter is scoped **inside** the `mkIf`, so hosts that never enable the
CachyOS kernel do not gain a third-party cache. This preserves the clean cache
list established by the garnix migration.

**`variant` enum — revised during Phase 3.** The draft allowed only
`latest` / `lts`. Live evaluation of `overlays.pinned` showed upstream exposes
**96 attributes**, including gaming-relevant scheduler flavours the draft would
have locked users out of. Upstream's `hydraJobs.nixosConfigurations` builds six
generic variants — `latest`, `latest-lto`, `bore`, `bore-lto`, `lts`,
`lts-lto` — which is the set its binary cache reliably covers. The enum was
widened to exactly those six.

Still excluded: `deckify`, `eevdf`, `bmq`, `hardened`, `rc`, `rt-bore`,
`server`, and all `x86_64-v2/v3/v4` / `zen4` micro-architecture builds. These
are not dependably cached; selecting one silently triggers a multi-hour local
kernel compile. The option description documents how to set
`boot.kernelPackages` directly for them.

**Scheduler note:** `modules/system-gaming.nix` enables `sched_ext` with
`scx_lavd`, which supersedes the in-kernel scheduler. With gaming enabled the
`latest` vs `bore` distinction therefore matters far less than it appears —
all six variants support `sched_ext`. `latest` remains the default.

### 4.5 Priority chain — `modules/system-latest-kernel.nix`

One-line change:

```nix
boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
```

Yielding a fully-ordered chain with no `mkForce` in the new module:

| Priority | Source | Wins when |
|----------|--------|-----------|
| 50 (`mkForce`) | `gpu/vm-guest-additions.nix` → `linuxPackages_6_12` | always, on VM variants |
| 100 (normal) | `system-cachyos-kernel.nix` (when enabled) | non-VM, CachyOS enabled |
| 1000 (`mkDefault`) | `system-latest-kernel.nix` | fallback |

VM variants keep their pinned 6.12 guest-additions kernel even if a user enables
CachyOS — the desired behaviour, falling out of priority arithmetic rather than
needing a guard.

Adding `lib` to that module's argument set is required (currently `{ pkgs, ... }`).

### 4.6 Interaction review

| Concern | Finding |
|---------|---------|
| `services.scx` / `scx_lavd` (`system-gaming.nix`) | Compatible. CachyOS kernels ship `sched_ext`; the module's stated floor is 6.12+ and CachyOS is well past it. No change. |
| NVIDIA (`gpu/nvidia.nix:19`) | `config.boot.kernelPackages.nvidiaPackages.stable` follows whatever is set, so it resolves. **But** upstream's cache carries no NVIDIA kmods built against CachyOS — expect a local NVIDIA module build on each kernel bump. Acceptable on desktop hardware; noted in §6. |
| `boot.kernelParams` (`system-gaming.nix`) | `preempt=full`, `split_lock_detect=off` are generic; supported by CachyOS. No change. |
| `modules/network.nix:74` | Existing comment already warns `linuxPackages_latest` may rename interfaces between kernels. Same class of risk, unchanged. |
| `system.stateVersion` | Untouched in all `configuration-*.nix`. |
| `hardware-configuration.nix` | Not added; remains host-generated. |

---

## 5. Files Changed

**New (3):**
- `modules/server/harmonia.nix`
- `modules/system-cachyos-kernel.nix`
- `.github/docs/subagent_docs/harmonia_cachyos_kernel_spec.md`

**Modified (8):**
- `flake.nix` — input, `cachyosOverlayModule`, `roles.desktop.extraModules`
- `modules/nix.nix` — `vexos.harmonia` client options
- `modules/server/default.nix` — import
- `modules/server/proxy.nix` — registry row
- `modules/server/backup.nix` — backup path
- `modules/system-latest-kernel.nix` — `mkDefault` (one line)
- `template/server-services.nix` — commented toggle
- `justfile` — registry sites + `harmonia-info` recipe

---

## 6. Risks and Mitigations

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | No `nixos-rebuild dry-build` / full preflight locally | **High** | WSL provides real `nix eval` validation (§7); `dry-build` + `preflight.sh` remain the user's gate on a NixOS host. Not claimed as verified until then. |
| 2 | `follows`-less flake input drifts from nixpkgs | Medium | Deliberate and commented. If upstream's pin diverges far enough, the symptom is a cache miss + local build, not an eval error. |
| 3 | Third-party cache trust (`attic.xuyh0120.win`) | Medium | Scoped inside `mkIf cfg.enable`, so only opted-in hosts trust it. Key already vetted in this repo's history. |
| 4 | NVIDIA kmod rebuild per kernel bump | Low | Documented. Desktop-class hardware, not vexos-vmc. |
| 5 | **Harmonia serves the entire host `/nix/store`** over HTTP | Medium | Inherent to the design — it is not a scoped cache. Store paths are world-readable locally, but this publishes *everything* on that host to the LAN, including any secret ever built into a store path. `openFirewall` defaults true to match house style; LAN-only exposure assumed. Documented in the module header — do **not** expose Harmonia to the internet. |
| 6 | Losing the Harmonia signing key breaks all clients | Low | Added to `backup.nix`. Regenerating means re-distributing `publicKey`. |
| 7 | `mkDefault` weakens an assignment two roles rely on | Low | Only `vm-guest-additions.nix` (mkForce 50) and the new module (100) set it. Chain verified in §4.5. |
| 8 | Harmonia port 5000 collision | Low | Checked against the full `justfile` port table — no vexos service uses 5000. |

---

## 7. Validation

### 7.1 Runnable in WSL (this session)

```bash
cd /mnt/c/Projects/vexos-nix
nix flake show --impure
# Stub hardware-configuration.nix required, as CI does:
nix eval --impure ".#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath"
nix eval --impure ".#nixosConfigurations.vexos-desktop-vm.config.boot.kernelPackages.kernel.version"
nix eval --impure ".#nixosConfigurations.vexos-server-amd.config.system.build.toplevel.drvPath"
```

**NEVER `nix flake check`** — see FORBIDDEN COMMANDS.

### 7.2 User must run on a NixOS host

```bash
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm     # must stay on 6.12
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd

git ls-files hardware-configuration.nix     # must be empty
grep -n 'system.stateVersion' configuration-*.nix

bash scripts/preflight.sh                   # exit code MUST be 0
```

### 7.3 Runtime smoke test (vexos-vmc, after enabling)

```bash
just enable harmonia && just rebuild
just harmonia-info          # expect: active, /nix-cache-info body, public key
```
