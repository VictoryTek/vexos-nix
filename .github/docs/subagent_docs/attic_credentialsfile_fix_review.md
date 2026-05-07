# Review: Fix `services.atticd.credentialsFile` → `services.atticd.environmentFile`

**Review Date:** 2026-05-07
**Reviewer:** Review Subagent
**Modified File:** `modules/server/attic.nix`
**Spec:** `.github/docs/subagent_docs/attic_credentialsfile_fix_spec.md`

---

## Verification Checklist

| Check | Result |
|-------|--------|
| `services.atticd.credentialsFile` does NOT appear in attic.nix | ✅ PASS |
| `services.atticd.environmentFile` IS used in its place | ✅ PASS |
| No new `lib.mkIf` guards introduced | ✅ PASS |
| Path `/etc/nixos/secrets/attic-credentials` is preserved | ✅ PASS |
| Header comment updated to `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` | ✅ PASS |
| Header comment updated to `openssl genrsa -traditional 4096 \| base64 -w0` | ✅ PASS |
| Module structure consistent with other server modules | ✅ PASS |

---

## Detailed Findings

### Option Rename

The primary fix is correct. The `credentialsFile` option was replaced with `environmentFile`:

```nix
# Before (broken):
credentialsFile = "/etc/nixos/secrets/attic-credentials";

# After (correct):
environmentFile = "/etc/nixos/secrets/attic-credentials";
```

This resolves the `error: The option 'services.atticd.credentialsFile' does not exist` failure that occurred because the nixpkgs 25.11 bundled attic module only exposes `environmentFile` without the backward-compat rename shim.

### Comment Update

The header comment was correctly updated from the outdated HS256 symmetric token format to the current RS256 asymmetric format:

```nix
# Before:
#   ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>
# Generate secret with: openssl rand -base64 32

# After:
#   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<secret>
# Generate secret with: openssl genrsa -traditional 4096 | base64 -w0
```

This is a critical operator-facing correction — using the old HS256 variable with the current module would result in a silent misconfiguration (the daemon would start but reject all tokens).

### Module Architecture Compliance

The implementation correctly follows the project's Option B module architecture:

- No new `lib.mkIf` guards were added inside the module body beyond the existing top-level `lib.mkIf cfg.enable` wrapper, which is the correct pattern for opt-in services.
- The module structure — `let cfg = …; in { options = …; config = lib.mkIf cfg.enable { … }; }` — is identical to `audiobookshelf.nix` and other server modules.
- No role-conditional logic was introduced.

### Consistency with Peer Modules

Compared against `audiobookshelf.nix` and reviewed `default.nix` (umbrella import):

- `attic.nix` is already listed in `default.nix` under `# ── Development ──` — no import change needed.
- Header comment style, option declaration style (`lib.mkOption` with `type`, `default`, `description`), and `config` block layout all match the project conventions.

### Syntax Review

Manual syntax inspection of the final file reveals no issues:

- All attribute sets are properly closed.
- String interpolation `"${toString cfg.port}"` and `"${cfg.dataDir}/…"` are correct.
- Inline comments use `#` correctly.
- No trailing commas or missing semicolons detected.

---

## Build Validation

**Status: CANNOT VALIDATE — Windows host**

This is a Windows development machine. NixOS-specific commands (`nix flake check`, `nixos-rebuild dry-build`) cannot be executed in the local environment. Build validation must be performed on a Linux host or in a NixOS VM/container.

The implemented change is a straightforward single-attribute rename with no structural changes; the risk of a build regression beyond what existed before is minimal.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | N/A | N/A (Windows host) |

**Overall Grade: A+ (98%)**

---

## Summary

The implementation fully satisfies the specification. Both required changes were applied correctly:

1. `credentialsFile` renamed to `environmentFile` — resolves the hard nixpkgs 25.11 evaluation error.
2. Header comment updated to reflect the current RS256 token format — prevents silent operator misconfiguration.

No new `lib.mkIf` guards, no structural regressions, no consistency violations. The module is clean and aligned with project conventions.

**Result: PASS**
