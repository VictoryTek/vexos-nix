# L-21 — Archive policy for `.github/docs/subagent_docs/`

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-21 (ARCH 5.4)

## Current State

`.github/docs/subagent_docs/` now holds 657 files (6.5 MB) — larger than
the plan's cited 384/4.9 MB, since this session added a spec+review pair
per backlog item processed. Identified 5 features with versioned
spec/review chains where an explicitly later revision supersedes earlier
ones for the *same* problem:

- `branding_logo_fixes` (v1 → v2) — `v2_spec.md` explicitly states
  "Supersedes: branding_logo_fixes_spec.md (v1 — partially failed)".
- `install_sudo_fix` (v1 → v2) — same naming convention, continuation of
  the same sudo-ownership fix.
- `network_share_discovery` (v1 → v2 → v3 → v4) — verified by reading both
  ends: `v4_spec.md` states "All three prior fix attempts (v1 → v3) have
  already landed," and the unversioned `network_share_discovery_review.md`
  is confirmed (by its own header and matching same-day timestamp) to be
  v4's Phase 3 review, not an orphaned early one — despite lacking a "_v4_"
  in its filename.
- `stateless_vm_boot` (`_failure` v1 → `_v2`) — same convention. **Not**
  included: `stateless_vm_boot_locked_root_*` (dated 2026-06-12, ~2 months
  later, a distinct problem, not part of the failure/v2 chain — kept
  regardless).
- `network_discovery_v5_spec.md` — the only file with this exact stem; not
  a chain (nothing to prune), left as-is.

Confirmed with the user this scope (all 5 chains, keep only the latest
revision per chain) before deleting anything, given one chain
(`network_share_discovery`) is part of the SMB/network-discovery history
flagged elsewhere as hard-won and fragile — even though these are
historical docs, not code.

## Problem Definition

Superseded spec/review revisions for the same already-resolved problem
accumulate alongside their replacements indefinitely, with no policy for
when an older revision can be removed.

## Proposed Solution

Delete the earlier revision(s) in each of the 5 confirmed chains, keeping
only the latest spec+review pair per feature. Git history retains
everything if ever needed. Document the policy (keep-latest-per-chain,
verify the "supersedes" relationship before deleting, never delete a
differently-named/distinct problem just because it shares a stem) for
future sessions to apply going forward.

## Implementation Steps

1. Delete: `branding_logo_fixes_spec.md`, `branding_logo_fixes_review.md`.
2. Delete: `install_sudo_fix_spec.md`, `install_sudo_fix_review.md`.
3. Delete: `network_share_discovery_spec.v1-2026-04-27.md`,
   `network_share_discovery_v2_spec.md`,
   `network_share_discovery_v2_review.md`,
   `network_share_discovery_v3_spec.md`,
   `network_share_discovery_v3_review.md`.
4. Delete: `stateless_vm_boot_failure_spec.md`,
   `stateless_vm_boot_failure_review.md`.
5. Add a short policy note to this spec (see above) for future sessions.

## Configuration Changes

None — documentation-only cleanup; no code, no NixOS module/option
changes.

## Risks and Mitigations

- **Risk:** deleting a doc that turns out to hold unique troubleshooting
  detail not captured in its "superseding" replacement.
  **Mitigation:** verified the actual supersession relationship for each
  chain by reading file content (not just filename pattern) before
  deleting anything; confirmed with the user given the SMB-adjacent chain.
  Git history retains full content regardless.
- **Risk:** conflating same-stem-but-different-problem docs (e.g.
  `stateless_vm_boot_locked_root_*`) with a real version chain.
  **Mitigation:** explicitly excluded `locked_root` from this prune —
  different problem, different date, not part of the `_failure`/`_v2`
  chain.
