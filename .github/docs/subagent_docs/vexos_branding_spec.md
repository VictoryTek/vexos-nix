# VexOS Branding Specification
**Feature:** Full OS identity branding for VexOS  
**Project:** vexos-nix — NixOS Flake (nixpkgs channel: `nixos-25.11`)  
**Target File:** `modules/branding.nix`  
**Date:** 2026-03-26  

---

## 1. Current State Analysis

### 1.1 What `modules/branding.nix` Currently Does

`modules/branding.nix` is imported unconditionally from `configuration.nix` and applies to all three host variants (`vexos-amd`, `vexos-nvidia`, `vexos-vm`). It currently handles:

| Concern | Option / Mechanism | Status |
|---|---|---|
| Plymouth boot splash theme | `boot.plymouth.theme = lib.mkDefault "spinner"` | ✅ Done |
| Plymouth watermark logo | `boot.plymouth.logo = ../files/plymouth/watermark.png` | ✅ Done |
| GNOME About-page logo icon | `system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo"` | ✅ Done |
| System pixmaps (distributor-logo, etc.) | `environment.systemPackages = [ vexosLogos vexosIcons ]` | ✅ Done |
| Hicolor icon theme entries for `vexos-logo` | `vexosIcons` derivation via `gtk-update-icon-cache` | ✅ Done |
| GDM login-screen logo | `programs.dconf.profiles.gdm` + `/etc/vexos/gdm-logo.png` | ✅ Done |

### 1.2 What Is Missing

| Concern | Current Value | Required Value |
|---|---|---|
| `NAME=` in `/etc/os-release` | `NixOS` | `VexOS` |
| `PRETTY_NAME=` in `/etc/os-release` | `NixOS 25.11 (Vicuna)` | `VexOS 25.11 (Vicuna)` |
| `ID=` in `/etc/os-release` | `nixos` | `vexos` |
| `ID_LIKE=` in `/etc/os-release` | _(absent — ID is "nixos")_ | `nixos` (auto-set when ID ≠ "nixos") |
| `VENDOR_NAME=` in `/etc/os-release` | `NixOS` | `VexOS` |
| `HOME_URL=` in `/etc/os-release` | `https://nixos.org/` | custom project URL (or empty) |
| `DISTRIB_ID=` in `/etc/lsb-release` | `nixos` | `vexos` |
| GRUB menu entry primary label | `NixOS` | `VexOS` |
| systemd-boot menu entry label | `NixOS` | `VexOS` |
| EFI NVRAM bootloader ID | `NixOS/boot-efi` | `VexOS/boot-efi` |
| `hostnamectl` OS field | `NixOS 25.11 (Vicuna)` | `VexOS 25.11 (Vicuna)` |

### 1.3 Existing `system.nixos.*` Usage

```nix
# modules/branding.nix (current)
system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo";
```

This sets `LOGO=vexos-logo` in `/etc/os-release`. It is the only existing use of
`system.nixos.*` options in the project.

---

## 2. Problem Definition

The operating system is still identified as **NixOS** at multiple system levels:

1. **`/etc/os-release`** — `NAME`, `PRETTY_NAME`, `ID`, `VENDOR_NAME`, and `HOME_URL` all
   reference NixOS. Tools like `hostnamectl`, `neofetch`, `inxi`, `GNOME Settings → About`,
   and any script that sources `/etc/os-release` will report "NixOS" instead of "VexOS".

2. **GRUB boot menu** — The primary menu entry is labeled `NixOS` (derived from
   `@distroName@` in `install-grub.pl`). All generation sub-entries follow the pattern
   `NixOS - Configuration N` or `NixOS - All configurations`.

3. **systemd-boot** — The `distroName` string is substituted into the systemd-boot Python
   builder at build time; entries show "NixOS [Generation N]" rather than "VexOS".

4. **`/etc/lsb-release`** — `DISTRIB_ID` and `DISTRIB_DESCRIPTION` reference NixOS.

---

## 3. NixOS Option Research

### 3.1 Source: `nixos/modules/misc/version.nix` (nixos-25.11 branch)

All branding options are defined in this module. They are marked `internal = true`, which
only hides them from NixOS documentation generation — they can be freely assigned in any
NixOS module.

| Option | Type | Default | Effect on `/etc/os-release` |
|---|---|---|---|
| `system.nixos.distroName` | `str` | `"NixOS"` | `NAME=`, `PRETTY_NAME=` prefix |
| `system.nixos.distroId` | `str` | `"nixos"` | `ID=`, `DEFAULT_HOSTNAME=`; triggers `ID_LIKE=nixos` when ≠ "nixos" |
| `system.nixos.vendorName` | `str` | `"NixOS"` | `VENDOR_NAME=` |
| `system.nixos.vendorId` | `str` | `"nixos"` | `VENDOR_URL=` and `CPE_NAME=` |
| `system.nixos.extraOSReleaseArgs` | `attrsOf str` | `{}` | Merged last, can override any field |
| `system.nixos.extraLSBReleaseArgs` | `attrsOf str` | `{}` | Merged into `/etc/lsb-release` |
| `system.nixos.variantName` | `nullOr str` | `null` | `VARIANT=` (optional) |
| `system.nixos.variant_id` | `nullOr (strMatching ...)` | `null` | `VARIANT_ID=` (optional) |

#### Key logic in `version.nix` (relevant excerpt):

```nix
let
  isNixos = cfg.distroId == "nixos";
in {
  NAME        = "${cfg.distroName}";
  ID          = "${cfg.distroId}";
  ID_LIKE     = optionalString (!isNixos) "nixos";   # auto-set when distroId ≠ "nixos"
  VENDOR_NAME = cfg.vendorName;
  PRETTY_NAME = "${cfg.distroName} ${cfg.release} (${cfg.codeName})";
  HOME_URL    = optionalString isNixos "https://nixos.org/";   # empty when distroId ≠ "nixos"
  ANSI_COLOR  = optionalString isNixos "0;38;2;126;186;228";  # empty when distroId ≠ "nixos"
  ...
} // cfg.extraOSReleaseArgs   # merged last — can override any field above
```

**Critical:** Setting `distroId = "vexos"` causes `HOME_URL` and `ANSI_COLOR` to become
empty strings (removed from the file entirely) unless explicitly set via `extraOSReleaseArgs`.

### 3.2 Source: `nixos/modules/system/boot/loader/grub/grub.nix` + `install-grub.pl`

**How GRUB labels are generated:**

- `@distroName@` in `install-grub.pl` is substituted at build time with
  `config.system.nixos.distroName`.
- The **primary GRUB menu entry** is: `addGeneration("@distroName@", ...)` → `"VexOS"`
- Generation sub-entries: `"@distroName@ - Configuration N"` → `"VexOS - Configuration N"`
- Profile sub-menu: `"@distroName@ - All configurations"` → `"VexOS - All configurations"`
- The **EFI bootloader ID** (stored in NVRAM) is:
  `"${config.system.nixos.distroName}${efiSysMountPoint}"` → e.g., `"VexOS-boot-efi"`

**`boot.loader.grub.configurationName`** (separate option, default `""`):

- Writes the content of the `configuration-name` file into each system profile.
- Used only for per-generation sub-entry labeling (the `$entryName` part).
- If set to `"VexOS"`, sub-entries show `"VexOS - VexOS"` (redundant, do NOT set this).
- **Recommendation:** Leave at default `""` — sub-entries will use the generation date/version.

**`boot.loader.grub.entryOptions`** (default `"--class nixos --unrestricted"`):

- The `--class nixos` tag references a GRUB2 theme CSS class, not the display label.
- Does not affect visible menu text. Safe to leave as-is unless a custom GRUB theme is added.

### 3.3 Source: `nixos/modules/system/boot/loader/systemd-boot/systemd-boot.nix`

```nix
replacements = {
  ...
  inherit (config.system.nixos) distroName;
  ...
};
```

`distroName` is substituted into the systemd-boot Python builder script at build time.
Setting `system.nixos.distroName = "VexOS"` therefore changes systemd-boot menu labels
for all NixOS generations to "VexOS [Generation N]".

---

## 4. Proposed Solution

### 4.1 Architecture Decision

**Do not use `environment.etc."os-release".text`** to override `/etc/os-release` directly.
Doing so would:
- Bypass the NixOS module merge system
- Require manually specifying every field (fragile, error-prone)
- Break future nixpkgs updates that add new os-release fields

**Instead, use the declarative `system.nixos.*` options** to set the distro identity, and
`extraOSReleaseArgs` only for fields that have conditional logic (e.g., `HOME_URL`, `ANSI_COLOR`).

### 4.2 Exact NixOS Options and Values

Add the following to `modules/branding.nix`:

```nix
# ── OS identity — /etc/os-release, GRUB/systemd-boot labels ─────────────────
# system.nixos.distroName: sets NAME=, PRETTY_NAME= prefix in /etc/os-release
# AND the primary label in GRUB and systemd-boot menu entries.
# Marked internal=true in NixOS but fully supported for override.
system.nixos.distroName = "VexOS";

# system.nixos.distroId: sets ID= in /etc/os-release.
# Setting this to anything other than "nixos" automatically adds ID_LIKE=nixos
# (correct for a NixOS-based derivative) and sets DEFAULT_HOSTNAME=vexos.
system.nixos.distroId = "vexos";

# system.nixos.vendorName / vendorId: set VENDOR_NAME= and appear in CPE_NAME=.
system.nixos.vendorName = "VexOS";
system.nixos.vendorId   = "vexos";

# Additional os-release fields.
# HOME_URL and ANSI_COLOR are conditionally emitted only when distroId == "nixos",
# so we must set them explicitly now that distroId = "vexos".
# LOGO is already set; retain it here for clarity and consolidation.
system.nixos.extraOSReleaseArgs = {
  LOGO       = "vexos-logo";
  HOME_URL   = "https://github.com/your-username/vexos-nix";
  ANSI_COLOR = "0;38;2;126;186;228";   # inherit NixOS blue; change if desired
};
```

> **Note on `extraOSReleaseArgs` merge behavior:** The existing line
> `system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo"` and the new block
> `system.nixos.extraOSReleaseArgs = { ... }` are both valid in Nix's module system —
> both are merged as attrset options. The final `/etc/os-release` will contain all keys.
> However, the spec recommends consolidating them into a single block to eliminate
> duplication and make the intent explicit.

### 4.3 Expected `/etc/os-release` After Change

```ini
NAME=VexOS
ID=vexos
ID_LIKE=nixos
VENDOR_NAME=VexOS
VERSION=25.11 (Vicuna)
VERSION_CODENAME=vicuna
VERSION_ID=25.11
BUILD_ID=25.11.<hash>
PRETTY_NAME=VexOS 25.11 (Vicuna)
CPE_NAME=cpe:/o:vexos:vexos:25.11
LOGO=vexos-logo
HOME_URL=https://github.com/your-username/vexos-nix
ANSI_COLOR=0;38;2;126;186;228
DEFAULT_HOSTNAME=vexos
SUPPORT_END=2026-06-30
```

### 4.4 Expected `/etc/lsb-release` After Change

```ini
LSB_VERSION=25.11 (Vicuna)
DISTRIB_ID=vexos
DISTRIB_RELEASE=25.11
DISTRIB_CODENAME=vicuna
DISTRIB_DESCRIPTION=VexOS 25.11 (Vicuna)
```

### 4.5 Expected GRUB Menu (After Change)

```
VexOS                                          ← primary entry (was: NixOS)
VexOS - Configuration 42 (2026-03-26 - ...)   ← generation sub-entry
VexOS - All configurations                    ← generation sub-menu
```

---

## 5. Implementation Steps

### Step 1 — Edit `modules/branding.nix`

**Location:** `/home/nimda/Projects/vexos-nix/modules/branding.nix`

**Action:** Replace the existing single-line `system.nixos.extraOSReleaseArgs.LOGO` with a
consolidated block that includes `distroName`, `distroId`, `vendorName`, `vendorId`, and
the full `extraOSReleaseArgs` attrset.

**Find (existing line, near bottom of the `{ ... }` block):**
```nix
  system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo";
```

**Replace with:**
```nix
  # ── OS identity (os-release, GRUB/systemd-boot labels, hostnamectl) ───────
  # distroName: overrides NAME/PRETTY_NAME in /etc/os-release AND the
  # primary label in both GRUB and systemd-boot boot menu entries.
  system.nixos.distroName = "VexOS";

  # distroId: overrides ID= in /etc/os-release.  When set to anything other
  # than "nixos", NixOS automatically adds ID_LIKE=nixos — correct for a
  # NixOS-based derivative.  Also sets DEFAULT_HOSTNAME= to this value.
  system.nixos.distroId = "vexos";

  # vendorName/vendorId: sets VENDOR_NAME= and appears in CPE_NAME= field.
  system.nixos.vendorName = "VexOS";
  system.nixos.vendorId   = "vexos";

  # HOME_URL and ANSI_COLOR are emitted by NixOS only when distroId == "nixos".
  # We must set them explicitly now that distroId = "vexos".
  system.nixos.extraOSReleaseArgs = {
    LOGO       = "vexos-logo";
    HOME_URL   = "https://github.com/your-username/vexos-nix";
    ANSI_COLOR = "0;38;2;126;186;228";
  };
```

**No other files need to be edited.** `modules/branding.nix` is imported by
`configuration.nix`, which is imported by all three host configs
(`hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/vm.nix`). The change propagates to all
three flake outputs automatically.

---

## 6. Files to Be Modified

| File | Change |
|---|---|
| `modules/branding.nix` | Add `distroName`, `distroId`, `vendorName`, `vendorId`; consolidate `extraOSReleaseArgs` |

No other files require modification.

---

## 7. Files NOT to Be Modified

| File | Reason |
|---|---|
| `flake.nix` | No naming changes needed at the flake outputs level |
| `configuration.nix` | Already imports `modules/branding.nix`; no change needed |
| `hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/vm.nix` | Branding is shared; no host-specific override needed |
| `modules/performance.nix` | Plymouth `enable` flag lives here intentionally (per existing comment) |

---

## 8. Risks and Mitigations

### Risk 1 — EFI NVRAM bootloader entry change (MEDIUM)

**What happens:** On a UEFI system with `boot.loader.efi.canTouchEfiVariables = true`, the
GRUB installer uses `system.nixos.distroName` as the `--bootloader-id` argument to
`grub-install`. Changing `distroName` from `"NixOS"` to `"VexOS"` causes a new
`"VexOS"` entry to be created in EFI NVRAM on the next `nixos-rebuild switch`. The old
`"NixOS"` entry becomes an orphan (still present in NVRAM, points to old GRUB EFI binary).

**Mitigation:** After the first `nixos-rebuild switch`, run:
```bash
efibootmgr  # list entries and find the old NixOS entry number
sudo efibootmgr --delete-bootnum --bootnum XXXX  # delete the orphan
```
This is cosmetic only — the system boots correctly from the new "VexOS" entry either way.

**VM variant note:** `hosts/vm.nix` uses GRUB in BIOS or UEFI mode depending on the VM
host. EFI NVRAM is typically not writable in VMs (no `canTouchEfiVariables`), so this risk
only applies to real hardware.

### Risk 2 — Scripts that check for `ID=nixos` (LOW)

**What happens:** Some scripts (nixos-rebuild, nix CLI wrappers, nixos-install) check
`/etc/os-release` `ID=nixos` to confirm they are running on NixOS. Setting `ID=vexos`
would cause these checks to fail.

**Mitigation:** NixOS sets `ID_LIKE=nixos` automatically when `distroId != "nixos"`.
All NixOS tooling and most well-written scripts check `ID_LIKE` in addition to `ID`.
The ones that do not (if any) are bugs in those scripts; `ID_LIKE=nixos` is the correct
FreeDesktop convention for this purpose.

**Verification:** After applying, confirm `nixos-rebuild switch` still works (it does — it
does not check os-release at all; it uses the nix-daemon and flake CLI).

### Risk 3 — Nix module merge conflict with existing `extraOSReleaseArgs` (LOW)

**What happens:** The current `branding.nix` sets:
```nix
system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo";
```
The proposed change replaces this with a full attrset including `LOGO`. If the
replacement is the only assignment, there is no conflict.

**Mitigation:** Delete the old single-attribute line and replace it with the full `extraOSReleaseArgs = { ... }` block. The Nix module system merges `attrsOf` types, but having two assignments for the same key (e.g., `LOGO`) with different priorities would trigger a conflict warning. Use a single consolidated block.

### Risk 4 — `SUPPORT_URL` and `BUG_REPORT_URL` fields (INFORMATIONAL)

The version.nix code uses a truncated `VENDOR_URL = opt...` — the full logic is
`VENDOR_URL = optionals (cfg.vendorId == ...) ...`. These fields are populated via the
nixpkgs `VENDOR_URL` option which inherits from the `vendorId`. Setting
`vendorId = "vexos"` may clear the `SUPPORT_URL`/`BUG_REPORT_URL` fields that were
previously pointing to nixos.org. Add them to `extraOSReleaseArgs` if needed:
```nix
BUG_REPORT_URL = "https://github.com/your-username/vexos-nix/issues";
```

### Risk 5 — NixOS version constraints (NONE)

All options used in this spec (`system.nixos.distroName`, `system.nixos.distroId`,
`system.nixos.vendorName`, `system.nixos.vendorId`, `system.nixos.extraOSReleaseArgs`)
were verified present in:
- `nixos-25.11` branch of nixpkgs (confirmed via GitHub source of `version.nix`)

The project `flake.nix` uses `nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"` and
`system.stateVersion = "25.11"`. These options are safe and available on 25.11.

> **Discrepancy note:** `copilot-instructions.md` states "NixOS 25.05" but the actual
> `flake.nix` and `configuration.nix` both use `nixos-25.11`. This spec targets 25.11.

---

## 9. Out of Scope

The following items are explicitly NOT part of this spec:

- **GRUB splash image / background** — handled separately by the GRUB splash image option
- **Custom GRUB theme** (`boot.loader.grub.theme`) — separate concern
- **Boot kernel parameters** (`quiet`, `splash`) — handled in `modules/performance.nix`
- **Plymouth theme selection** — already done in `modules/branding.nix`
- **GDM logo / desktop theming** — already done in `modules/branding.nix`
- **`boot.loader.grub.configurationName`** — should remain at default `""` to avoid
  redundant labels like `"VexOS - VexOS"` in generation sub-entries
- **`boot.loader.grub.entryOptions`** — the `--class nixos` CSS class does not affect
  visible text and requires a matching GRUB theme to matter; leave at default

---

## 10. Sources Consulted

1. **NixOS nixpkgs source — `nixos/modules/misc/version.nix` (nixos-25.11):**  
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/misc/version.nix  
   Primary source for `system.nixos.*` option definitions and os-release generation logic.

2. **NixOS nixpkgs source — `nixos/modules/system/boot/loader/grub/grub.nix` (nixos-25.11):**  
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/system/boot/loader/grub/grub.nix  
   Confirmed `boot.loader.grub.configurationName` definition, EFI bootloader ID logic,
   and `system.nixos.distroName` usage.

3. **NixOS nixpkgs source — `install-grub.pl` (nixos-25.11):**  
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/system/boot/loader/grub/install-grub.pl  
   Confirmed `@distroName@` template substitution for GRUB menu entry labels.

4. **NixOS nixpkgs source — `systemd-boot.nix` (nixos-25.11):**  
   https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/system/boot/loader/systemd-boot/systemd-boot.nix  
   Confirmed `inherit (config.system.nixos) distroName` in `replacements` — distroName
   is substituted into systemd-boot Python builder.

5. **NixOS Option Search (25.11):**  
   https://search.nixos.org/options?channel=25.11&query=system.nixos  
   Confirmed available options: `variant_id`, `variantName`, `tags`, `release`, `label`, `codeName`.

6. **NixOS Option Search — `boot.loader.grub.configurationName`:**  
   https://search.nixos.org/options?channel=25.11&query=boot.loader.grub.configurationName  
   Confirmed option exists with default `""` and example `"Stable 2.6.21"`.

7. **NixOS Wiki — Plymouth:**  
   https://wiki.nixos.org/wiki/Plymouth  
   Confirmed boot splash configuration patterns.

8. **FreeDesktop os-release(5) specification:**  
   https://www.freedesktop.org/software/systemd/man/os-release.html  
   Reference for `ID`, `ID_LIKE`, `NAME`, `PRETTY_NAME`, `VENDOR_NAME` field semantics.
   `ID_LIKE` is the correct mechanism for derived distributions.

---

## 11. Summary

**The entire VexOS OS-identity branding change is a single-file edit to `modules/branding.nix`.**

Add four new `system.nixos.*` options and consolidate `extraOSReleaseArgs`:

```nix
system.nixos.distroName = "VexOS";
system.nixos.distroId   = "vexos";
system.nixos.vendorName = "VexOS";
system.nixos.vendorId   = "vexos";

system.nixos.extraOSReleaseArgs = {
  LOGO       = "vexos-logo";
  HOME_URL   = "https://github.com/your-username/vexos-nix";
  ANSI_COLOR = "0;38;2;126;186;228";
};
```

This propagates to:
- `/etc/os-release` → `NAME=VexOS`, `PRETTY_NAME=VexOS 25.11 (Vicuna)`, `ID=vexos`, `ID_LIKE=nixos`
- `/etc/lsb-release` → `DISTRIB_ID=vexos`, `DISTRIB_DESCRIPTION=VexOS 25.11 (Vicuna)`
- **GRUB menu** → primary entry `VexOS`, sub-entries `VexOS - Configuration N`
- **systemd-boot menu** → entries labeled `VexOS [Generation N]`
- **`hostnamectl`** → `Operating System: VexOS 25.11 (Vicuna)`
- **GNOME Settings → About** → distro name `VexOS` with `vexos-logo` icon
