# Review — Narrow the vexos-update heavy-build block to the kernel source build

Feature: `vexos_update_kernel_block_narrowing`
Spec: `.github/docs/subagent_docs/vexos_update_kernel_block_narrowing_spec.md`
Date: 2026-07-29

---

## 1. Files reviewed

| File | Change |
|---|---|
| `pkgs/vexos-update/default.nix` | `HEAVY_BUILD_REGEX` → `^linux-[0-9][0-9.]*(-rc[0-9]+)?$`; comment block rewritten; classifier comment and `VEXOS_CACHE_BLOCK` message wording updated |
| `justfile` | `upgrade-analysis` regex aligned to the same value; `update` recipe comment and four `upgrade-analysis` report labels reworded |
| `README.md` | Update-classification bullets rewritten to match actual behaviour |

`scripts/install.sh` correctly untouched — it holds only `UNAVOIDABLE_REGEX`, no
heavy-build regex.

---

## 2. Specification compliance

All four implementation steps completed as specified:

- Step 1 (`pkgs/vexos-update/default.nix`) — regex value, comment, classifier comment,
  block message: **done**. `grep -n HEAVY_BUILD_REGEX` confirms one definition
  (line 115 of the generated script) and two consumers, structure unchanged.
- Step 2 (`justfile`) — regex, comment, four labels: **done**. Went one label beyond the
  spec's list (the `[3/3] Recommendation` line still said "kernel/NVIDIA"); same
  category of fix, same recipe.
- Step 3 (`README.md`) — bullets: **done**.
- Step 4 — validation: **done**, with one substitution recorded in §6.

No scope creep: the spec's three declared boundaries were respected — no new blocking
entries, no third display bucket in `upgrade-analysis`, `install.sh` untouched.

---

## 3. Classifier correctness

Regex partition verified against 14 representative derivation names. Every name lands
in exactly one bucket (partition is exhaustive — no derivation is silently dropped):

| name | bucket | expected |
|---|---|---|
| `linux-7.1.5` | HEAVY | ✓ |
| `linux-6.12.30` | HEAVY | ✓ |
| `linux-6.14-rc1` | HEAVY | ✓ |
| `linux-7.1.5-modules` | NON_HEAVY | ✓ |
| `linux-7.1.5-modules-shrunk` | NON_HEAVY | ✓ |
| `linux-config-7.1.5` | NON_HEAVY | ✓ |
| `linux-firmware-20250401` | NON_HEAVY | ✓ |
| `NVIDIA-Linux-x86_64-595.71.05` | UNAVOIDABLE | ✓ |
| `nvidia-x11-595.71.05-7.1.5` | UNAVOIDABLE | ✓ |
| `nvidia-open-595.71.05-7.1.5` | NON_HEAVY | ✓ |
| `openrazer-3.10.3` | UNAVOIDABLE | ✓ |
| `zfs-kernel-2.3.1-7.1.5` | NON_HEAVY | ✓ |
| `xpadneo-0.10.2` | NON_HEAVY | ✓ |
| `vexos-update` | NON_HEAVY | ✓ |

Escaping verified end-to-end: the built script at
`/nix/store/8bfy3kwf2qfc032cxrbgsxn0rkn2c85d-vexos-update/bin/vexos-update:115` contains
the regex byte-for-byte, so the Nix indented-string pass did not alter it (`$` at end,
no `${`, no `''` sequences). The `justfile` copy contains no `{` and therefore cannot
collide with `just`'s `{{ }}` interpolation — `just --summary` and `just --evaluate`
both parse.

Both `HEAVY_BUILD_REGEX` consumers reviewed:
- kernel-override auto-clear (`STILL_HEAVY`): now keys on the kernel itself, which
  repairs the secondary defect — the aggregate always matched, so
  `kernel-install-override.nix` could never auto-clear on a host with out-of-tree
  modules and such hosts stayed pinned to `pkgs.linuxPackages` forever.
- main classifier (`HEAVY_BUILDS`): blocks only on a real kernel compile.

`VEXOS_UPDATE_STRICT=1` path unchanged and still overrides the partition wholesale.

---

## 4. Best practices / consistency / maintainability

- Module Architecture Pattern (Option B): **not applicable** — no NixOS module content
  added or moved, no `lib.mkIf` introduced, no role gating touched.
- The cross-reference comment convention already used between `install.sh` and
  `vexos-update` for `UNAVOIDABLE_REGEX` is now mirrored at both `HEAVY_BUILD_REGEX`
  sites, which is the available mitigation for the two-copy duplication (a `just`
  recipe cannot source a fragment out of a Nix package).
- Existing file style matched: same comment idiom, same `printf`/`grep -E` shape, no
  reformatting of adjacent code.
- The initial comment block was trimmed during review (15 → 11 lines) after reading as
  overweight for the section it sits in; script rebuilt afterwards.

Pre-existing issue noted, **not** fixed (outside this task's scope): `README.md:154`
and `justfile:345` both say the script lives in `modules/nix.nix`; it moved to
`pkgs/vexos-update/`. Flagged for the user rather than silently corrected.

---

## 5. Security / performance

- No secrets, credentials, or file modes touched. No new plaintext credential paths.
  Preflight stage 7 guards unaffected.
- No new flake inputs (`git diff HEAD -- flake.nix flake.lock` empty), so the `follows`
  policy is not engaged.
- `hardware-configuration.nix` not tracked (`git ls-files` empty).
- `system.stateVersion` unchanged in every `configuration-*.nix`
  (`git diff HEAD -- '*.nix' | grep stateVersion` empty).
- Performance: strictly positive. The change removes a class of blocked-then-retried
  update cycles; the aggregates it now permits are a `buildEnv` + `depmod` and a
  module-subset copy (seconds), per the pinned nixpkgs sources cited in the spec.
- Risk direction: the regex is narrower, so a genuinely uncached kernel whose
  derivation is not named `linux-<version>` (e.g. `linux-hardened-*`) would not block.
  This is not a regression — the previous regex was anchored to `linux-[0-9]` too — and
  no role in this repo uses such a kernel.

---

## 6. Build validation

| Check | Result |
|---|---|
| `nix flake show --impure` | **PASS** — all outputs enumerated, no eval errors |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-amd…drvPath` | **PASS** — `vqx9k5cvjr8svw07gibgp98z3jwiza43` |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia…drvPath` | **PASS** — `v17fv885zmfx7p3mam309bhnwlrh45cp` |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-vm…drvPath` | **PASS** — `vvnc5jdp4a8mlpj8zms6zmak3y2hyvn2` |
| `vexos-update` package build (runs shellcheck via `writeShellApplication`) | **PASS** |
| `just --summary` / `just --evaluate` | **PASS** |
| `git ls-files hardware-configuration.nix` | **PASS** (empty) |
| `system.stateVersion` unchanged | **PASS** |
| New flake inputs declare `follows` | **N/A** — no input changes |

**Substitution recorded:** `sudo nixos-rebuild dry-build` could not run — this session's
sandbox sets the no-new-privileges flag, so `sudo` is refused outright. The three
required desktop variants were validated with `nix eval --impure … .drvPath` instead,
which CLAUDE.md names as the accepted equivalent forcing full evaluation for a single
target. Note this validates evaluation, not closure realisation; the shellcheck gate
that a dry-build would *not* have exercised (dry-build lists rather than builds) was
covered separately by building the `vexos-update` package outright.

Server/stateless/htpc dry-builds not required: the change touches no server, stateless,
or htpc module. `vexos-update` is installed by `modules/nix.nix` for all roles, and its
evaluation is identical across them — the three desktop targets cover it.

---

## 7. Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 97% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 96% | A |
| Build Success | 96% | A |

**Overall Grade: A (98%)**

Deductions: Consistency/Code Quality — the two-copy `HEAVY_BUILD_REGEX` duplication
persists (structurally unavoidable; mitigated by cross-references). Build Success —
`nixos-rebuild dry-build` substituted per §6.

---

## 8. Verdict

**PASS** — no CRITICAL or RECOMMENDED issues outstanding. Proceed to Phase 6 preflight.
