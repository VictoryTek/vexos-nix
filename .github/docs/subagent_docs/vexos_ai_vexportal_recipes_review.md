# vexos-ai VexPortal recipes — review

Scope: `justfile` (+38 lines, six recipes). Lock bump (spec step 2) pending the
vexos-ai push; it is reviewed in `vexos_ai_vexportal_recipes_review_final.md`.

## Findings

- **Spec compliance:** the six recipes, signatures and doc lines match the spec
  table. `just --dump --dump-format json` (just 1.51.0, nixos-26.05) compared
  with VexPortal's `catalog/tests/fixtures/vexos-nix-justfile.json` for
  `ai-*`, `agent` and `diagnose`: doc, params (name, default, kind) and
  private are identical.
- **Argument passing:** with a stub `vexos-ai` that prints argv, every recipe
  passes one word per parameter, empty defaults arrive as `''`, and
  `ai-crash-mute 'fire fox; touch /tmp/pwned' off` passes the name through
  verbatim with no shell execution. `quote()` is the first use in this
  justfile; `diagnose` keeps its existing unquoted `{{target}}` (out of scope).
- **Consistency:** same group, guard line and `@` style as `agent` and
  `diagnose`. The guard is repeated per recipe, as the existing two do. A
  private guard recipe would add an entry to the dump that VexPortal reads, so
  repetition is the safer choice.
- **Option B / Nix:** no Nix files changed. No `lib.mkIf` added.
- **Security:** no secrets; arguments quoted; the recipes run as the user, and
  none of them apply a configuration.

## Build validation (WSL, Nix 2.34.1; `nixos-rebuild` is unavailable here)

| Check | Result |
|---|---|
| `nix flake show --impure` | PASS |
| `vexos-desktop-amd` toplevel drvPath | PASS |
| `vexos-desktop-nvidia` toplevel drvPath | PASS |
| `vexos-desktop-vm` toplevel drvPath | PASS |
| desktop-amd + `vexos.features.ai.enable = true` toplevel drvPath | PASS (4 vexos-ai user units, `programs.vexos-ai.enable = true`) |
| `git ls-files hardware-configuration.nix` | empty |
| `system.stateVersion` / `flake.nix` | unchanged |
| `sudo nixos-rebuild dry-build` | not run (no NixOS host here); to run on a VexOS host |

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (98%)**

**Result: PASS** for the justfile. The lock bump follows once vexos-ai
`2789611` is on origin/main.
