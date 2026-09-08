# Limine Bootloader Branding — Spec

Feature name: `limine_branding`
Date: 2026-09-08

---

## 1. Current state analysis

### What renders today

`modules/system.nix:90-104` enables Limine with **zero styling**:

```nix
(lib.mkIf (config.vexos.bootloader == "limine") {
  boot.loader.systemd-boot.enable = false;
  boot.loader.limine = {
    enable         = true;
    efiSupport     = true;
    maxGenerations = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
})
```

Everything visible on the boot screen is therefore a **nixpkgs / upstream Limine default**:

| Screen element | Source | Confirmed via |
|---|---|---|
| Grey border frame | `term_margin` — upstream default is `64` **when a wallpaper is displayed** | Limine `CONFIG.md` (trunk) |
| Solid black slab over the wallpaper | `term_background` — upstream default `00000000` (TT=`00` → fully **opaque**) | Limine `CONFIG.md` |
| NixOS snowflake + "NixOS" text, top-left | Baked into the default wallpaper PNG (`pkgs.nixos-artwork.wallpapers.simple-dark-gray-bootloader`) | `limine.nix:40` in nixpkgs (`defaultWallpaper`) |
| Dark-grey background | That same default wallpaper, `wallpaperStyle = "stretched"`, `backdrop = "2F302F"` | `limine.nix:396-400` (both are `mkDefault`, gated on `wallpapers == [ defaultWallpaper ]`) |
| "Limine 12.5.2 (x86-64, UEFI)" cyan title | `interface_branding` — upstream default is the Limine version string; default colour `00aaaa` | Limine `CONFIG.md` |
| Green "ARROWS Select / ENTER Boot / S Firmware Setup" | `interface_help` — default colour `00aa00` | Limine `CONFIG.md` |
| "[-] VexOS Desktop default profile" entry title | Already branded — `limine-install.py` derives it from the profile name; `system.nixos.distroName` = "VexOS Desktop" (set in `modules/branding.nix`) | `modules/branding.nix` |
| Bottom "NixOS Yarara 26.05…(Linux 6.18.43)…" line | The selected entry's generated comment string — **not a style knob**, emitted by `limine-install.py` | `limine-install.py` |

### How NixOS exposes Limine styling

`boot.loader.limine.style.*` — all options are `nullOr str` / `nullOr int` with **no default**, passed straight through to `limine.conf` by
`nixos/modules/system/boot/loader/limine/limine-install.py:473-492`.

Relevant options (verified against the installed nixpkgs module and Limine `CONFIG.md`):

| NixOS option | `limine.conf` key | Format |
|---|---|---|
| `style.wallpapers` (list of path) | `wallpaper:` (one line per entry, random pick if >1) | BMP / PNG / JPEG / QOI |
| `style.wallpaperStyle` | `wallpaper_style` | `tiled` \| `centered` \| `stretched` (default `stretched`) |
| `style.backdrop` | `backdrop` | `RRGGBB` — fill for area not covered when style = `centered` |
| `style.interface.branding` | `interface_branding` | free string |
| `style.interface.brandingColor` | `interface_branding_colour` | `RRGGBB` hex (default `00aaaa`) |
| `style.interface.helpColor` | `interface_help_colour` | `RRGGBB` hex (default `00aa00`) |
| `style.interface.helpColorBright` | `interface_help_colour_bright` | `RRGGBB` hex |
| `style.interface.helpHidden` | `interface_help_hidden` | bool |
| `style.graphicalTerminal.background` | `term_background` | `TTRRGGBB` — **TT `00` = opaque, `FF` = fully transparent** |
| `style.graphicalTerminal.foreground` | `term_foreground` | `RRGGBB` |
| `style.graphicalTerminal.margin` | `term_margin` | int px (default `0`, or `64` with a wallpaper) |
| `style.graphicalTerminal.marginGradient` | `term_margin_gradient` | int px, clamped to `term_margin` |

> Setting `style.wallpapers` to anything other than `[ defaultWallpaper ]` disables the module's
> `mkDefault` for `backdrop` and `wallpaperStyle` (`limine.nix:398`), so both must be set explicitly here.

### Module import graph (relevant)

- `modules/branding.nix` — **universal**, imported by all 5 real roles
  (`configuration-{desktop,htpc,server,headless-server,stateless}.nix`). Owns Plymouth *theme + logo*,
  `system.nixos.distroName`, os-release, pixmaps. Its header explicitly states: *"Plymouth enable is
  deliberately kept in modules/system.nix. This module only sets the theme and logo (branding concerns)."*
  Already contains a bootloader-gated block:
  `boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable …`
- `modules/branding-display.nix` — display-only (GDM logo, GNOME wallpapers). **Not** imported by
  headless-server. Wrong home for Limine styling (Limine can be used on headless hosts).
- `modules/system.nix` — universal; declares `vexos.bootloader` enum and owns bootloader *enablement*.
- `configuration-vanilla.nix` — imports **neither** branding.nix nor system.nix; sets
  `boot.loader.systemd-boot.enable` directly. Not affected by this change.
- `assetRole` mapping in branding.nix: `headless-server` → `server` for all asset lookups
  (pixmaps, background_logos, plymouth). Limine assets will follow the same rule.

### Brand assets available

- `files/pixmaps/<role>/vex.png` — 455×164 RGBA, the full VexOS lockup **with a role banner**
  ("SERVER", "HTPC", "STATELESS"; desktop has no banner). Per-role, distinct files. Already deployed
  by branding.nix.
- `files/pixmaps/<role>/system-logo-white.png` — 107×128, the bare shield, identical across roles.
- Authoritative brand palette — **VexOS Neo-Cyberpunk**, documented in `files/ghostty/config`:
  - Canvas / darkest: `#0B1526` (ANSI 0), deep navy `#142230`, `#16233A`
  - Primary cyan accent: `#05F4FA` (cursor colour), bright `#7FF9FC`
  - Teal: `#0298BA`, `#0E7A8C`
  - Foreground text: `#E7EEF5`, muted `#B9C8DA`

### Tooling

- No Nix on Windows; WSL Ubuntu has Nix 2.34.1 (validates everything except `nixos-rebuild`).
- WSL `nixpkgs`: `imagemagick` 7.1.2-13, `librsvg` 2.61.3 available.

---

## 2. Problem definition

The Limine boot menu, when a host opts into `vexos.bootloader = "limine"`, shows **NixOS branding**
(snowflake logo, "Limine <version>" title, default grey wallpaper) and a heavy **opaque black slab**
covering most of the wallpaper. It does not look like part of VexOS.

Requirements (from the user):

1. Make the Limine screen visually part of the VexOS project — brand colours, VexOS logo, dark theme.
2. Reduce / remove the opaque black slab so the wallpaper is actually visible.
3. Claude produces a wallpaper for now (composite the existing VexOS logo on a dark canvas); the user
   may replace it with custom art later — so the wallpaper must be a **plain file at a predictable
   path**, not a generated derivation.
4. Purely additive: no host changes behaviour unless it already sets `vexos.bootloader = "limine"`.
   (Consistent with `limine_bootloader_option_spec.md` — this repo manages 30 deployed configs.)

### Non-goals

- No change to `interface_help` visibility — the help line stays (the Limine menu is where
  `modules/boot-discovery.nix` injects other-disk OS entries, so the keybind hints are useful);
  it is only recoloured to the brand palette.
- No `resolution` / `interface.resolution` / `term_font_scale` — hardware-dependent, not requested.
- No secure-boot / signing changes.
- The bottom entry-comment line ("…Yarara 26.05 (Linux …)") is not styleable and is left as-is.

---

## 3. Proposed solution architecture

### 3.1 New assets — `files/limine/<assetRole>/wallpaper.png`

Four files (`desktop`, `htpc`, `server`, `stateless`), mirroring `files/plymouth/`. `headless-server`
reuses `server` via the existing `assetRole` mapping.

- **Canvas:** 2560×1440, opaque, solid `#0B1526` (brand canvas colour).
- **Logo:** the role's `files/pixmaps/<role>/vex.png`, scaled to 1100 px wide (preserve aspect),
  composited centred horizontally, with its vertical centre at 32 % of canvas height (well above the
  vertically-centred entry list, below the Limine title line).
- **Format:** 24/32-bit PNG. Target < 200 KB each (flat background compresses well; run through
  `magick … -strip` and, if available, `pngquant`/`oxipng` — optional, cosmetic).
- **Generation (one-time, documented in a comment + here):**

  ```bash
  # Run from repo root inside WSL (imagemagick from nixpkgs).
  for role in desktop htpc server stateless; do
    mkdir -p "files/limine/$role"
    nix run nixpkgs#imagemagick -- -size 2560x1440 xc:'#0B1526' \
      \( "files/pixmaps/$role/vex.png" -resize 1100x \) \
      -gravity North -geometry +0+340 -composite \
      -strip "files/limine/$role/wallpaper.png"
  done
  ```

  (`+0+340`: North gravity puts the image top edge 340 px down; with a ~396 px-tall scaled logo its
  centre lands at ≈538 px ≈ 37 % — adjusted during implementation to hit ~32 % visual centre.)

These are committed static PNGs. A user replacing `files/limine/<role>/wallpaper.png` with their own
art needs no code change.

### 3.2 `modules/branding.nix` — styling block

Follows the Plymouth split already in this file: `system.nix` enables the bootloader, `branding.nix`
owns its look. Guarded by `lib.mkIf (config.vexos.bootloader == "limine")` — the **CLAUDE.md Option-B
carve-out**: gating by an option a sibling module (always imported alongside) declares, exactly like
the existing `lib.mkIf config.boot.loader.systemd-boot.enable` block in this same file. Not
role-smuggling.

Add to the `let` block (next to `plymouthDir`):

```nix
limineDir = ../files/limine + "/${assetRole}";
```

Add to `config` (new section, after the Plymouth block):

```nix
# ── Limine bootloader styling ─────────────────────────────────────────────
# Applies only when this host uses Limine (vexos.bootloader = "limine",
# declared in modules/system.nix). Mirrors the Plymouth split above:
# system.nix enables the bootloader, this module owns its branding.
# Upstream (nixpkgs limine.nix) otherwise ships the NixOS logo wallpaper and
# an opaque black terminal slab — replaced here with the VexOS Neo-Cyberpunk
# palette (see files/ghostty/config) and a per-role VexOS wallpaper.
boot.loader.limine.style = lib.mkIf (config.vexos.bootloader == "limine") {
  wallpapers     = [ (limineDir + "/wallpaper.png") ];
  wallpaperStyle = "stretched";
  # Fallback fill (only used if a display forces "centered"); matches the
  # wallpaper's own background so any letterboxing is seamless.
  backdrop       = "0B1526";

  interface = {
    branding        = "VexOS";
    brandingColor   = "05F4FA";  # brand cyan
    helpColor       = "0298BA";  # brand teal
    helpColorBright = "05F4FA";  # brand cyan (auto-boot countdown digit)
  };

  graphicalTerminal = {
    # TT=CC → ~80% transparent: removes the opaque black slab, leaves a
    # faint navy scrim so menu text stays legible over the wallpaper.
    background = "CC0B1526";
    foreground = "E7EEF5";  # brand foreground
  };
};
```

`term_margin` is deliberately left unset — upstream's `64 px` (applied because a wallpaper is present)
frames the screen and needs no override.

### 3.3 Behaviour for the 30 current configs

All 30 `nixosConfigurations` default to `vexos.bootloader = "systemd-boot"`, so the new `mkIf` block
evaluates to `{}` for every one of them. No wallpaper is added to any closure that doesn't use Limine.
CI (`nix eval` of each toplevel) is unaffected in output; it only gains eval coverage of the new
`let` binding and (inert) attrset.

---

## 4. Implementation steps

1. **Create assets.** Generate the four `files/limine/<role>/wallpaper.png` files with the ImageMagick
   command in §3.1 (tuning the logo size / offset by eye against the reference screenshot).
   → verify: `file files/limine/*/wallpaper.png` reports `PNG image data, 2560 x 1440`; visually
   inspect each (logo centred, dark navy field, role banner legible).
2. **Edit `modules/branding.nix`:** add the `limineDir` `let` binding and the
   `boot.loader.limine.style` block from §3.2.
   → verify: `nixpkgs-fmt --check modules/branding.nix` clean (or run `nixpkgs-fmt` on it).
3. **Eval — default path (systemd-boot):**
   `nix eval --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath`
   → verify: succeeds; block is inert.
4. **Eval — Limine path:** force the toggle and confirm the style attrs resolve and the wallpaper
   path is a valid store path, e.g.
   `nix eval --impure --expr '(import ./flake.nix) …'` overriding `vexos.bootloader = "limine"`, or
   the equivalent `nixos-rebuild dry-build` on the review host if one runs Limine.
   → verify: `config.boot.loader.limine.style.interface.branding == "VexOS"` and
   `config.boot.loader.limine.style.wallpapers` is a one-element list of an existing PNG.
5. **Structure:** `nix flake show --impure` → 30 `nixosConfigurations` still listed.
6. **Preflight:** `bash scripts/preflight.sh` (WSL) → exit 0 (dry-build stage self-skips without
   `/etc/nixos`; formatting + flake-show + secret scan + eval stages must pass).

---

## 5. Dependencies

- **No new flake inputs.** No new runtime packages. `imagemagick` is used once, ad-hoc, in WSL to
  author the committed PNGs — it does not enter any system closure.
- **No Context7 lookup required** — no new external library or versioned API is being integrated.
  Limine config-key formats were verified directly against Limine `CONFIG.md` (trunk) and the
  installed nixpkgs `limine.nix` / `limine-install.py`.

---

## 6. Configuration changes

| File | Change |
|---|---|
| `files/limine/desktop/wallpaper.png` | **new** — 2560×1440 PNG, VexOS lockup on `#0B1526` |
| `files/limine/htpc/wallpaper.png` | **new** — same, HTPC banner |
| `files/limine/server/wallpaper.png` | **new** — same, SERVER banner (also used by headless-server) |
| `files/limine/stateless/wallpaper.png` | **new** — same, STATELESS banner |
| `modules/branding.nix` | `let`: add `limineDir`; `config`: add `boot.loader.limine.style` block (`lib.mkIf` bootloader == "limine") |

No changes to `configuration-*.nix`, `hosts/`, `flake.nix`, `flake.lock`, `system.stateVersion`, or CI.

---

## 7. Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `term_background` transparency byte interpreted opposite to expectation | Low | Cosmetic — slab gets *more* opaque, not less | Confirmed `00`=opaque / `FF`=transparent in Limine `CONFIG.md` **and** the nixpkgs option description ("TT is transparency"). `CC` = ~80% transparent. Trivially flipped if wrong. |
| `brandingColor` / `helpColor` expected as a `0-7` index by an older Limine | Low | Title/help render wrong colour or literal string | Current Limine (screenshot shows 12.5.2) and nixpkgs `limine.nix` option docs both specify `RRGGBB` hex. Older 0-7 index scheme is pre-v8. |
| `stretched` distorts the logo on non-16:9 displays | Medium | Minor — logo slightly squished; solid background unaffected | Acceptable for a boot screen; most VexOS hardware is 16:9. `centered` + `backdrop` is a documented drop-in follow-up if it bothers the user. |
| Limine PNG decoder chokes on the file | Low | Limine falls back to `backdrop` colour (`0B1526`) — still on-brand, no boot failure | Use a plain 24/32-bit non-interlaced PNG (`-strip`), the format `nixos-artwork` wallpapers themselves use. |
| Four binary blobs in git | Certain | Repo size +~0.5 MB total | Matches existing precedent exactly (`files/plymouth/*/watermark.png`, `files/pixmaps/*/*.png`). Kept < 200 KB each. |
| Someone reads the `mkIf` guard as role-smuggling under Option B | Low | Review friction | Explicitly the documented carve-out (gating on an option a sibling module declares); identical pattern to the `systemd-boot.extraInstallCommands` block already in `branding.nix`. Noted in the code comment. |
| `config.vexos.bootloader` unavailable where `branding.nix` is imported | None | eval error | Verified: every `configuration-*.nix` that imports `branding.nix` also imports `system.nix` (which declares the option). `vanilla` imports neither. |

---

## 8. Success criteria (verifiable)

1. `files/limine/{desktop,htpc,server,stateless}/wallpaper.png` exist, each `PNG image data, 2560 x 1440`.
2. `nix eval --impure .#nixosConfigurations.vexos-desktop-amd.config.system.build.toplevel.drvPath`
   succeeds (default systemd-boot path — style block inert).
3. With `vexos.bootloader = "limine"` forced: `config.boot.loader.limine.style.interface.branding`
   evaluates to `"VexOS"` and `config.boot.loader.limine.style.wallpapers` is `[ <existing .png> ]`.
4. `nix flake show --impure` lists 30 `nixosConfigurations` (unchanged).
5. `bash scripts/preflight.sh` exits 0.
6. No diff to any `configuration-*.nix`, `flake.nix`, `flake.lock`, or `system.stateVersion`.
