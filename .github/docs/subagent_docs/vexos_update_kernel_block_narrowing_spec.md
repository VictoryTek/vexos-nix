# Spec — Narrow the vexos-update heavy-build block to the kernel source build

Feature name: `vexos_update_kernel_block_narrowing`
Date: 2026-07-29

---

## 1. Current state analysis

`vexos-update` (`pkgs/vexos-update/default.nix`) classifies every derivation in the
`nixos-rebuild dry-build` "will be built" list into three groups:

| Group | Regex | Action |
|-------|-------|--------|
| HEAVY | `^(linux-[0-9][^/]*-modules\|linux-[0-9][^/]*-modules-shrunk)` | block, restore `flake.lock`, exit 2 (`VEXOS_CACHE_BLOCK`) |
| UNAVOIDABLE | `^(NVIDIA-Linux-\|nvidia-x11-\|nvidia-settings-\|nvidia-persistenced-\|openrazer-[0-9])` | proceed, log `VEXOS_LOCAL_BUILD` |
| everything else | — | proceed, log `VEXOS_LOCAL_BUILD` |

`HEAVY_BUILD_REGEX` is defined once at line 117 and consumed twice:

- line 142 — kernel-install-override auto-clear (`STILL_HEAVY`): decides whether
  `/etc/nixos/kernel-install-override.nix` may be removed
- line 199 — the main classifier (`HEAVY_BUILDS`)

Two further copies of the classification exist:

- `justfile:444` (`upgrade-analysis` recipe) — carries the **pre-split** value that
  still includes `NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9]`; already
  divergent from `vexos-update`
- `README.md:157-163` — prose description of the same classification, also describing
  the pre-split behaviour ("Heavy builds (kernel modules, NVIDIA driver, OpenRazer DKMS
  module)")

`scripts/install.sh` holds only `UNAVOIDABLE_REGEX` (line 458); it has **no**
heavy-build regex, so it is unaffected by this change.

---

## 2. Problem definition

`HEAVY_BUILD_REGEX` matches only the two kernel *aggregate* derivations, never the
kernel source build itself. Both aggregates are:

**(a) structurally uncacheable for any host with out-of-tree modules.**
`nixos/modules/system/boot/kernel.nix:299` builds them from
`pkgs.aggregateModules`, whose `paths` are that host's `boot.extraModulePackages`
(`pkgs/os-specific/linux/kmod/aggregator.nix`). The derivation is therefore
configuration-specific, and Hydra can only ever cache the variant matching nixpkgs'
own module set.

Measured on `vexos-desktop-nvidia` (this host):

| store path | `cache.nixos.org` narinfo |
|---|---|
| `linux-7.1.5-modules` | **404** |
| `linux-7.1.5` (kernel source build) | **200** |

`nix-store -q --references` on the aggregate returns `nvidia-open`, `xone`,
`xpad-noone`, `xpadneo` — confirming the out-of-tree dependency set that makes it
host-specific.

**(b) cheap.** The aggregate is a `buildEnv` symlink tree plus one `depmod` run
(`aggregator.nix`); `-modules-shrunk` is a `stdenvNoCC.mkDerivation` that copies a
module subset (`pkgs/build-support/kernel/modules-closure.nix`). Neither compiles
anything. Seconds to a minute, not hours.

### Consequences

1. **False `VEXOS_CACHE_BLOCK` on every kernel bump.** The block message says
   "typically 1-3 days until Hydra caches them" for a derivation Hydra will never
   cache. `just update` is refused; the user's only real recourse is `just update-all`
   (full force) or `just deploy` (which deliberately does *not* bump nixpkgs), so the
   nixpkgs bump is held indefinitely.
2. **The `UNAVOIDABLE_REGEX` exemption is defeated.** The exemption exists so unfree
   `nvidia-x11` / patched `openrazer` do not permanently block NVIDIA hosts — but the
   aggregate that *depends on them* matches HEAVY first, so the block fires anyway.
3. **`kernel-install-override.nix` can never auto-clear on such hosts.** The
   `STILL_HEAVY` check at line 142 always matches the aggregate, so the installer's
   fallback to `pkgs.linuxPackages` is retained forever and the host never upgrades to
   its intended kernel.

The genuinely hours-long, genuinely cacheable build the block was written to prevent
is the kernel source derivation `linux-<version>` — which the current regex does not
match at all.

---

## 3. Proposed solution architecture

Redefine `HEAVY_BUILD_REGEX` to match the kernel **source build** and nothing else:

```
HEAVY_BUILD_REGEX='^linux-[0-9][0-9.]*(-rc[0-9]+)?$'
```

Anchored at both ends, so:

| derivation name | matches | rationale |
|---|---|---|
| `linux-7.1.5` | yes | hours to compile; Hydra does cache it |
| `linux-6.14-rc1` | yes | same |
| `linux-7.1.5-modules` | no | cheap `buildEnv`; never cacheable per-host |
| `linux-7.1.5-modules-shrunk` | no | cheap `stdenvNoCC` copy |
| `linux-config-7.1.5` | no | `[0-9]` fails on `c` |
| `linux-firmware-*` | no | `[0-9]` fails on `f` |
| `NVIDIA-Linux-*`, `nvidia-x11-*` | no | already handled by `UNAVOIDABLE_REGEX` |

Protection is preserved: whenever the kernel source itself must be compiled, the
aggregates must be rebuilt too, but the kernel derivation is present in the same
"will be built" list, so the block still fires. The aggregates were only ever a
redundant — and permanently stuck-on — proxy signal.

### Why the existing three-way partition stays exhaustive

`NON_HEAVY_BUILDS` is computed as `grep -Ev "$HEAVY_BUILD_REGEX|$UNAVOIDABLE_REGEX"`.
Because the new regex no longer matches the aggregates, they fall into
`NON_HEAVY_BUILDS` and are reported as fast local builds — accurate, and no derivation
ends up in zero buckets. No structural change to the partition is required.

### Scope boundaries (deliberate)

- **No new blocking entries.** `zfs-kernel-*` and `nvidia-open-*` are not added to
  HEAVY. Both are minutes, not hours, and neither is part of the reported problem.
- **`justfile` gets the regex alignment only**, not a third display bucket. The
  `upgrade-analysis` recipe is a read-only advisory report; adding an UNAVOIDABLE
  bucket there is not required to fix the block and would violate Simplicity First.
  Its labels are reworded so the buckets are not mislabelled.
- **`scripts/install.sh` is not touched** — it has no heavy regex.

---

## 4. Implementation steps

### Step 1 — `pkgs/vexos-update/default.nix`

1. Replace the `HEAVY_BUILD_REGEX` value (line 117) with
   `'^linux-[0-9][0-9.]*(-rc[0-9]+)?$'`.
2. Rewrite the comment block above it (lines 113-116) to state what is matched and
   why the aggregates are excluded (host-specific `buildEnv`, never cacheable, cheap).
3. Update the classifier comment (lines 171-172) to describe the kernel source build
   rather than "kernel modules".
4. Update the `VEXOS_CACHE_BLOCK:` message text (lines 214-215) from "kernel packages
   require a local source build" to name the kernel itself.

Verify: `grep -n 'HEAVY_BUILD_REGEX' pkgs/vexos-update/default.nix` shows one
definition and two consumers, unchanged in structure.

### Step 2 — `justfile` (`upgrade-analysis`, line 444)

1. Replace the stale combined regex with the same new value.
2. Update the comment to reference the kernel source build and note the value must
   stay in sync with `pkgs/vexos-update/default.nix`.
3. Reword the two mislabelled report lines: "Heavy kernel/NVIDIA builds (hours — will
   block update)" → kernel-only wording; "Non-heavy local builds (fast — system glue,
   scripts)" → "Other local builds" so NVIDIA userspace is not described as fast.
4. Same for the `── Heavy builds — kernel/NVIDIA not yet in cache ──` section header.

Verify: `just --evaluate` / `just --list` parses; regex contains no `{` so it cannot
collide with `just`'s `{{ }}` interpolation.

### Step 3 — `README.md` (lines 157-163)

Update the two classification bullets so the documented behaviour matches: heavy =
kernel source build only; NVIDIA userspace / OpenRazer / kernel module aggregates =
local builds that proceed.

### Step 4 — Validation

- `bash -n` equivalent via `writeShellApplication` shellcheck at build time
  (`nixos-rebuild dry-build` builds the package, so shellcheck runs)
- `nix flake show --impure`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `bash scripts/preflight.sh`

---

## 5. Dependencies

None. No new flake inputs, no new packages, no external libraries — Context7 not
applicable (internal shell/regex change only).

---

## 6. Configuration changes

None. `VEXOS_UPDATE_STRICT=1` behaviour is unchanged (it still overrides the
partition to treat all local builds as heavy). No option renames, no
`system.stateVersion` impact.

---

## 7. Risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| A genuinely uncached kernel slips through because its derivation name is not `linux-<ver>` (e.g. `linux-hardened-*`, `linux-zen-*`) | Low | Pre-existing limitation — the old regex was also anchored to `linux-[0-9]`. All kernels used in this repo (`linuxPackages_latest`, `linuxPackages`, `linuxPackages_6_12`) produce `linux-<version>`. No coverage regression. |
| `nvidia-open` / `zfs-kernel` module builds (minutes) now proceed unblocked on a kernel bump | Low | Intended. They are logged as `VEXOS_LOCAL_BUILD` and are minutes, matching the existing treatment of `nvidia-x11` (~10-15 min) under `UNAVOIDABLE_REGEX`. |
| The two regex copies drift again | Medium | Cross-referencing comments added at both sites, matching the existing convention used for `UNAVOIDABLE_REGEX` between `vexos-update` and `install.sh`. |
| `kernel-install-override.nix` now auto-clears on hosts where it was previously stuck | Low | This is the intended repair. If the target kernel is genuinely uncached, `STILL_HEAVY` matches `linux-<ver>` and the override is rewritten as before. |

---

## 8. Sources consulted

1. `pkgs/os-specific/linux/kmod/aggregator.nix` — nixpkgs pinned rev
   (`/nix/store/0qgjkdn0xns7h8h19jzhxpvxcsmslk23-source`): aggregate is `buildEnv` +
   `depmod`, `paths = modules`
2. `nixos/modules/system/boot/kernel.nix:299` — same rev: aggregate name is
   `<kernel.name>-modules`
3. `pkgs/build-support/kernel/modules-closure.nix` — same rev: `-shrunk` name and
   `stdenvNoCC` (no compilation)
4. `cache.nixos.org` narinfo probes: `linux-7.1.5-modules` → 404,
   `linux-7.1.5` → 200
5. `nix-store -q --references /run/current-system/kernel-modules` — out-of-tree
   module set proving host specificity
6. Repo: `pkgs/vexos-update/default.nix`, `justfile:393` (`deploy`), `justfile:444`
   (`upgrade-analysis`), `scripts/install.sh:458`, `README.md:157-163`,
   `modules/system.nix:85` (`linuxPackages_latest` from stable nixpkgs)
7. Prior design record: `.github/docs/subagent_docs/vexos_update_nvidia_unavoidable_spec.md`
   — establishes the HEAVY/UNAVOIDABLE split whose intent this change completes
