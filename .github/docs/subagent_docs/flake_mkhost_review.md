# Review: `mkHost` helper, NVIDIA legacy variants, `headless-server` enum

Spec:   `.github/docs/subagent_docs/flake_mkhost_spec.md`
Files reviewed:
- [flake.nix](flake.nix)
- [modules/branding.nix](modules/branding.nix)
- [configuration-headless-server.nix](configuration-headless-server.nix)

---

## 1. Specification compliance

Every step from spec §4 verified against the working tree:

| Spec step | Implementation | Status |
|---|---|---|
| §3.1 `mkHomeManagerModule` helper | [flake.nix](flake.nix#L97-L110) — single helper replacing 5 copies | ✅ |
| §3.2 `roles` table | [flake.nix](flake.nix#L62-L95) — desktop/htpc/stateless/server/headless-server | ✅ |
| §3.3 `mkHost` with `nvidiaVariant` legacyExtra | [flake.nix](flake.nix#L121-L139) — module ordering matches spec | ✅ |
| §3.4 `hostList` + `lib.listToAttrs` | [flake.nix](flake.nix#L141-L189) and [flake.nix](flake.nix#L231-L237) — 30 entries | ✅ |
| §3.5 `mkBaseModule` shared with role table; `backupFileExtension` drift fix | [flake.nix](flake.nix#L198-L226) — applied to `base` (additive) | ✅ |
| §3.6 branding enum + `assetRole` mapping (no new `lib.mkIf`) | [modules/branding.nix](modules/branding.nix#L9-L17) + [modules/branding.nix](modules/branding.nix#L74) | ✅ |
| §3.7 `vexos.branding.role = "headless-server"` | [configuration-headless-server.nix](configuration-headless-server.nix#L46) | ✅ |

---

## 2. Naming-convention check (CRITICAL gate)

Pre-refactor convention from `git show HEAD:flake.nix`:

```
vexos-desktop-nvidia-legacy535
vexos-desktop-nvidia-legacy470
vexos-stateless-nvidia-legacy535
…
vexos-htpc-nvidia-legacy470
```

→ **No-underscore** suffix in output names; underscored value `legacy_535` only inside the option assignment. New outputs `vexos-server-nvidia-legacy535/470` and `vexos-headless-server-nvidia-legacy535/470` follow the **identical convention**. ✅ Consistent.

---

## 3. Output count and identity

`nix eval --impure --json '.#nixosConfigurations' --apply 'cfgs: builtins.attrNames cfgs'` returned exactly **30** names. Diff vs the 26 pre-refactor outputs:

Added (4 expected):
- `vexos-server-nvidia-legacy535`
- `vexos-server-nvidia-legacy470`
- `vexos-headless-server-nvidia-legacy535`
- `vexos-headless-server-nvidia-legacy470`

Removed: none. Unexpected names: none. ✅

---

## 4. Semantic equivalence (26 pre-existing outputs)

Drv-path equality not measurable (no `/etc/nixos/hardware-configuration.nix` in sandbox — pre-existing constraint). Equivalence verified by construction + spot-checks:

By construction — `mkHost` produces exactly the same module list as the prior hand-written entries:

```
[ /etc/nixos/hardware-configuration.nix ]
++ roles.<role>.baseModules        # = unstableOverlayModule + upModule (+ proxmox for server)
++ [ (mkHomeManagerModule …) ]     # bit-equivalent to the per-role *HomeManagerModule
++ roles.<role>.extraModules       # impermanence for stateless, serverServicesModule for {headless-,}server
++ [ ./hosts/<role>-<gpu>.nix ]
++ legacyExtra                     # [{ vexos.gpu.nvidiaDriverVariant = "legacy_…"; }] or []
```

Cross-checked against `git show HEAD:flake.nix` lines 165–400 (per-role `commonModules`/`htpcModules`/`statelessModules`/`serverModules`/`headlessServerModules` and the five `*HomeManagerModule` blocks): module identity, ordering, and attribute set are preserved.

Spot checks on representative outputs:

| Output | `vexos.branding.role` | `environment.systemPackages` count |
|---|---|---|
| `vexos-desktop-amd` | `desktop` | 333 |
| `vexos-htpc-nvidia-legacy535` | `htpc` | (eval ok) |
| `vexos-server-amd` | `server` | 273 |
| `vexos-stateless-vm` | `stateless` | 274 |
| `vexos-headless-server-nvidia` | `headless-server` | 152 |
| `vexos-headless-server-nvidia-legacy535` | `headless-server` | 152 (identical to non-legacy — only difference is the `nvidiaDriverVariant` attr) |
| `vexos-server-nvidia-legacy470` | `server` | (eval ok) |

All spot-checks pass.

---

## 5. Option B compliance (branding.nix)

[modules/branding.nix](modules/branding.nix) gained:

- One `let`-binding: `assetRole = if role == "headless-server" then "server" else role;` ([modules/branding.nix](modules/branding.nix#L13)) — this is `let`-scope, not module `config`-scope, so it does **not** introduce a new role-conditional in module space.
- One enum addition: `"headless-server"` ([modules/branding.nix](modules/branding.nix#L74)).

No new `lib.mkIf` constructs. The pre-existing `distroName` `if/else` chain ([modules/branding.nix](modules/branding.nix#L86-L91)) is untouched (out of scope per spec §1.4 and §3.6). ✅

---

## 6. `nixosModules.*Base` external API stability

`nix eval --impure '.#nixosModules' --apply builtins.attrNames` →

```
[ "asus" "base" "gpuAmd" "gpuAmdHeadless" "gpuIntel" "gpuIntelHeadless"
  "gpuNvidia" "gpuNvidiaHeadless" "gpuVm" "headlessServerBase" "htpcBase"
  "serverBase" "statelessBase" "statelessGpuVm" ]
```

All five `*Base` exports plus all GPU/asus/statelessGpuVm exports preserved. The new `mkBaseModule` ([flake.nix](flake.nix#L198-L226)) produces lambda modules consumable by `template/etc-nixos-flake.nix`. The drift fix `backupFileExtension = "backup"` is applied to `base` ([flake.nix](flake.nix#L213)) and is purely additive — no existing consumer overrides this attribute. ✅

Note: the unstable overlay is duplicated inline inside `mkBaseModule` rather than reusing `unstableOverlayModule` via `imports`. This is intentional (pre-refactor code did the same), but flagged in §10 as a minor cleanup opportunity.

---

## 7. `headless-server` enum + asset path resolution

- `nix eval … vexos-headless-server-amd.config.vexos.branding.role` → `headless-server` ✅
- Asset paths in [modules/branding.nix](modules/branding.nix#L15-L17) interpolate `assetRole`, which maps `headless-server` → `server`, so resolution is `files/pixmaps/server`, `files/background_logos/server`, `files/plymouth/server`. All three directories exist on disk and contain every file referenced by `vexosLogos`/`vexosIcons` (`vex.png`, `system-logo-white.png`, `fedora-*.{png,svg}`, `watermark.png`). ✅
- `distroName` falls through to `"VexOS Desktop"` for the new role but is overridden via `lib.mkOverride 500 "VexOS Headless Server"` in [configuration-headless-server.nix](configuration-headless-server.nix#L47) — same final value as before. ✅

---

## 8. Build validation

- `nix flake check --no-build --impure` — fails with the **pre-existing environmental** assertion `boot.loader.grub.devices' or 'mirroredBoots'` (missing host `/etc/nixos/hardware-configuration.nix` in sandbox, identical to pre-refactor behaviour). **No new Nix evaluation errors, no syntax errors, no missing-attribute errors** introduced by this refactor.
- `nix eval … nixosConfigurations.<n>.config.vexos.branding.role` succeeded for all 7 spot-checked outputs (including all 4 new ones).
- `nix eval … environment.systemPackages` succeeded for 5 spot-checked outputs.
- `nix eval … nixosModules` enumerated 14 expected exports.

`scripts/preflight.sh` was not invoked here (Phase 6 concern); the discriminating evaluation checks above are the appropriate substitute for Phase 3 build validation in the no-`hardware-configuration.nix` sandbox.

Build result: **PASS** (no new failures; only the pre-existing environmental gap remains).

---

## 9. Out-of-scope respected

`git diff --name-only HEAD`:

```
configuration-headless-server.nix
flake.nix
modules/branding.nix
```

Exactly the three files declared in the spec. ✅ No spurious edits.

---

## 10. Code quality

Strengths:
- `mkHost` / `mkHomeManagerModule` / `mkBaseModule` cleanly separate the three pathways.
- `roles` table is the single source of truth, eliminating the historical drift between per-role module sets and `nixosModules.*Base` (the original motivation of the refactor).
- `hostList` is an aligned, readable table; adding a future `(role, gpu, variant)` is a one-line edit.
- Comments accurately describe ordering and the headless-server `up` omission.

Minor observations (RECOMMENDED, non-blocking):

1. **Unstable overlay duplicated.** [flake.nix](flake.nix#L218-L224) inlines the same overlay already defined in `unstableOverlayModule` ([flake.nix](flake.nix#L46-L55)). Could be replaced with `imports = [ unstableOverlayModule … ]` to remove duplication. Pre-existing; not a regression.
2. **`up` package referenced as a magic string.** [flake.nix](flake.nix#L226) references `up.packages.x86_64-linux.default`; the `system` constant is already declared but not reused here. Minor.
3. **`legacyExtra` could be hoisted to a named helper** if more variants accrue, but at 4 call sites the current form is fine.
4. The "GUI Server" comment block at [flake.nix](flake.nix#L154) reads cleanly; one might consider a `lib.optionalAttrs` pattern to skip nvidiaVariant on non-NVIDIA hosts, but the explicit hostList is clearer.

None of the above is a defect; they are documented for future consideration.

---

## 11. Score table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 92% | A− |
| Security | 100% | A (no new attack surface; `/etc/nixos/...` paths unchanged; no new inputs) |
| Performance | 100% | A (single `listToAttrs` over 30 entries; identical eval cost) |
| Consistency | 100% | A (naming convention preserved exactly) |
| Build Success | 95% | A (no new evaluation errors; only pre-existing env gap) |

**Overall Grade: A (97%)**

---

## 12. CRITICAL findings

**None.**

---

## 13. RECOMMENDED improvements (non-blocking)

1. Have `mkBaseModule` import `unstableOverlayModule` instead of inlining the overlay block — removes duplication between the two pathways. ([flake.nix](flake.nix#L218-L224))
2. Reuse the top-level `system` constant for `up.packages.${system}.default` references in `mkBaseModule`. ([flake.nix](flake.nix#L226))
3. Optionally annotate `hostList` entries with a `# legacy` trailing comment uniformly (currently only the 4 new entries carry `# NEW`).

---

## 14. Verdict

**PASS**

All spec steps implemented exactly. Naming convention matches pre-refactor outputs. 30 nixosConfigurations confirmed. `nixosModules.*Base` external API preserved (with the additive `backupFileExtension` drift fix). Branding enum extended without new conditional logic. No out-of-scope edits. No new evaluation errors.
