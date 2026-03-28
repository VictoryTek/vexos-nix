# Garnix Cache Migration — Specification

**Feature:** `garnix_cache_migration`  
**Date:** 2026-03-28  
**Status:** Draft — awaiting implementation

---

## 1. Current State Analysis

Cache-related configuration exists in **four files**. Every occurrence is
documented below with exact line numbers and content.

---

### 1.1 `flake.nix` — Build-time `nixConfig` (lines 2–13)

**Scope:** Build-time only. These entries are honoured by the Nix CLI when a
user runs `nixos-rebuild switch --flake .#` (the `--accept-flake-config` flag,
or a prompt, is required the first time). They are **additive** (`extra-*`)
and do **not** replace NixOS defaults.

```nix
nixConfig = {
  extra-substituters = [
    "https://attic.xuyh0120.win/lantian"     # CachyOS kernel — primary Hydra CI cache
    "https://cache.garnix.io"               # Garnix CI — already present ✓
    "https://vex-kernels.cachix.org"        # ⚠ CACHIX: Bazzite/vex-kernels kernel cache
  ];
  extra-trusted-public-keys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="  # ⚠ CACHIX
  ];
};
```

**Cachix references:**
- `https://vex-kernels.cachix.org` — substituter
- `vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck=` — public key

---

### 1.2 `configuration.nix` — Runtime `nix.settings` (lines 47–92)

**Scope:** Deployed system runtime. Controls all `nix` invocations on the
installed NixOS system. Uses `substituters` (not `extra-substituters`), which
**replaces** the NixOS default list — `cache.nixos.org` must therefore be
listed explicitly.

```nix
nix.settings = {
  experimental-features = [ "nix-command" "flakes" ];
  auto-optimise-store = true;

  substituters = [
    "https://cache.nixos.org"
    "https://nix-gaming.cachix.org"           # ⚠ CACHIX: nix-gaming packages
    # CachyOS kernel binary caches (xddxdd/nix-cachyos-kernel)
    "https://attic.xuyh0120.win/lantian"      # Primary: Hydra CI-backed
    "https://cache.garnix.io"                 # Garnix CI — already present ✓
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="  # ⚠ CACHIX
    # CachyOS kernel binary caches
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="           # already present ✓
  ];
  # ... (other performance / GC settings follow — not cache-related)
};
```

**Cachix references:**
- `https://nix-gaming.cachix.org` — substituter
- `nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4=` — public key

---

### 1.3 `hosts/vm.nix` — VM runtime `nix.settings` (lines 63–74)

**Scope:** Deployed VM system runtime. Appended after `configuration.nix`'s
`nix.settings` block via NixOS option merging. Adds the vex-kernels Cachix cache
for subsequent `nix` invocations on the running VM.

```nix
# Cachix binary cache for vex-kernels (bazzite kernel) — deployed system runtime.
# Build-time cache is handled via nixConfig in flake.nix.
nix.settings = {
  substituters = [
    "https://vex-kernels.cachix.org"        # ⚠ CACHIX: Bazzite/vex-kernels kernel
  ];
  trusted-public-keys = [
    "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="  # ⚠ CACHIX
  ];
};
```

**Cachix references:**
- `https://vex-kernels.cachix.org` — substituter
- `vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck=` — public key

---

### 1.4 `template/etc-nixos-flake.nix` — Template `nixConfig` (lines 52–61)

**Scope:** Deployment template for end users at `/etc/nixos/flake.nix`. Already
clean — no Cachix references.

```nix
nixConfig = {
  extra-substituters = [
    "https://attic.xuyh0120.win/lantian"
    "https://cache.garnix.io"             # ✓ already Garnix-only
  ];
  extra-trusted-public-keys = [
    "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
  ];
};
```

**Action required:** None — already migrated.

---

### 1.5 `flake.lock` — Indirect `cachix` mentions (lines 115, 121)

These reference the GitHub repository `cachix/git-hooks.nix`, which is a
transitive dependency of `nix-gaming.nixosModules.pipewireLowLatency`. This is
a **source code input**, not a binary cache endpoint. It is **not affected**
by this migration.

---

## 2. Problem Definition

### 2.1 Scope of Cachix references

| File | Cachix cache(s) present | Type |
|------|------------------------|------|
| `flake.nix` | `vex-kernels.cachix.org` | Build-time |
| `configuration.nix` | `nix-gaming.cachix.org` | Runtime |
| `hosts/vm.nix` | `vex-kernels.cachix.org` | VM runtime |
| `template/etc-nixos-flake.nix` | — none — | N/A |

### 2.2 Why migrate

The user has requested a clean migration to Garnix as the sole third-party
binary cache. The desired end state is:

```nix
nix.settings = {
  substituters = [ "https://cache.garnix.io" ];
  trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
};
```

This simplifies the cache stack, removes the Cachix dependency, and reduces
the number of untrusted third-party infrastructure endpoints.

---

## 3. Design Decisions

### 3.1 `substituters` — Replace or append to defaults?

**Decision: Replace, but always include `cache.nixos.org` first.**

When using `nix.settings.substituters` (without the `extra-` prefix), the list
**replaces** the NixOS default (`cache.nixos.org`). Omitting it would break
all official NixOS package builds and updates on the deployed system. The user's
requested config snippet (`substituters = [ "https://cache.garnix.io" ]`) is
**incomplete as-is** — it must include `cache.nixos.org`.

The correct safe form is:

```nix
substituters = [
  "https://cache.nixos.org"  # REQUIRED: official NixOS packages
  "https://cache.garnix.io"
];
```

Similarly, `trusted-public-keys` must include the `cache.nixos.org` key:

```nix
trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
];
```

### 3.2 `attic.xuyh0120.win/lantian` (CachyOS kernel cache) — Keep or remove?

**Decision: Remove from `configuration.nix` runtime. Keep in `flake.nix`
build-time nixConfig.**

Rationale:
- The CachyOS kernel (`nix-cachyos-kernel` input) is used at build time to
  assemble the NixOS system closure. The Attic/Lantian cache provides pre-built
  CachyOS kernel binaries. Removing it from the build-time nixConfig would
  force a local kernel compile, which is extremely expensive (multiple hours).
- However, the Attic/Lantian URL is a third-party server that is unrelated to
  Cachix. It is already present in `template/etc-nixos-flake.nix` without any
  Cachix tie-in.
- The user's migration goal is specifically "from Cachix to Garnix", not "remove
  all third-party caches". The Attic cache is not Cachix.
- **`configuration.nix` runtime**: Remove — the deployed system's runtime Nix
  only needs `cache.nixos.org` + `cache.garnix.io` for day-to-day operations.
  CachyOS/Attic binaries are needed at build time, not runtime.
- **`flake.nix` nixConfig**: Keep `attic.xuyh0120.win/lantian` — it is a
  non-Cachix build-time necessity.

### 3.3 `nix-gaming.cachix.org` — Remove?

**Decision: Remove. Accept the local-build risk; document it.**

The `nix-gaming` input provides `nix-gaming.nixosModules.pipewireLowLatency`.
Its Cachix cache (`nix-gaming.cachix.org`) provides pre-built binaries for
nix-gaming packages. Without it, PipeWire low-latency packages that are not in
`cache.nixos.org` or `cache.garnix.io` will be built locally.

Risk level: **MEDIUM** — PipeWire packages are relatively small; a one-time
local compile is acceptable. After the initial build they are cached in the
local Nix store.

### 3.4 `vex-kernels.cachix.org` — Remove?

**Decision: Remove as a Cachix endpoint. Assess Garnix availability.**

The `vex-kernels.cachix.org` cache provides pre-built Bazzite kernel binaries
for `hosts/vm.nix`. Without it:
- Build-time: The kernel must be compiled locally (very expensive, ~1–2 hours).
- Runtime: The same compiled kernel is used, so runtime is unaffected after
  the initial build.

Risk level: **HIGH** for first build after cache removal, LOW thereafter.

Mitigation: The `kernel-bazzite` input (`github:VictoryTek/vex-kernels`) is
from VictoryTek's own repository. If VictoryTek adds their own Garnix cache in
the future, the key would be `cache.garnix.io` (already configured). For now,
removing `vex-kernels.cachix.org` trades one-time local build cost for a
cleaner, Cachix-free configuration.

### 3.5 Best single location for the cache configuration

**Decision: `configuration.nix` remains the authoritative location for runtime
`nix.settings`.**

All variants (`vexos-amd`, `vexos-nvidia`, `vexos-intel`, `vexos-vm`) import
`configuration.nix`. Adding the cache config there means all variants inherit
it automatically without duplication. This is the existing pattern and should
be preserved.

No dedicated cache module is warranted — the block is small and already lives
in `configuration.nix`. Creating a separate `modules/cache.nix` would be
over-engineering for this scope.

The `hosts/vm.nix` override block (`nix.settings` with `vex-kernels.cachix.org`)
should be **removed entirely** — it was only needed for the Cachix endpoint.

---

## 4. Proposed Solution — Exact Changes

### 4.1 `configuration.nix` — Replace `substituters` and `trusted-public-keys`

**Current (lines 54–67):**
```nix
    # Binary caches — fetch pre-built derivations instead of compiling locally
    substituters = [
      "https://cache.nixos.org"
      "https://nix-gaming.cachix.org"
      # CachyOS kernel binary caches (xddxdd/nix-cachyos-kernel)
      "https://attic.xuyh0120.win/lantian"  # Primary: Hydra CI-backed
      "https://cache.garnix.io"             # Fallback: Garnix CI
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      # CachyOS kernel binary caches
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
```

**New (replacement):**
```nix
    # Binary caches — fetch pre-built derivations instead of compiling locally
    substituters = [
      "https://cache.nixos.org"   # Official NixOS cache — always required
      "https://cache.garnix.io"   # Garnix CI cache
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
```

**Change summary:**
- Remove: `https://nix-gaming.cachix.org` + its key
- Remove: `https://attic.xuyh0120.win/lantian` + its key (Attic, not Cachix, but
  not needed at runtime — CachyOS builds happen at build time, not after deploy)
- Keep: `https://cache.nixos.org` + its key (required)
- Keep: `https://cache.garnix.io` + its key

---

### 4.2 `flake.nix` — Remove `vex-kernels.cachix.org` from `nixConfig`

**Current (lines 2–13):**
```nix
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
      "https://vex-kernels.cachix.org"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="
    ];
  };
```

**New (replacement):**
```nix
  nixConfig = {
    extra-substituters = [
      "https://attic.xuyh0120.win/lantian"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };
```

**Change summary:**
- Remove: `https://vex-kernels.cachix.org` + its key
- Keep: `attic.xuyh0120.win/lantian` (needed at build time for CachyOS kernel)
- Keep: `cache.garnix.io` (already present)

---

### 4.3 `hosts/vm.nix` — Remove the entire Cachix `nix.settings` block

**Current (lines 63–74):**
```nix
  # Cachix binary cache for vex-kernels (bazzite kernel) — deployed system runtime.
  # Build-time cache is handled via nixConfig in flake.nix.
  nix.settings = {
    substituters = [
      "https://vex-kernels.cachix.org"
    ];
    trusted-public-keys = [
      "vex-kernels.cachix.org-1:V2rsF5p1U/J45nH+4uIJ45OlkWmqtv098pZSyq5ABck="
    ];
  };
```

**New:** Remove this entire block. No replacement needed — the Garnix cache
inherited from `configuration.nix` covers the deployed VM system.

The comment referencing "Cachix binary cache" on the build-time section
in the `hosts/vm.nix` header comment block (lines 22–23) should also be
updated to remove the Cachix reference:

**Current header comment (lines 22–23):**
```
# Cachix binary cache (vex-kernels.cachix.org) is configured here for the
# deployed VM system's runtime Nix. The build-time cache is in flake.nix nixConfig.
```

**New:** Remove these two comment lines.

---

### 4.4 `template/etc-nixos-flake.nix` — No changes required

Already clean: no Cachix references. Contains only `attic.xuyh0120.win/lantian`
and `cache.garnix.io`. No action.

---

## 5. Files Affected

| File | Action | Cachix entries removed |
|------|--------|----------------------|
| `configuration.nix` | Edit `nix.settings` block | `nix-gaming.cachix.org` (URL + key), `attic` URL+key |
| `flake.nix` | Edit `nixConfig` block | `vex-kernels.cachix.org` (URL + key) |
| `hosts/vm.nix` | Remove `nix.settings` block + 2 header comment lines | `vex-kernels.cachix.org` (URL + key) |
| `template/etc-nixos-flake.nix` | No changes | — |

---

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `nix-gaming` PipeWire packages not in Garnix cache — built locally | MEDIUM | One-time compile cost; acceptable. Result is cached in local Nix store. |
| Bazzite kernel (`vex-kernels`) not in Garnix cache — must build locally | HIGH | First build of `vexos-vm` after migration will compile the kernel locally (~1–2 hrs). Subsequent rebuilds use the local store or upstream source cache. Monitor if VictoryTek adds a Garnix cache. |
| CachyOS kernel (`attic.xuyh0120.win/lantian`) removed from runtime `nix.settings` | LOW | CachyOS binaries are only needed at build time. The Attic URL is retained in `flake.nix` nixConfig. Runtime Nix on the deployed system does not need it. |
| `cache.nixos.org` omitted from new config | CRITICAL | Avoided by spec: always include `cache.nixos.org` as the first `substituters` entry. |

---

## 7. Implementation Steps

1. **Edit `configuration.nix`**
   - Replace the `substituters` list (currently 4 entries) with 2 entries:
     `cache.nixos.org` and `cache.garnix.io`.
   - Replace the `trusted-public-keys` list (currently 4 entries) with 2 entries:
     `cache.nixos.org-1` and `cache.garnix.io`.
   - Update the inline comment from "Binary caches — fetch pre-built derivations ..."
     to reflect the simplified cache config.

2. **Edit `flake.nix`**
   - Remove `https://vex-kernels.cachix.org` from `extra-substituters`.
   - Remove `vex-kernels.cachix.org-1:...` from `extra-trusted-public-keys`.

3. **Edit `hosts/vm.nix`**
   - Remove the two-line comment block:
     `# Cachix binary cache for vex-kernels (bazzite kernel) — deployed system runtime.`
     `# Build-time cache is handled via nixConfig in flake.nix.`
   - Remove the entire `nix.settings { ... }` block that follows those comments.

4. **Validate**
   - Run `nix flake check --impure` — should pass (no Nix evaluation change).
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-amd` — verify no evaluation errors.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-nvidia` — same.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-vm` — same.  
     Note: dry-build for vm may attempt to fetch the Bazzite kernel; if the
     Cachix binary is no longer resolvable, it will fall back to local build or
     source. Dry-build does not execute the build, it only evaluates the
     derivation graph — so this step will still pass regardless.
   - Run `bash scripts/preflight.sh` — all checks must pass.

---

## 8. Dependencies

No new external library dependencies. This is a pure Nix configuration change.
Context7 verification is not required for this migration.

---

## 9. Out of Scope

- Removing the `attic.xuyh0120.win/lantian` build-time substituter — that is
  a non-Cachix third-party cache needed for CachyOS kernel binaries and is
  outside the "Cachix to Garnix" migration goal.
- Adding a dedicated VictoryTek Garnix cache — not currently available; may
  be revisited when/if `VictoryTek/vex-kernels` publishes to Garnix.
- Changing `nix-gaming` module integration — the PipeWire low-latency module
  is retained; only its Cachix binary cache reference is removed.
