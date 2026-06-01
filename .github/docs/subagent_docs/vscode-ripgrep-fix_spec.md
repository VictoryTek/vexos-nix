# Spec: vscode-ripgrep-fix

**Feature name:** `vscode-ripgrep-fix`  
**Date:** 2026-06-01  
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

`overlays/vscode.nix` pins VSCode to version 1.122.1 by overriding only `version`
and `src` on the nixpkgs base derivation:

```nix
vscode = prev.vscode.overrideAttrs (old: rec {
  version = "1.122.1";
  src = prev.fetchurl {
    url  = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
    hash = "sha256-t26YN3E5XaSJ7gki8nm06hVh4ZvXDEU77M749ZrqfAo=";
    name = "vscode-${version}-linux-x64.tar.gz";
  };
});
```

No `postPatch` override is present. This means the `postPatch` from the nixpkgs
base derivation (`pkgs/applications/editors/vscode/generic.nix`) runs unchanged.

---

## 2. Problem Definition

### Build failure

```
> Running phase: patchPhase
> rm: cannot remove 'resources/app/node_modules/@vscode/ripgrep/bin/rg': No such file or directory
error: Cannot build '/nix/store/1bk45a8pdbi3vd8045l3sgf08li17g5v-vscode-1.122.1.drv'.
```

### Root cause

The nixpkgs `generic.nix` `postPatch` for Linux hard-codes the ripgrep binary path:

```nix
let
  vscodeRipgrep =
    if stdenv.hostPlatform.isDarwin then
      if lib.versionAtLeast vscodeVersion "1.94.0" then
        "Contents/Resources/app/node_modules/@vscode/ripgrep/bin/rg"
      else
        "Contents/Resources/app/node_modules.asar.unpacked/@vscode/ripgrep/bin/rg"
    else
      "resources/app/node_modules/@vscode/ripgrep/bin/rg";  # ← Linux: no version guard
in
if !useVSCodeRipgrep then
  ''
    rm ${vscodeRipgrep}
    ln -s ${ripgrep}/bin/rg ${vscodeRipgrep}
  ''
```

This generates the shell commands:

```bash
rm resources/app/node_modules/@vscode/ripgrep/bin/rg
ln -s /nix/store/<ripgrep>/bin/rg resources/app/node_modules/@vscode/ripgrep/bin/rg
```

**VSCode 1.122.1 no longer ships `@vscode/ripgrep`.** Its `package.json` lists:

```json
"@vscode/ripgrep-universal": "^1.18.0"
```

instead. The `@vscode/ripgrep` package does not appear in the dependency tree at
all, so `node_modules/@vscode/ripgrep/bin/rg` does not exist in the tarball.
The `rm` therefore fails immediately with "No such file or directory", aborting
the build.

---

## 3. Evidence

### VSCode 1.122.1 `package.json` (relevant excerpt)

Fetched from:
`https://raw.githubusercontent.com/microsoft/vscode/1.122.1/package.json`

```json
"dependencies": {
  ...
  "@vscode/ripgrep-universal": "^1.18.0",
  ...
}
```

`@vscode/ripgrep` is absent from both `dependencies` and `devDependencies`.

### `@vscode/ripgrep-universal` binary layout

Fetched from:
`https://raw.githubusercontent.com/microsoft/vscode-ripgrep/main/packages/ripgrep-universal/lib/index.js`

```js
export function binPathFor({ os, arch }) {
  const binaryName = os === 'win32' ? 'rg.exe' : 'rg';
  return path.join(_packageRoot, 'bin', `${os}-${arch}`, binaryName);
}
export const rgPath = binPathFor({
  os: process.platform,
  arch: process.env.npm_config_arch || process.arch,
});
```

The README confirms: **"Binaries are placed under `bin/<os>-<arch>/<rg|rg.exe>`."**

For Linux x64 the binary is therefore at:
`<package_root>/bin/linux-x64/rg`

---

## 4. Proposed Solution Architecture

### Strategy: `builtins.replaceStrings` on `old.postPatch`

The overlay overrides `postPatch` in `overrideAttrs`, using `builtins.replaceStrings`
to surgically replace every occurrence of the old ripgrep path with the new one.

`builtins.replaceStrings` replaces ALL occurrences in the string, which is correct
here because the old path appears exactly twice in `old.postPatch` (once in `rm`
and once in `ln -s`). Both must be updated.

This approach:
- Preserves the rest of `postPatch` unchanged (jq product.json fix, sudo-prompt
  fix, asar extraction, jschardet symlink).
- Does not require duplicating the full postPatch script.
- Stays minimal: only the path string is changed.
- Is robust against whitespace differences (no line-pattern matching needed).

### New path

The full in-tarball path for the Linux x64 binary is one of:

| Location | Path |
|---|---|
| **Primary candidate** (native binary → asar.unpacked) | `resources/app/node_modules.asar.unpacked/@vscode/ripgrep-universal/bin/linux-x64/rg` |
| Fallback (if inside main asar, extracted by postPatch) | `resources/app/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg` |

**Implementation MUST verify the correct path** (see §6 below) before committing.

Because `@vscode/ripgrep-universal` ships 12 native executables (~60 MB), the
VSCode Linux build system almost certainly marks it as `unpackDir` in the asar
manifest, placing it in `node_modules.asar.unpacked/`. This is the **primary
candidate**.

However, the old `@vscode/ripgrep` was also a native binary and was handled via
the main asar extraction path in nixpkgs. If Microsoft changed their asar packing
strategy for `@vscode/ripgrep-universal`, the fallback path may apply.

---

## 5. Exact Fix to Apply

### File: `overlays/vscode.nix`

Add a `postPatch` attribute to the `overrideAttrs` block:

```nix
final: prev: {
  vscode = prev.vscode.overrideAttrs (old: rec {
    # ── Pinned version — updated by: just update-vscode <VERSION> ────────────
    version = "1.122.1";

    src = prev.fetchurl {
      url  = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
      hash = "sha256-t26YN3E5XaSJ7gki8nm06hVh4ZvXDEU77M749ZrqfAo=";
      name = "vscode-${version}-linux-x64.tar.gz";
    };

    # ── postPatch: fix ripgrep path for VSCode ≥ 1.122.0 ─────────────────────
    #
    # VSCode 1.122.0 replaced @vscode/ripgrep with @vscode/ripgrep-universal.
    # The new package stores the Linux x64 binary at:
    #   bin/linux-x64/rg   (within the package directory)
    #
    # The nixpkgs base postPatch hard-codes the OLD path
    #   resources/app/node_modules/@vscode/ripgrep/bin/rg
    # which no longer exists in the tarball.  Replace it everywhere it appears
    # in old.postPatch (rm AND ln -s) with the new package path.
    #
    # NOTE: The exact parent directory depends on whether VSCode packs
    # @vscode/ripgrep-universal inside node_modules.asar (extracted to
    # node_modules/ by postPatch) or in node_modules.asar.unpacked/.
    # Given that it ships ~60 MB of native binaries, it is almost certainly
    # in node_modules.asar.unpacked/.  VERIFY during implementation by
    # inspecting the tarball (see spec §6).
    postPatch = builtins.replaceStrings
      [ "resources/app/node_modules/@vscode/ripgrep/bin/rg" ]
      [ "resources/app/node_modules.asar.unpacked/@vscode/ripgrep-universal/bin/linux-x64/rg" ]
      old.postPatch;
  });
}
```

If verification reveals the binary is inside the main asar (not `.asar.unpacked`),
change the replacement target to:
```
resources/app/node_modules/@vscode/ripgrep-universal/bin/linux-x64/rg
```

---

## 6. Implementation Steps

### Step 1 — Verify the exact path in the tarball

Before writing any Nix, confirm which path is correct by inspecting the actual
VSCode 1.122.1 Linux tarball:

```bash
# Download (if not already cached by Nix)
curl -L "https://update.code.visualstudio.com/1.122.1/linux-x64/stable" \
     -o /tmp/vscode-1.122.1-linux-x64.tar.gz

# List ripgrep-universal paths
tar -tzf /tmp/vscode-1.122.1-linux-x64.tar.gz \
  | grep -E 'ripgrep' \
  | head -40
```

Expected output (primary candidate):
```
VSCode-linux-x64/resources/app/node_modules.asar.unpacked/@vscode/ripgrep-universal/bin/linux-x64/rg
```

If you see the path under `node_modules.asar.unpacked/`, use the primary candidate.
If you see it under `node_modules/` (no `.asar.unpacked`), use the fallback path.

### Step 2 — Apply the fix

Edit `overlays/vscode.nix` to add the `postPatch` override as shown in §5,
using whichever path was confirmed in Step 1.

### Step 3 — Validate

```bash
# Structural validation (safe, low RAM)
nix flake show

# Dry-build the vm variant (the one that failed)
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm

# Dry-build at least one more variant
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
```

The dry-build must complete without the `rm: cannot remove` error.

---

## 7. Why Not Other Approaches?

| Approach | Verdict | Reason |
|---|---|---|
| Override entire `postPatch` | Rejected | Duplicates ~30 lines of base postPatch; fragile against nixpkgs updates to the jq/sudo-prompt/asar sections |
| `prePatch` to create a stub file | Rejected | Would leave a dead symlink at the old path; doesn't fix the new package |
| `postPatch = old.postPatch + "..."` | Rejected | Appending doesn't fix the broken `rm` in the inherited postPatch — it still runs first and aborts the build |
| Update nixpkgs to ≥1.122.x | Out of scope | Would require nixpkgs bump and re-evaluation; this overlay is intentionally pinning ahead of nixpkgs |
| `builtins.replaceStrings` on `old.postPatch` | **Selected** | Minimal, surgical, self-documenting; handles both `rm` and `ln -s` in one replacement |

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Wrong path (asar vs asar.unpacked) | Medium | Verify via `tar -tzf` before writing the fix (Step 1) |
| nixpkgs later updates Linux to version-guard the ripgrep path | Low | Once nixpkgs ships 1.122.x natively, the overlay can be removed; `builtins.replaceStrings` is a no-op if the string is absent |
| `builtins.replaceStrings` fails silently if old string not present | Low | The old string is stable in nixpkgs generic.nix for Linux; also, if the `rm` still fails the build will catch it |
| VSCode 1.123.x changes ripgrep layout again | Low | Overlay comment documents the detection procedure (Step 1) so future updates are easy |
| Darwin builds broken if overlay applied | N/A | Overlay only sets Linux-specific `postPatch`; Darwin uses different VSCode packaging |

---

## 9. Files Modified

| File | Change |
|---|---|
| `overlays/vscode.nix` | Add `postPatch` attribute to `overrideAttrs` block |

No other files require changes.

---

## 10. Dependencies

No new Nix inputs or packages. The fix uses only:
- `builtins.replaceStrings` (built-in Nix function, always available)
- `old.postPatch` (already inherited from the base derivation)
- The system `ripgrep` from nixpkgs (already a dependency of the base VSCode derivation)
