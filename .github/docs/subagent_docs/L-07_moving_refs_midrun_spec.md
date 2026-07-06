# L-07 — Install scripts fetch moving refs mid-run

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-07 (BUGS L7) ·
`scripts/stateless-setup.sh:191`, `scripts/install.sh:119,126`
(current file: line numbers have drifted — see below; content still
matches the described defect shape)

## Current State

### Disko ref — verified NOT a bug (scope-narrowing finding)

`stateless-setup.sh:246` runs:
```bash
sudo nix ... run 'github:nix-community/disko/latest' -- ...
```

Checked directly against the upstream `nix-community/disko` GitHub repo
rather than trusting the plan's premise:
- `latest` is a real, maintained **tag** (not a branch) that disko's own
  maintainers re-point to their current stable release on every release
  (currently the same commit as their `v1.13.0` tag).
- Disko's own quickstart documentation explicitly recommends
  `nix run github:nix-community/disko/latest -- ...` as the standard
  one-liner invocation.

So this is upstream's own blessed idiom, not a defect this repo
introduced — pinning it to a fixed tag would deviate from the
documented-recommended usage and add a manual-bump maintenance burden
disko's own tag already exists to avoid. **Per user decision, left
unchanged.** `disko` is not a flake input anywhere in this repo
(confirmed via grep of `flake.nix`/`flake.lock`) — it is only ever
invoked ad hoc here, so there is no separate pinned reference to
reconcile it against.

### The real defect: this repo's own script-to-script fetch chain

Three scripts in this repo are each independently documented as
directly runnable via `curl -fsSL .../main/scripts/<name>.sh | bash`,
**and** `install.sh` also curls the other two mid-run:

- `install.sh:119` — `curl .../main/scripts/stateless-setup.sh | bash`
  (live-ISO stateless path)
- `install.sh:126` — `curl .../main/scripts/migrate-to-stateless.sh | sudo bash`
  (existing-install stateless migration path)
- `stateless-setup.sh:35-36` (`REPO_RAW`, `TEMPLATE_URL`,
  `DISKO_TEMPLATE_URL`) — downloads `template/etc-nixos-flake.nix` and
  `template/stateless-disko.nix`, both from `.../main/...`

Every one of these resolves the literal string `main` independently, at
the moment each individual `curl` executes — not once per run. A single
`install.sh` run legitimately spans minutes (disk formatting, package
downloads, a full `nixos-install` closure build), during which this is
an actively-developed repo that could receive a new commit to `main`.
If that happens between, say, `install.sh` starting and its line-119
curl firing, the running installer silently mixes code from two
different commits with no record of what actually executed — the
"SECURITY NOTICE / Always verify the source URL" comment in every one
of these scripts is meaningless in that scenario, since by the time a
user could check `main`, it may have already moved past what actually
ran.

This is distinct from — and does not conflict with — the *NixOS flake
build* itself always resolving to fresh `main` HEAD (`stateless-setup.sh`
and `install.sh` both force a `nix flake update --flake git+file://...`
immediately before `nixos-install`/`nixos-rebuild`, per the existing,
deliberate, already-correct H-10-era design: one atomic `flake update`
call produces one `flake.lock`, so there's no equivalent drift risk at
that layer). L-07 is purely about the *installer script bootstrap
layer* — the bash scripts themselves, before Nix is ever invoked to
build anything.

`migrate-to-stateless.sh` does not itself download any further
`raw.githubusercontent.com` content (confirmed via grep) — it only
operates on the already-cloned/tracked `/etc/nixos`. It only needs to
be consistent as the *target* of `install.sh`'s curl, not as a source of
further downloads itself.

## Problem Definition

`main` is resolved independently, once per `curl` call, across a single
multi-minute installer run spanning up to three separate scripts and
two separate template downloads — allowing a single run to silently mix
code from different commits if the branch is updated while the script
is executing.

## Proposed Solution

Resolve the target commit **once**, as early as possible in whichever
script the user starts (`install.sh` if going through the guided flow;
`stateless-setup.sh` directly if a user runs its own documented
one-liner without going through `install.sh` first), and reuse that same
resolved commit for every `raw.githubusercontent.com` fetch for the rest
of that run — including when `install.sh` hands off to
`stateless-setup.sh`/`migrate-to-stateless.sh` via a piped `curl | bash`,
which starts a brand-new process that would otherwise re-resolve `main`
independently.

Mechanism:
1. Resolve via `git ls-remote https://github.com/VictoryTek/vexos-nix main`
   (returns `<sha>\trefs/heads/main`; `cut -f1` extracts the SHA). This
   avoids GitHub REST API rate limits (`api.github.com` is capped at
   60 req/hr per IP for unauthenticated calls, which is a realistic
   concern on a NAT'd home network; the git smart-HTTP protocol used by
   `ls-remote` has no equivalent per-IP cap) and needs no `jq`/JSON
   parsing.
2. Guard resolution behind `${VEXOS_REV:-}`: if already set (inherited
   from a parent script's `export`), reuse it instead of re-resolving —
   this is what actually pins the whole `install.sh` →
   `stateless-setup.sh`/`migrate-to-stateless.sh` chain to one commit,
   not just each script individually.
3. `git` may be absent on a minimal live-ISO — reuse the exact
   already-established fallback idiom this repo uses for other missing
   tools (`install.sh:351-358`'s `git` bootstrap, `stateless-setup.sh`'s
   `openssl` bootstrap): `nix build nixpkgs#git --no-link --print-out-paths`
   and invoke the absolute store path.
4. Replace every `.../vexos-nix/main/...` URL used for an actual
   download with `.../vexos-nix/${VEXOS_REV}/...`. Cosmetic/documentation
   URLs that point a human at the *repository* for manual browsing
   (`https://github.com/.../blob/main/scripts/install.sh`) are updated
   to reflect the exact commit that is actually running, which is
   strictly more useful for the "verify the source" security notice than
   a permanently-moving `main` link.

## Implementation Steps

1. `scripts/install.sh`
   - `install.sh` already has an established `git`-or-`nix-build`
     fallback pattern at lines 351-358, but it runs *after* role/GPU
     selection — too late for the stateless-path curls at lines 119/126.
     Hoist an equivalent (but minimal — only needs `git ls-remote`, not
     full git functionality) resolution block to the very top of the
     script, right after `set -euo pipefail`, before the `SCRIPT_URL`
     line.
   - Update `SCRIPT_URL` and the "Verify:" line to use `${VEXOS_REV}`
     instead of `main`.
   - `export VEXOS_REV` so the two `curl | bash` invocations at lines
     119 and 126 inherit it into their child bash processes.
   - Change lines 119 and 126 to fetch from
     `.../vexos-nix/${VEXOS_REV}/scripts/{stateless-setup,migrate-to-stateless}.sh`.
   - The later, already-existing `git`-fallback block (lines 351-358,
     used for `/etc/nixos` git-tracking) is unrelated to this fix and is
     left as-is.

2. `scripts/stateless-setup.sh`
   - Add the same `${VEXOS_REV:-...}` resolution block near the top
     (before `REPO_RAW` is defined), so it only actually resolves when
     run standalone (not inheriting from `install.sh`).
   - Change `REPO_RAW="https://raw.githubusercontent.com/VictoryTek/vexos-nix/main"`
     to use `${VEXOS_REV}` instead of the literal `main`.
   - Leave `DISKO_TEMPLATE_URL`/`TEMPLATE_URL` derivation from
     `REPO_RAW` unchanged (they already inherit the fix once `REPO_RAW`
     is fixed).
   - Leave the disko `nix run` line untouched (see above).

3. `scripts/migrate-to-stateless.sh`
   - No functional change (it performs no further downloads). Only its
     header comment/"Source:" line, if present, could optionally be
     left as `main` since it's purely documentation and this script
     doesn't self-select a version the way `install.sh`/
     `stateless-setup.sh` do — confirm in Phase 2 whether it has an
     equivalent "Source:" echo line worth updating for consistency.

## Configuration Changes

None — shell-script-only changes; no NixOS module/option changes.

## Risks and Mitigations

- **Risk:** `git ls-remote` requires network access to
  `github.com` before any other network operation in the script — if
  DNS/network isn't up yet on the live ISO, this fails earlier than
  before.
  **Mitigation:** every one of these scripts already requires network
  access as step zero (they are themselves fetched via `curl` over the
  network) — this adds no new network dependency, just moves a
  resolution step earlier.
- **Risk:** if `main` is force-pushed/rewritten (not just fast-forwarded)
  between when a user copies the one-liner and when they run it, the
  resolved SHA could point at a commit no longer reachable from `main`
  by the time they'd manually inspect it on GitHub's web UI.
  **Mitigation:** out of scope — this is a pre-existing risk of the
  `curl | bash` distribution model itself, not something L-07 claims to
  fix; L-07 only fixes *mid-run* drift within a single execution.
- **Risk:** breaking the documented one-liners
  (`curl -fsSL .../main/scripts/install.sh | bash`) — users still start
  by fetching `install.sh` from `main` themselves; this fix only changes
  what *install.sh itself* fetches afterward, not the user-facing entry
  point.
  **Mitigation:** verify in Phase 3 that none of the three scripts'
  top-of-file usage comments need to change — they describe the
  *user's* initial fetch command, which is unaffected.
