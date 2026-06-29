# Spec: brave-origin — Custom Package for Desktop Role

## Current State

`modules/packages-desktop.nix` includes `pkgs.brave` (regular Brave browser, from nixpkgs).
Brave Origin is a separate product from Brave — it is not in nixpkgs and has no AUR/nixpkgs
upstream package yet.

## Problem Definition

User wants Brave Origin installed on the desktop role.

## Source Analysis

Brave Origin ships as a zip archive at:
```
https://github.com/brave/brave-browser/releases/download/v<version>/brave-origin-<version>-linux-amd64.zip
```

Current version: **1.91.171** (same tag as Brave browser release).

The zip extracts to a flat directory:
- `brave` — the Chromium-based ELF binary
- `brave-origin` — a bash wrapper script that sets `HERE=$(dirname $(readlink -f $0))` then
  calls `"$HERE/brave" "$@"`. Shebang is `#!/bin/bash`.
- `chrome_crashpad_handler` — ELF
- `chrome-management-service` — ELF
- `chrome-sandbox` — SUID helper (not installed on NixOS; userns sandbox used instead)
- `libEGL.so`, `libGLESv2.so`, `libvk_swiftshader.so`, `libvulkan.so.1`,
  `libqt5_shim.so`, `libqt6_shim.so` — bundled shared libs
- `product_logo_{16,24,32,48,64,128,256}.png` — icons
- Various `.pak` / `.dat` / `.bin` data files, `locales/`, `resources/` dirs
- `apparmor.d/`, `cron` — distro-specific; NOT installed on NixOS
- `vk_swiftshader_icd.json` — Vulkan ICD descriptor

Hash (NAR, --unpack): `sha256-hg1ogGswGK+GxNQT/SmQ0ewJ2uRa6bLzIAH1yNI46Kw=`

## Proposed Solution Architecture

### Option B — custom in-tree package under `pkgs/vexos.*`

Create `pkgs/brave-origin/default.nix` using `stdenv.mkDerivation` with:
- `fetchzip` to download the archive
- `autoPatchelfHook` to fix ELF interpreter + rpath (same library set as nixpkgs `brave`)
- `makeWrapper` to re-write the bash shebang cleanly via substituteInPlace
- Manual `.desktop` file (the zip ships no desktop file)
- Icons installed from the bundled `product_logo_*.png` files

Register under `pkgs.vexos.brave-origin` in `pkgs/default.nix`.

Add `pkgs.vexos.brave-origin` to `modules/packages-desktop.nix` (desktop-only; Origin is a
desktop browser product, not needed on server or HTPC roles).

### Runtime Dependencies (from nixpkgs brave rpath)

```
alsa-lib  at-spi2-core  cairo  cups.lib  dbus.lib  expat  fontconfig.lib  freetype
gdk-pixbuf  glib  gtk3  gtk4  libdrm  xorg.libX11  libglvnd  libxkbcommon
xorg.libXScrnSaver  xorg.libXcomposite  xorg.libXcursor  xorg.libXdamage
xorg.libXext  xorg.libXfixes  xorg.libXi  xorg.libXrandr  xorg.libXrender
xorg.libxshmfence  xorg.libXtst  mesa  nspr  nss  pango  pipewire  systemd.lib
wayland  xorg.libxcb  zlib  snappy  krb5.lib  qt6.qtbase  libpulseaudio  libva
```

## Implementation Steps

1. Create `pkgs/brave-origin/default.nix`
   - fetchzip the archive with the known hash
   - installPhase: copy all files to `$out/opt/brave.com/brave-origin/`, remove
     `apparmor.d/` and `cron`, fix `brave-origin` wrapper shebang via substituteInPlace
   - preFixup: `addAutoPatchelfSearchPath "$out/opt/brave.com/brave-origin"` so
     autoPatchelfHook finds the bundled .so files
   - Install icons to `$out/share/icons/hicolor/<N>x<N>/apps/brave-origin.png`
   - Install a minimal `.desktop` file to `$out/share/applications/brave-origin.desktop`
   - Symlink `$out/bin/brave-origin` → `$out/opt/brave.com/brave-origin/brave-origin`

2. Register in `pkgs/default.nix`:
   ```nix
   brave-origin = final.callPackage ./brave-origin { };
   ```

3. Add to `modules/packages-desktop.nix`:
   ```nix
   pkgs.vexos.brave-origin
   ```

## Risks and Mitigations

- **autoPatchelfHook may miss a library**: mitigated by listing the full set from nixpkgs
  brave. If any lib is missing, the dry-build will fail with a missing-symbol error that
  identifies exactly which library to add.
- **Version skew**: the zip URL includes the version; when updating brave in nixpkgs the
  version in this derivation must be bumped independently. Documented in the derivation.
- **chrome-sandbox SUID**: not installed. NixOS uses unprivileged user namespaces for the
  Chromium sandbox (`security.unprivilegedUsernsClone = true` is set in modules/system.nix
  or defaults to true on 26.05). Brave browser (regular) works fine without SUID sandbox.
- **Unfree license**: Brave is `lib.licenses.mpl20` (MPL 2.0) for the browser;
  nixpkgs does not mark it `unfree`. Same applies here.
