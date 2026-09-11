# DMS → ReGreet Greeter Migration — Review

Status: Phase 3 (Review & Quality Assurance) / Phase 6 (Preflight)

---

## 1. Specification compliance

| Item | Spec | Implemented | Match |
|---|---|---|---|
| New greeter file, reuses existing `isHyprland` gate | `modules/hyprland-greeter.nix` | Done | ✅ |
| `programs.regreet.enable = true`, no `services.greetd` set directly | Confirmed no `services.greetd.*` assignment in new file | ✅ |
| Background: newly authored SVG, rasterized via `resvg`, not a reused wallpaper | `files/regreet/background.svg` + `pkgs.runCommand` derivation | ✅ |
| Logo via CSS on `#clock_frame`, no template changes | `extraCss` `#clock_frame { background-image: url(...) }` using `pixmapsDir/vex.png` | ✅ |
| CSS targets only verified widget IDs/classes | All selectors cross-checked against `component.rs`/`templates.rs` read directly (§3.4 of spec) | ✅ |
| `font`/`theme`/`cursorTheme`/`iconTheme` options used, not hand-written `settings.GTK` | Only `font.package/name/size` set; `settings.GTK.application_prefer_dark_theme` is a distinct leaf key, no collision | ✅ |
| DMS greeter section removed from `modules/hyprland-desktop.nix`, redundant `accounts-daemon` line dropped | Done | ✅ |
| `flake.nix` `dmsBase` drops `nixosModules.greeter`, keeps `dank-material-shell` | Done | ✅ |
| `branding-display.nix` comment updated | Done | ✅ |
| Autologin/PAM sections untouched except stale "DMS greeter module" wording corrected | Confirmed — only that one clause reworded, no option changes | ✅ |

## 2. Best practices / Nix conventions

- New module follows the same `let isHyprland = …; in { config = lib.mkIf isHyprland { … }; }` shape as its sibling `hyprland-desktop.nix`.
- Palette values centralized in one `let palette = { … };` block rather than repeated hex literals through the CSS string — every color traces to `files/dms/vexos-neo-cyberpunk.json`.
- Background derivation is a minimal `runCommand` + single CLI invocation, matching the style of `branding-display.nix`'s existing `vexosWallpapers` derivation.

## 3. Consistency (Module Architecture Pattern)

`modules/hyprland-greeter.nix` reuses the pre-existing `vexos.desktop.environment == "hyprland"` gate already used by its sibling `hyprland-desktop.nix` and by `home/noctalia.nix` — not a new guard on a shared module. Matches the established `gnome.nix`/`gnome-desktop.nix` split pattern.

## 4. Maintainability

- Every non-obvious decision has a comment carrying its "why" (git-history-free rationale): why no `services.greetd` block, why `settings.GTK` is left alone, why the logo is CSS-composited instead of template-modified, why `restartIfChanged = false`.
- Spec file cross-references exact widget names so a future editor doesn't have to re-derive them from ReGreet's source again.

## 5. Completeness

All three original symptoms/requests addressed: DMS greeter replaced, cyberpunk-styled theming applied (palette-driven CSS), project logo shown (composited onto the clock panel), background freshly authored rather than reusing desktop wallpapers.

## 6. Performance

Background rasterization is a one-time build-time cost (single `resvg` invocation on a small vector file); no runtime cost added versus the DMS greeter.

## 7. Security

No secrets, no world-writable files. `programs.regreet.settings`/`extraCss` land in `/etc/greetd/regreet.{toml,css}` (world-readable, as greetd configs normally are — no credential material in either).

## 8. API currency

`programs.regreet.*` option shape verified by reading `nixos/modules/programs/regreet.nix` **at the exact pinned nixpkgs revision** (`d58a46e3…`), not the unstable-channel docs or a search index (which reported a different, newer option path `services.displayManager.regreet.*` that does not exist at this pin — confirmed by direct source read and avoided). CSS selectors verified by reading ReGreet's actual widget-template source, not inferred.

## 9. Build validation — and an important finding

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` (WSL) | ✅ passes (this check does not force deep evaluation — see finding below) |
| Full closure eval, hyprland branch, bypassing git file-filtering | `nix eval --impure` on `builtins.getFlake (toString ./.)` (WSL), forced `vexos.desktop.environment = "hyprland"` | ✅ `nixos-system-vexos-26.05.drv` produced — proves the Nix code itself (imports, option names, CSS-string interpolation, `resvg` derivation) is correct |
| SVG rasterization | `nix run nixpkgs#resvg -- files/regreet/background.svg …` (WSL) | ✅ produced a 1920×1080 PNG; visually inspected in this session — matches the intended cyberpunk look |
| `hardware-configuration.nix` not committed | `git ls-files hardware-configuration.nix` | ✅ empty |
| `stateVersion` unchanged | `grep stateVersion configuration-desktop.nix` | ✅ still `"25.11"` |
| `git status` scope | only the files listed in §6 of the spec changed/added | ✅ |
| **`bash scripts/preflight.sh`** | full script (WSL) | **✗ FAILED at stage 8/8** |

### The preflight failure is a git-staging prerequisite, not a code defect

Stage `[8/8]` runs `nix build ".#nixosConfigurations.vexos-desktop-amd.pkgs.vexos.vexos-update"` — a real flake-ref (`.#…`) build, which (unlike the `builtins.getFlake (toString ./.)` eval above) goes through Nix's **git-tracked-file source filtering**: for a local flake inside a git repository, `nix build .#…`/`nix eval .#…` only sees files that are tracked (or staged) in git. Genuinely untracked files are invisible to it, regardless of correctness.

Confirmed directly:
```
$ git status --porcelain | grep '^??'
?? .github/docs/subagent_docs/regreet_greeter_migration_spec.md
?? files/regreet/
?? modules/hyprland-greeter.nix

$ nix eval --impure ".#nixosConfigurations.vexos-desktop-amd.config.system.stateVersion"
error: path '/nix/store/…-source/modules/hyprland-greeter.nix' does not exist
```

This reproduces on **every** role, not just `desktop`/hyprland — `configuration-desktop.nix`'s `import ./modules/hyprland-greeter.nix` line is unconditional (only the module's `config` content is gated), so the file must physically exist in the filtered source tree for `import` to succeed at all, independent of whether `vexos.desktop.environment == "hyprland"`.

This is standard, universal Nix flake behavior for any new file in a git-managed flake — not specific to this change, and not fixable by editing the Nix code. Per this project's rules I cannot run `git add` myself (`git add`/`commit`/`push`/`stash` are explicitly forbidden — "all git write operations are the user's responsibility, not Claude's"). The equivalent full-closure evaluation above (which bypasses git filtering) already proves the code is correct; what remains is purely mechanical: **the new files need to be `git add`ed (staging alone, not a commit) before `nixos-rebuild` or any other `.#`-style flake command — including the user's own eventual `sudo nixos-rebuild switch`** — can see them.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 92% | A- (logo/CSS placement not visible on real hardware from this session; see spec §7 risk) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 80% | B (full-closure eval passes; the flake-ref-style build used by preflight stage 8/8 is blocked purely by untracked files, not a code error — see finding above) |

**Overall Grade: A- (96%)**

## Returns

- **NEEDS_REFINEMENT is not applicable here** — refinement would mean changing code, and there is no code defect to fix. The blocker is procedural (git staging), sits outside every action this session is permitted to take, and is described precisely above so it isn't mistaken for a build regression caused by this change. Flagged to the user directly rather than silently spending refinement cycles on it.
