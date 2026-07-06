# L-05 — preflight gitleaks hides its own findings

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-05 (BUGS L5) · `scripts/preflight.sh:374-380`
(current file: lines 374-388)

## Current State

`scripts/preflight.sh`'s gitleaks step runs:
```bash
gitleaks detect --source . --no-banner --redact --exit-code 1 2>/dev/null
```
then, on failure, prints `fail "gitleaks: secrets detected — review output above"`.

Investigated gitleaks' actual output behavior directly against its source
(fetched via the pinned nixpkgs `gitleaks` package) rather than assuming
`2>/dev/null` is the only problem:

- `logging/log.go:13` — gitleaks' default logger
  (`logging.Logger = zerolog.New(zerolog.ConsoleWriter{Out: os.Stderr})...`)
  writes to **stderr**, unconditionally. The scan summary
  (`logging.Warn().Msgf("leaks found: %d", len(findings))`,
  `cmd/root.go:448`) goes through this logger — so `2>/dev/null` does
  suppress even the leak *count*, confirming the plan's basic premise.
- **More significant finding**: per-finding detail is gated behind two
  flags neither of which the script passes. `detect/detect.go:744-746`
  only calls `printFinding(...)` `if d.Verbose` (i.e. only with
  `--verbose`/`-v`). Separately, `cmd/root.go:347-404` only constructs a
  `detector.Reporter` at all `if reportPath != ""` (i.e. only with
  `--report-path`). Without either flag — which is exactly today's
  invocation — gitleaks produces **zero per-finding output anywhere**,
  stdout or stderr, regardless of the `2>/dev/null` redirect. The *only*
  signal a real leak was found is the process exit code and the (currently
  suppressed) summary count. So "review output above" would print nothing
  to review even after removing `2>/dev/null` — the fix needs to also make
  gitleaks actually produce output, not just stop hiding a message that
  was never being generated in useful form to begin with.

Also re-checked the second sub-item: `nix flake show --impure --json` is
called twice in the flake-structure check (once to test exit status via
`if ... > /dev/null 2>&1`, once more to capture output for the
`nixosConfigurations` count) — confirmed at current lines 84-85. Since this
evaluates the entire flake structure (all `nixosConfigurations`,
`nixosModules`, and the `checks` output added in M-37), running it twice
doubles that evaluation cost for no reason.

## Problem Definition

1. gitleaks step: even with `2>/dev/null` removed, the step would produce no
   actionable output on a real finding without also enabling `--verbose`
   (chosen here — see Proposed Solution — since this runs interactively in
   a human's terminal, unlike `--report-path`, which targets a file/CI
   artifact).
2. `nix flake show` is evaluated twice for one piece of information.

## Proposed Solution

1. Remove `2>/dev/null` from the gitleaks invocation and add `--verbose`,
   so real findings actually print (redacted secret value, file, line,
   rule, commit) to the terminal the "review output above" message
   references.
2. Capture `nix flake show --impure --json` once into a variable; derive
   both the pass/fail check and the `nixosConfigurations` count from that
   single captured JSON.

## Implementation Steps

1. `scripts/preflight.sh` — gitleaks step: drop `2>/dev/null`, add
   `--verbose`.
2. `scripts/preflight.sh` — flake-structure check: run `nix flake show`
   once, reuse the captured output for both the pass/fail test and the
   `jq` count extraction.

## Configuration Changes

None — script-only changes; no NixOS module/option changes.

## Risks and Mitigations

- **Risk:** `--verbose` could print noisy per-file scan progress in
  addition to findings, cluttering preflight output on a clean repo.
  **Mitigation:** `--verbose` only triggers `printFinding` calls per
  *actual* match (confirmed in source: gated by `if d.Verbose` inside the
  finding-append path, not a general progress logger) — a clean repo
  produces the same "no secrets detected" pass line as before.
  Verified in Phase 3 by running the updated command against this repo
  (which preflight's own secret-hygiene checks already keep free of real
  hardcoded secrets) and confirming output stays clean.
- **Risk:** capturing `nix flake show` once instead of twice could change
  error-handling behavior if the first invocation's `> /dev/null 2>&1`
  exit-code check and the second's JSON parsing ever disagreed.
  **Mitigation:** using the same single command's exit code and stdout
  for both purposes removes the possibility of disagreement entirely,
  rather than needing to keep two invocations in sync.
