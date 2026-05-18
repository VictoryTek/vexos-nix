# Phase 6 GitLab Workflow Conversion Spec

Date: 2026-05-18
Feature: stateless_password_security
Target output: `.gitlab-ci.yml` (currently missing)
Spec path: `.github/docs/subagent_docs/stateless_password_security_gitlab_workflow_spec.md`

## 1. Scope And Goal

This spec converts existing GitHub Actions automation into an equivalent GitLab CI design for Phase 6 preflight validation and maintenance workflows.

Primary goals:

1. Preserve CI validation intent from GitHub workflows.
2. Ensure local repo validation minimums are enforced in GitLab CI:
   - `nix flake check`
   - `scripts/preflight.sh` (if present)
3. Handle environments where `sudo` or `nixos-rebuild` are unavailable in CI runners.
4. Provide a practical `.gitlab-ci.yml` sketch that can be implemented directly.

---

## 2. Source Workflows Analyzed

### 2.1 `.github/workflows/ci.yml`

- Trigger rules:
  - `push` to `main`
  - `pull_request` targeting `main`
  - push ignores: `*.md`, `LICENSE`, `.github/docs/**`, `wallpapers/**`, `files/**`
- Concurrency:
  - `group: ${{ github.workflow }}-${{ github.ref }}`
  - `cancel-in-progress: true`
- Permissions:
  - `contents: read`
  - `actions: write`
- Jobs:
  - `lint`
  - `evaluate` (matrix by role/group)

#### Extracted commands and behavior

`lint` job:

1. Checkout repository.
2. Verify `hardware-configuration.nix` is not tracked:
   - `git ls-files hardware-configuration.nix | grep -q .`
3. Verify `system.stateVersion` exists in all `configuration-*.nix` role files:
   - `grep -q 'system\.stateVersion' "$cfg"`

`evaluate` job:

1. Free disk space:
   - `sudo rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL "$AGENT_TOOLSDIRECTORY" || true`
2. Checkout repository.
3. Install Nix (`cachix/install-nix-action@v31`) with `github_access_token`.
4. Cache Nix store (`nix-community/cache-nix-action@v7`) with:
   - primary key: `nix-${{ runner.os }}-${{ matrix.group }}-${{ hashFiles('flake.lock') }}`
   - restore prefix: `nix-${{ runner.os }}-`
   - purge enabled (7-day access window)
5. Create CI stub at `/etc/nixos/hardware-configuration.nix`.
6. Evaluate all matrix configs with timeout:
   - `timeout 8m nix eval --impure ".#nixosConfigurations.${config}.config.system.build.toplevel.drvPath" > /dev/null`

Matrix groups present:

- `desktop`
- `stateless`
- `server`
- `headless-server`
- `htpc`
- `vanilla`

### 2.2 `.github/workflows/gitlab-mirror.yml`

- Trigger rules:
  - `push` to `main`
- Job:
  - `mirror`
- Commands:
  1. Checkout repository with `fetch-depth: 0`.
  2. Add GitLab remote using `secrets.GITLAB_TOKEN`.
  3. Push all branches and tags:
     - `git push gitlab --all`
     - `git push gitlab --tags`

### 2.3 `.github/workflows/update-flake-lock.yml`

- Trigger rules:
  - `push` to `main` (ignores `flake.lock`)
  - scheduled daily (`0 4 * * *`)
  - manual (`workflow_dispatch`)
- Permissions:
  - `contents: write`
- Job:
  - `update-nixpkgs`
- Commands:
  1. Checkout (`fetch-depth: 1`).
  2. Install Nix with `github_access_token`.
  3. `nix flake update`
  4. Detect lock changes:
     - `git diff --quiet flake.lock`
  5. If changed, commit and push:
     - `git add flake.lock`
     - `git commit -m "chore: update flake inputs"`
     - `git push`

---

## 3. Current Workflow Mapping Table (GitHub -> GitLab)

| GitHub workflow/job | Intent | Proposed GitLab stage/job | Notes |
|---|---|---|---|
| `ci.yml` -> `lint` | Fast static guardrails | `lint` -> `lint_static` | Direct command parity |
| `ci.yml` -> `evaluate` (matrix) | Full NixOS config evaluation without build | `validate` -> `evaluate_configs_matrix` | Keep role matrix and timeout loop |
| `ci.yml` (overall) | Validation gate on push/PR main | `validate` -> `nix_flake_check` + `preflight_validation` | Adds explicit Phase 6 minimums |
| `gitlab-mirror.yml` -> `mirror` | Push repo state to GitLab mirror | `maintenance` -> `mirror_to_github` (optional/manual) | In GitLab-native repo, reverse mirror direction only if needed |
| `update-flake-lock.yml` -> `update-nixpkgs` | Scheduled lock refresh + conditional commit | `maintenance` -> `update_flake_lock` | Schedule/manual, token-based push |

---

## 4. Proposed GitLab CI Design

### 4.1 Pipeline stages

1. `lint`
2. `validate`
3. `maintenance`

### 4.2 Pipeline-level rules

Run pipelines on:

1. Merge requests (`merge_request_event`)
2. Pushes to default branch (normally `main`)
3. Scheduled pipelines
4. Manual web-triggered pipelines

### 4.3 Caching/artifacts strategy

Caching:

1. Use lock-file keyed cache for Nix-related caches where runner permits persistence.
2. Keep cache conservative and branch-safe (`prefix` + `flake.lock` key).
3. Do not assume `/nix/store` cache portability across all GitLab runner types.

Artifacts:

1. Persist CI logs from validation jobs for troubleshooting.
2. Keep short retention (for example, 7 days).

### 4.4 Job definitions and exact commands

#### Job: `lint_static` (stage: `lint`)

Exact commands:

```bash
set -euo pipefail

if git ls-files hardware-configuration.nix | grep -q .; then
  echo "FAIL: hardware-configuration.nix must not be tracked in git"
  exit 1
fi
echo "PASS: hardware-configuration.nix is not tracked"

failed=()
for cfg in \
  configuration-desktop.nix \
  configuration-htpc.nix \
  configuration-server.nix \
  configuration-headless-server.nix \
  configuration-stateless.nix \
  configuration-vanilla.nix; do
  if ! grep -q 'system\.stateVersion' "$cfg"; then
    echo "FAIL: system.stateVersion missing from $cfg"
    failed+=("$cfg")
  else
    echo "PASS: system.stateVersion present in $cfg"
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  exit 1
fi
```

#### Job: `nix_flake_check` (stage: `validate`)

Exact commands:

```bash
set -euo pipefail
mkdir -p ci-logs

if [ ! -f /etc/nixos/hardware-configuration.nix ] && [ "$(id -u)" = "0" ]; then
  mkdir -p /etc/nixos
  cat > /etc/nixos/hardware-configuration.nix <<'EOF'
{ lib, ... }:
{
  fileSystems."/" = {
    device = lib.mkDefault "/dev/sda1";
    fsType = lib.mkDefault "ext4";
  };
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
}
EOF
fi

nix flake check --no-build --impure --show-trace | tee ci-logs/nix-flake-check.log
```

#### Job: `preflight_validation` (stage: `validate`)

Exact commands:

```bash
set -euo pipefail
mkdir -p ci-logs

if [ -f scripts/preflight.sh ]; then
  bash scripts/preflight.sh | tee ci-logs/preflight.log
else
  echo "scripts/preflight.sh missing"
  exit 1
fi
```

Compatibility behavior for non-privileged CI:

1. `scripts/preflight.sh` already falls back to `nix build --dry-run` when `sudo`/`nixos-rebuild` are unavailable.
2. This preserves validation intent even in containerized runners.

#### Job: `evaluate_configs_matrix` (stage: `validate`)

Exact commands:

```bash
set -euo pipefail
mkdir -p ci-logs

rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL || true
if [ -n "${AGENT_TOOLSDIRECTORY:-}" ]; then
  rm -rf "${AGENT_TOOLSDIRECTORY}" || true
fi
df -h /

if [ ! -f /etc/nixos/hardware-configuration.nix ] && [ "$(id -u)" = "0" ]; then
  mkdir -p /etc/nixos
  cat > /etc/nixos/hardware-configuration.nix <<'EOF'
{ lib, ... }:
{
  fileSystems."/" = {
    device = lib.mkDefault "/dev/sda1";
    fsType = lib.mkDefault "ext4";
  };
  boot.loader.grub.device = lib.mkDefault "/dev/sda";
}
EOF
fi

failed=()
for config in $CONFIGS; do
  echo "Evaluating ${config}"
  if timeout 8m nix eval --impure \
      ".#nixosConfigurations.${config}.config.system.build.toplevel.drvPath" \
      > /dev/null; then
    echo "PASS: ${config}"
  else
    echo "FAIL: ${config}"
    failed+=("${config}")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
```

#### Job: `update_flake_lock` (stage: `maintenance`)

Exact commands:

```bash
set -euo pipefail

nix flake update

if git diff --quiet flake.lock; then
  echo "All flake inputs are already up to date"
  exit 0
fi

git config user.name  "gitlab-ci[bot]"
git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
git add flake.lock
git commit -m "chore: update flake inputs"
git push "https://oauth2:${GITLAB_PUSH_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "HEAD:${CI_DEFAULT_BRANCH}"
```

Required variable: `GITLAB_PUSH_TOKEN` (masked + protected, API scope sufficient for push).

#### Job: `mirror_to_github` (stage: `maintenance`, optional)

Exact commands:

```bash
set -euo pipefail

git fetch --all --tags
git remote add github-mirror "https://oauth2:${GITHUB_MIRROR_TOKEN}@github.com/VictoryTek/vexos-nix.git"
git push github-mirror --all
git push github-mirror --tags
```

Required variable: `GITHUB_MIRROR_TOKEN` (optional; only if reverse mirroring is required).

---

## 5. Branch/Event Rule Conversion

GitHub -> GitLab equivalence:

1. `push` on `main` -> `if: $CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`
2. `pull_request` on `main` -> `if: $CI_PIPELINE_SOURCE == "merge_request_event"`
3. `schedule` cron -> GitLab pipeline schedules + `if: $CI_PIPELINE_SOURCE == "schedule"`
4. `workflow_dispatch` -> `if: $CI_PIPELINE_SOURCE == "web"` (manual)

Path-ignore note:

GitHub `paths-ignore` does not have a 1:1 workflow-level equivalent in GitLab. Use per-job `rules:changes` to approximate if needed. Initial recommendation is to prioritize correctness and run validation jobs for all push/MR events on `main`/MRs.

---

## 6. Risk And Compatibility Notes (Nix On GitLab Runners)

1. `sudo` may be unavailable on shared runners.
   - Mitigation: rely on existing preflight fallback to `nix build --dry-run`.
2. `/etc/nixos` may not be writable on non-root runners.
   - Mitigation: attempt stub creation only when running as root; keep `--impure` behavior explicit.
3. Nix installation method differs from GitHub Actions.
   - Mitigation: use a Nix-enabled image or install Nix in `before_script`; verify with `nix --version`.
4. Nix cache behavior is not identical to `cache-nix-action`.
   - Mitigation: start with lock-keyed GitLab cache and optional remote binary cache later.
5. Token-based push jobs can fail on protected branches.
   - Mitigation: use protected variables and explicit branch permissions for bot tokens.
6. Shell script line endings can break Linux CI execution.
   - Mitigation: keep `.sh` files LF-only (`*.sh text eol=lf`), especially `scripts/preflight.sh`.

---

## 7. Final Recommended `.gitlab-ci.yml` Content Sketch

```yaml
workflow:
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
    - when: never

stages:
  - lint
  - validate
  - maintenance

default:
  image: nixos/nix:2.24.11
  before_script:
    - set -euo pipefail
    - export NIX_CONFIG="experimental-features = nix-command flakes"
    - if ! command -v git >/dev/null; then nix profile install nixpkgs#git; fi
    - if ! command -v timeout >/dev/null; then nix profile install nixpkgs#coreutils; fi
    - nix --version
  cache:
    key:
      files:
        - flake.lock
      prefix: "nix-${CI_JOB_NAME}"
    paths:
      - .cache/nix
    policy: pull-push

lint_static:
  stage: lint
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - when: never
  script:
    - |
      set -euo pipefail
      if git ls-files hardware-configuration.nix | grep -q .; then
        echo "FAIL: hardware-configuration.nix must not be tracked in git"
        exit 1
      fi
      echo "PASS: hardware-configuration.nix is not tracked"
      failed=()
      for cfg in \
        configuration-desktop.nix \
        configuration-htpc.nix \
        configuration-server.nix \
        configuration-headless-server.nix \
        configuration-stateless.nix \
        configuration-vanilla.nix; do
        if ! grep -q 'system\.stateVersion' "$cfg"; then
          echo "FAIL: system.stateVersion missing from $cfg"
          failed+=("$cfg")
        else
          echo "PASS: system.stateVersion present in $cfg"
        fi
      done
      if [ ${#failed[@]} -gt 0 ]; then
        exit 1
      fi

nix_flake_check:
  stage: validate
  needs: ["lint_static"]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - when: never
  script:
    - mkdir -p ci-logs
    - |
      if [ ! -f /etc/nixos/hardware-configuration.nix ] && [ "$(id -u)" = "0" ]; then
        mkdir -p /etc/nixos
        cat > /etc/nixos/hardware-configuration.nix <<'EOF'
      { lib, ... }:
      {
        fileSystems."/" = {
          device = lib.mkDefault "/dev/sda1";
          fsType = lib.mkDefault "ext4";
        };
        boot.loader.grub.device = lib.mkDefault "/dev/sda";
      }
      EOF
      fi
    - nix flake check --no-build --impure --show-trace | tee ci-logs/nix-flake-check.log
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - ci-logs/nix-flake-check.log

preflight_validation:
  stage: validate
  needs: ["lint_static"]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - when: never
  script:
    - mkdir -p ci-logs
    - test -f scripts/preflight.sh
    - bash scripts/preflight.sh | tee ci-logs/preflight.log
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - ci-logs/preflight.log

evaluate_configs_matrix:
  stage: validate
  needs: ["lint_static"]
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - when: never
  parallel:
    matrix:
      - GROUP: "desktop"
        CONFIGS: "vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-nvidia-legacy535 vexos-desktop-nvidia-legacy470 vexos-desktop-vm vexos-desktop-intel"
      - GROUP: "stateless"
        CONFIGS: "vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-nvidia-legacy535 vexos-stateless-nvidia-legacy470 vexos-stateless-intel vexos-stateless-vm"
      - GROUP: "server"
        CONFIGS: "vexos-server-amd vexos-server-nvidia vexos-server-intel vexos-server-vm"
      - GROUP: "headless-server"
        CONFIGS: "vexos-headless-server-amd vexos-headless-server-nvidia vexos-headless-server-intel vexos-headless-server-vm"
      - GROUP: "htpc"
        CONFIGS: "vexos-htpc-amd vexos-htpc-nvidia vexos-htpc-nvidia-legacy535 vexos-htpc-nvidia-legacy470 vexos-htpc-intel vexos-htpc-vm"
      - GROUP: "vanilla"
        CONFIGS: "vexos-vanilla-amd vexos-vanilla-nvidia vexos-vanilla-intel vexos-vanilla-vm"
  script:
    - mkdir -p ci-logs
    - |
      rm -rf /usr/local/lib/android /usr/share/dotnet /opt/ghc /usr/local/.ghcup /opt/hostedtoolcache/CodeQL || true
      if [ -n "${AGENT_TOOLSDIRECTORY:-}" ]; then
        rm -rf "${AGENT_TOOLSDIRECTORY}" || true
      fi
      df -h /
    - |
      if [ ! -f /etc/nixos/hardware-configuration.nix ] && [ "$(id -u)" = "0" ]; then
        mkdir -p /etc/nixos
        cat > /etc/nixos/hardware-configuration.nix <<'EOF'
      { lib, ... }:
      {
        fileSystems."/" = {
          device = lib.mkDefault "/dev/sda1";
          fsType = lib.mkDefault "ext4";
        };
        boot.loader.grub.device = lib.mkDefault "/dev/sda";
      }
      EOF
      fi
    - |
      failed=()
      for config in $CONFIGS; do
        if timeout 8m nix eval --impure ".#nixosConfigurations.${config}.config.system.build.toplevel.drvPath" > /dev/null; then
          echo "PASS: ${config}"
        else
          echo "FAIL: ${config}"
          failed+=("${config}")
        fi
      done
      if [ ${#failed[@]} -gt 0 ]; then
        echo "Failed: ${failed[*]}"
        exit 1
      fi

update_flake_lock:
  stage: maintenance
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
      when: manual
    - when: never
  script:
    - nix flake update
    - |
      if git diff --quiet flake.lock; then
        echo "All flake inputs are already up to date"
        exit 0
      fi
    - git config user.name "gitlab-ci[bot]"
    - git config user.email "gitlab-ci[bot]@users.noreply.gitlab.com"
    - git add flake.lock
    - git commit -m "chore: update flake inputs"
    - git push "https://oauth2:${GITLAB_PUSH_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "HEAD:${CI_DEFAULT_BRANCH}"

mirror_to_github:
  stage: maintenance
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: manual
    - when: never
  allow_failure: true
  script:
    - git fetch --all --tags
    - git remote add github-mirror "https://oauth2:${GITHUB_MIRROR_TOKEN}@github.com/VictoryTek/vexos-nix.git"
    - git push github-mirror --all
    - git push github-mirror --tags
```

---

## 8. Acceptance Criteria For Implementation Phase

1. A new `.gitlab-ci.yml` is created from this sketch.
2. Pipeline includes `nix_flake_check` and `preflight_validation` jobs at minimum.
3. Validation jobs run for MRs and pushes to default branch.
4. Scheduled/manual lock-update behavior is implemented.
5. Token-dependent jobs (`update_flake_lock`, optional mirror) are guarded by rules and documented variables.
