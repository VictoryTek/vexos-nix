# Limine Bootloader Branding — Review

Feature: `limine_branding`
Spec: `.github/docs/subagent_docs/limine_branding_spec.md`
Date: 2026-09-08
Reviewer: orchestrating agent (Phase 3)

---

## Files reviewed

| File | Status | Notes |
|---|---|---|
| `modules/branding.nix` | Modified | +1 `let` binding (`limineDir`), +1 config block (`boot.loader.limine.style`, `lib.mkIf`) |
| `files/limine/desktop/wallpaper.png` | New | 2560×1440, 8-bit RGB PNG, 168 KB |
| `files/limine/htpc/wallpaper.png` | New | 2560×1440, 8-bit RGB PNG, 256 KB |
| `files/limine/server/wallpaper.png` | New | 2560×1440, 8-bit RGB PNG, 256 KB (also serves `headless-server`) |
| `files/limine/stateless/wallpaper.png` | New | 2560×1440, 8-bit RGB PNG, 236 KB |

Diff is surgical — every changed line traces to the request. No adjacent code touched, no
reformatting (the repo uses hand-aligned `=`; `nixpkgs-fmt` was deliberately **not** run, matching
existing style and the fact that preflight's format stage is WARN-only).

---

## 1. Specification compliance

| Spec item | Implemented | Match |
|---|---|---|
| Per-role wallpapers at `files/limine/<assetRole>/wallpaper.png` (desktop, htpc, server, stateless) | Yes | ✅ |
| `headless-server` → `server` via existing `assetRole` | Yes — confirmed by eval | ✅ |
| 2560×1440, solid `#0B1526`, role `vex.png` centred, ~30 % vertical | Yes — logo top edge +300 px, ~1000 px wide | ✅ (visual: logo centre ≈ 28 %, within intent) |
| Committed static PNGs, not a derivation | Yes | ✅ |
| `branding.nix`, `lib.mkIf (config.vexos.bootloader == "limine")` | Yes | ✅ |
| `branding "VexOS"`, `brandingColor 05F4FA`, `helpColor 0298BA`, `helpColorBright 05F4FA` | Yes | ✅ |
| `graphicalTerminal.background "CC0B1526"`, `foreground "E7EEF5"` | Yes | ✅ |
| `wallpaperStyle "stretched"`, `backdrop "0B1526"` | Yes | ✅ |
| Help line kept visible, only recoloured (non-goal: hide it) | Yes | ✅ |
| `term_margin` left at upstream default | Yes | ✅ |
| No change to `configuration-*.nix`, `flake.nix`, `flake.lock`, `stateVersion`, CI | Confirmed via `git status` / `git diff` | ✅ |

Full compliance.

## 2. Best practices (Nix / nixpkgs)

- `limineDir = ../files/limine + "/${assetRole}"` — identical idiom to the adjacent `plymouthDir`,
  `pixmapsDir`, `bgLogosDir`. Path + string → path; copied to the store by reference. ✅
- `wallpapers = [ (limineDir + "/wallpaper.png") ]` — matches `boot.plymouth.logo = plymouthDir + "/watermark.png"` two lines above. ✅
- Colour values are bare `RRGGBB` / `TTRRGGBB` hex with no `#`, as Limine's `limine.conf` expects and
  as `nixos/modules/.../limine-install.py` passes through verbatim. ✅
- `lib.mkIf` on the whole `.style` attrset — standard; evaluates to `{}` when the guard is false. ✅

## 3. Consistency with Module Architecture (Option B)

- The block lives in the **universal** `branding.nix` (imported by all 5 real roles), not the
  display-only `branding-display.nix` — correct, because Limine can be selected on headless hosts.
- `lib.mkIf (config.vexos.bootloader == "limine")` is the **documented carve-out**: gating a
  toggleable subsystem by an option a sibling module (`system.nix`, always imported alongside)
  declares. It is *not* role/display/gaming-flag smuggling. Direct precedent in the **same file**:
  `boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable …`.
- No new conditional logic added to any other shared module. No `configuration-*.nix` import list
  changed (styling is not a role toggle — it follows the bootloader choice, which is already
  per-host). ✅

## 4. Maintainability

- Comment block states *why* (upstream ships NixOS branding + opaque slab), names the palette source
  (`files/ghostty/config`), and explains the `TT=CC` transparency math and the carve-out rationale.
- A user swapping in custom art replaces one file per role — no code change. ✅

## 5. Completeness

- All four `assetRole` targets have an asset; `headless-server` mapping verified by eval.
- Default-path hosts (all 30 today) get an inert `{}` — no wallpaper enters their closure.
- The un-styleable bottom entry-comment line and the help-line visibility are explicitly out of
  scope per the spec. ✅

## 6. Performance

- `mkIf` false → `{}` for every current config; zero closure impact. Confirmed: `vexos-desktop-amd`,
  `-vm`, `vexos-stateless-amd`, `vexos-htpc-amd`, `vexos-server-amd` all still evaluate on the
  default path.
- On a Limine host: +1 PNG (~250 KB) copied to `/boot`. Negligible. ✅

## 7. Security

- No secrets, credentials, or tokens. Secret-scan regexes (`password|secret|token|api.key|privateKey =`)
  do not match `background` / `foreground` / `branding`. ✅
- PNGs are static, world-readable art assets — same class as `files/plymouth/*/watermark.png`. No
  world-writable paths, no executable bits needed. ✅
- `enableEditor` is untouched (already defaults to `false` upstream and in `system.nix` — no
  `init=/bin/sh` exposure introduced). ✅

## 8. API currency

Limine `limine.conf` keys verified against **Limine `CONFIG.md` (trunk)** and the **installed nixpkgs
`limine.nix` / `limine-install.py`**:

- `interface_branding_colour` / `interface_help_colour` / `interface_help_colour_bright` — current
  Limine takes an `RRGGBB` hex string (default `00aaaa` / `00aa00`), **not** the pre-v8 `0-7` index.
  The screenshot host runs Limine 12.5.2. ✅
- `term_background` — `TTRRGGBB`, `TT=00` opaque … `FF` fully transparent; default `00000000`
  (the opaque slab). `CC` ⇒ ~80 % transparent. ✅
- `wallpaper` accepts PNG. ✅
- No Context7 lookup required — no new dependency or versioned library integration.

## 9. Build validation

Environment: Windows host; validation run in WSL (Nix 2.34, non-NixOS). Per project Resource
Constraints, `nixos-rebuild dry-build` cannot run here and full 30-variant evaluation is delegated to
GitHub Actions CI; the CI-equivalent `nix eval … system.build.toplevel.drvPath` is used instead
(identical to `.github/workflows/ci.yml`). A CI-identical stub `/etc/nixos/hardware-configuration.nix`
was in place.

| Step | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | ✅ 30 `nixosConfigurations` (unchanged) |
| Default path | `nix eval …vexos-desktop-amd…toplevel.drvPath` | ✅ PASS (style block inert) |
| Default path | `…vexos-desktop-vm…` | ✅ PASS |
| Default path | `…vexos-stateless-amd…` | ✅ PASS |
| Default path | `…vexos-htpc-amd…` | ✅ PASS |
| Default path | `…vexos-server-amd…` | ✅ PASS |
| Limine path | `vexos-desktop-amd` + `{ vexos.bootloader = "limine"; }` (extendModules), full `toplevel.drvPath` | ✅ PASS |
| Limine path — style values | eval of `config.boot.loader.limine.style.*` | ✅ `branding="VexOS"`, `brandingColor="05F4FA"`, `helpColor="0298BA"`, `helpColorBright="05F4FA"`, `termBackground="CC0B1526"`, `termForeground="E7EEF5"`, `wallpaperStyle="stretched"`, `backdrop="0B1526"` |
| Limine path — wallpaper resolves | `builtins.all builtins.pathExists style.wallpapers` | ✅ `true`, path `…/files/limine/desktop/wallpaper.png` |
| `assetRole` map | `vexos-headless-server-amd` (limine forced) | ✅ `…/files/limine/server/wallpaper.png` |
| `hardware-configuration.nix` not tracked | `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | `git diff` on `configuration-*.nix` | ✅ no diff |
| New flake inputs `follows` | `git diff flake.nix` | ✅ flake.nix untouched |

> The Limine-forced eval **must** use a `path:` flake ref (or committed files). `git+file://` /
> `.#` exclude untracked files, so before `files/limine/*.png` is committed a bare `.#` eval of a
> Limine host fails with `path … does not exist`. This is a flake-source artifact, not a defect —
> see Findings.

No evaluation errors. No missing-attribute failures.

---

## Findings

### CRITICAL
None.

### RECOMMENDED

1. **Delivery note — commit the PNGs together with `modules/branding.nix`.** Because Nix flakes only
   see git-tracked files, a host on `vexos.bootloader = "limine"` will fail to build
   (`path '…/files/limine/<role>/wallpaper.png' does not exist`) if `branding.nix` is committed
   without the four new asset files in the same commit. → Handled in Phase 7 (all five files listed
   together); no code change.

### NICE-TO-HAVE (non-blocking)

2. **`wallpaperStyle = "stretched"` distorts the logo on non-16:9 panels.** The flat `#0B1526`
   field hides the stretch everywhere except the logo lockup itself. If a user runs the boot menu on
   a 16:10 / ultrawide panel and dislikes it, switching to `wallpaperStyle = "centered"` (with the
   already-set `backdrop = "0B1526"`) is a one-line drop-in. Left as `stretched` per spec; most
   VexOS hardware is 16:9.

3. **CI `paths-ignore: files/**` means a future commit that changes *only* a wallpaper PNG is not
   evaluated by CI.** Pre-existing repo behaviour (applies to all of `files/`, `wallpapers/`), not
   introduced here. Any commit that also touches `modules/branding.nix` is fully evaluated.

4. Logo vertical centre lands at ≈28 % rather than the spec's 32 %. Visually clears the
   vertically-centred entry list and the title line; no adjustment needed.

---

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

---

## Verdict

**PASS**

Build/eval green on every path tested (default for 5 role/variant configs; Limine-forced full
closure for desktop; `assetRole` mapping for headless-server). No CRITICAL findings. The one
RECOMMENDED item is a Phase 7 delivery instruction (commit assets alongside the module), not a code
defect. Proceed to Phase 6 (Preflight).
