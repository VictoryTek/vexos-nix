# kiji-proxy fakeHash Guard — Specification

**Feature:** `kiji_proxy_fakehash`  
**Status:** Ready for implementation  
**Severity:** Quality / Latent footgun (not a current CI failure)  
**Files Affected:** `pkgs/default.nix`, `modules/server/kiji-proxy.nix`

---

## 1. Current State Analysis

### 1.1 Overlay Structure

`pkgs/default.nix` is a single Nix overlay that exposes all custom packages under the
`pkgs.vexos` namespace.  `kiji-proxy` is listed unconditionally alongside the other
packages:

```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };
    kiji-proxy           = final.callPackage ./kiji-proxy { };   # ← always present
    portbook             = final.callPackage ./portbook { };
  };
}
```

### 1.2 The fakeHash

`pkgs/kiji-proxy/default.nix` uses `lib.fakeHash` as the source hash:

```nix
src = fetchurl {
  url  = "https://github.com/dataiku/kiji-proxy/releases/download/v${version}/...";
  hash = lib.fakeHash;   # ← placeholder
};
```

`lib.fakeHash` evaluates to the string `"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="`.
This is a syntactically valid SRI hash string, so:

- Nix **can evaluate** the derivation (produces a `.drv` without error).
- Nix **cannot build** the derivation: the hash will never match the real tarball.
  Failure occurs at fetch time with `hash mismatch in fixed-output derivation`.

### 1.3 The `just enable kiji-proxy` Workflow

When `just enable kiji-proxy` is run:

1. It detects `lib.fakeHash` via `grep -q 'lib\.fakeHash'` in the package file.
2. Fetches the real tarball with `nix-prefetch-url --unpack`.
3. Converts the base-32 hash to SRI format with `nix hash to-sri`.
4. Replaces `lib.fakeHash` in the file with the real SRI hash via `sed -i`.

This workflow mutates a tracked file in the repository.  The operator must commit
(or leave dirty) the result.

### 1.4 The NixOS Module Guard

`modules/server/kiji-proxy.nix` guards all package references behind `lib.mkIf cfg.enable`:

```nix
config = lib.mkIf cfg.enable {
  systemd.services.kiji-proxy = {
    serviceConfig.ExecStart = "${pkgs.vexos.kiji-proxy}/bin/kiji-proxy";
    ...
  };
};
```

No current `nixosConfiguration` (or tracked `server-services.nix`) sets
`vexos.server.kiji-proxy.enable = true`.

### 1.5 Flake Outputs

The flake exposes only:

- `nixosConfigurations.*` (34 outputs)
- `nixosModules.*` (role/gpu modules)

It does **not** expose `packages.*` or `legacyPackages.*` outputs.  This is critical:
`nix flake check` only evaluates the listed outputs.  Since no packages output exists,
the overlay packages are never enumerated directly by flake check.

---

## 2. Problem Definition

### 2.1 Is `nix flake check --impure` Currently Failing?

**No.**  Confirmed by:

- Prior terminal run: `nix flake check --impure 2>&1; echo "EXIT:$?"` → EXIT:0
- All `nixos-rebuild dry-build` variants pass (desktop-amd, desktop-nvidia, desktop-vm,
  stateless-amd)
- The grep `nix flake check --impure 2>&1 | grep -i kiji` returns **NOT EVALUATED**
  (kiji-proxy never appears in flake check output)

**Reason:** Nix's lazy evaluation means `pkgs.vexos.kiji-proxy` is only forced when
something in a system closure references it.  Because `lib.mkIf cfg.enable` is false
for all 34 outputs, the derivation is never forced.  The fakeHash string evaluates
without error; only the actual download would fail.

### 2.2 What Is the Actual Risk?

The risk is **latent, not active**.  It is triggered by exactly one operator action:

> Adding `vexos.server.kiji-proxy.enable = true` to `server-services.nix` and running
> `nixos-rebuild switch` **without** first running `just enable kiji-proxy`.

In that scenario:
- `nixos-rebuild` evaluates the closure → `pkgs.vexos.kiji-proxy` is reached
- Nix attempts to fetch the tarball
- Fetch fails: `hash mismatch: expected sha256-AAAA... got sha256-<real>`
- The build aborts with a confusing error that does not mention fakeHash or `just enable`

### 2.3 Why Is This Worth Fixing?

1. **Silent ambiguity in the overlay:** `pkgs.vexos` implies "ready to use".  Including
   `kiji-proxy` there with a fakeHash violates that contract.  Any future tooling that
   iterates `pkgs.vexos` (e.g. a CI job that builds all custom packages) would fail.

2. **Error UX:** A fetch-time hash mismatch is a confusing failure mode.  Operators are
   unlikely to trace it back to `lib.fakeHash` without reading the source.

3. **No structural signal:** Nothing in the overlay or module hierarchy tells a reader
   that `kiji-proxy` needs an extra setup step before it can be used.  The comment in
   `pkgs/kiji-proxy/default.nix` is the only indication — it is not visible from the
   call site in `pkgs/default.nix`.

---

## 3. Approaches Considered

### Approach A — Do Nothing (status quo)
Keep `lib.fakeHash` in the package, rely on `lib.mkIf cfg.enable` to prevent
evaluation in normal use.

**Verdict:** Acceptable today, but fragile.  No structural protection exists against
accidentally enabling the service, and no protection exists against future tooling that
enumerates overlay packages.

### Approach B — `meta.broken = true`
Mark the package permanently broken in its `meta` block.

**Verdict:** Rejected.  `meta.broken` causes `nix build` to refuse without `--impure
--allow-broken`.  After `just enable kiji-proxy` sets the real hash, the operator
would also need to remove `meta.broken` — the current `sed` in the justfile only
replaces one pattern.  This couples two concerns.

### Approach C — Replace `lib.fakeHash` with `lib.throw`
```nix
hash = lib.throw "kiji-proxy: run 'just enable kiji-proxy' to set the hash";
```

**Verdict:** Rejected.  `lib.throw` evaluates eagerly at attribute-access time (when
Nix forces the `src` attr).  If any evaluation context touches `pkgs.vexos.kiji-proxy`
— even to inspect its `meta` — it will throw.  This **could break `nix flake check`**
if the evaluation context visits overlay attributes.  The risk-vs-benefit is worse than
the status quo.

### Approach D — Sub-namespace isolation (`pkgs.vexos.optional.*`) ✅ RECOMMENDED
Move `kiji-proxy` from the `vexos` top-level set into a `vexos.optional` sub-namespace.
Update the module reference accordingly.

```nix
# pkgs/default.nix (after)
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };
    portbook             = final.callPackage ./portbook { };

    # Packages in `optional` require operator setup before use.
    # See the individual package file for instructions.
    optional = (prev.vexos.optional or { }) // {
      kiji-proxy = final.callPackage ./kiji-proxy { };
    };
  };
}
```

```nix
# modules/server/kiji-proxy.nix (after) — one-line change
ExecStart = "${pkgs.vexos.optional.kiji-proxy}/bin/kiji-proxy";
```

**Verdict:** RECOMMENDED.  See §4 for full rationale.

### Approach E — Store hash in a separate file / flake input
Move the hash out of the package `.nix` file into a separate `kiji-proxy-hash.nix`
or a flake input that `just enable` updates.

**Verdict:** Disproportionate complexity for this use case.  Approach D achieves the
goal with two files and three changed lines.

---

## 4. Recommended Solution — Approach D

### 4.1 Rationale

| Criterion | Approach D |
|-----------|-----------|
| Does NOT break `nix flake check --impure` | ✓ (lazy evaluation unchanged) |
| Makes "needs setup" intent structurally visible | ✓ (`optional` sub-namespace) |
| Does NOT change `just enable kiji-proxy` | ✓ (sed target path unchanged) |
| Does NOT change operator UX when service IS enabled | ✓ (module works identically) |
| Minimal diff | ✓ (2 files, ≤ 6 lines changed) |
| Extensible | ✓ (future opt-in packages can go in `optional` too) |
| No new dependencies | ✓ |

### 4.2 Semantic Contract

After this change:

- `pkgs.vexos.*` = packages that are **ready to use** in any nixosConfiguration.
- `pkgs.vexos.optional.*` = packages that **require operator initialization** before use.

The distinction is signalled by namespace position, not by code guards.  Any reader of
`pkgs/default.nix` immediately sees which packages are unconditional and which need setup.

### 4.3 Lazy Evaluation Safety

Moving `kiji-proxy` into a sub-attribute `vexos.optional.kiji-proxy` does not change
when the derivation is forced.  Nix only evaluates `pkgs.vexos.optional.kiji-proxy`
when something in a closure actually references it — which only happens when the module
is enabled (as before).  `nix flake check` is unaffected.

---

## 5. Implementation Steps

### Step 1 — `pkgs/default.nix`

Replace the existing `kiji-proxy` line with an `optional` sub-attribute set.

**Before:**
```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
    # ── AI & Privacy ────────────────────────────────────────────────────────
    kiji-proxy           = final.callPackage ./kiji-proxy { };
    portbook             = final.callPackage ./portbook { };
  };
}
```

**After:**
```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator    = final.callPackage ./cockpit-navigator { };
    cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };
    cockpit-identities   = final.callPackage ./cockpit-identities { };  # Phase D
    portbook             = final.callPackage ./portbook { };
    # ── Packages requiring operator setup before use ─────────────────────────
    # Run `just enable <name>` to initialise each package before enabling
    # the corresponding NixOS option. See each package file for details.
    optional = (prev.vexos.optional or { }) // {
      kiji-proxy = final.callPackage ./kiji-proxy { };
    };
  };
}
```

### Step 2 — `modules/server/kiji-proxy.nix`

Update the single `ExecStart` line to reference the new namespace.

**Before:**
```nix
ExecStart = "${pkgs.vexos.kiji-proxy}/bin/kiji-proxy";
```

**After:**
```nix
ExecStart = "${pkgs.vexos.optional.kiji-proxy}/bin/kiji-proxy";
```

Also update the `LD_LIBRARY_PATH` line in the same `Environment` list:

**Before:**
```nix
Environment = [
  "LD_LIBRARY_PATH=${pkgs.vexos.kiji-proxy}/lib"
  "PROXY_PORT=:${toString cfg.port}"
];
```

**After:**
```nix
Environment = [
  "LD_LIBRARY_PATH=${pkgs.vexos.optional.kiji-proxy}/lib"
  "PROXY_PORT=:${toString cfg.port}"
];
```

### Step 3 — No other files require changes

- `pkgs/kiji-proxy/default.nix` — unchanged (fakeHash stays; `just enable` sed target
  is the same file, same pattern)
- `justfile` — unchanged (the `enable kiji-proxy` recipe works on the package file
  path, which is unaffected by the overlay namespace change)
- `flake.nix` — unchanged
- All `configuration-*.nix` and `hosts/*.nix` files — unchanged

---

## 6. Validation Checklist

After implementation:

- [ ] `nix flake check --impure` exits 0 and produces no kiji-related errors
- [ ] `nix build --dry-run --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel`
      exits 0
- [ ] `nix build --dry-run --impure .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel`
      exits 0 (server role with kiji-proxy disabled — the common case)
- [ ] `grep -r 'vexos\.kiji-proxy' modules/` returns no matches
- [ ] `grep -r 'vexos\.optional\.kiji-proxy' modules/` matches exactly the two lines
      in `modules/server/kiji-proxy.nix`
- [ ] `bash scripts/preflight.sh` exits 0

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|-----------|
| A future overlay consumer iterates `pkgs.vexos` and hits `optional` | Low | `optional` is an attrset, not a derivation; iteration would need to be recursive to reach it |
| `just enable kiji-proxy` stops working after rename | None | The recipe operates on the file path, not the overlay key; nothing changes |
| Other code references `pkgs.vexos.kiji-proxy` directly | None | Confirmed by `grep -r 'vexos\.kiji-proxy'` — only `modules/server/kiji-proxy.nix` references it |
| The `optional` key collides with a future nixpkgs attribute | None | `pkgs.vexos` is a private namespace; `optional` is not a nixpkgs builtin under `pkgs` |

---

## 8. Out of Scope

The following are intentionally excluded from this change:

- Removing `lib.fakeHash` or pinning a real hash (that is the operator's job via
  `just enable kiji-proxy`; automating it in CI would require network access and a
  ~150 MB download)
- Changing the `just enable kiji-proxy` sed mechanism
- Adding `meta.broken` or any build-time assertion that would interfere with dry-run
  evaluation
- Any change to `pkgs/kiji-proxy/default.nix` itself

---

## 9. References

1. **NixOS Manual — `lib.fakeHash`**: https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-fetchers
   — Documents fakeHash as the standard placeholder when a hash is not yet known.
   The correct pattern is to run `nix build` once, let it fail, then copy the
   suggested hash from the error output into the expression.

2. **nixpkgs `requireFile`**: https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-requireFile
   — The canonical NixOS pattern for packages that cannot be downloaded automatically.
   Not applicable here (download is public), but referenced for contrast.

3. **NixOS Discourse — "placeholder hash workflow"**:
   https://discourse.nixos.org/t/is-there-a-way-to-get-a-hash-for-a-fetchurl-without-downloading-it/
   — Community confirmation that lib.fakeHash is the standard approach for
   placeholder hashes in iterative development.

4. **Nix lazy evaluation semantics**: https://nixos.wiki/wiki/Nix_Expression_Language#Lazy_evaluation
   — Explains why attributes in an overlay are not evaluated unless they are
   referenced in a forced expression, which is why fakeHash does not break
   `nix flake check` for unused packages.

5. **nixpkgs overlay best practices**: https://nixos.wiki/wiki/Overlays
   — Recommends namespacing custom packages to avoid collisions; the
   `vexos.optional` sub-namespace follows this convention.

6. **NixOS `lib.mkIf` evaluation**: https://nixos.org/manual/nixpkgs/stable/#sec-option-definitions-mkIf
   — Confirms that `lib.mkIf false { ... }` prevents the enclosed attrset from
   being merged into config, which is why no kiji-proxy reference reaches the
   system closure when `enable = false`.
