# Harmonia + CachyOS Kernel — Phase 5 Re-Review (Final)

**Feature:** `harmonia_cachyos_kernel`
**Date:** 2026-08-18
**Refinement cycle:** 1 of 2
**Result:** **APPROVED — code complete.** Phase 6 preflight blocked on one
user action (`git add`); see §4.

---

## 1. Refinements Applied (Phase 4, cycle 1)

| ID | Issue | Resolution | Verified |
|----|-------|-----------|----------|
| CRIT-1 | `mkDefault` collided with `modules/system.nix` at priority 1000 | Reverted `system-latest-kernel.nix` to its original normal-priority definition (comment only); new module now uses `lib.mkOverride 90` | ✅ all 6 variants evaluate |
| CRIT-2 | New modules untracked → absent from flake source | Not a code defect. Requires `git add` — forbidden to this agent | ⚠️ user action (§4) |
| REC-1 | `variant` enum too narrow | Widened to the six Hydra-built variants | ✅ `latest` / `bore` / `lts` all resolve |

`modules/system-latest-kernel.nix` now differs from `main` **only by a comment** —
its `boot.kernelPackages` line is byte-identical to the original.

---

## 2. Verification Evidence

### 2.1 Per-variant closure evaluation — 6/6 PASS

```
PASS  vexos-desktop-amd          -> nrg15kz6zshqqv7znz1n3kjdqm42lhh3-nixos-system-vexos-26.05.drv
PASS  vexos-desktop-nvidia       -> hqypxrpqzirya3r2i6yhk5540sqwcx7c-nixos-system-vexos-26.05.drv
PASS  vexos-desktop-vm           -> rl62ngm0q50clg12w6fb0mf26wai1zhk-nixos-system-vexos-26.05.drv
PASS  vexos-server-amd           -> nxy25hl7x9g2jxzcx6lgwk2kxx996dq6-nixos-system-vexos-26.05.drv
PASS  vexos-headless-server-amd  -> 0nvk1bvijza14kqc89qwkvv3z97wscgr-nixos-system-vexos-26.05.drv
PASS  vexos-stateless-amd        -> zb1rcadssgjlsbj9smx3cd8zvdfm6rmy-nixos-system-vexos-26.05.drv
```

(Was 3 PASS / 3 FAIL before refinement.) This is the same evaluation CI performs
per role — `nix eval …config.system.build.toplevel.drvPath`.

### 2.2 Default behaviour unchanged (regression check)

```
vexos-desktop-amd: linux 7.1.8        <- stock linuxPackages_latest, CachyOS off
vexos-desktop-vm:  linux 6.12.103     <- VM guest-additions pin intact
```

With the option disabled, `pname` is `linux` — the CachyOS kernel is not
selected and nothing about existing hosts changes.

### 2.3 End-to-end enable test on the real flake configurations

Via `extendModules` on the actual `nixosConfigurations`:

```
desktop-amd, cachyos enabled:
  default(latest) -> linux-cachyos-latest 7.1.8
  bore            -> linux-cachyos-bore   7.1.8
  lts             -> linux-cachyos-lts    6.18.42
desktop-vm, cachyos enabled (mkForce 50 must still win):
  vm              -> linux 6.12.103          ✅ VM pin still wins
```

Harmonia enabled on the real headless-server config:

```json
{"bind":"[::]:5000","unit":true,"fw":[22,5000],
 "subs":["https://cache.nixos.org","https://cache.nixos.org/"]}
```

Harmonia client options on the real desktop config:

```json
{"subs":["https://cache.nixos.org","http://vexos-vmc:5000","https://cache.nixos.org/"],
 "keys":["cache.nixos.org-1:6NCH…","cache.nixos.org-1:6NCH…","vexos-vmc-1:AAAA="]}
```

Substituter and trusted key both appear. (The duplicated `cache.nixos.org`
entry is a pre-existing NixOS default-merge artefact, unrelated to this change.)

### 2.4 `dry-build` equivalent — 6/6 PASS

`nixos-rebuild dry-build` is a wrapper around `nix build --dry-run` on
`config.system.build.toplevel`; that underlying command does **not** require a
NixOS host and was run in WSL:

```
PASS  dry-build  vexos-desktop-amd          (~686 derivations)
PASS  dry-build  vexos-desktop-nvidia       (~689)
PASS  dry-build  vexos-desktop-vm           (~697)
PASS  dry-build  vexos-server-amd           (~682)
PASS  dry-build  vexos-headless-server-amd  (~444)
PASS  dry-build  vexos-stateless-amd        (~675)
```

This closes the Phase 3 build-validation requirement. A `nixos-rebuild
dry-build` on a real NixOS host remains desirable as a final sanity check
(it additionally exercises the host's own `hardware-configuration.nix` rather
than the WSL stub), but is no longer the only available evidence.

### 2.5 CachyOS kernel is genuinely cached upstream

The design rests on the claim that enabling the option downloads a kernel
rather than compiling one. A first attempt via `nix build --dry-run` was
**inconclusive** — WSL's nix refused the third-party substituter
(`ignoring untrusted substituter … you are not a trusted user`) and so only
consulted `cache.nixos.org`, making the kernel look uncached.

Verified instead by querying the cache directly for each output path's
`.narinfo`:

```
qzy4l8hzapkwf37m75h041v9ax68afm1-linux-cachyos-latest-7.1.8   CACHED (HTTP 200)
awszn8n7k9n6r0ikkqvm12hr463d5q5m-linux-cachyos-bore-7.1.8     CACHED (HTTP 200)
```

Both resolve on `https://attic.xuyh0120.win/lantian`. Enabling
`vexos.kernel.cachyos` is therefore a download (~750 MiB for the wider closure),
not a multi-hour local kernel build — confirming both the `pinned`-overlay
choice and the decision to exclude uncached micro-architecture variants.

### 2.6 Repo invariants

| Invariant | Result |
|-----------|--------|
| `hardware-configuration.nix` not tracked | ✅ `git ls-files` empty |
| `system.stateVersion` unchanged | ✅ all six files remain `25.11` |
| `follows` exception commented in `flake.nix` | ✅ present |
| `flake.lock` — additions only | ✅ 5 new nodes; no existing input rev changed |
| No `nix flake check` used anywhere | ✅ |
| Module Architecture Pattern (Option B) | ✅ `mkIf` only on self-declared options |

---

## 3. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A+ |
| Best Practices | 97% | A |
| Functionality | 98% | A+ |
| Code Quality | 96% | A |
| Security | 95% | A |
| Performance | 96% | A |
| Consistency | 97% | A |
| Build Success | 95% | A |

**Overall Grade: A (96%)** — **APPROVED**

Build Success is 95% rather than 100% because `nixos-rebuild dry-build` cannot
run on a non-NixOS host; `nix eval` of the toplevel `drvPath` is the CI-grade
equivalent and passed for all six targets.

---

## 4. Phase 6 — Preflight Status: BLOCKED on user action

`scripts/preflight.sh` currently exits 1, solely at stage `[8/8]`, because the
three new files are untracked and Nix flakes copy only git-tracked files.

Stages `[0/8]`–`[7/8]` pass, apart from environment-only skips in WSL
(`jq`, `nixpkgs-fmt`, `gitleaks` not installed) and one pre-existing warning
(`modules/server/vexboard.nix:90` placeholder secret) unrelated to this change.

**Required user action** (this agent is forbidden from git write operations):

```bash
git add modules/server/harmonia.nix \
        modules/system-cachyos-kernel.nix \
        .github/docs/subagent_docs/harmonia_cachyos_kernel_spec.md \
        .github/docs/subagent_docs/harmonia_cachyos_kernel_review.md \
        .github/docs/subagent_docs/harmonia_cachyos_kernel_review_final.md
```

Then re-run preflight (WSL is sufficient — it needs `nix`, not NixOS):

```bash
bash scripts/preflight.sh                                    # expect exit 0
```

**All nix-based validation is complete** (§2.1–2.5): flake structure, six
per-variant closure evaluations, six `dry-run` toplevel builds, end-to-end
option-enable tests, and upstream cache verification. The remaining blocker is
**not** a nix limitation — it is a `git add`, which `CLAUDE.md` forbids this
agent from performing.

Optional final sanity check on a real NixOS host (exercises the host's own
`hardware-configuration.nix` instead of the WSL stub):

```bash
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm      # must stay 6.12
```

Work is **not** complete under `CLAUDE.md` until preflight exits 0.

---

## 5. Runtime Notes for First Use

**Harmonia** (on vexos-vmc):
```bash
just enable harmonia && just rebuild
just harmonia-info      # confirms live + prints client config
```
Harmonia serves only what is currently in that host's store, and
`min-free`/`max-free` GC will evict unreferenced paths. Pin anything that must
stay served:
```bash
nix-store --add-root /var/lib/harmonia/roots/<name> -r <store-path>
```
It serves the **entire** store to anyone who can reach port 5000 — keep it on
the LAN.

**CachyOS kernel** (desktop hosts), in `/etc/nixos/features.nix`:
```nix
vexos.kernel.cachyos.enable = true;
# vexos.kernel.cachyos.variant = "bore";   # optional
```
First rebuild adds `https://attic.xuyh0120.win/lantian` as a substituter and
downloads the kernel. NVIDIA hosts will still build the NVIDIA kernel module
locally — upstream's cache carries no NVIDIA kmods for CachyOS.
