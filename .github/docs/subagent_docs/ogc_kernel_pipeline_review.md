# Custom Kernel Pipeline (OGC) — Phase 3 Review

**Feature:** `kernel_pipeline`
**Date:** 2026-08-19
**Spec:** `.github/docs/subagent_docs/ogc_kernel_pipeline_spec.md`
**Result:** **PASS** — pending `git add` for preflight (see §5)

---

## 1. Validation Performed

All evaluation run in WSL (Ubuntu + Nix; not NixOS). Because the new files are
untracked, flake evaluation uses the `path:` scheme, which includes untracked
files — the same technique used and explained during the Harmonia work.

| Check | Result |
|-------|--------|
| `nix-instantiate --parse` × 12 changed/new Nix files | ✅ all OK |
| CI workflow YAML parses (`yaml.safe_load`) | ✅ `jobs: ['update']` |
| OGC kernel derivation evaluates | ✅ `linux-ogc-7.2`, `modDirVersion 7.2.0` |
| **Builder/client derivation identity** | ✅ **MATCH** (§2) |
| Per-variant toplevel eval × 7 | ✅ all PASS |
| Harmonia firewall now tailnet-only | ✅ `tailscale0:[5000]`, LAN `[22]` only |
| kernel-builder unit + timer generated | ✅ both `true` |
| kernel-builder assertion without Harmonia | ✅ fires with correct message |
| Desktop default kernel unchanged (feature off) | ✅ `pname = linux` |
| VM keeps its 6.12 pin even with feature ON | ✅ `6.12.103` |

### Per-variant evaluation

```
PASS  vexos-desktop-amd          PASS  vexos-server-amd
PASS  vexos-desktop-nvidia       PASS  vexos-headless-server-amd
PASS  vexos-desktop-vm           PASS  vexos-stateless-amd
PASS  vexos-htpc-amd
```

---

## 2. The Load-Bearing Check: Derivation Identity

The entire design fails silently if the kernel the builder produces is not
byte-identical to the one a desktop requests — Harmonia would serve a path no
client ever asks for, and every desktop would compile locally while appearing
to be configured correctly.

Verified directly:

```
builder: packages.x86_64-linux.kernel-ogc
  /nix/store/mfv9h0lz2jcm2z2f0ap1sr5m1jlsjcjq-linux-ogc-7.2.drv

client:  desktop-amd + vexos.features.kernel.enable = true
  /nix/store/mfv9h0lz2jcm2z2f0ap1sr5m1jlsjcjq-linux-ogc-7.2.drv

MATCH
```

This is why `packages.${system}` in `flake.nix` is constructed from the same
overlay set the nixosConfigurations use, rather than a convenience `pkgs`.

---

## 3. Findings Resolved During Implementation

### F-1 — `freeform` values must not be self-quoted (real bug, caught by eval)

`ANDROID_BINDER_DEVICES` was written as `freeform ''"binder,..."''`, producing
a doubly-quoted config value. nixpkgs adds the quotes itself. Fixed.

### F-2 — A bad probe was produced and discarded

An initial attempt to compute config overlaps by calling `common-config.nix`
directly returned `overlapCount: 0`, contradicting an error already observed.
The call signature was wrong, so `base.settings` silently defaulted to `{}`.
The probe was discarded and replaced with a direct `grep` of the nixpkgs source
in the store, which produced the correct answer. Recorded because the false
negative was plausible-looking and would have hidden 23 real conflicts.

### F-3 — 23 config keys overlap nixpkgs' `common-config.nix`

Of 128 OGC keys, 23 collide. Most agree in intent but differ in nixpkgs'
`optional` flag, which is sufficient to conflict. All 23 are handled through a
single named `overriddenByOgc` list in `pkgs/kernels/ogc/config.nix`, applied
via `lib.mapAttrs` + `lib.mkForce`. A future nixpkgs bump that introduces a new
overlap fails loudly and names the key.

**Three are genuine value divergences**, documented inline:

| Key | nixpkgs | OGC | Note |
|-----|---------|-----|------|
| `BPF_JIT_ALWAYS_ON` | `no` | `yes` | nixpkgs disables citing NixOS/nixpkgs#79304. **First thing to suspect on BPF-related breakage.** |
| `CROS_EC_ISHTP` | `module` | `no` | explicitly unset upstream |
| `U_SERIAL_CONSOLE` | `yes` | `no` | explicitly unset upstream |

### F-4 — Baked-in `cacheUrl` default would have broken every host

Making `vexos.harmonia.cacheUrl` default to `http://cache:5000` while
`publicKey` starts empty would have tripped the pre-existing assertion on
**every** host, making a fresh checkout unbuildable.

Resolved by replacing that assertion with a `warnings` entry and gating the
substituter on `publicKey != ""`. An unverifiable cache is useless anyway, so
not adding it is the correct behaviour; the warning explains the one-time fix.
This preserves the zero-configuration goal without a bootstrap deadlock.

---

## 4. Compliance

| Requirement | Status |
|-------------|--------|
| Device-agnostic (no hostname anywhere) | ✅ `vexos.server.kernelBuilder` enableable on any host; cache reached via MagicDNS `cache` |
| Multi-kernel / extensible | ✅ registry at `pkgs/kernels/default.nix`; adding a kernel = directory + one line + one CI matrix entry |
| `vexos.features.*` namespace | ✅ `vexos.features.kernel.{enable,name}`; registered in `_feature_names` |
| Module Architecture Pattern (Option B) | ✅ `lib.mkIf` only on options the same module declares |
| No `nix flake check` | ✅ |
| `system.stateVersion` untouched | ✅ |
| `hardware-configuration.nix` not tracked | ✅ |
| Kernel priority ladder honoured | ✅ `mkOverride 90`; VM `mkForce 50` still wins (verified) |
| Secrets | ✅ no plaintext; Harmonia key sops-managed with non-sops fallback |
| Security | ✅ Harmonia moved from LAN-wide to `tailscale0` only |

---

## 5. Preflight Status

`scripts/preflight.sh` stage `[8/8]` builds through the **git** flake ref, and
Nix flakes copy only git-tracked files. The new files are untracked, so
evaluation cannot see `pkgs/kernels`:

```
error: path '/nix/store/…-source/pkgs/kernels' does not exist
```

This is not a code defect — the identical evaluation succeeds through `path:`
(§1, §2). `CLAUDE.md` forbids this agent from running `git add`, so it is a
user action:

```bash
git add pkgs/kernels modules/system-custom-kernel.nix \
        modules/server/kernel-builder.nix \
        .github/workflows/update-kernels-nightly.yml \
        .github/docs/subagent_docs/ogc_kernel_pipeline_*.md
bash scripts/preflight.sh          # expect exit 0
```

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A+ |
| Best Practices | 96% | A |
| Functionality | 97% | A |
| Code Quality | 95% | A |
| Security | 97% | A |
| Performance | 95% | A |
| Consistency | 97% | A |
| Build Success | 95% | A |

**Overall Grade: A (96%)**

Build Success is 95% rather than 100% because the kernel has been *evaluated*
but never *compiled* — the first real build is a multi-hour job that must
happen on the builder host (§7).

---

## 7. Remaining Runtime Work (user-side)

1. `git add` the new files, re-run preflight.
2. Tailscale admin console: enable MagicDNS; rename the cache host to `cache`.
3. On the cache host: `just enable harmonia && just enable kernel-builder && just rebuild`
4. `just harmonia-info` → commit the printed `publicKey` into `modules/nix.nix`
   (one time; this is what makes every other host zero-config).
5. `just kernel-build-now` → the first real compile. **Not yet exercised**; this
   is the one step no amount of evaluation can substitute for.
6. On a desktop: `just enable-feature kernel && just update` → expect a
   download. The `_kernel-cache-guard` recipe will stop the rebuild with an
   explanatory message if the builder has not finished yet.
