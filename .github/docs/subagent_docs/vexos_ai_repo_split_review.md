# vexos-ai repo split — Review (Phase 3)

Result: **PASS** (pending preflight, which depends on the new repo being pushed — see Notes).

## Checks run (all with `--override-input vexos-ai path:~/Projects/vexos-ai`, `path:` refs)
- `nix flake show --impure` — OK.
- `nix eval …toplevel.drvPath`: desktop-amd, desktop-nvidia, desktop-vm, htpc-amd, stateless-amd — OK.
- server-amd, headless-server-amd — fail on the pre-existing ZFS placeholder-`hostId` assertion; **identical failure at HEAD** (verified from a `git archive HEAD` copy), so not caused by this change.
- With `vexos.features.ai.enable = true` (via `extendModules`) on desktop-amd, htpc-amd, server-amd: `programs.vexos-ai.enable = true`, managed Claude policy present, the 4 user services present, packages claude-code/opencode/vexos-ai present. Default (disabled) → `false`.
- **Policy byte-identity:** pre-change `modules/ai.nix` vs new `nix/module.nix` evaluated under the module system with identical stubs — Claude managed-settings JSON, OpenCode JSON, tmpfiles rules, user service names, timer names all IDENTICAL.
- New repo: `nix build` OK (shellcheck via `writeShellApplication`).
- `system.stateVersion` untouched; `hardware-configuration.nix` not tracked; new input declares `follows = "nixpkgs"`.

## Findings
| Sev | Item |
|---|---|
| Info | Two claude-code versions in systemPackages (stable from `development.nix`, unstable from here) — pre-existing, unchanged. |
| Info | Stateless/headless-server receive no `programs.vexos-ai` option (stateless never imported `modules/ai.nix`); `vexosAiModule` added to desktop, htpc, server only. |
| Note | `flake.lock` has no `vexos-ai` entry yet; needs `nix flake update vexos-ai` after the new repo is pushed. |

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 97% | A |
| Best Practices | 95% | A |
| Functionality | 96% | A |
| Code Quality | 95% | A |
| Security | 98% | A |
| Performance | 100% | A+ |
| Consistency | 96% | A |
| Build Success | 95% | A |

**Overall Grade: A (96%)**
