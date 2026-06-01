# VSCode Overlay — Review

**Feature:** `vscode_overlay`
**Date:** 2026-05-31
**Phase:** 3 — Review & Quality Assurance
**Verdict:** NEEDS_REFINEMENT

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A |
| Best Practices | 88% | B+ |
| Functionality | 40% | F |
| Code Quality | 95% | A |
| Security | 95% | A |
| Performance | N/A | — |
| Consistency | 92% | A |
| Build Success | 0% | F |

**Overall Grade: D (63%)**  
*(Dragged down by Functionality and Build Success — the placeholder hash makes the overlay completely non-functional.)*

---

## 1. Nix Overlay Correctness (`overlays/vscode.nix`)

### 1.1 `final: prev:` pattern ✅
Correctly uses `final: prev: { ... }`.

### 1.2 `prev.vscode.overrideAttrs` usage ✅
Uses `prev.vscode.overrideAttrs (old: rec { ... })` as specified. The `rec`
enables `src.url` to interpolate the overridden `version` attribute in-place.

### 1.3 URL correctness ✅
```nix
url = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
```
Matches the spec exactly. `fetchurl` follows redirects via curl `-L`.

### 1.4 Comment header ✅
Thorough header block explains purpose, wiring, and manual update procedure.

### 1.5 `hash` attribute uses SRI format ✅
Uses `hash = "sha256-..."` (not the legacy `sha256 = "..."` field). Correct for
NixOS 24.05+.

### 1.6 `name` attribute on `fetchurl` ✅
Required because the URL path ends in `stable` (not `.tar.gz`). Without this
the Nix store path basename would be uninformative. Correctly set to
`"vscode-${version}-linux-x64.tar.gz"`.

### 1.7 `version` interpolation in URL ✅
`rec` binds `version` so `${version}` in `src.url` resolves to the overridden
value without any manual duplication.

### 1.8 CRITICAL — Placeholder hash ❌

```nix
hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```

This is **a well-known-invalid SRI hash**. Any build that attempts to fetch
VSCode 1.122.1 will immediately fail with:

```
error: hash mismatch in fixed-output derivation …
  specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
  got:       sha256-<real hash>
```

The placeholder is documented as a TODO in the overlay comment, and the
`just update-vscode` recipe exists to automate filling it in. However, the
implementation phase ran on Windows where `nix-prefetch-url` is unavailable
(terminal history: exit code 1). The hash was never obtained.

**The overlay cannot be used until the real hash is substituted.**

### 1.9 `vscode-fhs` propagation — verified correct ✅

The review prompt flagged this for investigation. Source evidence from
`pkgs/applications/editors/vscode/generic.nix` (nixpkgs upstream) confirms the
spec's assertion:

```nix
# generic.nix
stdenv.mkDerivation (finalAttrs: {
  ...
  passthru = {
    fhs = fhs { };   # fhs uses finalAttrs.finalPackage
    ...
  };
})
```

The `buildFHSEnv` call inside `passthru.fhs` captures
`finalAttrs.finalPackage`. Because `generic.nix` uses the modern
`stdenv.mkDerivation (finalAttrs: …)` pattern, `finalAttrs.finalPackage`
refers to the **final overridden derivation** — i.e., the result of our
`overrideAttrs` call. Therefore:

- `final.vscode` = our overridden derivation (version 1.122.1)
- `final.vscode.fhs` = FHS env wrapping the **overridden** vscode binary ✅
- `final.vscode-fhs` (defined as `vscode.fhs` in all-packages.nix via the
  fixed-point `self.vscode`) = same overridden FHS env ✅

Overriding `vscode` alone is sufficient; no separate `vscode-fhs` override
is needed.

---

## 2. `flake.nix` Wiring

### 2.1 Overlay applied to `nixpkgs-unstable` import ✅

Confirmed in `unstableOverlayModule`:
```nix
unstable = (import nixpkgs-unstable {
  inherit (final) config;
  inherit (final.stdenv.hostPlatform) system;
}).extend (import ./overlays/vscode.nix);
```

### 2.2 `.extend (import ./overlays/vscode.nix)` syntax ✅
Correct. `.extend` takes an overlay function; `import ./overlays/vscode.nix`
returns `final: prev: { … }`. This is equivalent to passing the overlay via the
`overlays = [ … ]` nixpkgs argument.

### 2.3 Applied in ALL instantiation sites ✅

There are **two** places in `flake.nix` where `nixpkgs-unstable` is imported:

| Location | Overlay applied? |
|----------|------------------|
| `unstableOverlayModule` (~line 50) | ✅ |
| `mkBaseModule` (~line 282) | ✅ |

Both sites have the identical `.extend (import ./overlays/vscode.nix)` call.
This was a critical requirement per the spec (§ 4.3) and was correctly
implemented.

### 2.4 No obvious syntax errors ✅

The flake file reads cleanly. No unclosed braces, mismatched `let`/`in`,
or dangling semicolons detected on visual inspection.

### 2.5 `vanilla` role excluded — no regression ✅

The `vanilla` role has `baseModules = []` so it never imports
`unstableOverlayModule`. It does not use `pkgs.unstable.*`, so this is
intentional and correct.

---

## 3. `justfile` Recipe (`update-vscode`)

### 3.1 Recipe exists ✅
`update-vscode version:` is present (line 683).

### 3.2 Accepts a `version` argument ✅
Positional argument `version`; validated with an empty-string guard.

### 3.3 Fetches hash via `nix-prefetch-url` ✅
```bash
RAW_HASH=$(nix-prefetch-url "$DOWNLOAD_URL" 2>/dev/null)
```
Correctly captures the Nix base32 hash and validates it is non-empty.

### 3.4 Converts to SRI via `nix hash to-sri` ✅ (minor caveat)
```bash
SRI_HASH=$(nix hash to-sri --type sha256 "$RAW_HASH")
```
Correct. Minor note: `nix hash to-sri` was soft-deprecated in nix ≥ 2.20 in
favour of `nix hash convert --hash-algo sha256 --to sri`. The old subcommand
still works (produces correct output, may emit a deprecation warning). Not a
blocking issue on NixOS 25.05.

### 3.5 `sed` patterns — both verified correct ✅

**Pattern 1 — version:**
```bash
sed -i "s|version = \"[^\"]*\"|version = \"${VERSION}\"|" "$OVERLAY_FILE"
```
Matches `version = "1.122.1";` in the overlay (semicolon preserved).
No false positives: the pattern requires `version = "…"` with
double-quoted content; comment lines and `${version}` interpolations do
not match it.

**Pattern 2 — hash:**
```bash
sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${SRI_HASH}\"|" "$OVERLAY_FILE"
```
Matches `hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";` in the
overlay. Uses `|` as the sed delimiter so base64 characters (`/`, `+`, `=`)
inside `SRI_HASH` do not conflict with the delimiter.

Only one `hash = "sha256-..."` line exists in the overlay. ✅

**Confirmation grep at end of recipe:**
```bash
grep -E '^\s+(version|hash) = ' "$OVERLAY_FILE"
```
Both lines have leading whitespace matching `^\s+`. ✅

### 3.6 Error handling ✅
- `set -euo pipefail` aborts on failure
- Checks for `nix` in `$PATH` before proceeding
- Checks for non-empty `RAW_HASH` before conversion
- Checks that `$OVERLAY_FILE` exists

---

## 4. Home Manager Wiring (`home-desktop.nix`)

`home-desktop.nix` line 61 uses:
```nix
package = pkgs.unstable.vscode-fhs;
```

The overlay is applied to `pkgs.unstable` (see §2). As established in §1.9,
`pkgs.unstable.vscode-fhs` will resolve to the FHS env wrapping the overridden
version-1.122.1 vscode. No changes to `home-desktop.nix` are needed. ✅

---

## 5. Critical Issues

### CRITICAL-1: Placeholder hash prevents all builds

**Severity:** Critical — build-blocking
**File:** `overlays/vscode.nix`, line 33
**Description:**
```nix
hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
```
The placeholder hash will produce a `hash mismatch in fixed-output derivation`
error on any machine that tries to realise `pkgs.unstable.vscode` or
`pkgs.unstable.vscode-fhs`. This breaks every desktop, htpc, stateless, server,
and headless-server build.

**Required fix:** On a NixOS/Linux host, run:
```bash
just update-vscode 1.122.1
```
This will:
1. Download the tarball from `https://update.code.visualstudio.com/1.122.1/linux-x64/stable`
2. Compute the Nix base32 hash
3. Convert to SRI format
4. Update `overlays/vscode.nix` in-place

After running the recipe, verify:
```bash
grep 'hash =' overlays/vscode.nix
# Should show: hash = "sha256-<real 44-char base64>=";
```

Then validate with a dry-build:
```bash
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

---

## 6. Non-Critical Observations

### OBS-1: `nix hash to-sri` soft-deprecated
`nix hash to-sri --type sha256` still works on NixOS 25.05 but may emit
deprecation warnings in future nix versions. Consider upgrading to:
```bash
nix hash convert --hash-algo sha256 --to sri "$RAW_HASH"
```
Not blocking, but worth addressing in a follow-up.

### OBS-2: Overlay does not pin `vscodeVersion` passthru
The `passthru.vscodeVersion` attribute (exposed by `generic.nix`) is derived
from `version` in the `finalAttrs` pattern and will correctly reflect
`"1.122.1"` after the override. No action needed — noting for completeness.

---

## 7. Build Validation

Build validation was **not possible** because the placeholder hash prevents
fetching the tarball. The following commands were not run:

- `nix flake show` — would work (does not realise any derivations)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — **blocked by placeholder hash**
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — **blocked**
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` — **blocked**

Build validation must be re-run after CRITICAL-1 is resolved.

---

## 8. Verdict: NEEDS_REFINEMENT

The implementation is **architecturally correct and well-written** in every
respect. The overlay structure, flake wiring, sed patterns, and justfile recipe
are all sound. The one and only blocker is the unfilled placeholder hash.

**Resolution path:**
1. Run `just update-vscode 1.122.1` on a NixOS/Linux host
2. Verify `overlays/vscode.nix` now contains a real `sha256-<base64>=` hash
3. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` and `.#vexos-desktop-vm`
4. If both pass → Re-review verdict: **APPROVED**
