# VSCode Overlay — Implementation Specification

**Feature:** `vscode_overlay`  
**Date:** 2026-05-31  
**Phase:** 1 — Research & Specification

---

## 1. Current State Analysis

### 1.1 How VS Code is currently used

VS Code is **not** a system package. It lives entirely in the Home Manager layer:

| File | Reference | Detail |
|------|-----------|--------|
| `home-desktop.nix` line 61 | `package = pkgs.unstable.vscode-fhs;` | Home Manager `programs.vscode` package |
| `home-desktop.nix` line 21 | comment | Documents the FHS requirement |
| `modules/development.nix` lines 18-19 | comment | Documents that vscode-fhs is user-only |
| `modules/gnome.nix` line 146 | comment | Notes FHS dependency for Wayland |

**Key facts:**
- The attribute used is `pkgs.unstable.vscode-fhs`, NOT `pkgs.vscode`.
- `pkgs.unstable` is a separate nixpkgs instance (from `nixpkgs-unstable` input), not the stable `nixpkgs`.
- `vscode-fhs` in nixpkgs is defined as `vscode.fhs` — it is the `.fhs` passthru attribute of the `vscode` derivation, which wraps it in a `buildFHSEnv` chroot providing `/bin`, `/lib`, `/usr`.
- No system packages (`environment.systemPackages`) reference VS Code on any role.

### 1.2 How overlays currently work in this flake

The flake uses **three distinct overlay pathways**:

#### Pathway A — `unstableOverlayModule` (inline in `flake.nix`)
```nix
unstableOverlayModule = {
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import nixpkgs-unstable {
        inherit (final) config;
        inherit (final.stdenv.hostPlatform) system;
      };
    })
  ];
};
```
This creates `pkgs.unstable` by importing `nixpkgs-unstable` as a fresh nixpkgs instance.
Included in `commonBase` (used by desktop, htpc, stateless, server, headless-server roles).

#### Pathway B — `customPkgsOverlayModule` (inline in `flake.nix`)
```nix
customPkgsOverlayModule = {
  nixpkgs.overlays = [ (import ./pkgs) ];
};
```
Exposes `pkgs.vexos.*` custom in-tree packages. Included in `commonBase`.

#### Pathway C — `proxmoxOverlayModule` (inline in `flake.nix`)
Applied only to server / headless-server roles.

#### `mkBaseModule` (used for nixosModules.* exports)
Has its own **duplicate** inline overlay setup — it does NOT reference `unstableOverlayModule` or `customPkgsOverlayModule` by name, instead replicates their logic directly:
```nix
nixpkgs.overlays = [
  (final: prev: {
    unstable = import nixpkgs-unstable {
      inherit (final) config;
      inherit (final.stdenv.hostPlatform) system;
    };
  })
  (import ./pkgs)
];
```

#### `commonBase` composition
```nix
commonBase = [ unstableOverlayModule customPkgsOverlayModule ];
```
All roles except `vanilla` include `commonBase` in their `baseModules`.

### 1.3 Overlay file structure

`pkgs/default.nix` shows the project's overlay convention:
```nix
final: prev: {
  vexos = (prev.vexos or { }) // {
    cockpit-navigator = final.callPackage ./cockpit-navigator { };
    # ...
  };
}
```
Overlays are plain Nix files that export an `final: prev: { ... }` function.
The `overlays/` directory does **not yet exist**.

---

## 2. Problem Definition

The user wants to pin VS Code to a specific version (1.122.1) fetched directly
from Microsoft's update servers, bypassing whatever version `nixpkgs-unstable`
currently ships. The goals are:

1. Create `overlays/vscode.nix` — override `vscode` in the unstable nixpkgs
   instance so `pkgs.unstable.vscode-fhs` (and `pkgs.unstable.vscode`) resolve
   to the pinned version.
2. Wire the overlay into `flake.nix` so it is applied automatically to every
   role that uses `commonBase` (desktop, htpc, stateless, server, headless-server).
3. Add a `just update-vscode VERSION` recipe to automate future version bumps
   (updates the version string and sha256 hash in `overlays/vscode.nix` in-place).

**Critical constraint:** The overlay must target `pkgs.unstable`, not the
main stable `pkgs`, because `pkgs.unstable.vscode-fhs` is what the codebase
uses. An overlay applied only to the stable nixpkgs instance would have no
effect.

---

## 3. Research Findings

### 3.1 Nixpkgs `vscode` derivation structure (Source: nixpkgs upstream)

In nixpkgs (`pkgs/applications/editors/vscode/vscode.nix`), the package is
built with `stdenv.mkDerivation` and includes a `passthru` attribute:
```nix
passthru = {
  fhs = buildFHSEnv { ... };       # → pkgs.vscode-fhs
  fhsWithPackages = f: buildFHSEnv { packages = f; ... };
};
```
`pkgs.vscode-fhs` is defined in `all-packages.nix` as `vscode.fhs`.

**Consequence:** `overrideAttrs` on `vscode` preserves `passthru` (it is one
of the `mkDerivation` arguments and is untouched when only `version`/`src` are
overridden). Therefore `overriddenVscode.fhs` continues to work, and
`pkgs.vscode-fhs` automatically uses the new version — no separate override
of `vscode-fhs` is needed.

### 3.2 `overrideAttrs` pattern for tarball-based version pinning (Source: NixOS Wiki Overlays)

Standard pattern:
```nix
final: prev: {
  vscode = prev.vscode.overrideAttrs (old: rec {
    version = "1.122.1";
    src = prev.fetchurl {
      url  = "https://update.code.visualstudio.com/${version}/linux-x64/stable";
      hash = "sha256-<base64>";
      name = "vscode-${version}-linux-x64.tar.gz";
    };
  });
}
```
Using `rec` allows `src.url` to interpolate the overridden `version`.

### 3.3 `pkgs.extend` — applying an overlay to a sub-nixpkgs instance (Source: nixpkgs manual)

Every nixpkgs attribute set exposes `.extend (overlay)` which returns a new
attribute set with the overlay applied. This is the correct way to add an
overlay to the `pkgs.unstable` sub-instance **without** re-importing
`nixpkgs-unstable` from scratch:
```nix
unstable = (import nixpkgs-unstable { ... }).extend (import ./overlays/vscode.nix);
```
This is equivalent to:
```nix
unstable = import nixpkgs-unstable { overlays = [ (import ./overlays/vscode.nix) ]; };
```
Both are valid. The `.extend` form is marginally cleaner when one overlay is added.

### 3.4 `nix-prefetch-url` hash format (Source: Nix manual, nixpkgs contributing guide)

`nix-prefetch-url <URL>` outputs the hash in **Nix base32** format
(not hex, not SRI base64). Example:
```
1wlid4rwnlrs3bglv7gw3wvxpz6szldas1nk1mi43fqbldvknylb
```
Modern nixpkgs `fetchurl` uses the `hash` attribute in **SRI format**
(`sha256-<base64>`). To convert:
```bash
nix hash to-sri --type sha256 <nix-base32-hash>
```
The `sha256` attribute (legacy) also accepts the raw Nix base32 directly.
The `hash` attribute (preferred in NixOS 24.05+) requires SRI format.

`nix-prefetch-url` follows HTTP redirects by default (curl `-L` flag),
so `https://update.code.visualstudio.com/1.122.1/linux-x64/stable` (which
redirects to a CDN tarball) works without any special flags.
The hash is computed on the **final downloaded file content** (the tarball).

### 3.5 VSCode download URL pattern (Source: Microsoft update server, nixpkgs vscode.nix)

Microsoft provides two stable URL forms for a specific version:
- **Version URL:** `https://update.code.visualstudio.com/{VERSION}/linux-x64/stable`
  Redirects to the CDN tarball for that exact version. Stable per version number.
- **Commit URL:** `https://update.code.visualstudio.com/commit:{COMMIT_SHA}/linux-x64/stable`
  More explicit, requires knowing the commit SHA.

The version URL form is used here for readability and ease of update automation.

The tarball unpacks to a `VSCode-linux-x64/` directory. The binary is at
`VSCode-linux-x64/bin/code`. The nixpkgs derivation's `installPhase` handles
this structure and is unchanged by the overlay.

### 3.6 `just` recipe syntax for arguments (Source: just documentation)

```just
recipe-name argument:
    #!/usr/bin/env bash
    VALUE="{{argument}}"
    ...
```
Arguments are positional. `{{argument}}` is replaced at render time.
Required arguments produce an error if omitted.

### 3.7 `fetchurl` redirect and `name` attribute (Source: nixpkgs lib/fetchurl/builder.sh)

`fetchurl` passes `-L` to curl, so it follows redirects. The `name` attribute
sets the Nix store path basename. When the URL path ends in `stable` (not
`.tar.gz`), setting `name` explicitly is required to avoid a non-descriptive
store path.

---

## 4. Proposed Solution Architecture

### 4.1 Summary of changes

| File | Change |
|------|--------|
| `overlays/vscode.nix` (new) | Overlay function that overrides `vscode` version + src |
| `flake.nix` | Modify `unstableOverlayModule` to call `.extend` on the unstable import; modify `mkBaseModule` identically |
| `justfile` | Add `update-vscode version` recipe |

### 4.2 Why target `pkgs.unstable` and not main `pkgs`

The codebase uses `pkgs.unstable.vscode-fhs`. An overlay applied to the main
stable nixpkgs (`nixpkgs.overlays`) modifies `pkgs.vscode` but has no effect
on `pkgs.unstable.vscode` because `pkgs.unstable` is a completely independent
nixpkgs import.

The overlay must be applied via `.extend()` on the nixpkgs-unstable import.

### 4.3 Placement within `flake.nix`

Two places must be updated in sync (both define the `unstable` sub-nixpkgs):

1. **`unstableOverlayModule`** — used by all non-vanilla roles via `commonBase`
2. **`mkBaseModule`** — used by `nixosModules.*Base` exports (thin-wrapper hosts)

Both currently have the same inline `import nixpkgs-unstable { ... }` block.
Both get the same `.extend (import ./overlays/vscode.nix)` call appended.

---

## 5. Exact Implementation

### 5.1 `overlays/vscode.nix` (create new file)

```nix
# overlays/vscode.nix
# Pin pkgs.unstable.vscode (and pkgs.unstable.vscode-fhs) to a specific
# version fetched directly from Microsoft's update servers, bypassing whatever
# version nixpkgs-unstable currently ships.
#
# Applied via .extend() on the nixpkgs-unstable import in flake.nix so that
# pkgs.unstable.vscode-fhs (used in home-desktop.nix programs.vscode) picks up
# this version automatically.
#
# To update to a new version, run:
#   just update-vscode <VERSION>
#
# To update manually:
#   1. Run: nix-prefetch-url https://update.code.visualstudio.com/<VERSION>/linux-x64/stable
#   2. Convert: nix hash to-sri --type sha256 <nix-base32-hash-from-step-1>
#   3. Update `version` and `hash` below.
final: prev: {
  vscode = prev.vscode.overrideAttrs (old: rec {
    # ── Pinned version — updated by: just update-vscode <VERSION> ───────────
    version = "1.122.1";

    src = prev.fetchurl {
      # Microsoft stable-channel tarball for linux-x64.
      # This URL redirects to the CDN; fetchurl follows the redirect via curl -L.
      url  = "https://update.code.visualstudio.com/${version}/linux-x64/stable";

      # SHA256 hash in SRI format (sha256-<base64>).
      # Regenerate: nix-prefetch-url <url> | xargs nix hash to-sri --type sha256
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

      # Explicit name required: the URL path ends in "stable", not ".tar.gz",
      # so without this the Nix store path basename would be uninformative.
      name = "vscode-${version}-linux-x64.tar.gz";
    };
  });
}
```

**Note on the placeholder hash:** The implementation subagent must run
`nix-prefetch-url` on the Linux build host to obtain the real hash and replace
the `AAAA…` placeholder before committing. The recipe for this is in § 5.3.

### 5.2 Changes to `flake.nix`

#### Change 1 — `unstableOverlayModule` (around line 53)

Replace:
```nix
    # Inline NixOS module: exposes pkgs.unstable.* sourced from nixpkgs-unstable.
    # Used in modules/gnome.nix to pin GNOME application tools to latest.
    unstableOverlayModule = {
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
          };
        })
      ];
    };
```

With:
```nix
    # Inline NixOS module: exposes pkgs.unstable.* sourced from nixpkgs-unstable.
    # Used in modules/gnome.nix to pin GNOME application tools to latest.
    # The vscode overlay (overlays/vscode.nix) is applied via .extend so that
    # pkgs.unstable.vscode and pkgs.unstable.vscode-fhs use the pinned version.
    unstableOverlayModule = {
      nixpkgs.overlays = [
        (final: prev: {
          unstable = (import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
          }).extend (import ./overlays/vscode.nix);
        })
      ];
    };
```

#### Change 2 — `mkBaseModule` overlay list (around line 270)

The `mkBaseModule` function contains an inline `nixpkgs.overlays` block that
duplicates the `unstableOverlayModule` logic. Apply the same change there.

Replace:
```nix
      nixpkgs.overlays = [
        (final: prev: {
          unstable = import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
          };
        })
        (import ./pkgs)
      ];
```

With:
```nix
      nixpkgs.overlays = [
        (final: prev: {
          unstable = (import nixpkgs-unstable {
            inherit (final) config;
            inherit (final.stdenv.hostPlatform) system;
          }).extend (import ./overlays/vscode.nix);
        })
        (import ./pkgs)
      ];
```

### 5.3 `justfile` — add `update-vscode` recipe

Add this recipe after the `rollforward` recipe (or at a logical place near
the end of the file, before `reboot`/`shutdown`):

```just
# Pin VSCode to a new version by fetching the tarball hash from Microsoft's
# update servers and updating overlays/vscode.nix in-place.
#
# Usage:
#   just update-vscode 1.122.1
#
# What it does:
#   1. Fetches the tarball from update.code.visualstudio.com to get its hash
#   2. Converts the Nix base32 hash to SRI format (sha256-<base64>)
#   3. Updates `version` and `hash` in overlays/vscode.nix with sed
#
# After running this, commit the updated overlays/vscode.nix and rebuild.
# Requires: nix (with nix-command + flakes enabled), run on a Linux host.
update-vscode version:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi

    VERSION="{{version}}"

    if [ -z "$VERSION" ]; then
        echo "error: version argument is required." >&2
        echo "Usage: just update-vscode 1.122.1" >&2
        exit 1
    fi

    _jf_real=$(readlink -f "{{justfile()}}" 2>/dev/null || echo "{{justfile()}}")
    FLAKE_DIR=$(dirname "$_jf_real")
    OVERLAY_FILE="$FLAKE_DIR/overlays/vscode.nix"

    if [ ! -f "$OVERLAY_FILE" ]; then
        echo "error: $OVERLAY_FILE not found." >&2
        exit 1
    fi

    DOWNLOAD_URL="https://update.code.visualstudio.com/${VERSION}/linux-x64/stable"

    echo ""
    echo "Fetching VSCode ${VERSION} tarball hash..."
    echo "  URL: ${DOWNLOAD_URL}"
    echo ""

    # nix-prefetch-url returns the hash in Nix base32 format.
    RAW_HASH=$(nix-prefetch-url "$DOWNLOAD_URL" 2>/dev/null)

    if [ -z "$RAW_HASH" ]; then
        echo "error: nix-prefetch-url returned an empty hash." >&2
        echo "  Verify the version exists: $DOWNLOAD_URL" >&2
        exit 1
    fi

    # Convert Nix base32 → SRI format (sha256-<base64>) for use in fetchurl hash = "...".
    SRI_HASH=$(nix hash to-sri --type sha256 "$RAW_HASH")

    echo "  Nix base32: ${RAW_HASH}"
    echo "  SRI:        ${SRI_HASH}"
    echo ""

    # Update version = "..." in overlays/vscode.nix
    sed -i "s|version = \"[^\"]*\"|version = \"${VERSION}\"|" "$OVERLAY_FILE"

    # Update hash = "sha256-..." in overlays/vscode.nix
    # The SRI hash contains base64 chars (a-z A-Z 0-9 + / =), none of which
    # conflict with the | sed delimiter.
    sed -i "s|hash = \"sha256-[^\"]*\"|hash = \"${SRI_HASH}\"|" "$OVERLAY_FILE"

    echo "Updated $OVERLAY_FILE:"
    grep -E '^\s+(version|hash) = ' "$OVERLAY_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Run 'just build <role> <gpu>' to verify the new closure builds."
    echo "  2. Commit overlays/vscode.nix."
    echo "  3. Run 'just switch' to apply."
```

---

## 6. Notes on SHA256 Format

| Format | Example | Used in |
|--------|---------|---------|
| Nix base32 | `1wlid4rwnlrs3bglv7gw3wvxpz6szldas1nk1mi43fqbldvknylb` | `nix-prefetch-url` output; legacy `sha256 = "..."` attr |
| SRI (base64) | `sha256-abc123...=` | Modern `hash = "..."` attr in fetchurl / fetchFromGitHub |
| Hex | `deadbeef...` | Not used by fetchurl |

The overlay uses the `hash` attribute (SRI format) because:
- It is the recommended form in NixOS 24.05+ and all current nixpkgs documentation.
- It is self-describing (includes the hash type).
- `nix-prefetch-url` returns Nix base32; the recipe converts it to SRI with `nix hash to-sri`.

The `sha256` attribute (Nix base32) still works but is deprecated style.

---

## 7. Implementation Steps for Subagent

1. **Create `overlays/` directory** (does not exist yet).
2. **Create `overlays/vscode.nix`** with the content in § 5.1.
   - The placeholder hash `sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=` must
     be replaced with the real hash obtained by running:
     ```bash
     nix-prefetch-url https://update.code.visualstudio.com/1.122.1/linux-x64/stable \
       | xargs nix hash to-sri --type sha256
     ```
     This command must be run on the Linux build host. If running in CI or on a
     NixOS host, execute it in the implementation step.
3. **Edit `flake.nix`** — two locations (§ 5.2 Change 1 and Change 2).
4. **Edit `justfile`** — add the `update-vscode` recipe (§ 5.3).
5. **Verify** with `nix flake show` and at minimum one
   `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Placeholder hash causes evaluation error | High if not replaced | Implementation subagent must compute real hash before committing |
| `overrideAttrs` breaks `vscode.fhs` passthru | Low — passthru is preserved by overrideAttrs | Confirmed by nixpkgs source: `vscode-fhs = vscode.fhs` at top level; `.fhs` is a `passthru` attr that survives `overrideAttrs` when not explicitly changed |
| Microsoft CDN URL structure changes | Very low | URL has been stable since VSCode 1.x; if it breaks, `just update-vscode` would fail clearly with an HTTP error from nix-prefetch-url |
| `mkBaseModule` not updated in sync | Medium if forgotten | Both locations are noted in this spec; review must verify both |
| `vanilla` role not affected | Expected/correct | vanilla has `baseModules = []` — it intentionally uses stock nixpkgs without any vexos customization |
| `nix hash to-sri` not available on old Nix | Low (project uses NixOS 25.11) | Command is available since Nix 2.4; all current NixOS versions include it |
| Redirect URL non-determinism | Very low | nix-prefetch-url verifies content hash; if Microsoft ever re-publishes a different file under the same version URL, Nix will detect the hash mismatch |

---

## 9. Files Modified

| Path | Action |
|------|--------|
| `overlays/vscode.nix` | Create (new file, new directory) |
| `flake.nix` | Edit — 2 locations |
| `justfile` | Edit — add 1 recipe |

---

## 10. Sources

1. NixOS Wiki — Overlays: https://nixos.wiki/wiki/Overlays
2. NixOS Wiki — Visual Studio Code: https://nixos.wiki/wiki/Visual_Studio_Code
3. Nixpkgs manual — Overlays chapter: https://nixos.org/manual/nixpkgs/stable/#sec-overlays-definition
4. Nixpkgs source — vscode.nix: https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/vscode/vscode.nix
5. Nix manual — `nix hash to-sri`: https://nix.dev/manual/nix/latest/command-ref/new-cli/nix-hash
6. Nix manual — `nix-prefetch-url`: https://nix.dev/manual/nix/latest/command-ref/nix-prefetch-url
7. just documentation — Recipe arguments: https://just.systems/man/en/arguments.html
8. NixOS Discourse — pkgs.extend usage: https://discourse.nixos.org/t/how-to-apply-overlay-to-a-specific-nixpkgs-instance/
