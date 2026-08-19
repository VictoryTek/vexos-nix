# Harmonia + CachyOS Kernel — Phase 3 Review

**Feature:** `harmonia_cachyos_kernel`
**Date:** 2026-08-18
**Spec:** `.github/docs/subagent_docs/harmonia_cachyos_kernel_spec.md`
**Result:** **NEEDS_REFINEMENT** (2 issues — 1 CRITICAL, 1 RECOMMENDED)

---

## 1. Validation Performed

The Windows dev host has no `nix`. WSL (Ubuntu 24.04 + Nix, **not** NixOS) was
used instead, and turned out to already carry a stub
`/etc/nixos/hardware-configuration.nix`, which made **full flake evaluation
possible** — not merely static review.

| Check | Command | Result |
|-------|---------|--------|
| Nix syntax, all 12 changed/new files | `nix-instantiate --parse` | ✅ all OK |
| Flake structure | `nix flake show --impure` | ✅ exit 0 |
| Upstream overlay exists | `nix eval …#overlays --apply builtins.attrNames` | ✅ `[ "default" "pinned" ]` |
| Upstream attribute names | overlay applied to nixpkgs, `attrNames pkgs.cachyosKernels` | ✅ 96 attrs; `linuxPackages-cachyos-{latest,lts,bore,…}` present |
| Kernel priority chain | isolated `nixosSystem` probe | ⚠️ see CRIT-1 |
| Harmonia module contract | isolated `nixosSystem` probe | ✅ all assertions passed |
| Per-variant closure eval | `nix eval …system.build.toplevel.drvPath` × 6 | ⚠️ see CRIT-1 |
| `hardware-configuration.nix` untracked | `git ls-files` | ✅ empty |
| `system.stateVersion` unchanged | `git diff` + `grep` | ✅ all six remain `25.11` |
| `follows` exception documented | `grep` | ✅ comment present |
| `flake.lock` — only additions | `git diff flake.lock` | ✅ 5 new nodes, no existing rev changed |
| Preflight | `bash scripts/preflight.sh` | ❌ see CRIT-2 |

### Harmonia module probe — all passed

```json
{"disabled_cacheEnable":false,"disabled_firewall":[],"disabled_hasActivation":false,
 "enabled_cacheEnable":true,"enabled_bind":"[::]:5000","enabled_unitExists":true,
 "enabled_signKeyPaths":["/var/lib/harmonia/cache-priv-key.pem"],"enabled_firewall":[5000],
 "alt_bind":"[::]:5555","alt_firewall":[],
 "activationHasKeygen":true,"activationHasHostKey":true}
```

Confirms: fully inert when disabled; correct upstream `services.harmonia.cache.*`
nesting; `port` and `openFirewall` honoured; activation script generates a
hostname-derived key (`vexos-vmc-1`).

---

## 2. Findings

### CRIT-1 — `mkDefault` on `system-latest-kernel.nix` collides with `system.nix`

**Severity: CRITICAL.** Broke three previously-working variants.

```
error: The option `boot.kernelPackages' is defined multiple times while it's expected to be unique.
 - In `.../modules/system-latest-kernel.nix'
 - In `.../modules/system.nix'
```

`vexos-desktop-amd`, `vexos-desktop-nvidia` and `vexos-stateless-amd` all failed
to evaluate.

**Cause — a research error in Phase 1.** The `grep` used to enumerate
`boot.kernelPackages` definitions was truncated with `head -30` and returned
exactly 30 lines, silently hiding `modules/system.nix:85`. The spec's §4.5
priority table was therefore built from an incomplete picture: it listed **two**
existing definitions when there are **four**.

Actual ladder in this repo (lower number = higher priority):

| Priority | Source |
|----------|--------|
| 1000 `mkDefault` | `modules/system.nix:85` |
| 100 normal | `modules/system-latest-kernel.nix`, `modules/system-lts-kernel.nix` |
| 75 `mkOverride` | `modules/zfs-server.nix` |
| 50 `mkForce` | `modules/gpu/vm-guest-additions.nix` |

Lowering `system-latest-kernel.nix` to `mkDefault` put it at 1000 — equal to
`system.nix`, with no merge function. `vexos-desktop-vm` masked the bug because
`vm-guest-additions.nix`'s `mkForce` (50) outranks both.

**Fix applied (Phase 4):** revert `system-latest-kernel.nix` to its original
normal-priority definition, and slot the new module in at `lib.mkOverride 90`
instead. This is strictly better than the spec's design — it beats the role's
kernel track, still loses to the ZFS (75) and VM (50) pins, collides with
nothing, and means `system-latest-kernel.nix` needs no behavioural change at
all (only an added comment), satisfying the surgical-changes principle.

### CRIT-2 — Preflight fails: new modules are untracked by git

**Severity: CRITICAL — blocks Phase 6. Requires user action.**

```
[8/8] Building pkgs.vexos.vexos-update ...
error: path '/nix/store/…-source/modules/system-cachyos-kernel.nix' does not exist
✗ FAIL   Preflight FAILED
```

Nix flakes copy **only git-tracked files** into the store. The three new files
are untracked, so `configuration-desktop.nix` imports a path that does not exist
in the flake source.

Proven by differential test — identical build, two source schemes:

```
path:/mnt/c/Projects/vexos-nix#…   → path_scheme_exit=0   (untracked files included)
.#…                                 → git_flake_exit=1     (tracked files only)
```

**This is not a code defect** — the implementation is correct. It resolves the
moment the files are tracked. `CLAUDE.md` forbids this agent from running
`git add`, so it is handed to the user:

```
git add modules/server/harmonia.nix modules/system-cachyos-kernel.nix \
        .github/docs/subagent_docs/harmonia_cachyos_kernel_spec.md
```

CI would have hit exactly this, so preflight did its job.

### REC-1 — `variant` enum too narrow for "best gaming kernel available"

**Severity: RECOMMENDED.** The spec allowed only `latest` / `lts`. Live
evaluation showed upstream exposes 96 attributes including gaming-relevant
scheduler flavours (`bore`, `deckify`, `eevdf`, `bmq`, `rt-bore`). Upstream's
`hydraJobs.nixosConfigurations` builds six generic variants — precisely the
reliably-cached set.

**Fix applied (Phase 4):** enum widened to `latest`, `latest-lto`, `bore`,
`bore-lto`, `lts`, `lts-lto`. Uncached micro-architecture (`x86_64-v2/v3/v4`,
`zen4`) and niche flavours remain excluded to avoid a silent multi-hour local
compile; the option description documents how to select them manually.

Also documented: `modules/system-gaming.nix` enables `sched_ext` with
`scx_lavd`, which supersedes the in-kernel scheduler — so with gaming on, the
`latest` vs `bore` choice matters much less than it appears.

---

## 3. Non-Findings (checked, no action)

- **Pre-existing preflight warnings** — `vexboard.nix:90` placeholder secret;
  `jq` / `nixpkgs-fmt` / `gitleaks` absent in WSL. None related to this change.
- **`nix.settings.substituters` merging** — `types.listOf` concatenates across
  modules, so the CachyOS substituter merges cleanly with `modules/nix.nix`.
  Verified live.
- **Duplicate `cache.nixos.org` / key in the merged list** — pre-existing NixOS
  default-merging artefact, present before this change. Harmless.
- **Lazy `mkIf`** — `pkgs.cachyosKernels` is not forced when the option is off,
  so roles without the overlay cannot break. Confirmed: server/headless/stateless
  all evaluate.
- **Module Architecture Pattern** — both new modules use `lib.mkIf` on an option
  the same module declares (the explicit CLAUDE.md carve-out). No role/display/
  gaming-flag guards added to shared modules.
- **Security** — no hardcoded secrets; Harmonia key is root-owned `0600` and
  reaches the `DynamicUser` service via systemd `LoadCredential`.

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 88% | B+ |
| Functionality | 70% | C- |
| Code Quality | 92% | A- |
| Security | 95% | A |
| Performance | 95% | A |
| Consistency | 95% | A |
| Build Success | 50% | F |

**Overall Grade: C+ (84%)** — **NEEDS_REFINEMENT**

Build Success is scored on the Phase 3 state: 3 of 6 variants failed to
evaluate (CRIT-1) and preflight failed (CRIT-2).

→ Proceed to Phase 4 refinement, then Phase 5 re-review
(`harmonia_cachyos_kernel_review_final.md`).
