# Spec: Set Brave Browser as Default for All GNOME Roles

**Feature:** `brave_default_browser`  
**Author:** Research Subagent  
**Date:** 2026-04-24  
**Status:** Draft — ready for implementation

---

## 1. Current State Analysis

### 1.1 Roles Using GNOME

Four roles import `modules/gnome.nix` and therefore run the GNOME desktop:

| Role | Configuration file | Home Manager file | Imports gnome-common.nix |
|---|---|---|---|
| desktop | `configuration-desktop.nix` | `home-desktop.nix` | ✅ via `./home/gnome-common.nix` |
| htpc | `configuration-htpc.nix` | `home-htpc.nix` | ✅ via `./home/gnome-common.nix` |
| server | `configuration-server.nix` | `home-server.nix` | ✅ via `./home/gnome-common.nix` |
| stateless | `configuration-stateless.nix` | `home-stateless.nix` | ✅ via `./home/gnome-common.nix` |

The **headless-server** role (`configuration-headless-server.nix`) does **not** import
`modules/gnome.nix` and `home-headless-server.nix` does **not** import
`home/gnome-common.nix`. It has no desktop environment and no browser.

### 1.2 Where Brave Is Installed

`modules/packages-desktop.nix` installs `pkgs.brave` as a system package:

```nix
environment.systemPackages = with pkgs; [
  brave  # Chromium-based browser
];
```

This module is imported by `configuration-desktop.nix`, `configuration-htpc.nix`,
`configuration-server.nix`, and `configuration-stateless.nix` — exactly the four GNOME
roles. It is **not** imported by `configuration-headless-server.nix`.

### 1.3 Brave's .desktop File Name

Confirmed from the nixpkgs source for `pkgs.brave`
(`pkgs/by-name/br/brave/make-brave.nix`, nixos-25.11 branch):

```
substituteInPlace \
  $out/share/applications/{brave-browser,com.brave.Browser}.desktop \
  ...
```

The package installs **two** `.desktop` files:

| File | Usage |
|---|---|
| `brave-browser.desktop` | Primary entry; used by the existing dock favorites in `modules/gnome.nix` |
| `com.brave.Browser.desktop` | Reverse-DNS alias (added by Brave upstream for Flatpak compatibility) |

The correct filename to reference in `mimeapps.list` is **`brave-browser.desktop`**.
This is already confirmed by its appearance in the `favorite-apps` dconf key across
all four GNOME roles in `modules/gnome.nix`.

### 1.4 Current Default Browser Configuration

There is **no** `xdg.mimeApps`, `xdg.mime`, or `x-scheme-handler` configuration
anywhere in the repository. No `~/.config/mimeapps.list` is managed declaratively.
GNOME will fall back to whatever the first registered browser is — on a fresh
install this may be an unset key or Firefox if it was previously installed.

---

## 2. Problem Definition

On a fresh NixOS build of any GNOME role, clicking an `http://` or `https://` link
in any application (e.g. a mail client, terminal, or document viewer) will either:

- Open in a browser chosen arbitrarily by GNOME (often unset, resulting in a
  "no application to handle" error), or
- Open in a stale browser from a previous manual `xdg-settings set` invocation
  that was not preserved across rebuilds.

Brave is installed on every GNOME role and is already pinned as the first entry
in each role's dock favorites, signalling clear intent. However, no declarative
MIME handler registration backs this up.

**Goal:** Declare Brave as the default handler for all web-related MIME types on
every GNOME role, written reproducibly by Home Manager into
`~/.config/mimeapps.list`, so that the setting survives rebuilds and reboots
(including on the stateless role where the home directory is ephemeral).

---

## 3. How GNOME Picks Its Default Browser

GNOME's default application resolution follows the
[XDG MIME Applications Specification](https://specifications.freedesktop.org/mime-apps-spec/mime-apps-spec-latest.html):

1. **`~/.config/mimeapps.list`** — user-level overrides (highest priority)
2. **`/etc/xdg/mimeapps.list`** — system-level defaults
3. **`~/.local/share/applications/mimeapps.list`** — legacy location (still read)
4. XDG data dirs (`/run/current-system/sw/share/applications/*.desktop`) for
   `MimeType=` declarations inside installed `.desktop` files.

The GNOME Settings "Default Applications" panel reads and writes
`x-scheme-handler/http` and `x-scheme-handler/https` in `~/.config/mimeapps.list`.
Home Manager's `xdg.mimeApps` option owns `~/.config/mimeapps.list`, making it
the correct and authoritative mechanism.

---

## 4. Proposed Solution Architecture

### 4.1 Approach

Add `xdg.mimeApps` to `home/gnome-common.nix`.

**Rationale:**
- `home/gnome-common.nix` is the universal GNOME Home Manager base, imported by
  all four GNOME home files (`home-desktop.nix`, `home-htpc.nix`,
  `home-server.nix`, `home-stateless.nix`).
- The headless-server home file does **not** import it — so the setting will
  never be applied to the no-GNOME, no-browser role.
- No `lib.mkIf` guards are needed; the import list expresses role inclusion.
- This follows the project's **Option B** architecture rule: the universal base
  file contains settings that apply to all roles that import it; role-specific
  additions live in separate files.
- A single change in one file propagates correctly to all four GNOME roles.

### 4.2 File to Modify

```
home/gnome-common.nix
```

No other files require modification.

---

## 5. Implementation Steps

### 5.1 Exact Nix Code to Add

Add the following block to `home/gnome-common.nix`, after the existing
`dconf.settings` block (or anywhere in the attribute set — order is irrelevant
in Nix):

```nix
  # ── Default browser (Brave) ────────────────────────────────────────────────
  # Writes ~/.config/mimeapps.list so that xdg-open, GNOME, and all
  # XDG-compliant applications use Brave for web URLs and HTML files.
  # brave-browser.desktop is the primary .desktop file installed by pkgs.brave
  # (confirmed in pkgs/by-name/br/brave/make-brave.nix).
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html"                = "brave-browser.desktop";
      "application/xhtml+xml"   = "brave-browser.desktop";
      "x-scheme-handler/http"   = "brave-browser.desktop";
      "x-scheme-handler/https"  = "brave-browser.desktop";
      "x-scheme-handler/ftp"    = "brave-browser.desktop";
    };
  };
```

### 5.2 Placement in File

The block belongs immediately after the closing brace of `dconf.settings`, before
the final closing `}` of the module. The full file structure will be:

```
{ pkgs, lib, ... }:
{
  home.packages = ...;
  home.pointerCursor = ...;
  gtk.enable = ...;
  gtk.iconTheme = ...;
  gtk.cursorTheme = ...;
  dconf.settings = { ... };

  # ── Default browser (Brave) ────────────────────────────────────────────────
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html"                = "brave-browser.desktop";
      "application/xhtml+xml"   = "brave-browser.desktop";
      "x-scheme-handler/http"   = "brave-browser.desktop";
      "x-scheme-handler/https"  = "brave-browser.desktop";
      "x-scheme-handler/ftp"    = "brave-browser.desktop";
    };
  };
}
```

### 5.3 Generated Output

Home Manager will write `~/.config/mimeapps.list` containing:

```ini
[Default Applications]
text/html=brave-browser.desktop
application/xhtml+xml=brave-browser.desktop
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/ftp=brave-browser.desktop
```

---

## 6. MIME Types Chosen and Rationale

| MIME type | Reason |
|---|---|
| `x-scheme-handler/http` | HTTP URL handler — the primary key GNOME reads for "Default Web Browser" |
| `x-scheme-handler/https` | HTTPS URL handler — required separately from http |
| `text/html` | Locally opened `.html` files; also consulted by some apps when choosing a browser |
| `application/xhtml+xml` | XHTML documents; browsers handle these identically to HTML |
| `x-scheme-handler/ftp` | FTP URL handler; less common but still registered by browsers |

MIME types that are **intentionally excluded**:
- `x-scheme-handler/chrome` — Chromium internal protocol; not needed for default browser selection
- `application/x-extension-htm`, `application/x-extension-html`, etc. — non-standard aliases added by some browser packages; not part of the Freedesktop spec and not required by GNOME

---

## 7. Dependencies

No new Nix inputs or packages are required. `pkgs.brave` is already installed
via `modules/packages-desktop.nix` on all GNOME roles.

The Home Manager `xdg.mimeApps` option is part of the `home-manager` input already
declared in `flake.nix` with `inputs.nixpkgs.follows = "nixpkgs"`.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Home Manager file conflict: another activation already wrote `~/.config/mimeapps.list` manually | Low | `home-manager.backupFileExtension = "backup"` is already set in flake.nix; conflicting file will be renamed to `mimeapps.list.backup` at activation |
| GNOME's "Default Applications" panel overwrites `mimeapps.list` at runtime | Low–Medium | Any manual change the user makes via Settings will be overwritten by the next `nixos-rebuild switch` activation; this is expected and correct for a declarative config |
| Stateless role: `~/.config/mimeapps.list` is lost on reboot | N/A (mitigated) | The stateless role uses Home Manager which runs at each login session start via systemd, re-writing `mimeapps.list` before GNOME reads it |
| `brave-browser.desktop` not found at runtime | Very Low | The file is installed by `pkgs.brave` into `/run/current-system/sw/share/applications/`, which is on `XDG_DATA_DIRS`. If Brave is somehow not installed, xdg-open will fall back gracefully |
| Conflict with system-level `/etc/xdg/mimeapps.list` | None | No system-level mimeapps.list is written by this project; user-level (`~/.config/`) always takes precedence anyway |

---

## 9. Sources Consulted

1. **nixpkgs `make-brave.nix` (nixos-25.11)** — confirmed `.desktop` filenames
   `brave-browser.desktop` and `com.brave.Browser.desktop`:
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/by-name/br/brave/make-brave.nix

2. **Home Manager Options Reference (extranix, release-25.05)** — confirmed
   `xdg.mimeApps.enable`, `xdg.mimeApps.defaultApplications` option names and types:
   https://home-manager-options.extranix.com/?query=xdg.mimeApps

3. **NixOS Wiki — GNOME** — confirmed dconf configuration patterns and xdg
   integration in NixOS + Home Manager:
   https://wiki.nixos.org/wiki/GNOME

4. **Freedesktop XDG MIME Applications Specification** — authoritative source for
   `mimeapps.list` format, lookup order, and MIME type keys for browsers:
   https://specifications.freedesktop.org/mime-apps-spec/mime-apps-spec-latest.html

5. **Repository source analysis** — `modules/gnome.nix`, `home/gnome-common.nix`,
   `modules/packages-desktop.nix`, all four GNOME home files, and `flake.nix`
   to establish current state and architecture constraints.

6. **nixpkgs NixOS search (channel 25.11)** — confirmed `pkgs.brave` package
   availability and version (1.89.137 as of search date):
   https://search.nixos.org/packages?channel=25.11&query=brave

---

## 10. Summary

**One file changes:** `home/gnome-common.nix`

**What is added:** A `xdg.mimeApps` block that enables management of
`~/.config/mimeapps.list` and registers `brave-browser.desktop` as the default
handler for `x-scheme-handler/http`, `x-scheme-handler/https`, `text/html`,
`application/xhtml+xml`, and `x-scheme-handler/ftp`.

**Affected roles:** desktop, htpc, server, stateless (all GNOME roles).  
**Unaffected roles:** headless-server (no GNOME, no browser, does not import
`home/gnome-common.nix`).

**No new dependencies** are introduced. The change is minimal, idiomatic, and
aligned with the project's Option B architecture.
