# nvidia_legacy580_kernel72 — Specification

**Phase 1 — Research & Specification**
Feature: build the `legacy_580` NVIDIA variant against Linux 7.2 so desktop/stateless
hosts stay on `linuxPackages_latest` instead of being pinned to a removed kernel.

---

## 1. Current state analysis

### What broke

CI job `evaluate (desktop)` fails on `vexos-desktop-nvidia-legacy580`:

```
error: linux 7.1 was removed because it has reached its end of life upstream
       # Added 2026-09-02  (pkgs/top-level/linux-kernels.nix:686)
```

`nixpkgs` rev `6aefcda9` (current `flake.lock`) removed the `linux_7_1` /
`linuxPackages_7_1` attributes. `linuxPackages_latest` is now `7.2.4`;
`linux_7_0` was removed 2026-06-27, `linux_7_1` on 2026-09-02.

### Why the pin exists

Commit `2b59999` ("feat(gpu): build NVIDIA on 7.2, pin legacy_580 hosts to 7.1")
introduced two independent things:

1. **`modules/gpu/nvidia.nix`** — the `"latest"` variant (open modules, 595.71.05)
   gets the CachyOS `kernel_7_2_patch` (`fetchpatch`, commit-pinned) attached to
   `stable.open` via `overrideAttrs`. This is the "fix it" path and it still works.
2. **`modules/gpu/nvidia-legacy-kernel.nix`** — the `"legacy_580"` variant
   (closed modules, 580.173.02) was **never patched**. Instead the kernel is
   pinned: `boot.kernelPackages = lib.mkOverride 95 pkgs.linuxPackages_7_1`.
   `flake.nix` `mkHost` imports this module only for `latestKernelRoles =
   [ "desktop" "stateless" ]` (LTS-track roles already sit at 6.12).

So `legacy_580` on 7.2 was a known gap, worked around with a pin, and the pin
target has now been garbage-collected.

### Prior interim fix (this branch, not committed)

`modules/gpu/nvidia-legacy-kernel.nix` currently repins `linuxPackages_7_1` →
`linuxPackages_6_12` (verified: evaluates clean, `drvPath` resolves). This
unblocks CI but moves desktop/stateless legacy_580 hosts onto the LTS kernel —
the opposite of what this role wants. **This spec supersedes that**: the repin
should be reverted and the pin module deleted once the patch route builds.

### Affected files

| File | Role |
|------|------|
| `modules/gpu/nvidia.nix` | driver package selection; where the patch attaches |
| `modules/gpu/nvidia-legacy-kernel.nix` | the kernel pin — to be **deleted** |
| `flake.nix` (`mkHost`, ~L349–370) | `latestKernelRoles` plumbing that imports the pin — to be **removed** |
| `modules/system-custom-kernel.nix` (comments, ~L18–31) | priority-ladder doc references the pin |
| `pkgs/` | candidate home for a vendored patch file (option B below) |

---

## 2. Problem definition

NVIDIA 580.173.02 closed kernel modules fail to compile on Linux 7.2 because
7.2 removed `strncpy()` from the kernel-space string API (Phoronix: "Linux 7.2
Drops strncpy", 360+ commits). 580.173.02's `kernel/nvidia/os-interface.c` and
four sibling files still call it → implicit-declaration build error.

**Goal (verifiable):** `nix eval` + `nixos-rebuild dry-build` for
`vexos-desktop-nvidia-legacy580` succeed with the host on `linuxPackages_latest`
(7.2.x), the kernel-module derivation for 580.173.02 builds, and
`modules/gpu/nvidia-legacy-kernel.nix` no longer exists.

---

## 3. Open question — must be resolved by a build test

Does 580.173.02 need **only** the `strncpy` → `strscpy` change, or **also** the
Linux 7.2 `drm_atomic_state` → `drm_atomic_commit` rename (kernel TODO item that
appears to have landed in 7.2)?

| Evidence | Points to |
|----------|-----------|
| CachyOS `7.2/misc/nvidia/0001` patch (used for `"latest"`) does **both** | needs both |
| babiulep `my-kernel-patches/NVIDIA/7.2/610.43.02` ships **two** patches (`strncpy_removed.patch` + `drm_atomic_state-to-commit.patch`) | needs both |
| Community reports (rglinuxtech comments, Linux Mint forum) for **580 specifically**: "you only need `strncpy_removed.patch`" | strncpy only |
| `nvidia-drm` is built in this config (`modesetting.enable = true`) so a real DRM API break would bite | needs both |

Plausible reconciliation: 580.173.02's older `nvidia-drm` does not touch the
renamed helpers, or 7.2 keeps compat aliases. **Unverified.** The 610 DRM patch
is heavily version-specific (references `nvidia-drm-color-pipeline.c`, colorops,
HDR paths that 580.173.02 likely lacks) — it will **not** apply cleanly to 580.

**Plan:** implement the `strncpy` fix first, build the module against 7.2. If it
compiles → done. If `nvidia-drm` fails on `drm_atomic_*` → fall back (section 6).

---

## 4. Proposed solution

### 4.1 The patch content (5 call sites, all in `kernel/`)

From babiulep `strncpy_removed.patch` (verified against 610.43.02; the same call
sites exist in 580.173.02's tree). Not a blind `s/strncpy/strscpy/` — the two
wrapper functions return `dest`, `strscpy` does not:

| File | Change |
|------|--------|
| `kernel/nvidia/os-interface.c` | `os_get_current_process_name`: `strncpy(buf, current->comm, len-1)` → `strscpy(...)` |
| `kernel/nvidia/linux_nvswitch.c` | `nvswitch_os_read_registry_dword`: call → `strscpy`; `nvswitch_os_strncpy` wrapper: `return strncpy(d,s,n)` → `strscpy(d,s,n); return d;` |
| `kernel/nvidia-modeset/nvidia-modeset-linux.c` | `nvkms_strncpy` wrapper: `return strncpy(...)` → `strscpy(...); return dest;` |
| `kernel/nvidia-uvm/uvm_pmm_gpu.c` | `init_chunk_split_cache_level`: call → `strscpy` |

`strscpy` has existed since Linux 4.3, so the patched driver still builds on
6.12 — safe for any kernel this repo ships.

### 4.2 Sourcing — pick one (recommend **B**)

**A. `fetchpatch` from babiulep, commit-pinned** — mirrors the existing
`kernel_7_2_patch` style exactly.
```nix
kernel_7_2_strncpy_patch = pkgs.fetchpatch {
  url = "https://github.com/babiulep/my-kernel-patches/raw/<commit>/NVIDIA/7.2/610.43.02/strncpy_removed.patch";
  hash = "...";
  stripLen = 1;              # patch paths are nvidia/…, driver tree is kernel/nvidia/…
  extraPrefix = "kernel/";   # same idiom nixpkgs uses for gpl_symbols_linux_615_patch
};
```
- ✔ consistent with current code · ✔ zero patch text in-repo
- ✘ new external dependency on a personal repo (`babiulep`); CLAUDE.md Context7
  policy — third-party patch source, pin to an immutable commit, document why
- ✘ patch authored for 610.43.02; context lines around the 5 hunks are identical
  in 580.173.02 (verified from NVIDIA 580 source layout) but this is a soft risk

**B. Vendored patch file in-repo** — `pkgs/nvidia-580-kernel-7.2/strncpy.patch`,
referenced as a local path. ~40 lines. Adapt the 5 hunks to 580.173.02's exact
context (fetch the 580.173.02 `.run`, extract, diff).
- ✔ no external dependency, fully reproducible, reviewable in PR
- ✔ context guaranteed correct for our exact driver version
- ✘ we now maintain a kernel patch (small, mechanical, pinned driver version →
  effectively frozen)

**C. `postPatch` `substituteInPlace`** in `nvidia.nix` — no patch file at all,
~4 targeted string replacements.
- ✔ smallest diff · ✘ the two `return strncpy(...)` wrappers need a 2-line
  rewrite each, not a substitution → doesn't fit `substituteInPlace` cleanly
- Rejected.

### 4.3 Wiring (in `modules/gpu/nvidia.nix`)

Attach to the closed package the same way `"latest"` attaches to `.open`:

```nix
legacy580 = config.boot.kernelPackages.nvidiaPackages.legacy_580;
...
driverPackage =
  if variant == "latest" then
    stable // { open = stable.open.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ kernel_7_2_patch ]; }); }
  else
    legacy580.overrideAttrs (old: {
      patches = (old.patches or []) ++ [ kernel_7_2_strncpy_patch ];
    });
```

`generic.nix` applies `patches` to the main package src; the closed `.mod`
consumes the already-patched tree (`patches = []` on `.mod`, build files
"already patched when building the main package"). Confirmed by reading
`nixpkgs/pkgs/os-specific/linux/nvidia-x11/generic.nix`.

Add a `# REMOVE once nixpkgs ships a 580.x build for 7.2` comment, matching the
existing one on `kernel_7_2_patch`. Both patches fail loudly at patch time if
the driver moves under them.

### 4.4 Remove the pin

1. **Delete** `modules/gpu/nvidia-legacy-kernel.nix`.
2. **`flake.nix` `mkHost`:** drop `latestKernelRoles` and the
   `lib.optional (nvidiaVariant == "legacy_580" && …) ./modules/gpu/nvidia-legacy-kernel.nix`.
   `legacyExtra` collapses back to `imports = [ ./modules/gpu/nvidia.nix ]`.
3. **`modules/gpu/nvidia.nix`** option doc: replace the "Hosts on this variant
   are pinned to Linux 7.1" paragraph with a note that 580.x is patched for 7.2.
4. **`modules/system-custom-kernel.nix`** priority-ladder comment: remove the
   `95 mkOverride modules/gpu/nvidia-legacy-kernel.nix` row and the two
   sentences about "the 7.1/6.12 pin that variant needs".
5. Revert the interim `linuxPackages_6_12` edit (moot — file is deleted).

Net: `legacy_580` behaves like every other variant — role import list decides
the kernel, no special-casing in `mkHost`.

---

## 5. Module Architecture Pattern compliance

- No new `lib.mkIf` guards in shared modules. The `if variant == …` in
  `nvidia.nix` is the module's own already-declared option
  (`vexos.gpu.nvidiaDriverVariant`) selecting a package — the standard carve-out,
  identical to the existing `"latest"` branch.
- **Deletes** special-casing (`latestKernelRoles`) rather than adding any —
  net reduction in role-smuggling logic in `mkHost`.
- No role-addition file needed; the change is entirely within the GPU module
  that already owns this option.

---

## 6. Fallback if the DRM rename also bites 580.173.02

If the build test shows `nvidia-drm` failing on `drm_atomic_state`:

- **6a (preferred):** vendor a second patch (`drm_atomic.patch`) adapted to
  580.173.02's `nvidia-drm/` — smaller than 610's since 580 lacks the colorop
  files. Same wiring (append to `patches`).
- **6b (fallback):** keep `modules/gpu/nvidia-legacy-kernel.nix` but change its
  target to `linuxPackages_6_12` (LTS, in-tree, 580 builds there today) and
  reword it as a deliberate LTS choice for this variant, not a stopgap. Accept
  that desktop/stateless legacy_580 run 6.12. Still deletes nothing but changes
  the framing; CI goes green immediately. **This is the interim edit already in
  the tree** — 6b = "stop here, keep what's committed locally".

Decision on 6a vs 6b is the user's — it's a maintenance-burden vs
kernel-currency tradeoff for hardware (Maxwell/Pascal/Volta) that is already EOL
upstream at NVIDIA.

---

## 7. Dependencies

- No new flake inputs.
- Option A adds a `fetchpatch` from `github.com/babiulep/my-kernel-patches`
  (third-party personal repo) pinned to an immutable commit hash. Option B adds
  no external fetch. Per CLAUDE.md dependency policy this is a patch source, not
  a library — Context7 N/A; the mitigation is commit-pinning + a code comment
  explaining provenance and removal condition.
- `strscpy` kernel API: present since Linux 4.3 (2015) — no lower-bound risk.

---

## 8. Risks & mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| DRM atomic rename also breaks 580.173.02 | medium | build test before merge; fallback §6 |
| babiulep patch context mismatch vs 580.173.02 (option A) | low–med | use option B (vendored, exact context) |
| `overrideAttrs` on `patches` doesn't reach the closed `.mod` | low | verified via generic.nix read; build test confirms |
| Future `flake.lock` bump moves 580.173.02 → newer 580.x | low | patch `fetchpatch`/vendored patch fails loudly at patch phase; version is effectively frozen (last 580 branch) |
| nixpkgs later adds its own 7.2 patch for `legacy_580` | low | our append is idempotent-ish; `REMOVE once…` comment flags it |
| CI `evaluate (desktop)` still only *evaluates* (`nix eval` drvPath), doesn't *build* the module | certain | evaluation catches the removed-attr class of failure; a compile failure needs `dry-build` (Phase 3 step) or an actual build — add a build of the driver `.mod` to the test plan |

---

## 9. Implementation steps

1. Fetch NVIDIA 580.173.02 `.run`, extract `kernel/`, confirm the 5 `strncpy`
   call sites match the babiulep hunks → verify: `grep -n strncpy` on the tree.
2. Create the patch (option B: `pkgs/nvidia-580-kernel-7.2/strncpy.patch`).
3. `modules/gpu/nvidia.nix`: add `kernel_7_2_strncpy_patch`, attach to the
   `legacy_580` branch via `overrideAttrs`; update the option doc string.
   → verify: `nix eval .#nixosConfigurations.vexos-desktop-nvidia-legacy580.config.system.build.toplevel.drvPath`
3. Build the module against 7.2:
   `nix build .#nixosConfigurations.vexos-desktop-nvidia-legacy580.config.hardware.nvidia.package.out`
   (or the `.mod`) → verify: exits 0, `.ko` files produced.
4. Delete `modules/gpu/nvidia-legacy-kernel.nix`; strip `latestKernelRoles` from
   `flake.nix`; fix `modules/system-custom-kernel.nix` comments.
   → verify: `nix flake show --impure` lists all 30 outputs; grep shows no
   remaining reference to `nvidia-legacy-kernel`.
5. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia-legacy580` on a
   NixOS host (user-run) → verify: closure builds.
6. Phase 3 review → Phase 6 `scripts/preflight.sh`.

---

## 10. Recommendation

Proceed with **option B** (vendored patch), `strncpy`-only first, with a build
test gating the pin removal. If the DRM rename also bites, take **§6b** (keep a
deliberate `linuxPackages_6_12` pin for this variant) unless you specifically
want to carry a second DRM patch (§6a) for EOL hardware.

---

## 11. Decisions (user, 2026-09-09)

- **Patch source:** option B — vendored file, committed to the repo.
- **Route:** patch `legacy_580` for `linuxPackages_latest` (keep desktop/stateless
  on the newest kernel). Not the LTS-pin route.
- **DRM fallback:** not needed. Build test (2026-09-09):
  `nix build` of `linuxPackages_latest.nvidiaPackages.legacy_580` (7.2.4) with
  only `kernel_7_2_strncpy_patch` produced
  `nvidia-kernel-modules-580.173.02-7.2.4` with all five `.ko`s, **including
  `nvidia-drm.ko`** — the 7.2 `drm_atomic_state`→`drm_atomic_commit` rename does
  not affect 580.173.02. `strncpy`-only is sufficient; §6 is moot.
- **If §6b is ever taken:** the fallback kernel is **`linuxPackages_6_18`** — the
  current latest LTS (Greg KH, supported to Dec 2027+, extended to 2028), *not*
  6.12. 580.173.02 builds unpatched on any kernel < 7.2, so 6.18 needs no patch.
  (Pre-existing: `modules/system-lts-kernel.nix` still pins `linuxPackages_6_12`
  for the LTS-track roles — a separate question, out of scope here.)

### Implementation as built

- `modules/gpu/nvidia-580-kernel-7.2-strncpy.patch` — new, vendored; `patch -p1
  --dry-run` clean against the 580.173.02 tree.
- `modules/gpu/nvidia.nix` — `kernel_7_2_strncpy_patch` binding + `legacy580`
  alias; `driverPackage` legacy branch now `legacy580.overrideAttrs` appending
  the patch; option doc updated.
- `flake.nix` `mkHost` — `latestKernelRoles` and the conditional
  `nvidia-legacy-kernel.nix` import removed; `legacyExtra` back to a plain
  `imports = [ ./modules/gpu/nvidia.nix ]`.
- `modules/gpu/nvidia-legacy-kernel.nix` — **deleted**.
- `modules/system-custom-kernel.nix` — priority-ladder comment de-references the
  removed pin module.
