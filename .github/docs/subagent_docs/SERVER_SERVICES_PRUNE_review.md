# SERVER_SERVICES_PRUNE — Review

Phase 3 output. Reviews the implementation against
`.github/docs/subagent_docs/SERVER_SERVICES_PRUNE_spec.md`.

---

## 1. Files Changed

| File | Status | Purpose |
|------|--------|---------|
| `lib/server-service-names.nix` | new | Derives the service names from option declarations |
| `pkgs/vexos-prune-services/default.nix` | new | The tool; bakes the list in at build time |
| `pkgs/vexos-prune-services/prune.awk` | new | Statement-aware filter for the flat form |
| `flake.nix` | modified | `packages.…vexos-prune-services`, `apps.…prune-services` |
| `pkgs/vexos-update/default.nix` | modified | Pre-evaluation check + dry-build failure hint |
| `justfile` | modified | `prune-services` recipe |
| `scripts/preflight.sh` | modified | Renumbered to /10; new CHECK 10 |

`pkgs/default.nix` and `modules/` are untouched.

---

## 2. Specification Compliance

| Spec requirement | Status |
|---|---|
| 2.1 No bookkeeping edit when a service is removed | Met — list derived from declarations |
| 2.2 Host told exactly which entries are dead | Met — named, with `enable = true` called out |
| 2.3 Removable with one command | Met — `just prune-services` |
| 2.4 Nothing rewrites a host file unasked | Met — `vexos-update` uses `--check` only |
| 2.5 Works on a host with stale tooling | Met — flake app run from GitHub, no rebuild |
| 4.3.A modes, exit codes 0/1/2/3 | Met — all four verified |
| 4.3.B flake app output | Met |
| 4.3.C pre-evaluation check in `vexos-update` | Met, with a correction (§5.1) |
| 4.3.D justfile recipe | Met, with a correction (§5.2) |
| 4.3.E preflight stage | Met |
| 4.4 parsing rules | Met — flat form, comments preserved, nested refused, `.bak` written |
| 4.5 stops rather than auto-prunes | Met |

---

## 3. Build and Test Results

All executed under WSL Ubuntu, Nix 2.34.1, 2026-09-25.

### 3.1 Tool behaviour

| Case | Expected | Actual |
|---|---|---|
| Clean file | exit 0 | exit 0 |
| `template/server-services.nix` (dozens of commented entries) | exit 0, untouched | exit 0 |
| Nested `vexos.server = { … }` | exit 2, refuse | exit 2 |
| Missing file | exit 0 | exit 0 |
| Unknown flag | exit 3 | exit 3 |
| Dead entries, `--check` | exit 1, names listed | exit 1 |
| Dead entries, `--apply` | exit 0, removed, `.bak` | exit 0 |
| Re-run after `--apply` | exit 0 | exit 0 (idempotent) |

The `--apply` fixture mixed single-line, multi-line block, trailing-comment, and
commented-out entries alongside valid ones including `arr.sonarr` and
`kernelBuilder`. Result: the three dead entries (`home-assistant`, `grafana`
multi-line block, `minio` with inline comment) removed; the commented
`# vexos.server.grafana.enable = false;` line and all valid entries preserved.

### 3.2 Derivation

`58` names baked into the built tool, matching the spec's expected set,
including the irregular `kernelBuilder`, `nasSync`, `nas`, `storage`, `backup`,
`proxy`.

### 3.3 Integration

- `nix run path:.#prune-services -- --help` / `-- --check <file>` both correct.
- `nix flake show --impure path:.` lists `apps.x86_64-linux.prune-services` and
  `packages.x86_64-linux.vexos-prune-services`.
- `pkgs/vexos-update` builds, so its `writeShellApplication` shellcheck passes —
  rebuilt and re-verified after the §5.1 fix.
- `justfile` parses (`just --dump`, exit 0); `prune-services` present.
- jq revision extraction verified against synthetic `flake metadata --json`:
  returns the rev in the normal case; returns empty on a missing input and on
  malformed JSON, which routes to the non-fatal skip branch.

### 3.4 Lint and format

- `shellcheck -S warning scripts/preflight.sh` — clean.
- `nixpkgs-fmt --check` on both new `.nix` files — `0 / 2 would be reformatted`.

---

## 4. Build Validation Against CLAUDE.md Phase 3

| Required step | Result |
|---|---|
| `nix flake show --impure` | **Blocked** — see §6.1 |
| `nixos-rebuild dry-build` ×3 desktop variants | **Not possible** — see §6.2 |
| server / headless-server dry-builds | **Not possible** — see §6.2 |
| `hardware-configuration.nix` not tracked | Pass — `git ls-files` empty |
| `system.stateVersion` unchanged | Pass — all six files, preflight CHECK 4 |
| New flake inputs declare `follows` | N/A — no inputs added |

---

## 5. Issues Found and Fixed During Review

### 5.1 CRITICAL (fixed) — a missing app would have blocked every update

The first implementation treated any non-zero exit from `nix run` as "dead
entries found" and aborted the update. `nix run` also exits 1 when the flake
does not provide the app — which is the case for every revision predating this
change — and on network failure. A host could have been blocked from updating
by the check meant to unblock it.

Fixed: the abort path now requires exit code 1 **and** the tool's own wording in
the output. Every other outcome warns and continues, leaving the dry-build as
the backstop. Verified by rebuilding the package (shellcheck) after the change.

### 5.2 CRITICAL (fixed) — pruning against the restored lock would deadlock

`just prune-services` must not use the host's locked revision. When
`vexos-update` stops, it restores `flake.lock` to the **old** revision, which
still declares the removed service. Pruning against that would report the file
clean, leave the entry in place, and fail the next update identically — an
unbreakable loop.

The recipe uses `github:VictoryTek/vexos-nix#prune-services` (main) deliberately.
This differs from the `vexos-update` call site, which correctly uses the locked
revision because at that point the lock still holds the new one. Both call sites
now carry comments explaining why they differ, since the inconsistency looks
like a mistake.

### 5.3 Note (no change) — empty-list protection is layered

An empty derived list would mark every entry dead. Three independent guards:
the tool refuses to run on an empty `VALID`; preflight CHECK 10 fails on a
zero count; `--apply` always writes `.bak`.

---

## 6. Outstanding — Cannot Be Verified On This Workstation

### 6.1 Full preflight run is blocked by untracked files

`bash scripts/preflight.sh` currently **fails at CHECK 1**, which triggers its
early-exit at line 232 and skips CHECKS 5–10.

Cause: `nix flake show` resolves `.` as a `git+file://` ref, which cannot see
untracked files. `lib/` and `pkgs/vexos-prune-services/` are new and unstaged.
The same command against `path:.` succeeds and lists both new outputs.

This is not a defect in the change. It resolves once the new files are staged.
Per CLAUDE.md, staging is the user's operation, so **preflight has not been
observed exiting 0** and this review cannot claim it does. The skipped stages
were instead run individually (§3.3, §3.4) and all pass.

### 6.2 No `nixos-rebuild dry-build`

Requires a NixOS host with `/etc/nixos/vexos-variant`. This is a Windows
workstation validating through WSL. Preflight CHECK 2 reports SKIP here.

Mitigating factor: no NixOS module is added or changed, and
`modules/server/default.nix` is untouched, so the system closure is unaffected
by design. The changed Nix code is confined to flake outputs and two packages,
all of which build.

### 6.3 End-to-end on-host flow is unexercised

The sequence — `just update` stops → `just prune-services` → `just update`
succeeds — has not been run against a real `/etc/nixos`. Its components are
verified individually, but their composition is not. First real execution will
be on the user's `vexos-headless-server-intel`.

### 6.4 `nix run` against a real GitHub revision

Tested only via `path:` and local store refs. The GitHub fetch path in
`vexos-update` cannot be exercised until the change is pushed.

---

## 7. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 95% | A |
| Consistency | 100% | A |
| Build Success | 70% | C |

**Overall Grade: A− (91%)**

Build Success is marked down for §6.1 and §6.2: the mandated
`nix flake show --impure` and `nixos-rebuild dry-build` steps did not run to
completion in their required form. Everything that could be built here was
built, including both packages and the shellcheck gates.

Security: no secrets, no credentials, no network callbacks beyond the existing
flake fetch. `--apply` writes only `server-services.nix` and its `.bak`, and
`*.bak` is already in `/etc/nixos/.gitignore`, so a backup cannot leak into the
world-readable Nix store.

Performance: the pre-evaluation check adds one small options-only evaluation and
a tiny `writeShellApplication` build per update. No NixOS evaluation, and the
revision is already fetched by the preceding `nix flake update`.

---

## 8. Verdict

**PASS, conditional on §6.1.**

Both CRITICAL issues found during review were fixed and re-verified. No
unresolved findings.

The condition is procedural, not a defect: the new files must be staged before
`nix flake show` — and therefore full preflight and CI — can see them. Phase 6
must be re-run after staging, and the result must not be reported as passing
until it has been observed exiting 0.
