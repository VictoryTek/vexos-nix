# L-15 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/L-15_distroname_priority_spec.md`

## Modified Files

- `modules/branding.nix` — completed the `distroName` role-conditional
  with the missing `"headless-server"` branch.
- `configuration-server.nix` / `configuration-htpc.nix` /
  `configuration-headless-server.nix` — removed the now-redundant
  `lib.mkOverride 500 "VexOS <Role>"` lines.

## Review Findings

1. **Specification Compliance** — matches the plan's stated goal (a single
   place owning `distroName` precedence, no `mkOverride 500` workarounds)
   via a more targeted fix than the plan's literal suggestion (a brand-new
   `vexos.branding.distroName` option) — completing the existing
   `branding.nix` conditional that already owns this concern, rather than
   layering a second option on top of it.
2. **Best Practices** — traced the *entire* priority chain (branding.nix
   `mkDefault` → configuration-*.nix `mkOverride 500` → hosts/*.nix bare
   assignment) across *both* consumption paths (`mkHost` nixosConfigurations
   and `nixosModules.*Base` for the thin external wrapper) before touching
   anything — this surfaced the real risk (the `*Base` path has no host-file
   override to fall back on) that a naive "just delete the mkOverride
   lines" fix would have silently broken.
3. **Consistency** — matches the Option B carve-out already established by
   M-27 this session: gating `distroName`'s value by `vexos.branding.role`
   inside the same module that declares both is the standard,
   already-accepted pattern here, not new role-smuggling.
4. **Maintainability** — `distroName` now has exactly one place that
   derives its value per role; a future new role only needs one branch in
   `branding.nix`, not a fourth copy-pasted `mkOverride 500` line in some
   new `configuration-*.nix`.
5. **Completeness** — all three cited `mkOverride 500` sites removed; the
   conditional gap that made the headless-server one load-bearing is
   fixed at its actual source.
6. **Performance** — n/a.
7. **Security** — n/a.
8. **API Currency** — n/a.
9. **Build Validation:**
   - **Baseline captured before any change**: built
     `nixosModules.serverBase`/`htpcBase`/`headlessServerBase` standalone
     via `lib.nixosSystem` and recorded their pre-fix `distroName` values
     (`"VexOS Server"`, `"VexOS HTPC"`, `"VexOS Headless Server"`).
   - **Post-fix re-verification**: rebuilt all three the same way — all
     three resolve to the *identical* strings as the baseline.
   - `nix flake show --impure` — passed.
   - Per-target `nix eval --impure ".#nixosConfigurations.<x>.config.system.build.toplevel.drvPath"`
     for `vexos-desktop-amd`, `-nvidia`, `-vm`, plus `vexos-server-amd`,
     `-htpc-amd`, `-headless-server-amd` (roles touched) — **every one
     produced a `.drv` hash byte-identical to the value recorded in this
     session's immediately prior review (L-14)**, confirming zero effect
     on any real `mkHost`-generated `nixosConfigurations` output — exactly
     as predicted, since every host file's bare assignment already wins
     regardless of what `configuration-*.nix` sets.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — present, unchanged, in all 6
     `configuration-*.nix` files. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs
     as every prior review this session — nothing new.

No CRITICAL or RECOMMENDED issues found.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Returns

- Build result: PASS
- **PASS**
