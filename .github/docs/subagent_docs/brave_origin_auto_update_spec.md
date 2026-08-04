# Brave Origin Auto-Update — Specification

**Feature name:** `brave_origin_auto_update`
**Date:** 2026-08-04
**Status:** Phase 1 complete — ready for implementation

---

## 1. Current State Analysis

`vexos.brave-origin` is a hand-maintained, pre-built binary package that does not exist
in nixpkgs:

- `pkgs/brave-origin/default.nix` — `stdenv.mkDerivation` wrapping the upstream
  `brave-origin-<ver>-linux-amd64.zip` release asset, with `version` and the `fetchzip`
  `hash` both hardcoded.
- `pkgs/default.nix:13` — exposes it through the `vexos` overlay namespace.
- `modules/packages-desktop.nix:8` — installs `vexos.brave-origin` for the desktop role.
- `flake.nix:98` — applies `(import ./pkgs)` as a `nixpkgs.overlays` entry inside each
  `nixosConfiguration`. **There is no `packages.<system>` flake output**, so the package
  is not directly buildable via `nix build .#brave-origin`.

Existing update automation in `.github/workflows/`:

| Workflow | Scope | Style |
|----------|-------|-------|
| `update-flake-lock-daily.yml` | `nixpkgs`, `up`, `vexboard` | direct commit to `main` |
| `update-flake-lock-weekly-monday.yml` | all inputs | direct commit to `main` |
| `update-container-images-weekly-wednesday.yml` | 8 OCI image pins in `modules/server/*.nix` | direct commit to `main` |

`git log --oneline -- pkgs/brave-origin/default.nix` shows four commits, all build
fixes. The `version` string has never been bumped since the package was introduced.
Nothing in `.github/workflows/` or `scripts/` references brave-origin.

---

## 2. Problem Definition

The package is pinned at **1.91.171**. Upstream stable is **1.93.129** (verified live
against the GitHub releases API on 2026-08-04). Two independent reasons the gap never
closes on its own:

1. **Flake-input updates cannot reach it.** The daily/weekly workflows bump `flake.lock`.
   `vexos.brave-origin` is built from an in-tree expression with a literal version and
   hash, so it is invariant under every lock update. (Regular `brave`, from nixpkgs on
   line 7 of the same module, does track.)
2. **Brave's in-app updater cannot function.** `/nix/store` is read-only. The
   "out of date" banner the user sees is Brave comparing itself to upstream; it can
   never self-resolve, and no `nixos-rebuild` will change it either.

Result: silent, unbounded security drift on a network-facing browser. Manual bumps are
documented in the file header but rely on a human noticing.

---

## 3. Proposed Solution Architecture

A scheduled GitHub Actions workflow that discovers the newest **stable** Brave Origin
Linux release, rewrites `version` + `hash` in place, **builds the result to prove it
still works**, and only then commits to `main`.

Direct-commit-to-`main` matches the three existing update workflows. The build-verify
gate is the key addition: unlike a container-image tag bump, a new upstream binary can
introduce new shared-library dependencies that break `autoPatchelfHook`. CI's
`nix eval … drvPath` only evaluates and would not catch this, so the workflow must build
the derivation itself before committing.

### 3.1 Version discovery

Stable, beta and nightly all publish into the same `brave/brave-browser` releases feed
and are distinguished by asset filename:

| Channel | Asset name |
|---------|-----------|
| stable | `brave-origin-1.93.129-linux-amd64.zip` |
| beta | `brave-origin-beta-1.94.102-linux-amd64.zip` |
| nightly | `brave-origin-nightly-1.95.39-linux-amd64.zip` |

Anchoring the pattern at a digit right after `brave-origin-` selects stable only.
Stable brave-origin zips are sparse among many nightly releases, so two pages of 100 are
scanned (page 1 alone currently reaches back to 1.92.138 — a wide margin).

Verified working:

```bash
for p in 1 2; do
  curl -fsS -H "Authorization: Bearer $GH_TOKEN" \
    "https://api.github.com/repos/brave/brave-browser/releases?per_page=100&page=$p"
done | jq -r '.[].assets[].name' \
  | grep -oP '^brave-origin-\K[0-9]+\.[0-9]+\.[0-9]+(?=-linux-amd64\.zip$)' \
  | sort -V | tail -1
# → 1.93.129
```

`GITHUB_TOKEN` is passed to avoid the 60-req/hour unauthenticated limit shared across
Actions runner IPs.

### 3.2 Hash computation

Reuses the recipe already documented in the package header (proven to have produced the
current, working hash for this zip layout):

```bash
nix-prefetch-url --unpack "$URL"          # base32
nix hash convert --hash-algo sha256 --to sri "$RAW"
```

**Correction to the existing header comment:** it specifies `nix hash to-sri --type
sha256`, which Nix 2.34 reports as deprecated ("The old format conversion subcommands of
`nix hash` were deprecated in favor of `nix hash convert`"). The workflow uses
`nix hash convert`, and the header comment is updated to match and to point at the
workflow as the primary mechanism.

If the computed hash were ever wrong, the build-verify step (§3.4) fails on a
fixed-output hash mismatch and nothing is committed.

### 3.3 In-place rewrite

Two anchored `sed` substitutions against `pkgs/brave-origin/default.nix`:

- `version = "<old>";` → `version = "<new>";`
- `hash   = "sha256-…";` → `hash   = "<new SRI>";`

The `url` line interpolates `${version}` and needs no edit.

### 3.4 Build verification

Because there is no `packages.<system>` flake output, the package is built through the
overlay against the flake's own pinned nixpkgs. Verified locally:

```bash
nix eval --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    pkgs  = import flake.inputs.nixpkgs {
      system = "x86_64-linux"; overlays = [ (import ./pkgs) ];
    };
  in pkgs.vexos.brave-origin.name'
# → "brave-origin-1.91.171"
```

`nix build --no-link` on the same expression is the gate. `--impure` is required for
`getFlake` on a local path, consistent with every other `--impure` usage in this repo.

Dirty-tree note: the `sed` edits modify a **tracked** file, and Nix's dirty-tree flake
evaluation includes modified tracked files (only *untracked* files are invisible), so the
build sees the new version without any staging step.

This deliberately does **not** add a `packages` flake output — that would widen the
flake's public surface beyond what this request needs.

### 3.5 Commit

Same identity and direct-push pattern as the other three workflows. `git add` is scoped
to the single package file.

> Note on ABSOLUTE RULES: the prohibition on Claude running `git add`/`commit`/`push`
> governs *this agent's* actions. Authoring a workflow file whose steps the GitHub
> Actions bot executes is ordinary repo content, identical to the three update workflows
> already committed. No git write operation is performed by Claude in any phase.

---

## 4. Implementation Steps

1. **Create** `.github/workflows/update-brave-origin-weekly-thursday.yml`
   → verify: `yq`/manual read parses; step order matches §3.
2. **Update** the "To update to a new version" comment block in
   `pkgs/brave-origin/default.nix` to use `nix hash convert` and reference the workflow
   → verify: comment text matches the command the workflow actually runs.
3. **Validate** flake structure with `nix flake show --impure`
   → verify: exit 0, 30 `nixosConfigurations` listed.
4. **Validate** the desktop closure with `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   (and `-nvidia`, `-vm`) → verify: exit 0.
5. **Dry-run the workflow logic locally** (discovery + prefetch + sed on a scratch copy)
   → verify: produces a syntactically valid derivation that evaluates.
6. **Preflight** `bash scripts/preflight.sh` → verify: exit 0.

### Schedule slot

Existing slots: daily 04:00 UTC (flake lock), Monday 04:00 (weekly lock), Wednesday
04:00 (container images). This workflow takes **Thursday 05:00 UTC** (`0 5 * * 4`) —
no collision, and offset an hour so it never contends with the daily lock job.
Filename follows the established `update-<thing>-<cadence>-<day>.yml` convention.

Weekly cadence matches Brave's stable release rhythm (roughly weekly); daily would
mostly be no-ops, and the build-verify step is not free.

---

## 5. Dependencies

No new Nix dependencies, no new flake inputs, no new packages. Context7 lookup is not
applicable — this adds no external library integration (per CLAUDE.md's "Context7 is NOT
required for … internal code changes with no new dependencies").

GitHub Actions dependencies, both already used in-repo at these exact versions:

| Action | Version | Existing usage |
|--------|---------|----------------|
| `actions/checkout` | `v6` | all four current workflows |
| `cachix/install-nix-action` | `v31` | both flake-lock workflows |

External API: `api.github.com/repos/brave/brave-browser/releases` (public, authenticated
with the job's `GITHUB_TOKEN`).

---

## 6. Configuration Changes

`permissions: contents: write` on the job — required to push the bumped pin, identical to
the three existing update workflows. No secrets beyond the automatic `GITHUB_TOKEN`.
No changes to `flake.nix`, any `configuration-*.nix`, or any module.

`system.stateVersion` is untouched. `hardware-configuration.nix` is untouched.

---

## 7. Risks and Mitigations

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | New upstream binary adds an unsatisfied shared-library dep → `autoPatchelfHook` failure | High | Build-verify step (§3.4) runs before commit; job fails red and commits nothing. Repo stays on the last known-good version. |
| R2 | Computed hash wrong → fixed-output mismatch | Medium | Same gate as R1 — surfaces as a build failure, no commit. |
| R3 | GitHub API rate limit → empty version string | Medium | Authenticate with `GITHUB_TOKEN`; `set -euo pipefail` plus an explicit empty-result guard that exits cleanly with a warning rather than sed-ing garbage. |
| R4 | Beta/nightly asset accidentally selected | Medium | Regex anchored to a digit immediately after `brave-origin-`; beta/nightly assets carry a channel word there. Verified against live data. |
| R5 | Upstream renames the asset or drops the zip | Low | Empty-result guard (R3) makes this a clean no-op with a warning in the job log, not a broken commit. |
| R6 | Direct commit to `main` bypasses review | Low | Accepted — matches the three existing update workflows, and this one is strictly *safer* since it builds before committing. CI still runs on the resulting push. |
| R7 | User's machine still shows old version after the bot commits | Informational | The commit only updates the repo. The user must `git pull` and run `sudo nixos-rebuild switch` (user-initiated per FORBIDDEN COMMANDS) to actually receive the new browser. To be stated in delivery. |
| R8 | Runner disk/time cost of building a ~200 MB browser bundle weekly | Low | Weekly cadence, `--no-link`, single `x86_64-linux` package; well within `ubuntu-latest` limits. |

---

## 8. Out of Scope

- Adding a `packages.<system>` flake output (§3.4 rationale).
- Auto-updating `vexos.brave-origin` on any host at runtime — impossible by design on a
  read-only store; the update path is repo commit → pull → `nixos-rebuild switch`.
- Any change to the other in-tree `pkgs/` packages. If this pattern proves out it could
  generalize later, but nothing here is written speculatively for that.
- Bumping the version in this change. The workflow's first run performs the bump; that
  keeps the automation and the version change independently reviewable.
