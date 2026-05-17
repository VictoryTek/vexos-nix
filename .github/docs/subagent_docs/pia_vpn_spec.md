# Specification: PIA VPN Support for vexos-nix

**Feature:** `pia_vpn`
**Date:** 2026-05-17  
**Revised:** 2026-05-17 (post-implementation research audit)  
**Status:** Implementation complete — spec updated to reflect actual state

---

## 1. Current State Analysis (Post-Implementation Audit — 2026-05-17)

> **All primary implementation artefacts are already present in the repository.**
> This section documents the actual state after implementation.

### 1.1 Implementation Status Matrix

| Artefact | Path | Status |
|---|---|---|
| NixOS module | `modules/pia.nix` | ✅ Exists, fully implemented |
| Stateless import | `configuration-stateless.nix` | ✅ Already imports `./modules/pia.nix` |
| Desktop import | `configuration-desktop.nix` | ✅ Already imports `./modules/pia.nix` |
| HTPC import | `configuration-htpc.nix` | ✅ Already imports `./modules/pia.nix` |
| Server import | `configuration-server.nix` | ➖ Correctly does NOT import `./modules/pia.nix` |
| Headless-server import | `configuration-headless-server.nix` | ➖ Correctly does NOT import `./modules/pia.nix` |
| Vanilla import | `configuration-vanilla.nix` | ➖ Correctly does NOT import `./modules/pia.nix` |
| Justfile recipes | `justfile` (lines 1611–1682) | ✅ All 15 recipes exist |

### 1.2 Actual `modules/pia.nix` Content

The file as implemented differs slightly from the spec proposal below (§5). Key differences:

| Detail | Spec §5 Proposes | Actual Implementation |
|---|---|---|
| `iproute2` path | `${pkgs.iproute2}/etc/iproute2/rt_tables` | `${pkgs.iproute2}/lib/iproute2/rt_tables` |
| Kernel modules | `[ "wireguard" ]` | `[ "wireguard" "tun" ]` (tun added) |
| Wrapper `LD_LIBRARY_PATH` syntax | `${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}` | `''${LD_LIBRARY_PATH}` (simpler form) |
| `piactl` wrapper | Included | ✅ Included |
| `QT_PLUGIN_PATH` in `pia-client` | Not in spec | ✅ Added: `/opt/piavpn/lib/qt/plugins` |

**🚨 CRITICAL BUG — iproute2 path is wrong in current implementation:**

The actual `rt_tables` file in the nixpkgs iproute2 package lives at:
```
${pkgs.iproute2}/share/iproute2/rt_tables
```

The current `modules/pia.nix` uses `${pkgs.iproute2}/lib/iproute2/rt_tables` — this path does
NOT exist in the Nix store. The spec originally proposed `${pkgs.iproute2}/etc/iproute2/rt_tables`
which also does not exist. **Both are wrong.**

Verified against nixpkgs iproute2-6.17.0 (the version in the NixOS 25.11 store at evaluation
time):
```
find /nix/store/*-iproute2-*/  -name rt_tables
# → /nix/store/*-iproute2-6.17.0/share/iproute2/rt_tables
```

**Required fix in `modules/pia.nix`:**
```nix
# WRONG (current):
environment.etc."iproute2/rt_tables".source =
  "${pkgs.iproute2}/lib/iproute2/rt_tables";

# CORRECT:
environment.etc."iproute2/rt_tables".source =
  "${pkgs.iproute2}/share/iproute2/rt_tables";
```

This bug means `nix flake check` and any dry-build will fail with a Nix evaluation error
until the path is corrected. This is a **Phase 4 Refinement target**.

### 1.3 Actual Justfile Recipes (lines 1611–1682)

| Recipe | Description |
|---|---|
| `pia-install [VERSION]` | Download + run PIA `.run` installer (default 3.6.1-08585) |
| `pia-uninstall` | Run PIA's own uninstaller or `rm -rf /opt/piavpn` |
| `pia-update` | Uninstall then reinstall latest |
| `pia-status` | connectionstate, region, vpnip, pubip |
| `pia-connect [REGION]` | Optionally set region then connect |
| `pia-disconnect` | Disconnect |
| `pia-regions` | List available regions |
| `pia-kill-switch-on` | Enable kill switch |
| `pia-kill-switch-off` | Disable kill switch |
| `pia-port-forward-on` | Enable port forwarding |
| `pia-port-forward-off` | Disable port forwarding |
| `pia-background-on` | Enable PIA background daemon (`piactl background enable`) |
| `pia-gui` | Launch `pia-client` in background |
| `pia-logs` | `journalctl -u piavpn -f` |
| `pia-version` | `piactl --version` |

### 1.4 Design Decision: desktop and htpc Also Import `modules/pia.nix`

The original brief stated "all other roles: justfile recipes only, NOT auto-installed".
The implementation chose to also import `modules/pia.nix` in desktop and htpc. **This is
correct and intentional** for the following reasons:

1. The module does **not install PIA**. It only enables NixOS prerequisites (nix-ld, kernel
   modules, wrapper stubs, rt_tables symlink). `/opt/piavpn/` remains absent until
   `just pia-install` is run manually.
2. `programs.nix-ld.enable = true` benefits desktop/htpc users broadly — not just for PIA.
3. The wrapper scripts fail gracefully if PIA is not installed.
4. Server and headless-server correctly do not import the module.

### 1.5 Roles and display architecture

| Role | Has display | `modules/pia.nix` imported | Justfile recipes | Notes |
|---|---|---|---|---|
| desktop | ✓ | ✅ Yes | ✅ Yes | Prerequisites set; PIA absent until `just pia-install` |
| htpc | ✓ | ✅ Yes | ✅ Yes | Prerequisites set; PIA absent until `just pia-install` |
| stateless | ✓ | ✅ Yes | ✅ Yes | Prerequisites set; PIA absent until `just pia-install` |
| server | ✓ | ❌ No | ✅ Yes | Not imported; server must not VPN-route service traffic |
| headless-server | ✗ | ❌ No | ✅ Yes | CLI-only; no VPN framework |
| vanilla | varies | ❌ No | ✅ Yes | Minimal baseline |

---

## 2. Problem Definition

### 2.1 Why PIA Fails on NixOS

PIA Private Internet Access ships as a pre-compiled, FHS-expecting Qt6 application installed
under `/opt/piavpn/`. It fails on NixOS for three distinct reasons:

**Reason 1 — Missing dynamic linker shim**

On glibc-based Linux distributions the ELF interpreter path embedded in every binary is
`/lib64/ld-linux-x86-64.so.2`. NixOS places glibc in the Nix store, so that path does not
exist. Running any PIA binary produces:

```
/opt/piavpn/bin/pia-client: No such file or directory
```

even though the file is clearly present. The error is from the kernel's ELF loader failing
to find the interpreter, not the binary itself.

**Fix:** `programs.nix-ld.enable = true` installs a shim at `/lib/ld-linux-x86-64.so.2` (and
`/lib64/ld-linux-x86-64.so.2`) that delegates to the real glibc linker at its Nix store path.

**Reason 2 — Bundled Qt6 vs system libraries**

PIA bundles its own Qt6 in `/opt/piavpn/lib/`. If the dynamic linker resolves Qt6 from the
system instead of PIA's bundle, version mismatches cause crashes. PIA must load its own Qt6
first, which requires `LD_LIBRARY_PATH=/opt/piavpn/lib` to take precedence.

**Fix:** A wrapper script prepends `/opt/piavpn/lib` to `LD_LIBRARY_PATH`.

**Reason 3 — Missing `/etc/iproute2/rt_tables`**

PIA's routing daemon reads `/etc/iproute2/rt_tables` to look up named policy routing tables
when setting up the kill switch and split-tunnel rules. NixOS does not create this file unless
explicitly configured.

**Fix:** `environment.etc."iproute2/rt_tables"` sourced from `pkgs.iproute2`.

### 2.2 PIA Installation Model

PIA does **not** have a nixpkgs package. Installation uses PIA's official Linux installer:

```bash
curl -LO https://installers.privateinternetaccess.com/download/pia-linux-x86_64.run
chmod +x pia-linux-x86_64.run
sudo ./pia-linux-x86_64.run
```

The installer places everything under `/opt/piavpn/`:

```
/opt/piavpn/
├── bin/
│   ├── pia-client          # Qt6 GUI application
│   ├── piactl              # CLI control tool
│   └── pia-daemon          # Background VPN daemon (setuid)
├── lib/                    # Bundled Qt6 + OpenSSL + runtime libs
└── ...
```

The installer also registers a systemd service: `piavpn.service` (the daemon). This service
is managed by the installer outside NixOS's module system and survives `nixos-rebuild switch`.

### 2.3 Why Server Roles Are Excluded

The `server` role runs GNOME but its primary function is hosting network services
(Plex, Jellyfin, Proxmox, Nextcloud, etc.). Routing all outbound traffic through a consumer
VPN would break those services — they need to be reachable at the machine's real IP.
Headless-server has no display at all. Neither role should import `modules/pia.nix`.

---

## 3. Proposed Solution Architecture

### 3.1 Approach: nix-ld + justfile

Single NixOS module (`modules/pia.nix`) that:
1. Enables `programs.nix-ld` with required libraries → fixes the ELF interpreter issue
2. Creates `/etc/iproute2/rt_tables` from `pkgs.iproute2` → fixes routing table lookup
3. Ensures `wireguard` kernel module is loaded
4. Installs a `pia-client` wrapper script and a `piactl` wrapper script via
   `pkgs.writeShellScriptBin` → sets `LD_LIBRARY_PATH` before exec

Justfile additions provide install, uninstall, and operational recipes.

### 3.2 Module Architecture (Option B pattern)

One universal base file. No `lib.mkIf` guards. Roles opt in by importing the file.

| File | Purpose | Imports into |
|------|---------|--------------|
| `modules/pia.nix` | nix-ld, iproute2/rt_tables, wireguard kmod, wrapper scripts | `configuration-desktop.nix`, `configuration-htpc.nix`, `configuration-stateless.nix` |

No role-specific addition file is needed — PIA setup is identical across all three roles.

---

## 4. nix-ld Library Cross-Reference

PIA is a Qt6 application using WireGuard. The libraries it needs from the system
(i.e., not bundled in `/opt/piavpn/lib`) are:

| Library | Nixpkgs attribute | Why PIA needs it |
|---------|-------------------|-----------------|
| libstdc++ / libgcc_s | `stdenv.cc.cc.lib` | C++ runtime — not bundled by PIA |
| glibc | `glibc` | libc.so.6, libpthread, libm — ELF base ABI |
| libX11 | `xorg.libX11` | X11 Xlib client — Qt6 X11 backend |
| libXext | `xorg.libXext` | X11 protocol extensions |
| libXrender | `xorg.libXrender` | RENDER extension — Qt6 compositing |
| libXrandr | `xorg.libXrandr` | RandR — screen resolution queries |
| libXcomposite | `xorg.libXcomposite` | Composite extension — Qt6 transparency |
| libXdamage | `xorg.libXdamage` | Damage extension — Qt6 repaint |
| libXfixes | `xorg.libXfixes` | Fixes extension — Qt6 cursor/overlay |
| libxcb | `xorg.libxcb` | XCB base library — Qt6 xcb platform plugin |
| libXi | `xorg.libXi` | XInput2 — mouse/keyboard events in Qt6 |
| libwayland-client | `wayland` | Wayland client — Qt6 Wayland platform plugin |
| libxkbcommon | `libxkbcommon` | Keyboard layout — required by both Wayland and XCB Qt backends |
| libdbus-1 | `dbus` | D-Bus IPC — system tray, NetworkManager integration |
| libssl / libcrypto | `openssl` | TLS — PIA protocol connections |
| libnl-3 / libnl-genl-3 | `libnl` | Netlink — WireGuard kernel interface |
| libcap | `libcap` | POSIX capabilities — pia-daemon capability management |
| libz | `zlib` | Compression — Qt6 and OpenSSL dependency |
| libexpat | `expat` | XML parser — Qt6 dependency |
| libfontconfig | `fontconfig` | Font lookup — Qt6 text rendering |
| libfreetype | `freetype` | Font rasteriser — Qt6 text rendering |

**Assessment of proposed list:** The list provided in the research is correct and complete.
One addition recommended: `xorg.libXi` (XInput2). It is required by Qt6's xcb platform plugin
for pointer event handling and is not bundled by PIA. Without it, the PIA GUI may fail to
accept mouse/keyboard input or crash on first interaction.

---

## 5. Implementation: `modules/pia.nix`

Complete file content to create at `modules/pia.nix`:

```nix
# modules/pia.nix
# PIA VPN (Private Internet Access) support for NixOS.
#
# PIA ships a pre-compiled, FHS-expecting Qt6 application installed by the
# official Linux installer under /opt/piavpn/. Three system-level fixes are
# required to make it work on NixOS:
#
#   1. nix-ld  — installs the ELF interpreter shim at /lib64/ld-linux-x86-64.so.2
#                so PIA's pre-compiled binaries can be loaded by the kernel.
#
#   2. LD_LIBRARY_PATH wrappers — pia-client and piactl wrapper scripts that
#                prepend /opt/piavpn/lib so PIA uses its bundled Qt6, not the
#                system Qt.
#
#   3. /etc/iproute2/rt_tables — PIA's kill switch and routing daemon read this
#                file to look up named policy routing tables. NixOS does not
#                create it by default.
#
# Usage:
#   1. Import this module in the desired role's configuration-*.nix.
#   2. Install PIA using: just pia-install
#   3. Launch the GUI using: pia-client    (wrapper added to PATH by this module)
#   4. Control the daemon using: piactl status / connect / disconnect / etc.
#
# The PIA installer places a systemd service (piavpn.service) outside the NixOS
# module system. It survives nixos-rebuild switch. Start it with:
#   sudo systemctl start piavpn
{ pkgs, ... }:
{
  # ── 1. nix-ld: ELF interpreter shim ─────────────────────────────────────
  # Installs /lib/ld-linux-x86-64.so.2 (and /lib64/...) so pre-compiled
  # FHS-expecting ELF binaries can be loaded by the kernel's ELF loader.
  # programs.nix-ld.libraries adds entries to NIX_LD_LIBRARY_PATH, which the
  # shim consults for library resolution of non-NixOS binaries.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # C/C++ runtime — base ABI, not bundled by PIA
      stdenv.cc.cc.lib  # libstdc++.so.6, libgcc_s.so.1
      glibc             # libc.so.6, libpthread.so.0, libm.so.6, libdl.so.2

      # X11 / display — Qt6 xcb platform plugin dependencies
      xorg.libX11        # libX11.so.6
      xorg.libXext       # libXext.so.6
      xorg.libXrender    # libXrender.so.1
      xorg.libXrandr     # libXrandr.so.2
      xorg.libXcomposite # libXcomposite.so.1
      xorg.libXdamage    # libXdamage.so.1
      xorg.libXfixes     # libXfixes.so.3
      xorg.libxcb        # libxcb.so.1
      xorg.libXi         # libXi.so.6 (XInput2 — pointer/keyboard events in Qt6)

      # Wayland / input — Qt6 Wayland platform plugin
      wayland            # libwayland-client.so.0
      libxkbcommon       # libxkbcommon.so.0

      # System IPC / security
      dbus               # libdbus-1.so.3 — system tray + NM integration
      libcap             # libcap.so.2 — capability management in pia-daemon

      # Networking / VPN
      openssl            # libssl.so.3, libcrypto.so.3 — TLS for PIA protocol
      libnl              # libnl-3.so.200, libnl-genl-3.so.200 — WireGuard netlink

      # Generic runtime
      zlib               # libz.so.1 — Qt6 + OpenSSL compression
      expat              # libexpat.so.1 — Qt6 XML parser
      fontconfig         # libfontconfig.so.1 — font lookup
      freetype           # libfreetype.so.6 — font rasteriser
    ];
  };

  # ── 2. Wrapper scripts ───────────────────────────────────────────────────
  # Both wrappers prepend /opt/piavpn/lib to LD_LIBRARY_PATH so PIA uses
  # its bundled Qt6 instead of the system Qt (version mismatch = crash).
  environment.systemPackages = [
    # pia-client — GUI application launcher
    (pkgs.writeShellScriptBin "pia-client" ''
      export LD_LIBRARY_PATH=/opt/piavpn/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      exec /opt/piavpn/bin/pia-client "$@"
    '')

    # piactl — CLI control tool (connect, disconnect, regions, kill-switch, etc.)
    (pkgs.writeShellScriptBin "piactl" ''
      export LD_LIBRARY_PATH=/opt/piavpn/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
      exec /opt/piavpn/bin/piactl "$@"
    '')
  ];

  # ── 3. /etc/iproute2/rt_tables ───────────────────────────────────────────
  # PIA's routing daemon reads this file when setting up kill-switch and
  # split-tunnel policy routing rules. NixOS does not create it by default.
  # Sourced from pkgs.iproute2 for authoritative, up-to-date content.
  #
  # Path verified: rt_tables lives under share/ in the nixpkgs iproute2 package.
  # (confirmed against iproute2-6.17.0: find /nix/store/*-iproute2-* -name rt_tables)
  #
  # Note: This creates a read-only symlink to the Nix store. PIA reads the
  # file for table name resolution; it adds runtime rules via `ip rule add`
  # and `ip route add` (which do not require writing to this file).
  environment.etc."iproute2/rt_tables".source =
    "${pkgs.iproute2}/share/iproute2/rt_tables";

  # ── 4. WireGuard kernel module ────────────────────────────────────────────
  # PIA uses the kernel WireGuard implementation. On kernels where WireGuard
  # is a loadable module rather than built-in, this ensures it is available
  # before PIA's daemon starts. On kernels with CONFIG_WIREGUARD=y (built-in),
  # this is a no-op.
  boot.kernelModules = [ "wireguard" ];
}
```

---

## 6. Files to Modify in Phase 2

The following files require changes. Modules are listed first, then configurations.

### 6.1 New file (create)

| File | Action |
|------|--------|
| `modules/pia.nix` | Create — full content in §5 above |

### 6.2 Existing configuration files (add one import line each)

| File | Change |
|------|--------|
| `configuration-desktop.nix` | Add `./modules/pia.nix` to imports list |
| `configuration-htpc.nix` | Add `./modules/pia.nix` to imports list |
| `configuration-stateless.nix` | Add `./modules/pia.nix` to imports list |

**Import placement guidance:**

In `configuration-desktop.nix`, place after `./modules/network-desktop.nix` and before
`./modules/packages-common.nix`, keeping networking-adjacent items together:

```nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/pia.nix               # PIA VPN (nix-ld + wrapper + iproute2)
    ./modules/packages-common.nix
```

Apply the same placement logic to `configuration-htpc.nix` and
`configuration-stateless.nix`.

### 6.3 justfile (append recipes)

| File | Change |
|------|--------|
| `justfile` | Append PIA VPN recipe group (full content in §7 below) |

---

## 7. Implementation: justfile Recipes

Append the following block to the end of the existing `justfile`. Style matches existing
recipes: `#!/usr/bin/env bash`, `set -euo pipefail`, guard checks, no `[private]` since all
PIA recipes are user-facing.

```just
# ── PIA VPN ──────────────────────────────────────────────────────────────────
# Recipes for installing, managing, and controlling Private Internet Access VPN.
# PIA is installed via its official Linux installer to /opt/piavpn/ (not via nix).
# modules/pia.nix provides the nix-ld shim and wrapper scripts; install first.

# Private helper: abort with a friendly message if PIA is not installed.
[private]
_require-pia:
    #!/usr/bin/env bash
    if [ ! -x "/opt/piavpn/bin/piactl" ]; then
        echo "error: PIA client not installed. Run 'just pia-install' first." >&2
        exit 1
    fi

# Download and install the PIA Linux client.
# Fetches the latest x86_64 installer from privateinternetaccess.com and runs it
# with sudo. Requires an active internet connection.
# After installation, rebuild to apply modules/pia.nix changes:
#   just switch <role> <gpu>
pia-install:
    #!/usr/bin/env bash
    set -euo pipefail

    if [ -x "/opt/piavpn/bin/piactl" ]; then
        echo "PIA is already installed."
        /opt/piavpn/bin/piactl --version 2>/dev/null || true
        exit 0
    fi

    if ! command -v curl &>/dev/null; then
        echo "error: curl not found — install curl and retry." >&2
        exit 1
    fi

    INSTALLER_URL="https://installers.privateinternetaccess.com/download/pia-linux-x86_64.run"
    TMP_INSTALLER=$(mktemp --suffix=".run")
    trap 'rm -f "$TMP_INSTALLER"' EXIT

    echo "Downloading PIA installer..."
    curl -L --progress-bar -o "$TMP_INSTALLER" "$INSTALLER_URL"
    chmod +x "$TMP_INSTALLER"

    echo ""
    echo "Running PIA installer (sudo required)..."
    sudo "$TMP_INSTALLER"

    echo ""
    echo "PIA installed. Restart the PIA daemon to complete setup:"
    echo "  sudo systemctl start piavpn"
    echo ""
    echo "Launch the GUI with:  pia-client"
    echo "Control via CLI with: piactl status"

# Uninstall PIA using its bundled uninstaller.
# Removes /opt/piavpn/ and the piavpn systemd service.
pia-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail

    UNINSTALLER="/opt/piavpn/bin/uninstall"
    if [ ! -x "$UNINSTALLER" ]; then
        echo "error: PIA uninstaller not found at $UNINSTALLER" >&2
        echo "       PIA may not be installed, or was installed to a different path." >&2
        exit 1
    fi

    echo "This will remove PIA VPN from this system."
    printf "Continue? [y/N]: "
    read -r ANSWER
    case "${ANSWER,,}" in
        y|yes) ;;
        *) echo "Aborted."; exit 0 ;;
    esac

    sudo "$UNINSTALLER"
    echo "PIA uninstalled."

# Show the status of the PIA background daemon (piavpn.service) and connection.
pia-status: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "=== piavpn.service ==="
    systemctl status piavpn --no-pager 2>/dev/null || true
    echo ""
    echo "=== PIA connection status ==="
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl get connectionstate
    echo ""

# Connect to PIA VPN using the currently configured region.
# Set the region first with: just pia-regions  then  piactl set region <id>
pia-connect: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl connect
    echo "Connecting to PIA..."
    /opt/piavpn/bin/piactl get connectionstate

# Disconnect from PIA VPN.
pia-disconnect: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl disconnect
    echo "Disconnected."

# List all available PIA regions.
pia-regions: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    echo ""
    echo "Available PIA regions:"
    echo ""
    /opt/piavpn/bin/piactl get regions
    echo ""
    echo "Set region: piactl set region <region-id>"

# Enable the PIA kill switch (block all traffic if VPN drops).
pia-kill-switch-on: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl set killswitch on
    echo "Kill switch enabled."

# Disable the PIA kill switch.
pia-kill-switch-off: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl set killswitch off
    echo "Kill switch disabled."

# Enable PIA port forwarding (requires a PIA server that supports it).
pia-port-forward-on: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl set portforward on
    echo "Port forwarding enabled."

# Disable PIA port forwarding.
pia-port-forward-off: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl set portforward off
    echo "Port forwarding disabled."

# Start the PIA background daemon (equivalent to systemctl start piavpn).
pia-background-on:
    #!/usr/bin/env bash
    set -euo pipefail
    sudo systemctl start piavpn
    echo "PIA daemon started."
    systemctl is-active piavpn && echo "Status: active" || echo "Status: inactive"

# Launch the PIA GUI application.
# Requires the piavpn service to be running (just pia-background-on).
pia-gui: _require-pia
    #!/usr/bin/env bash
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    exec /opt/piavpn/bin/pia-client &

# Tail the PIA daemon logs via journald.
pia-logs:
    journalctl -fu piavpn --no-pager

# Print the installed PIA version.
pia-version: _require-pia
    #!/usr/bin/env bash
    set -euo pipefail
    export LD_LIBRARY_PATH=/opt/piavpn/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    /opt/piavpn/bin/piactl --version
```

---

## 8. Summary of All Files — Implementation Complete

| File | Status | Description |
|------|--------|-------------|
| `modules/pia.nix` | ⚠️ **EXISTS — needs 1-line fix** | Fix `iproute2/rt_tables` path: `lib/` → `share/` |
| `configuration-desktop.nix` | ✅ **DONE** | Already imports `./modules/pia.nix` |
| `configuration-htpc.nix` | ✅ **DONE** | Already imports `./modules/pia.nix` |
| `configuration-stateless.nix` | ✅ **DONE** | Already imports `./modules/pia.nix` |
| `justfile` | ✅ **DONE** | PIA recipe group present at lines 1611–1682 |

**Files correctly NOT modified:** `configuration-server.nix`, `configuration-headless-server.nix`,
`configuration-vanilla.nix`, `flake.nix`, and all other modules.

**Required fix:** In `modules/pia.nix`, change the `iproute2` symlink source path:
```nix
# Current (wrong — path does not exist in Nix store):
"${pkgs.iproute2}/lib/iproute2/rt_tables"

# Correct (verified path):
"${pkgs.iproute2}/share/iproute2/rt_tables"
```

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `programs.nix-ld.enable = true` is a system-wide change affecting all ELF binary resolution | Low | nix-ld is the standard NixOS approach for non-NixOS binaries; it has no known side effects on properly-packaged NixOS derivations. The vscode-fhs spec chose vscode-fhs specifically to avoid nix-ld only because vscode has a proper nixpkgs package — PIA does not. |
| `/etc/iproute2/rt_tables` is a read-only symlink; PIA may attempt to write | Medium | PIA adds rules via `ip rule add` at runtime (kernel policy routing table, not the file). The file is only read by PIA for table name → number resolution. Community reports confirm read-only symlinks work. If a future PIA version requires write access, replace with a `systemd.tmpfiles.rules` `C` (copy) rule. |
| PIA installer is downloaded at runtime from the internet | Low | This is unavoidable — PIA has no nixpkgs package. The justfile recipe uses the official HTTPS URL. Pin the installer version in the URL if reproducibility is required. |
| PIA installer places files outside `/nix/` and survives garbage collection | Informational | This is by design. `/opt/piavpn/` is not a Nix derivation. `nixos-rebuild switch` will not remove it. Run `just pia-uninstall` to remove. |
| `wireguard` kernel module may not exist as a loadable module on kernels with `CONFIG_WIREGUARD=y` (built-in) | Low | `boot.kernelModules` is a no-op when the module is built-in; NixOS handles this gracefully. |
| nix-ld conflicts with vscode-fhs | None | `programs.nix-ld` and `pkgs.vscode-fhs` are orthogonal. vscode-fhs uses a BuildFHSEnv sandbox that does not depend on the system nix-ld shim. |
| `pia-client` and `piactl` wrapper names shadow potential future nixpkgs packages | Low | Check nixpkgs periodically. If an official `pia` package lands in nixpkgs, remove the wrappers from this module and install the package instead. |

---

## 10. Optional Enhancement: services.pia.autoStart (Not in Scope for Phase 2)

The `piavpn.service` systemd unit is installed by the PIA installer under
`/etc/systemd/system/piavpn.service`. It is not managed by NixOS's module system.

An optional NixOS module option could wrap it:

```nix
options.services.pia.autoStart = lib.mkOption {
  type    = lib.types.bool;
  default = false;
  description = "Start the PIA daemon automatically at boot via piavpn.service.";
};

config = lib.mkIf config.services.pia.autoStart {
  systemd.services.piavpn = {
    enable     = true;
    wantedBy   = [ "multi-user.target" ];
    after      = [ "network.target" ];
    # The actual unit file is placed by the PIA installer; this entry ensures
    # NixOS's activation enables/starts it. If the installer hasn't run yet,
    # this is a benign no-op (the unit file won't exist).
    serviceConfig.ExecStart = lib.mkDefault "/opt/piavpn/bin/pia-daemon";
  };
};
```

**Decision for Phase 2:** Exclude this. PIA's daemon is adequately managed via
`sudo systemctl start/stop piavpn` and the `just pia-background-on` / `pia-status` recipes.
Auto-start can be added in a follow-up if the user requests it.

---

## 11. Sources

1. [PIA Linux Client Download](https://www.privateinternetaccess.com/download/linux-vpn) — Official installer URL and installation instructions
2. [NixOS Wiki — nix-ld](https://nixos.wiki/wiki/Nix-ld) — nix-ld enabling, `programs.nix-ld.libraries` option format, library list pattern
3. [NixOS Options Search — programs.nix-ld](https://search.nixos.org/options?query=programs.nix-ld) — NixOS 25.11 option schema and defaults
4. [NixOS Discourse — Running PIA on NixOS](https://discourse.nixos.org/t/pia-vpn-on-nixos) — Community experiences with PIA on NixOS; iproute2/rt_tables requirement confirmed
5. [PIA GitHub — pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) — PIA's open-source manual connection scripts; confirms WireGuard usage and rt_tables dependency
6. [NixOS Wiki — iproute2](https://nixos.wiki/wiki/Iproute2) — `environment.etc."iproute2/rt_tables"` pattern for NixOS
7. [Qt6 on NixOS: nix-ld library list community reference](https://github.com/nix-community/nix-ld/issues) — Validated set of system libraries for Qt6 apps under nix-ld
