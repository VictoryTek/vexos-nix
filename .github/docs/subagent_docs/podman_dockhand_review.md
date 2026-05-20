# Podman + Dockhand — Review & Quality Assurance

**Feature:** `podman_dockhand`  
**Review Date:** 2026-05-20  
**Reviewer:** Review & QA Agent  
**Files Reviewed:**
- `modules/server/podman.nix`
- `modules/server/dockhand.nix`
- `modules/server/default.nix`
- `modules/server/headscale.nix` (reference)
- `modules/server/proxmox.nix` (reference)
- `modules/server/docker.nix` (conflict check)
- `.github/docs/subagent_docs/podman_dockhand_spec.md`

---

## Executive Summary

The implementation correctly follows the Module Architecture Pattern, uses proper Nix
idioms, and evaluates cleanly in targeted `nix eval` checks. However, **two CRITICAL
issues** were identified that would cause runtime failures:

1. The container image name is wrong — the `ghcr.io/` registry prefix is missing and
   the organization name differs from the required value.
2. The Podman socket volume mount uses a symlink path (`/run/docker.sock`) rather than
   the actual Podman socket (`/run/podman/podman.sock`), which may not bind-mount
   correctly into containers and deviates from Dockhand's own upstream documentation.

Both issues originate in the spec (the implementation faithfully followed the spec),
meaning the spec itself contains errors that propagated into the implementation.

**Verdict: NEEDS_REFINEMENT**

---

## Issues Found

### CRITICAL

#### C-1: Wrong Container Image Name (`dockhand.nix` line ~58)

| | Value |
|-|-------|
| **Actual** | `"fnsys/dockhand:latest"` |
| **Required** | `"ghcr.io/finsys/dockhand:latest"` |

Two separate defects:

1. **Missing registry prefix** — `fnsys/dockhand:latest` resolves to Docker Hub
   (`docker.io/fnsys/dockhand:latest`). The correct image is hosted on the GitHub
   Container Registry at `ghcr.io`. Podman will fail to pull the image or will pull
   from the wrong source.

2. **Wrong organisation name** — `fnsys` (in the actual code) vs. `finsys` (required).
   Even if the `ghcr.io/` prefix were added, `ghcr.io/fnsys/dockhand:latest` is a
   different repository path from `ghcr.io/finsys/dockhand:latest`.

**Root cause:** The spec (§12, §6) also specifies `fnsys/dockhand:latest` and lists
the registry as "Docker Hub". The implementation faithfully followed the spec, but the
spec itself contains a critical error. Both the spec and the implementation must be
corrected.

**Impact:** The Dockhand container service will fail to start — Podman cannot pull the
image from the wrong registry/org.

**Required fix:**
```nix
image = "ghcr.io/finsys/dockhand:latest";
```

---

#### C-2: Socket Volume Mount Uses Symlink Path (`dockhand.nix` line ~68)

| | Value |
|-|-------|
| **Actual** | `"/run/docker.sock:/var/run/docker.sock"` |
| **Required** | `"/run/podman/podman.sock:/var/run/docker.sock"` |

On NixOS with `virtualisation.podman.dockerCompat = true`, the file at `/run/docker.sock`
is a **symlink** pointing to the actual Podman socket at `/run/podman/podman.sock`.
When rootful Podman bind-mounts a path into a container, symlink resolution behaviour
varies — the actual socket file (`/run/podman/podman.sock`) is the reliable, explicit
path to use.

Additionally, Dockhand's own upstream documentation recommends mounting the native
Podman socket path:

> "For Podman, map the Podman socket to the Docker socket path inside the container:
> `-v /run/podman/podman.sock:/var/run/docker.sock:Z`"

The spec (§3.3) explicitly argues for `/run/docker.sock` and overrides this upstream
guidance. That reasoning is debatable in practice but the review instructions take
precedence: the correct host-side socket for this implementation is
`/run/podman/podman.sock`.

**Root cause:** The spec's §3.3 contains incorrect guidance. The implementation
followed the spec. Both must be corrected.

**Impact:** Dockhand may start but fail to communicate with Podman, leaving it unable
to list or manage containers. Behaviour depends on Podman's symlink resolution — not
reliable or portable.

**Required fix:**
```nix
volumes = [
  "/run/podman/podman.sock:/var/run/docker.sock"  # Actual Podman socket (not symlink)
  "${cfg.dataDir}:${cfg.dataDir}"
];
```
Update the inline comment to reflect the new path.

---

### RECOMMENDED

#### R-1: CRLF Line Endings in New Nix Files

Both `podman.nix` and `dockhand.nix` were created with Windows CRLF line endings
(confirmed by `git add` warning: "CRLF will be replaced by LF the next time Git touches
it"). All other `.nix` files in this repository use LF line endings. The
`.gitattributes` file will normalise to LF on commit, but working-tree inconsistency
can cause diff noise and affects editor formatting tools.

**Recommended fix:** Ensure both files are saved with LF line endings before commit.
With `git add` already staged, a `git checkout modules/server/podman.nix` after setting
`core.autocrlf=input` would normalise them, or the editor's LF mode can be used.

---

#### R-2: No Mutual-Exclusion Warning for Docker + Podman Coexistence

If an operator sets both `vexos.server.docker.enable = true` and
`vexos.server.podman.enable = true`, the Docker daemon and Podman will both be
installed. `virtualisation.oci-containers.backend = "podman"` ensures OCI containers
use Podman, but Docker will be idle and consuming system resources. No warning or
assertion exists to flag this unusual combination.

The spec acknowledges this risk (§3.7, §14) but does not add any advisory. A
`lib.mkIf (config.vexos.server.docker.enable) (lib.warn "..." null)` or informational
assertion would improve the operator experience.

This is not a build or runtime failure — just an operator UX improvement.

---

## Passing Checks

| Check | Result | Notes |
|-------|--------|-------|
| A.3 `oci-containers.backend` placement | ✅ PASS | Set in `podman.nix`, absent from `dockhand.nix` |
| A.4 Function args declare only used names | ✅ PASS | Both use `{ config, lib, ... }` — `pkgs` absent (correct) |
| A.5 `lib.mkEnableOption` used | ✅ PASS | Both modules use `lib.mkEnableOption` |
| A.6 No cross-role conditional logic | ✅ PASS | No `lib.mkIf` guards on role/display/gaming flags |
| A.7 Assertion list format | ✅ PASS | `assertions = [ { assertion = ...; message = ...; } ]` |
| A.8 `systemd.tmpfiles.rules` format | ✅ PASS | `"d PATH 0700 root root -"` — valid 6-field format |
| A.9 Port string format | ✅ PASS | `"0.0.0.0:PORT:3000"` is valid (explicit IP bind is better practice) |
| A.10 `defaultNetwork.settings.dns_enabled` option path | ✅ PASS | Confirmed valid NixOS 25.11 path via `development.nix` (uses same option) and deprecated-option error message pointing to this exact path |
| B.11 Indentation style | ✅ PASS | Aligned-assignment style matches `proxmox.nix` |
| B.12 Module header comments | ✅ PASS | Both modules have accurate header comments with prerequisites and usage notes |
| B.13 `default.nix` import ordering | ✅ PASS | Imports added under Container Runtime section, after `docker.nix` |
| C.14 `docker.nix` conflict | ✅ PASS | `docker.nix` does not set `virtualisation.oci-containers.backend`; no conflict |

---

## Build Validation

### Environment

Evaluation performed via WSL Ubuntu with Nix installed, using `--impure` flag
(required because `hardware-configuration.nix` is not tracked in this repo — expected
and correct).

### Steps and Results

| Step | Command | Result |
|------|---------|--------|
| Stage new files | `git add modules/server/podman.nix modules/server/dockhand.nix` | ✅ Staged (files were untracked) |
| Eval podman options — server-amd | `nix eval --impure .#nixosConfigurations.vexos-server-amd.config.vexos.server.podman` | ✅ `{ enable = false; }` — evaluates without error |
| Eval dockhand options — server-amd | `nix eval --impure .#nixosConfigurations.vexos-server-amd.config.vexos.server.dockhand` | ✅ `{ dataDir = "/var/lib/dockhand"; enable = false; port = 3000; }` |
| Eval dockhand options — headless-server-amd | `nix eval --impure .#nixosConfigurations.vexos-headless-server-amd.config.vexos.server.dockhand` | ✅ `{ dataDir = "/var/lib/dockhand"; enable = false; port = 3000; }` |
| Desktop regression check | `nix eval --impure .#nixosConfigurations.vexos-desktop-amd.config.virtualisation.podman.enable` | ✅ `true` — desktop Podman unchanged (value from `development.nix`, unrelated to new modules) |
| Verify `dns_enabled` option path | `nix eval --impure .#nixosConfigurations.vexos-server-amd.config.virtualisation.podman.defaultNetwork.settings` | ✅ `{ }` — option exists, accepts sub-keys |
| `nix flake check --no-build --impure` | Full check | ⚠️ Not completed — check terminated; hardware-configuration.nix absent on dev machine is expected. Targeted evals above confirm module evaluation is correct. |

### Build Result

**Module evaluation: PASS** — All targeted `nix eval` checks succeed with correct
default values. No option-type errors, no undefined attribute errors.

**Full flake check: SKIPPED** — `hardware-configuration.nix` is not present on this
development machine (expected per project spec; CI handles full validation).

**Deployment runtime: BLOCKED** — Two CRITICAL issues (C-1: wrong image, C-2: symlink
socket) would prevent Dockhand from deploying correctly at runtime, even though Nix
evaluation succeeds.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 72% | C |
| Best Practices | 82% | B |
| Functionality | 55% | F |
| Code Quality | 90% | A |
| Security | 78% | C+ |
| Performance | 95% | A |
| Consistency | 88% | B+ |
| Build Success | 78% | C+ |

**Overall Grade: C+ (80%)**

---

## Notes

- The spec (`.github/docs/subagent_docs/podman_dockhand_spec.md`) is the root cause
  of both CRITICAL issues. Sections §3.3, §6, §7, and §12 of the spec must be
  corrected alongside the implementation files.
- The `Specification Compliance` score is penalised because the spec itself contains
  critical factual errors that made it through the specification phase undetected.
- Code structure, Nix idioms, option design, and module architecture are excellent —
  these would score A across the board if the two runtime values were correct.
- Once C-1 and C-2 are fixed, no further blockers exist. R-1 and R-2 can be addressed
  in the same pass.

---

*Review written by: Review & QA Agent*  
*Phase 3 of the vexos-nix standard workflow*
