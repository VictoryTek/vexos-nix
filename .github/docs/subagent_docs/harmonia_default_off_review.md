# Harmonia cache opt-in — Review

## Scope reviewed
- `modules/nix.nix` — `vexos.harmonia.cacheUrl` / `publicKey` defaults + comments

## Findings

1. **Spec compliance** — matches spec exactly. Both defaults flipped to off
   (`null` / `""`), symmetric with `vexos.attic` directly above. Comment block
   and `publicKey` description rewritten to opt-in wording.
2. **Config block** — untouched. Lines 104-152 already gate substituter/key
   injection on `cacheUrl != null` / `publicKey != ""`; with both off, no
   harmonia substituter and no assertion. `warnings` entry still fires if a
   host sets `cacheUrl` without `publicKey`.
3. **Module Architecture (Option B)** — unchanged. `modules/nix.nix` stays a
   universal base; no role/flag `lib.mkIf` added. The `cacheUrl != null` guard
   is the module's own toggleable-subsystem carve-out (allowed).
4. **Consumers** — `grep -rn 'vexos.harmonia' hosts/ template/ configuration-*.nix`
   → none. No host relied on the default; nothing breaks.
5. **Server side** — `modules/server/harmonia.nix` and `kernel-builder.nix`
   (`vexos.server.harmonia.*`) are independent and untouched.
6. **Security** — the removed committed public key is not a secret; no exposure.
7. **Formatting** — `nixpkgs-fmt --check modules/nix.nix` reports drift, but the
   HEAD version fails identically (repo-wide pre-existing: 108/197 files).
   Edit matches surrounding 2-space style. Not addressed per surgical-changes rule.

## Build validation
- `nix flake show --impure` — evaluates; only pre-existing `kernel-override`
  name warnings.
- `bash scripts/preflight.sh` — **Preflight PASSED — safe to push.**
  (dry-build of `vexos-desktop-nvidia` current variant included; WARNs are all
  pre-existing: repo formatting drift, vexboard `change-me` placeholder,
  gitleaks not installed.)

## Verdict: PASS
