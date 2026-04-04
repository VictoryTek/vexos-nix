# Spec: Automated nixpkgs Flake Lock Update (GitHub Actions)

**Feature:** `flake_lock_autoupdate`  
**Date:** 2026-04-04  
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

### 1.1 Repository Structure

| Path | Description |
|------|-------------|
| `flake.nix` | Root flake — defines 5 inputs and 4 `nixosConfigurations` outputs |
| `flake.lock` | Lock file — tracked in git, current as of 2026-04-01 (nixpkgs `bcd464c`) |
| `.github/workflows/gitlab-mirror.yml` | Existing workflow: mirrors `main` pushes to GitLab via `GITLAB_TOKEN` |
| `scripts/preflight.sh` | Local validation script — requires `hardware-configuration.nix` at `/etc/nixos/` |
| `.github/docs/subagent_docs/` | Subagent documentation directory |

### 1.2 Flake Inputs

| Input | URL | `follows` |
|-------|-----|-----------|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-25.11` | — (root input) |
| `nixpkgs-unstable` | `github:NixOS/nixpkgs/nixos-unstable` | none (intentional — pinned to unstable independently) |
| `nix-gaming` | `github:fufexan/nix-gaming` | `inputs.nixpkgs.follows = "nixpkgs"` |
| `home-manager` | `github:nix-community/home-manager/release-25.11` | `inputs.nixpkgs.follows = "nixpkgs"` |
| `up` | `github:VictoryTek/Up` | `inputs.nixpkgs.follows = "nixpkgs"` |

### 1.3 Current flake.lock State

The lock file is version 7 format. The `nixpkgs` entry was last updated on
2026-04-01 (rev `bcd464c`). `nix-gaming`, `home-manager`, and `up` all resolve
their internal nixpkgs reference through the root `nixpkgs` via the `follows`
mechanism — they do not carry separate nixpkgs lock entries. `nixpkgs-unstable`
is locked independently.

### 1.4 Existing CI/CD

- **`gitlab-mirror.yml`** — triggers on `push` to `main`, pushes all branches
  and tags to GitLab using a `GITLAB_TOKEN` secret. This workflow **will also
  run** when the auto-update workflow pushes its commit to `main` — this is
  desired behaviour (the updated lock file will be mirrored to GitLab
  automatically).

### 1.5 What is Missing

No automated mechanism exists to keep `flake.lock` up to date. The lock is
currently refreshed manually (`nix flake update nixpkgs`). The preflight
script warns when the lock is older than 30 days; this task automates the
refresh so that warning never fires in normal operation.

---

## 2. Problem Definition

`nixpkgs` receives security patches and package updates continuously. Without
periodic lock file refreshes the installed system accumulates CVEs and drifts
from upstream. Manual updates are easy to forget. A low-risk automated weekly
refresh is the standard solution for personal configuration repositories.

---

## 3. Proposed Solution Architecture

### 3.1 Trigger

- `on: schedule` with a weekly cron expression (every Monday 04:00 UTC).
- `on: workflow_dispatch` to allow on-demand manual runs.

### 3.2 Runner

`ubuntu-latest` (GitHub-hosted). No self-hosted runner is required or desired.

### 3.3 Nix Setup

Use `cachix/install-nix-action@v31` (latest stable release as of 2026-04). Key
properties:

- Enables `nix-command` and `flakes` experimental features **by default** — no
  `extra_nix_config` override needed.
- Passes `github_access_token: ${{ secrets.GITHUB_TOKEN }}` to avoid GitHub
  API rate-limit errors when resolving flake inputs.
- Fast (~4 s setup on Linux).

### 3.4 Update Command

```
nix flake update nixpkgs
```

This updates **only** the `nixpkgs` node in `flake.lock`. Because `nix-gaming`,
`home-manager`, and `up` declare `inputs.nixpkgs.follows = "nixpkgs"`, they
automatically resolve against the newly pinned nixpkgs without requiring
separate update commands. `nixpkgs-unstable` is intentionally left untouched
(it is tracked independently and should not be silently advanced on a schedule).

### 3.5 Change Detection

After `nix flake update nixpkgs` completes, check whether `flake.lock` was
actually modified:

```bash
git diff --quiet flake.lock
```

- Exit code `0` → no change → skip commit/push, annotate the run as a no-op.
- Exit code `1` → changed → proceed to commit.

This prevents empty commits when nixpkgs has not received any new commits since
the last update.

### 3.6 Commit Strategy

No pull request. Commit directly to `main`. Rationale: this is a personal
configuration repository; merge overhead adds no value and would require human
review for a fully automated, safe operation.

Commit identity: use the `github-actions[bot]` bot account (canonical email
`41898282+github-actions[bot]@users.noreply.github.com`) so provenance is
clear in `git log`.

Commit message:

```
chore: update nixpkgs flake input
```

### 3.7 GITHUB_TOKEN Permissions

Set `permissions: contents: write` at the job level. This overrides the
repository's default read-only token permission without requiring a global
repository settings change.

No `secrets.GITHUB_TOKEN` declaration is needed in the workflow — it is
injected automatically. Only the `permissions` block is required to enable
write access.

### 3.8 Interaction with `gitlab-mirror.yml`

When this workflow pushes to `main`, `gitlab-mirror.yml` will trigger (since it
listens on `push` to `main`). This is correct and desired — the updated
`flake.lock` is mirrored to GitLab automatically. No action is required.

---

## 4. Exact Workflow YAML

**Target path:** `.github/workflows/flake-lock-update.yml`

```yaml
name: Update nixpkgs flake input

on:
  schedule:
    - cron: '0 4 * * 1'   # Every Monday at 04:00 UTC
  workflow_dispatch:        # Allow manual trigger for testing and ad-hoc updates

permissions:
  contents: write           # Required to commit and push flake.lock back to main

jobs:
  update-nixpkgs:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          # GITHUB_TOKEN is used automatically via the workflow permissions block.
          # fetch-depth 1 is sufficient — we only need the working tree for the
          # update command and a single commit.
          fetch-depth: 1

      - name: Install Nix
        uses: cachix/install-nix-action@v31
        with:
          # Passes GITHUB_TOKEN to the Nix daemon to avoid API rate limits when
          # fetching flake inputs from GitHub (nixpkgs, nix-gaming, etc.).
          github_access_token: ${{ secrets.GITHUB_TOKEN }}

      - name: Update nixpkgs input
        run: nix flake update nixpkgs

      - name: Check if flake.lock changed
        id: diff
        run: |
          if git diff --quiet flake.lock; then
            echo "changed=false" >> "$GITHUB_OUTPUT"
            echo "nixpkgs is already up to date — nothing to commit."
          else
            echo "changed=true" >> "$GITHUB_OUTPUT"
            echo "flake.lock has been updated."
          fi

      - name: Commit and push updated flake.lock
        if: steps.diff.outputs.changed == 'true'
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add flake.lock
          git commit -m "chore: update nixpkgs flake input"
          git push
```

---

## 5. GitHub Repository Settings Required

### 5.1 Workflow Write Permissions (REQUIRED)

The `permissions: contents: write` declaration in the workflow YAML is
sufficient for GitHub-hosted runners when the repository's **Actions →
Workflow permissions** is set to either:

- **"Read and write permissions"** (allows the workflow-level override), OR
- The default **"Read repository contents and packages permissions"** with
  individual workflow permission overrides allowed (the default setting).

If the repository owner has globally restricted to read-only with **no
permission overrides allowed**, the `permissions: contents: write` block will
be silently downgraded. In that case, navigate to:

> Settings → Actions → General → Workflow permissions

and select **"Read and write permissions"**, or enable **"Allow GitHub Actions
to create and approve pull requests"** for the commit path.

### 5.2 Branch Protection (VERIFY)

If a branch protection rule exists on `main` that requires pull requests before
merging, the `github-actions[bot]` push will be blocked. For a personal config
repository it is recommended to **not** require PRs on `main`, or to add
`github-actions[bot]` as a bypass actor in the branch protection rule.

### 5.3 No Additional Secrets Required

The workflow uses only `secrets.GITHUB_TOKEN` (auto-injected). No new repository
secrets need to be created. The existing `GITLAB_TOKEN` secret used by
`gitlab-mirror.yml` is unrelated to this workflow.

---

## 6. Risks and Mitigations

### 6.1 Infinite Loop Prevention

| Scenario | Risk | Status |
|----------|------|--------|
| Auto-update commits to `main` → triggers itself again | Loop | **Not possible.** The workflow triggers on `schedule` only (not on `push`). Commits made by `GITHUB_TOKEN` do not re-trigger scheduled workflows. |
| Auto-update commits to `main` → triggers `gitlab-mirror.yml` | Expected side effect | **Desired.** GitLab mirror stays in sync. |

### 6.2 nixpkgs-unstable Not Updated

Scope is intentionally limited to `nix flake update nixpkgs`. `nixpkgs-unstable`
is not updated. Rationale: silently advancing the unstable channel on a schedule
could introduce breaking changes in GNOME application packages (the overlay in
`modules/gnome.nix`) without the user's awareness. A separate, explicit update
command remains the appropriate path for `nixpkgs-unstable`.

### 6.3 No CI Build Validation

The workflow does **not** run `nixos-rebuild dry-build` or `nix flake check`
after the update. Rationale:

- GitHub-hosted runners do not have `/etc/nixos/hardware-configuration.nix`,
  causing all NixOS-specific evaluation to fail with a missing file error.
- Building NixOS system closures in CI requires substantial compute time and
  binary cache infrastructure not currently set up.
- Advancing `nixpkgs` within the same channel (`nixos-25.11`) carries
  negligible breakage risk — it is patching within a stable release series.

Build validation happens when the user applies the update on the actual host
via `sudo nixos-rebuild switch --flake .#vexos-amd` (or the relevant variant).
The preflight script's `dry-build` step also validates the closure when run
locally before pushing.

### 6.4 Empty Commits

The `git diff --quiet flake.lock` guard eliminates empty commits. If nixpkgs
has not received any new commits since the last run (e.g., the lock is already
at the latest revision), the workflow exits cleanly with no commit.

### 6.5 Flake Lock Format Compatibility

`nix flake update nixpkgs` in the CI environment may use a different Nix
version than the developer's local machine. The lock file format (v7) is stable
and backward-compatible across Nix versions ≥ 2.4. The `install-nix-action`
installs the latest Nix release, which uses format v7 — identical to the
existing lock file format. No compatibility risk.

### 6.6 Rate Limiting

The `github_access_token` input passes `GITHUB_TOKEN` to the Nix daemon, which
uses it when fetching flake inputs from GitHub. This prevents unauthenticated
API calls (60 req/h) from being exhausted during input resolution and is
standard practice for Nix CI.

---

## 7. Implementation Steps

1. Create `.github/workflows/flake-lock-update.yml` with the exact YAML from
   Section 4.
2. Verify the repository's Actions workflow permission setting (Section 5.1).
3. Confirm no branch protection rule blocks bot pushes to `main` (Section 5.2).
4. Trigger `workflow_dispatch` manually once to validate end-to-end flow before
   relying on the weekly schedule.

---

## 8. Summary of Findings

- `cachix/install-nix-action@v31` is the current stable release. Flakes and
  `nix-command` are enabled by default — no `extra_nix_config` required.
- Native git commit/push (no third-party commit action) is preferred for
  simplicity and transparency.
- `permissions: contents: write` in the workflow YAML is sufficient to push
  back to `main` without global repository settings changes (assuming the
  default Actions permission configuration).
- Updating only `nixpkgs` is safe and correct: all inputs that `follows =
  "nixpkgs"` inherit the new pin automatically; `nixpkgs-unstable` is left
  untouched by design.
- The change-detection guard (`git diff --quiet flake.lock`) prevents empty
  commits on no-op runs.
- No infinite loop risk: the workflow is scheduled, not push-triggered; commits
  by `GITHUB_TOKEN` do not trigger further scheduled runs.
- The existing `gitlab-mirror.yml` will fire when the update is pushed,
  appropriately keeping the GitLab mirror current.

---

## 9. Sources Consulted

1. `cachix/install-nix-action` README and release notes — v31.10.3 (latest);
   confirmed default flakes support, `github_access_token` usage pattern.
2. GitHub Actions documentation — `on: schedule` cron syntax and
   `permissions: contents: write` job-level permission override.
3. GitHub Actions documentation — `GITHUB_TOKEN` and push behaviour: commits
   pushed by `GITHUB_TOKEN` do NOT re-trigger workflows, preventing loops.
4. Current `flake.nix` — confirmed 5 inputs, 4 outputs, `follows` structure.
5. Current `flake.lock` — confirmed format v7, current nixpkgs rev `bcd464c`.
6. Existing `gitlab-mirror.yml` — confirmed push-to-main trigger; mirroring
   after auto-update is correct and expected.
7. `scripts/preflight.sh` — confirmed `nix flake check --impure` requires
   `/etc/nixos/hardware-configuration.nix`; justifies skipping CI validation.
8. NixOS Flakes reference — `nix flake update <input>` updates a single named
   input; `follows` inputs resolve transitively at evaluation time, not in the
   lock entry, so they benefit automatically from the nixpkgs update.
